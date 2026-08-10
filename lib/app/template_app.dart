import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_template/app/config/app_config.dart';
import 'package:flutter_template/app/router/app_route_redirect_policy.dart';
import 'package:flutter_template/app/router/app_router.dart';
import 'package:flutter_template/app/state/app_state_scope.dart';
import 'package:flutter_template/app/state/app_theme_mode_controller.dart';
import 'package:flutter_template/app/theme/app_theme.dart';

/// 配置校验成功后的应用根 Widget。
///
/// [TemplateApp] 通过构造函数接收已验证的构建配置，不读取 Dart define 或进程全局单例。
/// 它创建并持有唯一 [AppRouter]，在根 Widget 销毁时同步释放路由监听；启动层仍是配置
/// 解析的唯一入口，Feature 不接触全局 Router。
///
/// 本 Widget 必须位于 [AppStateScope] 下方。主题模式来自唯一的
/// [appThemeModeProvider]；路由生命周期与主题重建相互独立，因此切换主题不会重置当前位置。
final class TemplateApp extends ConsumerStatefulWidget {
  /// 为 [config] 选择的环境创建应用壳层。
  ///
  /// 亮暗主题由 [AppTheme] 提供，当前模式由应用状态作用域管理。本构造函数不读取环境、
  /// 存储或插件，也不创建额外的 Provider 容器。
  const TemplateApp({
    required this.config,
    this.redirectPolicy = const AllowAllAppRouteRedirectPolicy(),
    super.key,
  });

  /// 启动阶段解析并验证的非敏感配置。
  final AppConfig config;

  /// 每次导航前使用的应用级重定向策略。
  ///
  /// 默认策略不重定向，也不表示任何认证状态。调用方仍拥有策略生命周期；本 Widget 只
  /// 释放自己创建的 [AppRouter]，不会处置策略或其依赖。
  final AppRouteRedirectPolicy redirectPolicy;

  @override
  ConsumerState<TemplateApp> createState() => _TemplateAppState();
}

final class _TemplateAppState extends ConsumerState<TemplateApp> {
  late AppRouter _router;

  @override
  void initState() {
    super.initState();
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
      redirectPolicy: widget.redirectPolicy,
    );
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(appThemeModeProvider);

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: widget.config.appName,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      routerConfig: _router.routerConfig,
    );
  }
}
