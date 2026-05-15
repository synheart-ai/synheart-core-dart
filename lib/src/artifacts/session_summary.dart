import 'artifact_header.dart';

class SessionInfo {
  final String sessionId;
  final int startMs;
  final int endMs;
  final String mode;

  const SessionInfo({
    required this.sessionId,
    required this.startMs,
    required this.endMs,
    required this.mode,
  });

  Map<String, dynamic> toJson() => {
    'session_id': sessionId,
    'started_at_ms': startMs,
    'ended_at_ms': endMs,
    'mode': mode,
  };

  factory SessionInfo.fromJson(Map<String, dynamic> json) => SessionInfo(
    sessionId: json['session_id'] as String,
    startMs: (json['started_at_ms'] as num).toInt(),
    endMs: (json['ended_at_ms'] as num).toInt(),
    mode: json['mode'] as String,
  );
}

class CoverageInfo {
  final int windowCount;
  final double coveragePct;

  const CoverageInfo({
    required this.windowCount,
    this.coveragePct = 0.0,
  });

  Map<String, dynamic> toJson() => {
    'window_count': windowCount,
    'coverage_pct': coveragePct,
  };

  factory CoverageInfo.fromJson(Map<String, dynamic> json) => CoverageInfo(
    windowCount: (json['window_count'] as num?)?.toInt() ?? 0,
    coveragePct: (json['coverage_pct'] as num?)?.toDouble() ?? 0.0,
  );
}

class AggregateAxis {
  final double mean;
  final double min;
  final double max;

  const AggregateAxis({
    required this.mean,
    required this.min,
    required this.max,
  });

  Map<String, dynamic> toJson() => {'mean': mean, 'min': min, 'max': max};

  factory AggregateAxis.fromJson(Map<String, dynamic> json) => AggregateAxis(
    mean: (json['mean'] as num).toDouble(),
    min: (json['min'] as num).toDouble(),
    max: (json['max'] as num).toDouble(),
  );
}

/// Per-axis aggregates, keyed by axis name.
///
/// New axes introduced by future HSI versions appear automatically — they
/// are reachable via [operator []] and listed in [keys]. The well-known
/// axes are exposed as named getters; a `null` getter means the axis was
/// not emitted for the session (no readings), which is distinct from a
/// recorded mean of zero.
class SessionAggregates {
  final Map<String, AggregateAxis> _byName;

  const SessionAggregates._(this._byName);

  const SessionAggregates.empty() : _byName = const {};

  Iterable<String> get keys => _byName.keys;

  AggregateAxis? operator [](String axis) => _byName[axis];

  AggregateAxis? get focus => _byName['focus'];
  AggregateAxis? get arousal => _byName['arousal'];
  AggregateAxis? get capacity => _byName['capacity'];
  AggregateAxis? get sleep => _byName['sleep'];
  AggregateAxis? get valence => _byName['valence'];
  AggregateAxis? get stress => _byName['stress'];
  AggregateAxis? get calm => _byName['calm'];

  Map<String, dynamic> toJson() =>
      _byName.map((k, v) => MapEntry(k, v.toJson()));

  factory SessionAggregates.fromJson(Map<String, dynamic> json) {
    final out = <String, AggregateAxis>{};
    for (final entry in json.entries) {
      final v = entry.value;
      if (v is Map<String, dynamic>) {
        out[entry.key] = AggregateAxis.fromJson(v);
      }
    }
    return SessionAggregates._(out);
  }
}

class AppMetric {
  final String name;
  final dynamic value;
  final int count;

  const AppMetric({
    required this.name,
    required this.value,
    required this.count,
  });

  Map<String, dynamic> toJson() =>
      {'name': name, 'value': value, 'count': count};

  factory AppMetric.fromJson(Map<String, dynamic> json) => AppMetric(
    name: json['name'] as String,
    value: json['value'],
    count: (json['count'] as num).toInt(),
  );
}

class InsightMetrics {
  final List<AppMetric> metrics;

  const InsightMetrics({this.metrics = const []});

  Map<String, dynamic> toJson() => {
    'metrics': metrics.map((m) => m.toJson()).toList(),
  };

  factory InsightMetrics.fromJson(Map<String, dynamic> json) => InsightMetrics(
    metrics: (json['metrics'] as List<dynamic>?)
            ?.map((e) => AppMetric.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const [],
  );
}

/// Compact session summary for UI display and fast queries.
class SessionSummaryArtifact {
  final ArtifactHeader header;
  final SessionInfo session;
  final CoverageInfo coverage;
  final SessionAggregates aggregates;
  final InsightMetrics? insightMetrics;

  SessionSummaryArtifact({
    required this.header,
    required this.session,
    required this.coverage,
    required this.aggregates,
    this.insightMetrics,
  });

  Map<String, dynamic> toJson() => {
    'header': header.toJson(),
    'session': session.toJson(),
    'coverage': coverage.toJson(),
    'aggregates': aggregates.toJson(),
    if (insightMetrics != null) 'insight_metrics': insightMetrics!.toJson(),
  };

  factory SessionSummaryArtifact.fromJson(Map<String, dynamic> json) =>
      SessionSummaryArtifact(
        header: ArtifactHeader.fromJson(json['header'] as Map<String, dynamic>),
        session: SessionInfo.fromJson(json['session'] as Map<String, dynamic>),
        coverage: CoverageInfo.fromJson(
          json['coverage'] as Map<String, dynamic>,
        ),
        aggregates: SessionAggregates.fromJson(
          json['aggregates'] as Map<String, dynamic>,
        ),
        insightMetrics: json['insight_metrics'] is Map<String, dynamic>
            ? InsightMetrics.fromJson(
                json['insight_metrics'] as Map<String, dynamic>,
              )
            : null,
      );
}
