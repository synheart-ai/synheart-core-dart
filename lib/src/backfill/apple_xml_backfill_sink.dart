// SPDX-License-Identifier: Apache-2.0
//
// Production `AppleXmlIngestSink` implementation that bridges into
// the native runtime via FFI.
//
// `synheart-wear-flutter` defines the `AppleXmlIngestSink` abstract
// class and an in-memory `RecordingIngestSink` for tests; this file
// supplies the runtime-backed sink for production. We re-implement
// the abstract surface inline so this package doesn't have to take a
// runtime dep on `synheart_wear` — keeps the FFI layer
// independently usable.

import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../core_runtime/ffi_bindings.dart';

/// Result of a sink batch insert. Mirrors the same-named types in
/// `synheart_wear`'s `apple_health_xml_import.dart`.
class BackfillBatchResult {
  const BackfillBatchResult({
    required this.inserted,
    required this.skippedAsDuplicate,
  });
  final int inserted;
  final int skippedAsDuplicate;
}

/// Result of a complete import session.
class BackfillImportResult {
  const BackfillImportResult({
    required this.importId,
    required this.totalSamples,
    required this.inserted,
    required this.skippedAsDuplicate,
    required this.durationMs,
  });
  final String importId;
  final int totalSamples;
  final int inserted;
  final int skippedAsDuplicate;
  final int durationMs;
}

/// Errors thrown by the runtime-backed sink.
sealed class BackfillSinkError implements Exception {
  const BackfillSinkError(this.message);
  final String message;
  @override
  String toString() => 'BackfillSinkError: $message';
}

class BackfillRuntimeUnavailable extends BackfillSinkError {
  const BackfillRuntimeUnavailable()
    : super(
        'runtime backfill symbols not present (need native runtime 5.4.0+)',
      );
}

class BackfillOpenFailed extends BackfillSinkError {
  const BackfillOpenFailed(super.message);
}

class BackfillBatchFailed extends BackfillSinkError {
  const BackfillBatchFailed(super.message);
}

class BackfillFinalizeFailed extends BackfillSinkError {
  const BackfillFinalizeFailed(super.message);
}

/// Bridges `AppleXmlIngestSink` calls into the runtime FFI.
///
/// Use this in production by wiring the synheart-wear orchestrator's
/// sink slot to an instance of [AppleXmlBackfillSink], so:
///
///     final sink = AppleXmlBackfillSink(ffi: ffi, dbPath: path);
///     final importer = AppleHealthXmlImport(
///       xmlBytes: file.openRead(),
///       sink: sink.asWearSink(),
///       importId: importId,
///     );
///     await importer.parse();
///
/// Memory: each `insertBatch` takes a List of samples that have
/// already been parsed by the wear-side parser. The sink JSON-encodes
/// the list, hands it to the runtime, and frees the response. No
/// caching at this layer — the runtime SQLite is the source of truth.
class AppleXmlBackfillSink {
  AppleXmlBackfillSink({required SynheartCoreFFI? ffi, required this.dbPath})
    : _ffi = ffi;

  final SynheartCoreFFI? _ffi;

  /// Filesystem path to the backfill SQLite DB. Pass `":memory:"` for
  /// ephemeral imports (tests, throwaway sessions).
  final String dbPath;

  String? _activeImportId;

  /// Whether the loaded runtime exposes the Apple Health XML backfill symbols.
  bool get isAvailable =>
      _ffi != null &&
      _ffi.backfillOpen != null &&
      _ffi.backfillInsertBatch != null &&
      _ffi.backfillFinalize != null;

  /// Open a new import session. Throws [BackfillOpenFailed] on
  /// duplicate id, missing symbol, or SQLite error.
  Future<void> open(String importId) async {
    if (importId.isEmpty) {
      throw const BackfillOpenFailed('importId must not be empty');
    }
    if (!isAvailable) throw const BackfillRuntimeUnavailable();

    final pathPtr = dbPath.toNativeUtf8();
    final idPtr = importId.toNativeUtf8();
    try {
      final rc = _ffi!.backfillOpen!(pathPtr, idPtr);
      if (rc != 0) {
        throw BackfillOpenFailed(
          'runtime backfill_open returned $rc for importId=$importId',
        );
      }
      _activeImportId = importId;
    } finally {
      malloc.free(pathPtr);
      malloc.free(idPtr);
    }
  }

  /// Insert a batch of samples. [samplesAsJson] must be a JSON string
  /// matching `Vec<AppleHealthSample>` on the runtime side; the
  /// orchestrator typically constructs this via
  /// `jsonEncode(samples.map((s) => s.toRuntimeJson()).toList())`.
  Future<BackfillBatchResult> insertBatchJson(String samplesAsJson) async {
    if (!isAvailable) throw const BackfillRuntimeUnavailable();
    final id = _activeImportId;
    if (id == null) {
      throw const BackfillBatchFailed('insertBatch called before open');
    }

    final idPtr = id.toNativeUtf8();
    final jsonPtr = samplesAsJson.toNativeUtf8();
    Pointer<Utf8> resultPtr = nullptr;
    try {
      resultPtr = _ffi!.backfillInsertBatch!(idPtr, jsonPtr);
      if (resultPtr == nullptr) {
        throw const BackfillBatchFailed(
          'runtime backfill_insert_batch returned NULL',
        );
      }
      final raw = resultPtr.toDartString();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return BackfillBatchResult(
        inserted: (decoded['inserted'] as num).toInt(),
        skippedAsDuplicate: (decoded['skipped_as_duplicate'] as num).toInt(),
      );
    } finally {
      malloc.free(idPtr);
      malloc.free(jsonPtr);
      if (resultPtr != nullptr) {
        _ffi!.coreFreeString(resultPtr);
      }
    }
  }

  /// Finalize and close. Throws [BackfillFinalizeFailed] if no
  /// session is open or the runtime returns NULL.
  Future<BackfillImportResult> finalize() async {
    if (!isAvailable) throw const BackfillRuntimeUnavailable();
    final id = _activeImportId;
    if (id == null) {
      throw const BackfillFinalizeFailed('finalize called before open');
    }

    final idPtr = id.toNativeUtf8();
    Pointer<Utf8> resultPtr = nullptr;
    try {
      resultPtr = _ffi!.backfillFinalize!(idPtr);
      if (resultPtr == nullptr) {
        throw const BackfillFinalizeFailed(
          'runtime backfill_finalize returned NULL',
        );
      }
      final raw = resultPtr.toDartString();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _activeImportId = null;
      return BackfillImportResult(
        importId: decoded['import_id'] as String,
        totalSamples: (decoded['total_samples'] as num).toInt(),
        inserted: (decoded['inserted'] as num).toInt(),
        skippedAsDuplicate: (decoded['skipped_as_duplicate'] as num).toInt(),
        durationMs: (decoded['duration_ms'] as num).toInt(),
      );
    } finally {
      malloc.free(idPtr);
      if (resultPtr != nullptr) {
        _ffi!.coreFreeString(resultPtr);
      }
    }
  }
}
