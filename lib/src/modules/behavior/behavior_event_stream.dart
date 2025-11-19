import 'dart:async';
import 'package:flutter/material.dart';
import 'behavior_events.dart';

/// Behavior event stream
///
/// Unified event bus for all user-device interactions
class BehaviorEventStream {
  final StreamController<BehaviorEvent> _controller =
      StreamController<BehaviorEvent>.broadcast();

  Stream<BehaviorEvent> get events => _controller.stream;

  /// Record a tap event
  void recordTap(Offset position) {
    _controller.add(BehaviorEvent.tap(position));
  }

  /// Record a scroll event
  void recordScroll(double delta) {
    _controller.add(BehaviorEvent.scroll(delta));
  }

  /// Record a key down event
  void recordKeyDown() {
    _controller.add(BehaviorEvent.keyDown());
  }

  /// Record a key up event
  void recordKeyUp() {
    _controller.add(BehaviorEvent.keyUp());
  }

  /// Record an app switch event
  void recordAppSwitch() {
    _controller.add(BehaviorEvent.appSwitch());
  }

  /// Record a notification received event
  void recordNotificationReceived() {
    _controller.add(BehaviorEvent.notificationReceived());
  }

  /// Record a notification opened event
  void recordNotificationOpened() {
    _controller.add(BehaviorEvent.notificationOpened());
  }

  Future<void> dispose() async {
    await _controller.close();
  }
}
