import 'package:flutter_template/core/error/app_error.dart';
import 'package:flutter_template/core/storage/secure_storage_key.dart';

/// 凭据、密钥和其他敏感字符串使用的项目自有安全存储契约。
///
/// 生产实现必须使用 Android Keystore 支持的加密存储或 iOS Keychain，并把插件类型限制在
/// adapter 文件中。接口不定义登录、Token 刷新、会话失效或认证状态机；这些属于第二阶段
/// 认证模块。它也不是数据库，不提供查询、事务或对象序列化。
abstract interface class SecureValueStore {
  /// 读取 [key] 对应的敏感值；不存在时返回 `null`。
  ///
  /// 平台不可用、解密失败或数据损坏时抛 [StorageReadError]，不会把失败折叠成 `null`。
  Future<String?> read(SecureStorageKey key);

  /// 写入或替换 [key] 对应的敏感 [value]。
  ///
  /// Future 只表示插件已完成本次平台调用；它不承诺跨设备同步或业务事务。失败时抛
  /// [StorageWriteError]，调用方不得降级写入普通偏好。
  Future<void> write(SecureStorageKey key, String value);

  /// 删除一个敏感值；键不存在时为空操作，平台失败时抛 [StorageDeleteError]。
  Future<void> delete(SecureStorageKey key);

  /// 清理当前 adapter 独占 service/namespace 中的全部敏感值。
  ///
  /// 该操作不可恢复且不保证事务性。调用方只能在明确的业务流程中使用；平台失败时抛
  /// [StorageClearError]。
  Future<void> clear();
}
