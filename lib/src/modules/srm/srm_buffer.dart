import 'dart:math' as math;

import 'srm_config.dart';
import 'srm_stratum.dart';
import 'srm_baseline_status.dart';
import 'srm_types.dart';

/// An accepted entry stored in the per-stratum buffer.
class BufferEntry {
  final String windowId;
  final Map<String, double> metrics;
  final DateTime observedAtUtc;

  const BufferEntry({
    required this.windowId,
    required this.metrics,
    required this.observedAtUtc,
  });

  /// Calendar day key (UTC) for distinct-day counting.
  String get dayKey =>
      '${observedAtUtc.year}-${observedAtUtc.month.toString().padLeft(2, '0')}-${observedAtUtc.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> toJson() => {
    'window_id': windowId,
    'metrics': metrics,
    'observed_at_utc': observedAtUtc.toIso8601String(),
  };

  factory BufferEntry.fromJson(Map<String, dynamic> json) {
    return BufferEntry(
      windowId: json['window_id'] as String,
      metrics: (json['metrics'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, (v as num).toDouble()),
      ),
      observedAtUtc: DateTime.parse(json['observed_at_utc'] as String),
    );
  }
}

/// Bounded per-stratum buffer with quality gating, outlier rejection,
/// oldest-first eviction, and deterministic median/MAD computation.
///
/// Implements SRM.pdf §4 (accept/reject) and §5 (buffer management).
class SRMBuffer {
  final SRMStratum stratum;
  final SRMConfig config;

  /// Ordered list of accepted entries (oldest first).
  final List<BufferEntry> _entries = [];

  /// Cached per-metric references. Recomputed after every buffer mutation.
  Map<String, MetricReference> _cachedReference = {};

  SRMBuffer({required this.stratum, required this.config});

  List<BufferEntry> get entries => List.unmodifiable(_entries);
  int get count => _entries.length;

  int get distinctDays {
    final days = <String>{};
    for (final e in _entries) {
      days.add(e.dayKey);
    }
    return days.length;
  }

  SRMBaselineStatus get baselineStatus {
    if (_entries.length < config.mMin) return SRMBaselineStatus.empty;
    if (_entries.length < config.mReady) return SRMBaselineStatus.warming;
    if (distinctDays < config.dMin) return SRMBaselineStatus.warming;
    return SRMBaselineStatus.ready;
  }

  Map<String, MetricReference> get reference =>
      Map.unmodifiable(_cachedReference);

  /// Submit a candidate window. Returns an [SRMResult].
  SRMResult submit(CandidateWindow candidate) {
    if (candidate.hasInvalidValues) {
      return _reject('nan_or_inf', candidate);
    }

    if (candidate.durationSeconds < config.durationThresholdSeconds) {
      return _reject('duration_below_threshold', candidate);
    }

    if (candidate.qualityScore < config.qualityThreshold) {
      return _reject('quality_below_threshold', candidate);
    }

    final motionThreshold = config.motionThresholdFor(stratum);
    if (candidate.motionScore > motionThreshold) {
      return _reject('motion_above_threshold', candidate);
    }

    if (_entries.length >= config.mMin) {
      for (final metric in config.trackedMetrics) {
        final value = candidate.metrics[metric];
        if (value == null) continue;
        final ref = _cachedReference[metric];
        if (ref == null) continue;

        final denominator = math.max(ref.mad, config.epsilon);
        final z = (value - ref.median) / denominator;
        if (z.abs() > config.outlierKappa) {
          return _reject('outlier_$metric', candidate);
        }
      }
    }

    if (_entries.length >= config.bufferSize) {
      _entries.removeAt(0);
    }

    _entries.add(BufferEntry(
      windowId: candidate.windowId,
      metrics: Map<String, double>.from(candidate.metrics),
      observedAtUtc: candidate.observedAtUtc,
    ));

    _recomputeReference();

    return _accept(candidate);
  }

  /// Restore buffer from serialized entries (snapshot restore).
  void restore(List<BufferEntry> entries) {
    _entries.clear();
    _entries.addAll(entries);
    _recomputeReference();
  }

  /// Clear all entries and cached reference.
  void reset() {
    _entries.clear();
    _cachedReference = {};
  }

  /// Deterministic median: lower-middle for even counts.
  static double deterministicMedian(List<double> values) {
    final sorted = List<double>.from(values)..sort();
    final n = sorted.length;
    if (n == 0) return double.nan;
    if (n.isOdd) return sorted[n ~/ 2];
    return sorted[n ~/ 2 - 1]; // lower-middle
  }

  /// MAD (Median Absolute Deviation).
  static double deterministicMAD(List<double> values, double median) {
    final deviations = values.map((x) => (x - median).abs()).toList();
    return deterministicMedian(deviations);
  }

  void _recomputeReference() {
    final ref = <String, MetricReference>{};
    for (final metric in config.trackedMetrics) {
      final values = <double>[];
      for (final e in _entries) {
        final v = e.metrics[metric];
        if (v != null) values.add(v);
      }
      if (values.isEmpty) continue;
      final med = deterministicMedian(values);
      final mad = deterministicMAD(values, med);
      ref[metric] = MetricReference(median: med, mad: mad);
    }
    _cachedReference = ref;
  }

  SRMResult _reject(String reason, CandidateWindow candidate) {
    return SRMResult(
      accepted: false,
      rejectionReason: reason,
      baselineStatus: baselineStatus,
      reference: _cachedReference.isNotEmpty ? _cachedReference : null,
      srmSnapshotId: _snapshotId(),
      srmVersion: config.srmVersion,
    );
  }

  SRMResult _accept(CandidateWindow candidate) {
    return SRMResult(
      accepted: true,
      baselineStatus: baselineStatus,
      reference: _cachedReference.isNotEmpty ? _cachedReference : null,
      srmSnapshotId: _snapshotId(),
      srmVersion: config.srmVersion,
    );
  }

  String _snapshotId() =>
      'srm_${stratum.name}_${_entries.length}_${DateTime.now().millisecondsSinceEpoch}';
}
