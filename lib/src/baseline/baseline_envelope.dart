import '../artifacts/artifact_header.dart';
import 'baseline_kind.dart';
import 'baseline_payloads.dart';

/// Engine reference embedded in every baseline envelope. Mirror of
/// `BaselineEngine` in engine-types.
class BaselineEngineRef {
  final String name;
  final String version;

  /// Deterministic hash of the engine's runtime config. Two snapshots
  /// with the same `configHash` were computed under identical settings.
  final String configHash;

  const BaselineEngineRef({
    required this.name,
    required this.version,
    required this.configHash,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'version': version,
    'config_hash': configHash,
  };

  factory BaselineEngineRef.fromJson(Map<String, dynamic> json) =>
      BaselineEngineRef(
        name: json['name'] as String? ?? '',
        version: json['version'] as String? ?? '',
        configHash: json['config_hash'] as String? ?? '',
      );
}

/// Coverage metadata — how much input fed this snapshot, and how many
/// dimensions / axes / metrics it covers. Used by the merge rule
/// (RFC §13) and by readers gating on freshness.
class BaselineCoverage {
  final int windowStartMs;
  final int windowEndMs;
  final int observations;
  final int dimensionsPresent;
  final int dimensionsTotal;

  const BaselineCoverage({
    required this.windowStartMs,
    required this.windowEndMs,
    required this.observations,
    required this.dimensionsPresent,
    required this.dimensionsTotal,
  });

  Map<String, dynamic> toJson() => {
    'window_start_ms': windowStartMs,
    'window_end_ms': windowEndMs,
    'observations': observations,
    'dimensions_present': dimensionsPresent,
    'dimensions_total': dimensionsTotal,
  };

  factory BaselineCoverage.fromJson(Map<String, dynamic> json) =>
      BaselineCoverage(
        windowStartMs: (json['window_start_ms'] as num).toInt(),
        windowEndMs: (json['window_end_ms'] as num).toInt(),
        observations: (json['observations'] as num?)?.toInt() ?? 0,
        dimensionsPresent: (json['dimensions_present'] as num?)?.toInt() ?? 0,
        dimensionsTotal: (json['dimensions_total'] as num?)?.toInt() ?? 0,
      );
}

/// One baseline snapshot, ready to upload to the cloud or restore
/// locally. Mirror of `BaselineEnvelope` in
/// `synheart-core-runtime::baseline::envelope` — same field set, same
/// wire shape, same `bs_<48hex>` `artifactId` derivation.
///
/// Payload is held as `Map<String, dynamic>` (the raw JSON) so the
/// envelope stays kind-agnostic — one Dart class for all kinds, one
/// reader. Producers use the typed builders; consumers use the typed
/// extractors ([payloadHsiAxes], [payloadSrmMetrics],
/// [payloadLongitudinalWear]) which dispatch on [kind] and throw
/// [BaselineKindMismatch] on the wrong call.
class BaselineEnvelope {
  final ArtifactHeader header;
  final BaselineKind kind;
  final int kindSchemaVersion;
  final int computedAtMs;
  final BaselineEngineRef engine;
  final BaselineCoverage coverage;
  final Map<String, dynamic> payload;

  const BaselineEnvelope({
    required this.header,
    required this.kind,
    required this.kindSchemaVersion,
    required this.computedAtMs,
    required this.engine,
    required this.coverage,
    required this.payload,
  });

  Map<String, dynamic> toJson() => {
    'header': header.toJson(),
    'kind': kind.wire,
    'kind_schema_version': kindSchemaVersion,
    'computed_at_ms': computedAtMs,
    'engine': engine.toJson(),
    'coverage': coverage.toJson(),
    'payload': payload,
  };

  /// Parse an envelope from JSON. Throws [FormatException] on missing
  /// header fields; throws [BaselineKindMismatch] only on typed
  /// payload extraction, not here — an envelope with an unknown
  /// `kind` parses to a [BaselineEnvelope] whose [kind] is set via
  /// best-effort fallback, leaving forward-compat alive at the
  /// reader's call sites.
  factory BaselineEnvelope.fromJson(Map<String, dynamic> json) {
    final headerJson = json['header'];
    if (headerJson is! Map) {
      throw const FormatException('baseline envelope missing header');
    }
    final kindWire = json['kind'] as String?;
    final kind = BaselineKind.fromWire(kindWire);
    if (kind == null) {
      throw FormatException(
        'unknown baseline kind: ${kindWire ?? '<null>'}. '
        'Update the SDK or skip this snapshot.',
      );
    }
    return BaselineEnvelope(
      header: ArtifactHeader.fromJson(headerJson.cast<String, dynamic>()),
      kind: kind,
      kindSchemaVersion: (json['kind_schema_version'] as num?)?.toInt() ?? 1,
      computedAtMs: (json['computed_at_ms'] as num).toInt(),
      engine: BaselineEngineRef.fromJson(
        (json['engine'] as Map).cast<String, dynamic>(),
      ),
      coverage: BaselineCoverage.fromJson(
        (json['coverage'] as Map).cast<String, dynamic>(),
      ),
      payload: (json['payload'] as Map).cast<String, dynamic>(),
    );
  }

  /// Decode this envelope's payload as an [HsiAxesBaseline]. Throws
  /// [BaselineKindMismatch] when [kind] is not
  /// [BaselineKind.sessionHsiAxes].
  HsiAxesBaseline payloadHsiAxes() {
    _requireKind(BaselineKind.sessionHsiAxes);
    return HsiAxesBaseline.fromJson(payload);
  }

  /// Decode this envelope's payload as a [SessionSrmMetricsBaseline].
  /// Throws [BaselineKindMismatch] when [kind] is not
  /// [BaselineKind.sessionSrmMetrics].
  SessionSrmMetricsBaseline payloadSrmMetrics() {
    _requireKind(BaselineKind.sessionSrmMetrics);
    return SessionSrmMetricsBaseline.fromJson(payload);
  }

  /// Decode this envelope's payload as a [LongitudinalWearBaseline].
  /// Throws [BaselineKindMismatch] when [kind] is not
  /// [BaselineKind.longitudinalWear].
  LongitudinalWearBaseline payloadLongitudinalWear() {
    _requireKind(BaselineKind.longitudinalWear);
    return LongitudinalWearBaseline.fromJson(payload);
  }

  void _requireKind(BaselineKind expected) {
    if (kind != expected) {
      throw BaselineKindMismatch(expected: expected, actual: kind);
    }
  }
}

/// Thrown by a typed payload extractor when the envelope's [kind]
/// doesn't match the caller's expected kind.
class BaselineKindMismatch implements Exception {
  final BaselineKind expected;
  final BaselineKind actual;
  const BaselineKindMismatch({required this.expected, required this.actual});

  @override
  String toString() =>
      'BaselineKindMismatch: envelope is ${actual.wire}, '
      'caller asked for ${expected.wire}';
}
