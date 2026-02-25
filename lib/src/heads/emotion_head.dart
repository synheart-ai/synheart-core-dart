import 'dart:async';
import 'package:rxdart/rxdart.dart';
import '../models/hsv.dart';
import '../core/logger.dart';

/// Emotion Head — DEPRECATED.
///
/// Emotion values now come from synheart-runtime via `RuntimeBridge.lastHsv()`.
/// The runtime computes emotion (valence, arousal) with confidence and full
/// inference metadata as part of the canonical 6-head HSV output.
///
/// This class is retained only for API compatibility. It passes HSVs through
/// unchanged and will be removed in a future release.
@Deprecated('Use RuntimeBridge.lastHsv() — emotion is computed by synheart-runtime')
class EmotionHead {
  StreamSubscription<HumanStateVector>? _subscription;
  final BehaviorSubject<HumanStateVector> _emotionStream =
      BehaviorSubject<HumanStateVector>();

  bool _isActive = false;

  EmotionHead();

  /// Stream of HSVs (pass-through — emotion now comes from runtime).
  Stream<HumanStateVector> get emotionStream => _emotionStream.stream;

  /// Start the emotion head, subscribing to base HSV stream.
  /// Now a pass-through: HSVs are forwarded unchanged.
  void start(Stream<HumanStateVector> baseHsvStream) {
    if (_isActive) return;

    _isActive = true;
    _subscription = baseHsvStream.listen(
      (baseHsv) {
        _emotionStream.add(baseHsv);
      },
      onError: (error, stackTrace) {
        SynheartLogger.log(
          '[EmotionHead] Error in HSV stream: $error',
          error: error,
          stackTrace: stackTrace,
        );
      },
    );
  }

  /// Stop the emotion head.
  Future<void> stop() async {
    _isActive = false;
    await _subscription?.cancel();
  }

  Future<void> dispose() async {
    await stop();
    await _emotionStream.close();
  }
}
