import 'srm_stratum.dart';
import 'srm_baseline_status.dart';
import 'srm_types.dart';

/// Minimal buffer entry for SRM snapshot serialization.
///
/// Previously defined in srm_buffer.dart; inlined here after that file
class BufferEntry {
  final DateTime timestamp;
  final Map<String, double> values;

  const BufferEntry({required this.timestamp, required this.values});

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toUtc().toIso8601String(),
    'values': values,
  };

  factory BufferEntry.fromJson(Map<String, dynamic> json) {
    return BufferEntry(
      timestamp: DateTime.parse(json['timestamp'] as String),
      values: (json['values'] as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, (v as num).toDouble())),
    );
  }
}

/// Per-stratum snapshot for serialization.
class StratumSnapshot {
  final SRMStratum stratum;
  final SRMBaselineStatus status;
  final List<BufferEntry> entries;
  final Map<String, MetricReference> reference;
  final int distinctDays;

  const StratumSnapshot({
    required this.stratum,
    required this.status,
    required this.entries,
    required this.reference,
    required this.distinctDays,
  });

  Map<String, dynamic> toJson() => {
    'stratum': stratum.name,
    'status': status.toUpperCase(),
    'entries': entries.map((e) => e.toJson()).toList(),
    'reference': reference.map((k, v) => MapEntry(k, v.toJson())),
    'distinct_days': distinctDays,
  };

  factory StratumSnapshot.fromJson(Map<String, dynamic> json) {
    return StratumSnapshot(
      stratum: SRMStratum.fromString(json['stratum'] as String) ?? SRMStratum.other,
      status: SRMBaselineStatus.values.firstWhere(
        (s) => s.toUpperCase() == (json['status'] as String),
        orElse: () => SRMBaselineStatus.empty,
      ),
      entries: (json['entries'] as List<dynamic>)
          .map((e) => BufferEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      reference: (json['reference'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, MetricReference.fromJson(v as Map<String, dynamic>)),
      ),
      distinctDays: (json['distinct_days'] as num).toInt(),
    );
  }
}

/// Complete SRM snapshot — all strata, versioned.
///
/// Used for in-memory save/restore of SRM state across session boundaries.
class SRMSnapshot {
  final String srmVersion;
  final DateTime createdAtUtc;
  final Map<SRMStratum, StratumSnapshot> strata;

  const SRMSnapshot({
    required this.srmVersion,
    required this.createdAtUtc,
    required this.strata,
  });

  Map<String, dynamic> toJson() => {
    'srm_version': srmVersion,
    'created_at_utc': createdAtUtc.toIso8601String(),
    'strata': strata.map((k, v) => MapEntry(k.name, v.toJson())),
  };

  factory SRMSnapshot.fromJson(Map<String, dynamic> json) {
    final strataJson = json['strata'] as Map<String, dynamic>;
    final strata = <SRMStratum, StratumSnapshot>{};
    for (final entry in strataJson.entries) {
      final stratum = SRMStratum.fromString(entry.key);
      if (stratum != null) {
        strata[stratum] = StratumSnapshot.fromJson(
          entry.value as Map<String, dynamic>,
        );
      }
    }
    return SRMSnapshot(
      srmVersion: json['srm_version'] as String,
      createdAtUtc: DateTime.parse(json['created_at_utc'] as String),
      strata: strata,
    );
  }
}
