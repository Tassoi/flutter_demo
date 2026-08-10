import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_template/core/error/app_error.dart';
import 'package:flutter_template/core/storage/secure_storage_key.dart';
import 'package:flutter_template/core/storage/secure_value_store.dart';
import 'package:flutter_template/core/storage/storage_error_mapper.dart';

/// 使用 flutter_secure_storage 的唯一敏感值 adapter。
///
/// Android 使用独立 [androidStorageNamespace]、显式固定的 RSA-OAEP 包装与 AES-GCM 数据
/// 加密，不启用生物识别，并关闭插件遇错自动清空以避免静默丢失；算法迁移启用加密备份
/// 保护。iOS 使用
/// 独立 [appleService]、仅本设备且仅解锁时可访问的 Keychain 项，不同步到 iCloud。
///
/// Feature 与 Repository 只能依赖 [SecureValueStore]。本 adapter 不实现登录、刷新 Token、
/// 认证状态机或普通偏好降级，也不会记录键、值或插件异常。
final class FlutterSecureValueStore implements SecureValueStore {
  /// 创建生产安全存储，并把同步插件构造失败映射为 [StorageInitializationError]。
  ///
  /// [storageFactory] 只用于 adapter 单元测试。它会收到生产路径使用的固定平台选项，
  /// 使测试可以验证加密、迁移和 Keychain 约束。生产调用方必须省略；改变 namespace、
  /// service、算法或 Keychain accessibility 需要迁移评估。
  factory FlutterSecureValueStore({
    @visibleForTesting
    FlutterSecureStorage Function({
      required AndroidOptions androidOptions,
      required IOSOptions iosOptions,
    })?
    storageFactory,
  }) {
    try {
      final storage =
          storageFactory?.call(
            androidOptions: _androidOptions,
            iosOptions: _iosOptions,
          ) ??
          _createPlatformStorage();
      return FlutterSecureValueStore._(storage);
    } on Object catch (error) {
      throw _errorMapper.fromInitialization(error);
    }
  }

  const FlutterSecureValueStore._(this._storage);

  /// 所有平台安全键使用的稳定前缀。
  ///
  /// 键前缀、平台 namespace 与 Apple service 都是持久化身份的一部分，不能随应用展示名
  /// 或环境变化。修改时必须先设计可回滚迁移。
  static const String keyPrefix = 'app.secure.';

  /// Android Keystore、配置标记和密文文件共用的隔离 namespace。
  static const String androidStorageNamespace = 'app_secure_storage';

  /// iOS Keychain 项使用的稳定 `kSecAttrService`。
  static const String appleService = 'app.secure_storage';

  static const _errorMapper = StorageErrorMapper();
  static const _androidOptions = AndroidOptions(
    storageNamespace: androidStorageNamespace,
    resetOnError: false,
    migrateOnAlgorithmChange: true,
    migrateWithBackup: true,
    enforceBiometrics: false,
    keyCipherAlgorithm:
        KeyCipherAlgorithm.RSA_ECB_OAEPwithSHA_256andMGF1Padding,
    storageCipherAlgorithm: StorageCipherAlgorithm.AES_GCM_NoPadding,
  );
  static const _iosOptions = IOSOptions(
    accountName: appleService,
    accessibility: KeychainAccessibility.unlocked_this_device,
    synchronizable: false,
  );

  final FlutterSecureStorage _storage;

  static FlutterSecureStorage _createPlatformStorage() {
    return const FlutterSecureStorage(
      aOptions: _androidOptions,
      iOptions: _iosOptions,
    );
  }

  @override
  Future<String?> read(SecureStorageKey key) async {
    try {
      return await _storage.read(key: _physicalKey(key));
    } on Object catch (error) {
      throw _errorMapper.fromRead(error);
    }
  }

  @override
  Future<void> write(SecureStorageKey key, String value) async {
    try {
      await _storage.write(key: _physicalKey(key), value: value);
    } on Object catch (error) {
      throw _errorMapper.fromWrite(error);
    }
  }

  @override
  Future<void> delete(SecureStorageKey key) async {
    try {
      await _storage.delete(key: _physicalKey(key));
    } on Object catch (error) {
      throw _errorMapper.fromDelete(error);
    }
  }

  @override
  Future<void> clear() async {
    try {
      // 插件实例独占 Android namespace 与 Apple service，因此 deleteAll 不会越过边界。
      await _storage.deleteAll();
    } on Object catch (error) {
      throw _errorMapper.fromClear(error);
    }
  }

  String _physicalKey(SecureStorageKey key) => '$keyPrefix${key.name}';
}
