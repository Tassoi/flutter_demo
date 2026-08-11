import 'package:flutter_template/core/network/network_credential_provider.dart';

/// 认证网络 adapter 与 Riverpod session controller 之间的最小协作接口。
///
/// 实现仍由唯一 Riverpod controller 拥有全部敏感状态；本接口不复制状态，也不暴露 refresh
/// credential。认证装饰器只会在受保护请求收到 401 后调用 [refreshSession]，并在重放仍
/// 收到 401 时调用 [invalidateSession]。
abstract interface class AuthSessionCoordinator {
  /// 当前认证会话的非敏感代次。
  ///
  /// 登录、退出、失效或销毁会推进该值，普通 access credential 刷新不会推进。网络装饰器
  /// 应在受保护请求开始时保存代次，并在交付响应、刷新、重放或失效前重新核对；若代次已
  /// 变化，说明结果属于旧会话，必须按取消处理，不能把旧请求带入新账号。
  int get sessionGeneration;

  /// 返回当前 access credential，必要时先执行共享刷新。
  Future<NetworkCredential?> loadNetworkCredential();

  /// 为当前 session generation 执行或等待唯一一次刷新。
  Future<void> refreshSession();

  /// 立即使当前内存会话失效，并尽力删除安全存储 envelope。
  Future<void> invalidateSession();
}
