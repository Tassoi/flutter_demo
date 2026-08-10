import 'package:flutter_template/app/bootstrap/startup_error_reporter.dart';
import 'package:flutter_template/core/error/app_error.dart';
import 'package:flutter_template/core/logging/app_log_level.dart';
import 'package:flutter_template/core/logging/app_logger.dart';

/// 把进程级启动异常转换为稳定错误 code 并写入结构化日志。
///
/// reporter 根据 [StartupErrorSource] 选择当前能够证明的映射：只有明确来自配置捕获边界
/// 的错误才转换为配置错误；应用组装中的 [FormatException] 和其他框架、平台、root Zone
/// 异常都保持未知错误。原始异常与堆栈只交给 [AppLogger] 的统一脱敏边界，不进入
/// [AppError] 或 UI。
///
/// 如果 logger 或映射器意外失败，本实现会调用 [fallbackReporter]；最后 fallback 也违反
/// 不抛异常契约时只会吞掉诊断失败，避免在 root Zone 中递归触发自身。
final class LoggingStartupErrorReporter implements StartupErrorReporter {
  /// 创建使用 [logger]、[errorMapper] 与最终 [fallbackReporter] 的 adapter。
  const LoggingStartupErrorReporter({
    required AppLogger logger,
    required StartupErrorReporter fallbackReporter,
    AppErrorMapper errorMapper = const AppErrorMapper(),
  }) : _logger = logger,
       _fallbackReporter = fallbackReporter,
       _errorMapper = errorMapper;

  final AppLogger _logger;
  final StartupErrorReporter _fallbackReporter;
  final AppErrorMapper _errorMapper;

  @override
  void report({
    required Object error,
    required StackTrace stackTrace,
    required StartupErrorSource source,
  }) {
    try {
      final appError =
          source == StartupErrorSource.configuration
              ? _errorMapper.fromConfiguration(error)
              : _errorMapper.fromUnexpected(error);
      _logger.log(
        AppLogLevel.error,
        event: 'startup.unhandled_error',
        message: 'An unhandled application error was captured.',
        context: <String, Object?>{
          'source': source.name,
          'errorCode': appError.code,
        },
        error: error,
        stackTrace: stackTrace,
      );
    } on Object {
      try {
        _fallbackReporter.report(
          error: error,
          stackTrace: stackTrace,
          source: source,
        );
      } on Object {
        // reporter 已位于进程最后异常边界，继续抛出只会递归进入同一个 root Zone handler。
      }
    }
  }
}
