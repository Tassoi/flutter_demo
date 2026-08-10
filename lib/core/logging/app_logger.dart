import 'dart:convert';

import 'package:flutter_template/core/logging/app_log_level.dart';

/// 业务与基础设施共同使用的项目日志门面。
///
/// 调用方提供稳定 [event]、固定 [message] 和结构化 [context]；实现必须在数据进入任何
/// sink 前完成脱敏与级别过滤。原始第三方 logger、平台控制台和序列化类型不得通过此接口
/// 暴露给 Feature。
abstract interface class AppLogger {
  /// 当前实例接受的最低日志严重级别。
  AppLogLevel get minimumLevel;

  /// 记录一条结构化日志事件。
  ///
  /// [event] 必须是稳定的小写点分标识，例如 `startup.unhandled_error`，不得拼接用户
  /// 输入、URL 或标识符。[message] 应描述事件本身，动态数据放入 [context]，以便统一
  /// 按字段脱敏。[error] 与 [stackTrace] 只供基础设施边界诊断；实现必须根据环境策略
  /// 决定是否保留，并且不得把原始对象直接传给 sink。
  ///
  /// 低于 [minimumLevel] 的事件不会求值错误文本或遍历 context。实例关闭后调用会抛出
  /// [StateError]，非法 event 会抛出 [ArgumentError]；时钟、脱敏、分发或 sink 自身失败
  /// 只能进入固定 fallback，不得反向中断业务。
  void log(
    AppLogLevel level, {
    required String event,
    String message = '',
    Map<String, Object?> context = const {},
    Object? error,
    StackTrace? stackTrace,
  });

  /// 停止向 sink 分发后续记录并释放内部监听。
  ///
  /// 关闭操作必须幂等。应用进程级 logger 通常与进程同生命周期，不需要主动关闭；短
  /// 生命周期测试或工具必须等待该 Future，避免异步监听泄漏到后续用例。
  Future<void> close();
}

/// 接收已经脱敏、可以安全输出的结构化日志记录。
///
/// sink 只负责持久化或展示，不得重新拼接原始异常。实现可以抛出写入异常，logger adapter
/// 会隔离该失败并执行固定文案 fallback，防止日志故障影响应用主流程。
abstract interface class AppLogSink {
  /// 写入一条已经完成脱敏的 [record]。
  void write(AppLogRecord record);
}

/// 传递给 [AppLogSink] 的不可变、已脱敏日志记录。
///
/// [context] 只允许 logger 的 redactor 产生的 JSON-safe 值。公开构造函数用于测试 sink
/// 和实现其他项目内 adapter；生产调用方应始终通过 [AppLogger.log] 创建记录，不能直接
/// 调用 sink 绕过脱敏与环境阈值。
final class AppLogRecord {
  /// 创建一条供 sink 消费的结构化记录。
  AppLogRecord({
    required DateTime timestamp,
    required this.level,
    required this.category,
    required this.event,
    required this.message,
    required Map<String, Object?> context,
    this.errorType,
    this.errorMessage,
    this.stackTrace,
  }) : timestamp = timestamp.toUtc(),
       context = Map<String, Object?>.unmodifiable(context);

  /// 统一转换为 UTC 的事件时间。
  final DateTime timestamp;

  /// 事件严重级别。
  final AppLogLevel level;

  /// 产生日志的稳定子系统名称，例如 `app` 或 `network`。
  final String category;

  /// 稳定、可聚合且不含动态数据的事件标识。
  final String event;

  /// 已完成自由文本脱敏的固定事件说明。
  final String message;

  /// 已递归脱敏并冻结的结构化上下文。
  final Map<String, Object?> context;

  /// 原始异常的类型名称；不会保存异常对象本身。
  final String? errorType;

  /// 按环境策略保留且已脱敏的异常文本。
  final String? errorMessage;

  /// 按环境策略保留且已脱敏的堆栈文本。
  final String? stackTrace;

  /// 转换为可以交给 JSON sink 的项目自有数据结构。
  Map<String, Object?> toJson() {
    final result = <String, Object?>{
      'timestamp': timestamp.toIso8601String(),
      'level': level.name,
      'category': category,
      'event': event,
      'message': message,
      'context': context,
    };
    if (errorType != null) {
      result['errorType'] = errorType;
    }
    if (errorMessage != null) {
      result['errorMessage'] = errorMessage;
    }
    if (stackTrace != null) {
      result['stackTrace'] = stackTrace;
    }
    return Map<String, Object?>.unmodifiable(result);
  }

  @override
  String toString() => jsonEncode(toJson());
}
