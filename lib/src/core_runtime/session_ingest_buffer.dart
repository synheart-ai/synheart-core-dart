/// Batched event ingest for mobile sessions.
///
/// Accumulates sensor events in memory and flushes them to the Rust
/// runtime via a single `ingestBatch` FFI call every [flushInterval].
/// This avoids per-sample FFI overhead and matches the mobile-first
/// pattern described in the Flutter Integration Guide.
///
/// Usage (internal to Synheart SDK — not called directly by apps):
/// ```dart
/// final buffer = SessionIngestBuffer(bridge: coreRuntime);
/// buffer.start();
/// buffer.addRr(tsMs, rrMs, provider: 'polar');
/// buffer.addHr(tsMs, bpm, provider: 'ble');
/// // ... every 5s, flush fires automatically
/// buffer.stop(); // final flush + cleanup
/// ```
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'core_runtime_bridge.dart';

class SessionIngestBuffer {
  SessionIngestBuffer({
    required CoreRuntimeBridge bridge,
    this.flushInterval = const Duration(seconds: 5),
    this.onHsi,
  }) : _bridge = bridge;

  final CoreRuntimeBridge _bridge;
  final Duration flushInterval;

  /// Called when a flush produces HSI output.
  void Function(String hsiJson)? onHsi;

  final List<Map<String, dynamic>> _buffer = [];
  Timer? _timer;
  bool _running = false;

  /// Start the periodic flush timer.
  void start() {
    if (_running) return;
    _running = true;
    _buffer.clear();
    _timer = Timer.periodic(flushInterval, (_) => flush());
  }

  /// Stop the timer and perform a final flush.
  void stop() {
    _timer?.cancel();
    _timer = null;
    if (_running) {
      flush(); // drain remaining events
    }
    _running = false;
    _buffer.clear();
  }

  /// Whether the buffer is actively collecting.
  bool get isRunning => _running;

  // ── Event push methods ────────────────────────────────────────────

  void addRr(int tsMs, double rrMs, {String provider = 'default_sensor'}) {
    if (!_running) return;
    _buffer.add({
      'type': 'rr',
      'ts_ms': tsMs,
      'rr_ms': rrMs,
      'provider': provider,
    });
  }

  void addHr(int tsMs, double bpm, {String provider = 'default_sensor'}) {
    if (!_running) return;
    _buffer.add({
      'type': 'hr',
      'ts_ms': tsMs,
      'bpm': bpm,
      'provider': provider,
    });
  }

  void addVendorHrv(
    int tsMs, {
    double? rmssd,
    double? sdnn,
    double? stress,
    double? recovery,
    String provider = 'default_sensor',
  }) {
    if (!_running) return;
    _buffer.add({
      'type': 'vendor_hrv',
      'ts_ms': tsMs,
      if (rmssd != null) 'rmssd_ms': rmssd,
      if (sdnn != null) 'sdnn_ms': sdnn,
      if (stress != null) 'stress': stress,
      if (recovery != null) 'recovery': recovery,
      'provider': provider,
    });
  }

  void addAccel(int tsMs, double x, double y, double z,
      {String provider = 'default_sensor'}) {
    if (!_running) return;
    _buffer.add({
      'type': 'accel',
      'ts_ms': tsMs,
      'x': x,
      'y': y,
      'z': z,
      'provider': provider,
    });
  }

  void addBehavior(int tsMs, String event, {Map<String, dynamic>? options}) {
    if (!_running) return;
    _buffer.add({
      'type': 'behavior',
      'ts_ms': tsMs,
      'event': event,
      if (options != null) 'options': options,
    });
  }

  // ── Flush ─────────────────────────────────────────────────────────

  /// Drain the buffer into a single `ingestBatch` FFI call.
  /// Returns the HSI JSON if a window completed, null otherwise.
  String? flush() {
    final count = _buffer.length;
    if (_buffer.isEmpty) {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final hsi = _bridge.ingestBatch('[]', nowMs);
      if (hsi != null) {
        debugPrint('[IngestBuffer] tick produced HSI (${hsi.length} chars)');
        onHsi?.call(hsi);
      }
      return hsi;
    }

    _buffer.sort((a, b) =>
        (a['ts_ms'] as int).compareTo(b['ts_ms'] as int));

    final types = <String, int>{};
    for (final e in _buffer) {
      final t = e['type'] as String? ?? 'unknown';
      types[t] = (types[t] ?? 0) + 1;
    }
    final batchJson = jsonEncode(_buffer);
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    _buffer.clear();

    debugPrint('[IngestBuffer] flushing $count events ($types)');
    final hsi = _bridge.ingestBatch(batchJson, nowMs);
    if (hsi != null) {
      try {
        final parsed = jsonDecode(hsi) as Map<String, dynamic>;
        final axes = parsed['axes'] as Map<String, dynamic>? ?? {};
        final readings = <String>[];
        for (final body in axes.values) {
          final list = (body is Map ? body['readings'] : body) as List? ?? [];
          for (final r in list) {
            if (r is Map) {
              final a = r['axis'] ?? r['name'] ?? '?';
              final s = r['score'] ?? r['value'];
              final c = r['confidence'];
              final t = r['source_tier'];
              final m = (r['model_id'] as String?)?.split('://').last ?? '?';
              final scoreStr = s is num
                  ? s.toStringAsFixed(3)
                  : s is Map
                      ? s.entries.where((e) => e.value is num).map((e) => '${e.key}=${(e.value as num).toStringAsFixed(2)}').join(',')
                      : '$s';
              readings.add('$a=$scoreStr(c=${(c as num).toStringAsFixed(2)},t$t,$m)');
            }
          }
        }
        debugPrint('[HSI] ${readings.join(" | ")}');
      } catch (e) {
        debugPrint('[IngestBuffer] HSI (${hsi.length} chars)');
      }
      // Dump feature diagnostics for tier debugging
      try {
        final features = _bridge.lastFeatures();
        if (features != null) {
          final preview = features.length > 300 ? features.substring(0, 300) : features;
          debugPrint('[Features] ${features.length} chars: $preview');
        }
      } catch (_) {}
      onHsi?.call(hsi);
    } else {
      debugPrint('[IngestBuffer] result: null');
    }
    return hsi;
  }
}
