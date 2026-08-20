import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_core/src/config/synheart_config.dart';
import 'package:synheart_core/src/config/synheart_errors.dart';
import 'package:synheart_core/src/config/synheart_mode.dart';

void main() {
  group('SynheartConfig validation messages are actionable', () {
    // The messages used to be bare assertions ("appId must not be empty"),
    // which told a developer what was wrong but not what to set or where.
    // These pin the guidance so it cannot silently regress to a bare noun.

    test('empty appId names the field and shows the call shape', () {
      final config = SynheartConfig(subjectId: 'usr_abc123');
      SynheartError? thrown;
      try {
        config.validate();
      } on SynheartError catch (e) {
        thrown = e;
      }

      expect(thrown, isNotNull);
      expect(thrown!.code, 'ERR_NOT_CONFIGURED');
      expect(thrown.message, contains('SynheartConfig.appId'));
      expect(thrown.message, contains('SynheartConfig(appId:'));
    });

    test('empty subjectId explains stability and the userId pitfall', () {
      final config = SynheartConfig(appId: 'com.example.app');
      SynheartError? thrown;
      try {
        config.validate();
      } on SynheartError catch (e) {
        thrown = e;
      }

      expect(thrown, isNotNull);
      expect(thrown!.code, 'ERR_NOT_CONFIGURED');
      expect(thrown.message, contains('SynheartConfig.subjectId'));
      // The trap the example app fell into: `userId:` on initialize() does not
      // populate config.subjectId.
      expect(thrown.message, contains('userId'));
      expect(thrown.message, contains('stable'));
    });

    test('a piped subjectId echoes the offending value and the reason', () {
      final config = SynheartConfig(
        appId: 'com.example.app',
        subjectId: 'usr|abc',
      );
      SynheartError? thrown;
      try {
        config.validate();
      } on SynheartError catch (e) {
        thrown = e;
      }

      expect(thrown, isNotNull);
      expect(thrown!.code, 'ERR_INVALID_MODE');
      expect(thrown.message, contains('usr|abc'));
      expect(thrown.message, contains('storage keys'));
    });

    test('appId is reported before subjectId when both are empty', () {
      // Deterministic ordering keeps the first run actionable instead of
      // making the developer fix one field to discover the next.
      final config = SynheartConfig();
      SynheartError? thrown;
      try {
        config.validate();
      } on SynheartError catch (e) {
        thrown = e;
      }
      expect(thrown!.message, contains('SynheartConfig.appId'));
    });
  });

  group('SynheartConfig validation', () {
    test('valid personal config passes', () {
      final config = SynheartConfig(
        appId: 'com.example.app',
        subjectId: 'usr_abc123',
        mode: SynheartMode.personal,
      );
      expect(() => config.validate(), returnsNormally);
    });

    test('valid insight config passes', () {
      final config = SynheartConfig(
        appId: 'com.example.app',
        subjectId: 'usr_abc123',
        mode: SynheartMode.insight,
      );
      expect(() => config.validate(), returnsNormally);
    });

    test('research mode requires allowResearch', () {
      final config = SynheartConfig(
        appId: 'com.example.app',
        subjectId: 'usr_abc123',
        mode: SynheartMode.research,
        privacy: const PrivacyConfig(allowResearch: false),
      );
      expect(
        () => config.validate(),
        throwsA(
          isA<SynheartError>().having(
            (e) => e.code,
            'code',
            'ERR_RESEARCH_NOT_ALLOWED',
          ),
        ),
      );
    });

    test('research mode with allowResearch passes', () {
      final config = SynheartConfig(
        appId: 'com.example.app',
        subjectId: 'usr_abc123',
        mode: SynheartMode.research,
        privacy: const PrivacyConfig(allowResearch: true),
      );
      expect(() => config.validate(), returnsNormally);
    });

    test('empty appId throws', () {
      final config = SynheartConfig(appId: '', subjectId: 'usr_abc123');
      expect(
        () => config.validate(),
        throwsA(
          isA<SynheartError>().having(
            (e) => e.code,
            'code',
            'ERR_NOT_CONFIGURED',
          ),
        ),
      );
    });

    test('empty subjectId throws', () {
      final config = SynheartConfig(appId: 'com.example.app', subjectId: '');
      expect(
        () => config.validate(),
        throwsA(
          isA<SynheartError>().having(
            (e) => e.code,
            'code',
            'ERR_NOT_CONFIGURED',
          ),
        ),
      );
    });

    test('subjectId with pipe throws', () {
      final config = SynheartConfig(
        appId: 'com.example.app',
        subjectId: 'usr|bad',
      );
      expect(
        () => config.validate(),
        throwsA(
          isA<SynheartError>().having(
            (e) => e.code,
            'code',
            'ERR_INVALID_MODE',
          ),
        ),
      );
    });
  });

  group('StorageConfig defaults', () {
    test('storage enabled by default', () {
      const config = StorageConfig();
      expect(config.enabled, isTrue);
      expect(config.retentionDays, isNull);
    });
  });

  group('SyncConfig defaults', () {
    test('sync disabled by default', () {
      const config = SyncConfig();
      expect(config.enabled, isFalse);
    });
  });

  group('PrivacyConfig defaults', () {
    test('research not allowed by default', () {
      const config = PrivacyConfig();
      expect(config.allowResearch, isFalse);
    });
  });
}
