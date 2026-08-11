import 'package:flutter_template/features/auth/domain/auth_credentials.dart';

/// 创建只用于测试进程内存的确定性认证凭据。
///
/// 值具有明显的 fixture 前缀，不对应任何真实服务或账号。调用方不得把返回对象输出到测试
/// 快照或日志；测试结束后它随进程内存释放，不提供真实加密或安全保证。
AuthCredentials createAuthCredentialsFixture({
  String generation = 'one',
  DateTime? accessExpiresAt,
  DateTime? refreshExpiresAt,
}) {
  final accessExpiry =
      accessExpiresAt ?? DateTime.utc(2030, DateTime.january, 1, 1);
  final refreshExpiry =
      refreshExpiresAt ?? DateTime.utc(2030, DateTime.january, 2, 1);
  return AuthCredentials(
    accessCredential: 'fixture-access-$generation',
    refreshCredential: 'fixture-refresh-$generation',
    accessExpiresAt: accessExpiry,
    refreshExpiresAt: refreshExpiry,
  );
}
