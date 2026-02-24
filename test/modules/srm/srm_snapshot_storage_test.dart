import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_core/src/modules/srm/srm_module.dart';
import 'package:synheart_core/src/modules/srm/srm_config.dart';
import 'package:synheart_core/src/modules/srm/srm_stratum.dart';
import 'package:synheart_core/src/modules/srm/srm_baseline_status.dart';
import 'package:synheart_core/src/modules/srm/srm_buffer.dart';
import 'package:synheart_core/src/modules/srm/srm_snapshot.dart';
import 'package:synheart_core/src/modules/srm/srm_snapshot_storage.dart';
import 'package:synheart_core/src/modules/srm/srm_types.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// In-memory mock for FlutterSecureStorage used in tests.
class MockSecureStorage implements FlutterSecureStorage {
  final Map<String, String> _store = {};

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value != null) {
      _store[key] = value;
    } else {
      _store.remove(key);
    }
  }

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return _store[key];
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _store.remove(key);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SRMSnapshotStorage', () {
    late MockSecureStorage mockStorage;
    late SRMSnapshotStorage storage;

    setUp(() {
      mockStorage = MockSecureStorage();
      storage = SRMSnapshotStorage(storage: mockStorage);
    });

    test('save and load round-trip preserves snapshot data', () async {
      final snapshot = SRMSnapshot(
        srmVersion: '1.0.0',
        createdAtUtc: DateTime.utc(2025, 6, 15, 12, 0, 0),
        strata: {
          SRMStratum.rest: StratumSnapshot(
            stratum: SRMStratum.rest,
            status: SRMBaselineStatus.warming,
            entries: [
              BufferEntry(
                windowId: 'w1',
                metrics: {'hr_mean': 72.0, 'rmssd': 45.0},
                observedAtUtc: DateTime.utc(2025, 6, 15, 10, 0, 0),
              ),
              BufferEntry(
                windowId: 'w2',
                metrics: {'hr_mean': 74.0, 'rmssd': 48.0},
                observedAtUtc: DateTime.utc(2025, 6, 15, 11, 0, 0),
              ),
            ],
            reference: {
              'hr_mean': MetricReference(median: 73.0, mad: 1.0),
              'rmssd': MetricReference(median: 46.5, mad: 1.5),
            },
            distinctDays: 1,
          ),
        },
      );

      await storage.save(snapshot);
      final loaded = await storage.load();

      expect(loaded, isNotNull);
      expect(loaded!.srmVersion, equals('1.0.0'));
      expect(loaded.strata.length, equals(1));
      expect(loaded.strata.containsKey(SRMStratum.rest), isTrue);

      final stratumSnapshot = loaded.strata[SRMStratum.rest]!;
      expect(stratumSnapshot.entries.length, equals(2));
      expect(stratumSnapshot.entries[0].windowId, equals('w1'));
      expect(stratumSnapshot.entries[0].metrics['hr_mean'], equals(72.0));
      expect(stratumSnapshot.entries[1].windowId, equals('w2'));
      expect(stratumSnapshot.reference['hr_mean']!.median, equals(73.0));
      expect(stratumSnapshot.reference['rmssd']!.mad, equals(1.5));
      expect(stratumSnapshot.distinctDays, equals(1));
    });

    test('load returns null when no data stored', () async {
      final loaded = await storage.load();
      expect(loaded, isNull);
    });

    test('clear removes stored data', () async {
      final snapshot = SRMSnapshot(
        srmVersion: '1.0.0',
        createdAtUtc: DateTime.utc(2025, 6, 15),
        strata: {},
      );

      await storage.save(snapshot);
      expect(await storage.load(), isNotNull);

      await storage.clear();
      expect(await storage.load(), isNull);
    });

    test('SRMModule restores snapshot from storage on init', () async {
      // 1. Create an SRM module and submit candidates to get WARMING status
      final config = SRMConfig(mMin: 3, mReady: 5, dMin: 2);
      final module1 = SRMModule(config: config, storage: storage);
      await module1.initialize();

      // Submit candidates to build up buffer
      module1.submitCandidate(CandidateWindow(
        sessionId: 's1',
        windowId: 'w1',
        stratum: SRMStratum.rest,
        metrics: {'hr_mean': 72.0, 'rmssd': 45.0},
        qualityScore: 0.9,
        motionScore: 0.1,
        durationSeconds: 60.0,
        observedAtUtc: DateTime.utc(2025, 6, 15, 10, 0, 0),
      ));
      module1.submitCandidate(CandidateWindow(
        sessionId: 's1',
        windowId: 'w2',
        stratum: SRMStratum.rest,
        metrics: {'hr_mean': 74.0, 'rmssd': 48.0},
        qualityScore: 0.9,
        motionScore: 0.1,
        durationSeconds: 60.0,
        observedAtUtc: DateTime.utc(2025, 6, 16, 10, 0, 0),
      ));
      module1.submitCandidate(CandidateWindow(
        sessionId: 's1',
        windowId: 'w3',
        stratum: SRMStratum.rest,
        metrics: {'hr_mean': 73.0, 'rmssd': 46.0},
        qualityScore: 0.9,
        motionScore: 0.1,
        durationSeconds: 60.0,
        observedAtUtc: DateTime.utc(2025, 6, 17, 10, 0, 0),
      ));

      expect(module1.baselineStatus(SRMStratum.rest), equals(SRMBaselineStatus.warming));
      expect(module1.totalAcceptedWindows, equals(3));

      // 2. Persist snapshot via stop (must start first)
      await module1.start();
      await module1.stop();

      // 3. Create a fresh SRM module with the same storage
      final module2 = SRMModule(config: config, storage: storage);
      await module2.initialize();

      // 4. Verify state was restored
      expect(module2.totalAcceptedWindows, equals(3));
      expect(module2.baselineStatus(SRMStratum.rest), equals(SRMBaselineStatus.warming));

      final ref = module2.queryReference(SRMStratum.rest);
      expect(ref, isNotNull);
      expect(ref!.bufferCount, equals(3));
    });
  });
}
