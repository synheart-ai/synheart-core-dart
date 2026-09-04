import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_core/src/core/serial_operation_queue.dart';

void main() {
  test('runs operations one at a time in submission order', () async {
    final queue = SerialOperationQueue();
    final releaseFirst = Completer<void>();
    final events = <String>[];

    final first = queue.run(() async {
      events.add('first-start');
      await releaseFirst.future;
      events.add('first-end');
      return 1;
    });
    final second = queue.run(() async {
      events.add('second-start');
      return 2;
    });

    await Future<void>.delayed(Duration.zero);
    expect(events, ['first-start']);

    releaseFirst.complete();

    expect(await first, 1);
    expect(await second, 2);
    expect(events, ['first-start', 'first-end', 'second-start']);
  });

  test('a failed operation does not prevent later work', () async {
    final queue = SerialOperationQueue();

    final failed = queue.run<int>(() async => throw StateError('failed'));
    final recovered = queue.run(() async => 42);

    await expectLater(failed, throwsStateError);
    expect(await recovered, 42);
  });
}
