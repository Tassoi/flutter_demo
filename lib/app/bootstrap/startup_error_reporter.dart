import 'package:flutter/foundation.dart';
import 'package:flutter_template/core/error/app_error.dart';

/// 标识捕获未处理启动异常的边界。
///
/// 该分类有意小于后续应用错误模型，因为它在日志和其他依赖可用前就必须工作；它只描述
/// 异常捕获位置，不猜测业务含义。
enum StartupErrorSource {
  /// 读取或校验应用构建配置失败。
  configuration,

  /// 配置成功后的应用组装或首次 `runApp` 调用失败。
  initialization,

  /// Flutter 通过 [FlutterError.onError] 报告异常。
  flutterFramework,

  /// 引擎报告未处理的异步回调异常。
  platformDispatcher,

  /// 异常越过更窄的处理器，最终到达 guarded root Zone。
  rootZone,
}

/// 接收正常应用错误处理建立前或其边界外捕获的异常。
///
/// 实现可以把 [error] 和 [stackTrace] 转发给符合隐私要求的诊断 sink，但自身不得抛出
/// 异常。最后边界再次抛出会阻止启动失败 UI 渲染，或者递归触发 root Zone 处理器。
///
/// 本接口不决定应用能否继续运行。该策略由 [source] 对应的调用方负责：配置或初始化
/// 失败会展示 fallback 应用；启动后的框架异常在报告后仍由 Flutter 管理当前 Widget 树。
abstract interface class StartupErrorReporter {
  /// 报告捕获到的 [error]、原始 [stackTrace] 和 [source]。
  ///
  /// 实现把诊断详情写入外部 sink 前必须自行脱敏。本方法同步执行，使平台处理器只在报告
  /// 完成后才确定地把异常标记为已处理。
  void report({
    required Object error,
    required StackTrace stackTrace,
    required StartupErrorSource source,
  });
}

/// 在启动依赖可用前后切换报告实现的一次性代理。
///
/// Flutter 全局异常处理器必须在读取配置前安装，但结构化 logger 的最低级别来自配置。
/// 本代理先把异常交给 [fallbackReporter]；应用组装创建 logger 后调用 [bind]，后续异常
/// 将由同一个全局 handler 对象转发到结构化实现。代理不缓存原始异常，避免敏感数据在
/// 内存中等待重放，也避免配置失败时依赖尚未初始化的日志系统。
///
/// 每个应用进程只能绑定一次。Dart isolate 内的同步字段替换不会出现中间状态；调用方仍
/// 必须在开始创建其他异步依赖前完成绑定，确保这些依赖的失败具有一致报告策略。
final class DeferredStartupErrorReporter implements StartupErrorReporter {
  /// 创建初始使用 [fallbackReporter] 的 reporter 代理。
  DeferredStartupErrorReporter({required StartupErrorReporter fallbackReporter})
    : _activeReporter = fallbackReporter;

  StartupErrorReporter _activeReporter;
  bool _isBound = false;

  /// 一次性绑定依赖初始化完成后的结构化 [reporter]。
  ///
  /// 重复调用会抛出 [StateError]，防止后续模块静默替换进程级诊断策略。该方法不会重放
  /// bind 之前的异常；它们已经由安全 fallback 处理。
  void bind(StartupErrorReporter reporter) {
    if (_isBound) {
      throw StateError('Startup error reporter has already been bound.');
    }
    _activeReporter = reporter;
    _isBound = true;
  }

  @override
  void report({
    required Object error,
    required StackTrace stackTrace,
    required StartupErrorSource source,
  }) {
    _activeReporter.report(
      error: error,
      stackTrace: stackTrace,
      source: source,
    );
  }
}

/// 结构化日志层可用前使用的隐私安全 reporter。
///
/// 此 fallback 有意只输出捕获边界和项目自有稳定错误 code，不格式化 [Object.toString]
/// 或堆栈，因为二者都可能包含凭据、个人数据或内部地址。后续日志适配器可以用结构化
/// 脱敏实现 [StartupErrorReporter]；在该适配器初始化前发生失败时，本实现仍可使用。
final class SafeStartupErrorReporter implements StartupErrorReporter {
  /// 创建只写入固定、非敏感诊断文案与稳定错误 code 的 reporter。
  ///
  /// [writeMessage] 可注入以支持确定性测试；writer 抛错会在最后诊断边界被隔离。
  /// 省略时使用 Flutter 控制台输出，但不会包含原始异常内容。[errorMapper] 是无 I/O 的
  /// 项目映射器，配置 logger 前也可安全使用。
  SafeStartupErrorReporter({
    void Function(String message)? writeMessage,
    AppErrorMapper errorMapper = const AppErrorMapper(),
  }) : _writeMessage = writeMessage ?? _writeToFlutterConsole,
       _errorMapper = errorMapper;

  final void Function(String message) _writeMessage;
  final AppErrorMapper _errorMapper;

  @override
  void report({
    required Object error,
    required StackTrace stackTrace,
    required StartupErrorSource source,
  }) {
    final boundary = switch (source) {
      StartupErrorSource.configuration => 'configuration',
      StartupErrorSource.initialization => 'initialization',
      StartupErrorSource.flutterFramework => 'Flutter framework',
      StartupErrorSource.platformDispatcher => 'platform dispatcher',
      StartupErrorSource.rootZone => 'root zone',
    };
    final appError =
        source == StartupErrorSource.configuration
            ? _errorMapper.fromConfiguration(error)
            : _errorMapper.fromUnexpected(error);

    // 这里有意不拼接原始异常和堆栈，确保配置或日志初始化失败时 reporter 仍不会泄密。
    try {
      _writeMessage(
        'Application error captured at the $boundary boundary '
        '(code: ${appError.code}).',
      );
    } on Object {
      // Safe reporter 可能正由 guarded root Zone 调用。最后 writer 再抛异常会越过该
      // Zone 的错误处理器，甚至递归触发同一 reporter，因此只能在此隔离诊断失败。
    }
  }

  static void _writeToFlutterConsole(String message) {
    debugPrint(message);
  }
}
