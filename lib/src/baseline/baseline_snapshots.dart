import 'dart:async';
import 'dart:convert';

import 'baseline_envelope.dart';
import 'baseline_kind.dart';
import 'baseline_payloads.dart';

/// Hook signature for "send this envelope to the cloud". The facade
/// stays decoupled from `CoreRuntimeBridge` — `Synheart` wires the
/// bridge methods in once the runtime is configured.
typedef BaselineCloudUploader =
    Future<Map<String, dynamic>?> Function(String envelopeJson);

/// Hook signature for "fetch the latest envelope per kind for this
/// subject from the cloud".
typedef BaselineCloudSweep =
    Future<Map<String, dynamic>?> Function(String subjectId);

/// Hook signature for "read every latest baseline envelope per kind
/// for the configured subject from local storage". No network — pure
/// SQLite + decryption. Same `{snapshots: [...]}` shape as the cloud
/// sweep, so the same parser handles both.
typedef BaselineLocalHydrator = Future<Map<String, dynamic>?> Function();

/// Thrown when an upload / restore is attempted before cloud hooks
/// have been wired (typically: runtime hasn't been configured yet,
/// or the linked runtime binary doesn't ship the baseline FFI).
class BaselineCloudUnavailable implements Exception {
  final String reason;
  const BaselineCloudUnavailable(this.reason);
  @override
  String toString() => 'BaselineCloudUnavailable: $reason';
}

/// Thrown when the cloud rejects an upload or returns an error body.
class BaselineCloudError implements Exception {
  final int? statusCode;
  final String? message;
  const BaselineCloudError({this.statusCode, this.message});
  @override
  String toString() =>
      'BaselineCloudError(status=$statusCode, message=$message)';
}

/// Host-facing facade for typed baseline-snapshot access.
///
/// Exposed via `Synheart.baselineSnapshots`. Replaces the
/// `Map<String, dynamic>`-shaped legacy access pattern with synchronous
/// per-kind typed getters:
///
/// ```dart
/// final wear = Synheart.baselineSnapshots.latestLongitudinalWear();
/// if (wear != null) {
///   print('HRV baseline: ${wear.reference.dimensions['hrv_rmssd_ms']}');
/// }
/// ```
///
/// ## Cache model
///
/// In-memory cache keyed by [BaselineKind], last-write-wins per kind.
/// Populated by:
/// - The on-device producer (engine state → envelope writer) via [cache].
/// - The cloud sweep via [restoreAll], which fetches the latest envelope
///   per kind from the cloud and pushes each into the cache.
///
/// ## Cloud wiring
///
/// [upload] and [restoreAll] go through hooks injected by `Synheart`
/// after the runtime bridge is ready. Until then they throw
/// [BaselineCloudUnavailable]. The hooks themselves shell out to the
/// runtime's FFI surface — older runtime binaries that don't export
/// the baseline cloud symbols cause the hooks to return null, which
/// surfaces as [BaselineCloudUnavailable] at the call site.
class BaselineSnapshots {
  /// Singleton instance returned by `Synheart.baselineSnapshots`.
  /// Direct construction is allowed for tests.
  BaselineSnapshots();

  final Map<BaselineKind, BaselineEnvelope> _cache = {};
  BaselineCloudUploader? _uploader;
  BaselineCloudSweep? _sweep;
  BaselineLocalHydrator? _localHydrator;

  /// The most recent envelope for [kind], or `null` if no producer
  /// has cached one yet. Synchronous — reads in-memory state.
  BaselineEnvelope? envelopeFor(BaselineKind kind) => _cache[kind];

  /// Latest `session.hsi_axes` baseline, or `null` if none cached.
  HsiAxesBaseline? latestHsiAxes() {
    final env = _cache[BaselineKind.sessionHsiAxes];
    return env?.payloadHsiAxes();
  }

  /// Latest `session.srm_metrics` baseline, or `null` if none cached.
  SessionSrmMetricsBaseline? latestSrmMetrics() {
    final env = _cache[BaselineKind.sessionSrmMetrics];
    return env?.payloadSrmMetrics();
  }

  /// Latest `longitudinal.wear` baseline, or `null` if none cached.
  LongitudinalWearBaseline? latestLongitudinalWear() {
    final env = _cache[BaselineKind.longitudinalWear];
    return env?.payloadLongitudinalWear();
  }

  /// Unmodifiable snapshot of every kind that currently has a cached
  /// envelope. Powers the first-launch hydration UI ("show me one
  /// summary per baseline kind the user has on file").
  Map<BaselineKind, BaselineEnvelope> envelopesByKind() =>
      Map.unmodifiable(_cache);

  /// Push an envelope into the cache. Called by the on-device producer
  /// (engine state → envelope writer) after each successful local
  /// snapshot, and by [restoreAll] after the cloud sweep.
  /// Last-write-wins per kind.
  void cache(BaselineEnvelope envelope) {
    _cache[envelope.kind] = envelope;
  }

  /// Forget every cached envelope. Called on logout / user switch.
  void reset() {
    _cache.clear();
  }

  // ---- Cloud wiring (injected by Synheart) -----------------------------

  /// Inject the cloud hooks. Called by `Synheart` after the runtime
  /// bridge is configured. Idempotent — re-calling replaces the
  /// previous hooks (useful for re-configuration in tests).
  ///
  /// Pass `null` to clear (e.g. after disposing the runtime bridge);
  /// subsequent upload/restore calls then throw
  /// [BaselineCloudUnavailable] until rewired.
  ///
  /// [localHydrator] is the local-storage read path used by
  /// [hydrateFromLocal] for cold-start cache hydration. Optional —
  /// when null, [hydrateFromLocal] is a no-op (e.g. older runtime
  /// binaries that don't export the hydrate FFI).
  void wireCloud({
    required BaselineCloudUploader? uploader,
    required BaselineCloudSweep? sweep,
    BaselineLocalHydrator? localHydrator,
  }) {
    _uploader = uploader;
    _sweep = sweep;
    _localHydrator = localHydrator;
  }

  /// True when cloud hooks are wired (the runtime bridge is configured
  /// and the linked binary exports the baseline FFI). Use this to
  /// gate UI affordances that would otherwise call [upload] /
  /// [restoreAll] and throw.
  bool get isCloudWired => _uploader != null && _sweep != null;

  // ---- Local hydration ------------------------------------------------

  /// Populate the in-memory cache from locally-persisted artifacts.
  /// Called by `Synheart` on bridge construction so the typed getters
  /// ([latestHsiAxes], [latestSrmMetrics], [latestLongitudinalWear])
  /// return real data immediately after app cold-start, without
  /// waiting on a cloud round-trip.
  ///
  /// No-op when the runtime binary doesn't ship the hydrate FFI
  /// (typed getters keep returning null until a producer caches or
  /// [restoreAll] succeeds).
  ///
  /// Returns the list of envelopes that successfully landed in the
  /// cache (empty when nothing was on disk or the symbol was
  /// missing). Forward-compat: envelopes whose `kind` this SDK
  /// can't decode are silently skipped, same as [restoreAll].
  Future<List<BaselineEnvelope>> hydrateFromLocal() async {
    final hydrator = _localHydrator;
    if (hydrator == null) return const [];
    final resp = await hydrator();
    if (resp == null) return const [];
    if (resp['error'] is String) return const [];

    final raw = resp['snapshots'];
    if (raw is! List) return const [];

    final out = <BaselineEnvelope>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      try {
        final envelope = BaselineEnvelope.fromJson(
          entry.cast<String, dynamic>(),
        );
        cache(envelope);
        out.add(envelope);
      } on FormatException {
        // Forward-compat: skip envelopes the SDK can't decode.
        continue;
      }
    }
    return out;
  }

  // ---- Cloud paths ----------------------------------------------------

  /// Push a locally-built envelope to the cloud so it can be restored
  /// on another device. The producer typically calls [cache] first
  /// (synchronous, makes the envelope readable via the typed getters)
  /// and then [upload] in the background.
  ///
  /// Throws [BaselineCloudUnavailable] when [wireCloud] hasn't been
  /// called or the runtime binary doesn't ship the baseline FFI
  /// symbols. Throws [BaselineCloudError] when the cloud rejects the
  /// upload (4xx or returned `success: false`).
  Future<void> upload(BaselineEnvelope envelope) async {
    final uploader = _uploader;
    if (uploader == null) {
      throw const BaselineCloudUnavailable(
        'cloud hooks not wired — runtime bridge not configured',
      );
    }
    final envelopeJson = jsonEncode(envelope.toJson());
    final resp = await uploader(envelopeJson);
    if (resp == null) {
      throw const BaselineCloudUnavailable(
        'runtime binary does not ship the baseline cloud FFI',
      );
    }
    if (resp['error'] is String) {
      throw BaselineCloudError(message: resp['error'] as String);
    }
    final success = resp['success'] == true;
    if (!success) {
      throw BaselineCloudError(
        statusCode: (resp['status_code'] as num?)?.toInt(),
        message: resp['error_message'] as String?,
      );
    }
  }

  /// Hydrate the local cache from the cloud — one envelope per kind
  /// the user has on file. Used by the first-launch restore flow on
  /// a new device. Returns the list of envelopes that successfully
  /// landed in the cache (empty when the subject has no baselines).
  ///
  /// Each envelope retrieved is parsed and pushed into [cache], so
  /// after this completes the typed getters ([latestHsiAxes],
  /// [latestSrmMetrics], [latestLongitudinalWear]) return real data.
  ///
  /// Throws [BaselineCloudUnavailable] / [BaselineCloudError] under
  /// the same conditions as [upload]. Envelopes whose `kind` this SDK
  /// doesn't understand are silently skipped (forward-compat for
  /// kinds added in a newer runtime / cloud).
  Future<List<BaselineEnvelope>> restoreAll({
    required String subjectId,
  }) async {
    final sweep = _sweep;
    if (sweep == null) {
      throw const BaselineCloudUnavailable(
        'cloud hooks not wired — runtime bridge not configured',
      );
    }
    final resp = await sweep(subjectId);
    if (resp == null) {
      throw const BaselineCloudUnavailable(
        'runtime binary does not ship the baseline cloud FFI',
      );
    }
    if (resp['error'] is String) {
      throw BaselineCloudError(message: resp['error'] as String);
    }
    if (resp['success'] != true) {
      throw BaselineCloudError(
        statusCode: (resp['status_code'] as num?)?.toInt(),
        message: resp['error_message'] as String?,
      );
    }

    // Cloud response shape: { success, status_code, body: { snapshots: [...] } }
    final body = resp['body'] as Map<String, dynamic>?;
    final raw = body?['snapshots'];
    if (raw is! List) return const [];

    final out = <BaselineEnvelope>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      try {
        final envelope = BaselineEnvelope.fromJson(
          entry.cast<String, dynamic>(),
        );
        cache(envelope);
        out.add(envelope);
      } on FormatException {
        // Forward-compat: skip envelopes the SDK can't decode.
        continue;
      }
    }
    return out;
  }
}
