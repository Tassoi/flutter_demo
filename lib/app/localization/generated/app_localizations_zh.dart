/// 此文件由 `dart run tool/generate_localizations.dart` 基于 ARB 资源生成。
/// 请勿手工修改；更新 `lib/app/localization/arb/` 后重新运行生成命令。

// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// 中文（`zh`）文案实现。
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get applicationUnavailableTitle => '应用暂不可用';

  @override
  String get applicationStartupFailedMessage => '应用无法启动。';

  @override
  String get applicationStartupFailedSemantics => '应用启动失败';

  @override
  String get unableToRenderContent => '无法显示此内容。';

  @override
  String get languageMenuTooltip => '切换语言';

  @override
  String get languageFollowSystem => '跟随系统';

  @override
  String get languageEnglish => '英语';

  @override
  String get languageChinese => '中文';

  @override
  String get languagePreferenceSaveFailed => '无法保存语言偏好。';

  @override
  String get openProtectedArea => '打开受保护页面';

  @override
  String get authSignInTitle => '登录';

  @override
  String get authIdentifierLabel => '账号';

  @override
  String get authPasswordLabel => '密码';

  @override
  String get authIdentifierRequired => '请输入账号。';

  @override
  String get authPasswordRequired => '请输入密码。';

  @override
  String get authShowPassword => '显示密码';

  @override
  String get authHidePassword => '隐藏密码';

  @override
  String get authSubmitSignIn => '登录';

  @override
  String get authSessionLoading => '正在恢复会话';

  @override
  String get authAccountTitle => '受保护页面';

  @override
  String get authSessionActive => '当前会话有效。';

  @override
  String get authSignOut => '退出登录';

  @override
  String get authFailureUnavailable => '登录服务暂不可用。';

  @override
  String get authFailureRejected => '账号或密码未通过验证。';

  @override
  String get authFailureSessionExpired => '会话已失效，请重新登录。';

  @override
  String get authFailurePersistence => '安全会话存储不可用。';

  @override
  String get authFailureUnexpected => '无法完成登录。';

  @override
  String get openExampleDetail => '打开示例详情';

  @override
  String get invalidExampleLinkTitle => '示例链接无效';

  @override
  String get invalidExampleLinkMessage => '无法打开此示例条目链接。';

  @override
  String get pageNotFoundTitle => '页面不存在';

  @override
  String get pageNotFoundMessage => '请求的页面当前不可用。';

  @override
  String get returnHome => '返回首页';

  @override
  String get exampleDetailLoading => '正在加载示例条目';

  @override
  String get exampleDetailErrorTitle => '无法加载条目';

  @override
  String get tryAgain => '重试';

  @override
  String get exampleItemUnavailableTitle => '条目不可用';

  @override
  String get exampleItemUnavailableMessage => '此链接没有对应的示例条目。';

  @override
  String get backToHome => '返回首页';

  @override
  String get back => '返回';

  @override
  String get exampleDetailTitle => '示例详情';

  @override
  String exampleItemIdentifier({required int itemId}) {
    final intl.NumberFormat itemIdNumberFormat = intl
        .NumberFormat.decimalPattern(localeName);
    final String itemIdString = itemIdNumberFormat.format(itemId);

    return '条目编号：$itemIdString';
  }

  @override
  String exampleItemCount({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个示例条目',
    );
    return '$_temp0';
  }

  @override
  String exampleUpdatedOn({required DateTime date}) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return '更新于 $dateString';
  }

  @override
  String get errorConfigurationInvalid => '应用配置无效。';

  @override
  String get errorConfigurationUnavailable => '应用配置不可用。';

  @override
  String get errorStorageUnavailable => '本地存储不可用。';

  @override
  String get errorStorageRead => '无法读取本地数据。';

  @override
  String get errorStorageWrite => '无法保存本地数据。';

  @override
  String get errorStorageDelete => '无法移除本地数据。';

  @override
  String get errorStorageClear => '无法清理本地数据。';

  @override
  String get errorNetworkConnection => '无法连接服务。';

  @override
  String get errorNetworkTimeout => '请求耗时过长。';

  @override
  String get errorNetworkCancelled => '请求已取消。';

  @override
  String get errorNetworkResponse => '服务无法完成请求。';

  @override
  String get errorNetworkParse => '服务返回了无法识别的响应。';

  @override
  String get errorCredentialsUnavailable => '此请求没有可用凭据。';

  @override
  String get errorUnexpected => '出现了问题。';
}
