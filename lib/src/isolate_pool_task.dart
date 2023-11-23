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
      if (!isClosed && task._task != null) {
        final t = task._task;
        value.send(t);
        task._task = null;
      }
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
    return t?._task == null ? null : t;
  }
}
