import 'dart:async';
import 'package:rxdart/rxdart.dart';
import '../models/hsv.dart';
import 'ingestion.dart';
import 'processors.dart';
import 'data_sources.dart';

/// HSI Core (State Engine)
/// 
/// Responsible for:
/// - Ingestion from Wear SDK, Phone SDK, Context Adapters
/// - Processing & Normalization
/// - Fusion & Embedding
/// - Producing base HSV stream
class StateEngine {
  final IngestionService _ingestion;
  final SignalProcessor _processor;
  final FusionEngine _fusion;

  final BehaviorSubject<HumanStateVector> _baseHsvStream =
      BehaviorSubject<HumanStateVector>();

  StreamSubscription? _ingestionSubscription;
  bool _isRunning = false;

  StateEngine({
    IngestionService? ingestion,
    SignalProcessor? processor,
    FusionEngine? fusion,
    BiosignalDataSource? biosignalSource,
    BehavioralDataSource? behavioralSource,
    ContextDataSource? contextSource,
  })  : _ingestion = ingestion ??
            IngestionService(
              biosignalSource: biosignalSource,
              behavioralSource: behavioralSource,
              contextSource: contextSource,
            ),
        _processor = processor ?? SignalProcessor(),
        _fusion = fusion ?? FusionEngine();

  /// Stream of base HSV (before emotion/focus heads populate)
  Stream<HumanStateVector> get baseHsvStream => _baseHsvStream.stream;

  /// Start the state engine
  Future<void> start() async {
    if (_isRunning) return;

    _isRunning = true;
    await _ingestion.start();

    // Subscribe to ingestion updates and process them
    _ingestionSubscription = _ingestion.signalStream.listen((signals) async {
      // Process and normalize signals
      final processed = await _processor.process(signals);

      // Fuse signals into base HSV
      final baseHsv = await _fusion.fuse(
        processed,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      // Emit base HSV
      _baseHsvStream.add(baseHsv);
    });
  }

  /// Stop the state engine
  Future<void> stop() async {
    _isRunning = false;
    await _ingestionSubscription?.cancel();
    await _ingestion.stop();
  }

  /// Get current state (latest HSV)
  HumanStateVector? get currentState => _baseHsvStream.hasValue
      ? _baseHsvStream.value
      : null;

  /// Dispose resources
  Future<void> dispose() async {
    await stop();
    await _baseHsvStream.close();
  }
}

