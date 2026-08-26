import 'dart:async';

/// Runs asynchronous operations one at a time in submission order.
///
/// An operation failure is delivered to that operation's caller without
/// poisoning the queue, so later work can still proceed.
class SerialOperationQueue {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}
