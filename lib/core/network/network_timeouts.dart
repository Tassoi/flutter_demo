/// 网络客户端使用的确定性超时集合。
///
/// 所有值都必须大于零，模板不允许用 `null` 或 [Duration.zero] 静默关闭保护。Dio 的
/// receive timeout 表示相邻响应数据事件之间的等待上限，不是整个请求的总时限；业务若
/// 需要端到端 deadline，应在具体用例有证据后另行设计，而不是误用本类型。
final class NetworkTimeouts {
  const NetworkTimeouts._({
    required this.connect,
    required this.send,
    required this.receive,
    required this.transform,
  });

  /// 模板使用的安全、有界默认值。
  static const defaults = NetworkTimeouts._(
    connect: Duration(seconds: 10),
    send: Duration(seconds: 15),
    receive: Duration(seconds: 20),
    transform: Duration(seconds: 5),
  );

  /// 创建自定义超时集合。
  ///
  /// 任一值小于或等于零时抛出 [ArgumentError]。超时是客户端资源上限，不代表请求可以
  /// 自动重试；本阶段没有隐式重试，避免重复执行有副作用的请求。
  factory NetworkTimeouts({
    Duration connect = const Duration(seconds: 10),
    Duration send = const Duration(seconds: 15),
    Duration receive = const Duration(seconds: 20),
    Duration transform = const Duration(seconds: 5),
  }) {
    _requirePositive('connect', connect);
    _requirePositive('send', send);
    _requirePositive('receive', receive);
    _requirePositive('transform', transform);
    return NetworkTimeouts._(
      connect: connect,
      send: send,
      receive: receive,
      transform: transform,
    );
  }

  /// 建立连接的等待上限。
  final Duration connect;

  /// 上传请求数据的等待上限。
  final Duration send;

  /// 相邻响应数据事件之间的等待上限。
  final Duration receive;

  /// Dio 在后台 isolate 转换大响应时的等待上限。
  final Duration transform;

  static void _requirePositive(String name, Duration value) {
    if (value <= Duration.zero) {
      throw ArgumentError('$name timeout must be greater than zero.');
    }
  }
}
