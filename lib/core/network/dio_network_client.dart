import 'package:dio/dio.dart';
import 'package:flutter_template/core/error/app_error.dart';
import 'package:flutter_template/core/logging/app_log_level.dart';
import 'package:flutter_template/core/logging/app_logger.dart';
import 'package:flutter_template/core/network/network_cancellation_token.dart';
import 'package:flutter_template/core/network/network_client.dart';
import 'package:flutter_template/core/network/network_credential_provider.dart';
import 'package:flutter_template/core/network/network_request.dart';
import 'package:flutter_template/core/network/network_response.dart';
import 'package:flutter_template/core/network/network_timeouts.dart';

const _operationExtraKey = 'flutter_template.network.operation';
const _requiresCredentialExtraKey =
    'flutter_template.network.requires_credential';

/// 使用 Dio 5 实现的默认 [NetworkClient] adapter。
///
/// 本类是唯一允许出现 Dio、Response、DioException、CancelToken 与 Interceptor 的生产
/// 边界。Feature 和 Repository 必须依赖 [NetworkClient]，不能导入本文件或
/// `package:dio`。adapter 使用已验证 Base URL、确定超时、默认 JSON Accept header、
/// 禁止自动重定向，并在返回前把全部插件对象转换为项目类型。
///
/// 每次请求都会创建独立 Dio CancelToken，并在 `finally` 中从项目取消令牌注销。调用
/// [close] 会先取消活跃请求，再强制释放底层连接；凭据只存在于单次 Dio RequestOptions，
/// 不会缓存到本类、响应对象或日志中。
final class DioNetworkClient implements NetworkClient {
  /// 创建使用当前平台正式 Dio transport 的客户端。
  ///
  /// [baseUri] 必须是无 user info、query、fragment 和路径穿越的绝对 HTTP(S) URI；缺少
  /// 末尾 `/` 时会被规范化。[commonHeaders] 只允许非敏感 header，`accept` 默认值为
  /// `application/json`，同名调用方值可以覆盖它。所有 header 会深拷贝且统一为小写。
  ///
  /// [credentialProvider] 默认不提供凭据。只有 `requiresCredential` 的请求会读取它，且
  /// 凭据只允许通过 HTTPS 发送。构造失败抛出的 [ArgumentError] 不回显 URI 或 header
  /// 内容。
  DioNetworkClient({
    required Uri baseUri,
    required AppLogger logger,
    NetworkTimeouts timeouts = NetworkTimeouts.defaults,
    Map<String, String> commonHeaders = const {},
    NetworkCredentialProvider credentialProvider =
        const NoNetworkCredentialProvider(),
  }) : this._(
         baseUri: baseUri,
         logger: logger,
         timeouts: timeouts,
         commonHeaders: commonHeaders,
         credentialProvider: credentialProvider,
       );

  /// 创建注入自定义 Dio [HttpClientAdapter] 的客户端。
  ///
  /// 该构造函数只属于 `core/network` adapter 测试边界，用于在不打开 Socket、不访问真实
  /// 服务的情况下验证完整 Dio pipeline。应用组装与 Feature 不得调用它；第三方类型只在
  /// 本实现文件和对应测试中出现。
  DioNetworkClient.withHttpClientAdapter({
    required Uri baseUri,
    required AppLogger logger,
    required HttpClientAdapter httpClientAdapter,
    NetworkTimeouts timeouts = NetworkTimeouts.defaults,
    Map<String, String> commonHeaders = const {},
    NetworkCredentialProvider credentialProvider =
        const NoNetworkCredentialProvider(),
  }) : this._(
         baseUri: baseUri,
         logger: logger,
         timeouts: timeouts,
         commonHeaders: commonHeaders,
         credentialProvider: credentialProvider,
         httpClientAdapter: httpClientAdapter,
       );

  DioNetworkClient._({
    required Uri baseUri,
    required AppLogger logger,
    required NetworkTimeouts timeouts,
    required Map<String, String> commonHeaders,
    required NetworkCredentialProvider credentialProvider,
    HttpClientAdapter? httpClientAdapter,
  }) {
    final normalizedBaseUri = _normalizeBaseUri(baseUri);
    final validatedCommonHeaders = _validateCommonHeaders(commonHeaders);
    final dio = Dio(
      BaseOptions(
        baseUrl: normalizedBaseUri.toString(),
        connectTimeout: timeouts.connect,
        sendTimeout: timeouts.send,
        receiveTimeout: timeouts.receive,
        transformTimeout: timeouts.transform,
        headers: <String, Object?>{
          Headers.acceptHeader: Headers.jsonContentType,
          ...validatedCommonHeaders,
        },
        responseType: ResponseType.json,
        receiveDataWhenStatusError: false,
        followRedirects: false,
      ),
    );
    if (httpClientAdapter != null) {
      dio.httpClientAdapter = httpClientAdapter;
    }

    final loggingInterceptor = _NetworkLoggingInterceptor(logger);
    // 日志拦截器先运行且只读取稳定 extra；凭据随后注入，日志代码从执行顺序上也无法接触
    // headerValue。Dio 自带的 content-type 推断不会输出请求内容。
    dio.interceptors
      ..add(loggingInterceptor)
      ..add(_NetworkCredentialInterceptor(credentialProvider));

    _dio = dio;
    _loggingInterceptor = loggingInterceptor;
  }

  late final Dio _dio;
  late final _NetworkLoggingInterceptor _loggingInterceptor;
  final Set<CancelToken> _activeCancelTokens = <CancelToken>{};
  bool _isClosed = false;

  @override
  Future<NetworkResponse<T>> send<T>(
    NetworkRequest request, {
    required NetworkResponseDecoder<T> decoder,
    NetworkCancellationToken? cancellationToken,
  }) async {
    if (_isClosed) {
      throw StateError('Cannot send a request with a closed NetworkClient.');
    }

    final dioCancelToken = CancelToken();
    final unregisterCancellation = cancellationToken?.register(
      dioCancelToken.cancel,
    );
    _activeCancelTokens.add(dioCancelToken);

    try {
      late final Response<Object?> response;
      try {
        response = await _dio.request<Object?>(
          request.path,
          data: request.body,
          queryParameters: request.queryParameters,
          cancelToken: dioCancelToken,
          options: Options(
            method: request.method.wireName,
            headers: request.headers,
            contentType: request.body == null ? null : Headers.jsonContentType,
            responseType: ResponseType.json,
            extra: <String, Object?>{
              _operationExtraKey: request.operation,
              _requiresCredentialExtraKey: request.requiresCredential,
            },
          ),
        );
      } on DioException catch (error, stackTrace) {
        final mapped = _mapDioException(error);
        _loggingInterceptor.logFailure(request, mapped, stackTrace);
        Error.throwWithStackTrace(mapped, stackTrace);
      } on Object catch (_, stackTrace) {
        const mapped = UnexpectedAppError();
        _loggingInterceptor.logFailure(request, mapped, stackTrace);
        Error.throwWithStackTrace(mapped, stackTrace);
      }

      if (_isCancellationRequested(dioCancelToken, cancellationToken)) {
        final stackTrace = StackTrace.current;
        const mapped = NetworkCancelledError();
        _loggingInterceptor.logFailure(request, mapped, stackTrace);
        Error.throwWithStackTrace(mapped, stackTrace);
      }

      final statusCode = response.statusCode;
      if (statusCode == null || statusCode < 100 || statusCode > 599) {
        final stackTrace = StackTrace.current;
        const mapped = UnexpectedAppError();
        _loggingInterceptor.logFailure(request, mapped, stackTrace);
        Error.throwWithStackTrace(mapped, stackTrace);
      }

      late final T decoded;
      try {
        final decoding = Future<T>.sync(() => decoder(response.data));
        final cancelled = dioCancelToken.whenCancel.then<T>((_) {
          throw const _DecoderCancellationMarker();
        });
        // decoder 可能执行异步 DTO 转换。与 Dio token 竞速可让页面销毁或 client.close()
        // 立即结束调用方 Future；Dart 无法强杀已经开始的任意 Future，其迟到结果由
        // Future.any 已安装的处理器接收并丢弃，不会触发未捕获异常。
        decoded = await Future.any<T>(<Future<T>>[decoding, cancelled]);
      } on _DecoderCancellationMarker catch (_, stackTrace) {
        const mapped = NetworkCancelledError();
        _loggingInterceptor.logFailure(request, mapped, stackTrace);
        Error.throwWithStackTrace(mapped, stackTrace);
      } on Object catch (_, stackTrace) {
        const mapped = NetworkResponseParseError();
        _loggingInterceptor.logFailure(request, mapped, stackTrace);
        Error.throwWithStackTrace(mapped, stackTrace);
      }

      if (_isCancellationRequested(dioCancelToken, cancellationToken)) {
        final stackTrace = StackTrace.current;
        const mapped = NetworkCancelledError();
        _loggingInterceptor.logFailure(request, mapped, stackTrace);
        Error.throwWithStackTrace(mapped, stackTrace);
      }

      _loggingInterceptor.logSuccess(request, statusCode);
      return NetworkResponse<T>(statusCode: statusCode, data: decoded);
    } finally {
      // decoder 也属于一次 send 的生命周期；等最终成功或失败后再注销，避免 close() 与
      // 异步 decoder 竞态时漏掉取消状态或长期保留请求资源。
      unregisterCancellation?.call();
      _activeCancelTokens.remove(dioCancelToken);
    }
  }

  @override
  void close() {
    if (_isClosed) {
      return;
    }
    _isClosed = true;

    // 先发出统一取消信号，使仍在 Dio pipeline 中的 Future 尽量映射为 network.cancelled；
    // 随后强制关闭 transport，确保 Socket 和挂起 adapter 不阻止进程或测试结束。
    final activeTokens = List<CancelToken>.of(_activeCancelTokens);
    for (final token in activeTokens) {
      token.cancel();
    }
    _dio.close(force: true);
  }
}

bool _isCancellationRequested(
  CancelToken dioToken,
  NetworkCancellationToken? projectToken,
) {
  return dioToken.isCancelled || (projectToken?.isCancelled ?? false);
}

final class _NetworkCredentialInterceptor extends Interceptor {
  const _NetworkCredentialInterceptor(this._provider);

  final NetworkCredentialProvider _provider;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (options.extra[_requiresCredentialExtraKey] != true) {
      handler.next(options);
      return;
    }
    // 返回 Future 让 Dio 观察凭据读取期间的意外实现错误；已知 provider 失败仍在下层折叠
    // 为固定 marker。这样 adapter 既不会挂起 handler，也不会产生 detached 异常。
    await _injectCredential(options, handler);
  }

  Future<void> _injectCredential(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (_rejectIfCancelled(options, handler)) {
      return;
    }

    // 运行时凭据绝不通过明文 HTTP 发送。开发环境需要受保护 endpoint 时也应提供本地
    // HTTPS；第一阶段不增加可以意外进入生产的 insecure override。
    if (options.uri.scheme != 'https') {
      _reject(options, handler);
      return;
    }

    NetworkCredential? credential;
    try {
      credential = await _provider.loadCredential();
    } on Object {
      // provider 异常可能包含安全存储详情或凭据，因此不把原始对象写入 Dio error。
      _reject(options, handler);
      return;
    }
    if (credential == null) {
      _reject(options, handler);
      return;
    }
    if (_rejectIfCancelled(options, handler)) {
      return;
    }
    if (handler.isCompleted) {
      return;
    }

    options.headers.removeWhere(
      (name, _) => name.toLowerCase() == credential!.headerName,
    );
    options.headers[credential.headerName] = credential.headerValue;
    handler.next(options);
  }

  static bool _rejectIfCancelled(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) {
    final cancelError = options.cancelToken?.cancelError;
    if (cancelError == null) {
      return false;
    }
    if (!handler.isCompleted) {
      // provider 的 I/O 不能由 Dio 强制终止；完成后再次检查可以避免已经取消的请求继续
      // 注入凭据，并让被放弃的 handler Future 正常结束而不是长期保留 RequestOptions。
      handler.reject(cancelError);
    }
    return true;
  }

  static void _reject(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) {
    if (handler.isCompleted) {
      return;
    }
    handler.reject(
      DioException(
        requestOptions: options,
        type: DioExceptionType.unknown,
        error: const _CredentialsUnavailableMarker(),
        message: 'Credentials are unavailable for this request.',
      ),
    );
  }
}

final class _NetworkLoggingInterceptor extends Interceptor {
  const _NetworkLoggingInterceptor(this._logger);

  final AppLogger _logger;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final operation = options.extra[_operationExtraKey];
    if (operation is String) {
      _safeLog(
        AppLogLevel.debug,
        event: 'network.request_started',
        message: 'A network request started.',
        context: <String, Object?>{
          'operation': operation,
          'method': options.method,
        },
      );
    }
    handler.next(options);
  }

  void logSuccess(NetworkRequest request, int statusCode) {
    _safeLog(
      AppLogLevel.info,
      event: 'network.request_succeeded',
      message: 'A network request completed successfully.',
      context: <String, Object?>{
        'operation': request.operation,
        'method': request.method.wireName,
        'statusCode': statusCode,
      },
    );
  }

  void logFailure(
    NetworkRequest request,
    AppError error,
    StackTrace stackTrace,
  ) {
    final context = <String, Object?>{
      'operation': request.operation,
      'method': request.method.wireName,
      'errorCode': error.code,
    };
    if (error is NetworkResponseError) {
      context['statusCode'] = error.statusCode;
    }
    final level = switch (error) {
      NetworkCancelledError() => AppLogLevel.info,
      UnexpectedAppError() => AppLogLevel.error,
      _ => AppLogLevel.warning,
    };
    _safeLog(
      level,
      event: 'network.request_failed',
      message: 'A network request did not complete successfully.',
      context: context,
      // 只交给 logger 稳定 AppError。原始 Dio/decoder 异常可能含 URL 或响应正文，
      // 即使存在统一 redactor 也不能主动扩大其可见范围。
      error: error,
      stackTrace: stackTrace,
    );
  }

  void _safeLog(
    AppLogLevel level, {
    required String event,
    required String message,
    required Map<String, Object?> context,
    Object? error,
    StackTrace? stackTrace,
  }) {
    try {
      _logger.log(
        level,
        event: event,
        message: message,
        context: context,
        error: error,
        stackTrace: stackTrace,
      );
    } on Object {
      // logger 关闭或实现违反非抛出约定时，网络结果仍必须由真实传输/解析行为决定。
    }
  }
}

AppError _mapDioException(DioException error) {
  return switch (error.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout ||
    DioExceptionType.transformTimeout => const NetworkTimeoutError(),
    DioExceptionType.badCertificate ||
    DioExceptionType.connectionError => const NetworkConnectionError(),
    DioExceptionType.badResponse => _mapBadResponse(error),
    DioExceptionType.cancel => const NetworkCancelledError(),
    DioExceptionType.unknown
        when error.error is _CredentialsUnavailableMarker =>
      const NetworkCredentialsUnavailableError(),
    DioExceptionType.unknown when error.error is FormatException =>
      const NetworkResponseParseError(),
    DioExceptionType.unknown => const UnexpectedAppError(),
  };
}

AppError _mapBadResponse(DioException error) {
  final statusCode = error.response?.statusCode;
  if (statusCode == null || statusCode < 100 || statusCode > 599) {
    return const UnexpectedAppError();
  }
  return NetworkResponseError(statusCode: statusCode);
}

Uri _normalizeBaseUri(Uri value) {
  if (!value.isAbsolute ||
      (value.scheme != 'http' && value.scheme != 'https') ||
      value.host.isEmpty ||
      value.userInfo.isNotEmpty ||
      value.hasQuery ||
      value.hasFragment) {
    throw ArgumentError(
      'Base URI must be an absolute HTTP(S) URI without credentials, query, '
      'or fragment.',
    );
  }

  try {
    for (final segment in value.pathSegments) {
      if (segment == '.' ||
          segment == '..' ||
          segment.contains('/') ||
          segment.contains('\\') ||
          segment.contains('?') ||
          segment.contains('#') ||
          _encodedBasePathSequencePattern.hasMatch(segment) ||
          _basePathControlCharacterPattern.hasMatch(segment)) {
        throw const _InvalidBaseUri();
      }
    }
  } on Object {
    throw ArgumentError('Base URI path is invalid.');
  }

  final normalizedPath =
      value.path.endsWith('/') ? value.path : '${value.path}/';
  return value.replace(path: normalizedPath);
}

Map<String, String> _validateCommonHeaders(Map<String, String> input) {
  try {
    final output = <String, String>{};
    for (final entry in input.entries) {
      final normalizedName = entry.key.toLowerCase();
      if (!_commonHeaderNamePattern.hasMatch(entry.key) ||
          _forbiddenCommonHeaders.contains(normalizedName) ||
          _commonHeaderControlCharacterPattern.hasMatch(entry.value)) {
        throw const _InvalidCommonHeader();
      }
      output[normalizedName] = entry.value;
    }
    return Map<String, String>.unmodifiable(output);
  } on Object {
    throw ArgumentError(
      'Common headers must be valid and must not contain credentials.',
    );
  }
}

final _commonHeaderNamePattern = RegExp(r"^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$");
final _commonHeaderControlCharacterPattern = RegExp(r'[\x00-\x1F\x7F]');
final _encodedBasePathSequencePattern = RegExp(r'%[0-9a-fA-F]{2}');
final _basePathControlCharacterPattern = RegExp(r'[\x00-\x1F\x7F]');
const _forbiddenCommonHeaders = <String>{
  'authorization',
  'proxy-authorization',
  'cookie',
  'set-cookie',
  'token',
  'x-token',
  'x-auth-token',
  'x-access-token',
  'x-refresh-token',
  'x-client-secret',
  'x-api-key',
  'api-key',
  'host',
  'content-length',
  'transfer-encoding',
  'connection',
  'content-type',
};

final class _CredentialsUnavailableMarker implements Exception {
  const _CredentialsUnavailableMarker();
}

final class _DecoderCancellationMarker implements Exception {
  const _DecoderCancellationMarker();
}

final class _InvalidBaseUri implements Exception {
  const _InvalidBaseUri();
}

final class _InvalidCommonHeader implements Exception {
  const _InvalidCommonHeader();
}
