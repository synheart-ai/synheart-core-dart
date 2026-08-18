import 'dart:collection';

/// A fixed-capacity FIFO buffer that evicts its oldest entry once full.
///
/// Backs the in-memory session history behind
/// `Synheart.getSessionHsiWindows()` and `Synheart.getSessionWearSamples()`,
/// bounding what a long-running session can retain.
///
/// Eviction is silent by design: the durable record lives in the native
/// runtime's storage and is read back through `Synheart.getHSIWindows()`.
class BoundedBuffer<T> {
  /// Maximum entries retained; adding beyond this evicts from the front.
  ///
  /// Zero or less disables the buffer rather than unbounding it, so a
  /// misconfigured cap can never restore unbounded growth.
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
