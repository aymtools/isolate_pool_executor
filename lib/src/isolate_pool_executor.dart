import 'dart:async';
import 'dart:collection';
import 'dart:isolate';

part 'isolate_pool_task.dart';

part 'isolate_pool_executor_core.dart';

part 'isolate_pool_executor_single.dart';

///饱和策略，当阻塞队列满了，且没有空闲的工作线程，如果继续提交任务，必须采取一种策略处理该任务，提供4种策略:
enum RejectedExecutionHandler {
  ///直接抛出异常，默认策略；
  abortPolicy,

  ///用调用者所在的Isolate来执行任务；
  callerRunsPolicy,

  ///丢弃阻塞队列中靠最前的任务，并执行当前任务；
  discardOldestPolicy,

  ///直接丢弃任务；
  discardPolicy,
}

abstract class IsolatePoolExecutor {
  factory IsolatePoolExecutor(
          {required int corePoolSize,
          required int maximumPoolSize,
          required Duration keepAliveTime,
          required Queue<ITask> taskQueue,
          required RejectedExecutionHandler handler}) =>
      _IsolatePoolExecutorCore(
          corePoolSize: corePoolSize,
          maximumPoolSize: maximumPoolSize,
          keepAliveTime: keepAliveTime,
          taskQueue: taskQueue,
          handler: handler);

  factory IsolatePoolExecutor.newFixedIsolatePool(int nIsolates,
          {Queue<ITask>? taskQueue, RejectedExecutionHandler? handler}) =>
      _IsolatePoolExecutorCore(
          corePoolSize: nIsolates,
          maximumPoolSize: nIsolates,
          keepAliveTime: const Duration(seconds: 1),
          taskQueue: taskQueue ?? Queue(),
          handler: handler ?? RejectedExecutionHandler.abortPolicy);

  ///
  /// taskQueueInIsolate 为true时 taskQueueFactory 会跨isolate访问无法使用当前isolate中的数据
  factory IsolatePoolExecutor.newSingleIsolateExecutor(
          {bool taskQueueInIsolate = false,
          Queue<ITask> Function()? taskQueueFactory,
          RejectedExecutionHandler? handler}) =>
      taskQueueInIsolate
          ? _IsolatePoolSingleExecutor(taskQueueFactory: taskQueueFactory)
          : IsolatePoolExecutor.newFixedIsolatePool(1,
              taskQueue: taskQueueFactory?.call(), handler: handler);

  ///
  ///
  factory IsolatePoolExecutor.newCachedIsolatePool() =>
      _IsolatePoolExecutorCore(
          corePoolSize: 0,
          // java中int最大值 魔法数
          maximumPoolSize: 2147483647,
          keepAliveTime: const Duration(),
          taskQueue: Queue(),
          handler: RejectedExecutionHandler.abortPolicy);

  Future<R> compute<Q, R>(FutureOr<R> Function(Q message) callback, Q message,
      {String? debugLabel, int what = 0, dynamic tag});

  void shutdown({bool force = false});
}
