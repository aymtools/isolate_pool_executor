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

  final dynamic tag;
  final int what;

  ITask._task(
    FutureOr Function(dynamic q) function,
    dynamic message,
    String taskLabel,
    this.what,
    this.tag,
  )   : taskId = _nextTaskId(),
        _computer = Completer<R>() {
    _task = _Task(function, message, taskId, taskLabel);
  }

  ITask._taskValue(
    _Task task,
    this.what,
    this.tag,
  )   : taskId = task.taskId,
        _computer = Completer<R>() {
    _task = task;
  }

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

enum IsolateExecutorState {
  creating,
  idle,
  running,
  close,
}

int _creating = 3;

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
    this._task = task;
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

Future<_TaskResult> _invokeTask(_Task task) async {
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

void _runIsolateWorkGuarded(SendPort sendPort, void Function() block) {
  runZonedGuarded(block, (error, stack) {
    final errs = List<Object?>.filled(2, null);
    errs[0] = error;
    errs[1] = stack;
    Isolate.exit(sendPort, errs);
  });
}

extension _ListFirstWhereOrNullExt<E> on List<E> {
  E? firstWhereOrNull(bool test(E element)) {
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

  String toString() {
    return "Create Isolate(${debugLabel ?? ''}) timeout (wait $waitTime seconds)\n "
        "Known cause:\n1.Open too many isolates at the same time \n2.https://github.com/flutter/flutter/issues/132731";
  }
}
