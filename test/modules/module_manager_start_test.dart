import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_core/src/modules/base/module_manager.dart';
import 'package:synheart_core/src/modules/base/synheart_module.dart';

/// `startAll()` used to `await module.start()` unguarded, so the first module
/// that threw aborted the loop and every later module was silently skipped.
///
/// Modules start in dependency order with wear first, so on an iOS build with
/// no HealthKit entitlement — where the wear source cannot initialize — the
/// behavior and phone modules never started either. The host got a session that
/// produced nothing at all, rather than one merely missing biosignals.
///
/// `initializeAll()` and `stopAll()` were already per-module resilient;
/// `startAll()` was the outlier.
class _FakeModule extends BaseSynheartModule {
  _FakeModule(this._id, {this.throwOnStart = false});

  final String _id;
  final bool throwOnStart;
  bool started = false;

  @override
  String get moduleId => _id;

  @override
  Future<void> onInitialize() async {}

  @override
  Future<void> onStart() async {
    if (throwOnStart) {
      throw StateError('$_id cannot start');
    }
    started = true;
  }

  @override
  Future<void> onStop() async {
    started = false;
  }

  @override
  Future<void> onDispose() async {}
}

void main() {
  group('ModuleManager.startAll resilience', () {
    test(
      'a failing module does not prevent later modules from starting',
      () async {
        final manager = ModuleManager();
        final first = _FakeModule('wear', throwOnStart: true);
        final second = _FakeModule('behavior');
        final third = _FakeModule('phone');

        manager.registerModule(first);
        manager.registerModule(second);
        manager.registerModule(third);
        await manager.initializeAll();

        await manager.startAll();

        // The regression: these were false because the loop aborted on `wear`.
        expect(second.started, isTrue, reason: 'behavior must still start');
        expect(third.started, isTrue, reason: 'phone must still start');
        expect(first.started, isFalse);
      },
    );

    test('failures are reported rather than swallowed', () async {
      final manager = ModuleManager();
      manager.registerModule(_FakeModule('wear', throwOnStart: true));
      manager.registerModule(_FakeModule('behavior'));
      await manager.initializeAll();

      final failures = await manager.startAll();

      // Degrading silently would be its own bug — the caller must be able to
      // tell which sources are missing.
      expect(failures.keys, contains('wear'));
      expect(failures.containsKey('behavior'), isFalse);
      // BaseSynheartModule.start() wraps the cause in a ModuleException, so the
      // map carries that rather than the raw error. The underlying reason must
      // survive the wrapping — that string is what a host surfaces to a
      // developer.
      expect('${failures['wear']}', contains('wear'));
      expect('${failures['wear']}', contains('cannot start'));
    });

    test('an all-healthy start reports no failures', () async {
      final manager = ModuleManager();
      final a = _FakeModule('wear');
      final b = _FakeModule('behavior');
      manager.registerModule(a);
      manager.registerModule(b);
      await manager.initializeAll();

      expect(await manager.startAll(), isEmpty);
      expect(a.started, isTrue);
      expect(b.started, isTrue);
    });

    test('startAll still rejects an uninitialized manager', () {
      expect(() => ModuleManager().startAll(), throwsA(isA<Exception>()));
    });
  });
}
