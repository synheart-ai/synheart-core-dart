import 'artifact_header.dart';

class Provenance {
  final String source;
  final String deviceId;
  final String appId;
  final String runtimeVersion;

  const Provenance({
    required this.source,
    required this.deviceId,
    required this.appId,
    required this.runtimeVersion,
  });

  Map<String, dynamic> toJson() => {
        'source': source,
        'device_id': deviceId,
        'app_id': appId,
        'runtime_version': runtimeVersion,
      };

  factory Provenance.fromJson(Map<String, dynamic> json) => Provenance(
        source: json['source'] as String,
        deviceId: json['device_id'] as String,
        appId: json['app_id'] as String,
        runtimeVersion: json['runtime_version'] as String,
      );
}

class WindowData {
  final int startMs;
  final int endMs;
  final int windowSizeMs;
  final Map<String, dynamic> hsi;

  const WindowData({
    required this.startMs,
    required this.endMs,
    this.windowSizeMs = 30000,
    required this.hsi,
  });

  Map<String, dynamic> toJson() => {
        'start_ms': startMs,
        'end_ms': endMs,
        'window_size_ms': windowSizeMs,
        'hsi': hsi,
      };

  factory WindowData.fromJson(Map<String, dynamic> json) => WindowData(
        startMs: json['start_ms'] as int,
        endMs: json['end_ms'] as int,
        windowSizeMs: json['window_size_ms'] as int? ?? 30000,
        hsi: json['hsi'] as Map<String, dynamic>,
      );
}

/// A time-windowed HSI state representation.
///
/// See RFC-CORE-0006 Section 6.2.
class HSIWindowArtifact {
  final ArtifactHeader header;
  final WindowData window;
  final Provenance provenance;

  HSIWindowArtifact({
    required this.header,
    required this.window,
    required this.provenance,
  });

  Map<String, dynamic> toJson() => {
        ...header.toJson(),
        'window': window.toJson(),
        'provenance': provenance.toJson(),
      };

  factory HSIWindowArtifact.fromJson(Map<String, dynamic> json) =>
      HSIWindowArtifact(
        header: ArtifactHeader.fromJson(json),
        window: WindowData.fromJson(json['window'] as Map<String, dynamic>),
        provenance:
            Provenance.fromJson(json['provenance'] as Map<String, dynamic>),
      );
}
