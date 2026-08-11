import 'package:flutter_template/core/network/network_cancellation_token.dart';
import 'package:flutter_template/features/auth/domain/auth_credentials.dart';
import 'package:flutter_template/features/auth/domain/auth_failure.dart';
import 'package:flutter_template/features/auth/domain/auth_gateway.dart';

/// 模板尚未绑定真实后端时使用的明确失败 gateway。
///
/// 它不接受任何本地测试账号、不生成伪 Token，也不访问 `.invalid` 地址。项目接入服务端
/// 后必须在应用组装层整体替换本实现，并保持登录/刷新请求使用未装饰的基础网络客户端。
final class UnconfiguredAuthGateway implements AuthGateway {
  /// 创建无状态的未配置 gateway。
  const UnconfiguredAuthGateway();

  @override
  Future<AuthCredentials> signIn(
    AuthSignInRequest request, {
    required NetworkCancellationToken cancellationToken,
  }) {
    return Future<AuthCredentials>.error(const AuthServiceUnavailableFailure());
  }

  @override
  Future<AuthCredentials> refresh({
    required String refreshCredential,
    required NetworkCancellationToken cancellationToken,
  }) {
    return Future<AuthCredentials>.error(const AuthSessionExpiredFailure());
  }
}
