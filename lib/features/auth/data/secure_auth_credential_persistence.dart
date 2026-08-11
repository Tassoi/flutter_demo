import 'dart:convert';

import 'package:flutter_template/core/storage/secure_storage_key.dart';
import 'package:flutter_template/core/storage/secure_value_store.dart';
import 'package:flutter_template/features/auth/data/auth_credential_persistence.dart';
import 'package:flutter_template/features/auth/domain/auth_credentials.dart';
import 'package:flutter_template/features/auth/domain/auth_failure.dart';

/// 使用项目 [SecureValueStore] 保存单个版本化认证 envelope。
///
/// schema 1 固定包含 access/refresh credential 及两项 UTC 毫秒时间戳。读取会拒绝缺字段、
/// 多字段、错误类型、未知 schema 或不满足凭据模型约束的数据；失败对象和 `toString()`
/// 从不包含原始 JSON。修改字段或时间精度必须新增 schema 与迁移测试，不能就地改变含义。
final class SecureAuthCredentialPersistence
    implements AuthCredentialPersistence {
  /// 使用由应用组装层拥有的 [secureValueStore] 创建认证持久化 adapter。
  ///
  /// 本类型不处置底层存储；插件生命周期与其他安全值由 composition root 统一管理。
  const SecureAuthCredentialPersistence(this._secureValueStore);

  static final SecureStorageKey _sessionKey = SecureStorageKey('auth.session');
  static const int _schemaVersion = 1;
  static const Set<String> _schemaKeys = <String>{
    'schemaVersion',
    'accessCredential',
    'refreshCredential',
    'accessExpiresAtMs',
    'refreshExpiresAtMs',
  };

  final SecureValueStore _secureValueStore;

  @override
  Future<AuthCredentials?> load() async {
    try {
      final encoded = await _secureValueStore.read(_sessionKey);
      if (encoded == null) {
        return null;
      }
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, Object?> ||
          decoded.keys.toSet().difference(_schemaKeys).isNotEmpty ||
          _schemaKeys.difference(decoded.keys.toSet()).isNotEmpty ||
          decoded['schemaVersion'] != _schemaVersion ||
          decoded['accessCredential'] is! String ||
          decoded['refreshCredential'] is! String ||
          decoded['accessExpiresAtMs'] is! int ||
          decoded['refreshExpiresAtMs'] is! int) {
        throw const FormatException('Invalid authentication envelope.');
      }
      return AuthCredentials(
        accessCredential: decoded['accessCredential']! as String,
        refreshCredential: decoded['refreshCredential']! as String,
        accessExpiresAt: DateTime.fromMillisecondsSinceEpoch(
          decoded['accessExpiresAtMs']! as int,
          isUtc: true,
        ),
        refreshExpiresAt: DateTime.fromMillisecondsSinceEpoch(
          decoded['refreshExpiresAtMs']! as int,
          isUtc: true,
        ),
      );
    } on Object {
      // JSON、模型校验和平台异常统一折叠，不能通过错误类型或文本暴露 envelope 内容。
      throw const AuthPersistenceFailure();
    }
  }

  @override
  Future<void> save(AuthCredentials credentials) async {
    final encoded = jsonEncode(<String, Object>{
      'schemaVersion': _schemaVersion,
      'accessCredential': credentials.accessCredential,
      'refreshCredential': credentials.refreshCredential,
      'accessExpiresAtMs': credentials.accessExpiresAt.millisecondsSinceEpoch,
      'refreshExpiresAtMs': credentials.refreshExpiresAt.millisecondsSinceEpoch,
    });
    try {
      // 单键覆盖避免 access 与 refresh 分两次更新造成半新半旧的会话。
      await _secureValueStore.write(_sessionKey, encoded);
    } on Object {
      throw const AuthPersistenceFailure();
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _secureValueStore.delete(_sessionKey);
    } on Object {
      throw const AuthPersistenceFailure();
    }
  }
}
