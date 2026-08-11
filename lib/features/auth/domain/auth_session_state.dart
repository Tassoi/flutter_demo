import 'package:flutter_template/features/auth/domain/auth_failure.dart';

/// Riverpod 认证状态机对外公开的稳定阶段。
enum AuthSessionPhase {
  /// 正在从安全存储恢复，受保护路由必须进入固定加载页。
  restoring,

  /// 当前没有可用会话。
  signedOut,

  /// 正在提交登录，登录页必须去重并禁用重复提交。
  signingIn,

  /// 内存中存在仍可刷新或发送的会话凭据。
  authenticated,

  /// 最近一次认证操作失败，当前仍按未认证处理。
  failure,
}

/// Router 与认证 UI 共同读取的不可变会话快照。
///
/// 状态只包含阶段与稳定 [AuthFailure]，不包含 credential、密码、账号标识、完整用户对象、
/// gateway 或存储实例。真正的敏感会话只由 controller 私有持有，因此 Provider observer、
/// Widget 调试输出和测试快照都无法读取 Token。
final class AuthSessionState {
  const AuthSessionState._({required this.phase, this.failure});

  /// 创建启动恢复状态。
  const AuthSessionState.restoring()
    : this._(phase: AuthSessionPhase.restoring);

  /// 创建明确未登录状态。
  const AuthSessionState.signedOut()
    : this._(phase: AuthSessionPhase.signedOut);

  /// 创建登录请求进行中状态。
  const AuthSessionState.signingIn()
    : this._(phase: AuthSessionPhase.signingIn);

  /// 创建已认证状态；敏感凭据不会作为参数进入本对象。
  const AuthSessionState.authenticated()
    : this._(phase: AuthSessionPhase.authenticated);

  /// 创建携带安全失败分类的未认证状态。
  const AuthSessionState.failure(AuthFailure failure)
    : this._(phase: AuthSessionPhase.failure, failure: failure);

  /// 当前稳定状态机阶段。
  final AuthSessionPhase phase;

  /// 仅在 [phase] 为 [AuthSessionPhase.failure] 时存在的稳定失败。
  final AuthFailure? failure;

  /// Router 是否可以放行受保护位置。
  bool get isAuthenticated => phase == AuthSessionPhase.authenticated;

  /// Router 是否必须等待启动恢复完成。
  bool get isRestoring => phase == AuthSessionPhase.restoring;

  @override
  String toString() {
    return 'AuthSessionState(phase: ${phase.name}, '
        'failureCode: ${failure?.code})';
  }
}
