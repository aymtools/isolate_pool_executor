import 'package:isolate_pool_executor/isolate_pool_executor.dart';
import 'package:test/test.dart';

/// 用于测试 WeightedQueue 的带优先级数据实体类
class _TaskItem {
  final String name;
  final int priority;

  _TaskItem(this.name, this.priority);
}

/// 针对 [WeightedQueue] 权重优先队列的单元测试
void main() {
  group('WeightedQueue tests', () {
    late WeightedQueue<_TaskItem> queue;

    setUp(() {
      // 创建以 priority 为权重计算依据的 WeightedQueue
      queue = WeightedQueue<_TaskItem>((item) => item.priority);
    });

    // 验证批量添加元素时，队列能够按照权重由高到低降序排列
    test('addAll maintains weight sorting descending', () {
      final items = [
        _TaskItem('low', 1),
        _TaskItem('high', 10),
        _TaskItem('medium', 5),
      ];

      queue.addAll(items);
      expect(queue.map((e) => e.name).toList(), equals(['high', 'medium', 'low']));
    });

    // 验证 removeFirst 总是移除并返回当前队列中权重最高的元素
    test('removeFirst removes highest weight item after addAll', () {
      queue.addAll([
        _TaskItem('p5', 5),
        _TaskItem('p20', 20),
        _TaskItem('p1', 1),
      ]);

      final highest = queue.removeFirst();
      expect(highest.name, equals('p20'));
      expect(queue.length, equals(2));
    });

    // 验证 removeLast 总是移除并返回当前队列中权重最低的元素
    test('removeLast removes lowest weight item after addAll', () {
      queue.addAll([
        _TaskItem('p5', 5),
        _TaskItem('p20', 20),
        _TaskItem('p1', 1),
      ]);

      final lowest = queue.removeLast();
      expect(lowest.name, equals('p1'));
      expect(queue.length, equals(2));
    });

    // 验证空队列执行 removeFirst 和 removeLast 时抛出 StateError
    test('removeFirst and removeLast on empty queue throw StateError', () {
      expect(() => queue.removeFirst(), throwsStateError);
      expect(() => queue.removeLast(), throwsStateError);
    });

    // 验证元素移除、条件过滤（removeWhere）、条件保留（retainWhere）及清空队列
    test('remove, removeWhere, retainWhere, clear', () {
      final item1 = _TaskItem('A', 10);
      final item2 = _TaskItem('B', 20);
      final item3 = _TaskItem('C', 30);

      queue.addAll([item1, item2, item3]);

      expect(queue.contains(item2), isTrue);
      expect(queue.remove(item2), isTrue);
      expect(queue.length, equals(2));

      queue.removeWhere((item) => item.priority == 30);
      expect(queue.length, equals(1));
      expect(queue.first.name, equals('A'));

      queue.addAll([item2]);
      queue.retainWhere((item) => item.priority >= 20);
      expect(queue.map((e) => e.name).toList(), equals(['B']));

      queue.clear();
      expect(queue.isEmpty, isTrue);
    });

    // 验证类型转换 cast 与 forEach 遍历功能
    test('cast and forEach', () {
      final item = _TaskItem('X', 50);
      queue.addAll([item]);

      final collected = <String>[];
      queue.forEach((e) => collected.add(e.name));
      expect(collected, equals(['X']));

      final casted = queue.cast<_TaskItem>();
      expect(casted.length, equals(1));
    });
  });
}
