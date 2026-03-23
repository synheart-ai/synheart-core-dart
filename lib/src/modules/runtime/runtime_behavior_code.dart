/// Runtime behavior event codes — must match synheart_runtime C ABI
/// (`synheart_runtime_push_behavior` event_type parameter).
abstract final class RuntimeBehaviorCode {
  static const int screenOn = 0;
  static const int screenOff = 1;

  /// Tap, key-down, key-up — any discrete input.
  static const int input = 2;

  static const int appSwitch = 3;

  /// Notification received or opened.
  static const int notification = 4;

  static const int scroll = 5;
  static const int swipe = 6;
  static const int call = 7;
}
