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
  Timer?
  _inferenceTimer; // Periodic timer to check for focus results (every 5s, matching step interval)
  Timer?
  _dataPushTimer; // Periodic timer to push HR data every 1s (matching synheart-poc-dart pattern)
  HumanStateVector?
  _latestHsv; // Cache latest HSV for focus population when results arrive
  double?
  _latestHrBpm; // Cache latest HR value for data pushing (updated when HSV arrives)

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

    // Start periodic HR data push (every 1s, matching synheart-poc-dart pattern)
    // This ensures FocusEngine receives sufficient data points (60/min) for reliable inference
    // FocusEngine requires 30+ HR points in 60s window - with 1s pushes we get 60 points
    _dataPushTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _pushHrData(),
    );

    // Start periodic inference check (every 5s, matching FocusEngine step interval)
    // This checks for results independently of data push frequency
    _inferenceTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _checkForResults(),
    );
  }

  /// Process HSV and push HR data to FocusEngine
  ///
  /// This method only pushes data to the engine. Result checking
  /// is handled separately by the periodic inference timer.
  Future<void> _processHsv(HumanStateVector hsv) async {
    // Prevent concurrent processing
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      // Cache latest HSV for focus population when results arrive
      // Preserve existing focus data if new base HSV has empty focus
      // This prevents focus data from being cleared when new base HSV updates arrive
      HumanStateVector hsvToCache;
      if (_latestHsv != null &&
          _isFocusEmpty(hsv.focus) &&
          !_isFocusEmpty(_latestHsv!.focus)) {
        // New base HSV has empty focus, but we have existing focus data
        // Merge existing focus into new base HSV to preserve it
        hsvToCache = hsv.copyWithFocus(_latestHsv!.focus);
      } else {
        // New base HSV has focus data, or we don't have existing focus
        // Use the new base HSV as-is
        hsvToCache = hsv;
      }
      _latestHsv = hsvToCache;

      // If base HSV has empty focus but we have existing focus data,
      // emit the merged HSV immediately to prevent UI from showing empty focus
      // This ensures focus data persists even when base HSV updates arrive
      if (_isFocusEmpty(hsv.focus) && !_isFocusEmpty(hsvToCache.focus)) {
        _focusStream.add(hsvToCache);
      }

      // Ensure engine is initialized
      if (_engine == null) {
        await _ensureEngineInitialized();
        if (_engine == null) return;
      }

      // Extract HR from HSV embedding
      // The embedding vector[0] contains raw HR (BPM) from FusionEngine._buildFusedVector()
      // FusionEngine puts features.wear!.hrAverage directly into vector[0] without normalization
      // See fusion_engine.dart line 64: vector.add(features.wear!.hrAverage ?? 0.0)
      final emb = hsv.meta.embedding.vector;
      if (emb.isEmpty) {
        SynheartLogger.log('[FocusHead] No embedding data available');
        return;
      }

      // Use HR directly from embedding (already in BPM, not normalized)
      // The embedding contains raw HR values from WearModule (hrAverage in BPM)
      double hrBpm = emb[0];

      // Validate HR is in reasonable range (40-180 bpm)
      // If it's outside this range, it may be invalid or incorrectly normalized
      if (hrBpm < 40.0 || hrBpm > 180.0) {
        SynheartLogger.log(
          '[FocusHead] HR value out of range: ${hrBpm.toStringAsFixed(1)} BPM (expected 40-180 BPM)',
        );
        return; // Skip invalid HR values
      }

      final clampedHrBpm = hrBpm.clamp(40.0, 180.0);

      // Cache latest HR value for periodic data pushing
      _latestHrBpm = clampedHrBpm;

      // Note: We don't push HR data here anymore - it's handled by _dataPushTimer
      // This matches the synheart-poc-dart pattern where HR is pushed every 1s
    } catch (e, stackTrace) {
      SynheartLogger.log(
        '[FocusHead] Error pushing data to focus engine: $e',
        error: e,
        stackTrace: stackTrace,
      );
    } finally {
      _isProcessing = false;
    }
  }

  /// Push HR data to FocusEngine periodically (every 1s, matching synheart-poc-dart pattern)
  ///
  /// This ensures FocusEngine receives sufficient data points (60/min) for reliable inference.
  /// FocusEngine requires 30+ HR points in 60s window - with 1s pushes we get 60 points.
  /// Uses cached HR value from latest HSV update.
  Future<void> _pushHrData() async {
    if (_engine == null || !_isActive || _latestHrBpm == null) return;

    try {
      // Use current timestamp for each push (matching synheart-poc-dart pattern)
      final currentTimestamp = DateTime.now();

      // Push HR data to FocusEngine - it will buffer internally and check if inference is ready
      final result = await _engine!.inferFromHrData(
        hrBpm: _latestHrBpm!,
        timestamp: currentTimestamp,
      );

      // If result is ready, process it immediately
      if (result != null) {
        _processResults(result);
      }
    } catch (e, stackTrace) {
      SynheartLogger.log(
        '[FocusHead] Error pushing HR data: $e',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Check for focus results periodically (called by inference timer)
  ///
  /// This is a safety check - results are also checked in _pushHrData().
  /// FocusEngine buffers HR internally and produces results every 5s (step interval)
  /// once it has enough data (60s window with 30+ points).
  Future<void> _checkForResults() async {
    if (_engine == null || !_isActive || _latestHrBpm == null) return;

    try {
      final currentTimestamp = DateTime.now();

      // Check if result is ready (reuses latest HR, checks inference timing)
      final result = await _engine!.inferFromHrData(
        hrBpm: _latestHrBpm!,
        timestamp: currentTimestamp,
      );

      if (result == null) {
        // Not enough data yet - FocusEngine is still buffering
        return;
      }

      // Process the result
      _processResults(result);
    } catch (e, stackTrace) {
      SynheartLogger.log(
        '[FocusHead] Error checking for results: $e',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Check if focus state is empty (all values are 0.0)
  bool _isFocusEmpty(FocusState focus) {
    return focus.score == 0.0 &&
        focus.cognitiveLoad == 0.0 &&
        focus.clarity == 0.0 &&
        focus.distraction == 0.0;
  }

  /// Process focus results and emit updated HSV
  void _processResults(sf.FocusResult result) {
    if (_latestHsv == null) {
      SynheartLogger.log(
        '[FocusHead] No cached HSV available for result processing',
      );
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
    final hsvWithFocus = _latestHsv!.copyWithFocus(focus);

    // Emit final HSV
    _focusStream.add(hsvWithFocus);
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
    _dataPushTimer?.cancel();
    _dataPushTimer = null;
    _inferenceTimer?.cancel();
    _inferenceTimer = null;
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
