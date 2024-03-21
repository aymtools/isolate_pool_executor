part of '../isolate_pool_executor.dart';

class TaskFuture<T> implements Future<T> {
  final Future<T> source;
  final ITask<T> _task;

  TaskFuture._(this._task) : source = _task._future;

  int get taskId => _task.taskId;

  dynamic get tag => _task.tag;

  int get what => _task.what;

  @override
  Stream<T> asStream() => source.asStream();

  @override
  Future<T> catchError(Function onError, {bool Function(Object error)? test}) =>
      source.catchError(onError, test: test);

  @override
  Future<R> then<R>(FutureOr<R> Function(T value) onValue,
          {Function? onError}) =>
      source.then(onValue, onError: onError);

  @override
  Future<T> timeout(Duration timeLimit, {FutureOr<T> Function()? onTimeout}) =>
      source.timeout(timeLimit, onTimeout: onTimeout);

  @override
  Future<T> whenComplete(FutureOr<void> Function() action) =>
      source.whenComplete(action);
}
