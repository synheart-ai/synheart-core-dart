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
  ///
  /// Runtimes before 0.20.0 inverted this in both directions: a permanent
  /// rejection reported `true`, so auto-retrying hosts looped on a 403, and a
  /// recoverable attestation blip reported `false`, so hosts gave up on
  /// something that would have worked seconds later. Both are correct from
  /// 0.20.0 on, so honouring this field is now the right behaviour.
  final bool retryable;

  /// Closed-set token narrowing the cause, or null when the runtime gave none
  /// (including any runtime older than 0.20.0 — absence is normal, not an
  /// error).
  ///
  /// `transient` · `timeout` · `quota` · `unsupported` · `misconfigured` ·
  /// `server_transient` · `policy` · `unknown`.
  ///
  /// This is the field worth branching on. [code] says a registration failed;
  /// `reason` says whether to retry, degrade to local-only permanently, or wake
  /// a developer — `unsupported` means stop asking even across relaunches,
  /// while `misconfigured` means a human has to fix something.
  final String? reason;

  /// Suggested backoff before retrying. Null unless [retryable].
  final int? retryAfterMs;

  /// Diagnostics only — `phase`, `http_status`, `server_code`. Log it; never
  /// branch on it. Its shape is not part of the contract.
  final Map<String, dynamic>? detail;

  const SyncNativeError({
    required this.code,
    required this.message,
    this.retryable = false,
    this.reason,
    this.retryAfterMs,
    this.detail,
  });

  /// Parse the `error` object of a native failure envelope. Missing fields fall
  /// back to a safe [unknown] shape so a malformed payload never throws here.
  ///
  /// The three fields below are optional in both directions: the runtime omits
  /// them rather than sending null, and an older runtime never sends them at
  /// all. A new SDK against an old runtime and an old SDK against a new one
  /// both work.
  factory SyncNativeError.fromMap(Map<String, dynamic> error) {
    final code = error['code'];
    final message = error['message'];
    final retryable = error['retryable'];
    final reason = error['reason'];
    final retryAfterMs = error['retry_after_ms'];
    final detail = error['detail'];
    return SyncNativeError(
      code: code is String && code.isNotEmpty ? code : 'UNKNOWN',
      message: message is String && message.isNotEmpty
          ? message
          : 'An unexpected error occurred.',
      retryable: retryable is bool ? retryable : false,
      reason: reason is String && reason.isNotEmpty ? reason : null,
      // Tolerate a JSON number that decoded as double — the envelope crosses
      // an FFI JSON boundary, so an integral value is not guaranteed to arrive
      // as int.
      retryAfterMs: retryAfterMs is int
          ? retryAfterMs
          : (retryAfterMs is num ? retryAfterMs.toInt() : null),
      detail: detail is Map<String, dynamic>
          ? detail
          : (detail is Map ? Map<String, dynamic>.from(detail) : null),
    );
  }

  /// Fallback used when a failure envelope is present but malformed.
  factory SyncNativeError.unknown() => const SyncNativeError(
    code: 'UNKNOWN',
    message: 'An unexpected error occurred.',
  );

  /// Registration failed because the device could produce no attestation
  /// material, and it never will on this hardware — no Play Services, a
  /// de-Googled ROM, an emulator, the iOS Simulator.
  ///
  /// Hosts should degrade to local-only and stop asking, including across
  /// relaunches.
  bool get isUnsupported => reason == 'unsupported';

  /// The attestation setup itself is wrong — not linked in Play Console, wrong
  /// cloud project number, callbacks unwired. Retrying cannot fix it; surface
  /// it to a developer.
  bool get isMisconfigured => reason == 'misconfigured';

  /// The server refused this device permanently. Distinct from
  /// [isUnsupported]: the device could attest, the server declined.
  bool get isPolicyRefusal => reason == 'policy';

  @override
  String toString() {
    // `reason` is included deliberately: this string is what lands in crash
    // logs, and without it every attestation failure reads identically.
    final buf = StringBuffer('SyncNativeError($code): $message');
    if (reason != null) buf.write(' [reason: $reason]');
    buf.write(' (retryable: $retryable');
    if (retryAfterMs != null) buf.write(', retryAfterMs: $retryAfterMs');
    buf.write(')');
    return buf.toString();
  }
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
  String? get reason => error.reason;
  int? get retryAfterMs => error.retryAfterMs;
  Map<String, dynamic>? get detail => error.detail;

  bool get isUnsupported => error.isUnsupported;
  bool get isMisconfigured => error.isMisconfigured;
  bool get isPolicyRefusal => error.isPolicyRefusal;

  @override
  String toString() => 'SyncNativeException: $error';
}
