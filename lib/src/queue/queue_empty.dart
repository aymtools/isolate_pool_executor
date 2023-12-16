import 'dart:collection';

/** The always empty iterator. */
class EmptyIterator<E> implements Iterator<E> {
  const EmptyIterator();

  bool moveNext() => false;

  E get current {
    throw IterableElementError.noElement();
  }
}

/**
 * The always empty Queue.
 */
class QueueEmpty<E> implements Queue<E> {
  @override
  void add(E value) {
    throw IterableElementError.tooMany();
  }

  @override
  void addAll(Iterable<E> iterable) {
    throw IterableElementError.tooMany();
  }

  @override
  void addFirst(E value) {
    throw IterableElementError.tooMany();
  }

  @override
  void addLast(E value) {
    throw IterableElementError.tooMany();
  }

  @override
  bool any(bool Function(E element) test) {
    return false;
  }

  @override
  Queue<R> cast<R>() {
    return QueueEmpty<R>();
  }

  @override
  void clear() {}

  @override
  bool contains(Object? element) {
    return false;
  }

  @override
  E elementAt(int index) {
    throw IterableElementError.noElement();
  }

  @override
  bool every(bool Function(E element) test) {
    return false;
  }

  @override
  Iterable<T> expand<T>(Iterable<T> Function(E element) toElements) {
    return Iterable<T>.empty();
  }

  @override
  E get first => throw IterableElementError.noElement();

  @override
  E firstWhere(bool Function(E element) test, {E Function()? orElse}) {
    throw IterableElementError.noElement();
  }

  @override
  T fold<T>(T initialValue, T Function(T previousValue, E element) combine) {
    return initialValue;
  }

  @override
  Iterable<E> followedBy(Iterable<E> other) {
    return Iterable<E>.empty();
  }

  @override
  void forEach(void Function(E element) action) {}

  @override
  bool get isEmpty => true;

  @override
  bool get isNotEmpty => false;

  @override
  Iterator<E> get iterator => EmptyIterator<E>();

  @override
  String join([String separator = ""]) {
    return '';
  }

  @override
  E get last => throw IterableElementError.noElement();

  @override
  E lastWhere(bool Function(E element) test, {E Function()? orElse}) {
    throw IterableElementError.noElement();
  }

  @override
  int get length => 0;

  @override
  Iterable<T> map<T>(T Function(E e) toElement) {
    return Iterable<T>.empty();
  }

  @override
  E reduce(E Function(E value, E element) combine) {
    throw IterableElementError.noElement();
  }

  @override
  bool remove(Object? value) {
    return false;
  }

  @override
  E removeFirst() {
    throw IterableElementError.noElement();
  }

  @override
  E removeLast() {
    throw IterableElementError.noElement();
  }

  @override
  void removeWhere(bool Function(E element) test) {}

  @override
  void retainWhere(bool Function(E element) test) {}

  @override
  E get single => throw IterableElementError.noElement();

  @override
  E singleWhere(bool Function(E element) test, {E Function()? orElse}) {
    throw IterableElementError.noElement();
  }

  @override
  Iterable<E> skip(int count) {
    return Iterable<E>.empty();
  }

  @override
  Iterable<E> skipWhile(bool Function(E value) test) {
    return Iterable<E>.empty();
  }

  @override
  Iterable<E> take(int count) {
    return Iterable<E>.empty();
  }

  @override
  Iterable<E> takeWhile(bool Function(E value) test) {
    return Iterable<E>.empty();
  }

  @override
  List<E> toList({bool growable = true}) {
    return List<E>.empty(growable: growable);
  }

  @override
  Set<E> toSet() {
    return <E>{};
  }

  @override
  Iterable<E> where(bool Function(E element) test) {
    return Iterable<E>.empty();
  }

  @override
  Iterable<T> whereType<T>() {
    return Iterable<T>.empty();
  }
}

/**
 * Creates errors throw by [Iterable] when the element count is wrong.
 */
abstract class IterableElementError {
  /** Error thrown thrown by, e.g., [Iterable.first] when there is no result. */
  static StateError noElement() => StateError("No element");

  /** Error thrown by, e.g., [Iterable.single] if there are too many results. */
  static StateError tooMany() => StateError("Too many elements");

  /** Error thrown by, e.g., [List.setRange] if there are too few elements. */
  static StateError tooFew() => StateError("Too few elements");
}
