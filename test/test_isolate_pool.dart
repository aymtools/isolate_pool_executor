import 'dart:isolate';

import 'package:isolate_pool_executor/isolate_pool_executor.dart';
import 'package:test/test.dart';

void main() {
  group('Isolate', () {
    late IsolatePoolExecutor pool;
    setUp(() {
      pool = IsolatePoolExecutor.newSingleIsolateExecutor();
    });

    tearDown(() {
      pool.shutdown();
    });

    test('current', () async {
      final curIsolateHash = Isolate.current.hashCode;

      final targetIsolateHash =
          await pool.execute((_) => Isolate.current.hashCode, null);

      expect(Isolate.current.hashCode, curIsolateHash);

      expect(curIsolateHash == targetIsolateHash, false);

      final targetIsolateHash2 =
          await pool.execute((_) => Isolate.current.hashCode, null);

      expect(curIsolateHash == targetIsolateHash2, false);
      expect(targetIsolateHash == targetIsolateHash2, true);
    });
  });
}
