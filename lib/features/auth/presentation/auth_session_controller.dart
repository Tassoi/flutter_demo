import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_template/core/error/app_error.dart';
import 'package:flutter_template/core/logging/app_log_level.dart';
import 'package:flutter_template/core/logging/app_logger.dart';
import 'package:flutter_template/core/network/network_cancellation_token.dart';
import 'package:flutter_template/core/network/network_credential_provider.dart';
import 'package:flutter_template/features/auth/data/auth_credential_persistence.dart';
import 'package:flutter_template/features/auth/data/unconfigured_auth_gateway.dart';
import 'package:flutter_template/features/auth/domain/auth_clock.dart';
import 'package:flutter_template/features/auth/domain/auth_credentials.dart';
import 'package:flutter_template/features/auth/domain/auth_failure.dart';
import 'package:flutter_template/features/auth/domain/auth_gateway.dart';
import 'package:flutter_template/features/auth/domain/auth_session_coordinator.dart';
import 'package:flutter_template/features/auth/domain/auth_session_state.dart';

/// 应用组装层替换真实认证 gateway 的唯一 Provider 入口。
///
/// 默认值明确失败且不访问网络、不接受本地账号。真实 adapter 只依赖项目接口，并由 app
/// composition root override；测试也应注入确定性 fake，而不是插件或真实服务。
final authGatewayProvider = Provider<AuthGateway>(
  (_) => const UnconfiguredAuthGateway(),
  name: 'authGateway',
);

/// 应用组装层绑定单 envelope 安全持久化实现的 Provider 入口。
///
/// 默认边界不保存敏感值，确保遗漏 production override 时登录失败关闭。正式应用必须使用
/// `SecureAuthCredentialPersistence`；绝不能替换为普通偏好或仅内存 production 实现。
final authCredentialPersistenceProvider = Provider<AuthCredentialPersistence>(
  (_) => const UnconfiguredAuthCredentialPersistence(),
  name: 'authCredentialPersistence',
);

/// 认证有效期判断使用的可替换时钟。
final authClockProvider = Provider<AuthClock>(
  (_) => const SystemAuthClock(),
  name: 'authClock',
);

/// 认证模块使用的可选安全日志边界。
///
/// production 会注入应用级 [AppLogger]。`null` 只用于尚未组装认证或聚焦状态行为的测试；
/// controller 从不把输入、credential、URI、异常或堆栈传给 logger。
final authLoggerProvider = Provider<AppLogger?>(
  (_) => null,
  name: 'authLogger',
);

/// 应用生命周期内唯一的认证会话状态所有者。
///
/// Provider 非 auto-dispose，因为路由、凭据注入器和多个页面共享同一 session generation；
/// 根 [ProviderScope] 销毁时统一取消登录/刷新工作，并阻止任何迟到结果更新状态。
final authSessionProvider =
    NotifierProvider<AuthSessionController, AuthSessionState>(
      AuthSessionController.new,
      name: 'authSession',
    );

/// 管理启动恢复、登录、退出、共享刷新、凭据注入和会话失效。
///
/// 敏感 [AuthCredentials] 只保存在私有字段。每次退出、替换账号或失效都会先递增 generation
/// 并清空内存，再取消认证模块拥有的令牌；所有异步结果在写状态前复核 generation。安全
/// 存储操作通过串行队列执行，保证旧 refresh 写入与随后的退出删除不会乱序。
///
/// 本 controller 不解析后端协议、不控制 Router、不保存用户对象，也不拥有 logger 或底层
/// 安全存储生命周期。对外状态只包含 [AuthSessionState] 和稳定 [AuthFailure]。
final class AuthSessionController extends Notifier<AuthSessionState>
    implements AuthSessionCoordinator {
  late AuthGateway _gateway;
  late AuthCredentialPersistence _persistence;
  late AuthClock _clock;
  AppLogger? _logger;

  AuthCredentials? _credentials;
  NetworkCancellationToken? _activeSignInToken;
  NetworkCancellationToken? _activeRefreshToken;
  Future<void>? _refreshFuture;
  int? _refreshFutureGeneration;
  Future<void> _persistenceQueue = Future<void>.value();
  final Completer<void> _restorationCompleted = Completer<void>();
  var _generation = 0;
  var _isDisposed = false;

  /// 初始化依赖并立即开始一次安全存储恢复。
  ///
  /// 方法同步返回 [AuthSessionState.restoring]；I/O 在该状态发布后异步进行。缺失 envelope
  /// 正常进入未登录，损坏/读取失败进入稳定失败；过期 access 会尝试一次共享刷新。
  @override
  AuthSessionState build() {
    _gateway = ref.read(authGatewayProvider);
    _persistence = ref.read(authCredentialPersistenceProvider);
    _clock = ref.read(authClockProvider);
    _logger = ref.read(authLoggerProvider);
    _isDisposed = false;
    final generation = ++_generation;
    ref.onDispose(_disposeController);
    unawaited(_restore(generation));
    return const AuthSessionState.restoring();
  }

  /// 当前启动恢复流程完成的确定性 Future。
  ///
  /// 测试和非 Widget 组装可以等待它再断言稳定状态。无论恢复成功、失败或 controller 提前
  /// 销毁，本 Future 都会完成且不会携带敏感错误；具体结果通过 Provider 状态读取。
  Future<void> get restorationCompleted => _restorationCompleted.future;

  @override
  int get sessionGeneration => _generation;

  /// 使用用户输入建立一代新会话。
  ///
  /// 返回 `true` 只表示 gateway 成功、凭据仍在当前 generation 且完整 envelope 已写入安全
  /// 存储。重复提交、恢复中或 controller 已销毁返回 `false`。登录开始前先使旧会话失效并
  /// 删除旧 envelope；写入失败绝不会降级成仅内存登录。
  Future<bool> signIn({
    required String identifier,
    required String password,
  }) async {
    if (_isDisposed ||
        state.phase == AuthSessionPhase.restoring ||
        state.phase == AuthSessionPhase.signingIn) {
      return false;
    }

    late final AuthSignInRequest request;
    try {
      request = AuthSignInRequest(identifier: identifier, password: password);
    } on Object {
      // Router 正常不会让已认证用户停留在登录页，但 controller 仍是公开命令边界。
      // 非法程序化调用不能仅因参数校验失败就丢弃或隐藏一份已经持久化的有效会话。
      if (!state.isAuthenticated) {
        state = const AuthSessionState.failure(UnexpectedAuthFailure());
      }
      return false;
    }

    final generation = _beginNewGeneration();
    state = const AuthSessionState.signingIn();
    NetworkCancellationToken? operationToken;
    try {
      await _runPersistence(_persistence.clear);
      if (!_isCurrentGeneration(generation)) {
        return false;
      }

      final cancellationToken = NetworkCancellationToken();
      operationToken = cancellationToken;
      _activeSignInToken = cancellationToken;
      final credentials = await _gateway.signIn(
        request,
        cancellationToken: cancellationToken,
      );
      _requireUsableFreshCredentials(credentials);
      if (!_isCurrentOperation(generation, cancellationToken)) {
        return false;
      }

      await _runPersistence(() => _persistence.save(credentials));
      if (!_isCurrentOperation(generation, cancellationToken)) {
        return false;
      }
      _credentials = credentials;
      state = const AuthSessionState.authenticated();
      _log(
        AppLogLevel.info,
        event: 'auth.sign_in_succeeded',
        message: 'Authentication sign-in succeeded.',
      );
      return true;
    } on Object catch (error) {
      if (!_isCurrentGeneration(generation)) {
        return false;
      }
      _credentials = null;
      final failure = _mapSignInFailure(error);
      state = AuthSessionState.failure(failure);
      await _clearPersistedBestEffort();
      _log(
        AppLogLevel.warning,
        event: 'auth.sign_in_failed',
        message: 'Authentication sign-in failed.',
      );
      return false;
    } finally {
      if (identical(_activeSignInToken, operationToken)) {
        _activeSignInToken = null;
      }
    }
  }

  /// 立即撤销当前内存会话，并删除持久化 envelope。
  ///
  /// generation 与状态会在第一次 `await` 前更新，所以旧请求、登录或 refresh 的迟到结果
  /// 无法恢复会话。返回 `true` 仅表示安全删除成功；删除失败保持未认证并发布
  /// [AuthPersistenceFailure]，调用方不得向用户谎报持久化退出已经完成。
  Future<bool> signOut() async {
    if (_isDisposed) {
      return false;
    }
    final generation = _beginNewGeneration();
    state = const AuthSessionState.signedOut();
    try {
      await _runPersistence(_persistence.clear);
      if (_isCurrentGeneration(generation)) {
        _log(
          AppLogLevel.info,
          event: 'auth.sign_out_succeeded',
          message: 'Authentication sign-out succeeded.',
        );
      }
      return true;
    } on Object {
      if (_isCurrentGeneration(generation)) {
        state = const AuthSessionState.failure(AuthPersistenceFailure());
        _log(
          AppLogLevel.warning,
          event: 'auth.sign_out_persistence_failed',
          message: 'Authentication sign-out could not clear secure storage.',
        );
      }
      return false;
    }
  }

  @override
  Future<NetworkCredential?> loadNetworkCredential() async {
    if (_isDisposed || !state.isAuthenticated) {
      return null;
    }
    final credentials = _credentials;
    if (credentials == null) {
      return null;
    }
    if (!credentials.isAccessUsableAt(_clock.now())) {
      await refreshSession();
    }
    if (_isDisposed || !state.isAuthenticated) {
      return null;
    }
    final current = _credentials;
    if (current == null || !current.isAccessUsableAt(_clock.now())) {
      return null;
    }
    return NetworkCredential(
      headerName: 'authorization',
      headerValue: 'Bearer ${current.accessCredential}',
    );
  }

  @override
  Future<void> refreshSession() {
    if (_isDisposed) {
      return Future<void>.error(const NetworkCancelledError());
    }
    final existing = _refreshFuture;
    if (existing != null && _refreshFutureGeneration == _generation) {
      return existing;
    }
    final credentials = _credentials;
    if (credentials == null || !credentials.isRefreshUsableAt(_clock.now())) {
      return _expireCurrentSession();
    }

    final generation = _generation;
    final cancellationToken = NetworkCancellationToken();
    _activeRefreshToken = cancellationToken;
    final refresh = _performRefresh(
      generation: generation,
      previousCredentials: credentials,
      cancellationToken: cancellationToken,
    );
    _refreshFuture = refresh;
    _refreshFutureGeneration = generation;
    return refresh;
  }

  @override
  Future<void> invalidateSession() async {
    if (_isDisposed) {
      return;
    }
    await _invalidateGeneration(
      generation: _generation,
      failure: const AuthSessionExpiredFailure(),
    );
  }

  Future<void> _restore(int generation) async {
    try {
      final stored = await _runPersistence(_persistence.load);
      if (!_isCurrentGeneration(generation)) {
        return;
      }
      if (stored == null) {
        state = const AuthSessionState.signedOut();
        return;
      }
      if (!stored.isRefreshUsableAt(_clock.now())) {
        await _invalidateGeneration(
          generation: generation,
          failure: const AuthSessionExpiredFailure(),
        );
        return;
      }
      _credentials = stored;
      if (stored.isAccessUsableAt(_clock.now())) {
        state = const AuthSessionState.authenticated();
        _log(
          AppLogLevel.info,
          event: 'auth.session_restored',
          message: 'Authentication session was restored.',
        );
        return;
      }
      await refreshSession();
    } on Object catch (error) {
      if (_isCurrentGeneration(generation)) {
        _credentials = null;
        final failure =
            error is AuthSessionExpiredFailure
                ? error
                : const AuthPersistenceFailure();
        state = AuthSessionState.failure(failure);
        // 损坏 envelope 不能留待下次启动重复解析；平台读取失败时删除也可能失败，因此只
        // 尽力清理并保持已经发布的安全失败，绝不改用普通存储或恢复未经验证的值。
        await _clearPersistedBestEffort();
        _log(
          AppLogLevel.warning,
          event: 'auth.session_restore_failed',
          message: 'Authentication session could not be restored.',
        );
      }
    } finally {
      if (!_restorationCompleted.isCompleted) {
        _restorationCompleted.complete();
      }
    }
  }

  Future<void> _performRefresh({
    required int generation,
    required AuthCredentials previousCredentials,
    required NetworkCancellationToken cancellationToken,
  }) async {
    try {
      final refreshed = await _gateway.refresh(
        refreshCredential: previousCredentials.refreshCredential,
        cancellationToken: cancellationToken,
      );
      _requireUsableFreshCredentials(refreshed);
      if (!_isCurrentOperation(generation, cancellationToken)) {
        throw const NetworkCancelledError();
      }
      await _runPersistence(() => _persistence.save(refreshed));
      if (!_isCurrentOperation(generation, cancellationToken)) {
        throw const NetworkCancelledError();
      }
      _credentials = refreshed;
      state = const AuthSessionState.authenticated();
      _log(
        AppLogLevel.info,
        event: 'auth.session_refreshed',
        message: 'Authentication session was refreshed.',
      );
    } on Object catch (error, stackTrace) {
      if (_isCurrentGeneration(generation)) {
        final failure =
            error is AuthPersistenceFailure
                ? const AuthPersistenceFailure()
                : const AuthSessionExpiredFailure();
        await _invalidateGeneration(generation: generation, failure: failure);
        _log(
          AppLogLevel.warning,
          event: 'auth.session_refresh_failed',
          message: 'Authentication session refresh failed.',
        );
        Error.throwWithStackTrace(failure, stackTrace);
      }
      Error.throwWithStackTrace(const NetworkCancelledError(), stackTrace);
    } finally {
      if (identical(_activeRefreshToken, cancellationToken)) {
        _activeRefreshToken = null;
      }
      if (_refreshFutureGeneration == generation) {
        _refreshFuture = null;
        _refreshFutureGeneration = null;
      }
    }
  }

  Future<void> _expireCurrentSession() async {
    final generation = _generation;
    await _invalidateGeneration(
      generation: generation,
      failure: const AuthSessionExpiredFailure(),
    );
    throw const AuthSessionExpiredFailure();
  }

  Future<void> _invalidateGeneration({
    required int generation,
    required AuthFailure failure,
  }) async {
    if (!_isCurrentGeneration(generation)) {
      return;
    }
    final invalidatedGeneration = _beginNewGeneration();
    state = AuthSessionState.failure(failure);
    try {
      await _runPersistence(_persistence.clear);
    } on Object {
      if (_isCurrentGeneration(invalidatedGeneration)) {
        _log(
          AppLogLevel.warning,
          event: 'auth.session_clear_failed',
          message: 'Invalid authentication session could not be cleared.',
        );
      }
    }
  }

  int _beginNewGeneration() {
    _generation++;
    _credentials = null;
    final signInToken = _activeSignInToken;
    final refreshToken = _activeRefreshToken;
    _activeSignInToken = null;
    _activeRefreshToken = null;
    signInToken?.cancel();
    refreshToken?.cancel();
    return _generation;
  }

  bool _isCurrentGeneration(int generation) {
    return !_isDisposed && generation == _generation;
  }

  bool _isCurrentOperation(
    int generation,
    NetworkCancellationToken cancellationToken,
  ) {
    return _isCurrentGeneration(generation) && !cancellationToken.isCancelled;
  }

  Future<T> _runPersistence<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _persistenceQueue = _persistenceQueue.then((_) async {
      try {
        result.complete(await operation());
      } on Object catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  Future<void> _clearPersistedBestEffort() async {
    try {
      await _runPersistence(_persistence.clear);
    } on Object {
      // 当前状态已是安全失败且内存凭据为空。删除失败不能改用普通存储，也不能把键、值或
      // 插件错误放入状态；固定日志事件用于提示重启后可能再次读到旧 envelope 的风险。
      _log(
        AppLogLevel.warning,
        event: 'auth.session_clear_failed',
        message: 'Invalid authentication session could not be cleared.',
      );
    }
  }

  AuthFailure _mapSignInFailure(Object error) {
    if (error is AuthFailure) {
      return error;
    }
    if (error is StorageInitializationError ||
        error is StorageReadError ||
        error is StorageWriteError ||
        error is StorageDeleteError ||
        error is StorageClearError) {
      return const AuthPersistenceFailure();
    }
    if (error is NetworkConnectionError ||
        error is NetworkTimeoutError ||
        error is NetworkResponseError ||
        error is NetworkCredentialsUnavailableError) {
      return const AuthServiceUnavailableFailure();
    }
    return const UnexpectedAuthFailure();
  }

  void _requireUsableFreshCredentials(AuthCredentials credentials) {
    final now = _clock.now();
    if (!credentials.isAccessUsableAt(now) ||
        !credentials.isRefreshUsableAt(now)) {
      throw const AuthSessionExpiredFailure();
    }
  }

  void _log(
    AppLogLevel level, {
    required String event,
    required String message,
  }) {
    try {
      _logger?.log(level, event: event, message: message);
    } on Object {
      // 日志生命周期或实现失败不能改变认证状态；禁止把 logger 异常反向写入 UI。
    }
  }

  void _disposeController() {
    _isDisposed = true;
    _generation++;
    _credentials = null;
    _activeSignInToken?.cancel();
    _activeRefreshToken?.cancel();
    _activeSignInToken = null;
    _activeRefreshToken = null;
    if (!_restorationCompleted.isCompleted) {
      _restorationCompleted.complete();
    }
  }
}
