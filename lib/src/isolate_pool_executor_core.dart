part of 'isolate_pool_executor.dart';

class _IsolatePoolExecutorCore implements IsolatePoolExecutor {
  ///池中的核心线程数，当提交一个任务时，创建一个新的Isolate执行任务，直到当前Isolate数等于corePoolSize, 即使有其他空闲Isolate能够执行新来的任务, 也会继续创建Isolate；如果当前Isolate数为corePoolSize，继续提交的任务被保存到阻塞队列中，等待被执行
  final int corePoolSize;

  ///Isolate池中允许的最大Isolate数。如果当前阻塞队列满了，且继续提交任务，则创建新的Isolate执行任务，前提是当前Isolate数小于maximumPoolSize；当阻塞队列是无界队列, 则maximumPoolSize则不起作用, 因为无法提交至核心Isolate池的线程会一直持续地放入taskQueue.
  final int maximumPoolSize;
  final int cachePoolSize;

  ///Isolate空闲时的存活时间，即当Isolate没有任务执行时，该Isolate继续存活的时间；该参数只在Isolate数大于corePoolSize时才有用, 超过这个时间的空闲线程将被终止；
  final Duration keepAliveTime;

  ///用来保存等待被执行的任务的阻塞队列
  final Queue<ITask> taskQueue;

  ///Isolate池的饱和策略，当阻塞队列满了，且没有空闲的工作Isolate，如果继续提交任务，必须采取一种策略处理该任务
  final RejectedExecutionHandler handler;
  final Map<Object, Object?>? isolateValues;

  final List<_IsolateExecutor?> _coreExecutor;
  final List<_IsolateExecutor> _cacheExecutor;
  final FutureOr<void> Function(Map<Object, Object?> isolateValues)?
      onIsolateCreated;

  final String? debugLabel;

  final int onIsolateCreateTimeoutTimesDoNotCreateNew;

  bool _shutdown = false;
  bool _canCreateNewIsolate = true;

  int _isolateCreateTimeoutCounter = 0;
  int _isolateIndex = 0;

  final TaskInvoker? customizeTaskInvoker;

  _IsolatePoolExecutorCore(
      {required this.corePoolSize,
      required this.maximumPoolSize,
      required this.keepAliveTime,
      required this.taskQueue,
      required this.handler,
      this.isolateValues,
      bool launchCoreImmediately = false,
      this.onIsolateCreated,
      int immediatelyStartedCore = 0,
      int onIsolateCreateTimeoutTimesDoNotCreateNew = -1,
      this.customizeTaskInvoker,
      this.debugLabel})
      : _coreExecutor = List.filled(corePoolSize, null),
        cachePoolSize = maximumPoolSize - corePoolSize,
        _cacheExecutor = [],
        onIsolateCreateTimeoutTimesDoNotCreateNew =
            onIsolateCreateTimeoutTimesDoNotCreateNew > 0
                ? onIsolateCreateTimeoutTimesDoNotCreateNew
                : -1,
        assert(maximumPoolSize >= corePoolSize,
            'must maximumPoolSize >= corePoolSize') {
    final immediatelyStarted = launchCoreImmediately
        ? corePoolSize
        : min(immediatelyStartedCore, corePoolSize);

    if (immediatelyStarted > 0) {
      for (int i = 0; i < immediatelyStarted; i++) {
        final executor = _makeExecutor(true, null);
        executor.whenClose = () => _coreExecutor[i] = null;
        _coreExecutor[i] = executor;
      }
    }
  }

  @override
  TaskFuture<R> compute<Q, R>(
      FutureOr<R> Function(Q message) callback, Q message,
      {String? debugLabel, int what = 0, dynamic tag, String? taskLabel}) {
    debugLabel ??= callback.toString();
    final task = _makeTask<R>(
        (d) => callback(d), message, taskLabel ?? debugLabel, what, tag);
    return TaskFuture<R>._(task);
  }

  void shutdown({bool force = false}) {
    _shutdown = true;
    if (force) {
      try {
        taskQueue.clear();
        for (var e in _coreExecutor) {
          e?.close();
        }
      } catch (_) {}
    } else if (taskQueue.isEmpty) {
      try {
        for (var e in _coreExecutor) {
          e?.close();
        }
      } catch (_) {}
    }
  }

  ITask<R> _makeTask<R>(dynamic Function(dynamic p) run, dynamic p,
      String taskLabel, int what, dynamic tag) {
    if (_shutdown) {
      throw 'IsolatePoolExecutor${this.debugLabel?.isNotEmpty == true ? '-${this.debugLabel}' : ''} is shutdown';
    }

    ITask<R> task = ITask<R>._task(run, p, taskLabel, what, tag);

    _addTask(task);

    return task;
  }

  void _addTask(ITask task, {bool header = false}) {
    final executor = _emitTask(task);
    if (executor != null) {
      // executor.emit(task);
      return;
    }
    try {
      if (header) {
        taskQueue.addFirst(task);
      } else {
        taskQueue.add(task);
      }
      _poolTask();
    } catch (error) {
      switch (handler) {
        case RejectedExecutionHandler.abortPolicy:
          // 直接通知 task执行异常
          task._computer.completeError(
              RejectedExecutionException(error), StackTrace.current);
          break;
        case RejectedExecutionHandler.callerRunsPolicy:
          _runTask(task);
          break;
        case RejectedExecutionHandler.discardOldestPolicy:
          if (taskQueue.isNotEmpty) {
            taskQueue.removeFirst();
            _addTask(task, header: header);
          }
          // 如果已经是空的还添加不进去意味着将自己也扔掉
          break;
        case RejectedExecutionHandler.discardPolicy:
          break;
      }
    }
  }

  _runTask(ITask taskX) async {
    final task = taskX._task;
    if (task == null) return;
    final taskResult = task.makeResult();
    runZonedGuarded(() async {
      final invoker = customizeTaskInvoker ?? _taskInvoker;
      dynamic r = invoker(task.taskId, task.function, task.message,
          task.taskLabel, task.what, task.tag);
      if (r is Future) {
        r = await r;
      }
      taskResult.result = r;
      taskX._submit(taskResult);
    }, (error, stack) {
      taskResult.err = error;
      taskResult.stackTrace = stack;
      taskX._submit(taskResult);
    });
  }

  void _poolTask([_IsolateExecutor? executorIdle]) {
    scheduleMicrotask(() {
      if (executorIdle != null && executorIdle.isIdle && taskQueue.isNotEmpty) {
        final task = taskQueue.removeFirst();
        executorIdle.emit(task);
        return;
      }

      while (taskQueue.isNotEmpty) {
        final task = taskQueue.first;
        final executor = _emitTask(task);
        if (executor == null) {
          break;
        }
        final taskF = taskQueue.removeFirst();
        assert(task == taskF, '??????');
      }
    });
  }

  _isolateCreateSupervisor(_IsolateExecutor executor) {
    if (onIsolateCreateTimeoutTimesDoNotCreateNew > 0) {
      executor.onTimeout = () {
        _isolateCreateTimeoutCounter++;
        if (_isolateCreateTimeoutCounter >=
            onIsolateCreateTimeoutTimesDoNotCreateNew) {
          _canCreateNewIsolate = false;
        }
      };
    }
  }

  _IsolateExecutor? _emitTask(ITask task,
      {bool jumpCheckCanCreateNewIsolate = false}) {
    int i = 0, j = corePoolSize;
    for (; i < j; i++) {
      final e = _coreExecutor[i];
      if (e == null) {
        if (_canCreateNewIsolate || jumpCheckCanCreateNewIsolate) {
          _IsolateExecutor executor = _makeExecutor(true, task);
          _coreExecutor[i] = executor;
          executor.whenClose = () => _coreExecutor[i] = null;
          return executor;
        }
      } else if (e.isIdle) {
        e.emit(task);
        return e;
      }
    }
    if (cachePoolSize == 0) return null;
    final idleExecutor = _cacheExecutor.firstWhereOrNull((e) => e.isIdle);
    if (idleExecutor != null) {
      idleExecutor.emit(task);
      return idleExecutor;
    }
    if (_cacheExecutor.length == cachePoolSize) {
      return null;
    }
    if (keepAliveTime == Duration.zero) {
      return _makeNoCacheExecutor(task);
    } else if (_canCreateNewIsolate || jumpCheckCanCreateNewIsolate) {
      _IsolateExecutor executor = _makeExecutor(false, task);
      executor.whenClose = () => _cacheExecutor.remove(executor);
      _cacheExecutor.add(executor);
      return executor;
    }
    if (!jumpCheckCanCreateNewIsolate) {
      if (!_canCreateNewIsolate &&
          (_coreExecutor.isEmpty && _cacheExecutor.isEmpty)) {
        //当前无法创建新isolate，并且也没有可用的isolate时  那就继续尝试创建
        return _emitTask(task, jumpCheckCanCreateNewIsolate: true);
      }
    }

    return null;
    // _IsolateExecutor executor = keepAliveTime == Duration.zero
    //     ? _makeNoCacheExecutor(task)
    //     : _makeExecutor(false, task);
    // executor.whenClose = () => _cacheExecutor.remove(executor);
    // _cacheExecutor.add(executor);
    // return executor;
  }

  _IsolateExecutor _makeExecutor(bool isCore, ITask? task) {
    // final completer = Completer<SendPort>();
    final receivePort = RawReceivePort();
    String? debugLabel;
    assert(() {
      debugLabel = 'IsolatePoolExecutor-${isCore ? 'Core' : 'NotCore'}'
          '${this.debugLabel?.isNotEmpty == true ? '-${this.debugLabel}' : ''}'
          '-${_isolateIndex++}';
      return true;
    }());

    _IsolateExecutor executor = _IsolateExecutor(receivePort, task, debugLabel);

    _isolateCreateSupervisor(executor);

    receivePort.handler = ((message) {
      if (message == null) {
        //执行了Isolate exit
        final task = executor.close();

        if (task != null) {
          //执行推出时存在待执行的task时重新发回头部执行
          _addTask(task, header: true);
        }
        return;
      } else if (message is SendPort) {
        executor.sendPort = message;

        _canCreateNewIsolate = true;
        _isolateCreateTimeoutCounter = 0;

        if (isCore && executor.isIdle) {
          _poolTask(executor);
        }
        return;
      } else if (message is _TaskResult) {
        executor.submit(message);

        if (_shutdown && isCore && taskQueue.isEmpty) {
          executor.close();
          return;
        }
        _poolTask(executor);
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
        _poolTask();
      }
    });

    final args = List<dynamic>.filled(6, null);
    args[0] = receivePort.sendPort;
    if (!isCore) args[1] = keepAliveTime;
    args[2] = isolateValues;
    args[3] = task?._task;
    args[4] = onIsolateCreated;
    args[5] = customizeTaskInvoker;

    Isolate.spawn(_worker, args,
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

    return executor;
  }

  @override
  bool get isShutdown => _shutdown;
}

void _worker(List args) {
  SendPort sendPort = args[0];
  _runIsolateWorkGuarded(sendPort, () async {
    Duration? duration = args[1];
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

    final TaskInvoker? customInvoker = args[5];
    if (customInvoker != null) {
      _taskInvoker = customInvoker;
    }

    void Function() startListen;
    if (duration == null) {
      startListen = () => receivePort
          .listen((message) async => sendPort.send(await _invokeTask(message)));
    } else {
      startListen = () {
        final exitDuration = duration;
        Timer exitTimer = Timer(exitDuration, () => Isolate.exit());
        receivePort.listen((message) async {
          exitTimer.cancel();
          try {
            final result = await _invokeTask(message);
            sendPort.send(result);
          } finally {
            exitTimer.cancel();
            exitTimer = Timer(exitDuration, () => Isolate.exit());
          }
        });
      };
    }

    if (task != null) {
      _invokeTask(task).then(sendPort.send).then((_) => startListen());
    } else {
      startListen();
    }
  });
}
