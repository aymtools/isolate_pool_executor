import 'package:isolate_pool_executor/isolate_pool_executor.dart';
import 'package:test/test.dart';

/// 针对 [QueueEmpty] 类的单元测试，验证空队列的各项方法行为
void main() {
  group('QueueEmpty tests', () {
    late QueueEmpty<int> queue;

    setUp(() {
      queue = QueueEmpty<int>();
    });

    // 验证初始状态下的各项属性（如 isEmpty, length, join 等）
    test('initial properties', () {
      expect(queue.isEmpty, isTrue);
      expect(queue.isNotEmpty, isFalse);
      expect(queue.length, equals(0));
      expect(queue.join(','), equals(''));
      expect(queue.toList(), isEmpty);
      expect(queue.toSet(), isEmpty);
    });

    // 验证向空队列添加元素时是否抛出 StateError 异常
    test('add methods throw StateError', () {
      expect(() => queue.add(1), throwsStateError);
      expect(() => queue.addAll([1, 2]), throwsStateError);
      expect(() => queue.addFirst(1), throwsStateError);
      expect(() => queue.addLast(1), throwsStateError);
    });

    // 验证访问或移除空队列的元素时抛出 StateError 异常
    test('element access methods throw StateError', () {
      expect(() => queue.first, throwsStateError);
      expect(() => queue.last, throwsStateError);
      expect(() => queue.single, throwsStateError);
      expect(() => queue.removeFirst(), throwsStateError);
      expect(() => queue.removeLast(), throwsStateError);
      expect(() => queue.elementAt(0), throwsStateError);
      expect(() => queue.reduce((a, b) => a + b), throwsStateError);
      expect(() => queue.firstWhere((e) => true), throwsStateError);
      expect(() => queue.lastWhere((e) => true), throwsStateError);
      expect(() => queue.singleWhere((e) => true), throwsStateError);
    });

    // 验证空队列的检索与判断方法返回 false 或默认值
    test('search and check methods return false/default', () {
      expect(queue.contains(1), isFalse);
      expect(queue.any((e) => true), isFalse);
      expect(queue.every((e) => true), isFalse);
      expect(queue.remove(1), isFalse);
      expect(queue.fold<int>(10, (prev, e) => prev + e), equals(10));
    });

    // 验证空队列迭代器的移动与当前元素获取行为
    test('iterator behavior', () {
      final iterator = queue.iterator;
      expect(iterator.moveNext(), isFalse);
      expect(() => iterator.current, throwsStateError);
    });

    // 验证变换与过滤操作均返回空集合
    test('transformation and filtering return empty iterables', () {
      expect(queue.cast<String>(), isA<QueueEmpty<String>>());
      expect(queue.expand((e) => [e]), isEmpty);
      expect(queue.followedBy([1, 2]), isEmpty);
      expect(queue.map((e) => e * 2), isEmpty);
      expect(queue.skip(1), isEmpty);
      expect(queue.skipWhile((e) => true), isEmpty);
      expect(queue.take(1), isEmpty);
      expect(queue.takeWhile((e) => true), isEmpty);
      expect(queue.where((e) => true), isEmpty);
      expect(queue.whereType<double>(), isEmpty);
    });

    // 验证空队列的无效应答操作（清空、遍历等）正常执行且不引发异常
    test('no-op methods do not throw', () {
      expect(() => queue.clear(), returnsNormally);
      expect(() => queue.forEach((e) {}), returnsNormally);
      expect(() => queue.removeWhere((e) => true), returnsNormally);
      expect(() => queue.retainWhere((e) => true), returnsNormally);
    });

    // 验证 IterableElementError 工具类返回的各种 StateError 实例
    test('IterableElementError helpers', () {
      final errNoElement = IterableElementError.noElement();
      expect(errNoElement, isA<StateError>());
      expect(errNoElement.message, equals('No element'));

      final errTooMany = IterableElementError.tooMany();
      expect(errTooMany, isA<StateError>());
      expect(errTooMany.message, equals('Too many elements'));

      final errTooFew = IterableElementError.tooFew();
      expect(errTooFew, isA<StateError>());
      expect(errTooFew.message, equals('Too few elements'));
    });
  });
}
