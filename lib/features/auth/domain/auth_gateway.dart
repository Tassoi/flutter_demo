import 'package:flutter_template/core/network/network_cancellation_token.dart';
import 'package:flutter_template/core/network/network_client.dart';
import 'package:flutter_template/features/auth/domain/auth_credentials.dart';

/// 提交给认证 gateway 的一次敏感登录输入。
///
/// 本类型不会进入状态或日志，只在用户提交到 gateway 的 Future 生命周期内存在。它不假设
/// 标识符是邮箱、手机号或用户名，也不修改密码内容；真实 adapter 负责协议编码和服务端
/// 字段映射。
final class AuthSignInRequest {
  /// 创建经过基本边界校验的登录输入。
  ///
  /// [identifier] 会去除首尾空白后保存，长度最多 320 且不能包含控制字符；[password]
  /// 不会 trim，必须为 1 到 4096 个 UTF-16 code unit 且不含控制字符。非法错误不会回显
  /// 输入。具体密码策略必须由服务端决定，模板不能提前拒绝合法账号规则。
  factory AuthSignInRequest({
    required String identifier,
    required String password,
  }) {
    final normalizedIdentifier = identifier.trim();
    if (normalizedIdentifier.isEmpty ||
        normalizedIdentifier.length > 320 ||
        _inputControlCharacterPattern.hasMatch(normalizedIdentifier)) {
      throw ArgumentError('Authentication identifier is invalid.');
    }
    if (password.isEmpty ||
        password.length > 4096 ||
        _inputControlCharacterPattern.hasMatch(password)) {
      throw ArgumentError('Authentication password is invalid.');
    }
    return AuthSignInRequest._(
      identifier: normalizedIdentifier,
      password: password,
    );
  }

  const AuthSignInRequest._({required this.identifier, required this.password});

  /// 只供 gateway 请求编码读取的登录标识符。
  final String identifier;

  /// 只供 gateway 请求编码读取的原始密码。
  final String password;

  @override
  String toString() => 'AuthSignInRequest([REDACTED])';
}

final _inputControlCharacterPattern = RegExp(r'[\x00-\x1F\x7F]');

/// 项目后端认证协议的可替换边界。
///
/// 模板不规定 URL、JSON 字段、OAuth provider 或第三方 SDK。production 默认使用明确的
/// 未配置实现；接入真实服务时，adapter 应使用基础 [NetworkClient] 发送登录与刷新请求，
/// 不能使用认证网络装饰器，否则 401 会递归触发刷新。
///
/// 实现只返回 [AuthCredentials]，并把已证明的服务语义转换为稳定 `AuthFailure`。取消令牌
/// 属于协作信号；收到取消后不得再把迟到响应解释为当前会话。
abstract interface class AuthGateway {
  /// 使用 [request] 登录并返回一组完整的新凭据。
  Future<AuthCredentials> signIn(
    AuthSignInRequest request, {
    required NetworkCancellationToken cancellationToken,
  });

  /// 使用敏感 [refreshCredential] 换取一组完整的新凭据。
  ///
  /// 参数不得记录、展示或放入错误。刷新拒绝应抛 `AuthSessionExpiredFailure`；连接类失败
  /// 可以抛稳定网络错误，由 session controller 折叠为安全认证状态。
  Future<AuthCredentials> refresh({
    required String refreshCredential,
    required NetworkCancellationToken cancellationToken,
  });
}
