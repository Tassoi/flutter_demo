import 'dart:async';

import 'package:flutter_template/core/error/app_error.dart';
import 'package:flutter_template/core/network/network_cancellation_token.dart';
import 'package:flutter_template/core/network/network_client.dart';
import 'package:flutter_template/core/network/network_request.dart';
import 'package:flutter_template/core/network/network_response.dart';
import 'package:flutter_template/features/auth/domain/auth_session_coordinator.dart';

/// 在现有 [NetworkClient] 外增加 401 单次刷新/重放语义的认证装饰器。
///
/// 只有明确 `requiresCredential` 且第一次响应为 401 的请求会触发刷新。同一 session
/// generation 的并发请求由 [AuthSessionCoordinator] 汇聚到一个 refresh Future；每个受保护
/// 请求还会绑定开始时的非敏感 generation。退出、失效或新登录推进 generation 后，旧请求的
/// 成功、失败和 401 都按取消处理，不能刷新、重放或失效新会话。装饰器自身不读取、保存或
/// 记录 credential。刷新成功后，每个请求最多重放一次，默认仅允许无 body GET；其他方法
/// 必须显式选择 `NetworkRequestReplayPolicy.explicitlyIdempotent`。
///
/// 登录和刷新 gateway 必须直接使用构造时传入的基础客户端，不能调用本装饰器，避免 401
/// 递归。装饰器拥有 [_baseClient] 的关闭职责；应用释放它时会关闭共享传输，此后再次发送
/// 抛固定 [StateError]。
final class AuthenticatedNetworkClient implements NetworkClient {
  /// 创建认证装饰器。
  ///
  /// [_baseClient] 应已配置 [SessionCredentialProvider]，使首次发送和重放都按请求时的
  /// 最新内存 credential 注入。[_sessionCoordinator] 必须与该 provider 指向同一 controller。
  AuthenticatedNetworkClient({
    required NetworkClient baseClient,
    required AuthSessionCoordinator sessionCoordinator,
  }) : _baseClient = baseClient,
       _sessionCoordinator = sessionCoordinator;

  final NetworkClient _baseClient;
  final AuthSessionCoordinator _sessionCoordinator;
  var _isClosed = false;

  @override
  Future<NetworkResponse<T>> send<T>(
    NetworkRequest request, {
    required NetworkResponseDecoder<T> decoder,
    NetworkCancellationToken? cancellationToken,
  }) async {
    _ensureActive();
    final requestGeneration =
        request.requiresCredential
            ? _sessionCoordinator.sessionGeneration
            : null;
    try {
      final response = await _baseClient.send<T>(
        request,
        decoder: decoder,
        cancellationToken: cancellationToken,
      );
      _ensureCurrentSession(requestGeneration);
      return response;
    } on AppError catch (error, stackTrace) {
      _ensureCurrentSession(requestGeneration);
      if (!request.requiresCredential ||
          error is! NetworkResponseError ||
          error.statusCode != 401) {
        Error.throwWithStackTrace(error, stackTrace);
      }

      try {
        final refresh = _sessionCoordinator.refreshSession();
        await _waitForRefresh(
          refresh,
          callerCancellationToken: cancellationToken,
        );
      } on NetworkCancelledError catch (error, cancellationStackTrace) {
        Error.throwWithStackTrace(error, cancellationStackTrace);
      } on Object {
        // refresh 的具体失败已由 session controller 折叠并使会话失效。调用方继续收到首次
        // 401，避免 gateway 异常、refresh 响应或安全存储详情跨越网络契约。
        Error.throwWithStackTrace(error, stackTrace);
      }

      _ensureCurrentSession(requestGeneration);
      if (cancellationToken?.isCancelled ?? false) {
        throw const NetworkCancelledError();
      }
      if (!_canReplay(request)) {
        Error.throwWithStackTrace(error, stackTrace);
      }

      try {
        // 直接调用基础客户端而不是递归调用 send，严格保证每个原始请求最多重放一次。
        final response = await _baseClient.send<T>(
          request,
          decoder: decoder,
          cancellationToken: cancellationToken,
        );
        _ensureCurrentSession(requestGeneration);
        return response;
      } on AppError catch (retryError, retryStackTrace) {
        _ensureCurrentSession(requestGeneration);
        if (retryError is NetworkResponseError &&
            retryError.statusCode == 401) {
          try {
            await _sessionCoordinator.invalidateSession();
          } on Object {
            // 安全存储清理失败已由 controller 记录为稳定状态，不能遮盖服务端第二次 401。
          }
        }
        Error.throwWithStackTrace(retryError, retryStackTrace);
      }
    }
  }

  @override
  void close() {
    if (_isClosed) {
      return;
    }
    _isClosed = true;
    _baseClient.close();
  }

  bool _canReplay(NetworkRequest request) {
    return request.method == NetworkMethod.get ||
        request.replayPolicy == NetworkRequestReplayPolicy.explicitlyIdempotent;
  }

  void _ensureCurrentSession(int? requestGeneration) {
    if (requestGeneration != null &&
        requestGeneration != _sessionCoordinator.sessionGeneration) {
      // generation 变化表示用户已经退出、会话失效或切换账号。即使底层请求随后成功，也不能
      // 把旧会话发起的结果交给调用方，更不能用它触发新会话的刷新、重放或失效。
      throw const NetworkCancelledError();
    }
  }

  Future<void> _waitForRefresh(
    Future<void> refresh, {
    required NetworkCancellationToken? callerCancellationToken,
  }) async {
    final token = callerCancellationToken;
    if (token == null) {
      await refresh;
      return;
    }
    if (token.isCancelled) {
      throw const NetworkCancelledError();
    }

    final cancelled = Completer<void>();
    final unregister = token.register(() {
      if (!cancelled.isCompleted) {
        cancelled.completeError(const NetworkCancelledError());
      }
    });
    try {
      // 取消仅结束当前调用方的等待；共享 refresh 使用 controller 自己的令牌，仍会服务
      // 其他并发 401。Future.any 会为未胜出的 Future 保留错误监听，避免迟到失败未处理。
      await Future.any<void>(<Future<void>>[refresh, cancelled.future]);
    } finally {
      unregister();
    }
  }

  void _ensureActive() {
    if (_isClosed) {
      throw StateError('Authenticated network client is closed.');
    }
  }
}
