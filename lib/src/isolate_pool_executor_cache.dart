part of 'isolate_pool_executor.dart';

extension _IsolatePoolExecutorCoreNoCache on _IsolatePoolExecutorCore {
  _IsolateExecutor _makeNoCacheExecutor() {
    final completer = Completer<SendPort>();
    final receivePort = ReceivePort();

    final watchDogPort = ReceivePort();
    _IsolateExecutor executor =
        _IsolateExecutor(completer.future, watchDogPort, receivePort);

    watchDogPort.listen((message) {
      final task = executor.task;
      if (message == null) {
        // onExit handler message, isolate terminated without sending result.
        task?._submitError(RemoteError("Computation ended without result", ""),
            StackTrace.empty);
      } else if (message is _TaskResult) {
        task?._submit(message);
      }
      executor.close();
    });

    receivePort.listen((message) {
      if (message is SendPort) {
        if (!completer.isCompleted) completer.complete(message);
        return;
      }
      final task = executor.task;
      if (message == null) {
        // onExit handler message, isolate terminated without sending result.
        task?._submitError(RemoteError("Computation ended without result", ""),
            StackTrace.empty);
      } else if (message is _TaskResult) {
        task?._submit(message);
      }
      executor.close();
    });

    final args = List<dynamic>.filled(3, null);
    args[0] = receivePort.sendPort;
    args[2] = isolateValues;

    Isolate.spawn(_workerNoCache, args,
            onError: receivePort.sendPort,
            onExit: receivePort.sendPort,
            debugName: 'IsolatePoolExecutor-${_isolateIndex++}-worker')
        .then((value) => executor.isolate = value)
        .catchError(
      (_) {
        final task = executor.close();
        if (task != null) {
          _addTask(task, header: true);
        }
      },
    );

    return executor;
  }
}

void _workerNoCache(List args) {
  SendPort sendPort = args[0];
  final isolateValues = args[2];
  if (isolateValues != null) {
    _isolateValues.addAll(isolateValues as Map<Object, Object?>);
  }
  ReceivePort receivePort = ReceivePort();
  sendPort.send(receivePort.sendPort);

  Future<_TaskResult> invokeTask(_Task task) async {
    final taskResult = task.makeResult();
    try {
      final function = task.function;
      dynamic result = function(task.message);
      if (result is Future) {
        result = await result;
      }
      taskResult.result = result;
    } catch (err, stackTrace) {
      taskResult.err = err;
      taskResult.stackTrace = stackTrace;
    } finally {
      return taskResult;
    }
  }

  receivePort.listen((message) async {
    receivePort.close();
    final result = await invokeTask(message);
    Isolate.exit(sendPort, result);
  });
}
