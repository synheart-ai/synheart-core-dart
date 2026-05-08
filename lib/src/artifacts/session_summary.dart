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
    'start_ms': startMs,
    'end_ms': endMs,
    'mode': mode,
  };

  factory SessionInfo.fromJson(Map<String, dynamic> json) => SessionInfo(
    sessionId: json['session_id'] as String,
    startMs: json['start_ms'] as int,
    endMs: json['end_ms'] as int,
    mode: json['mode'] as String,
  );
}

class CoverageInfo {
  final int totalWindows;
  final int windowSizeMs;

  const CoverageInfo({required this.totalWindows, this.windowSizeMs = 30000});

  Map<String, dynamic> toJson() => {
    'total_windows': totalWindows,
    'window_size_ms': windowSizeMs,
  };

  factory CoverageInfo.fromJson(Map<String, dynamic> json) => CoverageInfo(
    totalWindows: json['total_windows'] as int,
    windowSizeMs: json['window_size_ms'] as int? ?? 30000,
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

class SessionAggregates {
  final AggregateAxis focus;
  final AggregateAxis arousal;
  final AggregateAxis capacity;
  final AggregateAxis sleep;

  const SessionAggregates({
    required this.focus,
    required this.arousal,
    required this.capacity,
    required this.sleep,
  });

  Map<String, dynamic> toJson() => {
    'focus': focus.toJson(),
    'arousal': arousal.toJson(),
    'capacity': capacity.toJson(),
    'sleep': sleep.toJson(),
  };

  factory SessionAggregates.fromJson(
    Map<String, dynamic> json,
  ) => SessionAggregates(
    focus: AggregateAxis.fromJson(json['focus'] as Map<String, dynamic>),
    arousal: AggregateAxis.fromJson(json['arousal'] as Map<String, dynamic>),
    capacity: AggregateAxis.fromJson(json['capacity'] as Map<String, dynamic>),
    sleep: AggregateAxis.fromJson(json['sleep'] as Map<String, dynamic>),
  );
}

class AppMetric {
  final String name;
  final double mean;
  final int count;

  const AppMetric({
    required this.name,
    required this.mean,
    required this.count,
  });

  Map<String, dynamic> toJson() => {'name': name, 'mean': mean, 'count': count};

  factory AppMetric.fromJson(Map<String, dynamic> json) => AppMetric(
    name: json['name'] as String,
    mean: (json['mean'] as num).toDouble(),
    count: json['count'] as int,
  );
}

class InsightMetrics {
  final List<AppMetric> appMetrics;

  const InsightMetrics({this.appMetrics = const []});

  Map<String, dynamic> toJson() => {
    'app_metrics': appMetrics.map((m) => m.toJson()).toList(),
  };

  factory InsightMetrics.fromJson(Map<String, dynamic> json) => InsightMetrics(
    appMetrics:
        (json['app_metrics'] as List<dynamic>?)
            ?.map((e) => AppMetric.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const [],
  );
}

/// A compact session summary for UI display and fast queries.
///
/// See RFC-CORE-0006 Section 6.3.
class SessionSummaryArtifact {
  final ArtifactHeader header;
  final SessionInfo session;
  final CoverageInfo coverage;
  final SessionAggregates aggregates;
  final InsightMetrics insightMetrics;

  SessionSummaryArtifact({
    required this.header,
    required this.session,
    required this.coverage,
    required this.aggregates,
    this.insightMetrics = const InsightMetrics(),
  });

  Map<String, dynamic> toJson() => {
    ...header.toJson(),
    'session': session.toJson(),
    'coverage': coverage.toJson(),
    'aggregates': aggregates.toJson(),
    'insight_metrics': insightMetrics.toJson(),
  };

  factory SessionSummaryArtifact.fromJson(Map<String, dynamic> json) =>
      SessionSummaryArtifact(
        header: ArtifactHeader.fromJson(json),
        session: SessionInfo.fromJson(json['session'] as Map<String, dynamic>),
        coverage: CoverageInfo.fromJson(
          json['coverage'] as Map<String, dynamic>,
        ),
        aggregates: SessionAggregates.fromJson(
          json['aggregates'] as Map<String, dynamic>,
        ),
        insightMetrics: json['insight_metrics'] != null
            ? InsightMetrics.fromJson(
                json['insight_metrics'] as Map<String, dynamic>,
              )
            : const InsightMetrics(),
      );
}
