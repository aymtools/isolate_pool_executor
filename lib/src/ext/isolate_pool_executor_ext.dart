import 'dart:async';
import 'dart:isolate';

import '../isolate_pool_executor.dart';

extension IsolatePoolExecutorExt on IsolatePoolExecutor {
  /// 别名
  TaskFuture<R> execute<Q, R>(
          FutureOr<R> Function(Q message) callback, Q message,
          {String? debugLabel, int what = 0, dynamic tag, String? taskLabel}) =>
      compute(callback, message,
          debugLabel: debugLabel, what: what, tag: tag, taskLabel: taskLabel);
}

Isolate get currentIsolate => Isolate.current;
