import 'dart:async';

import 'package:isolate_pool_executor/isolate_pool_executor.dart';
import 'package:test/test.dart';

/// 顶级函数：求和计算
int _addNumbers(List<int> numbers) {
  return numbers.reduce((a, b) => a + b);
}

/// 顶级函数：读取特定密钥在当前 Isolate 中存放的数据
Object? _readIsolateValue(Object key) {
  return currentIsolate[key];
}

/// 顶级函数：自定义任务执行器 TaskInvoker，对返回值附加累加运算
Future<dynamic> _customTaskInvoker(
  int taskId,
  FutureOr Function(dynamic) function,
  dynamic message,
  String taskLabel,
  int what,
  dynamic tag,
) async {
  dynamic result = function(message);
  if (result is Future) {
    result = await result;
  }
  return (result as int) + what;
}

/// 针对核心与固定数量 Isolate 池的单元测试
void main() {
  group('IsolatePoolExecutor Core and Fixed Pool tests', () {
    // 验证 launchCoreImmediately 参数：创建线程池时立即启动所有核心 Isolate
    test('launchCoreImmediately starts core isolates immediately', () async {
      final pool = IsolatePoolExecutor.newFixedIsolatePool(
        2,
        launchCoreImmediately: true,
      );

      final res1 = await pool.execute(_addNumbers, [1, 2, 3]);
      final res2 = await pool.execute(_addNumbers, [10, 20]);

      expect(res1, equals(6));
      expect(res2, equals(30));

      pool.shutdown();
      expect(pool.isShutdown, isTrue);
    });

    // 验证 immediatelyStartedCore 参数：创建线程池时预先启动指定数量的核心 Isolate
    test('immediatelyStartedCore starts specified number of core isolates', () async {
      final pool = IsolatePoolExecutor(
        corePoolSize: 3,
        maximumPoolSize: 3,
        launchCoreImmediately: false,
        immediatelyStartedCore: 2,
      );

      final futures = List.generate(
        3,
        (i) => pool.compute((int val) => val * 2, i + 1),
      );

      final results = await Future.wait(futures);
      expect(results, equals([2, 4, 6]));

      pool.shutdown();
    });

    // 验证 isolateValues 数据共享与 onIsolateCreated 回调执行
    test('isolateValues and onIsolateCreated', () async {
      final pool = IsolatePoolExecutor.newFixedIsolatePool(
        1,
        isolateValues: {'app_id': 'test_app_123', 'env': 'test'},
        onIsolateCreated: _setupIsolateValues,
      );

      final appId = await pool.compute(_readIsolateValue, 'app_id');
      final env = await pool.compute(_readIsolateValue, 'env');
      final init = await pool.compute(_readIsolateValue, 'initialized');

      expect(appId, equals('test_app_123'));
      expect(env, equals('test'));
      expect(init, equals(true));

      pool.shutdown();
    });

    // 验证 customizeTaskInvoker 自定义任务执行器
    test('customizeTaskInvoker customizes task execution', () async {
      final pool = IsolatePoolExecutor.newFixedIsolatePool(
        1,
        customizeTaskInvoker: _customTaskInvoker,
      );

      final res = await pool.compute(
        (int input) => input + 10,
        5,
        what: 100,
        tag: 'TAG_A',
        taskLabel: 'CustomTaskLabel',
      );

      expect(res, equals(115)); // (5 + 10) + 100

      pool.shutdown();
    });

    test('execute extension alias works identically to compute', () async {
      final pool = IsolatePoolExecutor.newFixedIsolatePool(1);

      final res = await pool.execute(
        (String str) => str.toUpperCase(),
        'hello world',
        debugLabel: 'dbg_label',
        what: 1,
        tag: 'ext_tag',
        taskLabel: 'ext_task_label',
      );

      expect(res, equals('HELLO WORLD'));

      pool.shutdown();
    });

    // 验证线程池关闭后提交新任务会抛出错误提示
    test('submitting task after shutdown throws String message', () {
      final pool = IsolatePoolExecutor.newFixedIsolatePool(1, debugLabel: 'my_pool');

      pool.shutdown();
      expect(pool.isShutdown, isTrue);

      expect(
        () => pool.compute((_) => 1, null),
        throwsA(isA<String>().having(
          (s) => s,
          'message',
          contains('IsolatePoolExecutor-my_pool is shutdown'),
        )),
      );
    });

    // 验证 shutdown(force: true) 强制关闭线程池并清空排队任务
    test('shutdown with force: true clears taskQueue and closes core executors', () async {
      final pool = IsolatePoolExecutor.newFixedIsolatePool(1);

      // 提交耗时任务
      pool.compute((_) async {
        await Future.delayed(const Duration(milliseconds: 200));
      }, null);

      // 强制立即关闭线程池
      pool.shutdown(force: true);
      expect(pool.isShutdown, isTrue);
    });
  });
}

/// Isolate 启动初始化回调：注入初始化变量
void _setupIsolateValues(Map<Object, Object?> values) {
  values['initialized'] = true;
}
