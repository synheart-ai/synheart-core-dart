import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_core/synheart_core.dart';

void main() {
  test('parses a valid native sync result', () {
    final result = SyncResult.fromRuntimeResponse({'pushed': 2, 'pulled': 3});

    expect(result.pushed, 2);
    expect(result.pulled, 3);
  });

  test('rejects a missing native sync result', () {
    expect(() => SyncResult.fromRuntimeResponse(null), throwsStateError);
  });

  test('rejects a malformed native sync result', () {
    expect(
      () => SyncResult.fromRuntimeResponse({'pushed': 1}),
      throwsFormatException,
    );
  });
}
