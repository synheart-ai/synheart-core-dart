import 'artifact_header.dart';

class AxisStats {
  final double mean;
  final double std;
  final double confidence;

  const AxisStats({
    required this.mean,
    required this.std,
    required this.confidence,
  });

  Map<String, dynamic> toJson() => {
        'mean': mean,
        'std': std,
        'confidence': confidence,
      };

  factory AxisStats.fromJson(Map<String, dynamic> json) => AxisStats(
        mean: (json['mean'] as num).toDouble(),
        std: (json['std'] as num).toDouble(),
        confidence: (json['confidence'] as num).toDouble(),
      );
}

class BaselineCoverage {
  final int startMs;
  final int endMs;
  final int totalWindows;

  const BaselineCoverage({
    required this.startMs,
    required this.endMs,
    required this.totalWindows,
  });

  Map<String, dynamic> toJson() => {
        'start_ms': startMs,
        'end_ms': endMs,
        'total_windows': totalWindows,
      };

  factory BaselineCoverage.fromJson(Map<String, dynamic> json) =>
      BaselineCoverage(
        startMs: json['start_ms'] as int,
        endMs: json['end_ms'] as int,
        totalWindows: json['total_windows'] as int,
      );
}

class BaselineAxes {
  final AxisStats sleep;
  final AxisStats capacity;
  final AxisStats arousal;
  final AxisStats focus;

  const BaselineAxes({
    required this.sleep,
    required this.capacity,
    required this.arousal,
    required this.focus,
  });

  Map<String, dynamic> toJson() => {
        'sleep': sleep.toJson(),
        'capacity': capacity.toJson(),
        'arousal': arousal.toJson(),
        'focus': focus.toJson(),
      };

  factory BaselineAxes.fromJson(Map<String, dynamic> json) => BaselineAxes(
        sleep: AxisStats.fromJson(json['sleep'] as Map<String, dynamic>),
        capacity: AxisStats.fromJson(json['capacity'] as Map<String, dynamic>),
        arousal: AxisStats.fromJson(json['arousal'] as Map<String, dynamic>),
        focus: AxisStats.fromJson(json['focus'] as Map<String, dynamic>),
      );
}

class ModelRef {
  final String modelId;
  final String modelVersion;

  const ModelRef({required this.modelId, required this.modelVersion});

  Map<String, dynamic> toJson() => {
        'model_id': modelId,
        'model_version': modelVersion,
      };

  factory ModelRef.fromJson(Map<String, dynamic> json) => ModelRef(
        modelId: json['model_id'] as String,
        modelVersion: json['model_version'] as String,
      );
}

class BaselineData {
  final BaselineCoverage coverage;
  final BaselineAxes axes;
  final ModelRef model;

  const BaselineData({
    required this.coverage,
    required this.axes,
    required this.model,
  });

  Map<String, dynamic> toJson() => {
        'coverage': coverage.toJson(),
        'axes': axes.toJson(),
        'model': model.toJson(),
      };

  factory BaselineData.fromJson(Map<String, dynamic> json) => BaselineData(
        coverage: BaselineCoverage.fromJson(
            json['coverage'] as Map<String, dynamic>),
        axes: BaselineAxes.fromJson(json['axes'] as Map<String, dynamic>),
        model: ModelRef.fromJson(json['model'] as Map<String, dynamic>),
      );
}

/// A compact representation of the user's baseline state.
///
/// See RFC-CORE-0006 Section 6.1.
class BaselineSnapshotArtifact {
  final ArtifactHeader header;
  final BaselineData baseline;

  BaselineSnapshotArtifact({
    required this.header,
    required this.baseline,
  });

  factory BaselineSnapshotArtifact.create({
    required String subjectId,
    required BaselineData baseline,
  }) {
    final header = ArtifactHeader(
      type: 'baseline_snapshot',
      subjectId: subjectId,
      sessionId: null,
      timeRange: TimeRange(
        startMs: baseline.coverage.startMs,
        endMs: baseline.coverage.endMs,
      ),
      schema: const SchemaRef(name: 'baseline_snapshot', version: '1'),
    );
    return BaselineSnapshotArtifact(header: header, baseline: baseline);
  }

  Map<String, dynamic> toJson() => {
        ...header.toJson(),
        'baseline': baseline.toJson(),
      };

  factory BaselineSnapshotArtifact.fromJson(Map<String, dynamic> json) =>
      BaselineSnapshotArtifact(
        header: ArtifactHeader.fromJson(json),
        baseline:
            BaselineData.fromJson(json['baseline'] as Map<String, dynamic>),
      );
}
