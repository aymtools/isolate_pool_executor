import 'package:isolate_pool_executor/isolate_pool_executor.dart';
import 'package:test/test.dart';

/// 用于测试 UniqueQueue 的数据实体类
class _TestItem {
  final int id;
  final String name;

  _TestItem(this.id, this.name);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _TestItem &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name;

  @override
  int get hashCode => id.hashCode ^ name.hashCode;
}

/// 针对 [UniqueQueue] 自动去重队列的单元测试
void main() {
  group('UniqueQueue tests', () {
    late UniqueQueue<_TestItem> queue;

    setUp(() {
      // 创建以 item.id 为唯一标识依据的 UniqueQueue
      queue = UniqueQueue<_TestItem>((item) => item.id);
    });

    // 验证从尾部添加元素以及自动忽略重复 ID 的行为
    test('addLast and deduplication', () {
      final item1 = _TestItem(1, 'A');
      final item2 = _TestItem(2, 'B');
      final item1Duplicate = _TestItem(1, 'A_dup');

      queue.add(item1);
      queue.addLast(item2);
      queue.add(item1Duplicate); // 因 id=1 已存在，此元素会被忽略

      expect(queue.length, equals(2));
      expect(queue.map((e) => e.name).toList(), equals(['A', 'B']));
    });

    // 验证从头部插入元素以及自动忽略重复 ID 的行为
    test('addFirst and deduplication', () {
      final item1 = _TestItem(1, 'A');
      final item2 = _TestItem(2, 'B');
      final item2Duplicate = _TestItem(2, 'B_dup');

      queue.add(item1);
      queue.addFirst(item2);
      queue.addFirst(item2Duplicate); // 忽略重复项

      expect(queue.length, equals(2));
      expect(queue.map((e) => e.name).toList(), equals(['B', 'A']));
    });

    // 验证批量添加带重复项的列表时的过滤效果
    test('addAll with duplicates', () {
      final items = [
        _TestItem(1, 'A'),
        _TestItem(2, 'B'),
        _TestItem(1, 'A2'),
        _TestItem(3, 'C'),
      ];

      queue.addAll(items);
      expect(queue.length, equals(3));
      expect(queue.map((e) => e.id).toList(), equals([1, 2, 3]));
    });

    // 验证移除头部/尾部元素后，对应 ID 能够重新被添加到队列中
    test('removeFirst and removeLast allow re-adding same key', () {
      final item1 = _TestItem(1, 'A');
      final item2 = _TestItem(2, 'B');

      queue.addAll([item1, item2]);

      final removedFirst = queue.removeFirst();
      expect(removedFirst.id, equals(1));
      expect(queue.length, equals(1));

      // 移除 key 1 后，重新添加 key 1 应当成功
      final newItem1 = _TestItem(1, 'New_A');
      queue.add(newItem1);
      expect(queue.length, equals(2));

      final removedLast = queue.removeLast();
      expect(removedLast.id, equals(1));
      expect(queue.length, equals(1));
    });

    // 验证空队列执行 removeFirst 和 removeLast 时抛出 StateError
    test('removeFirst / removeLast on empty queue throw StateError', () {
      expect(() => queue.removeFirst(), throwsStateError);
      expect(() => queue.removeLast(), throwsStateError);
    });

    // 验证移除特定元素并更新已使用键集合的行为
    test('remove specific item', () {
      final item1 = _TestItem(1, 'A');
      final item2 = _TestItem(2, 'B');
      queue.addAll([item1, item2]);

      expect(queue.remove(item1), isTrue);
      expect(queue.length, equals(1));
      expect(queue.remove(_TestItem(99, 'X')), isFalse);

      // 重新添加 id=1
      queue.add(_TestItem(1, 'A_readded'));
      expect(queue.length, equals(2));
    });

    // 验证按条件删除（removeWhere）与按条件保留（retainWhere）的功能
    test('removeWhere and retainWhere', () {
      final item1 = _TestItem(1, 'A');
      final item2 = _TestItem(2, 'B');
      final item3 = _TestItem(3, 'C');
      queue.addAll([item1, item2, item3]);

      queue.removeWhere((item) => item.id == 2);
      expect(queue.map((e) => e.id).toList(), equals([1, 3]));

      // 删除后可重新添加 id=2
      queue.add(_TestItem(2, 'B2'));
      expect(queue.length, equals(3));

      queue.retainWhere((item) => item.id == 3);
      expect(queue.length, equals(1));
      expect(queue.first.id, equals(3));
    });

    // 验证 contains, forEach, clear 以及类型转换 cast 方法
    test('contains, forEach, clear, and cast', () {
      final item1 = _TestItem(1, 'A');
      final item2 = _TestItem(2, 'B');
      queue.addAll([item1, item2]);

      expect(queue.contains(item1), isTrue);
      expect(queue.contains(_TestItem(99, 'Z')), isFalse);

      final iteratedNames = <String>[];
      queue.forEach((item) => iteratedNames.add(item.name));
      expect(iteratedNames, equals(['A', 'B']));

      final casted = queue.cast<_TestItem>();
      expect(casted.length, equals(2));

      queue.clear();
      expect(queue.isEmpty, isTrue);
      expect(queue.length, equals(0));
    });
  });
}
