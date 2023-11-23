part of 'isolate_pool_executor.dart';

Queue<ITask> _defaultTaskQueueFactory() => Queue();

class _IsolatePoolSingleExecutor implements IsolatePoolExecutor {
  final Queue<ITask> Function()? taskQueueFactory;
  bool _shutdown = false;

  final List<_IsolateExecutor?> _coreExecutor = List.filled(1, null);
  final Map<int, ITask> taskQueue = {};
  late final void Function(
          _IsolateExecutor executor, ITask task, int what, dynamic tag)
      _emitTask = taskQueueFactory == null ? _emitTask2 : _emitTask1;

  _IsolatePoolSingleExecutor({Queue<ITask> Function()? taskQueueFactory})
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

    final watchDogPort = ReceivePort();
    _IsolateExecutor executor =
        _IsolateExecutor(completer.future, watchDogPort, receivePort);

    watchDogPort.listen((message) {
      if (message == null) {
        //执行了Isolate exit
      } else if (message is _TaskResult) {
        // 正常退出
        _TaskResult result = message;
        taskQueue[result.taskId]?._submit(result);
      }
      executor.close();
    });

    receivePort.listen((message) {
      if (message is SendPort && !completer.isCompleted) {
        completer.complete(message);
      }
      if (message is! _TaskResult) return;
      _TaskResult result = message;
      taskQueue[result.taskId]?._submit(result);
    });
    final args = List<dynamic>.filled(2, null);
    args[0] = receivePort.sendPort;
    args[1] = taskQueueFactory;
    Isolate.spawn(_workerSingle, args,
            onError: watchDogPort.sendPort,
            onExit: watchDogPort.sendPort,
            debugName: 'SingleIsolatePoolExecutor-worker')
        .then((value) => executor.isolate = value);

    return executor;
  }
}

void _workerSingle(List args) {
  SendPort sendPort = args[0];
  Queue<ITask> Function()? taskQueueFactory = args[1];

  ReceivePort receivePort = ReceivePort();
  sendPort.send(receivePort.sendPort);
  if (taskQueueFactory == null) {
    void invokeTask1(_Task task) async {
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
        sendPort.send(taskResult);
      }
      receivePort.listen((message) => invokeTask1(message));
    }
  } else {
    Queue<ITask> taskQueue = taskQueueFactory();
    _Task? doingTask;

    late void Function() _poolTask;

    void invokeTask(_Task task) async {
      // print('$task ${task.message}');
      final taskResult = task.makeResult();
      try {
        final function = task.function;
        dynamic result = function(task.message);
        if (result is Future) {
          result = await result;
        }
        taskResult.result = result;
        // print('in isolate   ${result}');
      } catch (err, stackTrace) {
        taskResult.err = err;
        taskResult.stackTrace = stackTrace;
        // print('in isolate   ${err}');
      } finally {
        sendPort.send(taskResult);
        doingTask = null;
        _poolTask();
      }
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