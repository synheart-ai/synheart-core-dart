import 'dart:convert';

/// Suppresses HSI windows that reach Dart more than once.
///
/// A completed window can arrive by two routes: the native HSI callback, and the
/// return value of a batch ingest. A window completed by a per-event push
/// (`pushWearHr`, `pushVendorHrv`) travels both, so it would otherwise be
/// delivered twice.
///
/// Identity is `meta.ids.hsi_id` (RFC-IDENTITY-0001) — the same key the runtime
/// uses to deduplicate ingest rows.
class HsiDeliveryDeduper {
  HsiDeliveryDeduper({this.capacity = 100});

  /// Upper bound on remembered ids. Sized to absorb interleaving between the
  /// two delivery routes, not to deduplicate across an entire session.
  final int capacity;

  /// Dart's default `Set` is a `LinkedHashSet`: iteration is insertion ordered,
  /// so `.first` is the oldest entry and eviction below is FIFO.
  final Set<String> _seen = <String>{};

  /// Ids currently remembered. Exposed for diagnostics and tests.
  int get length => _seen.length;

  /// Whether [hsiJson] should be delivered: true the first time a window is
  /// seen, false for any repeat.
  ///
  /// A payload carrying no `meta.ids.hsi_id` is always delivered — it cannot be
  /// identified, and dropping a window is worse than repeating one.
  bool shouldDeliver(String hsiJson) {
    final id = extractHsiId(hsiJson);
    if (id == null) return true;
    if (!_seen.add(id)) return false;
    if (_seen.length > capacity) {
      _seen.remove(_seen.first);
    }
    return true;
  }

  /// Forget every id. Call on session start and teardown so an id from a
  /// previous session cannot suppress the next session's first window.
  void reset() => _seen.clear();

  /// Pull `meta.ids.hsi_id` out of a raw HSI payload.
  ///
  /// Null when the payload is unparseable, is not an object, or predates
  /// RFC-IDENTITY-0001.
  static String? extractHsiId(String hsiJson) {
    try {
      final root = jsonDecode(hsiJson);
      if (root is! Map) return null;
      final meta = root['meta'];
      if (meta is! Map) return null;
      final ids = meta['ids'];
      if (ids is! Map) return null;
      final id = ids['hsi_id'];
      return (id is String && id.isNotEmpty) ? id : null;
    } catch (_) {
      return null;
    }
  }
}
