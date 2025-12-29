import 'package:flutter/material.dart';

/// Types of behavior events
enum BehaviorEventType {
  tap,
  scroll,
  keyDown,
  keyUp,
  appSwitch,
  notificationReceived,
  notificationOpened,
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
}
