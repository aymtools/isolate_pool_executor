## 2.1.0

* customizeTaskInvoker adds new parameters: taskLabel, what, and tag, derived from the corresponding
  parameters in compute.

### Breaking Changes

* The tag parameter in compute will be sent to the isolate. Note that you should verify whether the
  parameter value can be sent. https://api.dart.dev/dart-isolate/SendPort/send.html

## 2.0.0

* Allow customization of task execution in Isolate.
* Fix `onIsolateCreated` bug
* Improve the ability to capture task exceptions
* Modify debugLabel name

## 1.2.3

* Allow obtaining the content of the message before submitting the task for calculating the order.

## 1.2.2

* Fixed the task execution exception when `taskQueueInIsolate` is set to `true` in `SingleIsolate`.

## 1.2.1

* In non-release mode (determined by `assert`), the default creation waiting time is changed to 6
  seconds. In release mode, it remains unchanged at 3 seconds.

## 1.2.0

* Added a new parameter `onIsolateCreateTimeoutTimesDoNotCreateNew`. If isolate creation times
  out `n` consecutive times, no new isolates will be created, and only the already initialized
  isolates will be used. If no timeouts occur, the pool will use the isolates with `m` cores, along
  with other cached isolates.
* This feature can help alleviate [this issue](https://github.com/flutter/flutter/issues/132731).
  See the [README](https://github.com/aymtools/isolate_pool_executor/blob/master/README.md) for more
  details.

## 1.1.5

* Added the `immediatelyStartedCore` parameter to `IsolatePoolExecutor`
  and `IsolatePoolExecutor.newFixedIsolatePool`, allowing customization of the number of isolates
  that start immediately.

## 1.1.4

* The `isolateValues` in the `onIsolateCreated` callback is now non-nullable and will default to an
  empty map.
* Added `isShutdown` to the pool to check if `shutdown` has been called.
* Updated the README to include instructions on calling `MethodChannel` from an isolate in Flutter.

## 1.1.3

* The return value of `compute` is now wrapped in `TaskFuture`, allowing you to view the
  current `taskId` and related `tag`.

## 1.1.2

* Added support for specifying a `debugLabel` for `IsolatePoolExecutor`.

## 1.1.1

* Added a new `onIsolateCreated` parameter, which is called immediately after an isolate is created.
  This, along with `isolateValues`, allows initialization of data for the isolate.
*

Example: [Introducing background isolate channels](https://medium.com/flutter/introducing-background-isolate-channels-7a299609cad8).

* Interaction with isolates now uses `RawReceivePort`.

## 1.1.0

* Optimized initial isolate startup by directly assigning tasks, reducing one send operation, and
  improved idle state detection for isolates.
* Added timeout validation for isolate startup due
  to [this known issue](https://github.com/flutter/flutter/issues/132731).
* Added a parameter `launchCoreImmediately` (default `false`), which starts all core isolates
  immediately.

## 1.0.6

* Fixed `QueueEmpty` in `newCachedIsolatePool` to prevent adding any tasks.

## 1.0.5

* Threw an exception when sending tasks failed.
* Added global exception handling for workers in isolates.

## 1.0.4

* Added common extension methods.

## 1.0.3

* Optimized communication times in `IsolateNoCache`, bringing performance close to `Isolate.run`.

## 1.0.2

* Added support for storing `map` values during isolate initialization.
* Optimized isolate exit mechanism when `keepAliveTime` is set to 0.
* Improved data transfer between isolates.

## 1.0.1

* Refined code structure. When using a single isolate, tasks can be sent directly to the isolate
  without a queue.

## 1.0.0

* First version completed with 3 common creation methods implemented by default.
