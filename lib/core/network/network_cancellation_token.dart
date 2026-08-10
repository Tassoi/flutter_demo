/// 由状态层控制、与具体网络插件无关的请求取消令牌。
///
/// 同一个令牌可以取消多个并发请求；[cancel] 首次调用会同步通知当前全部监听者，后续
/// 调用不产生额外效果。请求结束后 adapter 必须注销监听，避免长期持有请求 header、body
/// 或传输资源。
///
/// 取消只是一种协作信号，不能回滚服务端已经执行的操作。对于会产生副作用的 endpoint，
/// 调用方仍需使用服务端幂等策略，而不能把客户端取消当成事务保证。
final class NetworkCancellationToken {
  final Map<int, void Function()> _listeners = <int, void Function()>{};
  bool _isCancelled = false;
  int _nextRegistrationId = 0;

  /// 当前是否已经发出取消信号。
  bool get isCancelled => _isCancelled;

  /// 注册一个在取消时同步执行的 [listener]。
  ///
  /// 如果令牌已经取消，[listener] 会在本方法返回前执行。返回函数用于幂等注销；网络
  /// adapter 必须在请求完成或失败后的 `finally` 中调用它。监听者异常会被隔离，确保一个
  /// 传输实现的清理失败不会阻止其他请求收到取消信号。
  void Function() register(void Function() listener) {
    if (_isCancelled) {
      _notifySafely(listener);
      return _noOp;
    }
    final registrationId = _nextRegistrationId++;
    _listeners[registrationId] = listener;
    var isRegistered = true;
    return () {
      if (!isRegistered) {
        return;
      }
      isRegistered = false;
      _listeners.remove(registrationId);
    };
  }

  /// 发出一次取消信号。
  ///
  /// 本方法幂等且不会因监听者失败而抛出异常。取消时先清空内部集合，再通知快照中的
  /// 监听者，因此回调内再次调用 [cancel] 或注销自身都不会造成并发修改。
  void cancel() {
    if (_isCancelled) {
      return;
    }
    _isCancelled = true;
    final listeners = List<void Function()>.of(_listeners.values);
    _listeners.clear();
    for (final listener in listeners) {
      _notifySafely(listener);
    }
  }

  static void _notifySafely(void Function() listener) {
    try {
      listener();
    } on Object {
      // 取消必须保持非抛出语义；监听者属于已测试的基础设施 adapter，此处也没有可安全
      // 记录任意回调异常的 logger 边界，因此仅隔离失败并继续通知其他请求。
    }
  }

  static void _noOp() {}

  @override
  String toString() => 'NetworkCancellationToken(isCancelled: $_isCancelled)';
}
