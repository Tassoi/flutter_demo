import 'package:flutter/foundation.dart';

/// 一次应用级重定向判断所需的稳定输入。
///
/// [uri] 是 go_router 已解析的当前目标位置。策略可以检查 path、query 和 fragment，
/// 但不得记录其中可能来自深链的动态值，也不得把它直接展示给用户。本对象不暴露
/// go_router 状态、BuildContext 或 Navigator，避免认证等后续模块控制全局 Router。
@immutable
final class AppRouteRedirectRequest {
  /// 创建只包含目标 [uri] 的重定向请求。
  const AppRouteRedirectRequest({required this.uri});

  /// 当前导航尝试的完整应用 URI。
  final Uri uri;
}

/// 应用 Router 在每次导航前调用的可替换重定向策略。
///
/// 返回 `null` 或与 [AppRouteRedirectRequest.uri] 相同的 URI 表示放行；返回另一个 URI
/// 表示重定向。策略必须同步、确定、无导航副作用，并允许被重复调用；不得在实现中调用
/// Navigator 或 Router，否则容易形成重入和重定向循环。
///
/// [AppRouter] 只接受站内绝对路径作为返回值，并把非法目标交给不泄漏详情的统一错误页。
/// 当前默认实现不执行认证判断。登录、会话刷新及认证状态驱动的重新求值属于第二阶段。
abstract interface class AppRouteRedirectPolicy {
  /// 判断 [request] 是否需要改写到另一个站内位置。
  Uri? redirect(AppRouteRedirectRequest request);
}

/// 不改变任何导航目标的第一阶段默认策略。
///
/// 该实现明确表示“允许访问”，不是已登录状态，也不预设认证模型。未来认证模块可以通过
/// [AppRouteRedirectPolicy] 注入替代实现，而无需让 Feature 依赖 go_router。
final class AllowAllAppRouteRedirectPolicy implements AppRouteRedirectPolicy {
  /// 创建无状态的允许策略。
  const AllowAllAppRouteRedirectPolicy();

  @override
  Uri? redirect(AppRouteRedirectRequest request) => null;
}
