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
  })  : _liveState = liveState ?? (() => Synheart.currentHSIState),
        _listSessions = listSessions ?? Synheart.listSessions,
        _sessionSummary = sessionSummary ?? Synheart.getSessionSummary;

  final HSIState? Function() _liveState;
  final Future<List<SessionRecord>> Function({SessionRange? range})
      _listSessions;
  final Future<Map<String, dynamic>?> Function(String sessionId)
      _sessionSummary;

  /// How many recent sessions to digest into the history block.
  static const _historyDepth = 8;

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
    SynheartLogger.log(
      '[syni] context builder: current=${ctx.containsKey('current')} '
      'history_sessions=${(ctx['history'] as Map?)?['recent_sessions'] is List ? ((ctx['history'] as Map)['recent_sessions'] as List).length : 0}',
    );
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
    // NOTE: HSIAxes has no `recovery` axis today — the runtime's
    // StateSnapshot.recovery stays null until the engine exposes it
    // (e.g. via SRM). Intentionally omitted rather than faked.

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

  /// Digest one session into the runtime's `SessionDigest` shape:
  /// `{started_at_utc, duration_min?, axis_means: {focus: 0.6, ...}}`.
  ///
  /// Parses the typed [SessionSummaryArtifact] — duration from the session
  /// window, axis means from `aggregates.{focus,capacity,arousal}.mean`. If
  /// the summary is missing or malformed, the digest carries the timestamp
  /// only (degrades gracefully).
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

        // Per-axis means. `sleep` is a daily measure, not meaningfully a
        // per-(focus-)session aggregate — omit it here.
        final agg = summary.aggregates;
        digest['axis_means'] = <String, double>{
          'focus': agg.focus.mean,
          'capacity': agg.capacity.mean,
          'arousal': agg.arousal.mean,
        };
      }
    } catch (e) {
      // Summary unavailable or shape mismatch — keep timestamp-only digest.
      SynheartLogger.log('[syni] session digest failed for ${s.sessionId}: $e');
    }

    return digest;
  }
}
