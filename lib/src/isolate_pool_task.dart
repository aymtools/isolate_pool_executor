part of 'isolate_pool_executor.dart';

int _currIndex = 0;

const _maxIndex = 0xffffffffffff;

int _nextTaskId() {
  _currIndex = (_currIndex + 1) & _maxIndex;
  return _currIndex;
}

///待执行的任务
class ITask<R> {
  final int taskId;
  _Task? _task;

  final Completer<R> _computer;
  final String taskLabel;
  final dynamic tag;
  final int what;

  /// 只有在任务提交前可以使用 提交后为了优化将会置为null
  dynamic get taskMessage => _task?.message;

  /// 一般用于配合队列 缓存 对task按一定规则计算排序时 计算的结果
  dynamic obj;

  ITask._task(
    FutureOr Function(dynamic q) function,
    dynamic message,
    this.taskLabel,
    this.what,
    this.tag,
  )   : taskId = _nextTaskId(),
        _computer = Completer<R>() {
    _task = _Task(function, message, taskId, taskLabel, what, tag);
  }

  ITask._taskValue(
    _Task this._task,
  )   : taskId = _task.taskId,
        taskLabel = _task.taskLabel,
        what = _task.what,
        tag = _task.tag,
        _computer = Completer<R>();

  Future<R> get _future => _computer.future;

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
  final int taskId;
  final String taskLabel;
  dynamic result;
  dynamic err;
  StackTrace? stackTrace;

  _TaskResult(this.taskLabel, this.taskId);
}

class _Task {
  final int taskId;
  final String taskLabel;
  final dynamic message;
  final FutureOr Function(dynamic q) function;
  final int what;
  final dynamic tag;

  _Task(this.function, this.message, this.taskId, this.taskLabel, this.what,
      this.tag);

  _TaskResult makeResult() => _TaskResult(taskLabel, taskId);
}

enum IsolateExecutorState {
  creating,
  idle,
  running,
  close,
}

int _creating = () {
  int t = 3;
  assert(() {
    t = 6;
    return true;
  }());
  return t;
}();

// Future<Null> get _waitOtherImmediatelyStarted async {
//   if (_creating < 5) {
//     return Future.value();
//   }
//   await Future.delayed(Duration(seconds: 1));
//   return _waitOtherImmediatelyStarted;
// }

class _IsolateExecutor {
  final RawReceivePort _receivePort;
  final String? debugLabel;
  void Function()? whenClose;
  bool _isClosed = false;
  Isolate? _isolate;
  SendPort? _sendPort;

  ITask? _task;

  late Timer timer;
  void Function()? onTimeout;

  _IsolateExecutor(this._receivePort, this._task, this.debugLabel);

  bool get isIdle =>
      _isolate != null && _sendPort != null && !_isClosed && _task == null;

  bool get isClosed => _isClosed;

  bool get isCreating => !isClosed && _sendPort == null;

  set sendPort(SendPort port) {
    if (_creating > 3) _creating--;
    timer.cancel();
    assert(!isClosed);
    _sendPort = port;
  }

  set isolate(Isolate isolate) {
    assert(!isClosed);
    _isolate = isolate;
    _creating++;
    final time = _creating;
    //用以监听此bug https://github.com/flutter/flutter/issues/132731
    timer = Timer(Duration(seconds: _creating), () {
      if (_creating > 3) _creating--;
      if (!isClosed && _sendPort == null) {
        final errStr = CreateIsolateTimeoutException(
            debugLabel: debugLabel, waitTime: time);

        close()?._submitError(errStr, StackTrace.empty);
        print(errStr);
        onTimeout?.call();
      }
    });
  }

  void emit(ITask task) {
    if (_task == task) return;
    _task = task;
    assert(!isIdle, 'IsolateExecutor is busy');
    try {
      _sendPort!.send(task._task);
      task._task = null;
    } catch (err, st) {
      task._submitError(err, st);
      close();
    }
  }

  void submit(_TaskResult result) {
    if (result.taskId == _task?.taskId) {
      _task?._submit(result);
    }
    _task = null;
  }

  ITask? close() {
    _isClosed = true;
    _sendPort = null;
    final t = _task;
    whenClose?.call();
    _task = null;
    _receivePort.close();
    _isolate?.kill();
    whenClose = null;
    return t?._task == null ? null : t;
  }
}

TaskInvoker _taskInvoker = (taskId, function, message, _, __, ___) async {
  dynamic result = function(message);
  if (result is Future) {
    result = await result;
  }
  return result;
};

Future<_TaskResult> _invokeTask(_Task task) async {
  final taskResult = task.makeResult();
  Completer<_TaskResult> computer = Completer();
  runZonedGuarded(() async {
    dynamic r = _taskInvoker(task.taskId, task.function, task.message,
        task.taskLabel, task.what, task.tag);
    if (r is Future) {
      r = await r;
    }
    taskResult.result = r;
    if (!computer.isCompleted) computer.complete(taskResult);
  }, (error, stack) {
    taskResult.err = error;
    taskResult.stackTrace = stack;
    if (!computer.isCompleted) computer.complete(taskResult);
  });
  return computer.future;
}

void _runIsolateWorkGuarded(SendPort sendPort, void Function() block) {
  runZonedGuarded(block, (error, stack) {
    final errs = List<Object?>.filled(2, null);
    errs[0] = error;
    errs[1] = stack;
    Isolate.exit(sendPort, errs);
  });
}

extension _ListFirstWhereOrNullExt<E> on List<E> {
  E? firstWhereOrNull(bool Function(E element) test) {
    for (E element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}

class CreateIsolateTimeoutException implements Exception {
  final String? debugLabel;

  final int waitTime;

  CreateIsolateTimeoutException(
      {required this.debugLabel, required this.waitTime});

  @override
  String toString() {
    return "Create Isolate(${debugLabel ?? ''}) timeout (wait $waitTime seconds)\n "
        "Known cause:\n1.Open too many isolates at the same time \n2.https://github.com/flutter/flutter/issues/132731";
  }
}
