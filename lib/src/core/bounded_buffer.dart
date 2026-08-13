import 'dart:collection';

/// A fixed-capacity FIFO buffer that evicts its oldest entry once full.
///
/// Backs the session HSI / wear buffers behind `Synheart.getSessionHsiWindows()`
/// and `Synheart.getSessionWearSamples()`. Those were plain growing lists,
/// cleared only on the *next* `startSession()` — so with the default 24h
/// session duration a long-running session retained roughly 8,600 HSI JSON
/// strings (one per ~10s window) and 86,000 wear samples, and kept holding them
/// after the session stopped.
///
/// Eviction is silent by design: the durable record lives in the native
/// runtime's storage and is read back through `Synheart.getHSIWindows()`. This
/// buffer only exists to serve recent in-memory history.
class BoundedBuffer<T> {
  /// Maximum entries retained. Adding beyond this evicts from the front.
  ///
  /// A capacity of zero (or less) makes [add] a no-op — the buffer is disabled
  /// rather than unbounded, so a misconfigured cap cannot reintroduce unbounded
  /// growth.
  final int capacity;

  final ListQueue<T> _items;

  BoundedBuffer(this.capacity) : _items = ListQueue<T>();

  /// Append [value], evicting the oldest entries if that exceeds [capacity].
  void add(T value) {
    if (capacity <= 0) return;
    _items.addLast(value);
    while (_items.length > capacity) {
      _items.removeFirst();
    }
  }

  void clear() => _items.clear();

  int get length => _items.length;

  bool get isEmpty => _items.isEmpty;

  bool get isNotEmpty => _items.isNotEmpty;

  /// True once [capacity] is reached and further [add]s start evicting.
  bool get isSaturated => _items.length >= capacity;

  /// An immutable oldest-first snapshot. Safe to hand to callers — later
  /// [add]s do not mutate a snapshot already returned.
  List<T> snapshot() => List<T>.unmodifiable(_items);
}
