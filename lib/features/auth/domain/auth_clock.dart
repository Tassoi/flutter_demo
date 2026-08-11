/// 认证会话判断凭据有效期时使用的可替换时钟。
///
/// production 使用 [SystemAuthClock]。测试应注入固定时钟，避免依赖设备时间、时区或执行
/// 速度；所有返回值都会由凭据模型转换为 UTC，因此实现不应自行加入宽限期或时钟偏移。
abstract interface class AuthClock {
  /// 返回当前时间；调用方会立即转换为 UTC 后进行有效期比较。
  DateTime now();
}

/// 从 Dart 系统时钟读取当前时间的 production 实现。
final class SystemAuthClock implements AuthClock {
  /// 创建无缓存的系统时钟。
  const SystemAuthClock();

  @override
  DateTime now() => DateTime.now().toUtc();
}
