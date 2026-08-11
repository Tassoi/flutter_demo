import 'package:flutter/widgets.dart';

/// 用户可选择的应用语言策略。
///
/// `system` 不固定具体 [Locale]，设备语言变化时由 Flutter 的本地化解析流程重新选择。
/// `english` 与 `chinese` 只表示当前真实维护的通用语言资源，不虚构地区变体；新增语言时
/// 必须同步更新 ARB、生成器白名单、解析测试和语言菜单。
enum AppLocalePreference {
  /// 跟随设备语言；不在普通偏好中保留显式 locale 值。
  system,

  /// 固定使用通用英语资源。
  english,

  /// 固定使用通用中文资源。
  chinese,
}

/// [AppLocalePreference] 的稳定存储值和 Flutter locale 映射。
extension AppLocalePreferenceProperties on AppLocalePreference {
  /// 供普通偏好保存的稳定值。
  ///
  /// 该值属于持久化协议，不能直接改为枚举名称；重命名枚举成员时仍应保持既有值可读。
  String get storageValue => switch (this) {
    AppLocalePreference.system => 'system',
    AppLocalePreference.english => 'en',
    AppLocalePreference.chinese => 'zh',
  };

  /// 交给 `MaterialApp.locale` 的显式 locale。
  ///
  /// 跟随系统时返回 `null`，让 Flutter 把设备 locale 列表交给项目解析函数。返回的 locale
  /// 只有语言码，不声称存在尚未维护的地区资源。
  Locale? get explicitLocale => switch (this) {
    AppLocalePreference.system => null,
    AppLocalePreference.english => const Locale('en'),
    AppLocalePreference.chinese => const Locale('zh'),
  };
}

/// 把普通偏好中的稳定值转换为应用语言策略。
///
/// 未知、空白或旧版本遗留值统一安全降级为 [AppLocalePreference.system]，不会让损坏的
/// 可恢复偏好阻止应用启动。调用方若需要诊断读取失败，应在存储边界捕获异常；本函数只处理
/// 已成功读取但不受支持的普通字符串。
AppLocalePreference parseStoredAppLocalePreference(String value) {
  return switch (value) {
    'en' => AppLocalePreference.english,
    'zh' => AppLocalePreference.chinese,
    'system' || _ => AppLocalePreference.system,
  };
}

/// 从请求 locale 列表中选择当前应用实际支持的通用语言。
///
/// [requestedLocales] 按 Flutter 提供的优先级依次匹配语言码，地区和脚本变体会落到同语言的
/// 通用资源。无法匹配、列表为空或为 `null` 时固定回退英语。[supportedLocales] 应传入生成的
/// 支持列表；若调用方误传不含英语的列表，本函数仍返回通用英语，避免回退结果随迭代顺序漂移。
///
/// 本函数不修改 `Intl.defaultLocale`，日期、数字与复数格式始终由生成的本地化实例显式使用
/// 自身 locale，从而避免并行 Widget 树或测试互相污染。
Locale resolveAppLocale(
  List<Locale>? requestedLocales,
  Iterable<Locale> supportedLocales,
) {
  final List<Locale> supported = List<Locale>.unmodifiable(supportedLocales);
  for (final Locale requested in requestedLocales ?? const <Locale>[]) {
    for (final Locale candidate in supported) {
      if (candidate.languageCode == requested.languageCode) {
        return candidate;
      }
    }
  }
  return const Locale('en');
}
