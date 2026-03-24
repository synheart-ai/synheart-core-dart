import 'dart:convert';

import 'package:crypto/crypto.dart';

class CanonicalWearableEvent {
  final String eventId;
  final String subjectId;
  final String deviceInstallId;
  final String eventClass;
  final String type;
  final String provider;
  final String? providerRecordId;
  final DateTime observedAt;
  final DateTime ingestedAt;
  final DateTime? effectiveStart;
  final DateTime? effectiveEnd;
  final Map<String, dynamic> payload;
  final String? unit;
  final double confidence;
  final String sourceFidelity;
  final Map<String, dynamic>? provenance;
  final int schemaVersion;

  CanonicalWearableEvent({
    required this.eventId,
    required this.subjectId,
    required this.deviceInstallId,
    required this.eventClass,
    required this.type,
    required this.provider,
    this.providerRecordId,
    required this.observedAt,
    required this.ingestedAt,
    this.effectiveStart,
    this.effectiveEnd,
    required this.payload,
    this.unit,
    required this.confidence,
    required this.sourceFidelity,
    this.provenance,
    this.schemaVersion = 1,
  });

  static String computeWearableEventId({
    required String subjectId,
    required String type,
    required String provider,
    String? providerRecordId,
    required DateTime observedAt,
    DateTime? effectiveStart,
    DateTime? effectiveEnd,
  }) {
    final String canonical;
    if (providerRecordId != null) {
      canonical =
          'kind=wearable_event|provider=$provider|provider_record_id=$providerRecordId|v=1';
    } else {
      final endStr = effectiveEnd?.toIso8601String() ?? '~';
      final startStr = effectiveStart?.toIso8601String() ?? '~';
      canonical =
          'effective_end=$endStr|effective_start=$startStr|kind=wearable_event|observed=${observedAt.toIso8601String()}|provider=$provider|subject=$subjectId|type=$type|v=1';
    }
    final hash = sha256.convert(utf8.encode(canonical));
    final truncated = hash.bytes.sublist(0, 24);
    final hex = truncated.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return 'we_$hex';
  }

  Map<String, dynamic> toMap() => {
        'event_id': eventId,
        'subject_id': subjectId,
        'device_install_id': deviceInstallId,
        'event_class': eventClass,
        'event_type': type,
        'provider': provider,
        'provider_record_id': providerRecordId,
        'observed_at': observedAt.toIso8601String(),
        'ingested_at': ingestedAt.toIso8601String(),
        'effective_start': effectiveStart?.toIso8601String(),
        'effective_end': effectiveEnd?.toIso8601String(),
        'payload': jsonEncode(payload),
        'unit': unit,
        'confidence': confidence,
        'source_fidelity': sourceFidelity,
        'provenance': provenance != null ? jsonEncode(provenance) : null,
        'schema_version': schemaVersion,
      };

  factory CanonicalWearableEvent.fromMap(Map<String, dynamic> map) =>
      CanonicalWearableEvent(
        eventId: map['event_id'] as String,
        subjectId: map['subject_id'] as String,
        deviceInstallId: map['device_install_id'] as String,
        eventClass: map['event_class'] as String,
        type: map['event_type'] as String,
        provider: map['provider'] as String,
        providerRecordId: map['provider_record_id'] as String?,
        observedAt: DateTime.parse(map['observed_at'] as String),
        ingestedAt: DateTime.parse(map['ingested_at'] as String),
        effectiveStart: map['effective_start'] != null
            ? DateTime.parse(map['effective_start'] as String)
            : null,
        effectiveEnd: map['effective_end'] != null
            ? DateTime.parse(map['effective_end'] as String)
            : null,
        payload: jsonDecode(map['payload'] as String) as Map<String, dynamic>,
        unit: map['unit'] as String?,
        confidence: (map['confidence'] as num).toDouble(),
        sourceFidelity: map['source_fidelity'] as String,
        provenance: map['provenance'] != null
            ? jsonDecode(map['provenance'] as String) as Map<String, dynamic>
            : null,
        schemaVersion: map['schema_version'] as int? ?? 1,
      );
}
