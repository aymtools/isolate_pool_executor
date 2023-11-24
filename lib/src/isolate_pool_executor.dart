import 'dart:async';
import 'dart:collection';
import 'dart:isolate';

part 'isolate_pool_task.dart';

part 'isolate_pool_executor_core.dart';

part 'isolate_pool_executor_cache.dart';

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
          required RejectedExecutionHandler handler,
          Map<Object, Object?>? isolateValues}) =>
      _IsolatePoolExecutorCore(
          corePoolSize: corePoolSize,
          maximumPoolSize: maximumPoolSize,
          keepAliveTime: keepAliveTime,
          taskQueue: taskQueue,
          handler: handler,
          isolateValues: isolateValues);

  factory IsolatePoolExecutor.newFixedIsolatePool(int nIsolates,
          {Queue<ITask>? taskQueue,
          RejectedExecutionHandler? handler,
          Map<Object, Object?>? isolateValues}) =>
      _IsolatePoolExecutorCore(
          corePoolSize: nIsolates,
          maximumPoolSize: nIsolates,
          keepAliveTime: const Duration(seconds: 1),
          taskQueue: taskQueue ?? Queue(),
          handler: handler ?? RejectedExecutionHandler.abortPolicy,
          isolateValues: isolateValues);

  ///
  /// taskQueueInIsolate 为true时 taskQueueFactory 会跨isolate访问无法使用当前isolate中的数据
  factory IsolatePoolExecutor.newSingleIsolateExecutor(
          {bool taskQueueInIsolate = false,
          Queue<ITask> Function()? taskQueueFactory,
          RejectedExecutionHandler? handler,
          Map<Object, Object?>? isolateValues}) =>
      taskQueueInIsolate
          ? _IsolatePoolSingleExecutor(
              taskQueueFactory: taskQueueFactory, isolateValues: isolateValues)
          : IsolatePoolExecutor.newFixedIsolatePool(1,
              taskQueue: taskQueueFactory?.call(),
              handler: handler,
              isolateValues: isolateValues);

  ///
  factory IsolatePoolExecutor.newCachedIsolatePool(
          {Map<Object, Object?>? isolateValues}) =>
      _IsolatePoolExecutorCore(
          corePoolSize: 0,
          // java中int最大值 魔法数
          maximumPoolSize: 2147483647,
          keepAliveTime: const Duration(seconds: 1),
          taskQueue: Queue(),
          handler: RejectedExecutionHandler.abortPolicy,
          isolateValues: isolateValues);

  Future<R> compute<Q, R>(FutureOr<R> Function(Q message) callback, Q message,
      {String? debugLabel, int what = 0, dynamic tag});

  void shutdown({bool force = false});
}

final Map<Object, Object?> _isolateValues = {};

extension IsolateDataExt on Isolate {
  dynamic operator [](Object? key) => _isolateValues[key];
}
