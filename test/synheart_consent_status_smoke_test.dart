import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_core/synheart_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('getConsentStatusMap exposes coarse consent keys', () {
    final map = Synheart.getConsentStatusMap();

    expect(map.containsKey('biosignals'), isTrue);
    expect(map.containsKey('behavior'), isTrue);
    expect(map.containsKey('phoneContext'), isTrue);
    expect(map.containsKey('cloudUpload'), isTrue);
    expect(map.containsKey('vendorSync'), isTrue);
    expect(map.containsKey('research'), isTrue);
  });
}
