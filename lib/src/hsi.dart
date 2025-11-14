import 'dart:async';
import 'package:rxdart/rxdart.dart';
import 'core/state_engine.dart';
import 'core/data_sources.dart';
import 'heads/emotion_head.dart';
import 'heads/focus_head.dart';
import 'models/hsv.dart';

/// Human State Interface (HSI)
/// 
/// Main entry point for HSI SDK.
/// Orchestrates HSI Core, Emotion Head, and Focus Head.
class HSI {
  static HSI? _instance;
  static HSI get shared => _instance ??= HSI._();

  HSI._();

  StateEngine? _stateEngine;
  final EmotionHead _emotionHead = EmotionHead();
  final FocusHead _focusHead = FocusHead();

  final BehaviorSubject<HumanStateVector> _finalHsvStream =
      BehaviorSubject<HumanStateVector>();

  StreamSubscription<HumanStateVector>? _focusSubscription;
  bool _isRunning = false;
  String? _appKey;

  /// Stream of final HSV (with emotion and focus populated)
  Stream<HumanStateVector> get onStateUpdate => _finalHsvStream.stream;

  /// Configure HSI with app key and optional data sources
  ///
  /// Example with default mock data:
  /// ```dart
  /// await hsi.configure(appKey: 'YOUR_KEY');
  /// ```
  ///
  /// Example with custom data sources:
  /// ```dart
  /// await hsi.configure(
  ///   appKey: 'YOUR_KEY',
  ///   biosignalSource: SynheartWearDataSource(),
  ///   behavioralSource: PhoneSDKDataSource(),
  /// );
  /// ```
  Future<void> configure({
    required String appKey,
    BiosignalDataSource? biosignalSource,
    BehavioralDataSource? behavioralSource,
    ContextDataSource? contextSource,
  }) async {
    _appKey = appKey;

    // Create state engine with optional data sources
    _stateEngine = StateEngine(
      biosignalSource: biosignalSource,
      behavioralSource: behavioralSource,
      contextSource: contextSource,
    );

    // TODO: Validate app key, initialize any required services
  }

  /// Start HSI pipeline
  Future<void> start() async {
    if (_isRunning) return;
    if (_appKey == null || _stateEngine == null) {
      throw StateError('HSI must be configured with appKey before starting');
    }

    _isRunning = true;

    // Start state engine (produces base HSV)
    await _stateEngine!.start();

    // Start emotion head (subscribes to base HSV)
    _emotionHead.start(_stateEngine!.baseHsvStream);

    // Start focus head (subscribes to emotion stream)
    _focusHead.start(_emotionHead.emotionStream);

    // Subscribe to focus stream to get final HSV
    _focusSubscription = _focusHead.focusStream.listen((finalHsv) {
      _finalHsvStream.add(finalHsv);
    });
  }

  /// Stop HSI pipeline
  Future<void> stop() async {
    _isRunning = false;
    await _focusSubscription?.cancel();
    await _focusHead.stop();
    await _emotionHead.stop();
    await _stateEngine?.stop();
  }

  /// Get current state (latest HSV)
  HumanStateVector? get currentState {
    // Try to get from final stream first
    if (_finalHsvStream.hasValue) {
      return _finalHsvStream.value;
    }
    // Fallback to state engine
    return _stateEngine?.currentState;
  }

  /// Enable cloud sync (aggregated HSV only, no raw biosignals)
  Future<void> enableCloudSync() async {
    // TODO: Implement cloud sync
    // This should sync aggregated HSV only, not raw biosignals
    throw UnimplementedError('Cloud sync not yet implemented');
  }

  /// Dispose all resources
  Future<void> dispose() async {
    await stop();
    await _finalHsvStream.close();
    await _focusHead.dispose();
    await _emotionHead.dispose();
    await _stateEngine?.dispose();
  }
}

