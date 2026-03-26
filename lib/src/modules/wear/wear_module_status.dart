/// Status events emitted by [WearModule] to surface initialization,
/// permission, and streaming outcomes that would otherwise be silent.
///
/// Callers that don't subscribe to the status stream are unaffected —
/// this is purely additive.
enum WearModuleStatusType {
  /// A wear source initialized successfully.
  sourceInitialized,

  /// A wear source failed to initialize (non-permission error).
  sourceInitFailed,

  /// Permissions were denied or missing for a wear source.
  permissionDenied,

  /// An error occurred on the sample stream from a wear source.
  streamingError,

  /// Data collection started successfully.
  dataCollectionStarted,

  /// Data collection stopped (consent revoked or explicit stop).
  dataCollectionStopped,

  /// Consent stream encountered an error.
  consentStreamError,
}

class WearModuleStatus {
  final WearModuleStatusType type;

  /// Optional source identifier (e.g. "appleHealth", "mock").
  final String? source;

  /// The error, if this is a failure status.
  final Object? error;

  /// Human-readable message for logging / debugging.
  final String? message;

  const WearModuleStatus({
    required this.type,
    this.source,
    this.error,
    this.message,
  });

  bool get isError =>
      type == WearModuleStatusType.sourceInitFailed ||
      type == WearModuleStatusType.permissionDenied ||
      type == WearModuleStatusType.streamingError ||
      type == WearModuleStatusType.consentStreamError;

  @override
  String toString() =>
      'WearModuleStatus($type${source != null ? ', source: $source' : ''}'
      '${message != null ? ', $message' : ''}'
      '${error != null ? ', error: $error' : ''})';
}
