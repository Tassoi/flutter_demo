import 'package:flutter_template/app/router/app_route_redirect_policy.dart';
import 'package:flutter_template/features/auth/domain/auth_session_state.dart';
import 'package:flutter_template/features/auth/routing/auth_route_contract.dart';

/// Router 每次重定向时读取当前稳定认证快照的回调。
typedef AuthSessionStateReader = AuthSessionState Function();

/// 把认证状态映射为登录、恢复加载和受保护位置的同步重定向策略。
///
/// 策略只调用 [sessionStateReader] 读取 Riverpod 已发布的快照，不发起存储、登录、刷新或
/// 导航副作用。恢复期的受保护请求进入固定 loading route；未认证进入登录；认证成功后只
/// 恢复 [AuthRouteContract] 白名单允许的 `returnTo`。非法 query 被丢弃且从不记录。
final class AuthAppRouteRedirectPolicy implements AppRouteRedirectPolicy {
  /// 使用始终返回当前会话快照的 [sessionStateReader] 创建策略。
  const AuthAppRouteRedirectPolicy({required this.sessionStateReader});

  /// 由应用 ProviderScope 提供的同步状态读取边界。
  final AuthSessionStateReader sessionStateReader;

  @override
  Uri? redirect(AppRouteRedirectRequest request) {
    final session = sessionStateReader();
    final currentUri = request.uri;
    final returnTo = AuthRouteContract.tryParseReturnTo(
      currentUri.queryParameters[AuthRouteContract.returnToQueryParameter],
    );

    if (currentUri.path == AuthRouteContract.signInPath) {
      // 未认证、失败和登录进行中都必须停留在登录页。已认证时只恢复白名单目标；直接访问
      // 或携带非法 returnTo 的登录页回到公开首页，形成明确终止点而不会循环。
      return session.isAuthenticated ? returnTo ?? Uri(path: '/') : null;
    }

    if (currentUri.path == AuthRouteContract.sessionLoadingPath) {
      if (session.isRestoring) {
        return null;
      }
      if (session.isAuthenticated) {
        return returnTo ?? Uri(path: '/');
      }
      return AuthRouteContract.signInLocation(returnTo: returnTo);
    }

    if (AuthRouteContract.isProtected(currentUri)) {
      final canonicalReturnTo = Uri(path: AuthRouteContract.protectedLocation);
      if (session.isRestoring) {
        return AuthRouteContract.sessionLoadingLocation(
          returnTo: canonicalReturnTo,
        );
      }
      if (!session.isAuthenticated) {
        return AuthRouteContract.signInLocation(returnTo: canonicalReturnTo);
      }
    }

    return null;
  }
}
