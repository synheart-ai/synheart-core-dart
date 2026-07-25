import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_core/synheart_core.dart';

void main() {
  Map<String, dynamic> snapshot({
    String state = 'READY',
    bool configured = true,
    bool storagePresent = true,
    bool deviceRegistered = true,
    bool deviceRevoked = false,
    bool engineReady = true,
    bool activeSpace = true,
    bool srkReady = true,
  }) => <String, dynamic>{
    'state': state,
    'configured': configured,
    'storage_present': storagePresent,
    'device_registered': deviceRegistered,
    'device_revoked': deviceRevoked,
    'engine_ready': engineReady,
    'active_space': activeSpace,
    'srk_ready': srkReady,
  };

  SyncReadiness evaluate(
    SyncOperation operation, {
    bool activated = true,
    bool consent = true,
    bool capability = true,
    Map<String, dynamic>? native,
  }) => SyncReadiness.evaluate(
    operation: operation,
    activated: activated,
    cloudConsentGranted: consent,
    capabilityAllowed: capability,
    nativeSnapshot: native ?? snapshot(),
  );

  group('create-space readiness', () {
    test('does not require a running collection session', () {
      // Collection-session state is deliberately not an input. A fresh app can
      // create a space while the native snapshot reports all bootstrap state as
      // absent.
      final result = evaluate(
        SyncOperation.createSpace,
        native: snapshot(
          state: 'ENGINE_NOT_INITIALIZED',
          engineReady: false,
          activeSpace: false,
          srkReady: false,
        ),
      );

      expect(result.isReady, isTrue);
      expect(result.code, SyncReadinessCode.ready);
      expect(result.nativeState, 'ENGINE_NOT_INITIALIZED');
    });

    test('ignores no-active-space and missing-SRK native gates', () {
      final result = evaluate(
        SyncOperation.createSpace,
        native: snapshot(
          state: 'NO_ACTIVE_SPACE',
          activeSpace: false,
          srkReady: false,
        ),
      );

      expect(result.isReady, isTrue);
    });
  });

  group('common native prerequisites', () {
    test('requires configuration', () {
      final result = evaluate(
        SyncOperation.createSpace,
        native: snapshot(configured: false),
      );

      expect(result.code, SyncReadinessCode.configurationMissing);
    });

    test('requires storage', () {
      final result = evaluate(
        SyncOperation.createSpace,
        native: snapshot(storagePresent: false),
      );

      expect(result.code, SyncReadinessCode.storageUnavailable);
    });

    test('reports revocation before missing registration', () {
      final result = evaluate(
        SyncOperation.createSpace,
        native: snapshot(deviceRegistered: false, deviceRevoked: true),
      );

      expect(result.code, SyncReadinessCode.deviceRevoked);
    });

    test('requires device registration', () {
      final result = evaluate(
        SyncOperation.createSpace,
        native: snapshot(deviceRegistered: false),
      );

      expect(result.code, SyncReadinessCode.deviceRegistrationRequired);
    });
  });

  group('SDK authorization prerequisites', () {
    test('requires activation', () {
      expect(
        evaluate(SyncOperation.createSpace, activated: false).code,
        SyncReadinessCode.featureNotActivated,
      );
    });

    test('requires cloud consent', () {
      expect(
        evaluate(SyncOperation.createSpace, consent: false).code,
        SyncReadinessCode.cloudConsentRequired,
      );
    });

    test('requires capability', () {
      expect(
        evaluate(SyncOperation.createSpace, capability: false).code,
        SyncReadinessCode.capabilityNotAllowed,
      );
    });

    test('requires the native runtime snapshot', () {
      final result = SyncReadiness.evaluate(
        operation: SyncOperation.createSpace,
        activated: true,
        cloudConsentGranted: true,
        capabilityAllowed: true,
        nativeSnapshot: null,
      );

      expect(result.code, SyncReadinessCode.nativeRuntimeUnavailable);
    });
  });

  group('space and SRK requirements', () {
    test('pairing requires an active space', () {
      final result = evaluate(
        SyncOperation.generatePairing,
        native: snapshot(activeSpace: false, srkReady: false),
      );

      expect(result.code, SyncReadinessCode.activeSpaceRequired);
    });

    test('pairing requires an SRK', () {
      final result = evaluate(
        SyncOperation.generatePairing,
        native: snapshot(srkReady: false),
      );

      expect(result.code, SyncReadinessCode.srkUnavailable);
    });

    test('sync-now requires an SRK', () {
      final result = evaluate(
        SyncOperation.syncNow,
        native: snapshot(srkReady: false),
      );

      expect(result.code, SyncReadinessCode.srkUnavailable);
    });

    test('management requires a space but not an SRK', () {
      for (final operation in const [
        SyncOperation.listDevices,
        SyncOperation.revokeDevice,
        SyncOperation.leaveSpace,
        SyncOperation.deleteSpace,
      ]) {
        final ready = evaluate(operation, native: snapshot(srkReady: false));
        final blocked = evaluate(
          operation,
          native: snapshot(activeSpace: false, srkReady: false),
        );

        expect(ready.isReady, isTrue, reason: '$operation should be ready');
        expect(
          blocked.code,
          SyncReadinessCode.activeSpaceRequired,
          reason: '$operation should require an active space',
        );
      }
    });

    test('recovery does not require an active space or SRK', () {
      final result = evaluate(
        SyncOperation.recoverSpace,
        native: snapshot(activeSpace: false, srkReady: false),
      );

      expect(result.isReady, isTrue);
    });
  });

  group('local clear', () {
    test('does not require SDK authorization or device registration', () {
      final result = SyncReadiness.evaluate(
        operation: SyncOperation.clearLocalSpace,
        activated: false,
        cloudConsentGranted: false,
        capabilityAllowed: false,
        nativeSnapshot: snapshot(
          deviceRegistered: false,
          deviceRevoked: true,
          activeSpace: false,
        ),
      );

      expect(result.isReady, isTrue);
      expect(result.code, SyncReadinessCode.ready);
    });
  });
}
