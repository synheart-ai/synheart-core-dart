import 'dart:async';
import 'package:synheart_session/synheart_session.dart';
import '../../core/logger.dart';

/// Thin adapter around [SynheartSession] for watch-based session management.
///
/// Provides:
/// - Watch session start/stop (relayed to companion watch via Wearable Data Layer)
/// - Watch connectivity status
/// - Stream of [SessionEvent]s from the watch
///
/// The underlying [SynheartSession] is composed, not merged — the session SDK
/// remains standalone and can be used independently.
class WatchSessionModule {
  SynheartSession? _session;
  StreamSubscription<SessionEvent>? _activeSubscription;
  String? _activeSessionId;

  final StreamController<SessionEvent> _eventController =
      StreamController<SessionEvent>.broadcast();

  /// Stream of session events from the active watch session.
  Stream<SessionEvent> get events => _eventController.stream;

  /// Whether a watch session is currently active.
  bool get isActive => _activeSessionId != null;

  /// The active session ID, if any.
  String? get activeSessionId => _activeSessionId;

  /// Initialize the module (creates the underlying [SynheartSession]).
  void initialize() {
    _session ??= SynheartSession();
    SynheartLogger.log('[WatchSessionModule] Initialized');
  }

  /// Query watch connectivity status.
  ///
  /// Returns null if the module has not been initialized.
  Future<WatchStatus?> getWatchStatus() async {
    if (_session == null) {
      SynheartLogger.log(
        '[WatchSessionModule] Not initialized — cannot query watch status',
      );
      return null;
    }
    return _session!.getWatchStatus();
  }

  /// Start a watch session with the given [config].
  ///
  /// Returns a broadcast stream of [SessionEvent]s. The same events are also
  /// emitted on [events].
  ///
  /// Throws [StateError] if a session is already active.
  Stream<SessionEvent> startSession(SessionConfig config) {
    if (_session == null) {
      throw StateError(
        'WatchSessionModule not initialized. Call initialize() first.',
      );
    }
    if (_activeSessionId != null) {
      throw StateError(
        'A watch session is already active (id: $_activeSessionId). '
        'Stop it before starting a new one.',
      );
    }

    _activeSessionId = config.sessionId;
    SynheartLogger.log(
      '[WatchSessionModule] Starting session ${config.sessionId} '
      '(mode: ${config.mode.value}, duration: ${config.durationSec}s)',
    );

    final stream = _session!.startSession(config);

    _activeSubscription = stream.listen(
      (event) {
        if (!_eventController.isClosed) {
          _eventController.add(event);
        }

        if (event is SessionSummary || event is SessionError) {
          SynheartLogger.log(
            '[WatchSessionModule] Session ${event.sessionId} ended '
            '(${event.runtimeType})',
          );
          _cleanup();
        }
      },
      onError: (Object error) {
        SynheartLogger.log(
          '[WatchSessionModule] Stream error: $error',
          error: error,
        );
        if (!_eventController.isClosed) {
          _eventController.addError(error);
        }
      },
      onDone: _cleanup,
    );

    return _eventController.stream;
  }

  /// Stop the active watch session.
  ///
  /// No-op if no session is active.
  Future<void> stopSession() async {
    final id = _activeSessionId;
    if (id == null || _session == null) return;

    SynheartLogger.log('[WatchSessionModule] Stopping session $id');
    await _session!.stopSession(id);
  }

  /// Dispose all resources. After this call the module cannot be reused.
  void dispose() {
    _activeSubscription?.cancel();
    _activeSubscription = null;
    _activeSessionId = null;
    _session?.dispose();
    _session = null;
    _eventController.close();
    SynheartLogger.log('[WatchSessionModule] Disposed');
  }

  void _cleanup() {
    _activeSubscription?.cancel();
    _activeSubscription = null;
    _activeSessionId = null;
  }
}
