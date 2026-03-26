import 'dart:io' show Platform;

/// Platform string for ingest API: ios, android, or dart (desktop/other).
String get currentIngestPlatform {
  if (Platform.isIOS) return 'ios';
  if (Platform.isAndroid) return 'android';
  return 'dart';
}
