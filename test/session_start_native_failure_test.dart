import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_core/synheart_core.dart';

/// `startSession()` used to treat a null native result as "no native runtime"
/// and fall through to the Dart-only path, which mints a `core_<millis>`
/// session id. A host with a loaded runtime therefore received a session handle
/// and a `collecting` state for a session the runtime never opened — no native
/// windowing, no HSI, no stored artifacts, and no error.
///
/// The guard is tested directly rather than through `startSession()`: reaching
/// that branch requires a `CoreRuntimeBridge` wrapping a live native handle,
/// which a unit test cannot construct. `startSession()` calls this same
/// function, so deleting the guard fails these tests.
void main() {
  group('assertNativeSessionStarted', () {
    test('throws when the runtime returned no session', () {
      expect(
        () => Synheart.assertNativeSessionStarted(null),
        throwsA(isA<StateError>()),
      );
    });

    test('passes through a session the runtime did open', () {
      expect(
        () => Synheart.assertNativeSessionStarted({
          'session_id': 'sess_abc',
          'started_at_ms': 1700000000000,
        }),
        returnsNormally,
      );
    });

    test('the message rules out the local-only path', () {
      // The failure mode this guards is a developer reading "no session" as
      // "running locally". The message has to close that door explicitly.
      String? message;
      try {
        Synheart.assertNativeSessionStarted(null);
      } on StateError catch (e) {
        message = e.message;
      }

      expect(message, isNotNull);
      expect(message, contains('native session failed to start'));
      expect(
        message,
        contains('not the local-only path'),
        reason:
            'Without this the error reads as a benign fallback rather than a '
            'failure that collects nothing.',
      );
    });

    test('the message names the most likely cause and a next step', () {
      String? message;
      try {
        Synheart.assertNativeSessionStarted(null);
      } on StateError catch (e) {
        message = e.message;
      }

      // An already-open native session is the common case, and stopSession()
      // is the fix. Naming both is what makes this actionable rather than
      // merely correct.
      expect(message, contains('stopSession()'));
      expect(message, contains('runtimeDiagnostics()'));
    });

    test('an empty map is a session, not a failure', () {
      // Only null means "the runtime gave nothing back". An empty map would
      // fail later on its missing fields, and conflating the two here would
      // report a parse problem as a start-up refusal.
      expect(
        () => Synheart.assertNativeSessionStarted(const {}),
        returnsNormally,
      );
    });
  });
}
