part of 'isolate_pool_executor.dart';

// Queue<ITask> _defaultTaskQueueFactory() => Queue();

class _IsolatePoolSingleExecutor implements IsolatePoolExecutor {
  final Queue<ITask> Function()? taskQueueFactory;

  final Map<Object, Object?>? isolateValues;
  final List<_IsolateExecutor?> _coreExecutor = List.filled(1, null);

  final Map<int, ITask> taskQueue = {};

  bool _shutdown = false;

  late final void Function(
          _IsolateExecutor executor, ITask task, int what, dynamic tag)
      _emitTask = taskQueueFactory == null ? _emitTask2 : _emitTask1;

  _IsolatePoolSingleExecutor(
      {Queue<ITask> Function()? taskQueueFactory, this.isolateValues})
      : taskQueueFactory = taskQueueFactory;

  @override
  Future<R> compute<Q, R>(FutureOr<R> Function(Q message) callback, Q message,
      {String? debugLabel, int what = 0, dynamic tag}) {
    debugLabel ??= callback.toString();

    return _makeTask<R>((d) => callback(d), message, debugLabel, what, tag)
        ._future;
  }

  @override
  void shutdown({bool force = false}) {
    _shutdown = true;
    if (force) {
      try {
        _coreExecutor[0]?.close();
        _coreExecutor[0] = null;
      } catch (ignore) {}
    }
  }

  ITask<R> _makeTask<R>(dynamic Function(dynamic p) run, dynamic p,
      String debugLabel, int what, dynamic tag) {
    if (_shutdown) throw 'SingleIsolatePoolExecutor is shutdown';

    ITask<R> task = ITask<R>._task(run, p, debugLabel, what, tag);
    taskQueue[task.taskId] = task;

    final executor = _findExecutor();
    _emitTask(executor, task, what, tag);
    return task;
  }

  void _emitTask1(
      _IsolateExecutor executor, ITask task, int what, dynamic tag) {
    final t = task._task;
    task._task = null;
    final message = List<dynamic>.filled(3, null);
    message[0] = t;
    message[1] = what;
    message[2] = tag;
    executor.sendPort.then((value) {
      if (!executor.isClosed) {
        value.send(message);
      }
    });
  }

  void _emitTask2(
      _IsolateExecutor executor, ITask task, int what, dynamic tag) {
    final t = task._task;
    task._task = null;
    executor.sendPort.then((value) {
      if (!executor.isClosed) {
        value.send(t);
      }
    });
  }

  _IsolateExecutor _findExecutor() {
    var executor = _coreExecutor[0];
    if (executor == null) {
      executor = _makeExecutor();
      _coreExecutor[0] = executor;
      executor.whenClose = () => _coreExecutor[0] = null;
    }
    return executor;
  }

  _IsolateExecutor _makeExecutor() {
    final completer = Completer<SendPort>();
    final receivePort = ReceivePort();

    _IsolateExecutor executor = _IsolateExecutor(completer.future, receivePort);

    receivePort.listen((message) {
      if (message == null) {
        //执行了Isolate exit
        final task = executor.task;
        if (task != null) {
          task._submitError(RemoteError("Computation ended without result", ""),
              StackTrace.empty);
          taskQueue.remove(task.taskId);
        }
        executor.close();
      } else if (message is SendPort) {
        if (!completer.isCompleted) completer.complete(message);
        return;
      } else if (message is _TaskResult) {
        _TaskResult result = message;
        taskQueue[result.taskId]?._submit(result);
        taskQueue.remove(result.taskId);
        if (_shutdown && taskQueue.isEmpty) {
          executor.close();
        }
      }
    });
    final args = List<dynamic>.filled(3, null);
    args[0] = receivePort.sendPort;
    args[1] = taskQueueFactory;
    args[2] = isolateValues;
    Isolate.spawn(_workerSingle, args,
            onError: receivePort.sendPort,
            onExit: receivePort.sendPort,
            debugName: 'SingleIsolatePoolExecutor-worker')
        .then((value) => executor.isolate = value);

    return executor;
  }
}

void _workerSingle(List args) {
  SendPort sendPort = args[0];
  Queue<ITask> Function()? taskQueueFactory = args[1];

  final isolateValues = args[2];
  if (isolateValues != null) {
    _isolateValues.addAll(isolateValues as Map<Object, Object?>);
  }

  ReceivePort receivePort = ReceivePort();
  sendPort.send(receivePort.sendPort);
  if (taskQueueFactory == null) {
    receivePort
        .listen((message) async => sendPort.send(await _invokeTask(message)));
  } else {
    Queue<ITask> taskQueue = taskQueueFactory();
    _Task? doingTask;

    late void Function() _poolTask;

    void invokeTask(_Task task) async {
      final taskResult = await _invokeTask(task);
      sendPort.send(taskResult);
      doingTask = null;
      _poolTask();
    }

    _poolTask = () {
      scheduleMicrotask(() {
        while (doingTask == null && taskQueue.isNotEmpty) {
          final task = taskQueue.removeFirst();
          doingTask = task._task;
        }
        if (doingTask != null) {
          Timer.run(() => invokeTask(doingTask!));
        }
      });
    };

    receivePort.listen((message) {
      List list = message;
      scheduleMicrotask(() {
        taskQueue.add(ITask._taskValue(list[0], list[1], list[2]));
        _poolTask();
      });
    });
  }
}
