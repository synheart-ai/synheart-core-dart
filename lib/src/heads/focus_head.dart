import 'dart:async';
import 'package:rxdart/rxdart.dart';
import '../models/hsv.dart';

/// Focus Head — DEPRECATED.
///
/// Focus values now come from synheart-runtime via `RuntimeBridge.lastHsv()`.
/// The runtime computes focus with confidence and full inference metadata as
/// part of the canonical 6-head HSV output.
///
/// This class is retained only for API compatibility. It passes HSVs through
/// unchanged and will be removed in a future release.
@Deprecated('Use RuntimeBridge.lastHsv() — focus is computed by synheart-runtime')
class FocusHead {
  StreamSubscription<HumanStateVector>? _subscription;
  final BehaviorSubject<HumanStateVector> _focusStream =
      BehaviorSubject<HumanStateVector>();

  bool _isActive = false;

  FocusHead();

  /// Stream of HSVs (pass-through — focus now comes from runtime).
  Stream<HumanStateVector> get focusStream => _focusStream.stream;

  /// Start the focus head, subscribing to an HSV stream.
  /// Now a pass-through: HSVs are forwarded unchanged.
  Future<void> start(Stream<HumanStateVector> hsvStream) async {
    if (_isActive) return;

    _isActive = true;
    _subscription = hsvStream.listen((hsv) {
      _focusStream.add(hsv);
    });
  }

  /// Stop the focus head.
  Future<void> stop() async {
    _isActive = false;
    await _subscription?.cancel();
    _subscription = null;
  }

  Future<void> dispose() async {
    await stop();
    await _focusStream.close();
  }
}
