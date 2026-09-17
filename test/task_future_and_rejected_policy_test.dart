import 'dart:async';
import 'dart:collection';

import 'package:isolate_pool_executor/isolate_pool_executor.dart';
import 'package:test/test.dart';

/// 模拟容量受限且超限抛出异常的阻塞队列
class ThrowingQueue extends ListQueue<ITask> {
  final int maxCapacity;

  ThrowingQueue(this.maxCapacity);

  @override
  void add(ITask value) {
    if (length >= maxCapacity) {
      throw StateError('Queue full exception');
    }
    super.add(value);
  }
}

/// 顶级测试函数，乘以2
int _doubleValue(int x) => x * 2;

/// 顶级测试函数，抛出 FormatException 格式化异常
Object? _throwError(dynamic _) {
  throw FormatException('invalid format');
}

/// 顶级测试函数，模拟耗时任务
Future<void> _longTask(dynamic _) async {
  await Future.delayed(const Duration(milliseconds: 300));
}

/// 针对 [TaskFuture] 与 [RejectedExecutionHandler] 饱和策略的单元测试
void main() {
  group('TaskFuture and RejectedExecutionHandler tests', () {
    // 验证 RejectedExecutionException 异常对象的 toString 格式
    test('RejectedExecutionException toString', () {
      final exc = RejectedExecutionException('test error');
      expect(exc.toString(), contains('RejectedExecutionException test error'));
    });

    // 验证 TaskFuture 的各种属性（what, tag, taskId）以及转换为 Stream 订阅
    test('TaskFuture properties and stream conversion', () async {
      final pool = IsolatePoolExecutor.newSingleIsolateExecutor();

      final future = pool.compute(
        _doubleValue,
        21,
        what: 42,
        tag: 'custom_tag',
        taskLabel: 'lbl',
      );

      expect(future.what, equals(42));
      expect(future.tag, equals('custom_tag'));
      expect(future.taskId, isA<int>());
      expect(future.source, isA<Future<int>>());

      final stream = future.asStream();
      final value = await stream.first;
      expect(value, equals(42));

      pool.shutdown();
    });

    // 验证 TaskFuture 的 Future 链式调用（then, catchError, whenComplete, timeout）
    test('TaskFuture then, catchError, whenComplete, timeout', () async {
      final pool = IsolatePoolExecutor.newSingleIsolateExecutor();

      bool whenCompletedCalled = false;

      final res = await pool
          .compute((int x) => x + 1, 10)
          .then((v) => v * 2)
          .whenComplete(() {
        whenCompletedCalled = true;
      });

      expect(res, equals(22));
      expect(whenCompletedCalled, isTrue);

      // 通过 catchError 捕获Isolate中抛出的异常
      final errFuture = pool.compute(_throwError, null);

      final caughtErr = await errFuture.catchError((Object err) => -1);
      expect(caughtErr, equals(-1));

      // 测试超时逻辑
      final timeoutTask = pool.compute(_longTask, null);

      expect(
        timeoutTask.timeout(const Duration(milliseconds: 10), onTimeout: () => null),
        completion(isNull),
      );

      pool.shutdown();
    });

    // 验证饱和策略 abortPolicy：队列满时直接抛出 RejectedExecutionException
    test('RejectedExecutionHandler.abortPolicy completes error with RejectedExecutionException', () async {
      final pool = IsolatePoolExecutor(
        corePoolSize: 1,
        maximumPoolSize: 1,
        taskQueue: ThrowingQueue(0), // 容量为0，添加即抛出异常
        handler: RejectedExecutionHandler.abortPolicy,
      );

      // 提交长耗时任务占据 Isolate
      pool.compute(_longTask, null);

      // 稍微等待确保 Isolate 已启动并处于忙碌状态
      await Future.delayed(const Duration(milliseconds: 10));

      // 提交新任务，因无法放入队列触发 abortPolicy 策略
      final future = pool.compute((_) => 100, null);

      expect(
        future,
        throwsA(isA<RejectedExecutionException>().having(
          (e) => e.toString(),
          'message',
          contains('Queue full exception'),
        )),
      );

      pool.shutdown(force: true);
    });

    // 验证饱和策略 callerRunsPolicy：队列满时退回到调用者所在的 Isolate 中同步执行
    test('RejectedExecutionHandler.callerRunsPolicy executes task in current isolate', () async {
      final pool = IsolatePoolExecutor(
        corePoolSize: 1,
        maximumPoolSize: 1,
        taskQueue: ThrowingQueue(0),
        handler: RejectedExecutionHandler.callerRunsPolicy,
      );

      // 占据 Isolate 的任务
      pool.compute(_longTask, null);

      await Future.delayed(const Duration(milliseconds: 10));

      // 新任务因队列满由主呼叫线程（主 Isolate）直接执行
      final result = await pool.compute((int val) => val * 10, 5);
      expect(result, equals(50));

      pool.shutdown(force: true);
    });

    // 验证饱和策略 discardOldestPolicy：队列满时丢弃阻塞队列中最老（头部）的任务
    test('RejectedExecutionHandler.discardOldestPolicy discards oldest queued task', () async {
      final pool = IsolatePoolExecutor(
        corePoolSize: 1,
        maximumPoolSize: 1,
        taskQueue: ThrowingQueue(1), // 容量为1
        handler: RejectedExecutionHandler.discardOldestPolicy,
      );

      // 任务 1：占据 Isolate
      pool.compute(_longTask, null);

      await Future.delayed(const Duration(milliseconds: 10));

      // 任务 2：填满队列容量
      final task2Future = pool.compute((_) => 'Task 2', null);

      // 任务 3：队列已满，discardOldestPolicy 会抛弃任务 2 并放入任务 3
      final task3Future = pool.compute((_) => 'Task 3', null);

      // 任务 3 最终会成功完成
      final res3 = await task3Future;
      expect(res3, equals('Task 3'));

      // 任务 2 被丢弃，不会正常返回结果（超时）
      expect(
        task2Future.timeout(const Duration(milliseconds: 10), onTimeout: () => 'timeout'),
        completion(equals('timeout')),
      );

      pool.shutdown();
    });

    // 验证饱和策略 discardPolicy：队列满时直接丢弃最新提交的任务
    test('RejectedExecutionHandler.discardPolicy discards new task', () async {
      final pool = IsolatePoolExecutor(
        corePoolSize: 1,
        maximumPoolSize: 1,
        taskQueue: ThrowingQueue(0),
        handler: RejectedExecutionHandler.discardPolicy,
      );

      // 任务 1：占据 Isolate
      pool.compute(_longTask, null);

      await Future.delayed(const Duration(milliseconds: 10));

      // 任务 2：因队列满直接被 discardPolicy 丢弃
      final task2Future = pool.compute((_) => 'Task 2', null);

      expect(
        task2Future.timeout(const Duration(milliseconds: 10), onTimeout: () => 'discarded'),
        completion(equals('discarded')),
      );

      pool.shutdown(force: true);
    });
  });
}
