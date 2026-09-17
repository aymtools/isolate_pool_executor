import 'dart:async';

import 'package:isolate_pool_executor/isolate_pool_executor.dart';
import 'package:test/test.dart';

/// 顶级测试函数：计算平方
int _square(int n) => n * n;

/// 针对 CachedIsolatePool (缓存池) 的单元测试
void main() {
  group('IsolatePoolExecutor Cached Pool tests', () {
    // 验证 newCachedIsolatePool 能根据需要自动创建多个 Isolate 并行处理任务
    test('newCachedIsolatePool handles concurrent tasks', () async {
      final pool = IsolatePoolExecutor.newCachedIsolatePool(
        keepAliveTime: const Duration(milliseconds: 200),
        debugLabel: 'CachedPoolTest',
      );

      final futures = List.generate(
        10,
        (i) => pool.compute(_square, i),
      );

      final results = await Future.wait(futures);
      expect(results, equals([0, 1, 4, 9, 16, 25, 36, 49, 64, 81]));

      pool.shutdown();
      expect(pool.isShutdown, isTrue);
    });

    // 验证缓存池在有空闲 Isolate 时优先复用空闲 Isolate
    test('cached pool reuses idle isolates before spawning new ones', () async {
      final pool = IsolatePoolExecutor.newCachedIsolatePool(
        keepAliveTime: const Duration(seconds: 2),
      );

      // 第一批任务
      final r1 = await pool.compute(_square, 5);
      expect(r1, equals(25));

      // 第二批任务复用已有的空闲 Isolate
      final r2 = await pool.compute(_square, 6);
      expect(r2, equals(36));

      pool.shutdown();
    });

    // 验证缓存池配合 isolateValues 与 onIsolateCreated 初始化回调
    test('cached pool with isolateValues and onIsolateCreated', () async {
      final pool = IsolatePoolExecutor.newCachedIsolatePool(
        isolateValues: {'token': 'secret_123'},
        onIsolateCreated: (values) {
          values['ready'] = true;
        },
      );

      final token = await pool.compute((_) => currentIsolate['token'], null);
      final ready = await pool.compute((_) => currentIsolate['ready'], null);

      expect(token, equals('secret_123'));
      expect(ready, equals(true));

      pool.shutdown();
    });

    // 验证 keepAliveTime 为 Duration.zero 时，使用不缓存模式执行任务（执行完即销毁）
    test('cached pool with zero keepAliveTime uses no-cache executor', () async {
      final pool = IsolatePoolExecutor.newCachedIsolatePool(
        keepAliveTime: Duration.zero,
      );

      final r1 = await pool.compute(_square, 7);
      expect(r1, equals(49));

      final r2 = await pool.compute(_square, 8);
      expect(r2, equals(64));

      pool.shutdown();
    });
  });
}
