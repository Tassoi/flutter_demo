import 'package:flutter/material.dart';
import 'package:flutter_template/app/router/app_route_redirect_policy.dart';
import 'package:flutter_template/features/example/presentation/example_detail_page.dart';
import 'package:flutter_template/features/example/routing/example_route_contract.dart';
import 'package:flutter_template/shared/assets/app_assets.dart';
import 'package:flutter_template/shared/design/app_layout_tokens.dart';
import 'package:go_router/go_router.dart';

/// 应用唯一的声明式路由组装与生命周期边界。
///
/// 本类型把 go_router、根 Navigator、ShellRoute Navigator、未知页和顶层重定向集中在
/// `app/`。Feature 只公开路径及参数契约，不能创建 [AppRouter]、持有全局 Router 或依赖
/// go_router 类型。
///
/// 首页与详情位于 ShellRoute 的嵌套 Navigator，保留应用壳层并形成后续 Feature 页面可
/// 复用的导航边界；无法匹配的 URI 和重定向异常由根 Navigator 展示固定安全状态。调用方
/// 必须在根 Widget 销毁时调用 [dispose]，该方法幂等且不会处置外部重定向策略。
final class AppRouter {
  /// 使用 [appName] 和可替换的 [redirectPolicy] 创建路由表。
  ///
  /// [appName] 只用于首页展示且不得为空白。[redirectPolicy] 默认完全放行，不包含认证
  /// 业务。构造过程没有网络、存储或平台 I/O；路由配置错误属于开发期缺陷，应由本文件
  /// 的测试和静态分析阻止发布。
  factory AppRouter({
    required String appName,
    AppRouteRedirectPolicy redirectPolicy =
        const AllowAllAppRouteRedirectPolicy(),
  }) {
    if (appName.trim().isEmpty) {
      throw ArgumentError('App name must contain readable text.');
    }

    final rootNavigatorKey = GlobalKey<NavigatorState>(
      debugLabel: 'app-root-navigator',
    );
    final shellNavigatorKey = GlobalKey<NavigatorState>(
      debugLabel: 'app-shell-navigator',
    );

    final router = GoRouter(
      navigatorKey: rootNavigatorKey,
      redirect:
          (_, state) =>
              _resolveRedirect(policy: redirectPolicy, currentUri: state.uri),
      errorBuilder: (_, _) {
        // go_router 的默认错误页会显示异常文本，其中可能包含外部深链或策略异常详情。
        // 统一替换为固定状态，原始 URI、query 和 error 对象都不跨入 Widget 类型边界。
        return const Scaffold(
          body: _RouteProblemView(kind: _RouteProblemKind.unknown),
        );
      },
      routes: <RouteBase>[
        ShellRoute(
          navigatorKey: shellNavigatorKey,
          builder:
              (_, _, child) => _AppRouteShell(
                key: const Key('app-route-shell'),
                child: child,
              ),
          routes: <RouteBase>[
            GoRoute(
              path: '/',
              name: _homeRouteName,
              builder: (_, _) => _TemplateHomeRoute(appName: appName),
              routes: <RouteBase>[
                GoRoute(
                  path: ExampleRouteContract.detailPath,
                  name: ExampleRouteContract.detailRouteName,
                  builder: (_, state) {
                    final itemId = ExampleRouteContract.tryParseItemId(
                      state.pathParameters[ExampleRouteContract
                          .itemIdParameter],
                    );
                    if (itemId == null) {
                      return const _RouteProblemView(
                        kind: _RouteProblemKind.invalidParameter,
                      );
                    }
                    return _ExampleDetailRoute(itemId: itemId);
                  },
                ),
              ],
            ),
          ],
        ),
      ],
    );

    return AppRouter._(router);
  }

  AppRouter._(this._router);

  static const String _homeRouteName = 'app.home';

  final GoRouter _router;
  var _isDisposed = false;

  /// 提供给 `MaterialApp.router` 的 Flutter Router 配置。
  ///
  /// 返回类型使用 Flutter 自有 [RouterConfig]，不会把 GoRouter 暴露给 Feature。实例在
  /// [dispose] 后不再可用，继续读取会抛出不包含路由数据的 [StateError]。
  RouterConfig<Object> get routerConfig {
    _ensureActive();
    return _router;
  }

  /// 释放 go_router 持有的解析器、delegate 和 route information provider。
  ///
  /// 本方法可以重复调用；它不释放 [AppRouteRedirectPolicy]，策略及其未来可能依赖的认证
  /// 状态由创建策略的应用组装层拥有。
  void dispose() {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    _router.dispose();
  }

  void _ensureActive() {
    if (_isDisposed) {
      throw StateError('AppRouter has already been disposed.');
    }
  }
}

String? _resolveRedirect({
  required AppRouteRedirectPolicy policy,
  required Uri currentUri,
}) {
  final destination = policy.redirect(AppRouteRedirectRequest(uri: currentUri));
  if (destination == null || destination == currentUri) {
    return null;
  }
  if (!_isSafeInternalLocation(destination)) {
    // 错误文本保持固定，不回显可能携带凭据或个人数据的策略返回 URI。
    throw const FormatException(
      'Route redirects must target an internal absolute path.',
    );
  }
  return destination.toString();
}

bool _isSafeInternalLocation(Uri uri) {
  return !uri.hasScheme &&
      !uri.hasAuthority &&
      uri.userInfo.isEmpty &&
      uri.path.startsWith('/') &&
      !uri.path.startsWith('//');
}

final class _AppRouteShell extends StatelessWidget {
  const _AppRouteShell({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: child);
  }
}

final class _TemplateHomeRoute extends StatelessWidget {
  const _TemplateHomeRoute({required this.appName});

  final String appName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      key: const Key('template-home-route'),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AppAssets.templateLayers.image(
                key: const Key('template-app-symbol'),
                width: AppSpacing.xxxl,
                height: AppSpacing.xxxl,
                color: theme.colorScheme.tertiary,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                appName,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                key: const Key('open-example-detail'),
                onPressed:
                    () => context.go(
                      ExampleRouteContract.detailLocation(1).toString(),
                    ),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open example detail'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _ExampleDetailRoute extends StatelessWidget {
  const _ExampleDetailRoute({required this.itemId});

  final int itemId;

  @override
  Widget build(BuildContext context) {
    return ExampleDetailPage(
      itemId: itemId,
      onBack: () {
        final router = GoRouter.of(context);
        if (router.canPop()) {
          context.pop();
          return;
        }
        // 直接深链或平台恢复可能没有可弹出的历史页，此时回到稳定首页，避免把 Feature
        // 的返回操作变成无响应命令；具体导航仍完全留在 app/ 边界。
        context.go('/');
      },
    );
  }
}

enum _RouteProblemKind { invalidParameter, unknown }

final class _RouteProblemView extends StatelessWidget {
  const _RouteProblemView({required this.kind});

  final _RouteProblemKind kind;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isInvalidParameter = kind == _RouteProblemKind.invalidParameter;

    return SafeArea(
      key: const Key('app-route-problem'),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                ExcludeSemantics(
                  child: Icon(
                    isInvalidParameter
                        ? Icons.link_off_outlined
                        : Icons.search_off_outlined,
                    size: AppSpacing.xxl,
                    color: theme.colorScheme.error,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Semantics(
                  key: Key(
                    isInvalidParameter
                        ? 'invalid-route-parameter'
                        : 'unknown-route',
                  ),
                  liveRegion: true,
                  header: true,
                  child: Text(
                    isInvalidParameter
                        ? 'Invalid example link'
                        : 'Page not found',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  isInvalidParameter
                      ? 'This example item link cannot be opened.'
                      : 'The requested page is unavailable.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: AppSpacing.lg),
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: 48,
                    maxWidth: 320,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => context.go('/'),
                      icon: const Icon(Icons.home_outlined),
                      label: const Text('Return home'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
