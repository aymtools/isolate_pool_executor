import 'dart:async';
import 'dart:collection';
import 'dart:isolate';

int _currIndex = 0;

const _maxIndex = 0xffffffffffff;

int _nextTaskId() {
  _currIndex = (_currIndex + 1) & _maxIndex;
  return _currIndex;
}

///待执行的任务
class ITask<R> {
  final _Task _task;

  final Completer<R> _computer;

  ITask._task(int taskId, String taskLabel,
      FutureOr Function(dynamic q) function, dynamic message)
      : _task = _Task(function, message, taskId, taskLabel),
        _computer = Completer<R>();

  Future<R> get future => _computer.future;

  int get taskId => _task.taskId;

  void _submit(_TaskResult result) {
    if (_computer.isCompleted) return;
    if (result.err == null) {
      _computer.complete(result.result);
    } else {
      _computer.completeError(result.err, result.stackTrace);
    }
  }

  void _submitError(Object error, [StackTrace? stackTrace]) {
    if (_computer.isCompleted) return;
    _computer.completeError(error, stackTrace);
  }
}

class _TaskResult {
  final String taskLabel;
  final int taskId;
  dynamic result;
  dynamic err;
  StackTrace? stackTrace;

  _TaskResult(this.taskLabel, this.taskId);
}

class _Task {
  final String taskLabel;
  final int taskId;
  final dynamic message;
  final FutureOr Function(dynamic q) function;

  _Task(this.function, this.message, this.taskId, this.taskLabel);

  _TaskResult makeResult() => _TaskResult(taskLabel, taskId);
}

class _IsolateExecutor {
  final Future<SendPort> sendPort;
  final ReceivePort watchDog;
  final ReceivePort receivePort;
  void Function()? whenClose;
  bool isClosed = false;
  Isolate? isolate;

  ITask? task;

  _IsolateExecutor(this.sendPort, this.watchDog, this.receivePort);

  bool get isIdle => task == null;

  void emit(ITask task) {
    this.task = task;
    sendPort.then((value) {
      if (!isClosed) value.send(task._task);
    });
  }

  void submit(_TaskResult result) {
    if (result.taskId == task?.taskId) {
      task?._submit(result);
    }
    task = null;
  }

  ITask? close() {
    isClosed = true;
    final t = task;
    whenClose?.call();
    task = null;
    receivePort.close();
    watchDog.close();
    isolate?.kill();
    whenClose = null;
    return t;
  }
}

///饱和策略，当阻塞队列满了，且没有空闲的工作线程，如果继续提交任务，必须采取一种策略处理该任务，提供4种策略:
enum RejectedExecutionHandler {
  ///直接抛出异常，默认策略；
  abortPolicy,

  ///用调用者所在的Isolate来执行任务；
  callerRunsPolicy,

  ///丢弃阻塞队列中靠最前的任务，并执行当前任务；
  discardOldestPolicy,

  ///直接丢弃任务；
  discardPolicy,
}

class IsolatePoolExecutor {
  ///池中的核心线程数，当提交一个任务时，创建一个新的Isolate执行任务，直到当前Isolate数等于corePoolSize, 即使有其他空闲Isolate能够执行新来的任务, 也会继续创建Isolate；如果当前Isolate数为corePoolSize，继续提交的任务被保存到阻塞队列中，等待被执行
  final int corePoolSize;

  ///Isolate池中允许的最大Isolate数。如果当前阻塞队列满了，且继续提交任务，则创建新的Isolate执行任务，前提是当前Isolate数小于maximumPoolSize；当阻塞队列是无界队列, 则maximumPoolSize则不起作用, 因为无法提交至核心Isolate池的线程会一直持续地放入taskQueue.
  final int maximumPoolSize;

  ///Isolate空闲时的存活时间，即当Isolate没有任务执行时，该Isolate继续存活的时间；该参数只在Isolate数大于corePoolSize时才有用, 超过这个时间的空闲线程将被终止；
  final Duration keepAliveTime;

  ///用来保存等待被执行的任务的阻塞队列
  final Queue<ITask> taskQueue;

  ///Isolate池的饱和策略，当阻塞队列满了，且没有空闲的工作Isolate，如果继续提交任务，必须采取一种策略处理该任务
  final RejectedExecutionHandler handler;

  final List<_IsolateExecutor?> _coreExecutor;
  final List<_IsolateExecutor> _cacheExecutor;

  bool _shutdown = false;

  int _isolateIndex = 0;

  IsolatePoolExecutor(
      {required this.corePoolSize,
      required this.maximumPoolSize,
      required this.keepAliveTime,
      required this.taskQueue,
      required this.handler})
      : _coreExecutor = List.filled(corePoolSize, null),
        _cacheExecutor = [],
        assert(maximumPoolSize >= corePoolSize,
            'must maximumPoolSize >= corePoolSize');

  factory IsolatePoolExecutor.newFixedIsolatePool(int nIsolates) =>
      IsolatePoolExecutor(
          corePoolSize: nIsolates,
          maximumPoolSize: nIsolates,
          keepAliveTime: const Duration(seconds: 1),
          taskQueue: Queue(),
          handler: RejectedExecutionHandler.abortPolicy);

  factory IsolatePoolExecutor.newSingleIsolateExecutor() =>
      IsolatePoolExecutor.newFixedIsolatePool(1);

  factory IsolatePoolExecutor.newCachedIsolatePool() => IsolatePoolExecutor(
      corePoolSize: 0,
      // java中int最大值 魔法数
      maximumPoolSize: 2147483647,
      keepAliveTime: const Duration(),
      taskQueue: Queue(),
      handler: RejectedExecutionHandler.abortPolicy);

  Future<R> compute<Q, R>(FutureOr<R> Function(Q message) callback, Q message,
      {String? debugLabel}) async {
    debugLabel ??= callback.toString();
    return _makeTask<R>((d) => callback(d), message, debugLabel).future;
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

  ITask<R> _makeTask<R>(
      dynamic Function(dynamic p) run, dynamic p, String debugLabel) {
    if (_shutdown) throw 'IsolatePoolExecutor is shutdown';

    ITask<R> task = ITask<R>._task(_nextTaskId(), debugLabel, run, p);

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

  _runTask(ITask task) async {
    final result = task._task.makeResult();
    try {
      dynamic r = task._task.function(task._task.message);
      if (r is Future) {
        r = await r;
      }
      result.result = r;
    } catch (e, st) {
      result.err = e;
      result.stackTrace = st;
    } finally {
      task._submit(result);
    }
  }

  void _poolTask() {
    scheduleMicrotask(() {
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

    i = 0;
    j = maximumPoolSize - corePoolSize;
    if (j == 0) return null;
    int k = _cacheExecutor.length;
    for (; i < k && i < j; i++) {
      final e = _cacheExecutor[i];
      if (e.isIdle) {
        return e;
      }
    }
    if (i == j) {
      return null;
    }
    _IsolateExecutor executor = _makeExecutor(false);
    _cacheExecutor.add(executor);
    executor.whenClose = () => _cacheExecutor.remove(executor);
    return executor;
  }

  _IsolateExecutor _makeExecutor(bool isCore) {
    final completer = Completer<SendPort>();
    final receivePort = ReceivePort();

    final watchDogPort = ReceivePort();
    _IsolateExecutor executor =
        _IsolateExecutor(completer.future, watchDogPort, receivePort);

    watchDogPort.listen((message) {
      if (message == null) {
        //执行了Isolate exit
        final task = executor.close();

        if (task != null) {
          //执行推出时存在待执行的task时重新发回头部执行
          _addTask(task, header: true);
        }
        return;
      } else if (message is _TaskResult) {
        // 正常退出
        executor.submit(message);
        executor.close();
        if (_shutdown && isCore && taskQueue.isEmpty) {
          return;
        }
        _poolTask();
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
            var error =
                RemoteError(remoteError.toString(), remoteStack.toString());
            task._submitError(error, error.stackTrace);
          }
        }
      }
    });

    receivePort.listen((message) {
      if (message is SendPort && !completer.isCompleted) {
        completer.complete(message);
      }
      if (message is! _TaskResult) return;
      _TaskResult result = message;
      executor.submit(result);
      // print(
      //     '_shutdown $_shutdown isCore $isCore taskQueue.isEmpty ${taskQueue.isEmpty}');
      if (_shutdown && isCore && taskQueue.isEmpty) {
        executor.close();
        return;
      }
      _poolTask();
    });

    final args = List<dynamic>.filled(2, null);
    args[0] = receivePort.sendPort;
    if (!isCore) args[1] = keepAliveTime;

    Isolate.spawn(_worker, args,
            onError: watchDogPort.sendPort,
            onExit: watchDogPort.sendPort,
            debugName: 'IsolatePoolExecutor-${_isolateIndex++}-worker')
        .catchError(
      (_) {
        final task = executor.close();
        if (task != null) {
          _addTask(task, header: true);
        }
      },
    ).then((value) => executor.isolate = value);

    return executor;
  }
}

void _worker(List args) {
  SendPort sendPort = args[0];
  Duration? duration = args[1];

  ReceivePort receivePort = ReceivePort();
  sendPort.send(receivePort.sendPort);

  Future<_TaskResult> invokeTask(_Task task) async {
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
      return taskResult;
    }
  }

  if (duration == null) {
    receivePort
        .listen((message) async => sendPort.send(await invokeTask(message)));
    // } else if (duration == const Duration()) {
    //   //立即退出
    //   receivePort.listen((message) async {
    //     final result = await invokeTask(message);
    //     Isolate.exit(sendPort, result);
    //   });
  } else {
    Timer? exitTimer;
    final exitDuration = duration;
    receivePort.listen((message) async {
      exitTimer?.cancel();
      exitTimer = null;
      try {
        final result = await invokeTask(message);
        sendPort.send(result);
      } finally {
        exitTimer = Timer(exitDuration, () => Isolate.exit());
      }
    });
  }
}
