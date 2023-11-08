import 'dart:collection';
import 'dart:isolate';
import 'dart:math';

import 'package:isolate_pool_executor/isolate_pool_executor.dart';

main() {
  final pool1 = IsolatePoolExecutor.newSingleIsolateExecutor();

  pool1.compute(printName, 100000000);
  pool1.compute(printName, 100000001);
  pool1.compute(printName, 100000002);
  pool1.compute(printName, 100000003);
  pool1.compute(printName, 100000004);
  pool1.compute(printName, 100000005);
  pool1.compute(printName, 100000006);

  ///如果不执行shutdown 则会一直等待新任务 不会退出
  pool1.shutdown();

  //将会如下打印
  // IsolatePoolExecutor-0-worker start input: 100000000
  // IsolatePoolExecutor-0-worker end input: 100000000 value: 499931747952  use time: 1551
  // IsolatePoolExecutor-0-worker start input: 100000001
  // IsolatePoolExecutor-0-worker end input: 100000001 value: 499945187362  use time: 1405
  // IsolatePoolExecutor-0-worker start input: 100000002
  // IsolatePoolExecutor-0-worker end input: 100000002 value: 499940162718  use time: 1400
  // IsolatePoolExecutor-0-worker start input: 100000003
  // IsolatePoolExecutor-0-worker end input: 100000003 value: 499907550879  use time: 1291
  // IsolatePoolExecutor-0-worker start input: 100000004
  // IsolatePoolExecutor-0-worker end input: 100000004 value: 499952207275  use time: 1362
  // IsolatePoolExecutor-0-worker start input: 100000005
  // IsolatePoolExecutor-0-worker end input: 100000005 value: 499985831624  use time: 1293
  // IsolatePoolExecutor-0-worker start input: 100000006
  // IsolatePoolExecutor-0-worker end input: 100000006 value: 499935347702  use time: 1125
  //
  // Process finished with exit code 0

  final pool2 = IsolatePoolExecutor.newFixedIsolatePool(3);
  pool2.compute(printName, 200000000);
  pool2.compute(printName, 200000001);
  pool2.compute(printName, 200000002);
  pool2.compute(printName, 200000003);
  pool2.compute(printName, 200000004);
  pool2.compute(printName, 200000005);
  pool2.compute(printName, 200000006);

  ///如果不执行shutdown 则会一直等待新任务 不会退出
  pool2.shutdown();
  //其中某一次会如下打印
  // IsolatePoolExecutor-1-worker start input: 200000001
  // IsolatePoolExecutor-2-worker start input: 200000002
  // IsolatePoolExecutor-0-worker start input: 200000000
  // IsolatePoolExecutor-2-worker end input: 200000002 value: 999807824711  use time: 2167
  // IsolatePoolExecutor-2-worker start input: 200000003
  // IsolatePoolExecutor-0-worker end input: 200000000 value: 999798195612  use time: 3906
  // IsolatePoolExecutor-0-worker start input: 200000004
  // IsolatePoolExecutor-1-worker end input: 200000001 value: 999929274810  use time: 4079
  // IsolatePoolExecutor-1-worker start input: 200000005
  // IsolatePoolExecutor-2-worker end input: 200000003 value: 999871536520  use time: 2226
  // IsolatePoolExecutor-2-worker start input: 200000006
  // IsolatePoolExecutor-0-worker end input: 200000004 value: 999930512191  use time: 2198
  // IsolatePoolExecutor-1-worker end input: 200000005 value: 999890205891  use time: 3651
  // IsolatePoolExecutor-2-worker end input: 200000006 value: 999852440430  use time: 3919
  //
  // Process finished with exit code 0

  final pool3 = IsolatePoolExecutor.newCachedIsolatePool();
  pool3.compute(printName, 500000000);
  pool3.compute(printName, 500000001);
  pool3.compute(printName, 500000002);
  pool3.compute(printName, 500000003);
  pool3.compute(printName, 500000004);
  pool3.compute(printName, 500000005);
  pool3.compute(printName, 500000006);

  // 非必须 任务队列空后会自动退出所有的后台isolate
  //pool3.shutdown();
  //其中某一次会如下打印
  // IsolatePoolExecutor-3-worker start input: 500000003
  // IsolatePoolExecutor-4-worker start input: 500000004
  // IsolatePoolExecutor-6-worker start input: 500000006
  // IsolatePoolExecutor-5-worker start input: 500000005
  // IsolatePoolExecutor-0-worker start input: 500000000
  // IsolatePoolExecutor-1-worker start input: 500000001
  // IsolatePoolExecutor-2-worker start input: 500000002
  // IsolatePoolExecutor-6-worker end input: 500000006 value: 2499721241141  use time: 6502
  // IsolatePoolExecutor-1-worker end input: 500000001 value: 2499721459535  use time: 10303
  // IsolatePoolExecutor-4-worker end input: 500000004 value: 2499851277264  use time: 10989
  // IsolatePoolExecutor-2-worker end input: 500000002 value: 2499672191358  use time: 11025
  // IsolatePoolExecutor-5-worker end input: 500000005 value: 2499756041921  use time: 11083
  // IsolatePoolExecutor-3-worker end input: 500000003 value: 2499844333942  use time: 11244
  // IsolatePoolExecutor-0-worker end input: 500000000 value: 2499679184934  use time: 13071
  //
  // Process finished with exit code 0

  final pool4 = IsolatePoolExecutor(
      corePoolSize: 2,
      maximumPoolSize: 4,
      keepAliveTime: Duration(seconds: 1),
      taskQueue: Queue(),
      handler: RejectedExecutionHandler.abortPolicy);
  pool4.compute(printName, 500000000);
  pool4.compute(printName, 500000001);
  pool4.compute(printName, 500000002);
  pool4.compute(printName, 500000003);
  pool4.compute(printName, 500000004);
  pool4.compute(printName, 500000005);
  pool4.compute(printName, 500000006);
  pool4.shutdown();
}

int printName(int n) {
  int startTime = DateTime.now().millisecondsSinceEpoch;
  print(Isolate.current.debugName! + ' start input: $n ');
  final v = _doTask(n);
  int endTime = DateTime.now().millisecondsSinceEpoch;
  print(Isolate.current.debugName! +
      ' end input: $n value: $v  use time: ${endTime - startTime}');
  return v;
}

int _doTask(int count) {
  int sum = 0;
  final random = new Random();
  for (int i = 0; i < count; i++) {
    sum += random.nextInt(10000);
  }
  return sum;
}
