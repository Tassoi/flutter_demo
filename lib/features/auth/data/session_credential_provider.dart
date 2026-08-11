import 'package:flutter_template/core/network/network_credential_provider.dart';
import 'package:flutter_template/features/auth/domain/auth_session_coordinator.dart';

/// 把唯一 session controller 的内存 access credential 接入基础网络客户端。
///
/// 本 adapter 不缓存 credential，也不读取安全存储。每次受保护请求都会委托
/// [AuthSessionCoordinator.loadNetworkCredential]，因此登录、刷新、退出和失效后的变化立即
/// 生效；未认证时返回 `null`，由既有网络 adapter 折叠为稳定凭据不可用错误。
final class SessionCredentialProvider implements NetworkCredentialProvider {
  /// 使用由 Riverpod 管理的 [coordinator] 创建凭据提供者。
  const SessionCredentialProvider(this._coordinator);

  final AuthSessionCoordinator _coordinator;

  @override
  Future<NetworkCredential?> loadCredential() {
    return _coordinator.loadNetworkCredential();
  }

  @override
  String toString() => 'SessionCredentialProvider([REDACTED])';
}
