## 1.2.1

* 在非release模式下(assert 来判断),默认的创建等待时间改为6s，release模式不影响依旧为3s

## 1.2.0

* 新增一个参数onIsolateCreateTimeoutTimesDoNotCreateNew, 当创建isolate时连续出现n次超时，则不再创建新的，只使用当前已经启动完成的,
  如果未出现创建超时，则正常使用包含m个核心的isolate，和其他的cached isolate
* 可利用此特性来缓解 https://github.com/flutter/flutter/issues/132731
  参见 [readme](https://github.com/aymtools/isolate_pool_executor/blob/master/README.md)

## 1.1.5

* IsolatePoolExecutor和IsolatePoolExecutor.newFixedIsolatePool增加启动参数immediatelyStartedCore
  可自定义立即启动isolate的数量

## 1.1.4

* onIsolateCreated回调中的isolateValues是不可空的默认会生成一个空的map
* pool新增isShutdown可判断当前是否是已经调用shutdown后的状态
* readme中增加在flutter中isolate里调用methodChannel的说明

## 1.1.3

* 将compute的返回值包装为TaskFuture,可查看当前的taskid以及传入的tag相关

## 1.1.2

* 新增可以指定IsolatePoolExecutor的debugLabel

## 1.1.1

* 增加创建一个参数onIsolateCreated当Isolate创建后会立即调用，配合isolateValues可以实现初始化当前个Isolate的一些数据。
* 例如： https://medium.com/flutter/introducing-background-isolate-channels-7a299609cad8 此需求
* Isolate直接的交互使用RawReceivePort

## 1.1.0

* 优化首次启动isolate时直接携带任务，减少一次发送，同时调整isolated的空闲判断
* 增加验证启动Isolate的超时判断，已知原因 https://github.com/flutter/flutter/issues/132731
* 增加一个参数launchCoreImmediately默认为false 立即启动所有的core Isolate

## 1.0.6

* newCachedIsolatePool的队列修正为QueueEmpty不可添加任何任务

## 1.0.5

* 当send task失败时抛出异常
* isolate中的worker增加全局异常捕获

## 1.0.4

* 增加常用的扩展方法

## 1.0.3

* 优化IsolateNoCache的通信次数，使性能接近Isolate.run

## 1.0.2

* 增加isolate初始化时存入map values
* keepAliveTime为0时优化isolate的退出机制
* 优化isolate之间的数据传

## 1.0.1

* 优化代码结构，新增单isolate时可以不使用队列保存task直接发送到isolate

## 1.0.0

* 首个版本完成，默认实现3个常用创建方式

