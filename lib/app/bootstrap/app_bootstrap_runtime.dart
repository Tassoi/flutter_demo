import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_template/app/bootstrap/startup_error_reporter.dart';

const _safeErrorWidgetMessage = 'Unable to render this content.';

/// 将 Flutter 进程级启动操作与启动编排逻辑隔离。
///
/// [AppBootstrap] 依赖这个项目自有边界，使测试无需修改 Flutter 全局状态或挂载真实
/// 应用即可验证时序和失败行为。实现只负责接入框架，不得读取环境配置或构造应用依赖。
abstract interface class AppBootstrapRuntime {
  /// 在任何插件相关工作开始前初始化 Flutter Binding。
  void ensureBindingInitialized();

  /// 安装把框架和引擎异常转发给 [errorReporter] 的处理器。
  ///
  /// 本方法必须与 [runApplication] 在同一个 guarded Zone 中执行。Flutter 平台调度器
  /// 会记住设置处理器时的 `Zone.current`；如果在其他 Zone 安装，异常链路会跨边界分裂。
  /// 实现还必须阻止 Flutter 的 debug 错误 Widget 直接显示原始框架异常。
  void installUncaughtErrorHandlers(StartupErrorReporter errorReporter);

  /// 把 [application] 挂载为当前进程的 Flutter 根 Widget 树。
  void runApplication(Widget application);
}

/// 基于 Flutter 全局 API 的正式 [AppBootstrapRuntime] 实现。
///
/// 安装后会在应用整个生命周期内替换当前框架、平台和错误 Widget 回调。直接调用本实现
/// 的测试必须恢复原回调，避免全局状态污染其他测试。
final class FlutterAppBootstrapRuntime implements AppBootstrapRuntime {
  /// 创建无状态的 Flutter runtime 适配器。
  const FlutterAppBootstrapRuntime();

  /// 在当前 guarded Zone 中初始化 [WidgetsFlutterBinding]。
  @override
  void ensureBindingInitialized() {
    WidgetsFlutterBinding.ensureInitialized();
  }

  /// 把 Flutter 框架与平台回调异常统一交给同一个 reporter。
  @override
  void installUncaughtErrorHandlers(StartupErrorReporter errorReporter) {
    FlutterError.onError = (details) {
      errorReporter.report(
        error: details.exception,
        stackTrace: details.stack ?? StackTrace.current,
        source: StartupErrorSource.flutterFramework,
      );
    };

    PlatformDispatcher.instance.onError = (error, stackTrace) {
      errorReporter.report(
        error: error,
        stackTrace: stackTrace,
        source: StartupErrorSource.platformDispatcher,
      );

      // 返回 true 表示异常已经到达应用最后的报告边界，避免引擎再次输出非结构化信息。
      return true;
    };

    // Flutter 默认的 debug ErrorWidget 会显示 exception.toString()，可能把配置或
    // 个人数据直接暴露在屏幕上。原始详情已经通过 FlutterError.onError 进入 reporter，
    // 因此替代 Widget 只渲染稳定且不敏感的固定文案。
    ErrorWidget.builder = (_) {
      return ErrorWidget.withDetails(message: _safeErrorWidgetMessage);
    };
  }

  /// 把已经完成组装的 Widget 树交给 Flutter [runApp]。
  @override
  void runApplication(Widget application) {
    runApp(application);
  }
}
