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

final pool1 = IsolatePoolExecutor.newSingleIsolateExecutor();

// 用来提交任务
pool1.compute(_doTask, 100000000);

//终止池
pool1.shutdown();

```

See [example](https://github.com/aymtools/isolate_pool_executor/example) for detailed test
case.

## Issues

If you encounter issues, here are some tips for debug, if nothing helps report
to [issue tracker on GitHub](https://github.com/aymtools/isolate_pool_executor/issues):
