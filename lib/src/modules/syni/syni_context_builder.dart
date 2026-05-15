import '../../artifacts/session_summary.dart';
import '../../core/logger.dart';
import '../../models/hsi_state.dart';
import '../../models/metric_event.dart' show SessionRange;
import '../../synheart.dart';

/// Builds the `HsiContext` JSON payload that conditions Syni inference.
///
/// This is the SDK's half of the Syni HSI contract: it gathers live HSI plus
/// stored session history and projects them into the reduced shape the
/// runtime's `HsiContext` expects (see syni-runtime `core/rust/src/prompt.rs`
/// — `current` = `StateSnapshot`, `history` = `StateHistory`).
///
/// Layering: the SDK *gathers* state; the runtime's `PromptBuilder` *renders*
/// it into conditioning text. Keep the JSON keys here in sync with the Rust
/// structs.
///
/// **Axis-agnostic.** The builder privileges no axis — it projects whatever
/// HSI axes / session means exist, generically. Which axis matters is the
/// active persona's concern, not the SDK's.
///
/// Every section degrades gracefully — if a data source is empty the
/// corresponding key is omitted, and the runtime renders nothing for it. A
/// fresh app with no sessions and no live HSI yields `null` (no context).
class SyniContextBuilder {
  SyniContextBuilder({
    HSIState? Function()? liveState,
    Future<List<SessionRecord>> Function({SessionRange? range})? listSessions,
    Future<Map<String, dynamic>?> Function(String sessionId)? sessionSummary,
    Future<List<Map<String, dynamic>>> Function(String sessionId)? hsiWindows,
  })  : _liveState = liveState ?? (() => Synheart.currentHSIState),
        _listSessions = listSessions ?? Synheart.listSessions,
        _sessionSummary = sessionSummary ?? Synheart.getSessionSummary,
        _hsiWindows = hsiWindows ?? ((id) => Synheart.getHSIWindows(id));

  final HSIState? Function() _liveState;
  final Future<List<SessionRecord>> Function({SessionRange? range})
      _listSessions;
  final Future<Map<String, dynamic>?> Function(String sessionId)
      _sessionSummary;
  final Future<List<Map<String, dynamic>>> Function(String sessionId)
      _hsiWindows;

  /// HSI 1.3 channel names we project, with their `(axis, channel)` location
  /// in the payload — see `hsi/schema/hsi-1.3.schema.json` (RFC-HSI-0010).
  /// Names match the runtime contract's `axis_means` keys.
  static const _channels = <String, ({String axis, String name})>{
    'focus': (axis: 'cognitive', name: 'focus'),
    'capacity': (axis: 'cognitive', name: 'capacity'),
    'arousal': (axis: 'affective', name: 'arousal'),
    'recovery': (axis: 'physiological', name: 'recovery'),
  };

  /// How many recent sessions to digest into the history block.
  ///
  /// Trade-off: more = richer reasoning, but ~30 tokens of prompt prefill
  /// per session, on every turn. With ~3-5 tok/sec prefill on phone CPU,
  /// each session costs ~6-10s of "Syni is thinking…" latency. 4 is the
  /// sweet spot for V1 — enough trend signal, bounded prefill.
  static const _historyDepth = 4;

  /// Build the `HsiContext` JSON. Returns `null` when there is genuinely
  /// nothing to contribute (no live HSI, no stored sessions).
  Future<Map<String, dynamic>?> build({String surface = 'coach'}) async {
    final ctx = <String, dynamic>{'surface': surface};

    final snapshot = _snapshotFromHsi(_liveState());
    if (snapshot != null) ctx['current'] = snapshot;

    final history = await _buildHistory();
    if (history != null) ctx['history'] = history;

    // `surface` alone isn't worth shipping — only return context if we have
    // real state to condition on.
    if (!ctx.containsKey('current') && !ctx.containsKey('history')) {
      SynheartLogger.log(
        '[syni] context builder: no live HSI, no session history — '
        'sending empty context',
      );
      return null;
    }
    final sessions =
        ((ctx['history'] as Map?)?['recent_sessions'] as List?) ?? const [];
    final withAxes = sessions
        .whereType<Map>()
        .where((m) => m['axis_means'] != null)
        .length;
    SynheartLogger.log(
      '[syni] context builder: current=${ctx.containsKey('current')} '
      'history_sessions=${sessions.length} with_axes=$withAxes',
    );
    final labPresent =
        (Synheart.labExportJson != null && Synheart.labExportJson!.isNotEmpty);
    SynheartLogger.log('[syni] lab_export_present=$labPresent');
    return ctx;
  }

  // ---------------------------------------------------------------------------
  // Current snapshot
  // ---------------------------------------------------------------------------

  /// Project a live [HSIState] into the runtime's `StateSnapshot` shape.
  /// Returns `null` when no axes carry readings.
  Map<String, dynamic>? _snapshotFromHsi(HSIState? state) {
    if (state == null) return null;
    final axes = state.hsi;
    final snapshot = <String, dynamic>{};

    void put(String key, HSIAxisValue? axis) {
      if (axis == null) return;
      snapshot[key] = {
        'value': axis.value,
        'confidence': axis.confidence,
      };
    }

    put('focus', axes.focus);
    put('capacity', axes.capacity);
    put('arousal', axes.arousal);

    if (snapshot.isEmpty) return null;
    snapshot['observed_at_utc'] =
        DateTime.fromMillisecondsSinceEpoch(state.timestampMs, isUtc: true)
            .toIso8601String();
    return snapshot;
  }

  // ---------------------------------------------------------------------------
  // Historical digest
  // ---------------------------------------------------------------------------

  /// Build the `StateHistory` block from stored sessions. Returns `null` when
  /// there are no usable session digests.
  ///
  /// Ships raw per-session digests (time + duration + per-axis means). The
  /// runtime / model does any time-of-day or trend reasoning — the SDK does
  /// not pre-compute axis-specific "peaks" or "trends".
  Future<Map<String, dynamic>?> _buildHistory() async {
    final List<SessionRecord> sessions;
    try {
      sessions = await _listSessions();
    } catch (_) {
      return null;
    }
    if (sessions.isEmpty) return null;

    // Newest first, capped.
    final recent = [...sessions]
      ..sort((a, b) => b.startUtc.compareTo(a.startUtc));

    final recentSessions = <Map<String, dynamic>>[];
    for (final s in recent.take(_historyDepth)) {
      recentSessions.add(await _digestSession(s));
    }
    if (recentSessions.isEmpty) return null;
    return {'recent_sessions': recentSessions};
  }

  /// Digest one session into a `{started_at_utc, duration_min?, axis_means?}`
  /// shape. Falls back to stored HSI windows when a session summary is
  /// unavailable; degrades to a timestamp-only digest on parse failure.
  Future<Map<String, dynamic>> _digestSession(SessionRecord s) async {
    final startedAt =
        DateTime.fromMillisecondsSinceEpoch(s.startUtc, isUtc: true);
    final digest = <String, dynamic>{
      'started_at_utc': startedAt.toIso8601String(),
    };

    try {
      final raw = await _sessionSummary(s.sessionId);
      if (raw != null) {
        final summary = SessionSummaryArtifact.fromJson(raw);

        final durMs = summary.session.endMs - summary.session.startMs;
        if (durMs > 0) {
          digest['duration_min'] = (durMs / 60000).round();
        }

        // Skip `sleep` (daily, not per-session), null axes (no readings),
        // and axes whose mean is 0 (would mislead the model).
        final agg = summary.aggregates;
        final means = <String, double>{};
        for (final axis in agg.keys) {
          if (axis == 'sleep') continue;
          final a = agg[axis];
          if (a == null || a.mean == 0) continue;
          means[axis] = a.mean;
        }
        if (means.isNotEmpty) {
          digest['axis_means'] = means;
        }
        SynheartLogger.log(
          '[syni] session ${s.sessionId}: summary path '
          '(axes=${means.length}/${agg.keys.length}, '
          'dur=${digest['duration_min'] ?? 0}min)',
        );
        return digest;
      }

      // Fallback when the summary isn't persisted: aggregate axes from the
      // per-window HSI payloads instead.
      final windows = await _hsiWindows(s.sessionId);
      if (windows.isEmpty) {
        SynheartLogger.log(
          '[syni] session ${s.sessionId}: no summary, no HSI windows',
        );
        return digest;
      }

      final means = _aggregateAxesFromWindows(windows);
      if (means.isNotEmpty) digest['axis_means'] = means;
      // HSI windows are 60s each by convention — count ≈ minutes.
      digest['duration_min'] = windows.length;
      SynheartLogger.log(
        '[syni] session ${s.sessionId}: aggregated ${windows.length} HSI '
        'windows → ${means.length} axes (no summary path)',
      );
    } catch (e) {
      SynheartLogger.log(
        '[syni] session ${s.sessionId}: digest failed: $e',
      );
    }

    return digest;
  }

  /// Mean per-channel score across the HSI frames buffered inside HSI
  /// windows. Each frame is weighted equally.
  static Map<String, double> _aggregateAxesFromWindows(
    List<Map<String, dynamic>> windows,
  ) {
    final sums = <String, double>{};
    final counts = <String, int>{};
    for (final w in windows) {
      for (final frame in _findFrames(w)) {
        final axes = _findAxes(frame);
        if (axes == null) continue;
        for (final entry in _channels.entries) {
          final outName = entry.key;
          final loc = entry.value;
          final readings = axes[loc.axis];
          if (readings is! List) continue;
          for (final r in readings) {
            if (r is! Map) continue;
            if (r['name'] != loc.name) continue;
            final score = (r['score'] as num?)?.toDouble();
            if (score == null) break;
            sums[outName] = (sums[outName] ?? 0.0) + score;
            counts[outName] = (counts[outName] ?? 0) + 1;
            break;
          }
        }
      }
    }
    final out = <String, double>{};
    sums.forEach((k, v) => out[k] = v / counts[k]!);
    return out;
  }

  /// Extract HSI frame payloads from one window envelope. Normalizes the
  /// several envelope shapes the runtime can emit into a flat frame list.
  static List<Map<String, dynamic>> _findFrames(Map<String, dynamic> w) {
    final win = w['window'];
    if (win is Map) {
      final hsi = win['hsi'];
      if (hsi is List) {
        return hsi.whereType<Map<String, dynamic>>().toList();
      }
      if (hsi is Map<String, dynamic>) return [hsi];
    }
    if (w['axes'] is Map) return [w];
    final hsi = w['hsi'];
    if (hsi is List) return hsi.whereType<Map<String, dynamic>>().toList();
    if (hsi is Map<String, dynamic>) return [hsi];
    return const [];
  }

  /// Locate the `axes` map inside a single HSI frame.
  static Map? _findAxes(Map<String, dynamic> frame) {
    if (frame['axes'] is Map) return frame['axes'] as Map;
    final hsi = frame['hsi'];
    if (hsi is Map && hsi['axes'] is Map) return hsi['axes'] as Map;
    if (hsi is Map) return hsi;
    return null;
  }
}
