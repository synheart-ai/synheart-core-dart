/// Constants derived from hsi-1.1.schema.json.
///
/// When the HSI schema is upgraded, update [version], add/modify the
/// domain and field sets, and the [HsiSchemaTransformer] adapts automatically.
///
/// See: https://github.com/synheart-ai/hsi/tree/main/schema
class HsiSchema {
  static const String version = '1.1';

  /// Valid top-level axis domain names (additionalProperties: false on `axes`).
  static const Set<String> axisDomains = {
    'physiological',
    'behavior',
    'engagement',
    'context',
  };

  /// Valid source types.
  static const Set<String> sourceTypes = {
    'sensor',
    'app',
    'self_report',
    'observer',
    'derived',
    'other',
  };

  /// Valid direction values for axis readings.
  static const Set<String> directions = {
    'higher_is_more',
    'higher_is_less',
    'bidirectional',
  };

  /// Valid embedding encoding formats.
  static const Set<String> encodings = {
    'float32',
    'float64',
    'fp16',
    'int8',
  };

  /// Valid privacy consent level values.
  static const Set<String> consentLevels = {
    'none',
    'implicit',
    'explicit',
  };

  /// Allowed fields on `axis_reading` (additionalProperties: false).
  static const Set<String> readingFields = {
    'axis',
    'score',
    'confidence',
    'window_id',
    'direction',
    'unit',
    'evidence_source_ids',
    'notes',
  };

  /// Allowed fields on `window` (additionalProperties: false).
  static const Set<String> windowFields = {'start', 'end', 'label'};

  /// Allowed fields on `producer` (additionalProperties: false).
  static const Set<String> producerFields = {
    'name',
    'version',
    'instance_id',
  };

  /// Allowed fields on `privacy` (additionalProperties: false).
  static const Set<String> privacyFields = {
    'contains_pii',
    'raw_biosignals_allowed',
    'derived_metrics_allowed',
    'embedding_allowed',
    'consent',
    'purposes',
    'notes',
  };

  /// Allowed fields on `source` (additionalProperties: false).
  static const Set<String> sourceFields = {
    'type',
    'quality',
    'degraded',
    'notes',
  };
}
