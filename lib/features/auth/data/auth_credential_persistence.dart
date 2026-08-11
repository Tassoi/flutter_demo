import 'package:flutter_template/features/auth/domain/auth_credentials.dart';
import 'package:flutter_template/features/auth/domain/auth_failure.dart';

/// session controller 使用的凭据 envelope 持久化边界。
///
/// 实现必须把 access/refresh credential 与有效期作为一个原子逻辑值保存，不能拆到普通
/// 偏好或多个安全键。读取缺失值返回 `null`；损坏、平台失败或无法证明写入/删除完成时只
/// 抛 [AuthPersistenceFailure]，不暴露原始值或键名。
abstract interface class AuthCredentialPersistence {
  /// 读取并严格验证当前安全 envelope；不存在时返回 `null`。
  Future<AuthCredentials?> load();

  /// 以单个安全 envelope 覆盖保存 [credentials]。
  Future<void> save(AuthCredentials credentials);

  /// 删除认证模块拥有的安全 envelope；不存在时成功完成。
  Future<void> clear();
}

/// 认证持久化尚未接入时使用的安全默认实现。
///
/// 它不会保存任何值，启动按无会话处理，清理为空操作；任何保存尝试都失败关闭，确保只
/// 替换 gateway 却遗漏安全存储组装时不能建立仅驻留内存或写入普通偏好的伪会话。
final class UnconfiguredAuthCredentialPersistence
    implements AuthCredentialPersistence {
  /// 创建无状态、不会持久化敏感值的默认边界。
  const UnconfiguredAuthCredentialPersistence();

  @override
  Future<AuthCredentials?> load() async => null;

  @override
  Future<void> save(AuthCredentials credentials) {
    return Future<void>.error(const AuthPersistenceFailure());
  }

  @override
  Future<void> clear() async {}
}
