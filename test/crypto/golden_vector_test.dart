import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:synheart_core/src/crypto/urk.dart';

/// Golden vector tests for cross-platform key derivation consistency.
///
/// These expected hex values were computed from the Kotlin HKDF implementation
/// and are shared across Kotlin, Dart, and Swift test suites via
/// encryption_vectors.json in synheart-core/test/vectors/.
void main() {
  // -- Inline vectors (mirrors encryption_vectors.json) ----------------------

  const artifactUrkHex =
      '0101010101010101010101010101010101010101010101010101010101010101';
  const artifactId = 'test_artifact_001';
  const expectedArtifactKeyHex =
      '38f4cae76ca1a4a75f8300552747adf23a4043685ff3548e98bd523897f062f4';

  const bekSessionSecret = 'test_session_secret';
  const bekSubjectId = 'usr_test123';
  const expectedBekHex =
      '02ab906478234d2d1db18ab9fefd1d2f9c3a2548700b3c0853c685f8cba20e9b';

  // -- Helpers ---------------------------------------------------------------

  String toHex(Uint8List bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  Uint8List hexToBytes(String hex) {
    final result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < result.length; i++) {
      result[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return result;
  }

  // -- Tests -----------------------------------------------------------------

  group('GoldenVector', () {
    test('artifact key derivation matches golden vector', () async {
      final urk = hexToBytes(artifactUrkHex);
      final derived = await URK.deriveArtifactKey(
        urk: urk,
        artifactId: artifactId,
      );
      expect(
        toHex(derived),
        equals(expectedArtifactKeyHex),
        reason:
            'Artifact key derivation mismatch — cross-platform HKDF inconsistency',
      );
    });

    test('BEK derivation matches golden vector', () async {
      final derived = await URK.deriveBEK(
        sessionSecret: bekSessionSecret,
        subjectId: bekSubjectId,
      );
      expect(
        toHex(derived),
        equals(expectedBekHex),
        reason:
            'BEK derivation mismatch — cross-platform HKDF inconsistency',
      );
    });
  });
}
