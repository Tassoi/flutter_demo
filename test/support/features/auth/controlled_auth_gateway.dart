import 'dart:async';

import 'package:flutter_template/core/network/network_cancellation_token.dart';
import 'package:flutter_template/features/auth/domain/auth_credentials.dart';
import 'package:flutter_template/features/auth/domain/auth_gateway.dart';

/// 由测试显式完成登录和刷新操作的确定性 gateway。
///
/// 替身只保存调用次数、脱敏 `toString()` 和取消令牌，不保存账号、密码或 refresh credential。
/// [ControlledAuthOperation] 即使令牌取消后仍允许测试注入迟到结果，用于证明 production
/// controller 的 generation 检查，而不是依赖 fake 主动配合取消。
final class ControlledAuthGateway implements AuthGateway {
  final Completer<void> _firstSignInRequested = Completer<void>();
  final Completer<void> _firstRefreshRequested = Completer<void>();

  /// 已创建且尚可由测试完成的登录操作。
  final List<ControlledAuthOperation> signInOperations =
      <ControlledAuthOperation>[];

  /// 已创建且尚可由测试完成的刷新操作。
  final List<ControlledAuthOperation> refreshOperations =
      <ControlledAuthOperation>[];

  /// 登录输入的安全格式化结果，用于证明敏感字段未进入诊断字符串。
  final List<String> safeSignInDescriptions = <String>[];

  /// 第一次登录调用已经进入 gateway 的确定性信号。
  Future<void> get firstSignInRequested => _firstSignInRequested.future;

  /// 第一次刷新调用已经进入 gateway 的确定性信号。
  Future<void> get firstRefreshRequested => _firstRefreshRequested.future;

  @override
  Future<AuthCredentials> signIn(
    AuthSignInRequest request, {
    required NetworkCancellationToken cancellationToken,
  }) {
    safeSignInDescriptions.add(request.toString());
    final operation = ControlledAuthOperation(cancellationToken);
    signInOperations.add(operation);
    if (!_firstSignInRequested.isCompleted) {
      _firstSignInRequested.complete();
    }
    return operation.result;
  }

  @override
  Future<AuthCredentials> refresh({
    required String refreshCredential,
    required NetworkCancellationToken cancellationToken,
  }) {
    // 故意不保存或格式化 refreshCredential；调用次数已经足够验证单飞语义。
    final operation = ControlledAuthOperation(cancellationToken);
    refreshOperations.add(operation);
    if (!_firstRefreshRequested.isCompleted) {
      _firstRefreshRequested.complete();
    }
    return operation.result;
  }
}

/// 测试控制的一次 gateway Future 与其项目取消令牌。
final class ControlledAuthOperation {
  /// 创建尚未完成的操作。
  ControlledAuthOperation(this.cancellationToken);

  final Completer<AuthCredentials> _completer = Completer<AuthCredentials>();

  /// production controller 传给 gateway 的取消令牌。
  final NetworkCancellationToken cancellationToken;

  /// gateway 返回给 controller 的结果 Future。
  Future<AuthCredentials> get result => _completer.future;

  /// 使用 [credentials] 成功完成；已完成时不重复写入。
  void succeed(AuthCredentials credentials) {
    if (!_completer.isCompleted) {
      _completer.complete(credentials);
    }
  }

  /// 使用 [error] 和可选 [stackTrace] 失败完成。
  void fail(Object error, [StackTrace? stackTrace]) {
    if (!_completer.isCompleted) {
      _completer.completeError(error, stackTrace ?? StackTrace.current);
    }
  }
}
