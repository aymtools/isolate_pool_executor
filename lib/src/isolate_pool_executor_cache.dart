part of 'isolate_pool_executor.dart';

extension _IsolatePoolExecutorCoreNoCache on _IsolatePoolExecutorCore {
  _IsolateExecutor _makeNoCacheExecutor(ITask task) {
    final receivePort = RawReceivePort();
    String? debugLabel;
    assert(() {
      debugLabel =
          'IsolatePoolExecutor-NotCache${this.debugLabel?.isNotEmpty == true ? '-${this.debugLabel}' : ''}'
          '-${_isolateIndex++}';
      return true;
    }());

    _IsolateExecutor executor = _IsolateExecutor(receivePort, task, debugLabel);

    void runIsolate(_Task task) {
      final args = List<dynamic>.filled(5, null);
      args[0] = receivePort.sendPort;
      args[1] = task;
      args[2] = isolateValues;
      args[3] = onIsolateCreated;
      args[4] = customTaskInvoker;

      Isolate.spawn(_workerNoCache, args,
              onError: receivePort.sendPort,
              onExit: receivePort.sendPort,
              debugName: debugLabel)
          .then(
        (value) => executor.isolate = value,
        onError: (error, stackTrace) {
          final task = executor.close();
          if (task != null) {
            task._submitError(error, stackTrace);
          }
        },
      );
    }

    receivePort.handler = ((message) {
      if (message == null) {
        // onExit handler message, isolate terminated without sending result.
        executor._task?._submitError(
            RemoteError("Computation ended without result", ""),
            StackTrace.empty);
      } else if (message is _Task) {
        runIsolate(message);
        return;
      } else if (message is _TaskResult) {
        executor.submit(message);
      } else if (message is List && message.length == 2) {
        //发生了异常退出
        final task = executor.close();
        if (task != null) {
          var remoteError = message[0];
          var remoteStack = message[1];
          if (remoteStack is StackTrace) {
            // Typed error.
            task._submitError(remoteError!, remoteStack);
          } else {
            // onError handler message, uncaught async error.
            // Both values are strings, so calling `toString` is efficient.
            var error = RemoteError(
                remoteError.toString(), remoteStack?.toString() ?? '');
            task._submitError(error, error.stackTrace);
          }
        }
      } else if (message is SendPort) {
        executor.sendPort = message;
        return;
      }
      executor.close();
      _poolTask();
    });
    runIsolate(task._task!);
    return executor;
  }
}

void _workerNoCache(List args) {
  SendPort sendPort = args[0];
  _runIsolateWorkGuarded(sendPort, () async {
    final isolateValues = args[2];
    if (isolateValues != null) {
      _isolateValues.addAll(isolateValues as Map<Object, Object?>);
    }

    ReceivePort receivePort = ReceivePort();
    sendPort.send(receivePort.sendPort);

    FutureOr<void> Function(Map<Object, Object?> isolateValues)?
        onIsolateCreated = args[3];
    if (onIsolateCreated != null) {
      final result = onIsolateCreated.call(_isolateValues);
      if (result is Future) {
        await result;
      }
    }

    _Task task = args[1];

    final TaskInvoker? customInvoker = args[4];
    if (customInvoker != null) {
      _taskInvoker = customInvoker;
    }

    _invokeTask(task).then((result) => Isolate.exit(sendPort, result));
  });
}
