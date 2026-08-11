/// 此文件由 `dart run tool/generate_localizations.dart` 基于 ARB 资源生成。
/// 请勿手工修改；更新 `lib/app/localization/arb/` 后重新运行生成命令。

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// 提供当前 Widget 树的类型安全本地化文案。
///
/// 调用方通过 [AppLocalizations.of] 读取当前语言资源。应用根必须注册
/// [localizationsDelegates] 与 [supportedLocales]；Feature 不应自行创建代理或维护另一份
/// 支持语言列表。人工维护源仅位于 ARB 目录，本文件必须通过仓库生成命令更新。
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// 应用文案代理与 Flutter Material、Cupertino、Widget 默认代理的固定集合。
  ///
  /// 应用若需要新增代理，应在根部显式追加；Feature 不得复制或改写本列表。
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// 当前生成产物明确支持的语言列表。
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// 安全启动失败应用的窗口标题。
  String get applicationUnavailableTitle;

  /// 启动失败时展示给用户的稳定且不含诊断细节的说明。
  String get applicationStartupFailedMessage;

  /// 启动失败状态供辅助技术播报的语义标签。
  String get applicationStartupFailedSemantics;

  /// Flutter Widget 构建失败时替代原始异常详情的安全文案。
  String get unableToRenderContent;

  /// 打开应用语言选择菜单的按钮提示。
  String get languageMenuTooltip;

  /// 语言选择菜单中跟随设备系统语言的选项。
  String get languageFollowSystem;

  /// 语言选择菜单中的英语选项。
  String get languageEnglish;

  /// 语言选择菜单中的中文选项。
  String get languageChinese;

  /// 语言偏好写入普通存储失败时展示的安全反馈。
  String get languagePreferenceSaveFailed;

  /// 首页进入认证模块受保护示例页面的操作。
  String get openProtectedArea;

  /// 认证登录页面标题。
  String get authSignInTitle;

  /// 登录标识符输入框标签，不预设邮箱或手机号协议。
  String get authIdentifierLabel;

  /// 认证密码输入框标签。
  String get authPasswordLabel;

  /// 登录标识符为空时的本地表单校验文案。
  String get authIdentifierRequired;

  /// 登录密码为空时的本地表单校验文案。
  String get authPasswordRequired;

  /// 显示密码内容的图标按钮提示。
  String get authShowPassword;

  /// 隐藏密码内容的图标按钮提示。
  String get authHidePassword;

  /// 提交认证登录表单的主要操作。
  String get authSubmitSignIn;

  /// 受保护路由等待安全会话恢复时的状态说明。
  String get authSessionLoading;

  /// 认证成功后受保护示例页面的标题。
  String get authAccountTitle;

  /// 不包含用户资料或凭据的已认证状态说明。
  String get authSessionActive;

  /// 清除当前认证会话的退出操作。
  String get authSignOut;

  /// 认证服务未配置或网络不可用时的安全失败文案。
  String get authFailureUnavailable;

  /// 合并账号存在性与密码错误原因的登录拒绝文案。
  String get authFailureRejected;

  /// 刷新失败或会话失效后的安全提示。
  String get authFailureSessionExpired;

  /// 安全凭据无法可靠读写或删除时的提示。
  String get authFailurePersistence;

  /// 没有更具体稳定分类的认证失败文案。
  String get authFailureUnexpected;

  /// 首页进入示例详情流程的主要操作。
  String get openExampleDetail;

  /// 示例详情路由参数无效时的安全标题。
  String get invalidExampleLinkTitle;

  /// 示例详情路由参数无效时且不回显 URI 的说明。
  String get invalidExampleLinkMessage;

  /// 未知路由页面的安全标题。
  String get pageNotFoundTitle;

  /// 未知路由页面中不回显请求 URI 的说明。
  String get pageNotFoundMessage;

  /// 从安全路由错误页返回首页的操作。
  String get returnHome;

  /// 示例详情首次加载或重试时的状态说明。
  String get exampleDetailLoading;

  /// 示例详情加载失败时的稳定标题。
  String get exampleDetailErrorTitle;

  /// 可恢复失败状态中的重试操作。
  String get tryAgain;

  /// 示例详情成功返回空数据时的标题。
  String get exampleItemUnavailableTitle;

  /// 示例详情成功返回空数据时的说明。
  String get exampleItemUnavailableMessage;

  /// 从示例空状态返回首页的操作。
  String get backToHome;

  /// 示例详情顶部返回按钮的提示。
  String get back;

  /// 示例详情页面的固定标题。
  String get exampleDetailTitle;

  /// 使用当前 locale 数字格式展示示例条目标识。
  String exampleItemIdentifier({required int itemId});

  /// 按当前 locale 复数规则展示示例条目数量。
  String exampleItemCount({required int count});

  /// 使用当前 locale 的中等日期格式展示示例更新时间。
  String exampleUpdatedOn({required DateTime date});

  /// 配置内容不符合安全约束时的用户兜底文案。
  String get errorConfigurationInvalid;

  /// 配置无法读取时的用户兜底文案。
  String get errorConfigurationUnavailable;

  /// 本地存储无法初始化时的用户兜底文案。
  String get errorStorageUnavailable;

  /// 本地数据读取失败时的用户兜底文案。
  String get errorStorageRead;

  /// 本地数据写入失败时的用户兜底文案。
  String get errorStorageWrite;

  /// 本地数据删除失败时的用户兜底文案。
  String get errorStorageDelete;

  /// 本地数据清理失败时的用户兜底文案。
  String get errorStorageClear;

  /// 网络连接阶段失败时的用户兜底文案。
  String get errorNetworkConnection;

  /// 网络请求超时时的用户兜底文案。
  String get errorNetworkTimeout;

  /// 网络请求被取消时的用户兜底文案。
  String get errorNetworkCancelled;

  /// 服务返回非成功状态时的用户兜底文案。
  String get errorNetworkResponse;

  /// 服务响应无法安全解析时的用户兜底文案。
  String get errorNetworkParse;

  /// 受保护请求缺少可用凭据时的用户兜底文案。
  String get errorCredentialsUnavailable;

  /// 没有更具体稳定错误分类时的用户兜底文案。
  String get errorUnexpected;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // 当前只维护通用语言码；地区变体由应用根解析到对应通用语言。
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
