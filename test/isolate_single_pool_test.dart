import 'dart:async';
import 'dart:isolate';

import 'package:isolate_pool_executor/isolate_pool_executor.dart';
import 'package:test/test.dart';

void main() {
  group('SingleIsolate taskQueueInIsolate=false', () {
    late IsolatePoolExecutor pool;
    setUp(() {
      pool = IsolatePoolExecutor.newSingleIsolateExecutor();
    });

    tearDown(() {
      pool.shutdown();
    });

    test('current Isolate', () async {
      final curIsolateHash = Isolate.current.hashCode;

      final targetIsolateHash =
          await pool.compute((_) => Isolate.current.hashCode, null);

      expect(Isolate.current.hashCode, curIsolateHash);

      expect(curIsolateHash == targetIsolateHash, false);

      final targetIsolateHash2 =
          await pool.compute((_) => Isolate.current.hashCode, null);

      expect(curIsolateHash == targetIsolateHash2, false);
      expect(targetIsolateHash == targetIsolateHash2, true);
    });

    test('sequential execution', () async {
      final results = <int>[];
      final completer1 = Completer<void>();
      final completer2 = Completer<void>();

      pool.compute((_) async {
        // This task simulates some work with a delay
        await Future.delayed(const Duration(milliseconds: 100));
        return 1;
      }, null).then((value) {
        results.add(value);
        completer1.complete();
      });

      // Ensure the first task is likely sent and queued in the isolate
      // before the second task is sent.
      await Future.delayed(const Duration(milliseconds: 10));

      pool.compute((_) {
        // This task completes quickly
        return 2;
      }, null).then((value) {
        results.add(value);
        completer2.complete();
      });

      // Wait for both tasks to complete
      await Future.wait([completer1.future, completer2.future]);

      // Verify that results were added in the order of task execution
      expect(results, orderedEquals([1, 2]));
    });
    
    test('sequential execution with pool.execute', () async {
      final results = <int>[];
      final completer1 = Completer<void>();
      final completer2 = Completer<void>();

      pool.compute((_) async {
        // This task simulates some work with a delay
        await Future.delayed(const Duration(milliseconds: 100));
        return 1;
      }, null).then((value) {
        results.add(value);
        completer1.complete();
      });

      // Ensure the first task is likely sent and queued in the isolate
      // before the second task is sent.
      await Future.delayed(const Duration(milliseconds: 10));

      pool.compute((_) {
        // This task completes quickly
        return 2;
      }, null).then((value) {
        results.add(value );
        completer2.complete();
      });

      // Wait for both tasks to complete
      await Future.wait([completer1.future, completer2.future]);

      // Verify that results were added in the order of task execution
      expect(results, orderedEquals([1, 2]));
    });

    test('error propagation from compute', () async {
      Future<void> task() async {
        await pool.compute((_) {
          // This task will throw an error
          throw Exception('Task Error compute');
        }, null);
      }
      // We expect the task to throw an Exception that contains the message 'Task Error compute'
      expect(task(), throwsA(
          isA<Exception>().having((e) => e.toString(), 'message',
              contains('Task Error compute'))));
    });

    test('compute with arguments', () async {
      final argument = 10;
      final expectedResult = argument * 2;

      final result = await pool.compute((int arg) {
        return arg * 2;
      }, argument);

      expect(result, equals(expectedResult));
    });
  });
}
