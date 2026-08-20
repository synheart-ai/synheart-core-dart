// SPDX-License-Identifier: Apache-2.0
//
// High-level Dart API for the multi-source priority resolver.
//
// When the runtime exposes the priority-resolver FFI symbols (native runtime
// in newer builds), all calls route through them. When older runtimes load,
// or in unit tests with no native library, calls fall back to a pure-Dart
// in-memory store so consumer apps can still develop against the API.

import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../core_runtime/ffi_bindings.dart';
import 'priority_metric.dart';

/// Process-wide priority API.
///
/// Construct one [SynheartPriority] for the lifetime of the runtime
/// and reuse it. The class is a thin wrapper over the FFI store, with
/// graceful fallback to an in-memory implementation when the runtime
/// doesn't expose the symbols (older builds, headless tests).
class SynheartPriority {
  /// Build using the resolved FFI bindings. Pass `null` to force
  /// in-memory mode (used by tests).
  SynheartPriority({SynheartCoreFFI? ffi})
    : _ffi = ffi,
      _native = ffi?.prioritySetProvider != null;

  final SynheartCoreFFI? _ffi;
  final bool _native;

  // Pure-Dart fallback store — used when [_native] is false.
  final Map<String, int> _providers = {};
  final Map<({PriorityMetric metric, String provider}), int> _overrides = {};

  /// Whether calls route through the runtime FFI.
  bool get usingNativeStore => _native;

  /// Set the global rank for a provider. Lower wins.
  void setProviderPriority(String provider, int rank) {
    if (provider.isEmpty) {
      throw ArgumentError.value(provider, 'provider', 'must not be empty');
    }
    if (_native && _ffi != null) {
      final p = provider.toNativeUtf8();
      try {
        final rc = _ffi.prioritySetProvider!(p, rank);
        if (rc != 0) {
          throw StateError('runtime rejected setProviderPriority ($rc)');
        }
      } finally {
        malloc.free(p);
      }
      return;
    }
    _providers[provider] = rank;
  }

  /// Set or clear the per-metric override. Pass `null` for [rank] to
  /// clear; the metric falls back to the global rank.
  void setMetricOverride(PriorityMetric metric, String provider, int? rank) {
    if (provider.isEmpty) {
      throw ArgumentError.value(provider, 'provider', 'must not be empty');
    }
    if (_native && _ffi != null) {
      final m = metric.wireName.toNativeUtf8();
      final p = provider.toNativeUtf8();
      try {
        final rc = _ffi.prioritySetMetricOverride!(
          m,
          p,
          rank == null ? 0 : 1,
          rank ?? 0,
        );
        if (rc != 0) {
          throw StateError('runtime rejected setMetricOverride ($rc)');
        }
      } finally {
        malloc.free(m);
        malloc.free(p);
      }
      return;
    }
    final key = (metric: metric, provider: provider);
    if (rank == null) {
      _overrides.remove(key);
    } else {
      _overrides[key] = rank;
    }
  }

  /// Read the effective rank for `(metric, provider)`. Returns
  /// [kPriorityUnranked] for unknown providers.
  int effectiveRank(PriorityMetric metric, String provider) {
    if (_native && _ffi != null) {
      final m = metric.wireName.toNativeUtf8();
      final p = provider.toNativeUtf8();
      try {
        return _ffi.priorityEffectiveRank!(m, p);
      } finally {
        malloc.free(m);
        malloc.free(p);
      }
    }
    final key = (metric: metric, provider: provider);
    return _overrides[key] ?? _providers[provider] ?? kPriorityUnranked;
  }

  /// Resolve the winning source for [metric] given a `{provider:
  /// sample_count}` map. Returns `null` only when there's nothing to
  /// pick (empty input).
  SourceResolution? resolve(
    PriorityMetric metric,
    Map<String, int> samplesByProvider,
  ) {
    if (samplesByProvider.isEmpty) return null;

    if (_native && _ffi != null) {
      final m = metric.wireName.toNativeUtf8();
      final j = jsonEncode(samplesByProvider).toNativeUtf8();
      Pointer<Utf8> resultPtr = nullptr;
      try {
        resultPtr = _ffi.priorityResolve!(m, j);
        if (resultPtr == nullptr) return null;
        final raw = resultPtr.toDartString();
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final winner = decoded['winner'];
        if (winner == null) return null;
        return SourceResolution(
          winner: winner as String,
          rank: (decoded['rank'] as num).toInt(),
          alsoRan: ((decoded['also_ran'] as List?) ?? const [])
              .map((e) {
                final m = e as Map<String, dynamic>;
                return (
                  provider: m['provider'] as String,
                  rank: (m['rank'] as num).toInt(),
                );
              })
              .toList(growable: false),
        );
      } finally {
        malloc.free(m);
        malloc.free(j);
        if (resultPtr != nullptr) {
          // Free the runtime-allocated string. The same `coreFreeString`
          // that handles every other FFI string also handles this one.
          _ffi.coreFreeString(resultPtr);
        }
      }
    }

    return _resolveInMemory(metric, samplesByProvider);
  }

  SourceResolution? _resolveInMemory(
    PriorityMetric metric,
    Map<String, int> samplesByProvider,
  ) {
    final candidates = samplesByProvider.entries
        .where((e) => e.value > 0)
        .map(
          (e) => (
            provider: e.key,
            rank: effectiveRank(metric, e.key),
            count: e.value,
          ),
        )
        .toList();
    if (candidates.isEmpty) return null;

    candidates.sort((a, b) {
      final byRank = a.rank.compareTo(b.rank);
      if (byRank != 0) return byRank;
      final byCount = b.count.compareTo(a.count);
      if (byCount != 0) return byCount;
      return a.provider.compareTo(b.provider);
    });

    final winner = candidates.first;
    final alsoRan = candidates
        .skip(1)
        .map((c) => (provider: c.provider, rank: c.rank))
        .toList(growable: false);

    return SourceResolution(
      winner: winner.provider,
      rank: winner.rank,
      alsoRan: alsoRan,
    );
  }
}
