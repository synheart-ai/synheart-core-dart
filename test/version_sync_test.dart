// Ensures `lib/src/version.dart` hasn't drifted from `pubspec.yaml`.
// Regenerate after bumping pubspec:
//
//   dart run tool/sync_version.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_core/synheart_core.dart';

void main() {
  test('synheartCoreVersion matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*(.+?)\s*$',
      multiLine: true,
    ).firstMatch(pubspec);
    expect(match, isNotNull, reason: 'pubspec.yaml is missing `version:`');
    expect(
      synheartCoreVersion,
      match!.group(1),
      reason:
          'version.dart is out of sync with pubspec.yaml — '
          'run `dart run tool/sync_version.dart`',
    );
  });
}
