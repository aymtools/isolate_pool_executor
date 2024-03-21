import 'dart:async';
import 'dart:isolate';

import '../isolate_pool_executor.dart';

extension IsolatePoolExecutorExt on IsolatePoolExecutor {
  TaskFuture<R> execute<Q, R>(
          FutureOr<R> Function(Q message) callback, Q message,
          {String? debugLabel, int what = 0, dynamic tag}) =>
      compute(callback, message, debugLabel: debugLabel, what: what, tag: tag);
}

Isolate get currentIsolate => Isolate.current;
