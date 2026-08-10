import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 当前应用主题模式及其唯一修改入口。
///
/// provider 位于 `app/`，因为主题模式影响整个 Widget 树而不是某个 Feature。默认值跟随
/// 系统；[AppThemeModeController] 只管理内存状态，不读取或写入存储。未来接入普通偏好时，
/// 应由应用组装层提供已验证初值并显式持有持久化失败策略，不能让 Controller 直接依赖
/// shared_preferences 插件。
final appThemeModeProvider =
    NotifierProvider<AppThemeModeController, ThemeMode>(
      AppThemeModeController.new,
      name: 'appThemeMode',
    );

/// 管理应用级 [ThemeMode] 的同步状态单元。
///
/// 生命周期由根 [ProviderScope] 持有，根作用域销毁后状态随容器释放；重新创建应用作用域会
/// 回到 [ThemeMode.system]。本类型不负责主题对象组装、偏好持久化、平台亮度监听或页面导航。
final class AppThemeModeController extends Notifier<ThemeMode> {
  /// 创建由根 ProviderScope 持有的主题模式 Controller。
  ///
  /// 调用方不应直接构造或缓存本实例；[appThemeModeProvider] 负责创建并随根状态作用域释放。
  AppThemeModeController();

  /// 返回无 I/O、无缓存的安全默认主题模式。
  @override
  ThemeMode build() => ThemeMode.system;

  /// 把应用主题切换为 [themeMode]。
  ///
  /// 更新同步通知所有监听者且没有存储或平台副作用。重复设置当前值会被忽略，避免根
  /// `MaterialApp` 因无状态变化产生无意义重建。
  void setThemeMode(ThemeMode themeMode) {
    if (state == themeMode) {
      return;
    }
    state = themeMode;
  }
}
