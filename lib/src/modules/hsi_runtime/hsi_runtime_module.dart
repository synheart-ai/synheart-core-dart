import 'dart:async';
import 'package:rxdart/rxdart.dart';
import '../../core/logger.dart';
import '../base/synheart_module.dart';
import '../interfaces/feature_providers.dart';
import '../../models/hsv.dart';
import 'window_scheduler.dart';
import 'channel_collector.dart';
import 'fusion_engine.dart';

/// HSI Runtime Module
///
/// Orchestrates the HSI pipeline:
/// 1. Schedules windows (30s, 5m, 1h, 24h)
/// 2. Collects features from Wear, Phone, Behavior
/// 3. Fuses features into HSI (state axes, indices, embeddings)
/// 4. Publishes HSI updates
///
/// IMPORTANT: This module does NOT include emotion or focus interpretation.
/// Those are optional downstream modules that consume HSI output.
class HSIRuntimeModule extends BaseSynheartModule {
  @override
  String get moduleId => 'hsi_runtime';

  final ChannelCollector _collector;
  final FusionEngine _fusion = FusionEngine();

  WindowScheduler? _scheduler;

  final BehaviorSubject<HumanStateVector> _hsiStream =
      BehaviorSubject<HumanStateVector>();

  HSIRuntimeModule({required ChannelCollector collector})
    : _collector = collector;

  /// Stream of HSI updates (state representation only)
  ///
  /// HSI contains:
  /// - State axes (affect, engagement, activity, context)
  /// - State indices (arousalIndex, engagementStability, etc.)
  /// - 64D state embedding
  ///
  /// HSI does NOT contain interpretation (emotion, focus).
  Stream<HumanStateVector> get hsiStream => _hsiStream.stream;

  /// Get current HSI state
  HumanStateVector? get currentState =>
      _hsiStream.hasValue ? _hsiStream.value : null;

  @override
  Future<void> onInitialize() async {
    SynheartLogger.log('[HSIRuntime] Initializing HSI Runtime...');
    // No emotion/focus heads here - they're optional modules
  }

  @override
  Future<void> onStart() async {
    SynheartLogger.log('[HSIRuntime] Starting HSI Runtime...');

    // Start window scheduler
    _scheduler = WindowScheduler(
      onWindow: (window) {
        // Only compute for 30s window (primary window)
        if (window == WindowType.window30s) {
          _computeState(window);
        }
      },
    );

    _scheduler!.start();
    SynheartLogger.log('[HSIRuntime] HSI Runtime started');
  }

  @override
  Future<void> onStop() async {
    SynheartLogger.log('[HSIRuntime] Stopping HSI Runtime...');

    _scheduler?.stop();
    _scheduler = null;
  }

  @override
  Future<void> onDispose() async {
    SynheartLogger.log('[HSIRuntime] Disposing HSI Runtime...');

    await _hsiStream.close();
  }

  /// Compute HSI state for a window
  Future<void> _computeState(WindowType window) async {
    try {
      // Collect features from all modules
      final features = _collector.collect(window);

      if (!features.hasAnyFeatures) {
        SynheartLogger.log('[HSIRuntime] No features available for $window');
        return;
      }

      // Fuse into HSI (state representation)
      final hsi = await _fusion.fuse(
        features,
        window,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      // Emit HSI (state representation only, no interpretation)
      _hsiStream.add(hsi);

      SynheartLogger.log('[HSIRuntime] Computed HSI for $window');
    } catch (e, stack) {
      SynheartLogger.log(
        '[HSIRuntime] Error computing HSI: $e',
        error: e,
        stackTrace: stack,
      );
    }
  }
}
