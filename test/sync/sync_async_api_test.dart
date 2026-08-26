import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_core/synheart_core.dart';

void main() {
  test('cloud-backed sync facade methods expose Future contracts', () async {
    final operations = <Future<Map<String, dynamic>?>>[
      Synheart.syncCreateSpace(deviceName: 'Phone'),
      Synheart.syncGeneratePairing(),
      Synheart.syncJoinSpace(pairingToken: 'TOKEN', deviceName: 'Phone'),
      Synheart.syncRecoverSpace(recoveryKey: 'KEY', spaceId: 'SPACE'),
      Synheart.syncLeaveSpace(),
      Synheart.syncListDevices(),
      Synheart.syncRevokeDevice(deviceId: 'DEVICE'),
      Synheart.syncDeleteSpace(),
      Synheart.syncClearLocalSpace(),
    ];

    expect(await Future.wait(operations), everyElement(isNull));
  });

  test('local sync snapshots remain synchronous', () {
    final Map<String, dynamic>? status = Synheart.syncStatusSnapshot();
    final Map<String, dynamic>? readiness = Synheart.syncReadinessSnapshot();

    expect(status, isNull);
    expect(readiness, isNull);
  });
}
