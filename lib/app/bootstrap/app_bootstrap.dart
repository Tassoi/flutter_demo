import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_template/app/bootstrap/app_bootstrap_runtime.dart';
import 'package:flutter_template/app/bootstrap/logging_startup_error_reporter.dart';
import 'package:flutter_template/app/bootstrap/startup_error_reporter.dart';
import 'package:flutter_template/app/bootstrap/startup_failure_app.dart';
import 'package:flutter_template/app/config/app_config.dart';
import 'package:flutter_template/app/config/app_environment.dart';
import 'package:flutter_template/app/localization/app_locale.dart';
import 'package:flutter_template/app/localization/app_locale_persistence.dart';
import 'package:flutter_template/app/state/app_locale_controller.dart';
import 'package:flutter_template/app/state/app_state_scope.dart';
import 'package:flutter_template/app/template_app.dart';
import 'package:flutter_template/core/logging/console_log_sink.dart';
import 'package:flutter_template/core/logging/package_logging_app_logger.dart';
import 'package:flutter_template/core/storage/flutter_secure_value_store.dart';
import 'package:flutter_template/core/storage/shared_preferences_preference_store.dart';
import 'package:flutter_template/features/auth/data/auth_credential_persistence.dart';
import 'package:flutter_template/features/auth/data/secure_auth_credential_persistence.dart';
import 'package:flutter_template/features/auth/data/unconfigured_auth_gateway.dart';
import 'package:flutter_template/features/auth/presentation/auth_session_controller.dart';
import 'package:flutter_template/features/example/data/bundled_example_repository.dart';
import 'package:flutter_template/features/example/presentation/example_detail_controller.dart';

/// 在最终未捕获异常边界内启动正式应用流程。
///
/// guarded Zone 在 Flutter Binding 初始化前建立，并持续覆盖启动过程中注册的回调。
/// 因此同步异常、未等待 Future 的异步异常、Flutter 框架异常和平台调度异常都会交给
/// 同一个 [StartupErrorReporter]。
///
/// 本函数安排异步初始化后立即返回；最终调用 [runApp] 后，进程生命周期由 Flutter
/// 管理。
void bootstrapApplication() {
  final safeReporter = SafeStartupErrorReporter();
  final errorReporter = DeferredStartupErrorReporter(
    fallbackReporter: safeReporter,
  );

  runBootstrapInGuardedZone(
    bootstrap: () async {
      await AppBootstrap.production(
        errorReporter: errorReporter,
        assembleApplication:
            (config) async => _assembleProductionApplication(
              config: config,
              startupReporter: errorReporter,
              fallbackReporter: safeReporter,
            ),
      ).run();
    },
    errorReporter: errorReporter,
  );
}

/// 在能够观察最终未捕获异常的 Zone 中执行 [bootstrap]。
///
/// [bootstrap] 通过参数注入，使测试无需启动真实应用即可触发同步和异步失败。原生入口
/// 不等待它返回的 Future，但该 Future 及其派生异步任务仍属于此 Zone，未处理异常会转发
/// 给 [errorReporter]。
///
/// [errorReporter] 不得抛出异常。这是进程级最后一道边界；如果 reporter 自身失败，
/// 在这里再次捕获会产生递归错误处理风险。
void runBootstrapInGuardedZone({
  required Future<void> Function() bootstrap,
  required StartupErrorReporter errorReporter,
}) {
  runZonedGuarded<void>(
    () {
      unawaited(bootstrap());
    },
    (error, stackTrace) {
      errorReporter.report(
        error: error,
        stackTrace: stackTrace,
        source: StartupErrorSource.rootZone,
      );
    },
  );
}

/// 按确定顺序编排 Flutter 应用初始化。
///
/// 初始化顺序固定为：
///
/// 1. 初始化 Flutter Binding；
/// 2. 安装框架和平台异常处理器；
/// 3. 读取并校验构建配置；
/// 4. 异步组装应用及其依赖；
/// 5. 把完整 Widget 树交给 `runApp`。
///
/// 配置解析、应用组装和首次 `runApp` 使用同一安全呈现策略，但配置具有独立错误来源，
/// 避免把后续解析类异常误判成配置失败。每个边界都会在 UI 之外报告原始异常，再挂载
/// 不依赖任何初始化结果的 fallback。Binding 或异常处理器安装失败时无法可靠渲染
/// Flutter UI，因此异常会继续交给外层 guarded Zone。
///
/// 本类是职责聚焦的 composition root，不是 service locator。调用方通过显式构造参数
/// 接收依赖，不能从 [AppBootstrap] 动态查找服务。
final class AppBootstrap {
  /// 创建各副作用边界均可替换的启动编排器。
  ///
  /// [runtime] 管理 Flutter 全局 API，[loadConfig] 只做纯配置解析，
  /// [assembleApplication] 完成依赖初始化后返回根 Widget。
  /// [buildFailureApplication] 不得依赖配置或只初始化了一部分的服务；
  /// [errorReporter] 必须同步执行且不得抛出异常。
  const AppBootstrap({
    required AppBootstrapRuntime runtime,
    required StartupErrorReporter errorReporter,
    required AppConfig Function() loadConfig,
    required Future<Widget> Function(AppConfig config) assembleApplication,
    required Widget Function() buildFailureApplication,
  }) : _runtime = runtime,
       _errorReporter = errorReporter,
       _loadConfig = loadConfig,
       _assembleApplication = assembleApplication,
       _buildFailureApplication = buildFailureApplication;

  /// 创建供平台入口使用的正式启动编排器。
  ///
  /// 传入的 [errorReporter] 同时供 guarded root Zone 使用，确保异常无论由哪层启动边界
  /// 捕获，都执行相同的报告策略。[assembleApplication] 在配置校验后创建 logger 和其他
  /// 应用依赖，并且必须等全部异步初始化完成后才返回根 Widget。
  factory AppBootstrap.production({
    required StartupErrorReporter errorReporter,
    required Future<Widget> Function(AppConfig config) assembleApplication,
  }) {
    return AppBootstrap(
      runtime: const FlutterAppBootstrapRuntime(),
      errorReporter: errorReporter,
      loadConfig: AppConfig.fromDartDefines,
      assembleApplication: assembleApplication,
      buildFailureApplication: StartupFailureApp.new,
    );
  }

  final AppBootstrapRuntime _runtime;
  final StartupErrorReporter _errorReporter;
  final AppConfig Function() _loadConfig;
  final Future<Widget> Function(AppConfig config) _assembleApplication;
  final Widget Function() _buildFailureApplication;

  /// 按文档顺序执行一次完整启动。
  ///
  /// 正常应用或启动 fallback 交给 Flutter 后，返回的 Future 才完成。每个进程只能调用
  /// 一次；重复调用会覆盖全局处理器并挂载多个根 Widget。组装过程中已取得资源的回收由
  /// `assembleApplication` 的具体实现负责。
  Future<void> run() async {
    _runtime.ensureBindingInitialized();
    _runtime.installUncaughtErrorHandlers(_errorReporter);

    late final AppConfig config;
    try {
      config = _loadConfig();
    } on Object catch (error, stackTrace) {
      _reportFailureAndRunFallback(
        error: error,
        stackTrace: stackTrace,
        source: StartupErrorSource.configuration,
      );
      return;
    }

    try {
      final application = await _assembleApplication(config);
      _runtime.runApplication(application);
    } on Object catch (error, stackTrace) {
      _reportFailureAndRunFallback(
        error: error,
        stackTrace: stackTrace,
        source: StartupErrorSource.initialization,
      );
    }
  }

  /// 报告一个已经精确分类的启动失败，并挂载不接收诊断数据的 fallback。
  void _reportFailureAndRunFallback({
    required Object error,
    required StackTrace stackTrace,
    required StartupErrorSource source,
  }) {
    _errorReporter.report(error: error, stackTrace: stackTrace, source: source);

    // fallback 只在失败后创建，而且不接收异常对象，从类型边界上阻止诊断内容进入 UI。
    _runtime.runApplication(_buildFailureApplication());
  }
}

Future<Widget> _assembleProductionApplication({
  required AppConfig config,
  required DeferredStartupErrorReporter startupReporter,
  required StartupErrorReporter fallbackReporter,
}) async {
  final retainsDiagnosticDetails = config.environment != AppEnvironment.prod;
  final logger = PackageLoggingAppLogger(
    category: 'app',
    minimumLevel: config.minimumLogLevel,
    sink: ConsoleLogSink(),
    includeErrorMessage: retainsDiagnosticDetails,
    includeStackTrace: retainsDiagnosticDetails,
  );

  // 全局 handler 已在读取配置前持有 DeferredStartupErrorReporter。先绑定 logger，
  // 再初始化其他依赖，确保后续任一失败都经过环境阈值和统一脱敏；配置读取失败仍使用
  // 不依赖任何配置的 SafeStartupErrorReporter。
  startupReporter.bind(
    LoggingStartupErrorReporter(
      logger: logger,
      fallbackReporter: fallbackReporter,
    ),
  );

  AppLocalePreference initialLocalePreference = AppLocalePreference.system;
  AppLocalePreferencePersistence? localePreferencePersistence;
  try {
    localePreferencePersistence = PreferenceStoreAppLocalePersistence(
      SharedPreferencesPreferenceStore(),
    );
    try {
      initialLocalePreference = await localePreferencePersistence.load();
    } on Object catch (error, stackTrace) {
      // 语言偏好是可恢复的普通设置，读取失败不能阻止应用启动。保留已经创建的写入边界，
      // 让用户之后的显式选择有机会修复平台值；日志只使用固定事件和脱敏错误通道。
      logger.log(
        AppLogLevel.warning,
        event: 'startup.locale_preference_unavailable',
        message: 'Locale preference is unavailable; following system locale.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  } on Object catch (error, stackTrace) {
    // adapter 同步构造失败时没有可恢复的存储实例。应用仍按系统语言运行，并注入明确失败
    // 的写入边界；后续选择会回滚并提示，不能把只在内存生效的结果伪装为已经持久化。
    logger.log(
      AppLogLevel.warning,
      event: 'startup.locale_storage_unavailable',
      message: 'Locale storage is unavailable; following system locale.',
      error: error,
      stackTrace: stackTrace,
    );
    localePreferencePersistence =
        const UnavailableAppLocalePreferencePersistence();
  }

  AuthCredentialPersistence authCredentialPersistence;
  try {
    authCredentialPersistence = SecureAuthCredentialPersistence(
      FlutterSecureValueStore(),
    );
  } on Object catch (error, stackTrace) {
    // 认证是可裁剪增强能力，安全存储同步构造失败不能阻止公开首页启动。使用明确未配置边界
    // 让恢复按无会话处理、任何登录保存都失败关闭；绝不降级到普通偏好或仅内存凭据。
    logger.log(
      AppLogLevel.warning,
      event: 'startup.auth_storage_unavailable',
      message: 'Authentication secure storage is unavailable.',
      error: error,
      stackTrace: stackTrace,
    );
    authCredentialPersistence = const UnconfiguredAuthCredentialPersistence();
  }
  logger.log(
    AppLogLevel.info,
    event: 'startup.dependencies_ready',
    message: 'Application dependencies are ready.',
    context: <String, Object?>{
      'environment': config.environment.name,
      'minimumLogLevel': config.minimumLogLevel.name,
    },
  );

  // 默认示例 Repository 完全离线，确保占位 .invalid 配置不会触发真实请求。项目接入
  // 服务端时只在此组装边界替换为 NetworkExampleRepository，并由拥有者关闭 NetworkClient；
  // Feature 的 domain/presentation 不接触 Dio 或客户端生命周期。
  final exampleRepository = BundledExampleRepository();

  // Provider 容器只在配置、异常边界和可恢复偏好读取完成后创建；根 Widget 销毁时由
  // AppStateScope 统一释放状态，不能使用进程级全局容器绕过 Widget 生命周期。
  return AppStateScope(
    overrides: [
      exampleRepositoryProvider.overrideWithValue(exampleRepository),
      appInitialLocalePreferenceProvider.overrideWithValue(
        initialLocalePreference,
      ),
      appLocalePreferencePersistenceProvider.overrideWithValue(
        localePreferencePersistence,
      ),
      authGatewayProvider.overrideWithValue(const UnconfiguredAuthGateway()),
      authCredentialPersistenceProvider.overrideWithValue(
        authCredentialPersistence,
      ),
      authLoggerProvider.overrideWithValue(logger),
    ],
    child: TemplateApp(config: config),
  );
}
