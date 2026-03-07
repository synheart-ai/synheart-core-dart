/// Deterministic error codes for Synheart Core.
///
/// See RFC-CORE-0007 Section 14.
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
