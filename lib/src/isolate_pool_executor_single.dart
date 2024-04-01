part of 'isolate_pool_executor.dart';

// Queue<ITask> _defaultTaskQueueFactory() => Queue();

class _IsolatePoolSingleExecutor implements IsolatePoolExecutor {
  final Queue<ITask> Function()? taskQueueFactory;

  final Map<Object, Object?>? isolateValues;
  final List<_IsolateExecutor?> _coreExecutor = List.filled(1, null);

  final Map<int, ITask> taskQueue = {};

  final FutureOr<void> Function(Map<Object, Object?> isolateValues)?
      onIsolateCreated;
  final String? debugLabel;

  bool _shutdown = false;

  List<ITask> creatingCache = [];

  late final void Function(ITask task, int what, dynamic tag) _emitTask =
      taskQueueFactory == null ? _emitTask2 : _emitTask1;

  _IsolatePoolSingleExecutor(
      {Queue<ITask> Function()? taskQueueFactory,
      this.isolateValues,
      bool launchCoreImmediately = false,
      this.onIsolateCreated,
      this.debugLabel})
      : taskQueueFactory = taskQueueFactory {
    if (launchCoreImmediately) {
      final executor = _makeExecutor(null);
      executor.whenClose = () => _coreExecutor[0] = null;
      _coreExecutor[0] = executor;
    }
  }

  @override
  TaskFuture<R> compute<Q, R>(
      FutureOr<R> Function(Q message) callback, Q message,
      {String? debugLabel, int what = 0, dynamic tag}) {
    debugLabel ??= callback.toString();
    final task =
        _makeTask<R>((d) => callback(d), message, debugLabel, what, tag);
    return TaskFuture<R>._(task);
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
    if (_shutdown)
      throw 'SingleIsolatePoolExecutor${this.debugLabel?.isNotEmpty == true ? '-${this.debugLabel}' : ''} is shutdown';

    ITask<R> task = ITask<R>._task(run, p, debugLabel, what, tag);
    taskQueue[task.taskId] = task;

    _emitTask(task, what, tag);
    return task;
  }

  void _emitTask1(ITask task, int what, dynamic tag) {
    final t = task._task;
    final message = List<dynamic>.filled(3, null);
    message[0] = t;
    message[1] = what;
    message[2] = tag;

    var executor = _coreExecutor[0];
    if (executor == null) {
      executor = _makeExecutor(task);
      _coreExecutor[0] = executor;
      executor.whenClose = () => _coreExecutor[0] = null;
      task._task = null;
    } else if (executor.isCreating) {
      creatingCache.add(task);
    } else if (!executor.isClosed) {
      try {
        executor._sendPort!.send(message);
        task._task = null;
      } catch (err, st) {
        task._submitError(err, st);
        executor.close();
      }
    } else {}
  }

  void _emitTask2(ITask task, int what, dynamic tag) {
    final t = task._task;

    var executor = _coreExecutor[0];
    if (executor == null) {
      executor = _makeExecutor(task);
      _coreExecutor[0] = executor;
      executor.whenClose = () => _coreExecutor[0] = null;
      task._task = null;
    } else if (executor.isCreating) {
      creatingCache.add(task);
    } else if (!executor.isClosed) {
      try {
        executor._sendPort!.send(t);
        task._task = null;
      } catch (err, st) {
        task._submitError(err, st);
        executor.close();
      }
    } else {}
  }

  _IsolateExecutor _makeExecutor(ITask? fistTask) {
    final receivePort = RawReceivePort();

    String? debugLabel;

    assert(() {
      debugLabel =
          'SingleIsolatePoolExecutor${this.debugLabel?.isNotEmpty == true ? '-${this.debugLabel}' : ''}-worker';
      return true;
    }());

    _IsolateExecutor executor =
        _IsolateExecutor(receivePort, fistTask, debugLabel);

    //需要特殊处理
    executor.onTimeout = () {
      var error =
          "Create Isolate timeout \n https://github.com/flutter/flutter/issues/132731";
      taskQueue.values.forEach((task) {
        task._submitError(error, StackTrace.empty);
      });
      executor.close();
      taskQueue.clear();
      creatingCache.clear();
    };

    receivePort.handler = ((message) {
      if (message == null) {
        //执行了Isolate exit
        final err = RemoteError("Computation ended without result", "");
        taskQueue.values.forEach((task) {
          task._submitError(err, StackTrace.empty);
        });
        executor.close();
        taskQueue.clear();
        creatingCache.clear();
      } else if (message is SendPort) {
        // if (!completer.isCompleted) completer.complete(message);
        executor.sendPort = message;
        if (taskQueueFactory == null) {
          creatingCache.forEach((task) {
            message.send(task._task!);
            task._task = null;
          });
        } else {
          creatingCache.forEach((task) {
            final t = task._task;
            final msg = List<dynamic>.filled(3, null);
            msg[0] = t;
            msg[1] = task.what;
            msg[2] = task.tag;
            message.send(msg);
            task._task = null;
          });
        }
        creatingCache.clear();
        return;
      } else if (message is _TaskResult) {
        _TaskResult result = message;
        taskQueue[result.taskId]?._submit(result);
        taskQueue.remove(result.taskId);
        if (_shutdown && taskQueue.isEmpty) {
          executor.close();
        }
      } else if (message is List && message.length == 2) {
        //发生了异常退出
        var remoteError = message[0];
        var remoteStack = message[1];
        if (remoteStack! is StackTrace) {
          var error = RemoteError(
              remoteError.toString(), remoteStack?.toString() ?? '');
          remoteError = error;
          remoteStack = error.stackTrace;
        }

        taskQueue.values.forEach((task) {
          task._submitError(remoteError, remoteStack);
        });
        executor.close();
        taskQueue.clear();
        creatingCache.clear();
      }
    });
    final args = List<dynamic>.filled(5, null);
    args[0] = receivePort.sendPort;
    args[1] = taskQueueFactory;
    args[2] = isolateValues;
    args[3] = fistTask?._task;
    args[4] = onIsolateCreated;

    Isolate.spawn(_workerSingle, args,
            onError: receivePort.sendPort,
            onExit: receivePort.sendPort,
            debugName: debugLabel)
        .then((value) {
      executor.isolate = value;
    }).catchError(
      (error, stackTrace) {
        executor.close();
        taskQueue.values.forEach((task) {
          task._submitError(error, stackTrace);
        });
        executor.close();
        taskQueue.clear();
        creatingCache.clear();
      },
    );

    return executor;
  }

  @override
  bool get isShutdown => _shutdown;
}

void _workerSingle(List args) {
  SendPort sendPort = args[0];
  _runIsolateWorkGuarded(sendPort, () async {
    Queue<ITask> Function()? taskQueueFactory = args[1];

    final isolateValues = args[2];
    if (isolateValues != null) {
      _isolateValues.addAll(isolateValues as Map<Object, Object?>);
    }

    ReceivePort receivePort = ReceivePort();
    sendPort.send(receivePort.sendPort);

    try {
      FutureOr<void> Function(Map<Object, Object?>? isolateValues)?
          onIsolateCreated = args[4];
      if (onIsolateCreated != null) {
        final result = onIsolateCreated.call(_isolateValues);
        if (result is Future) {
          await result;
        }
      }
    } catch (ignore) {}

    final _Task? task = args[3];

    void Function() startListen;

    if (taskQueueFactory == null) {
      startListen = () => receivePort
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
      startListen = () => receivePort.listen((message) {
            List list = message;
            scheduleMicrotask(() {
              taskQueue.add(ITask._taskValue(list[0], list[1], list[2]));
              _poolTask();
            });
          });
    }
    if (task != null) {
      _invokeTask(task).then(sendPort.send).then((_) => startListen());
    } else {
      startListen();
    }
  });
}
