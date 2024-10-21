import 'dart:collection';

/// 可以根据规则 自动去重的队列
class UniqueQueue<T> extends IterableBase<T> implements Queue<T> {
  final List<T> _items = [];
  final Set<Object> _seen = {};

  final Object Function(T) _genUnique;

  UniqueQueue(this._genUnique);

  @override
  void addFirst(T value) {
    final uniqueProperty = _genUnique(value);
    if (_seen.add(uniqueProperty)) {
      _items.insert(0, value);
    }
  }

  @override
  void addLast(T value) {
    final uniqueProperty = _genUnique(value);
    if (_seen.add(uniqueProperty)) {
      _items.add(value);
    }
  }

  @override
  T removeFirst() {
    if (_items.isNotEmpty) {
      final item = _items.removeAt(0);
      _seen.remove(_genUnique(item));
      return item;
    }
    throw StateError('Queue is empty');
  }

  @override
  T removeLast() {
    if (_items.isNotEmpty) {
      final item = _items.removeAt(_items.length - 1);
      _seen.remove(_genUnique(item));
      return item;
    }
    throw StateError('Queue is empty');
  }

  @override
  bool get isEmpty => _items.isEmpty;

  @override
  int get length => _items.length;

  @override
  Iterator<T> get iterator => _items.iterator;

  @override
  void clear() {
    _items.clear();
    _seen.clear();
  }

  @override
  bool remove(Object? value) {
    if (_items.remove(value)) {
      if (value is T) {
        _seen.remove(_genUnique(value));
      }
      return true;
    }
    return false;
  }

  @override
  void forEach(void Function(T element) f) {
    _items.forEach(f);
  }

  @override
  bool contains(Object? element) => _items.contains(element);

  @override
  void removeWhere(bool Function(T element) test) {
    _items.removeWhere(test);
    _seen.clear();
    for (var item in _items) {
      _seen.add(_genUnique(item));
    }
  }

  @override
  void add(T value) {
    addLast(value);
  }

  @override
  void addAll(Iterable<T> iterable) {
    for (var item in iterable) {
      add(item);
    }
  }

  @override
  void retainWhere(bool Function(T element) test) {
    _items.retainWhere(test);
    _seen.clear();
    for (var item in _items) {
      _seen.add(_genUnique(item));
    }
  }

  @override
  Queue<R> cast<R>() {
    return Queue.of(_items.cast<R>());
  }
}
