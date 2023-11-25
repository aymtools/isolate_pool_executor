import 'dart:async';

import '../isolate_pool_executor.dart';

extension IsolatePoolExecutorExt on IsolatePoolExecutor {
  Future<R> execute<Q, R>(FutureOr<R> Function(Q message) callback, Q message,
          {String? debugLabel, int what = 0, dynamic tag}) =>
      compute(callback, message, debugLabel: debugLabel, what: what, tag: tag);
}
