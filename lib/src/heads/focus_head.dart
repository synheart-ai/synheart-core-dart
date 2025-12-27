import 'dart:async';
import 'package:rxdart/rxdart.dart';
import '../models/hsv.dart';
import '../models/focus.dart';
import 'package:synheart_focus/synheart_focus.dart' as sf;

/// Focus Engine (Synheart Focus Head)
/// 
/// Model head that subscribes to HSI stream (optionally with emotion)
/// and populates hsv.focus
class FocusHead {
  StreamSubscription<HumanStateVector>? _subscription;
  final BehaviorSubject<HumanStateVector> _focusStream =
      BehaviorSubject<HumanStateVector>();

  final sf.FocusEngine _engine = sf.FocusEngineFactory.createDefault();

  bool _isActive = false;

  FocusHead();

  /// Stream of HSVs with focus populated
  Stream<HumanStateVector> get focusStream => _focusStream.stream;

  /// Start the focus head, subscribing to an HSV stream (optionally with emotion).
  void start(Stream<HumanStateVector> hsvStream) {
    if (_isActive) return;

    _isActive = true;
    _subscription = hsvStream.listen((hsv) async {
      final hsiData = _toHSIData(hsv);
      final behaviorData = _toBehaviorData(hsv);

      // Infer focus using synheart_focus SDK.
      final result = await _engine.infer(hsiData, behaviorData);

      // Map synheart_focus output -> synheart_core FocusState.
      final score = result.focusScore.clamp(0.0, 1.0).toDouble();
      final focus = FocusState(
        score: score,
        cognitiveLoad: (1.0 - score).clamp(0.0, 1.0).toDouble(),
        clarity: score,
        distraction: (1.0 - score).clamp(0.0, 1.0).toDouble(),
      );

      // Update HSV with focus
      final hsvWithFocus = hsv.copyWithFocus(focus);

      // Emit final HSV
      _focusStream.add(hsvWithFocus);
    });
  }

  /// Stop the focus head
  Future<void> stop() async {
    _isActive = false;
    await _subscription?.cancel();
  }

  sf.HSIData _toHSIData(HumanStateVector hsv) {
    final emb = hsv.meta.hsiEmbedding;

    // FusionEngine embeds biosignals first.
    final hr = emb.isNotEmpty ? emb[0] : 0.0;
    final hrvRmssd = emb.length > 1 ? emb[1] : 0.0;
    final motionIntensity = emb.length > 5 ? emb[5] : 0.0;

    // Prefer emotion-derived stress when available; otherwise fall back to overload.
    final stressIndex = (hsv.emotion.stress > 0
            ? hsv.emotion.stress
            : hsv.context.overload)
        .clamp(0.0, 1.0)
        .toDouble();

    return sf.HSIData(
      hr: hr,
      hrvRmssd: hrvRmssd,
      stressIndex: stressIndex,
      motionIntensity: motionIntensity.clamp(0.0, 1.0).toDouble(),
    );
  }

  sf.BehaviorData _toBehaviorData(HumanStateVector hsv) {
    final idleRatio = (hsv.behavior.idleGaps / 60.0).clamp(0.0, 1.0).toDouble();
    return sf.BehaviorData(
      taskSwitchRate: hsv.behavior.appSwitchRate,
      interactionBurstiness:
          hsv.behavior.typingBurstiness.clamp(0.0, 1.0).toDouble(),
      idleRatio: idleRatio,
    );
  }

  Future<void> dispose() async {
    await stop();
    _engine.dispose();
    await _focusStream.close();
  }
}

