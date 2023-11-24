part of 'isolate_pool_executor.dart';

extension _IsolatePoolExecutorCoreNoCache on _IsolatePoolExecutorCore {
  _IsolateExecutor _makeNoCacheExecutor() {
    final completer = Completer<SendPort>();
    final receivePort = ReceivePort();

    _IsolateExecutor executor = _IsolateExecutor(completer.future, receivePort);

    receivePort.listen((message) {
      if (message == null) {
        // onExit handler message, isolate terminated without sending result.
        executor.task?._submitError(
            RemoteError("Computation ended without result", ""),
            StackTrace.empty);
      } else if (message is SendPort) {
        if (!completer.isCompleted) completer.complete(message);
        return;
      } else if (message is _TaskResult) {
        executor.task?._submit(message);
      }
      executor.close();
      _poolTask();
    });

    final args = List<dynamic>.filled(3, null);
    args[0] = receivePort.sendPort;
    args[2] = isolateValues;

    Isolate.spawn(_workerNoCache, args,
            onError: receivePort.sendPort,
            onExit: receivePort.sendPort,
            debugName: 'IsolatePoolExecutor-NoCache-${_isolateIndex++}-worker')
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

  receivePort.listen((message) async {
    receivePort.close();
    final result = await _invokeTask(message);
    Isolate.exit(sendPort, result);
  });
}
