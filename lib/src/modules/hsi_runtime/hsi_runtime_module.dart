import 'dart:async';
import 'package:rxdart/rxdart.dart';
import '../base/synheart_module.dart';
import '../interfaces/feature_providers.dart';
import '../../models/hsv.dart';
import '../../heads/emotion_head.dart';
import '../../heads/focus_head.dart';
import 'window_scheduler.dart';
import 'channel_collector.dart';
import 'fusion_engine_v2.dart';

/// HSI Runtime Module
///
/// Orchestrates the HSI pipeline:
/// 1. Schedules windows (30s, 5m, 1h, 24h)
/// 2. Collects features from Wear, Phone, Behavior
/// 3. Fuses features into base HSV
/// 4. Runs Emotion and Focus heads
/// 5. Publishes final HSV
class HSIRuntimeModule extends BaseSynheartModule {
  @override
  String get moduleId => 'hsi_runtime';

  final ChannelCollector _collector;
  final FusionEngineV2 _fusion = FusionEngineV2();
  final EmotionHead _emotionHead = EmotionHead();
  final FocusHead _focusHead = FocusHead();

  WindowScheduler? _scheduler;

  final BehaviorSubject<HumanStateVector> _baseHsvStream =
      BehaviorSubject<HumanStateVector>();
  final BehaviorSubject<HumanStateVector> _finalHsvStream =
      BehaviorSubject<HumanStateVector>();

  StreamSubscription<HumanStateVector>? _emotionSubscription;
  StreamSubscription<HumanStateVector>? _focusSubscription;

  HSIRuntimeModule({
    required ChannelCollector collector,
  }) : _collector = collector;

  /// Stream of base HSV (before emotion/focus)
  Stream<HumanStateVector> get baseHsvStream => _baseHsvStream.stream;

  /// Stream of final HSV (with emotion and focus)
  Stream<HumanStateVector> get finalHsvStream => _finalHsvStream.stream;

  /// Get current state
  HumanStateVector? get currentState =>
      _finalHsvStream.hasValue ? _finalHsvStream.value : null;

  @override
  Future<void> onInitialize() async {
    print('[HSIRuntime] Initializing HSI Runtime...');

    // Initialize emotion and focus heads
    _emotionHead.start(_baseHsvStream.stream);
    _focusHead.start(_emotionHead.emotionStream);

    // Subscribe to focus stream for final HSV
    _emotionSubscription = _emotionHead.emotionStream.listen(
      (hsv) {
        // Pass through for debugging
      },
      onError: (e) => print('[HSIRuntime] Emotion stream error: $e'),
    );

    _focusSubscription = _focusHead.focusStream.listen(
      (finalHsv) {
        _finalHsvStream.add(finalHsv);
      },
      onError: (e) => print('[HSIRuntime] Focus stream error: $e'),
    );
  }

  @override
  Future<void> onStart() async {
    print('[HSIRuntime] Starting HSI Runtime...');

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
    print('[HSIRuntime] HSI Runtime started');
  }

  @override
  Future<void> onStop() async {
    print('[HSIRuntime] Stopping HSI Runtime...');

    _scheduler?.stop();
    _scheduler = null;
  }

  @override
  Future<void> onDispose() async {
    print('[HSIRuntime] Disposing HSI Runtime...');

    await _emotionSubscription?.cancel();
    await _focusSubscription?.cancel();

    await _emotionHead.dispose();
    await _focusHead.dispose();

    await _baseHsvStream.close();
    await _finalHsvStream.close();
  }

  /// Compute state for a window
  Future<void> _computeState(WindowType window) async {
    try {
      // Collect features from all modules
      final features = _collector.collect(window);

      if (!features.hasAnyFeatures) {
        print('[HSIRuntime] No features available for $window');
        return;
      }

      // Fuse into base HSV
      final baseHsv = await _fusion.fuse(
        features,
        window,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      // Emit base HSV (will flow through emotion -> focus heads)
      _baseHsvStream.add(baseHsv);

      print('[HSIRuntime] Computed state for $window');
    } catch (e, stack) {
      print('[HSIRuntime] Error computing state: $e');
      print(stack);
    }
  }
}
