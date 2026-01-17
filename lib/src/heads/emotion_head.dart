import 'dart:async';
import 'dart:math';
import 'package:rxdart/rxdart.dart';
import '../models/hsv.dart';
import '../models/emotion.dart';
import '../core/logger.dart';
import 'package:synheart_emotion/synheart_emotion.dart' as se;

/// Emotion Engine (Synheart Emotion Head)
///
/// Model head that subscribes to HSI Core stream and populates hsv.emotion
/// Uses EmotionEngine from synheart_emotion package for inference.
///
/// The emotion engine uses ONNX models that require:
/// - Real RR intervals (or synthesized from mean RR)
/// - Async inference via consumeReadyAsync()
/// - Binary classification: Baseline vs Stress
class EmotionHead {
  StreamSubscription<HumanStateVector>? _subscription;
  final BehaviorSubject<HumanStateVector> _emotionStream =
      BehaviorSubject<HumanStateVector>();

  se.EmotionEngine? _engine;

  // Use 60s window with 5s step for near-realtime updates
  // This matches the ExtraTrees_60_5 model configuration
  // The modelId will be auto-detected from the loaded ONNX model
  final se.EmotionConfig _config = const se.EmotionConfig(
    window: Duration(seconds: 60),
    step: Duration(seconds: 5),
    minRrCount: 30, // Minimum RR intervals required for inference
  );

  bool _isActive = false;
  bool _isProcessing = false; // Prevent concurrent async processing
  bool _isInitializing = false; // Track model initialization state
  Completer<void>?
  _initializationCompleter; // Completer for initialization (created on demand)

  Timer?
  _inferenceTimer; // Periodic timer to check for emotion results (every 5s, matching step interval)
  HumanStateVector?
  _latestHsv; // Cache latest HSV for emotion population when results arrive

  EmotionHead();

  /// Stream of HSVs with emotion populated
  Stream<HumanStateVector> get emotionStream => _emotionStream.stream;

  /// Start the emotion head, subscribing to base HSV stream
  void start(Stream<HumanStateVector> baseHsvStream) {
    if (_isActive) return;

    _isActive = true;
    _subscription = baseHsvStream.listen(
      (baseHsv) {
        // Process asynchronously without blocking the stream
        _processHsv(baseHsv);
      },
      onError: (error, stackTrace) {
        SynheartLogger.log(
          '[EmotionHead] Error in HSV stream: $error',
          error: error,
          stackTrace: stackTrace,
        );
      },
    );

    // Start periodic inference check (every 5s, matching step interval)
    // This ensures we check for results regularly, independent of HSV update frequency
    _inferenceTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _checkForResults(),
    );
  }

  /// Process HSV update asynchronously - pushes data to emotion engine
  ///
  /// This method only pushes data to the emotion engine. Result checking
  /// is handled separately by the periodic inference timer.
  Future<void> _processHsv(HumanStateVector baseHsv) async {
    // Prevent concurrent processing
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      // Cache latest HSV for emotion population when results arrive
      // Preserve existing emotion data if new base HSV has empty emotion
      // This prevents emotion data from being cleared when new base HSV updates arrive
      HumanStateVector hsvToCache;
      if (_latestHsv != null &&
          _isEmotionEmpty(baseHsv.emotion) &&
          !_isEmotionEmpty(_latestHsv!.emotion)) {
        // New base HSV has empty emotion, but we have existing emotion data
        // Merge existing emotion into new base HSV to preserve it
        hsvToCache = baseHsv.copyWithEmotion(_latestHsv!.emotion);
      } else {
        // New base HSV has emotion data, or we don't have existing emotion
        // Use the new base HSV as-is
        hsvToCache = baseHsv;
      }
      _latestHsv = hsvToCache;

      // If base HSV has empty emotion but we have existing emotion data,
      // emit the merged HSV immediately to prevent UI from showing empty emotion
      // This ensures emotion data persists even when base HSV updates arrive
      if (_isEmotionEmpty(baseHsv.emotion) &&
          !_isEmotionEmpty(hsvToCache.emotion)) {
        _emotionStream.add(hsvToCache);
      }

      // Ensure engine is initialized (async model loading)
      await _ensureEngineInitialized();

      // If engine is still null after initialization, skip processing
      if (_engine == null) {
        SynheartLogger.log(
          '[EmotionHead] Engine not initialized, skipping processing',
        );
        return;
      }

      // Extract HR and mean RR from HSV embedding
      final hrAndRr = _extractHrAndRr(baseHsv);
      if (hrAndRr == null) {
        // Not enough signal quality / missing biosignal features yet
        SynheartLogger.log(
          '[EmotionHead] Skipping: insufficient HR/RR data in HSV embedding',
        );
        return;
      }

      final hr = hrAndRr['hr']!;
      final meanRr = hrAndRr['mean_rr']!;

      // Generate synthetic RR intervals from mean RR
      // This is a workaround until raw RR intervals are available in HSV
      // The engine will extract all 14 HRV features from these RR intervals
      final syntheticRR = _generateSyntheticRrIntervals(meanRr);

      // Push to EmotionEngine (adds to ring buffer)
      // Result checking is handled by periodic timer, not here
      _engine!.push(
        hr: hr,
        rrIntervalsMs: syntheticRR,
        timestamp: DateTime.fromMillisecondsSinceEpoch(baseHsv.timestamp),
      );

      SynheartLogger.log(
        '[EmotionHead] Pushed data to emotion engine: HR=${hr.toStringAsFixed(1)}, '
        'MeanRR=${meanRr.toStringAsFixed(1)}ms',
      );
    } catch (e, stackTrace) {
      SynheartLogger.log(
        '[EmotionHead] Error pushing data to emotion engine: $e',
        error: e,
        stackTrace: stackTrace,
      );
    } finally {
      _isProcessing = false;
    }
  }

  /// Check for emotion results periodically (called by inference timer)
  ///
  /// This method is called every 5 seconds to check if emotion results are ready,
  /// matching the emotion engine's step interval.
  Future<void> _checkForResults() async {
    if (_engine == null || !_isActive) return;

    try {
      // Check for ready results (async for ONNX models)
      final results = await _engine!.consumeReadyAsync();
      if (results.isEmpty) {
        // No results ready yet (waiting for step interval or more data)
        return;
      }

      // Process first result
      final result = results.first;
      _processResults(result);
    } catch (e, stackTrace) {
      SynheartLogger.log(
        '[EmotionHead] Error checking for emotion results: $e',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Process emotion result and emit updated HSV
  ///
  /// Maps EmotionResult from synheart_emotion to EmotionState and updates
  /// the latest HSV with emotion data.
  void _processResults(se.EmotionResult result) {
    // Need latest HSV to update with emotion
    if (_latestHsv == null) {
      SynheartLogger.log(
        '[EmotionHead] No HSV available for emotion population',
      );
      return;
    }

    // Map synheart_emotion EmotionResult -> synheart_core EmotionState
    // Real ONNX models return "Baseline" and "Stress" (binary classification)
    final baselineProb = (result.probabilities['Baseline'] ?? 0.0)
        .clamp(0.0, 1.0)
        .toDouble();
    final stressProb = (result.probabilities['Stress'] ?? 0.0)
        .clamp(0.0, 1.0)
        .toDouble();

    // Map to EmotionState:
    // - Baseline → calm
    // - Stress → stress
    // - Engagement: derived from stress level (lower stress = higher engagement)
    // - Activation: derived from stress (higher stress = higher activation)
    // - Valence: derived from baseline vs stress (baseline = positive, stress = negative)
    final emotion = EmotionState(
      stress: stressProb,
      calm: baselineProb,
      engagement: (1.0 - stressProb).clamp(0.0, 1.0), // Inverse of stress
      activation: stressProb, // Stress indicates activation
      valence: (baselineProb - stressProb).clamp(
        -1.0,
        1.0,
      ), // Baseline positive, stress negative
    );

    // Update latest HSV with emotion
    final hsvWithEmotion = _latestHsv!.copyWithEmotion(emotion);

    // Emit updated HSV
    _emotionStream.add(hsvWithEmotion);

    SynheartLogger.log(
      '[EmotionHead] Emotion updated: Stress=${stressProb.toStringAsFixed(2)}, '
      'Calm=${baselineProb.toStringAsFixed(2)}, '
      'Engagement=${emotion.engagement.toStringAsFixed(2)}',
    );
  }

  /// Check if emotion state is empty (all values are 0.0)
  bool _isEmotionEmpty(EmotionState emotion) {
    return emotion.stress == 0.0 &&
        emotion.calm == 0.0 &&
        emotion.engagement == 0.0 &&
        emotion.activation == 0.0 &&
        emotion.valence == 0.0;
  }

  /// Stop the emotion head
  Future<void> stop() async {
    _isActive = false;
    _inferenceTimer?.cancel();
    _inferenceTimer = null;
    await _subscription?.cancel();
  }

  /// Ensure the emotion engine is initialized with ONNX model
  ///
  /// This method loads the ONNX model asynchronously and creates the EmotionEngine.
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
      SynheartLogger.log('[EmotionHead] Loading ONNX emotion model...');

      // Load the ONNX model from assets
      // Using ExtraTrees_60_5 model which matches our 60s/5s configuration
      final onnxModel = await se.OnnxEmotionModel.loadFromAsset(
        modelAssetPath: 'assets/ml/ExtraTrees_60_5_nozipmap.onnx',
      );

      SynheartLogger.log('[EmotionHead] Model loaded: ${onnxModel.modelId}');

      // Create engine with the loaded model
      // Use the modelId from the loaded model to ensure compatibility
      _engine = se.EmotionEngine.fromPretrained(
        _config.copyWith(modelId: onnxModel.modelId),
        model: onnxModel,
        onLog: (level, message, {context}) {
          // Log emotion engine messages for debugging
          SynheartLogger.log('[EmotionEngine][$level] $message');
        },
      );

      SynheartLogger.log(
        '[EmotionHead] Emotion engine initialized successfully',
      );

      // Complete the initialization future
      if (_initializationCompleter != null &&
          !_initializationCompleter!.isCompleted) {
        _initializationCompleter!.complete();
      }
    } catch (e, stackTrace) {
      SynheartLogger.log(
        '[EmotionHead] Failed to initialize emotion engine: $e',
        error: e,
        stackTrace: stackTrace,
      );

      // Complete with error
      if (_initializationCompleter != null &&
          !_initializationCompleter!.isCompleted) {
        _initializationCompleter!.completeError(e, stackTrace);
      }

      // Reset initialization state to allow retry
      _isInitializing = false;
      _initializationCompleter = null;

      rethrow;
    }
  }

  /// Extract HR and mean RR from HSV embedding
  ///
  /// The HSV embedding contains HRV features at specific indices:
  /// - [0] HR_mean (bpm)
  /// - [1] RMSSD (ms)
  /// - [2] SDNN (ms)
  /// - [3] pNN50 (%)
  /// - [4] Mean_RR (ms)
  ///
  /// Returns null if insufficient data or invalid values.
  Map<String, double>? _extractHrAndRr(HumanStateVector hsv) {
    final emb = hsv.meta.embedding.vector;
    if (emb.length < 5) {
      return null;
    }

    final hrMean = emb[0];
    var meanRr = emb[4];

    if (hrMean <= 0 || hrMean > 300) {
      // Invalid HR range
      return null;
    }

    if (meanRr <= 0 || meanRr > 2000) {
      // Invalid RR range, derive from HR
      meanRr = 60000.0 / hrMean;
    }

    return {'hr': hrMean, 'mean_rr': meanRr};
  }

  /// Generate synthetic RR intervals from mean RR
  ///
  /// Creates realistic RR intervals with natural variation around the mean.
  /// The EmotionEngine will extract all 14 HRV features from these intervals.
  List<double> _generateSyntheticRrIntervals(double meanRr) {
    // Generate more realistic RR intervals with better variance
    // Use a pattern that simulates natural heart rate variability
    final rrIntervals = <double>[];
    final random = DateTime.now().millisecondsSinceEpoch % 1000 / 1000.0;

    for (int i = 0; i < 20; i++) {
      // Create more realistic variation using a sine wave pattern
      // This simulates respiratory sinus arrhythmia (RSA)
      final phase = (i * 0.3) % (2 * pi);
      final rsaVariation = (meanRr * 0.05) * sin(phase);

      // Add random variation
      final randomVariation = (random * 20 - 10) * (i % 3 == 0 ? 1 : 0.5);

      // Combine variations
      final rr = meanRr + rsaVariation + randomVariation;

      // Clamp to physiological range (300ms - 2000ms)
      rrIntervals.add(rr.clamp(300.0, 2000.0));
    }

    return rrIntervals;
  }

  Future<void> dispose() async {
    await stop();
    // Clear EmotionEngine buffer
    _engine?.clear();
    _engine = null;
    await _emotionStream.close();
  }
}
