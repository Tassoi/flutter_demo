/// 认证模块可以稳定暴露给状态层和 UI 的失败基类。
///
/// [code] 供程序分支与本地化映射使用；具体 gateway 异常、响应正文、账号标识、密码和
/// credential 都不会保存在错误对象中。UI 即使格式化整个对象，也只会得到稳定 code。
sealed class AuthFailure implements Exception {
  const AuthFailure({required this.code});

  /// 跨 gateway 实现保持稳定且不含动态数据的错误代码。
  final String code;

  @override
  String toString() => '$runtimeType(code: $code)';
}

/// 登录服务尚未配置或当前无法访问。
final class AuthServiceUnavailableFailure extends AuthFailure {
  /// 创建不携带地址、响应或底层异常的服务不可用失败。
  const AuthServiceUnavailableFailure() : super(code: 'auth.unavailable');
}

/// 服务明确拒绝了登录凭据。
final class AuthSignInRejectedFailure extends AuthFailure {
  /// 创建不区分账号是否存在、密码是否错误的统一拒绝结果。
  ///
  /// 合并原因可以避免 UI 和日志形成账号枚举通道。需要验证码、锁定或 MFA 的项目应在
  /// 明确后端协议后新增经过安全评审的稳定状态。
  const AuthSignInRejectedFailure() : super(code: 'auth.sign_in_rejected');
}

/// 当前会话已经失效，必须重新登录。
final class AuthSessionExpiredFailure extends AuthFailure {
  /// 创建不暴露 401 正文、refresh credential 或后端原因的失效结果。
  const AuthSessionExpiredFailure() : super(code: 'auth.session_expired');
}

/// 安全凭据无法可靠读取、写入或删除。
final class AuthPersistenceFailure extends AuthFailure {
  /// 创建不区分安全存储键、平台或插件异常的持久化失败。
  const AuthPersistenceFailure() : super(code: 'auth.persistence');
}

/// 没有经过验证的认证错误映射时使用的固定失败。
final class UnexpectedAuthFailure extends AuthFailure {
  /// 创建不保留原始异常的未知认证失败。
  const UnexpectedAuthFailure() : super(code: 'auth.unexpected');
}
