part of 'isolate_pool_executor.dart';

extension _IsolatePoolExecutorCoreNoCache on _IsolatePoolExecutorCore {
  _IsolateExecutor _makeNoCacheExecutor() {
    // final completer = Completer<SendPort>();
    final receivePort = ReceivePort();

    _IsolateExecutor executor =
        _IsolateExecutor(Future.value(receivePort.sendPort), receivePort);

    void runIsolate(_Task task) {
      final args = List<dynamic>.filled(3, null);
      args[0] = receivePort.sendPort;
      args[1] = task;
      args[2] = isolateValues;

      Isolate.spawn(_workerNoCache, args,
              onError: receivePort.sendPort,
              onExit: receivePort.sendPort,
              debugName:
                  'IsolatePoolExecutor-NoCache-${_isolateIndex++}-worker')
          .then((value) => executor.isolate = value)
          .catchError(
        (err, st) {
          final task = executor.close();
          if (task != null) {
            task._submitError(err, st);
          }
        },
      );
    }

    receivePort.listen((message) {
      if (message == null) {
        // onExit handler message, isolate terminated without sending result.
        executor.task?._submitError(
            RemoteError("Computation ended without result", ""),
            StackTrace.empty);
      } else if (message is _Task) {
        runIsolate(message);
        return;
      } else if (message is _TaskResult) {
        executor.task?._submit(message);
      }
      executor.close();
      _poolTask();
    });

    return executor;
  }
}

void _workerNoCache(List args) {
  SendPort sendPort = args[0];
  _Task task = args[1];
  final isolateValues = args[2];
  if (isolateValues != null) {
    _isolateValues.addAll(isolateValues as Map<Object, Object?>);
  }
  _invokeTask(task).then((result) => Isolate.exit(sendPort, result));
}
