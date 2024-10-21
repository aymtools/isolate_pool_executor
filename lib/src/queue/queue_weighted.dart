import 'dart:collection';

/// 可以自定义权重的队列
class WeightedQueue<T> extends IterableBase<T> implements Queue<T> {
  final List<T> _items = [];

  final int Function(T) _genWeighted;

  WeightedQueue(this._genWeighted);

  @override
  void addFirst(T value) {
    addLast(value);
  }

  @override
  void addLast(T value) {
    final weight = _genWeighted(value);
    _items.add(value);
    _items.sort((a, b) => _genWeighted(b).compareTo(weight)); // 从高到低排序
  }

  @override
  T removeFirst() {
    if (_items.isNotEmpty) {
      return _items.removeAt(0); // 移除并返回权重最高的元素
    }
    throw StateError('Queue is empty');
  }

  @override
  T removeLast() {
    if (_items.isNotEmpty) {
      return _items.removeAt(_items.length - 1);
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
  }

  @override
  bool remove(Object? value) {
    if (_items.remove(value)) {
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
  }

  @override
  void add(T value) {
    addLast(value);
  }

  @override
  void addAll(Iterable<T> iterable) {
    _items.addAll(iterable);
    _items.sort((a, b) => _genWeighted(b).compareTo(_genWeighted(a))); // 从高到低排序
  }

  @override
  void retainWhere(bool Function(T element) test) {
    _items.retainWhere(test);
  }

  @override
  Queue<R> cast<R>() {
    return Queue.of(_items.cast<R>());
  }
}
