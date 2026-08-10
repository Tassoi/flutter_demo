import 'package:flutter/foundation.dart';
import 'package:flutter_template/core/logging/app_logger.dart';

/// 把已脱敏 [AppLogRecord] 以单行 JSON 写入 Flutter 控制台的默认 sink。
///
/// JSON 结构便于本地检索和未来替换平台 sink；本类不做脱敏，也不接收原始异常。生产调用
/// 必须通过 [AppLogger] 使用，不能把未经清理的数据手工构造成 record 后直接写入。
final class ConsoleLogSink implements AppLogSink {
  /// 创建控制台 sink。
  ///
  /// [writeLine] 允许测试捕获输出；省略时使用 [debugPrint]。writer 抛出的异常由上层
  /// logger adapter 隔离，本类不会自行重试或缓存。
  ConsoleLogSink({void Function(String line)? writeLine})
    : _writeLine = writeLine ?? _writeToFlutterConsole;

  final void Function(String line) _writeLine;

  @override
  void write(AppLogRecord record) {
    _writeLine(record.toString());
  }

  static void _writeToFlutterConsole(String line) {
    debugPrint(line);
  }
}
