import 'package:flutter/material.dart';

/// Types of behavior events.
///
/// Maps 1:1 to the synheart-runtime C ABI event_type codes:
///   0=ScreenOn, 1=ScreenOff, 2=Touch, 3=AppSwitch,
///   4=NotificationReceived, 5=Scroll, 6=Swipe, 7=Call
enum BehaviorEventType {
  screenOn,
  screenOff,
  tap,
  scroll,
  swipe,
  keyDown,
  keyUp,
  appSwitch,
  notificationReceived,
  notificationOpened,
  call,
}

/// Behavior event captured from user interactions
class BehaviorEvent {
  final BehaviorEventType type;
  final DateTime timestamp;
  final Map<String, dynamic>? metadata;

  const BehaviorEvent({
    required this.type,
    required this.timestamp,
    this.metadata,
  });

  factory BehaviorEvent.screenOn() {
    return BehaviorEvent(
      type: BehaviorEventType.screenOn,
      timestamp: DateTime.now(),
    );
  }

  factory BehaviorEvent.screenOff() {
    return BehaviorEvent(
      type: BehaviorEventType.screenOff,
      timestamp: DateTime.now(),
    );
  }

  factory BehaviorEvent.tap(Offset position) {
    return BehaviorEvent(
      type: BehaviorEventType.tap,
      timestamp: DateTime.now(),
      metadata: {'x': position.dx, 'y': position.dy},
    );
  }

  factory BehaviorEvent.scroll(double delta) {
    return BehaviorEvent(
      type: BehaviorEventType.scroll,
      timestamp: DateTime.now(),
      metadata: {'delta': delta},
    );
  }

  factory BehaviorEvent.swipe({double? velocity, String? direction}) {
    return BehaviorEvent(
      type: BehaviorEventType.swipe,
      timestamp: DateTime.now(),
      metadata: {
        if (velocity != null) 'velocity': velocity,
        if (direction != null) 'direction': direction,
      },
    );
  }

  factory BehaviorEvent.keyDown() {
    return BehaviorEvent(
      type: BehaviorEventType.keyDown,
      timestamp: DateTime.now(),
    );
  }

  factory BehaviorEvent.keyUp() {
    return BehaviorEvent(
      type: BehaviorEventType.keyUp,
      timestamp: DateTime.now(),
    );
  }

  factory BehaviorEvent.appSwitch() {
    return BehaviorEvent(
      type: BehaviorEventType.appSwitch,
      timestamp: DateTime.now(),
    );
  }

  factory BehaviorEvent.notificationReceived() {
    return BehaviorEvent(
      type: BehaviorEventType.notificationReceived,
      timestamp: DateTime.now(),
    );
  }

  factory BehaviorEvent.notificationOpened() {
    return BehaviorEvent(
      type: BehaviorEventType.notificationOpened,
      timestamp: DateTime.now(),
    );
  }

  factory BehaviorEvent.call() {
    return BehaviorEvent(
      type: BehaviorEventType.call,
      timestamp: DateTime.now(),
    );
  }
}
