part of 'isolate_pool_executor.dart';

// Queue<ITask> _defaultTaskQueueFactory() => Queue();

class _IsolatePoolSingleExecutor implements IsolatePoolExecutor {
  final Queue<ITask> Function()? taskQueueFactory;

  final Map<Object, Object?>? isolateValues;
  final List<_IsolateExecutor?> _coreExecutor = List.filled(1, null);

  final Map<int, ITask> taskQueue = {};

  final RejectedExecutionHandler? handler;

  final FutureOr<void> Function(Map<Object, Object?> isolateValues)?
      onIsolateCreated;

  final TaskInvoker? customTaskInvoker;

  final String? debugLabel;

  bool _shutdown = false;

  List<ITask> creatingCache = [];

  late final void Function(ITask task, int what, dynamic tag) _emitTask =
      taskQueueFactory == null ? _emitTask2 : _emitTask1;

  _IsolatePoolSingleExecutor(
      {Queue<ITask> Function()? taskQueueFactory,
      this.handler,
      this.isolateValues,
      bool launchCoreImmediately = false,
      this.onIsolateCreated,
      this.customTaskInvoker,
      this.debugLabel})
      : taskQueueFactory = taskQueueFactory {
    assert(
        taskQueueFactory == null ||
            handler != RejectedExecutionHandler.callerRunsPolicy,
        'When the queue is within an Isolate, it cannot be executed in the calling Isolate.');

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
      } catch (_) {}
    }
  }

  ITask<R> _makeTask<R>(dynamic Function(dynamic p) run, dynamic p,
      String debugLabel, int what, dynamic tag) {
    if (_shutdown) {
      throw 'SingleIsolatePoolExecutor${this.debugLabel?.isNotEmpty == true ? '-${this.debugLabel}' : ''} is shutdown';
    }

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
    final args = List<dynamic>.filled(7, null);
    args[0] = receivePort.sendPort;
    args[1] = taskQueueFactory;
    args[2] = isolateValues;
    args[3] = fistTask?._task;
    args[4] = onIsolateCreated;
    args[5] = handler;
    args[6] = customTaskInvoker;

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

    FutureOr<void> Function(Map<Object, Object?> isolateValues)?
        onIsolateCreated = args[4];
    if (onIsolateCreated != null) {
      final result = onIsolateCreated.call(_isolateValues);
      if (result is Future) {
        await result;
      }
    }

    final _Task? task = args[3];

    final RejectedExecutionHandler handler =
        args[5] ?? RejectedExecutionHandler.abortPolicy;

    final TaskInvoker? customInvoker = args[6];
    if (customInvoker != null) {
      _taskInvoker = customInvoker;
    }

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
          if (doingTask != null) return;
          while (doingTask == null && taskQueue.isNotEmpty) {
            final task = taskQueue.removeFirst();
            doingTask = task._task;
          }
          if (doingTask != null) {
            Timer.run(() => invokeTask(doingTask!));
          }
        });
      };
      void addTask(ITask task) {
        try {
          taskQueue.add(task);
        } catch (error) {
          switch (handler) {
            case RejectedExecutionHandler.abortPolicy:
              // 直接通知 task执行异常
              final errResult = task._task?.makeResult();
              if (errResult != null) {
                errResult.err = RejectedExecutionException(error);
                errResult.stackTrace = StackTrace.current;
                sendPort.send(errResult);
              }
              break;
            case RejectedExecutionHandler.callerRunsPolicy:
              break;
            case RejectedExecutionHandler.discardOldestPolicy:
              if (taskQueue.isNotEmpty) {
                taskQueue.removeFirst();
                addTask(task);
              }
              // 如果已经是空的还添加不进去意味着将自己也扔掉
              break;
            case RejectedExecutionHandler.discardPolicy:
              break;
          }
        }
      }

      startListen = () => receivePort.listen((message) {
            List list = message;
            scheduleMicrotask(() {
              addTask(ITask._taskValue(list[0], list[1], list[2]));
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
