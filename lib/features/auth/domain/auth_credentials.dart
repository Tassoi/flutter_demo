/// 登录或刷新成功后得到的敏感认证凭据集合。
///
/// 本类型只在认证 data/controller 边界内流转，不得放入 Riverpod 可打印状态、普通存储、
/// 日志 context、错误详情或 Widget。access 与 refresh credential 都会严格校验，但不会
/// 解析具体 JWT/OAuth 格式；真实服务 adapter 负责把后端协议映射到本项目模型。
final class AuthCredentials {
  /// 创建一组具有明确 UTC 有效期的凭据。
  ///
  /// 两项 credential 必须非空、无首尾空白且不含控制字符。[refreshExpiresAt] 不得早于
  /// [accessExpiresAt]，否则刷新能力可能先于当前访问凭据失效，属于 adapter 契约错误。
  /// 参数非法时抛出的 [ArgumentError] 使用固定文本，不回显任何凭据。
  factory AuthCredentials({
    required String accessCredential,
    required String refreshCredential,
    required DateTime accessExpiresAt,
    required DateTime refreshExpiresAt,
  }) {
    _validateCredential(accessCredential);
    _validateCredential(refreshCredential);
    final accessExpiry = accessExpiresAt.toUtc();
    final refreshExpiry = refreshExpiresAt.toUtc();
    if (refreshExpiry.isBefore(accessExpiry)) {
      throw ArgumentError(
        'Refresh credential expiry cannot precede access credential expiry.',
      );
    }
    return AuthCredentials._(
      accessCredential: accessCredential,
      refreshCredential: refreshCredential,
      accessExpiresAt: accessExpiry,
      refreshExpiresAt: refreshExpiry,
    );
  }

  const AuthCredentials._({
    required this.accessCredential,
    required this.refreshCredential,
    required this.accessExpiresAt,
    required this.refreshExpiresAt,
  });

  /// 只供凭据注入器读取的 access credential。
  final String accessCredential;

  /// 只供 [AuthGateway] 刷新会话时读取的 refresh credential。
  final String refreshCredential;

  /// access credential 的 UTC 失效时刻。
  final DateTime accessExpiresAt;

  /// refresh credential 的 UTC 失效时刻。
  final DateTime refreshExpiresAt;

  /// 判断 access credential 在 [now] 时是否仍可发送。
  ///
  /// 到达失效时刻即视为不可用，不提供隐式宽限期；需要提前刷新的项目应在真实 gateway
  /// 或更明确的会话策略中配置，而不是修改时间比较语义。
  bool isAccessUsableAt(DateTime now) => now.toUtc().isBefore(accessExpiresAt);

  /// 判断 refresh credential 在 [now] 时是否仍可用于换取新会话。
  bool isRefreshUsableAt(DateTime now) =>
      now.toUtc().isBefore(refreshExpiresAt);

  @override
  String toString() => 'AuthCredentials([REDACTED])';
}

final _credentialControlCharacterPattern = RegExp(r'[\x00-\x1F\x7F]');

void _validateCredential(String value) {
  if (value.isEmpty ||
      value != value.trim() ||
      _credentialControlCharacterPattern.hasMatch(value)) {
    throw ArgumentError('Authentication credential is invalid.');
  }
}
