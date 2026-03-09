import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_core/src/auth/auth_module.dart';

void main() {
  group('AuthModule', () {
    test('starts unauthenticated', () {
      final auth = AuthModule(appId: 'test_app');
      expect(auth.isAuthenticated, isFalse);
      expect(auth.subjectId, isNull);
      expect(auth.status.syncReady, isFalse);
    });

    test('anonymous auth generates subject_id', () async {
      final auth = AuthModule(appId: 'test_app');
      final result = await auth.authenticateAnonymous();

      expect(result.subjectId, startsWith('anon_'));
      expect(result.accessToken, isNull);
      expect(result.syncReady, isFalse);
      expect(auth.status.provider, equals('anonymous'));
      expect(auth.status.authenticated, isFalse);
      expect(auth.subjectId, isNotNull);
    });

    test('logout clears state', () async {
      final auth = AuthModule(appId: 'test_app');
      await auth.authenticateAnonymous();
      expect(auth.subjectId, isNotNull);

      await auth.logout();
      expect(auth.subjectId, isNull);
      expect(auth.isAuthenticated, isFalse);
      expect(auth.accessToken, isNull);
    });

    test('markSyncReady updates status', () async {
      final auth = AuthModule(appId: 'test_app');
      await auth.authenticateAnonymous();
      expect(auth.status.syncReady, isFalse);

      auth.markSyncReady();
      expect(auth.status.syncReady, isTrue);
    });
  });

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
        refreshToken: 'rt_xyz',
        sessionSecret: 'ss_secret',
        syncReady: false,
      );
      expect(result.subjectId, equals('usr_123'));
      expect(result.accessToken, equals('at_abc'));
      expect(result.refreshToken, equals('rt_xyz'));
      expect(result.sessionSecret, equals('ss_secret'));
      expect(result.syncReady, isFalse);
    });
  });
}
