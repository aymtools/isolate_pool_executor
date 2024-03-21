The current package provides background creation of isolates to perform CPU-intensive tasks without
affecting the current isolate.
Just like a thread pool, but with isolates.

## Usage


```dart
int _doTask(int count) {
  int sum = 0;
  final random = new Random();
  for (int i = 0; i < count; i++) {
    sum += random.nextInt(10000);
  }
  return sum;
}

//单个的isolate 任务顺序执行
final pool1 = IsolatePoolExecutor.newSingleIsolateExecutor();

//固定数量的isolate 任务按空闲分配
final pool2 = IsolatePoolExecutor.newFixedIsolatePool(3);
// 不限制总数 会有等待时间超时自动销毁 任务没有空闲的isolate时创建新的，有空闲的使用空闲的
final pool3 = IsolatePoolExecutor.newCachedIsolatePool();

//按需求自定义
final pool4 = IsolatePoolExecutor(
  // 核心数量，无任务时一直等待，需要shutdown后才会销毁
    corePoolSize: 2,
    // 总数 超过核心数之后的超时会自动销毁
    maximumPoolSize: 4,
    //非核心的isolate从超时等待时间
    keepAliveTime: Duration(seconds: 1),
    // 任务寄放队列
    taskQueue: Queue(),
    // 当队列添加失败时的处理方式
    handler: RejectedExecutionHandler.abortPolicy);

void doSomething() async {
  ///...doSomething
  // 用来提交任务
  final result = await pool1.compute(_doTask, 100000000);

  ///...doSomething
}

void willKillPool() {
  //终止池
  pool1.shutdown();
}



```

See [example](https://github.com/aymtools/isolate_pool_executor/blob/master/example/isolate_pool_executor_example.dart) for detailed test
case.

## Issues

If you encounter issues, here are some tips for debug, if nothing helps report
to [issue tracker on GitHub](https://github.com/aymtools/isolate_pool_executor/issues):
