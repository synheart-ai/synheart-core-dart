import 'dart:async';
import '../../core/logger.dart';
import '../../models/canonical_wearable_event.dart';
import '../../storage/storage_manager.dart';
import '../runtime/runtime_bridge.dart';
import '../srm/longitudinal_srm_module.dart';

/// Processes incoming RAMEN vendor events into the SynHeart pipeline:
///   RamenEvent payload → CanonicalWearableEvent → SQLite store → SRM push → runtime
///
/// This is the bridge between the wear SDK's real-time event stream and the
/// core SDK's longitudinal SRM engine. Each vendor event (sleep, recovery,
/// HRV, strain) is normalized, stored immutably, and pushed to the runtime
/// for baseline computation.
class WearableEventProcessor {
  final StorageManager _storage;
  final RuntimeBridge? _bridge;
  final LongitudinalSrmModule _srm;
  final String _subjectId;
  final String _deviceInstallId;

  WearableEventProcessor({
    required StorageManager storage,
    required RuntimeBridge? bridge,
    required String subjectId,
    required String deviceInstallId,
    LongitudinalSrmModule? srm,
  })  : _storage = storage,
        _bridge = bridge,
        _subjectId = subjectId,
        _deviceInstallId = deviceInstallId,
        _srm = srm ?? LongitudinalSrmModule();

  /// Process a raw vendor event from RAMEN.
  ///
  /// [provider] — e.g. "whoop", "garmin"
  /// [eventType] — e.g. "sleep.updated", "recovery.updated"
  /// [payload] — decoded JSON payload from the EventEnvelope
  /// [eventId] — RAMEN event ID (used for dedup)
  /// [seq] — RAMEN sequence number
  ///
  /// Returns the canonical event if processed, null if skipped (unknown type or dedup).
  Future<CanonicalWearableEvent?> processRamenEvent({
    required String provider,
    required String eventType,
    required Map<String, dynamic> payload,
    required String eventId,
    required int seq,
  }) async {
    // Map RAMEN event type to canonical event type
    final mapping = _mapEventType(provider, eventType);
    if (mapping == null) {
      SynheartLogger.log(
        '[WearableEventProcessor] Unknown event type: $provider/$eventType — skipping',
      );
      return null;
    }

    // Extract timestamps
    final observedAt = _extractTimestamp(payload, mapping.observedAtKey) ?? DateTime.now().toUtc();
    final effectiveStart = _extractTimestamp(payload, mapping.effectiveStartKey);
    final effectiveEnd = _extractTimestamp(payload, mapping.effectiveEndKey);

    // Extract provider record ID for deterministic dedup
    final providerRecordId = payload[mapping.providerRecordIdKey]?.toString();

    // Extract confidence from payload or use provider default
    final confidence = _extractConfidence(payload, provider);

    // Build canonical event
    final canonicalEventId = CanonicalWearableEvent.computeWearableEventId(
      subjectId: _subjectId,
      type: mapping.canonicalType,
      provider: provider,
      providerRecordId: providerRecordId,
      observedAt: observedAt,
      effectiveStart: effectiveStart,
      effectiveEnd: effectiveEnd,
    );

    // Extract the sub-payload for the canonical event
    final canonicalPayload = mapping.extractPayload(payload);

    final event = CanonicalWearableEvent(
      eventId: canonicalEventId,
      subjectId: _subjectId,
      deviceInstallId: _deviceInstallId,
      eventClass: 'PROVIDER_SUMMARY',
      type: mapping.canonicalType,
      provider: provider,
      providerRecordId: providerRecordId,
      observedAt: observedAt,
      ingestedAt: DateTime.now().toUtc(),
      effectiveStart: effectiveStart,
      effectiveEnd: effectiveEnd,
      payload: canonicalPayload,
      confidence: confidence,
      sourceFidelity: 'provider_summary',
      provenance: {
        'ramen_event_id': eventId,
        'ramen_seq': seq,
        'raw_event_type': eventType,
      },
    );

    // Store (idempotent — INSERT OR IGNORE on event_id)
    try {
      await _storage.insertWearableEvent(event.toMap());
    } catch (e) {
      SynheartLogger.log(
        '[WearableEventProcessor] Storage error: $e',
        error: e,
      );
      // Continue to SRM push even if storage fails — runtime needs the data
    }

    // Push to longitudinal SRM via runtime bridge
    try {
      await _srm.ingestEvent(event, _storage, _bridge);
      SynheartLogger.log(
        '[WearableEventProcessor] Processed $provider/${mapping.canonicalType} '
        '(seq=$seq, confidence=${confidence.toStringAsFixed(2)})',
      );
    } catch (e) {
      SynheartLogger.log(
        '[WearableEventProcessor] SRM push error: $e',
        error: e,
      );
    }

    return event;
  }

  /// Map RAMEN event types to canonical event types with extraction config.
  _EventMapping? _mapEventType(String provider, String eventType) {
    // Normalize: providers use different event naming
    final key = '$provider:$eventType';
    return _eventMappings[key] ?? _eventMappings[eventType];
  }

  DateTime? _extractTimestamp(Map<String, dynamic> payload, String? key) {
    if (key == null) return null;
    final raw = payload[key];
    if (raw == null) return null;
    if (raw is String) return DateTime.tryParse(raw)?.toUtc();
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw, isUtc: true);
    return null;
  }

  double _extractConfidence(Map<String, dynamic> payload, String provider) {
    // Some providers include quality/confidence in payload
    final quality = payload['quality'];
    if (quality is Map) {
      final conf = quality['confidence'];
      if (conf is num) return conf.toDouble().clamp(0.0, 1.0);
    }
    // Provider-level defaults (vendor summaries are generally high confidence)
    switch (provider) {
      case 'whoop':
        return 0.90;
      case 'garmin':
        return 0.85;
      case 'oura':
        return 0.88;
      default:
        return 0.75;
    }
  }

  // ─── Event Mapping Registry ─────────────────────────────────────────

  static final _eventMappings = <String, _EventMapping>{
    // WHOOP events
    'whoop:recovery.updated': _EventMapping(
      canonicalType: 'recovery.summary.recorded',
      observedAtKey: 'created_at',
      providerRecordIdKey: 'cycle_id',
      extractPayload: (p) => {
        'score': _asDouble(p['score']) ?? _asDouble(p['recovery_score']),
        'hrv_rmssd_ms': _asDouble(p['hrv']),
        'resting_hr_bpm': _asDouble(p['resting_heart_rate']),
        'spo2_pct': _asDouble(p['spo2_percentage']),
      },
    ),
    'whoop:sleep.updated': _EventMapping(
      canonicalType: 'sleep.summary.recorded',
      observedAtKey: 'end',
      effectiveStartKey: 'start',
      effectiveEndKey: 'end',
      providerRecordIdKey: 'id',
      extractPayload: (p) => {
        'duration_seconds': _asInt(p['total_in_bed_time_milli'] ?? p['duration_seconds']),
        'efficiency_pct': _asDouble(p['sleep_efficiency']),
        'midpoint_time': p['start'] != null && p['end'] != null
            ? _midpointIso(p['start']?.toString(), p['end']?.toString())
            : null,
      },
    ),
    'whoop:workout.updated': _EventMapping(
      canonicalType: 'workout.summary.recorded',
      observedAtKey: 'end',
      effectiveStartKey: 'start',
      effectiveEndKey: 'end',
      providerRecordIdKey: 'id',
      extractPayload: (p) => {
        'strain_score': _asDouble(p['strain']) ?? _asDouble(p['score']),
        'duration_seconds': _asInt(p['duration_seconds']),
        'avg_hr_bpm': _asDouble(p['average_heart_rate']),
        'max_hr_bpm': _asDouble(p['max_heart_rate']),
        'calories': _asDouble(p['kilojoule']),
      },
    ),

    // Garmin events
    'garmin:sleep.updated': _EventMapping(
      canonicalType: 'sleep.summary.recorded',
      observedAtKey: 'calendarDate',
      providerRecordIdKey: 'summaryId',
      extractPayload: (p) => {
        'duration_seconds': _asInt(p['durationInSeconds']),
        'deep_sleep_seconds': _asInt(p['deepSleepDurationInSeconds']),
        'light_sleep_seconds': _asInt(p['lightSleepDurationInSeconds']),
        'rem_sleep_seconds': _asInt(p['remSleepInSeconds']),
        'awake_seconds': _asInt(p['awakeDurationInSeconds']),
      },
    ),
    'garmin:recovery.updated': _EventMapping(
      canonicalType: 'recovery.summary.recorded',
      observedAtKey: 'calendarDate',
      providerRecordIdKey: 'summaryId',
      extractPayload: (p) => {
        'score': _asDouble(p['bodyBatteryChargedValue']) != null
            ? (_asDouble(p['bodyBatteryChargedValue'])! / 100.0)
            : null,
        'stress_avg': _asDouble(p['averageStressLevel']),
        'resting_hr_bpm': _asDouble(p['restingHeartRateInBeatsPerMinute']),
      },
    ),
    'garmin:hrv.updated': _EventMapping(
      canonicalType: 'hrv.recorded',
      observedAtKey: 'calendarDate',
      providerRecordIdKey: 'summaryId',
      extractPayload: (p) => {
        'rmssd_ms': _asDouble(p['weeklyAvg']) ?? _asDouble(p['lastNightAvg']),
        'status': p['hrvStatus'],
      },
    ),

    // Generic fallbacks (provider-agnostic event types)
    'recovery.updated': _EventMapping(
      canonicalType: 'recovery.summary.recorded',
      observedAtKey: 'created_at',
      extractPayload: (p) => {
        'score': _asDouble(p['score']) ?? _asDouble(p['recovery_score']),
      },
    ),
    'sleep.updated': _EventMapping(
      canonicalType: 'sleep.summary.recorded',
      observedAtKey: 'end',
      effectiveStartKey: 'start',
      effectiveEndKey: 'end',
      extractPayload: (p) => {
        'duration_seconds': _asInt(p['duration_seconds']),
        'efficiency_pct': _asDouble(p['efficiency']),
      },
    ),
  };

  static double? _asDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  static String? _midpointIso(String? start, String? end) {
    if (start == null || end == null) return null;
    final s = DateTime.tryParse(start);
    final e = DateTime.tryParse(end);
    if (s == null || e == null) return null;
    final mid = s.add(Duration(milliseconds: e.difference(s).inMilliseconds ~/ 2));
    return mid.toUtc().toIso8601String();
  }
}

/// Configuration for mapping a RAMEN event type to a canonical event.
class _EventMapping {
  final String canonicalType;
  final String? observedAtKey;
  final String? effectiveStartKey;
  final String? effectiveEndKey;
  final String? providerRecordIdKey;
  final Map<String, dynamic> Function(Map<String, dynamic>) extractPayload;

  const _EventMapping({
    required this.canonicalType,
    this.observedAtKey,
    this.effectiveStartKey,
    this.effectiveEndKey,
    this.providerRecordIdKey,
    required this.extractPayload,
  });
}
