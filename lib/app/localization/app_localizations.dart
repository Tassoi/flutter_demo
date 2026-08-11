import 'package:flutter/widgets.dart';
import 'package:flutter_template/app/localization/generated/app_localizations.dart';
import 'package:flutter_template/core/error/app_error.dart';

export 'package:flutter_template/app/localization/generated/app_localizations.dart'
    show AppLocalizations;

/// 从当前 Widget 树读取类型安全文案的便捷入口。
extension AppLocalizationsBuildContext on BuildContext {
  /// 返回由应用根为当前 locale 加载的 [AppLocalizations]。
  ///
  /// 本 getter 会建立 Flutter 本地化依赖，因此运行时切换语言后调用它的 Widget 会自动重建。
  /// 只能在已经注册生成代理的 `MaterialApp` 子树中使用；启动最末级错误边界应使用可空的
  /// `Localizations.of` 并提供不含诊断数据的固定兜底，不能在代理尚未建立时强行调用。
  AppLocalizations get localizations => AppLocalizations.of(this);
}

/// 把稳定 [AppError.code] 映射为当前 locale 的安全用户文案。
///
/// 映射不会读取 [AppError.displayMessage]、底层异常或服务端正文，避免第一阶段固定英语兜底
/// 绕过国际化边界。未知 code 统一使用通用未知错误；新增稳定错误类型时必须同时补充 ARB 和
/// 本映射测试。日志和程序分支仍应使用 code，不得把本地化文本当作协议值。
String localizeAppError(AppLocalizations localizations, AppError error) {
  return switch (error.code) {
    'configuration.invalid' => localizations.errorConfigurationInvalid,
    'configuration.unavailable' => localizations.errorConfigurationUnavailable,
    'storage.initialization' => localizations.errorStorageUnavailable,
    'storage.read' => localizations.errorStorageRead,
    'storage.write' => localizations.errorStorageWrite,
    'storage.delete' => localizations.errorStorageDelete,
    'storage.clear' => localizations.errorStorageClear,
    'network.connection' => localizations.errorNetworkConnection,
    'network.timeout' => localizations.errorNetworkTimeout,
    'network.cancelled' => localizations.errorNetworkCancelled,
    'network.response' => localizations.errorNetworkResponse,
    'network.parse' => localizations.errorNetworkParse,
    'network.credentials_unavailable' =>
      localizations.errorCredentialsUnavailable,
    _ => localizations.errorUnexpected,
  };
}
