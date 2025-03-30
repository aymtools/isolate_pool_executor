import 'dart:async';
import 'dart:collection';
import 'dart:isolate';
import 'dart:math';

import 'package:isolate_pool_executor/src/queue/queue_empty.dart';

part 'future/task_future.dart';
part 'isolate_pool_executor_cache.dart';
part 'isolate_pool_executor_core.dart';
part 'isolate_pool_executor_single.dart';
part 'isolate_pool_task.dart';

///饱和策略，当阻塞队列满了，且没有空闲的工作线程，如果继续提交任务，必须采取一种策略处理该任务，提供4种策略:
enum RejectedExecutionHandler {
  ///直接抛出异常，默认策略；
  abortPolicy,

  ///用调用者所在的Isolate来执行任务；
  callerRunsPolicy,

  ///丢弃阻塞队列中靠最前的任务；
  discardOldestPolicy,

  ///直接丢弃任务；
  discardPolicy,
}

/// 兼容旧版本 未来移除
TaskInvoker? _warpTaskInvoker(
    Future<dynamic> Function(
            int taskId, FutureOr Function(dynamic) function, dynamic message)?
        invoker) {
  if (invoker == null) return null;
  return (taskId, function, message, _, __, ___) =>
      invoker(taskId, function, message);
}

/// 池化的isolate
abstract class IsolatePoolExecutor {
  /// [launchCoreImmediately] 是否立即启动所有的核心isolate
  /// 如果值为false时 同时判断[immediatelyStartedCore] 自定义的启动数量，不超过[corePoolSize]
  factory IsolatePoolExecutor({
    required int corePoolSize,
    required int maximumPoolSize,
    Duration? keepAliveTime,
    Queue<ITask>? taskQueue,
    RejectedExecutionHandler? handler,
    Map<Object, Object?>? isolateValues,
    bool launchCoreImmediately = false,
    int immediatelyStartedCore = 0,
    FutureOr<void> Function(Map<Object, Object?> isolateValues)?
        onIsolateCreated,
    int onIsolateCreateTimeoutTimesDoNotCreateNew = 0,
    @Deprecated('Use customizeTaskInvoker, deprecated after v2.1.0 ')
    Future<dynamic> Function(
            int taskId, FutureOr Function(dynamic) function, dynamic message)?
        customTaskInvoker,
    TaskInvoker? customizeTaskInvoker,
    String? debugLabel,
  }) {
    assert(maximumPoolSize >= corePoolSize);
    return _IsolatePoolExecutorCore(
      corePoolSize: corePoolSize,
      maximumPoolSize: maximumPoolSize,
      keepAliveTime: const Duration(seconds: 30),
      taskQueue: taskQueue ?? Queue(),
      handler: handler ?? RejectedExecutionHandler.abortPolicy,
      isolateValues: isolateValues,
      launchCoreImmediately: launchCoreImmediately,
      immediatelyStartedCore: immediatelyStartedCore,
      onIsolateCreated: onIsolateCreated,
      onIsolateCreateTimeoutTimesDoNotCreateNew:
          onIsolateCreateTimeoutTimesDoNotCreateNew,
      customizeTaskInvoker:
          customizeTaskInvoker ?? _warpTaskInvoker(customTaskInvoker),
      debugLabel: debugLabel,
    );
  }

  /// [launchCoreImmediately] 是否立即启动所有的核心isolate
  /// 如果值为false时 同时判断[immediatelyStartedCore] 自定义的启动数量，不超过[nIsolates]
  factory IsolatePoolExecutor.newFixedIsolatePool(
    int nIsolates, {
    Queue<ITask>? taskQueue,
    RejectedExecutionHandler? handler,
    Map<Object, Object?>? isolateValues,
    bool launchCoreImmediately = false,
    int immediatelyStartedCore = 0,
    FutureOr<void> Function(Map<Object, Object?> isolateValues)?
        onIsolateCreated,
    int onIsolateCreateTimeoutTimesDoNotCreateNew = 0,
    @Deprecated('Use taskInvoker, deprecated after v2.1.0 ')
    Future<dynamic> Function(
            int taskId, FutureOr Function(dynamic) function, dynamic message)?
        customTaskInvoker,
    TaskInvoker? customizeTaskInvoker,
    String? debugLabel,
  }) =>
      _IsolatePoolExecutorCore(
        corePoolSize: nIsolates,
        maximumPoolSize: nIsolates,
        keepAliveTime: const Duration(seconds: 1),
        taskQueue: taskQueue ?? Queue(),
        handler: handler ?? RejectedExecutionHandler.abortPolicy,
        isolateValues: isolateValues,
        launchCoreImmediately: launchCoreImmediately,
        immediatelyStartedCore: immediatelyStartedCore,
        onIsolateCreated: onIsolateCreated,
        onIsolateCreateTimeoutTimesDoNotCreateNew:
            onIsolateCreateTimeoutTimesDoNotCreateNew,
        customizeTaskInvoker:
            customizeTaskInvoker ?? _warpTaskInvoker(customTaskInvoker),
        debugLabel: debugLabel,
      );

  ///
  /// taskQueueInIsolate 为true时 taskQueueFactory 会跨isolate访问无法使用当前isolate中的数据
  factory IsolatePoolExecutor.newSingleIsolateExecutor({
    bool taskQueueInIsolate = false,
    Queue<ITask> Function()? taskQueueFactory,
    RejectedExecutionHandler? handler,
    Map<Object, Object?>? isolateValues,
    bool launchCoreImmediately = false,
    FutureOr<void> Function(Map<Object, Object?> isolateValues)?
        onIsolateCreated,
    @Deprecated('Use customizeTaskInvoker, deprecated after v2.1.0 ')
    Future<dynamic> Function(
            int taskId, FutureOr Function(dynamic) function, dynamic message)?
        customTaskInvoker,
    TaskInvoker? customizeTaskInvoker,
    String? debugLabel,
  }) =>
      taskQueueInIsolate
          ? _IsolatePoolSingleExecutor(
              taskQueueFactory: taskQueueFactory,
              handler: handler ?? RejectedExecutionHandler.abortPolicy,
              isolateValues: isolateValues,
              launchCoreImmediately: launchCoreImmediately,
              onIsolateCreated: onIsolateCreated,
              customizeTaskInvoker:
                  customizeTaskInvoker ?? _warpTaskInvoker(customTaskInvoker),
              debugLabel: debugLabel,
            )
          : IsolatePoolExecutor.newFixedIsolatePool(
              1,
              taskQueue: taskQueueFactory?.call(),
              handler: handler,
              isolateValues: isolateValues,
              launchCoreImmediately: launchCoreImmediately,
              onIsolateCreated: onIsolateCreated,
              customizeTaskInvoker:
                  customizeTaskInvoker ?? _warpTaskInvoker(customTaskInvoker),
              debugLabel: debugLabel,
            );

  /// 创建一个无上限数量的缓存可用pool
  factory IsolatePoolExecutor.newCachedIsolatePool({
    Duration keepAliveTime = const Duration(seconds: 10),
    Map<Object, Object?>? isolateValues,
    FutureOr<void> Function(Map<Object, Object?> isolateValues)?
        onIsolateCreated,
    @Deprecated('Use taskInvoker, deprecated after v2.1.0 ')
    Future<dynamic> Function(
            int taskId, FutureOr Function(dynamic) function, dynamic message)?
        customTaskInvoker,
    TaskInvoker? customizeTaskInvoker,
    String? debugLabel,
  }) =>
      _IsolatePoolExecutorCore(
        corePoolSize: 0,
        // java中int最大值 魔法数
        maximumPoolSize: 2147483647,
        keepAliveTime: keepAliveTime,
        taskQueue: QueueEmpty(),
        handler: RejectedExecutionHandler.abortPolicy,
        isolateValues: isolateValues,
        onIsolateCreated: onIsolateCreated,
        customizeTaskInvoker:
            customizeTaskInvoker ?? _warpTaskInvoker(customTaskInvoker),
        debugLabel: debugLabel,
      );

  /// 提交一个任务
  /// [message] 和 [tag] 将会被发送到isolate中 注意是否可以发送
  /// https://api.dart.dev/dart-isolate/SendPort/send.html
  TaskFuture<R> compute<Q, R>(
      FutureOr<R> Function(Q message) callback, Q message,
      {String? debugLabel, int what = 0, dynamic tag, String? taskLabel});

  /// 关闭当前的pool
  void shutdown({bool force = false});

  /// 是否正在处于关闭中或这正在关闭
  bool get isShutdown;
}

final Map<Object, Object?> _isolateValues = {};

/// 用以存放到isolate中数据
extension IsolateDataExt on Isolate {
  /// 获取存放在isolate中的数据
  dynamic operator [](Object? key) => _isolateValues[key];
}

/// 自定义对于task的执行器
typedef TaskInvoker = Future<dynamic> Function(
    int taskId,
    FutureOr Function(dynamic) function,
    dynamic message,
    String taskLabel,
    int what,
    dynamic tag);

/// 当策略为RejectedExecutionHandler.abortPolicy 且无法添加到Queue时 的异常
class RejectedExecutionException implements Exception {
  final dynamic error;

  RejectedExecutionException(this.error);

  @override
  String toString() {
    return 'RejectedExecutionException $error';
  }
}
