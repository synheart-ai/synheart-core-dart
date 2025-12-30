import 'dart:developer' as developer;

/// Lightweight internal logger (replaces `print`, keeps `flutter_lints` happy).
///
/// This library is Flutter-first, but we avoid `debugPrint` so this stays usable
/// from pure Dart contexts (and works in tests).
class SynheartLogger {
  static void log(
    String message, {
    String name = 'synheart',
    Object? error,
    StackTrace? stackTrace,
  }) {
    developer.log(message, name: name, error: error, stackTrace: stackTrace);
  }
}
