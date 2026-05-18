import '../config/synheart_mode.dart';

/// A handle to an active or completed session.
///
/// Returned by [Synheart.startSession] and [Synheart.currentSession].
class SessionHandle {
  final String sessionId;
  final int startedAtMs;
  final SynheartMode mode;

  const SessionHandle({
    required this.sessionId,
    required this.startedAtMs,
    required this.mode,
  });

  @override
  String toString() =>
      'SessionHandle(sessionId: $sessionId, mode: ${mode.name}, startedAtMs: $startedAtMs)';
}
