import 'dart:developer' as developer;

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

/// Lightweight internal logger (replaces `print`, keeps `flutter_lints` happy).
///
/// In debug mode, logs to the Flutter terminal via [debugPrint] so you see
/// output when running `flutter run`.
class SynheartLogger {
  static void log(
    String message, {
    String name = 'synheart',
    Object? error,
    StackTrace? stackTrace,
  }) {
    developer.log(message, name: name, error: error, stackTrace: stackTrace);
    if (kDebugMode) {
      final line = error != null ? '$message ($error)' : message;
      debugPrint(line);
    }
  }
}
