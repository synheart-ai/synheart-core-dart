import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_core/src/config/runtime_config_map.dart';
import 'package:synheart_core/src/config/synheart_config.dart';
import 'package:synheart_core/src/config/synheart_mode.dart';

/// Guards the JSON handed to `synheart_core_new`.
///
/// The bug these exist for: `ingest.enabled` and `device_auth.enabled` were
/// hardcoded `true`. A host with no CloudConfig therefore hit
///
///   ERR_NOT_CONFIGURED: cloud connector org_id must not be empty when HSI
///   ingest is enabled
///
/// inside `synheart_core_new`. The handle came back null, `_coreRuntime` stayed
/// null, and initialize() went on to log "Initialization complete" — with no
/// HSI, no consent store, and no storage. Local-only operation could not
/// initialise at all, and the whole suite passed, because nothing exercised the
/// config map.
void main() {
  SynheartConfig localOnly() =>
      SynheartConfig(appId: 'com.example.app', subjectId: 'usr_abc');

  SynheartConfig withCloud({String orgId = 'org_123'}) => SynheartConfig(
    appId: 'com.example.app',
    subjectId: 'usr_abc',
    cloudConfig: CloudConfig(
      subjectId: 'usr_abc',
      instanceId: 'inst_1',
      orgId: orgId,
    ),
  );

  group('ingest gate', () {
    test('stays OFF for a local-only config', () {
      final ingest = buildRuntimeConfigMap(localOnly())['ingest'] as Map;

      // All three must be false together: the runtime rejects the entire
      // config when any ingest channel is on without an org_id.
      expect(ingest['enabled'], isFalse);
      expect(ingest['hsi'], isFalse);
      expect(ingest['lab'], isFalse);
    });

    test('turns ON when a CloudConfig supplies an org id', () {
      final ingest = buildRuntimeConfigMap(withCloud())['ingest'] as Map;
      expect(ingest['enabled'], isTrue);
      expect(ingest['hsi'], isTrue);
      expect(ingest['lab'], isTrue);
    });

    test('stays OFF when a CloudConfig is present but org id is empty', () {
      // Enabling ingest here would reproduce the original failure, since the
      // org_id the runtime demands is exactly what is missing.
      final map = buildRuntimeConfigMap(withCloud(orgId: ''));
      expect((map['ingest'] as Map)['enabled'], isFalse);
      expect(map['org_id'], '');
    });
  });

  group('device_auth gate', () {
    test('stays OFF without a DeviceAuthConfig', () {
      // Enabling it without one makes the runtime reject crypto-callback
      // registration with ERR_NOT_CONFIGURED and log a misleading ERROR.
      final auth = buildRuntimeConfigMap(localOnly())['device_auth'] as Map;
      expect(auth['enabled'], isFalse);
      expect(auth['auth_base_url'], '');
    });

    test('turns ON and carries the URLs when configured', () {
      final config = SynheartConfig(
        appId: 'com.example.app',
        subjectId: 'usr_abc',
        deviceAuthConfig: const DeviceAuthConfig(
          authBaseUrl: 'https://auth.example.com',
          packageName: 'com.example.app',
        ),
      );
      final auth = buildRuntimeConfigMap(config)['device_auth'] as Map;
      expect(auth['enabled'], isTrue);
      expect(auth['auth_base_url'], 'https://auth.example.com');
      expect(auth['package_name'], 'com.example.app');
    });
  });

  group('required identity fields', () {
    test('client_id mirrors subject_id', () {
      // The runtime derives the device identity's subject from client_id and
      // rejects the config when device_auth is on without one.
      final map = buildRuntimeConfigMap(localOnly());
      expect(map['client_id'], 'usr_abc');
      expect(map['subject_id'], 'usr_abc');
    });

    test('api_base_url is always populated from sync config', () {
      // Left empty, the runtime falls back to its hardcoded production URL, so
      // a dev build would silently talk to production.
      final map = buildRuntimeConfigMap(localOnly());
      expect(map['api_base_url'], isNotEmpty);
    });

    test('data_dir is omitted rather than sent empty when unresolved', () {
      // An empty data_dir would land the SRM snapshot and SQLite in the OS temp
      // dir, where they do not survive app restarts.
      expect(buildRuntimeConfigMap(localOnly()).containsKey('data_dir'), false);
      expect(
        buildRuntimeConfigMap(localOnly(), dataDir: '/tmp/x')['data_dir'],
        '/tmp/x',
      );
    });
  });

  group('pass-through fields', () {
    test('mode, storage, sync, and privacy reflect the config', () {
      final config = SynheartConfig(
        appId: 'com.example.app',
        subjectId: 'usr_abc',
        mode: SynheartMode.research,
        storage: const StorageConfig(enabled: false),
        sync: const SyncConfig(enabled: true, baseUrl: 'https://s.example.com'),
        privacy: const PrivacyConfig(allowResearch: true),
      );
      final map = buildRuntimeConfigMap(config);

      expect(map['mode'], 'research');
      expect((map['storage'] as Map)['enabled'], isFalse);
      expect((map['sync'] as Map)['enabled'], isTrue);
      expect((map['sync'] as Map)['base_url'], 'https://s.example.com');
      expect((map['privacy'] as Map)['allow_research'], isTrue);
    });
  });
}
