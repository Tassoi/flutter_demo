/// 应用可以稳定暴露给状态层和 UI 的错误基类。
///
/// [code] 用于程序分支、日志关联和测试断言，[displayMessage] 是不包含底层异常、插件
/// 类型、服务端响应或敏感数据的安全兜底文案。原始异常与堆栈不保存在此模型中，而应只在
/// 基础设施边界交给统一日志系统；这样 UI 即使输出整个 [AppError] 也不会泄漏实现细节。
///
/// 子类型集中定义在本文件中，便于调用方对稳定错误集合做穷尽处理。基础设施 adapter
/// 只在能够证明具体语义的边界创建对应子类型，不能依据异常文本猜测分类。
sealed class AppError implements Exception {
  const AppError({required this.code, required this.displayMessage});

  /// 跨实现保持稳定、适合程序判断的错误代码。
  final String code;

  /// 可以直接交给通用错误 UI 的非敏感兜底文案。
  ///
  /// 该字段保留固定英文作为无本地化上下文时的最后安全兜底。正常 Widget UI 必须通过
  /// [code] 映射当前语言资源，而不是直接展示本字段或把底层异常文本当作文案。
  final String displayMessage;

  @override
  String toString() => '$runtimeType(code: $code)';
}

/// 应用构建或运行配置不可用时的稳定错误。
///
/// 该类型不保存被拒绝的配置值，也不区分具体密钥名称，避免配置内容通过状态对象进入
/// Widget 树、测试快照或日志。调用方可以通过不同构造函数区分格式非法与读取失败。
final class AppConfigurationError extends AppError {
  /// 表示配置存在但格式、环境名或安全约束不合法。
  const AppConfigurationError.invalid()
    : super(
        code: 'configuration.invalid',
        displayMessage: 'The application configuration is invalid.',
      );

  /// 表示配置因未知基础设施失败而无法取得或完成解析。
  const AppConfigurationError.unavailable()
    : super(
        code: 'configuration.unavailable',
        displayMessage: 'The application configuration is unavailable.',
      );
}

/// 存储插件或平台实现无法完成初始化时的稳定错误。
///
/// 该类型不区分普通偏好与安全存储，也不保存平台名称、MethodChannel 异常或本地路径。
/// 组装层可以把它视为依赖初始化失败；如果应用尚未依赖存储，则不应提前创建 adapter。
final class StorageInitializationError extends AppError {
  /// 创建不携带插件初始化详情的错误。
  const StorageInitializationError()
    : super(
        code: 'storage.initialization',
        displayMessage: 'Local storage is unavailable.',
      );
}

/// 普通偏好或安全存储无法读取值时的稳定错误。
///
/// 缺失键不是错误：普通偏好返回调用方提供的默认值，安全存储返回 `null`。只有平台失败、
/// 数据类型不匹配或解密失败才映射到本类型，且错误对象不会保留键名、值或底层异常。
final class StorageReadError extends AppError {
  /// 创建不携带键和值的读取错误。
  const StorageReadError()
    : super(
        code: 'storage.read',
        displayMessage: 'Local data could not be read.',
      );
}

/// 普通偏好或安全存储无法写入值时的稳定错误。
///
/// 本类型不表示写入是否可以安全重试。调用方必须依据上层业务语义决定后续动作，不能从
/// 插件异常文本推测结果；特别是安全凭据写入失败时，不得退回普通偏好存储。
final class StorageWriteError extends AppError {
  /// 创建不携带键、值或插件原因的写入错误。
  const StorageWriteError()
    : super(
        code: 'storage.write',
        displayMessage: 'Local data could not be saved.',
      );
}

/// 删除单个普通偏好或安全值失败时的稳定错误。
///
/// 删除不存在的键应由插件视为空操作；只有平台操作实际失败时才创建本类型。错误不保存
/// 待删除键，避免凭据用途或用户状态进入 UI、状态快照或日志。
final class StorageDeleteError extends AppError {
  /// 创建不携带删除目标的错误。
  const StorageDeleteError()
    : super(
        code: 'storage.delete',
        displayMessage: 'Local data could not be removed.',
      );
}

/// 清理 adapter 所拥有全部值失败时的稳定错误。
///
/// 普通偏好 adapter 只清理自己的命名空间，安全存储 adapter 只清理自己的平台 service
/// 或 namespace。本错误不暴露已删除数量，也不能证明清理操作具有事务性。
final class StorageClearError extends AppError {
  /// 创建不携带清理范围或插件详情的错误。
  const StorageClearError()
    : super(
        code: 'storage.clear',
        displayMessage: 'Local data could not be cleared.',
      );
}

/// DNS、TLS 证书、Socket 或其他连接阶段失败时的稳定错误。
///
/// 本类型不区分主机、IP、证书或底层异常，避免服务地址与平台实现进入上层。网络 adapter
/// 可以把原始失败转换成已脱敏诊断，但 Repository 与 UI 只依据 [code] 决定重试呈现。
final class NetworkConnectionError extends AppError {
  /// 创建不携带连接详情的错误。
  const NetworkConnectionError()
    : super(
        code: 'network.connection',
        displayMessage: 'Unable to connect to the service.',
      );
}

/// 连接、发送、接收或响应转换超过明确上限时的稳定错误。
///
/// 超时不会隐式触发重试，因为服务端可能已经执行有副作用的操作。调用方必须根据具体
/// endpoint 的幂等语义决定是否向用户提供重试。
final class NetworkTimeoutError extends AppError {
  /// 创建不暴露具体网络阶段和内部时长的超时错误。
  const NetworkTimeoutError()
    : super(
        code: 'network.timeout',
        displayMessage: 'The request took too long.',
      );
}

/// 调用方或客户端关闭流程主动取消请求时的稳定错误。
///
/// 取消通常不应作为需要展示的失败，但它仍是明确终止 Future 的结果。状态管理层可以
/// 依据 [code] 忽略离开页面后的结果，而无需导入 Dio 的 CancelToken 或异常类型。
final class NetworkCancelledError extends AppError {
  /// 创建不携带任意取消 reason 的错误。
  const NetworkCancelledError()
    : super(
        code: 'network.cancelled',
        displayMessage: 'The request was cancelled.',
      );
}

/// 服务端返回非 2xx HTTP 状态时的稳定错误。
///
/// [statusCode] 是唯一保留的响应元数据。错误不保存 response header、Cookie、reason
/// phrase 或正文；具体业务错误码应由有明确协议的 Repository 在未来专用边界处理，不能
/// 让通用 UI 读取任意服务端 payload。
final class NetworkResponseError extends AppError {
  const NetworkResponseError._({required this.statusCode})
    : super(
        code: 'network.response',
        displayMessage: 'The service could not complete the request.',
      );

  /// 创建一个携带安全 HTTP 状态码的响应错误。
  ///
  /// [statusCode] 必须在 100 到 599 之间；非法值代表 adapter 契约故障并抛出固定
  /// [ArgumentError]，不会保留响应对象。
  factory NetworkResponseError({required int statusCode}) {
    if (statusCode < 100 || statusCode > 599) {
      throw ArgumentError('Status code must be a valid HTTP status code.');
    }
    return NetworkResponseError._(statusCode: statusCode);
  }

  /// 服务端返回的非成功 HTTP 状态码。
  final int statusCode;
}

/// JSON 转换或请求指定 decoder 无法理解响应形状时的稳定错误。
///
/// 本类型不保存原始正文、字段值或解析异常。网络日志也只记录本类型与 [code]，避免把
/// 服务端返回的个人数据或凭据复制到日志。
final class NetworkResponseParseError extends AppError {
  /// 创建不携带响应内容的解析错误。
  const NetworkResponseParseError()
    : super(
        code: 'network.parse',
        displayMessage: 'The service returned an unexpected response.',
      );
}

/// 受保护请求无法取得或安全发送凭据时的稳定错误。
///
/// `null` 凭据、提供者失败以及试图通过非 HTTPS 连接发送凭据都折叠为同一结果。具体
/// 登录、刷新与会话失效原因属于第二阶段认证模块，不进入第一阶段网络契约。
final class NetworkCredentialsUnavailableError extends AppError {
  /// 创建不区分凭据来源与失败原因的错误。
  const NetworkCredentialsUnavailableError()
    : super(
        code: 'network.credentials_unavailable',
        displayMessage: 'Credentials are unavailable for this request.',
      );
}

/// 没有更具体且经过验证的映射规则时使用的稳定错误。
///
/// 本类型有意不携带原始异常。基础设施应先记录已经脱敏的诊断信息，再把该错误返回给
/// 上层；不得通过新增任意 `details` 字段绕过错误边界。
final class UnexpectedAppError extends AppError {
  /// 创建不暴露底层原因的未知错误。
  const UnexpectedAppError()
    : super(code: 'unexpected', displayMessage: 'Something went wrong.');
}

/// 把边界外异常转换为项目自有 [AppError] 的无状态映射器。
///
/// 映射器只处理配置与没有专用语义的异常，不直接导入网络或存储插件。对应 adapter 应先
/// 在自己的实现文件中把插件异常转换为上方稳定类型，再把无法识别的异常交给
/// [fromUnexpected]；这样第三方类型不会进入本文件或上层调用方。
final class AppErrorMapper {
  /// 创建无缓存、无 I/O 的错误映射器。
  const AppErrorMapper();

  /// 把配置边界捕获的 [error] 转换为稳定配置错误。
  ///
  /// 已经是 [AppError] 的值保持原实例，避免重复映射丢失上游稳定语义。
  /// [FormatException] 对应非法配置；其他异常只表示配置不可用，原始内容不会进入结果。
  AppError fromConfiguration(Object error) {
    if (error is AppError) {
      return error;
    }
    if (error is FormatException) {
      return const AppConfigurationError.invalid();
    }
    return const AppConfigurationError.unavailable();
  }

  /// 把没有已知上下文的 [error] 转换为稳定未知错误。
  ///
  /// 已映射的 [AppError] 原样返回；其他异常统一折叠为 [UnexpectedAppError]。
  AppError fromUnexpected(Object error) {
    if (error is AppError) {
      return error;
    }
    return const UnexpectedAppError();
  }
}
