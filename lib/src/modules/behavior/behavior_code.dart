/// Typed behavior-event kinds that cross the FFI seam.
///
/// Replaces the previous flat `int` codes (`RuntimeBehaviorCode.screenOn = 0`)
/// with an enum so SDK call sites can't drift out of sync with the
/// engine. Each variant carries:
///   * [code] — the raw integer the legacy `synheart_core_push_behavior`
///     FFI still expects.
///   * [kind] — the canonical string used by the rich
///     `synheart_core_push_behavior_event` FFI / `BehaviorEventInput.kind`.
///
/// When migrating to the rich-event FFI, only [kind] needs to change;
/// the SDK API stays put.
enum RuntimeBehaviorEvent {
  screenOn(0, 'screen_on'),
  screenOff(1, 'screen_off'),
  input(2, 'touch'),
  appSwitch(3, 'app_switch'),
  notification(4, 'notification'),
  scroll(5, 'scroll'),
  swipe(6, 'swipe'),
  call(7, 'call');

  final int code;
  final String kind;
  const RuntimeBehaviorEvent(this.code, this.kind);
}
