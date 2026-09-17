import 'dart:async';
import 'dart:collection';

import 'package:isolate_pool_executor/isolate_pool_executor.dart';
import 'package:test/test.dart';

int _triple(int x) => x * 3;

Queue<ITask> _createQueue() => ListQueue<ITask>();

Future<dynamic> _topLevelInvoker(
  int taskId,
  FutureOr Function(dynamic) function,
  dynamic message,
  String taskLabel,
  int what,
  dynamic tag,
) async {
  dynamic res = function(message);
  if (res is Future) {
    res = await res;
  }
  if (res is int) {
    return res + what;
  }
  return res;
}

void main() {
  group('SingleIsolate taskQueueInIsolate=true tests', () {
    test('taskQueueInIsolate=true executes tasks in single isolate', () async {
      final pool = IsolatePoolExecutor.newSingleIsolateExecutor(
        taskQueueInIsolate: true,
        launchCoreImmediately: true,
        debugLabel: 'SingleInIsolate',
      );

      final res1 = await pool.compute((_) => 10, null);
      final res2 = await pool.compute((_) => 20, null);

      expect(res1, equals(10));
      expect(res2, equals(20));

      pool.shutdown();
      expect(pool.isShutdown, isTrue);
    });

    test('taskQueueInIsolate=true with isolateValues and customizeTaskInvoker', () async {
      final pool = IsolatePoolExecutor.newSingleIsolateExecutor(
        taskQueueInIsolate: true,
        isolateValues: {'module': 'auth'},
        onIsolateCreated: _setupSingleIsolateValues,
        customizeTaskInvoker: _topLevelInvoker,
      );

      final result = await pool.compute(
        _triple,
        10,
        what: 5,
        taskLabel: 'TripleTask',
      );

      expect(result, equals(35)); // (10 * 3) + 5

      final module = await pool.compute((_) => currentIsolate['module'], null);
      final config = await pool.compute((_) => currentIsolate['config'], null);

      expect(module, equals('auth'));
      expect(config, equals('v1'));

      pool.shutdown();
    });

    test('error propagation in taskQueueInIsolate=true', () async {
      final pool = IsolatePoolExecutor.newSingleIsolateExecutor(
        taskQueueInIsolate: true,
      );

      final future = pool.compute((_) {
        throw StateError('SingleIsolate Error');
      }, null);

      expect(
        future,
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('SingleIsolate Error'),
        )),
      );

      pool.shutdown();
    });

    test('submitting task to shutdown single executor throws Exception', () {
      final pool = IsolatePoolExecutor.newSingleIsolateExecutor(
        taskQueueInIsolate: true,
        debugLabel: 'single_test',
      );

      pool.shutdown();
      expect(pool.isShutdown, isTrue);

      expect(
        () => pool.compute((_) => 1, null),
        throwsA(isA<String>().having(
          (s) => s,
          'message',
          contains('SingleIsolatePoolExecutor-single_test is shutdown'),
        )),
      );
    });

    test('assert throws when taskQueueFactory != null and callerRunsPolicy', () {
      expect(
        () => IsolatePoolExecutor.newSingleIsolateExecutor(
          taskQueueInIsolate: true,
          taskQueueFactory: _createQueue,
          handler: RejectedExecutionHandler.callerRunsPolicy,
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}

void _setupSingleIsolateValues(Map<Object, Object?> values) {
  values['config'] = 'v1';
}
