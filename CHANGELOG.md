## 1.0.0

* 首个版本完成，默认实现3个常用创建方式

## 1.0.1

* 优化代码结构，新增单isolate时可以不使用队列保存task直接发送到isolate

## 1.0.2

* 增加isolate初始化时存入map values
* keepAliveTime为0时优化isolate的退出机制
* 优化isolate之间的数据传

## 1.0.3

* 优化IsolateNoCache的通信次数，使性能接近Isolate.run

## 1.0.4

* 增加常用的扩展方法