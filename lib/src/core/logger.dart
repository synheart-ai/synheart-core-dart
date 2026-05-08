import 'dart:developer' as developer;

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

/// Lightweight internal logger (replaces `print`, keeps `flutter_lints` happy).
///
/// In debug mode, logs to the Flutter terminal via [debugPrint] so you see
/// output when running `flutter run`.
///
/// Consumer apps are encouraged to call the domain-tagged convenience methods
/// ([stream], [research], [wear], [consent]) instead of hand-rolling their own
/// prefixed wrappers. This keeps log prefixes and `developer.log` names
/// consistent across every Synheart-aware app, so filters in IDEs / log
/// collectors work uniformly.
class SynheartLogger {
  /// When true, tagged logs print in release builds too (on top of the
  /// default [kDebugMode] gate). Apps flip this when they want verbose
  /// Synheart traces on a signed build.
  static bool verbose = false;

  /// Generic log — prefers the tagged convenience methods where possible.
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

  /// RAMEN streaming pipeline — vendor sync start/stop, per-event routing,
  /// native runtime bridge errors. Gated by [verbose] or [kDebugMode].
  static void stream(String message, {Object? error, StackTrace? stackTrace}) =>
      _tagged(
        prefix: 'Synheart Stream',
        name: 'synheart.stream',
        message: message,
        error: error,
        stackTrace: stackTrace,
        gated: true,
      );

  /// Research / lab mode — session lifecycle, heartbeats, stall detection,
  /// HSI snapshots. Ungated: research mode is already an explicit consent
  /// opt-in, so logs flow whenever a research session is active.
  static void research(
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) => _tagged(
    prefix: 'Synheart Research Mode',
    name: 'synheart.research',
    message: message,
    error: error,
    stackTrace: stackTrace,
    gated: false,
  );

  /// Wear source-linking (OAuth flows, BLE connect, HealthKit permissions,
  /// vendor provider setup). Gated by [verbose] or [kDebugMode].
  static void wear(String message, {Object? error, StackTrace? stackTrace}) =>
      _tagged(
        prefix: 'Synheart Wear',
        name: 'synheart.wear',
        message: message,
        error: error,
        stackTrace: stackTrace,
        gated: true,
      );

  /// Consent lifecycle — grant / revoke / profile changes. Gated.
  static void consent(
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) => _tagged(
    prefix: 'Synheart Consent',
    name: 'synheart.consent',
    message: message,
    error: error,
    stackTrace: stackTrace,
    gated: true,
  );

  static void _tagged({
    required String prefix,
    required String name,
    required String message,
    Object? error,
    StackTrace? stackTrace,
    required bool gated,
  }) {
    final tagged = '[$prefix] $message';
    developer.log(tagged, name: name, error: error, stackTrace: stackTrace);
    if (!gated || kDebugMode || verbose) {
      final line = error != null ? '$tagged ($error)' : tagged;
      debugPrint(line);
    }
  }
}
