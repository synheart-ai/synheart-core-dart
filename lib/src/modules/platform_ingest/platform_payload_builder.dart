import 'dart:math';

import '../../config/synheart_config.dart';
import '../behavior/behavior_events.dart';
import '../phone/phone_cache.dart';
import '../phone/phone_collectors.dart';
import '../wear/wear_source_handler.dart';
import '../interfaces/feature_providers.dart';

/// Builds platform ingestion payloads from SDK internal data.
///
/// Aggregates raw wear samples, behavior events, and phone context
/// into the structured format expected by the platform ingestion API.
class PlatformPayloadBuilder {
  const PlatformPayloadBuilder._();

  // ── Metadata payload ──────────────────────────────────────────────

  /// Build a metadata payload from SDK config and user-provided data.
  ///
  /// [userInfo] contains user-specific fields (birthdate, gender, etc.)
  /// that are not part of SynheartConfig.
  static Map<String, dynamic> buildMetadata({
    required SynheartConfig config,
    required String deviceId,
    required String platform,
    required String osVersion,
    Map<String, dynamic>? userInfo,
    Map<String, dynamic>? deviceExtra,
  }) {
    final now = DateTime.now().toUtc().toIso8601String();

    return {
      'app': {
        'created_at': now,
        'app_id': config.appId,
        'app_name': config.appName,
        'app_version': config.appVersion,
        'category': config.category,
        'developer': config.developer,
        'extra_data': config.additionalAppMetadata,
      },
      'user': {
        'user_id': config.subjectId,
        'birthdate': userInfo?['birthdate'] ?? '',
        'gender': userInfo?['gender'] ?? '',
        'blood_type': userInfo?['blood_type'],
        'skin_type': userInfo?['skin_type'],
        'race': userInfo?['race'],
        'extra_data': userInfo?['extra_data'] ?? {},
      },
      'devices': [
        {
          'created_at': now,
          'device': {
            'device_id': deviceId,
            'device_type': userInfo?['device_type'] ?? 'Phone',
            'device_model': userInfo?['device_model'] ?? '',
            'platform': platform,
            'device_os_version': osVersion,
            'extra_data': deviceExtra ?? {},
          },
        },
      ],
    };
  }

  // ── Session payload ───────────────────────────────────────────────

  /// Build a session payload from SDK internal data collected during a session.
  static Map<String, dynamic> buildSession({
    required String sessionId,
    required String deviceId,
    required String appId,
    required String userId,
    required int startedAtMs,
    required int endedAtMs,
    required bool dataOnCloud,
    String? cohortId,
    Map<String, dynamic>? extraData,
    List<Map<String, dynamic>>? failures,
    required List<WearSample> wearSamples,
    required List<BehaviorEvent> behaviorEvents,
    required List<PhoneDataPoint> phoneDataPoints,
    Map<String, dynamic>? insightData,
    List<Map<String, dynamic>>? childWindows,
    int? previousSessionEndMs,
  }) {
    final startedAt = DateTime.fromMillisecondsSinceEpoch(startedAtMs, isUtc: true).toIso8601String();
    final endedAt = DateTime.fromMillisecondsSinceEpoch(endedAtMs, isUtc: true).toIso8601String();
    final durationMs = endedAtMs - startedAtMs;

    return {
      'id': sessionId,
      'session_metadata': {
        'device_id': deviceId,
        'app_id': appId,
        'user_id': userId,
        'started_at': startedAt,
        'ended_at': endedAt,
        'data_on_cloud': dataOnCloud,
        if (cohortId != null) 'cohort_id': cohortId,
        if (extraData != null) 'extra_data': extraData,
      },
      'session_failure': failures ?? [],
      'session_window': [
        _buildWindowNode(
          windowId: sessionId, // root window uses session ID
          parentId: null,
          startedAt: startedAt,
          endedAt: endedAt,
          durationMs: durationMs,
          wearSamples: wearSamples,
          behaviorEvents: behaviorEvents,
          phoneDataPoints: phoneDataPoints,
          insightData: insightData,
          children: childWindows ?? [],
          previousSessionEndMs: previousSessionEndMs,
        ),
      ],
    };
  }

  // ── Window node builder ───────────────────────────────────────────

  static Map<String, dynamic> _buildWindowNode({
    required String windowId,
    required String? parentId,
    required String startedAt,
    required String endedAt,
    required int durationMs,
    required List<WearSample> wearSamples,
    required List<BehaviorEvent> behaviorEvents,
    required List<PhoneDataPoint> phoneDataPoints,
    Map<String, dynamic>? insightData,
    List<Map<String, dynamic>> children = const [],
    int? previousSessionEndMs,
  }) {
    return {
      'id': windowId,
      'parent_id': parentId,
      'window_metadata': {
        'started_at': startedAt,
        'ended_at': endedAt,
        'duration_ms': durationMs,
      },
      'window_data': {
        'state_data': {
          'wear_data': _aggregateWearData(wearSamples),
          'behavior_data': _aggregateBehaviorData(
            behaviorEvents,
            phoneDataPoints,
            durationMs,
            previousSessionEndMs: previousSessionEndMs,
          ),
        },
        'insight_data': insightData ?? {},
      },
      'children': children,
    };
  }

  // ── Wear data aggregation ─────────────────────────────────────────

  static Map<String, dynamic> _aggregateWearData(List<WearSample> samples) {
    if (samples.isEmpty) {
      return {
        'has_wear_data': false,
        'hr_mean': null,
        'hrv_rmssd_mean': null,
      };
    }

    final hrSamples = samples.where((s) => s.hr != null).toList();
    final hrvSamples = samples.where((s) => s.hrvRmssd != null).toList();

    double? hrMean;
    double? hrMin;
    double? hrMax;
    if (hrSamples.isNotEmpty) {
      final hrs = hrSamples.map((s) => s.hr!).toList();
      hrMean = hrs.reduce((a, b) => a + b) / hrs.length;
      hrMin = hrs.reduce(min);
      hrMax = hrs.reduce(max);
    }

    double? hrvMean;
    if (hrvSamples.isNotEmpty) {
      final hrvs = hrvSamples.map((s) => s.hrvRmssd!).toList();
      hrvMean = hrvs.reduce((a, b) => a + b) / hrvs.length;
    }

    return {
      'has_wear_data': true,
      'hr_mean': hrMean,
      'hrv_rmssd_mean': hrvMean,
      if (hrMin != null) 'hr_min': hrMin,
      if (hrMax != null) 'hr_max': hrMax,
    };
  }

  // ── Behavior data aggregation ─────────────────────────────────────

  static Map<String, dynamic> _aggregateBehaviorData(
    List<BehaviorEvent> events,
    List<PhoneDataPoint> phonePoints,
    int durationMs, {
    int? previousSessionEndMs,
  }) {
    final durationSec = durationMs / 1000.0;
    if (durationSec <= 0) return _zeroBehaviorData();

    // Count event types
    int tapCount = 0;
    int scrollCount = 0;
    int keyDownCount = 0;
    int keyUpCount = 0;
    int appSwitchCount = 0;
    int notifReceived = 0;
    int notifOpened = 0;
    int callCount = 0;
    int screenOnCount = 0;

    final List<DateTime> keyDownTimestamps = [];
    final List<DateTime> tapTimestamps = [];

    for (final e in events) {
      switch (e.type) {
        case BehaviorEventType.tap:
          tapCount++;
          tapTimestamps.add(e.timestamp);
          break;
        case BehaviorEventType.scroll:
          scrollCount++;
          break;
        case BehaviorEventType.swipe:
          tapCount++; // counted as interaction
          break;
        case BehaviorEventType.keyDown:
          keyDownCount++;
          keyDownTimestamps.add(e.timestamp);
          break;
        case BehaviorEventType.keyUp:
          keyUpCount++;
          break;
        case BehaviorEventType.appSwitch:
          appSwitchCount++;
          break;
        case BehaviorEventType.notificationReceived:
          notifReceived++;
          break;
        case BehaviorEventType.notificationOpened:
          notifOpened++;
          break;
        case BehaviorEventType.call:
          callCount++;
          break;
        case BehaviorEventType.screenOn:
          screenOnCount++;
          break;
        case BehaviorEventType.screenOff:
          break;
      }
    }

    final totalEvents = events.length;
    final notifIgnored = notifReceived - notifOpened;
    final notifIgnoreRate = notifReceived > 0 ? notifIgnored / notifReceived : 0.0;

    // Phone context aggregation
    final motionPoints = phonePoints.where((p) => p.motionLevel != null).toList();
    final screenPoints = phonePoints.where((p) => p.screenOn != null).toList();
    final appSwitchPoints = phonePoints.where((p) => p.appSwitch == true).toList();
    final notifPoints = phonePoints.where((p) => p.notification == true).toList();

    // Typing session analysis
    final typingAnalysis = _analyzeTypingSessions(keyDownTimestamps, durationSec);

    // Compute behavioral metrics
    final interactionIntensity = totalEvents > 0
        ? (totalEvents / durationSec).clamp(0.0, 1.0)
        : 0.0;

    final taskSwitchRate = appSwitchCount / durationSec;

    // Idle ratio: time with no events
    final idleRatio = _computeIdleRatio(events, durationMs);

    // Active interaction time
    final activeTime = durationSec * (1.0 - idleRatio);

    // Burstiness
    final burstiness = _computeBurstiness(events, durationMs);

    // Notification load
    final notifLoad = notifReceived / max(durationSec / 60.0, 1.0);
    final normalizedNotifLoad = (notifLoad / 10.0).clamp(0.0, 1.0);

    // Focus hint (inverse of distraction)
    final distractionScore = _computeDistractionScore(
      appSwitchCount: appSwitchCount,
      notifIgnored: notifIgnored,
      notifReceived: notifReceived,
      scrollCount: scrollCount,
      idleRatio: idleRatio,
    );
    final focusHint = (1.0 - distractionScore).clamp(0.0, 1.0);

    // Deep focus blocks
    final deepFocusBlocks = _detectDeepFocusBlocks(events, durationMs);

    // Session spacing
    int sessionSpacing = 0;
    if (previousSessionEndMs != null) {
      final sessionStartMs = events.isNotEmpty
          ? events.first.timestamp.millisecondsSinceEpoch
          : 0;
      if (sessionStartMs > 0) {
        sessionSpacing = ((sessionStartMs - previousSessionEndMs) / 1000).round();
        if (sessionSpacing < 0) sessionSpacing = 0;
      }
    }

    // Micro session: < 30 seconds
    final microSession = durationMs < 30000;

    // Scroll jitter
    final scrollJitterRate = scrollCount > 0
        ? (scrollCount / max(totalEvents, 1)).clamp(0.0, 1.0)
        : 0.0;

    return {
      'micro_session': microSession,
      'session_spacing': sessionSpacing,
      'motion_state': _buildMotionState(motionPoints),
      'device_context': _buildDeviceContext(screenPoints),
      'activity_summary': {
        'total_events': totalEvents,
        'app_switch_count': appSwitchCount + appSwitchPoints.length,
      },
      'notification_summary': {
        'notification_count': notifReceived + notifPoints.length,
        'notification_ignored': notifIgnored,
        'notification_ignore_rate': notifIgnoreRate,
        'notification_clustering_index': _computeNotifClustering(events, durationMs),
        'call_count': callCount,
        'call_ignored': callCount, // conservative: calls during session assumed ignored
      },
      'system_state': {
        'internet_state': true, // not tracked at raw level yet
        'do_not_disturb': false,
        'charging': false,
      },
      'typing_session_summary': typingAnalysis,
      'behavioral_metrics': {
        'correction_rate': typingAnalysis['correction_key_count'] > 0
            ? (typingAnalysis['correction_key_count'] as int) /
                max(keyDownCount, 1)
            : 0.0,
        'editing_friction': typingAnalysis['clipboard_activity_rate'] as num,
        'interaction_intensity': interactionIntensity,
        'task_switch_rate': taskSwitchRate,
        'task_switch_cost': 0, // requires inter-switch timing analysis
        'idle_ratio': idleRatio,
        'active_interaction_time': activeTime,
        'burstiness': burstiness,
        'notification_load': normalizedNotifLoad,
        'fragmented_idle_ratio': _computeFragmentedIdleRatio(events, durationMs),
        'scroll_jitter_rate': scrollJitterRate,
        'distraction_score': distractionScore,
        'focus_hint': focusHint,
        'deep_focus_blocks': deepFocusBlocks,
      },
    };
  }

  // ── Typing session analysis ───────────────────────────────────────

  static Map<String, dynamic> _analyzeTypingSessions(
    List<DateTime> keyTimestamps,
    double durationSec,
  ) {
    if (keyTimestamps.isEmpty) {
      return {
        'correction_key_count': 0,
        'clipboard_copy_count': 0,
        'clipboard_paste_count': 0,
        'clipboard_activity_rate': 0.0,
        'typing_session_count': 0,
        'average_keystrokes_per_session': 0,
        'average_typing_session_duration': 0.0,
        'average_typing_speed': 0.0,
        'average_typing_gap': 0.0,
        'average_inter-tap_interval': 0.0,
        'average_typing_cadence_stability': 0.0,
        'average_burstiness_of_typing': 0.0,
        'total_typing_duration': 0.0,
        'active_typing_ratio': 0.0,
        'deep_typing_blocks': 0,
      };
    }

    // Group keystrokes into sessions (gap > 2s = new session)
    const sessionGapMs = 2000;
    final sorted = List<DateTime>.from(keyTimestamps)..sort();
    final sessions = <List<DateTime>>[
      [sorted.first]
    ];

    for (int i = 1; i < sorted.length; i++) {
      final gap = sorted[i].difference(sorted[i - 1]).inMilliseconds;
      if (gap > sessionGapMs) {
        sessions.add([sorted[i]]);
      } else {
        sessions.last.add(sorted[i]);
      }
    }

    // Inter-tap intervals
    final intervals = <double>[];
    for (int i = 1; i < sorted.length; i++) {
      intervals.add(sorted[i].difference(sorted[i - 1]).inMilliseconds / 1000.0);
    }

    final avgIti = intervals.isEmpty ? 0.0 : intervals.reduce((a, b) => a + b) / intervals.length;

    // Cadence stability (1 - coefficient of variation)
    double cadenceStability = 0.0;
    if (intervals.length > 1) {
      final mean = avgIti;
      final variance = intervals.map((i) => (i - mean) * (i - mean)).reduce((a, b) => a + b) / intervals.length;
      final std = sqrt(variance);
      cadenceStability = mean > 0 ? (1.0 - (std / mean)).clamp(0.0, 1.0) : 0.0;
    }

    // Session durations
    final sessionDurations = sessions.map((s) {
      if (s.length < 2) return 0.0;
      return s.last.difference(s.first).inMilliseconds / 1000.0;
    }).toList();
    final totalTypingDuration = sessionDurations.reduce((a, b) => a + b);

    // Session gaps
    final sessionGaps = <double>[];
    for (int i = 1; i < sessions.length; i++) {
      sessionGaps.add(sessions[i].first.difference(sessions[i - 1].last).inMilliseconds / 1000.0);
    }
    final avgGap = sessionGaps.isEmpty ? 0.0 : sessionGaps.reduce((a, b) => a + b) / sessionGaps.length;

    // Burstiness of typing
    final burstiness = sessions.length > 1
        ? (sessions.where((s) => s.length > 5).length / sessions.length).clamp(0.0, 1.0)
        : 0.0;

    return {
      'correction_key_count': 0, // not distinguishable from keyDown events alone
      'clipboard_copy_count': 0,
      'clipboard_paste_count': 0,
      'clipboard_activity_rate': 0.0,
      'typing_session_count': sessions.length,
      'average_keystrokes_per_session': (sorted.length / sessions.length).round(),
      'average_typing_session_duration': sessionDurations.isEmpty
          ? 0.0
          : totalTypingDuration / sessions.length,
      'average_typing_speed': totalTypingDuration > 0
          ? sorted.length / totalTypingDuration
          : 0.0,
      'average_typing_gap': avgGap,
      'average_inter-tap_interval': avgIti,
      'average_typing_cadence_stability': cadenceStability,
      'average_burstiness_of_typing': burstiness,
      'total_typing_duration': totalTypingDuration,
      'active_typing_ratio': durationSec > 0 ? (totalTypingDuration / durationSec).clamp(0.0, 1.0) : 0.0,
      'deep_typing_blocks': sessions.where((s) => s.length > 20).length,
    };
  }

  // ── Motion state ──────────────────────────────────────────────────

  static Map<String, dynamic> _buildMotionState(List<PhoneDataPoint> motionPoints) {
    if (motionPoints.isEmpty) {
      return {
        'state': ['unknown'],
        'major_state': 'unknown',
        'major_state_pct': 0.0,
        'ml_model': 'none',
        'confidence': 0.0,
      };
    }

    // Classify motion levels: <0.1 = stationary, <0.4 = walking, else running
    final states = <String>[];
    for (final p in motionPoints) {
      final level = p.motionLevel ?? 0.0;
      if (level < 0.1) {
        states.add('stationary');
      } else if (level < 0.4) {
        states.add('walking');
      } else {
        states.add('running');
      }
    }

    // Find major state
    final counts = <String, int>{};
    for (final s in states) {
      counts[s] = (counts[s] ?? 0) + 1;
    }
    final majorState = counts.entries.reduce((a, b) => a.value > b.value ? a : b).key;
    final majorPct = counts[majorState]! / states.length;

    // Deduplicate consecutive states
    final uniqueStates = <String>[states.first];
    for (int i = 1; i < states.length; i++) {
      if (states[i] != states[i - 1]) uniqueStates.add(states[i]);
    }

    return {
      'state': uniqueStates,
      'major_state': majorState,
      'major_state_pct': majorPct,
      'ml_model': 'motion_heuristic_v1',
      'confidence': majorPct, // higher majority = higher confidence
    };
  }

  // ── Device context ────────────────────────────────────────────────

  static Map<String, dynamic> _buildDeviceContext(List<PhoneDataPoint> screenPoints) {
    return {
      'avg_screen_brightness': 0.5, // not tracked at raw level
      'start_orientation': 'portrait', // not tracked at raw level
      'orientation_changes': 0,
    };
  }

  // ── Statistical helpers ───────────────────────────────────────────

  static double _computeIdleRatio(List<BehaviorEvent> events, int durationMs) {
    if (events.isEmpty || durationMs <= 0) return 1.0;

    // Idle = gaps > 5s between events
    const idleThresholdMs = 5000;
    final sorted = List<BehaviorEvent>.from(events)..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    int idleMs = 0;
    for (int i = 1; i < sorted.length; i++) {
      final gap = sorted[i].timestamp.difference(sorted[i - 1].timestamp).inMilliseconds;
      if (gap > idleThresholdMs) {
        idleMs += gap;
      }
    }

    return (idleMs / durationMs).clamp(0.0, 1.0);
  }

  static double _computeFragmentedIdleRatio(List<BehaviorEvent> events, int durationMs) {
    if (events.isEmpty || durationMs <= 0) return 0.0;

    // Fragmented idle = short idle periods (5-30s)
    const shortIdleMin = 5000;
    const shortIdleMax = 30000;
    final sorted = List<BehaviorEvent>.from(events)..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    int fragmentedMs = 0;
    for (int i = 1; i < sorted.length; i++) {
      final gap = sorted[i].timestamp.difference(sorted[i - 1].timestamp).inMilliseconds;
      if (gap >= shortIdleMin && gap <= shortIdleMax) {
        fragmentedMs += gap;
      }
    }

    return (fragmentedMs / durationMs).clamp(0.0, 1.0);
  }

  static double _computeBurstiness(List<BehaviorEvent> events, int durationMs) {
    if (events.length < 2 || durationMs <= 0) return 0.0;

    // Burstiness = variance-to-mean ratio of inter-event intervals
    final sorted = List<BehaviorEvent>.from(events)..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final intervals = <double>[];
    for (int i = 1; i < sorted.length; i++) {
      intervals.add(sorted[i].timestamp.difference(sorted[i - 1].timestamp).inMilliseconds.toDouble());
    }

    if (intervals.isEmpty) return 0.0;
    final mean = intervals.reduce((a, b) => a + b) / intervals.length;
    if (mean <= 0) return 0.0;
    final variance = intervals.map((i) => (i - mean) * (i - mean)).reduce((a, b) => a + b) / intervals.length;
    final std = sqrt(variance);

    // Fano factor normalized to 0-1
    return ((std / mean) / 2.0).clamp(0.0, 1.0);
  }

  static double _computeNotifClustering(List<BehaviorEvent> events, int durationMs) {
    final notifs = events.where((e) =>
        e.type == BehaviorEventType.notificationReceived ||
        e.type == BehaviorEventType.notificationOpened).toList();
    if (notifs.length < 2) return 0.0;

    // Clustering = proportion of notifications within 60s of each other
    notifs.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    int clustered = 0;
    for (int i = 1; i < notifs.length; i++) {
      if (notifs[i].timestamp.difference(notifs[i - 1].timestamp).inSeconds < 60) {
        clustered++;
      }
    }
    return (clustered / (notifs.length - 1)).clamp(0.0, 1.0);
  }

  static double _computeDistractionScore({
    required int appSwitchCount,
    required int notifIgnored,
    required int notifReceived,
    required int scrollCount,
    required double idleRatio,
  }) {
    // Weighted distraction factors
    final switchFactor = (appSwitchCount / 10.0).clamp(0.0, 1.0) * 0.3;
    final notifFactor = notifReceived > 0
        ? ((1.0 - notifIgnored / notifReceived) * 0.2)
        : 0.0;
    final idleFactor = idleRatio * 0.3;
    final scrollFactor = (scrollCount / 50.0).clamp(0.0, 1.0) * 0.2;

    return (switchFactor + notifFactor + idleFactor + scrollFactor).clamp(0.0, 1.0);
  }

  static List<Map<String, dynamic>> _detectDeepFocusBlocks(
    List<BehaviorEvent> events,
    int durationMs,
  ) {
    if (events.isEmpty) return [];

    // Deep focus = continuous activity for > 2 minutes with no idle > 10s
    const minBlockMs = 120000;
    const maxGapMs = 10000;

    final sorted = List<BehaviorEvent>.from(events)..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final blocks = <Map<String, dynamic>>[];

    var blockStart = sorted.first.timestamp;
    var blockEnd = sorted.first.timestamp;

    for (int i = 1; i < sorted.length; i++) {
      final gap = sorted[i].timestamp.difference(sorted[i - 1].timestamp).inMilliseconds;
      if (gap <= maxGapMs) {
        blockEnd = sorted[i].timestamp;
      } else {
        // End of block — check if long enough
        final blockDuration = blockEnd.difference(blockStart).inMilliseconds;
        if (blockDuration >= minBlockMs) {
          blocks.add({
            'started_at': blockStart.toUtc().toIso8601String(),
            'ended_at': blockEnd.toUtc().toIso8601String(),
            'duration_ms': blockDuration,
          });
        }
        blockStart = sorted[i].timestamp;
        blockEnd = sorted[i].timestamp;
      }
    }

    // Check final block
    final lastDuration = blockEnd.difference(blockStart).inMilliseconds;
    if (lastDuration >= minBlockMs) {
      blocks.add({
        'started_at': blockStart.toUtc().toIso8601String(),
        'ended_at': blockEnd.toUtc().toIso8601String(),
        'duration_ms': lastDuration,
      });
    }

    return blocks;
  }

  static Map<String, dynamic> _zeroBehaviorData() {
    return {
      'micro_session': false,
      'session_spacing': 0,
      'motion_state': {
        'state': ['unknown'],
        'major_state': 'unknown',
        'major_state_pct': 0.0,
        'ml_model': 'none',
        'confidence': 0.0,
      },
      'device_context': {
        'avg_screen_brightness': 0.0,
        'start_orientation': 'portrait',
        'orientation_changes': 0,
      },
      'activity_summary': {'total_events': 0, 'app_switch_count': 0},
      'notification_summary': {
        'notification_count': 0,
        'notification_ignored': 0,
        'notification_ignore_rate': 0.0,
        'notification_clustering_index': 0.0,
        'call_count': 0,
        'call_ignored': 0,
      },
      'system_state': {
        'internet_state': true,
        'do_not_disturb': false,
        'charging': false,
      },
      'typing_session_summary': {
        'correction_key_count': 0,
        'clipboard_copy_count': 0,
        'clipboard_paste_count': 0,
        'clipboard_activity_rate': 0.0,
        'typing_session_count': 0,
        'average_keystrokes_per_session': 0,
        'average_typing_session_duration': 0.0,
        'average_typing_speed': 0.0,
        'average_typing_gap': 0.0,
        'average_inter-tap_interval': 0.0,
        'average_typing_cadence_stability': 0.0,
        'average_burstiness_of_typing': 0.0,
        'total_typing_duration': 0.0,
        'active_typing_ratio': 0.0,
        'deep_typing_blocks': 0,
      },
      'behavioral_metrics': {
        'correction_rate': 0.0,
        'editing_friction': 0.0,
        'interaction_intensity': 0.0,
        'task_switch_rate': 0.0,
        'task_switch_cost': 0.0,
        'idle_ratio': 0.0,
        'active_interaction_time': 0.0,
        'burstiness': 0.0,
        'notification_load': 0.0,
        'fragmented_idle_ratio': 0.0,
        'scroll_jitter_rate': 0.0,
        'distraction_score': 0.0,
        'focus_hint': 0.0,
        'deep_focus_blocks': <Map<String, dynamic>>[],
      },
    };
  }
}
