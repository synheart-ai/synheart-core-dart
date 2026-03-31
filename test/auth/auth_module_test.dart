import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_core/src/auth/auth_module.dart';

// Minimal mock for SynheartAuth — tests that don't call authenticate()
// don't need full device auth. For authenticate() tests, use integration tests
// with a mock ConsentAPIClient and mock SynheartAuth.

void main() {
  group('AuthStatus', () {
    test('unauthenticated has correct defaults', () {
      const status = AuthStatus.unauthenticated;
      expect(status.authenticated, isFalse);
      expect(status.subjectId, isNull);
      expect(status.provider, isNull);
      expect(status.syncReady, isFalse);
    });
  });

  group('AuthResult', () {
    test('holds all fields', () {
      const result = AuthResult(
        subjectId: 'usr_123',
        accessToken: 'at_abc',
        sessionSecret: 'ss_secret',
        syncReady: false,
      );
      expect(result.subjectId, equals('usr_123'));
      expect(result.accessToken, equals('at_abc'));
      expect(result.sessionSecret, equals('ss_secret'));
      expect(result.syncReady, isFalse);
    });
  });
}
