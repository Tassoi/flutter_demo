import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_template/app/config/app_config.dart';
import 'package:flutter_template/app/localization/app_locale.dart';
import 'package:flutter_template/app/localization/app_localizations.dart';
import 'package:flutter_template/app/router/app_route_redirect_policy.dart';
import 'package:flutter_template/app/router/app_router.dart';
import 'package:flutter_template/app/router/auth_app_route_redirect_policy.dart';
import 'package:flutter_template/app/state/app_locale_controller.dart';
import 'package:flutter_template/app/state/app_state_scope.dart';
import 'package:flutter_template/app/state/app_theme_mode_controller.dart';
import 'package:flutter_template/app/theme/app_theme.dart';
import 'package:flutter_template/features/auth/domain/auth_session_state.dart';
import 'package:flutter_template/features/auth/presentation/auth_session_controller.dart';
import 'package:flutter_template/shared/layout/app_screen_adaptation.dart';

/// 配置校验成功后的应用根 Widget。
///
/// [TemplateApp] 通过构造函数接收已验证的构建配置，不读取 Dart define 或进程全局单例。
/// 它创建并持有唯一 [AppRouter]，在根 Widget 销毁时同步释放路由监听；启动层仍是配置
/// 解析的唯一入口，Feature 不接触全局 Router。
///
/// 本 Widget 必须位于 [AppStateScope] 下方。主题模式来自唯一的
/// [appThemeModeProvider]，语言策略来自 [appLocalePreferenceProvider]；路由生命周期与这两种
/// 根状态重建相互独立，因此切换主题或语言不会重置当前位置。
/// [AppScreenAdaptation] 会先建立参考设计单位，再延迟创建 [MaterialApp] 及其主题，保证主题和
/// 页面后续可以从同一个根作用域读取尺寸比例。启动失败页位于本 Widget 之外，不依赖该适配层，
/// 因而配置或依赖组装失败时仍可独立呈现安全回退界面。
final class TemplateApp extends ConsumerStatefulWidget {
  /// 为 [config] 选择的环境创建应用壳层。
  ///
  /// 亮暗主题由 [AppTheme] 提供，当前模式由应用状态作用域管理。本构造函数不读取环境、
  /// 存储或插件，也不创建额外的 Provider 容器。
  const TemplateApp({required this.config, this.redirectPolicy, super.key});

  /// 启动阶段解析并验证的非敏感配置。
  final AppConfig config;

  /// 每次导航前使用的应用级重定向策略。
  ///
  /// 省略时使用读取唯一 [authSessionProvider] 的认证策略；测试或下游项目可以注入其他同步
  /// 策略。调用方仍拥有自定义策略生命周期；本 Widget 只释放自己创建的 [AppRouter]，
  /// 不会处置策略或其依赖。
  final AppRouteRedirectPolicy? redirectPolicy;

  @override
  ConsumerState<TemplateApp> createState() => _TemplateAppState();
}

final class _TemplateAppState extends ConsumerState<TemplateApp> {
  late final _AppRouterRefreshNotifier _routerRefreshNotifier;
  late final ProviderSubscription<AuthSessionState> _authSubscription;
  late AppRouter _router;

  @override
  void initState() {
    super.initState();
    _routerRefreshNotifier = _AppRouterRefreshNotifier();
    _authSubscription = ref.listenManual<AuthSessionState>(
      authSessionProvider,
      (_, _) => _routerRefreshNotifier.notifyAuthSessionChanged(),
    );
    _router = _createRouter();
  }

  @override
  void didUpdateWidget(TemplateApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config.appName == widget.config.appName &&
        identical(oldWidget.redirectPolicy, widget.redirectPolicy)) {
      return;
    }

    // 应用名称被页面 builder 捕获，重定向策略也在 Router 创建时绑定。先成功创建替代
    // 实例再释放旧 Router，避免构造失败把当前导航树提前置为不可用。
    final previousRouter = _router;
    _router = _createRouter();
    previousRouter.dispose();
  }

  AppRouter _createRouter() {
    return AppRouter(
      appName: widget.config.appName,
      redirectPolicy:
          widget.redirectPolicy ??
          AuthAppRouteRedirectPolicy(
            sessionStateReader: () => ref.read(authSessionProvider),
          ),
      refreshListenable: _routerRefreshNotifier,
    );
  }

  @override
  void dispose() {
    _authSubscription.close();
    _router.dispose();
    _routerRefreshNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(appThemeModeProvider);
    final localePreference = ref.watch(appLocalePreferenceProvider);

    return AppScreenAdaptation(
      builder:
          (adaptedContext) => MaterialApp.router(
            debugShowCheckedModeBanner: false,
            title: widget.config.appName,
            theme: AppTheme.light(adaptedContext),
            darkTheme: AppTheme.dark(adaptedContext),
            themeMode: themeMode,
            locale: localePreference.explicitLocale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            localeListResolutionCallback: resolveAppLocale,
            routerConfig: _router.routerConfig,
          ),
    );
  }
}

/// 只把 Riverpod 会话变化转换为 go_router 刷新通知的私有桥接。
///
/// 本对象不保存认证快照，也不决定重定向；策略每次收到通知后仍从唯一 Provider 读取当前
/// 状态。这样 Router 可以使用 Flutter [Listenable]，同时不会产生第二个会话状态所有者。
final class _AppRouterRefreshNotifier extends ChangeNotifier {
  /// 通知 Router 重新执行同步策略。
  void notifyAuthSessionChanged() => notifyListeners();
}
