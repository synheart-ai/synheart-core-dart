import 'synheart_module.dart';

/// Manages the lifecycle of all Synheart modules
///
/// Responsibilities:
/// - Initialize modules in correct order
/// - Handle module dependencies
/// - Coordinate module lifecycle
/// - Handle errors and recovery
class ModuleManager {
  final Map<String, SynheartModule> _modules = {};
  final Map<String, List<String>> _dependencies = {};
  bool _isInitialized = false;

  /// Register a module with optional dependencies
  void registerModule(
    SynheartModule module, {
    List<String>? dependsOn,
  }) {
    if (_modules.containsKey(module.moduleId)) {
      throw ModuleException(
        module.moduleId,
        'Module already registered',
      );
    }

    _modules[module.moduleId] = module;
    if (dependsOn != null && dependsOn.isNotEmpty) {
      _dependencies[module.moduleId] = dependsOn;
    }
  }

  /// Get a module by ID
  T? getModule<T extends SynheartModule>(String moduleId) {
    return _modules[moduleId] as T?;
  }

  /// Initialize all registered modules in dependency order
  Future<void> initializeAll() async {
    if (_isInitialized) {
      throw Exception('Modules already initialized');
    }

    final initOrder = _resolveInitializationOrder();

    for (final moduleId in initOrder) {
      final module = _modules[moduleId];
      if (module != null) {
        await module.initialize();
      }
    }

    _isInitialized = true;
  }

  /// Start all modules in dependency order
  Future<void> startAll() async {
    if (!_isInitialized) {
      throw Exception('Modules must be initialized before starting');
    }

    final startOrder = _resolveInitializationOrder();

    for (final moduleId in startOrder) {
      final module = _modules[moduleId];
      if (module != null && module.status == ModuleStatus.initialized) {
        await module.start();
      }
    }
  }

  /// Stop all modules in reverse dependency order
  Future<void> stopAll() async {
    final stopOrder = _resolveInitializationOrder().reversed.toList();

    for (final moduleId in stopOrder) {
      final module = _modules[moduleId];
      if (module != null && module.status == ModuleStatus.running) {
        try {
          await module.stop();
        } catch (e) {
          // Log error but continue stopping other modules
          print('Error stopping module $moduleId: $e');
        }
      }
    }
  }

  /// Dispose all modules in reverse dependency order
  Future<void> disposeAll() async {
    final disposeOrder = _resolveInitializationOrder().reversed.toList();

    for (final moduleId in disposeOrder) {
      final module = _modules[moduleId];
      if (module != null) {
        try {
          await module.dispose();
        } catch (e) {
          // Log error but continue disposing other modules
          print('Error disposing module $moduleId: $e');
        }
      }
    }

    _modules.clear();
    _dependencies.clear();
    _isInitialized = false;
  }

  /// Get status of all modules
  Map<String, ModuleStatus> getModuleStatuses() {
    return Map.fromEntries(
      _modules.entries.map((e) => MapEntry(e.key, e.value.status)),
    );
  }

  /// Resolve the initialization order based on dependencies
  List<String> _resolveInitializationOrder() {
    final order = <String>[];
    final visited = <String>{};
    final visiting = <String>{};

    void visit(String moduleId) {
      if (visited.contains(moduleId)) return;

      if (visiting.contains(moduleId)) {
        throw Exception('Circular dependency detected for module: $moduleId');
      }

      visiting.add(moduleId);

      // Visit dependencies first
      final deps = _dependencies[moduleId] ?? [];
      for (final dep in deps) {
        if (!_modules.containsKey(dep)) {
          throw Exception(
            'Module $moduleId depends on $dep, but $dep is not registered',
          );
        }
        visit(dep);
      }

      visiting.remove(moduleId);
      visited.add(moduleId);
      order.add(moduleId);
    }

    // Visit all modules
    for (final moduleId in _modules.keys) {
      visit(moduleId);
    }

    return order;
  }
}
