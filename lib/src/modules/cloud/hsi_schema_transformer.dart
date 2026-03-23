import 'package:uuid/uuid.dart';
import '../../models/hsi_constants.dart';

/// Transforms raw HSI JSON maps produced by synheart-runtime into payloads
/// that conform to hsi-1.1.schema.json (additionalProperties: false).
///
/// The Rust runtime may produce slightly non-conformant output (e.g. extra
/// fields on readings or windows). This class patches the map in-place,
/// stripping anything that would fail schema validation.
class HsiSchemaTransformer {
  const HsiSchemaTransformer();

  /// Patch [hsi] in-place to conform to hsi-1.1.schema.json.
  Map<String, dynamic> patch(Map<String, dynamic> hsi) {
    hsi['hsi_version'] = HsiSchema.version;
    _patchProducer(hsi);
    _patchSources(hsi);
    _patchAxes(hsi);
    _patchWindows(hsi);
    _patchPrivacy(hsi);
    return hsi;
  }

  void _patchProducer(Map<String, dynamic> hsi) {
    final producer = hsi['producer'];
    if (producer is Map<String, dynamic>) {
      producer.putIfAbsent('instance_id', () => const Uuid().v4());
      producer.removeWhere(
        (k, _) => !HsiSchema.producerFields.contains(k),
      );
    }
  }

  /// Ensure `source_ids` + `sources` pair integrity at top level.
  /// Both are optional, but if one is present the other must be too.
  void _patchSources(Map<String, dynamic> hsi) {
    final sourceIds = hsi['source_ids'];
    final sources = hsi['sources'];

    final hasSourceIds = sourceIds is List && sourceIds.isNotEmpty;
    final sourcesMap = sources is Map<String, dynamic> ? sources : null;
    final hasSources = sourcesMap != null && sourcesMap.isNotEmpty;

    if (hasSourceIds && !hasSources) {
      hsi.remove('source_ids');
    } else if (!hasSourceIds && hasSources) {
      hsi['source_ids'] = sourcesMap!.keys.toList();
    }

    // Ensure source_ids is a List<String> if present.
    final patchedSourceIds = hsi['source_ids'];
    if (patchedSourceIds is List) {
      final strings = patchedSourceIds.whereType<String>().toList();
      if (strings.isEmpty) {
        hsi.remove('source_ids');
      } else {
        hsi['source_ids'] = strings;
      }
    }

    final srcMap = hsi['sources'];
    if (srcMap is Map<String, dynamic>) {
      for (final entry in srcMap.values) {
        if (entry is Map<String, dynamic>) {
          entry.removeWhere(
            (k, _) => !HsiSchema.sourceFields.contains(k),
          );
          if (!HsiSchema.sourceTypes.contains(entry['type'])) {
            entry['type'] = 'derived';
          }
        }
      }
    }
  }

  void _patchAxes(Map<String, dynamic> hsi) {
    final axes = hsi['axes'];
    if (axes is! Map<String, dynamic>) return;

    // Drop unknown domains (additionalProperties: false).
    axes.removeWhere((k, _) => !HsiSchema.axisDomains.contains(k));

    for (final domain in axes.values) {
      if (domain is! Map<String, dynamic>) continue;
      final readings = domain['readings'];
      if (readings is! List) continue;
      for (final reading in readings) {
        if (reading is! Map<String, dynamic>) continue;
        reading.removeWhere(
          (k, _) => !HsiSchema.readingFields.contains(k),
        );

        final direction = reading['direction'];
        if (direction is String && !HsiSchema.directions.contains(direction)) {
          reading.remove('direction');
        }

        final evidence = reading['evidence_source_ids'];
        if (evidence is List) {
          final strings = evidence.whereType<String>().toList();
          if (strings.isEmpty) {
            reading.remove('evidence_source_ids');
          } else {
            reading['evidence_source_ids'] = strings;
          }
        }
      }
    }
  }

  void _patchWindows(Map<String, dynamic> hsi) {
    final windows = hsi['windows'];
    if (windows is! Map<String, dynamic>) return;

    for (final window in windows.values) {
      if (window is Map<String, dynamic>) {
        window.removeWhere(
          (k, _) => !HsiSchema.windowFields.contains(k),
        );
      }
    }
  }

  void _patchPrivacy(Map<String, dynamic> hsi) {
    final privacy = hsi['privacy'];
    if (privacy is! Map<String, dynamic>) return;

    final consent = privacy['consent'];
    if (consent is Map<String, dynamic>) {
      privacy['consent'] = consent['level']?.toString() ?? 'explicit';
    } else if (consent is String) {
      if (!HsiSchema.consentLevels.contains(consent)) {
        privacy['consent'] = 'explicit';
      }
    }
    final patchedConsent = privacy['consent'];
    if (patchedConsent is String &&
        !HsiSchema.consentLevels.contains(patchedConsent)) {
      privacy['consent'] = 'explicit';
    }

    privacy['contains_pii'] = false;
    privacy.putIfAbsent('raw_biosignals_allowed', () => false);
    privacy.putIfAbsent('derived_metrics_allowed', () => true);

    privacy.removeWhere(
      (k, _) => !HsiSchema.privacyFields.contains(k),
    );
  }
}
