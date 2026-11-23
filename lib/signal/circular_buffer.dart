/// Buffer circular de capacidade fixa. Quando cheio, sobrescreve o item mais
/// antigo. Memória constante, push O(1).
class CircularBuffer<T> {
  CircularBuffer(this.capacity) {
    if (capacity <= 0) throw ArgumentError.value(capacity, 'capacity', 'deve ser maior que zero');
  }

  final int capacity;
  final List<T> _items = [];
  int _start = 0;

  int get length => _items.length;
  bool get isEmpty => _items.isEmpty;

  void push(T item) {
    if (_items.length < capacity) {
      _items.add(item);
    } else {
      _items[_start] = item;
      _start = (_start + 1) % capacity;
    }
  }

  /// Item mais antigo ainda no buffer.
  T? get first => _items.isEmpty ? null : _items[_start];

  /// Item mais recente.
  T? get last => _items.isEmpty ? null : _items[(_start + _items.length - 1) % _items.length];

  /// Cópia em ordem cronológica (do mais antigo ao mais recente).
  List<T> toList() => [for (var i = 0; i < _items.length; i++) _items[(_start + i) % _items.length]];

  void clear() {
    _items.clear();
    _start = 0;
  }
}
