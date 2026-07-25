/// Deterministic error codes for Synheart Core.
class SynheartError implements Exception {
  final String code;
  final String message;

  const SynheartError(this.code, this.message);

  @override
  String toString() => 'SynheartError($code): $message';

  static const notConfigured = SynheartError(
    'ERR_NOT_CONFIGURED',
    'Synheart.configure() must be called before this operation.',
  );

  static const invalidMode = SynheartError(
    'ERR_INVALID_MODE',
    'The specified mode is not valid for this operation.',
  );

  static const researchNotAllowed = SynheartError(
    'ERR_RESEARCH_NOT_ALLOWED',
    'Research mode requires privacy.allowResearch to be true.',
  );

  static const sessionNotFound = SynheartError(
    'ERR_SESSION_NOT_FOUND',
    'No session found with the given session_id.',
  );

  static const sessionActive = SynheartError(
    'ERR_SESSION_ACTIVE',
    'Cannot start a new session while one is already active.',
  );

  static const noActiveSession = SynheartError(
    'ERR_NO_ACTIVE_SESSION',
    'No active session. Call startSession() first.',
  );

  static const storageDisabled = SynheartError(
    'ERR_STORAGE_DISABLED',
    'Storage is disabled in the current configuration.',
  );

  static const syncDisabled = SynheartError(
    'ERR_SYNC_DISABLED',
    'Sync is not enabled in the current configuration.',
  );

  static const cryptoKeyUnavailable = SynheartError(
    'ERR_CRYPTO_KEY_UNAVAILABLE',
    'Encryption key is not available.',
  );

  static const modeForbidsStream = SynheartError(
    'ERR_MODE_FORBIDS_STREAM',
    'The current mode does not allow this stream type.',
  );
}

/// A structured failure returned by a native sync operation.
///
/// The native runtime now reports sync failures as a consistent envelope
/// (`{"ok": false, "error": {"code", "message", "retryable"}}`) instead of a
/// bare null, so the host keeps the exact failure reason. [code] is a stable,
/// machine-readable string (e.g. `DEVICE_REGISTRATION_REQUIRED`, `NETWORK`);
/// [message] is a safe, human-readable string suitable for display; sensitive
/// internal detail stays in the native diagnostic logs and never reaches here.
class SyncNativeError {
  /// Stable machine-readable code, e.g. `DEVICE_REGISTRATION_REQUIRED`.
  final String code;

  /// Safe, user-facing message from the native layer.
  final String message;

  /// Whether retrying the same call unchanged may succeed (transient failure).
  final bool retryable;

  const SyncNativeError({
    required this.code,
    required this.message,
    this.retryable = false,
  });

  /// Parse the `error` object of a native failure envelope. Missing fields fall
  /// back to a safe [unknown] shape so a malformed payload never throws here.
  factory SyncNativeError.fromMap(Map<String, dynamic> error) {
    final code = error['code'];
    final message = error['message'];
    final retryable = error['retryable'];
    return SyncNativeError(
      code: code is String && code.isNotEmpty ? code : 'UNKNOWN',
      message: message is String && message.isNotEmpty
          ? message
          : 'An unexpected error occurred.',
      retryable: retryable is bool ? retryable : false,
    );
  }

  /// Fallback used when a failure envelope is present but malformed.
  factory SyncNativeError.unknown() => const SyncNativeError(
    code: 'UNKNOWN',
    message: 'An unexpected error occurred.',
  );

  @override
  String toString() =>
      'SyncNativeError($code): $message (retryable: $retryable)';
}

/// Thrown by the sync bridge methods when the native layer reports a failure
/// envelope. Carries the structured [error] so the host can render
/// cause-specific copy (and decide whether to offer a retry) instead of a
/// generic "sync engine not ready" message.
class SyncNativeException implements Exception {
  final SyncNativeError error;

  const SyncNativeException(this.error);

  String get code => error.code;
  String get message => error.message;
  bool get retryable => error.retryable;

  @override
  String toString() => 'SyncNativeException: $error';
}
