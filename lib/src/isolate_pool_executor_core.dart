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

  bool _shutdown = false;

  int _isolateIndex = 0;

  _IsolatePoolExecutorCore(
      {required this.corePoolSize,
      required this.maximumPoolSize,
      required this.keepAliveTime,
      required this.taskQueue,
      required this.handler,
      this.isolateValues})
      : _coreExecutor = List.filled(corePoolSize, null),
        cachePoolSize = maximumPoolSize - corePoolSize,
        _cacheExecutor = [],
        assert(maximumPoolSize >= corePoolSize,
            'must maximumPoolSize >= corePoolSize');

  Future<R> compute<Q, R>(FutureOr<R> Function(Q message) callback, Q message,
      {String? debugLabel, int what = 0, dynamic tag}) async {
    debugLabel ??= callback.toString();
    return _makeTask<R>((d) => callback(d), message, debugLabel, what, tag)
        ._future;
  }

  void shutdown({bool force = false}) {
    _shutdown = true;
    if (force) {
      try {
        taskQueue.clear();
        for (var e in _coreExecutor) {
          e?.close();
        }
      } catch (ignore) {}
    } else if (taskQueue.isEmpty) {
      try {
        for (var e in _coreExecutor) {
          e?.close();
        }
      } catch (ignore) {}
    }
  }

  ITask<R> _makeTask<R>(dynamic Function(dynamic p) run, dynamic p,
      String debugLabel, int what, dynamic tag) {
    if (_shutdown) throw 'IsolatePoolExecutor is shutdown';

    ITask<R> task = ITask<R>._task(run, p, debugLabel, what, tag);

    _addTask(task);

    return task;
  }

  void _addTask(ITask task, {bool header = false}) {
    final executor = _findIdleExecutor();
    if (executor != null) {
      executor.emit(task);
      return;
    }
    try {
      if (header) {
        taskQueue.addFirst(task);
      } else {
        taskQueue.add(task);
      }
      _poolTask();
    } catch (ignore) {
      switch (handler) {
        case RejectedExecutionHandler.abortPolicy:
          rethrow;
        case RejectedExecutionHandler.callerRunsPolicy:
          _runTask(task);
          break;
        case RejectedExecutionHandler.discardOldestPolicy:
          taskQueue.removeFirst();
          _addTask(task, header: header);
          break;
        case RejectedExecutionHandler.discardPolicy:
          break;
      }
    }
  }

  _runTask(ITask taskX) async {
    final task = taskX._task;
    if (task == null) return;
    final result = task.makeResult();
    try {
      dynamic r = task.function(task.message);
      if (r is Future) {
        r = await r;
      }
      result.result = r;
    } catch (e, st) {
      result.err = e;
      result.stackTrace = st;
    } finally {
      taskX._submit(result);
    }
  }

  void _poolTask([_IsolateExecutor? executorIdle]) {
    scheduleMicrotask(() {
      if (executorIdle != null && executorIdle.isIdle && taskQueue.isNotEmpty) {
        final task = taskQueue.removeFirst();
        executorIdle.emit(task);
        return;
      }

      while (taskQueue.isNotEmpty) {
        final executor = _findIdleExecutor();
        if (executor == null) {
          break;
        }
        final task = taskQueue.removeFirst();
        executor.emit(task);
      }
    });
  }

  _IsolateExecutor? _findIdleExecutor() {
    int i = 0, j = corePoolSize;
    for (; i < j; i++) {
      final e = _coreExecutor[i];
      if (e == null) {
        _IsolateExecutor executor = _makeExecutor(true);
        _coreExecutor[i] = executor;
        executor.whenClose = () => _coreExecutor[i] = null;
        return executor;
      } else if (e.isIdle) {
        return e;
      }
    }
    if (cachePoolSize == 0) return null;
    final idleExecutor = _cacheExecutor.firstWhereOrNull((e) => e.isIdle);
    if (idleExecutor != null) return idleExecutor;
    if (_cacheExecutor.length == cachePoolSize) {
      return null;
    }
    _IsolateExecutor executor = keepAliveTime == Duration.zero
        ? _makeNoCacheExecutor()
        : _makeExecutor(false);
    executor.whenClose = () => _cacheExecutor.remove(executor);
    _cacheExecutor.add(executor);
    return executor;
  }

  _IsolateExecutor _makeExecutor(bool isCore) {
    final completer = Completer<SendPort>();
    final receivePort = ReceivePort();

    _IsolateExecutor executor = _IsolateExecutor(completer.future, receivePort);

    receivePort.listen((message) {
      if (message == null) {
        //执行了Isolate exit
        final task = executor.close();

        if (task != null) {
          //执行推出时存在待执行的task时重新发回头部执行
          _addTask(task, header: true);
        }
        return;
      } else if (message is SendPort) {
        if (!completer.isCompleted) completer.complete(message);
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

    final args = List<dynamic>.filled(3, null);
    args[0] = receivePort.sendPort;
    if (!isCore) args[1] = keepAliveTime;
    args[2] = isolateValues;

    Isolate.spawn(_worker, args,
            onError: receivePort.sendPort,
            onExit: receivePort.sendPort,
            debugName:
                'IsolatePoolExecutor-${isCore ? 'Core' : 'NoCore'}-${_isolateIndex++}-worker')
        .then(
      (value) => executor.isolate = value,
      onError: (error, stackTrace) {
        final task = executor.close();
        if (task != null) {
          _addTask(task, header: true);
        }
      },
    );

    return executor;
  }
}

void _worker(List args) {
  SendPort sendPort = args[0];
  _runIsolateWorkGuarded(sendPort, () {
    Duration? duration = args[1];
    final isolateValues = args[2];
    if (isolateValues != null) {
      _isolateValues.addAll(isolateValues as Map<Object, Object?>);
    }

    ReceivePort receivePort = ReceivePort();
    sendPort.send(receivePort.sendPort);

    if (duration == null) {
      receivePort
          .listen((message) async => sendPort.send(await _invokeTask(message)));
    } else {
      Timer? exitTimer;
      final exitDuration = duration;
      receivePort.listen((message) async {
        exitTimer?.cancel();
        exitTimer = null;
        try {
          final result = await _invokeTask(message);
          sendPort.send(result);
        } finally {
          exitTimer = Timer(exitDuration, () => Isolate.exit());
        }
      });
    }
  });
}
