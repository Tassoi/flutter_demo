import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_template/core/logging/app_log_level.dart';
import 'package:flutter_template/core/logging/app_logger.dart';
import 'package:flutter_template/core/logging/log_redactor.dart';
import 'package:logging/logging.dart' as package_logging;

/// 使用 `package:logging` 分发记录的默认 [AppLogger] adapter。
///
/// 本实现使用 detached logger，不读取或修改 `Logger.root`，因此多个测试和嵌入式 Flutter
/// engine 不会互相覆盖全局级别或监听。第三方 [package_logging.Logger] 与
/// [package_logging.LogRecord] 只存在于本文件，调用方和 sink 始终使用项目自有类型。
///
/// 原始 message、context、异常和堆栈在调用 package logger 前完成脱敏。时钟、脱敏、
/// package logger 或 sink 抛出的异常都会被隔离，并只通过固定无敏感内容的 fallback
/// 文案报告，绝不递归记录原始失败。
final class PackageLoggingAppLogger implements AppLogger {
  /// 创建具有明确级别、隐私策略和生命周期的 logger。
  ///
  /// [category] 必须是稳定的小写点分名称。[includeErrorMessage] 和
  /// [includeStackTrace] 应由显式环境配置决定；生产环境应同时关闭，以避免任意第三方
  /// 异常文本或本机构建路径进入日志。[now] 可替换以保证测试不依赖真实时钟。
  PackageLoggingAppLogger({
    required String category,
    required this.minimumLevel,
    required AppLogSink sink,
    LogRedactor redactor = const LogRedactor(),
    bool includeErrorMessage = true,
    bool includeStackTrace = true,
    DateTime Function()? now,
    void Function(String message)? writeFallback,
  }) : _category = _validateCategory(category),
       _sink = sink,
       _redactor = redactor,
       _includeErrorMessage = includeErrorMessage,
       _includeStackTrace = includeStackTrace,
       _now = now ?? DateTime.now,
       _writeFallback = writeFallback ?? _defaultFallbackWriter {
    _logger = package_logging.Logger.detached(_category)
      ..level = _toPackageLevel(minimumLevel);
    _subscription = _logger.onRecord.listen(_handlePackageRecord);
  }

  static final _categoryPattern = RegExp(
    r'^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*$',
  );
  static final _eventPattern = RegExp(
    r'^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*$',
  );

  final String _category;

  @override
  final AppLogLevel minimumLevel;

  final AppLogSink _sink;
  final LogRedactor _redactor;
  final bool _includeErrorMessage;
  final bool _includeStackTrace;
  final DateTime Function() _now;
  final void Function(String message) _writeFallback;
  late final package_logging.Logger _logger;
  late final StreamSubscription<package_logging.LogRecord> _subscription;
  bool _isClosed = false;

  @override
  void log(
    AppLogLevel level, {
    required String event,
    String message = '',
    Map<String, Object?> context = const {},
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (_isClosed) {
      throw StateError('Cannot write to a closed AppLogger.');
    }
    if (!_eventPattern.hasMatch(event)) {
      throw ArgumentError(
        'Event must be a stable lowercase dot-separated name.',
      );
    }

    final packageLevel = _toPackageLevel(level);
    if (!_logger.isLoggable(packageLevel)) {
      return;
    }

    try {
      final record = AppLogRecord(
        timestamp: _now(),
        level: level,
        category: _category,
        event: event,
        message: _redactor.redactText(message),
        context: _redactor.redactContext(context),
        errorType:
            error == null
                ? null
                : _redactor.redactText(error.runtimeType.toString()),
        errorMessage:
            error != null && _includeErrorMessage
                ? _redactor.redactError(error)
                : null,
        stackTrace:
            stackTrace != null && _includeStackTrace
                ? _redactor.redactStackTrace(stackTrace)
                : null,
      );

      // package:logging 只接收已经脱敏的 AppLogRecord，且不使用其 error/stack 字段，
      // 避免原始对象被第三方 LogRecord 保留或由其他 listener 意外读取。
      _logger.log(packageLevel, record);
    } on Object {
      // 日志是诊断旁路；时钟、脱敏或第三方分发故障都不能改变主业务结果。此处只写固定
      // fallback，不携带尚未证明已脱敏的输入。
      _reportPipelineFailure();
    }
  }

  @override
  Future<void> close() async {
    if (_isClosed) {
      return;
    }
    _isClosed = true;
    await _subscription.cancel();
    _logger.clearListeners();
  }

  void _handlePackageRecord(package_logging.LogRecord packageRecord) {
    final record = packageRecord.object;
    if (record is! AppLogRecord) {
      _reportPipelineFailure();
      return;
    }
    try {
      _sink.write(record);
    } on Object {
      _reportPipelineFailure();
    }
  }

  void _reportPipelineFailure() {
    try {
      _writeFallback('A structured log record could not be written.');
    } on Object {
      // 这是日志系统最后的降级路径。继续传播会让诊断失败中断业务或递归触发启动 reporter。
    }
  }

  static String _validateCategory(String category) {
    if (!_categoryPattern.hasMatch(category)) {
      throw ArgumentError(
        'Category must be a stable lowercase dot-separated name.',
      );
    }
    return category;
  }

  static package_logging.Level _toPackageLevel(AppLogLevel level) {
    return switch (level) {
      AppLogLevel.debug => package_logging.Level.FINE,
      AppLogLevel.info => package_logging.Level.INFO,
      AppLogLevel.warning => package_logging.Level.WARNING,
      AppLogLevel.error => package_logging.Level.SEVERE,
    };
  }

  static void _defaultFallbackWriter(String message) {
    debugPrint(message);
  }
}
