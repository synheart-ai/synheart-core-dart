import 'dart:async';
import 'package:rxdart/rxdart.dart';
import '../models/hsv.dart';
import '../models/focus.dart';
import '../core/logger.dart';
import 'package:synheart_focus/synheart_focus.dart' as sf;

/// Focus Engine (Synheart Focus Head)
///
/// Model head that subscribes to HSI stream (optionally with emotion)
/// and populates hsv.focus using ONNX model inference.
class FocusHead {
  StreamSubscription<HumanStateVector>? _subscription;
  final BehaviorSubject<HumanStateVector> _focusStream =
      BehaviorSubject<HumanStateVector>();

  sf.FocusEngine? _engine;
  bool _isActive = false;
  bool _isInitializing = false;
  Completer<void>? _initializationCompleter;
  bool _isProcessing = false;

  final sf.FocusConfig _config = const sf.FocusConfig(
    windowSeconds: 60,
    stepSeconds: 5,
    minRrCount: 30,
    enableSmoothing: true,
    enableDebugLogging: false,
  );

  FocusHead();

  /// Stream of HSVs with focus populated
  Stream<HumanStateVector> get focusStream => _focusStream.stream;

  /// Start the focus head, subscribing to an HSV stream (optionally with emotion).
  Future<void> start(Stream<HumanStateVector> hsvStream) async {
    if (_isActive) return;

    // Ensure engine is initialized before starting
    await _ensureEngineInitialized();

    _isActive = true;
    _subscription = hsvStream.listen((hsv) {
      _processHsv(hsv);
    });
  }

  /// Process HSV and run focus inference
  Future<void> _processHsv(HumanStateVector hsv) async {
    if (!_isActive || _isProcessing || _engine == null) return;

    _isProcessing = true;
    try {
      // Extract HR from HSV embedding
      // The embedding vector[0] contains normalized HR (0-1 range)
      // We need to denormalize it to get actual BPM
      final emb = hsv.meta.embedding.vector;
      if (emb.isEmpty) {
        SynheartLogger.log('[FocusHead] No embedding data available');
        return;
      }

      // Denormalize HR from embedding (assuming normalization: (hr - 50) / 70)
      // This matches the normalization in processors.dart: ((hr - 50) / 70).clamp(0.0, 1.0)
      final normalizedHr = emb[0].clamp(0.0, 1.0);
      final hrBpm = (normalizedHr * 70.0) + 50.0; // Denormalize: hr = normalized * 70 + 50

      // Clamp to reasonable HR range (40-180 bpm)
      final clampedHrBpm = hrBpm.clamp(40.0, 180.0);

      // Convert timestamp from milliseconds to DateTime
      final timestamp = DateTime.fromMillisecondsSinceEpoch(hsv.timestamp);

      // Run inference using ONNX model (inferFromHrData)
      final result = await _engine!.inferFromHrData(
        hrBpm: clampedHrBpm,
        timestamp: timestamp,
      );

      if (result == null) {
        // Not enough data yet (waiting for 60-second window)
        return;
      }

      // Map FocusResult (0-100 score) to FocusState (0-1 score)
      final score = (result.focusScore / 100.0).clamp(0.0, 1.0);
      final focus = FocusState(
        score: score,
        cognitiveLoad: (1.0 - score).clamp(0.0, 1.0).toDouble(),
        clarity: score,
        distraction: (1.0 - score).clamp(0.0, 1.0).toDouble(),
      );

      SynheartLogger.log(
        '[FocusHead] Focus updated: Score=${score.toStringAsFixed(2)}, '
        'State=${result.focusState}, Confidence=${result.confidence.toStringAsFixed(2)}',
      );

      // Update HSV with focus
      final hsvWithFocus = hsv.copyWithFocus(focus);

      // Emit final HSV
      _focusStream.add(hsvWithFocus);
    } catch (e, stackTrace) {
      SynheartLogger.log(
        '[FocusHead] Error processing HSV: $e',
        error: e,
        stackTrace: stackTrace,
      );
    } finally {
      _isProcessing = false;
    }
  }

  /// Ensure the focus engine is initialized with ONNX model
  ///
  /// This method loads the ONNX model asynchronously and creates the FocusEngine.
  /// It prevents concurrent initializations and caches the initialization future.
  Future<void> _ensureEngineInitialized() async {
    // If already initialized, return immediately
    if (_engine != null) return;

    // If initialization is in progress, wait for it to complete
    if (_isInitializing && _initializationCompleter != null) {
      if (!_initializationCompleter!.isCompleted) {
        await _initializationCompleter!.future;
      }
      return;
    }

    // Start initialization
    _isInitializing = true;
    _initializationCompleter = Completer<void>();

    try {
      SynheartLogger.log('[FocusHead] Loading ONNX focus model...');

      // Create engine with config
      _engine = sf.FocusEngine(
        config: _config,
        onLog: (level, message, {context}) {
          SynheartLogger.log('[FocusEngine][$level] $message');
        },
      );

      // Initialize with ONNX model
      await _engine!.initialize(
        modelPath: 'assets/models/Gradient_Boosting.onnx',
        backend: 'onnx',
      );

      SynheartLogger.log('[FocusHead] Focus engine initialized successfully');

      // Complete the initialization future
      if (_initializationCompleter != null &&
          !_initializationCompleter!.isCompleted) {
        _initializationCompleter!.complete();
      }
    } catch (e, stackTrace) {
      SynheartLogger.log(
        '[FocusHead] Failed to initialize focus engine: $e',
        error: e,
        stackTrace: stackTrace,
      );
      if (_initializationCompleter != null &&
          !_initializationCompleter!.isCompleted) {
        _initializationCompleter!.completeError(e, stackTrace);
      }
      _isInitializing = false;
      _initializationCompleter = null;
      rethrow;
    }
  }

  /// Stop the focus head
  Future<void> stop() async {
    _isActive = false;
    await _subscription?.cancel();
    _subscription = null;
  }

  Future<void> dispose() async {
    await stop();
    _engine?.dispose();
    _engine = null;
    await _focusStream.close();
  }
}
