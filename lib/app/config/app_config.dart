import 'package:flutter/services.dart';
import 'package:flutter_template/app/config/app_environment.dart';
import 'package:flutter_template/core/logging/app_log_level.dart';

export 'package:flutter_template/core/logging/app_log_level.dart'
    show AppLogLevel;

const _appEnvironmentKey = 'APP_ENV';
const _apiBaseUrlKey = 'API_BASE_URL';

/// 单次应用构建所选择的不可变、非敏感配置。
///
/// [AppConfig] 只保存适合编译进应用的值：环境标识、API 地址、日志阈值、展示名称和
/// 原生包名后缀。Dart define 可以从构建产物中提取，因此本类型不得保存 API key、
/// 密码、签名数据或长期凭据；运行时凭据属于安全存储边界。
///
/// 应在应用启动阶段只解析一次，并把结果注入消费者。本类型不执行 I/O，也不维护可变
/// 全局状态，因此测试可以调用 [AppConfig.fromValues]，无需修改进程环境或依赖执行顺序。
final class AppConfig {
  const AppConfig._({
    required this.environment,
    required this.apiBaseUri,
    required this.minimumLogLevel,
    required this.appName,
    required this.packageNameSuffix,
  });

  /// 从编译期 Dart define 解析配置。
  ///
  /// `APP_ENV` 必填且只能是 `dev`、`staging` 或 `prod`。`API_BASE_URL` 可选；
  /// 省略时使用所选环境对应的不可路由 `.invalid` 地址。[nativeFlavor] 默认读取 Flutter
  /// `--flavor` 注入的 [appFlavor]；存在时必须与 `APP_ENV` 精确相同，避免原生包标识和
  /// Dart 后端配置属于不同环境。非法输入会在创建任何依赖或网络客户端前抛出
  /// [FormatException]。
  ///
  /// Flutter 单元测试或直接由 Xcode 发起且没有 `--flavor` 的构建可能得到 `null`；此时仍
  /// 严格校验 `APP_ENV`，但无法执行跨边界比对。正式的 Android/iOS 命令必须同时传入
  /// `--flavor` 和对应的 define 文件。本方法没有副作用；启动层会在 Widget 树之外报告
  /// 失败，并且只展示固定的非敏感状态。
  factory AppConfig.fromDartDefines({String? nativeFlavor = appFlavor}) {
    return AppConfig.fromValues(
      environment: const String.fromEnvironment(_appEnvironmentKey),
      apiBaseUrl: const String.fromEnvironment(_apiBaseUrlKey),
      nativeFlavor: nativeFlavor,
    );
  }

  /// 解析显式传入的配置值。
  ///
  /// [environment] 遵循 [AppEnvironment.parse] 定义的严格 `APP_ENV` 契约。
  /// [apiBaseUrl] 为空时选择安全默认值；非空值必须是绝对 HTTP(S) URI，且不能包含
  /// 内嵌凭据、query 或 fragment。生产环境覆盖值必须使用 HTTPS。缺失的末尾 `/` 会
  /// 被统一补齐，避免解析相对端点时意外替换 base path 的最后一段。开发和预发布允许
  /// HTTP 只表示配置模型能够描述该 URI；模板不会放宽 Android Network Security 或 iOS
  /// ATS，移动端默认仍应使用 HTTPS。[nativeFlavor] 非空时必须与 [environment] 精确一致；
  /// 传入 `null` 只适用于不经过原生 flavor 的纯 Dart 测试或工具调用。
  ///
  /// 环境不受支持或 URL 格式错误、不安全时抛出 [FormatException]。异常消息刻意不包含
  /// 原始 URL，防止误嵌入的凭据被复制到日志。
  factory AppConfig.fromValues({
    required String environment,
    String apiBaseUrl = '',
    String? nativeFlavor,
  }) {
    final parsedEnvironment = AppEnvironment.parse(environment);
    _validateNativeFlavor(
      environment: parsedEnvironment,
      nativeFlavor: nativeFlavor,
    );
    final defaults = switch (parsedEnvironment) {
      AppEnvironment.dev => (
        apiBaseUrl: 'https://api.dev.example.invalid/',
        minimumLogLevel: AppLogLevel.debug,
        appName: 'Flutter Template Dev',
        packageNameSuffix: '.dev',
      ),
      AppEnvironment.staging => (
        apiBaseUrl: 'https://api.staging.example.invalid/',
        minimumLogLevel: AppLogLevel.info,
        appName: 'Flutter Template Staging',
        packageNameSuffix: '.staging',
      ),
      AppEnvironment.prod => (
        apiBaseUrl: 'https://api.example.invalid/',
        minimumLogLevel: AppLogLevel.warning,
        appName: 'Flutter Template',
        packageNameSuffix: '',
      ),
    };

    return AppConfig._(
      environment: parsedEnvironment,
      apiBaseUri: _parseApiBaseUri(
        value: apiBaseUrl.isEmpty ? defaults.apiBaseUrl : apiBaseUrl,
        environment: parsedEnvironment,
      ),
      minimumLogLevel: defaults.minimumLogLevel,
      appName: defaults.appName,
      packageNameSuffix: defaults.packageNameSuffix,
    );
  }

  /// 决定本模型其他全部值的环境。
  final AppEnvironment environment;

  /// 组装网络层时使用的已验证 base URI。
  ///
  /// 该 URI 始终使用 HTTP(S) scheme、具有非空 host、不含 user info、query 或
  /// fragment，并且 path 以 `/` 结尾。默认值有意不可路由；真实端点必须在版本控制外
  /// 注入。
  final Uri apiBaseUri;

  /// 供日志适配器使用的项目自有最低严重级别。
  final AppLogLevel minimumLogLevel;

  /// 所选 Dart 与原生环境共同使用的应用展示名称。
  ///
  /// Android flavor 与 iOS build configuration 必须保持相同值；平台配置漂移会由
  /// 平台构建和工程检查阻止。
  final String appName;

  /// Android/iOS 基础包标识应追加的后缀。
  ///
  /// 开发和预发布后缀包含前导点，生产环境为空。Android application ID 与 iOS bundle
  /// identifier 使用同一后缀，本类型只验证约定，不在运行时修改平台工程。
  final String packageNameSuffix;

  static void _validateNativeFlavor({
    required AppEnvironment environment,
    required String? nativeFlavor,
  }) {
    if (nativeFlavor == null) {
      return;
    }

    // Flutter 把 `--flavor` 原样编译进 FLUTTER_APP_FLAVOR。这里不做大小写或空格
    // 归一化，否则配置拼写错误可能静默连接另一个环境的后端。
    if (nativeFlavor != environment.name) {
      throw const FormatException(
        'The native flavor must exactly match APP_ENV.',
      );
    }
  }

  static Uri _parseApiBaseUri({
    required String value,
    required AppEnvironment environment,
  }) {
    final uri = Uri.tryParse(value);
    final hasSupportedScheme =
        uri != null && (uri.scheme == 'http' || uri.scheme == 'https');

    if (uri == null ||
        !uri.isAbsolute ||
        !hasSupportedScheme ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw FormatException(
        'API_BASE_URL for ${environment.name} must be an absolute HTTP(S) '
        'base URI without credentials, query parameters, or a fragment.',
      );
    }

    if (environment == AppEnvironment.prod && uri.scheme != 'https') {
      throw const FormatException('Production API_BASE_URL must use HTTPS.');
    }

    // base path 缺少末尾 `/` 时，Uri.resolve 会把最后一段视为文件。这里统一补齐，
    // 防止 `/v1` + `users` 意外得到 `/users` 而不是 `/v1/users`。
    final normalizedPath = uri.path.endsWith('/') ? uri.path : '${uri.path}/';
    return uri.replace(path: normalizedPath);
  }
}
