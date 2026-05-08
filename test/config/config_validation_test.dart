import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_core/src/config/synheart_config.dart';
import 'package:synheart_core/src/config/synheart_errors.dart';
import 'package:synheart_core/src/config/synheart_mode.dart';

void main() {
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
