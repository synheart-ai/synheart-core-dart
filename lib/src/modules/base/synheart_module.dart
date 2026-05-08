/// Base interface for all Synheart modules
///
/// Each module in the Core SDK (Wear, Phone, Behavior, HSI Runtime, etc.)
/// extends this interface to ensure consistent lifecycle management.
abstract class SynheartModule {
  /// Module identifier
  String get moduleId;

  /// Current module status
  ModuleStatus get status;

  /// Whether this module is currently enabled
  bool get isEnabled;

  /// Initialize the module with required dependencies
  Future<void> initialize();

  /// Start the module's operation
  Future<void> start();

  /// Stop the module's operation (can be restarted)
  Future<void> stop();

  /// Dispose of all resources (final cleanup)
  Future<void> dispose();
}

/// Module lifecycle status
enum ModuleStatus {
  /// Module has not been initialized
  uninitialized,

  /// Module is initializing
  initializing,

  /// Module is initialized but not started
  initialized,

  /// Module is starting
  starting,

  /// Module is running
  running,

  /// Module is stopping
  stopping,

  /// Module is stopped
  stopped,

  /// Module has encountered an error
  error,

  /// Module is disposed
  disposed,
}

/// Exception thrown by modules
class ModuleException implements Exception {
  final String moduleId;
  final String message;
  final Object? cause;
  final StackTrace? stackTrace;

  ModuleException(this.moduleId, this.message, {this.cause, this.stackTrace});

  @override
  String toString() {
    final buffer = StringBuffer('ModuleException [$moduleId]: $message');
    if (cause != null) {
      buffer.write('\nCaused by: $cause');
    }
    return buffer.toString();
  }
}

/// Base implementation of SynheartModule with common functionality
abstract class BaseSynheartModule implements SynheartModule {
  ModuleStatus _status = ModuleStatus.uninitialized;

  @override
  ModuleStatus get status => _status;

  @override
  bool get isEnabled => _status == ModuleStatus.running;

  /// Set the module status and notify listeners
  void setStatus(ModuleStatus newStatus) {
    _status = newStatus;
  }

  @override
  Future<void> initialize() async {
    if (_status != ModuleStatus.uninitialized) {
      throw ModuleException(moduleId, 'Module already initialized');
    }

    try {
      setStatus(ModuleStatus.initializing);
      await onInitialize();
      setStatus(ModuleStatus.initialized);
    } catch (e, stack) {
      setStatus(ModuleStatus.error);
      throw ModuleException(
        moduleId,
        'Failed to initialize',
        cause: e,
        stackTrace: stack,
      );
    }
  }

  @override
  Future<void> start() async {
    if (_status != ModuleStatus.initialized &&
        _status != ModuleStatus.stopped) {
      throw ModuleException(
        moduleId,
        'Module must be initialized or stopped before starting',
      );
    }

    try {
      setStatus(ModuleStatus.starting);
      await onStart();
      setStatus(ModuleStatus.running);
    } catch (e, stack) {
      setStatus(ModuleStatus.error);
      throw ModuleException(
        moduleId,
        'Failed to start',
        cause: e,
        stackTrace: stack,
      );
    }
  }

  @override
  Future<void> stop() async {
    if (_status != ModuleStatus.running) {
      throw ModuleException(moduleId, 'Module is not running');
    }

    try {
      setStatus(ModuleStatus.stopping);
      await onStop();
      setStatus(ModuleStatus.stopped);
    } catch (e, stack) {
      setStatus(ModuleStatus.error);
      throw ModuleException(
        moduleId,
        'Failed to stop',
        cause: e,
        stackTrace: stack,
      );
    }
  }

  @override
  Future<void> dispose() async {
    try {
      if (_status == ModuleStatus.running) {
        await stop();
      }
      await onDispose();
      setStatus(ModuleStatus.disposed);
    } catch (e, stack) {
      setStatus(ModuleStatus.error);
      throw ModuleException(
        moduleId,
        'Failed to dispose',
        cause: e,
        stackTrace: stack,
      );
    }
  }

  /// Called during initialization
  Future<void> onInitialize();

  /// Called when starting the module
  Future<void> onStart();

  /// Called when stopping the module
  Future<void> onStop();

  /// Called during disposal
  Future<void> onDispose();
}
