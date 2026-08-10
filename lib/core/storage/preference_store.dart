import 'package:flutter_template/core/error/app_error.dart';
import 'package:flutter_template/core/storage/preference_key.dart';

/// 可恢复、非敏感应用偏好的项目自有存储契约。
///
/// 接口只支持 `bool`、`int`、有限 `double`、`String` 和 `List<String>`，对应 Android/iOS
/// 普通偏好能够稳定表达的类型。每次读取都显式要求默认值；键不存在时返回默认值，平台
/// 或类型失败则抛 [StorageReadError]，不会把失败伪装成“尚未保存”。
///
/// 本接口不得保存 Token、密码、Cookie、私钥、认证会话或其他需要加密的值。此类数据必须
/// 使用 `SecureValueStore`。普通偏好插件不保证关键数据事务性或永久持久化，因此业务事实、
/// 支付状态和不可恢复数据也不属于本接口。
abstract interface class PreferenceStore {
  /// 读取布尔偏好；键不存在时返回 [defaultValue]。
  Future<bool> readBool(PreferenceKey key, {required bool defaultValue});

  /// 读取整数偏好；键不存在时返回 [defaultValue]。
  Future<int> readInt(PreferenceKey key, {required int defaultValue});

  /// 读取有限浮点偏好；键不存在时返回 [defaultValue]。
  ///
  /// 非有限默认值属于调用方编程错误，实现应抛出固定 [ArgumentError]。
  Future<double> readDouble(PreferenceKey key, {required double defaultValue});

  /// 读取字符串偏好；键不存在时返回 [defaultValue]。
  Future<String> readString(PreferenceKey key, {required String defaultValue});

  /// 读取字符串列表；键不存在时返回 [defaultValue] 的不可修改副本。
  ///
  /// 实现也必须复制已存列表，避免调用方修改返回对象时绕过异步写入边界。
  Future<List<String>> readStringList(
    PreferenceKey key, {
    required List<String> defaultValue,
  });

  /// 写入布尔偏好；平台拒绝写入时抛 [StorageWriteError]。
  Future<void> writeBool(PreferenceKey key, bool value);

  /// 写入整数偏好；平台拒绝写入时抛 [StorageWriteError]。
  Future<void> writeInt(PreferenceKey key, int value);

  /// 写入有限浮点偏好。
  ///
  /// 非有限 [value] 在接触插件前以固定 [ArgumentError] 拒绝；平台失败映射为
  /// [StorageWriteError]。
  Future<void> writeDouble(PreferenceKey key, double value);

  /// 写入字符串偏好；平台拒绝写入时抛 [StorageWriteError]。
  Future<void> writeString(PreferenceKey key, String value);

  /// 复制并写入字符串列表；平台拒绝写入时抛 [StorageWriteError]。
  Future<void> writeStringList(PreferenceKey key, List<String> value);

  /// 删除一个键；键不存在时为空操作，平台失败时抛 [StorageDeleteError]。
  Future<void> remove(PreferenceKey key);

  /// 清理当前实现拥有的普通偏好命名空间。
  ///
  /// 实现不得调用无范围的平台全量清理，也不得删除原生代码或其他插件写入的值。清理不是
  /// 跨进程事务，并发调用方应等待冲突操作完成；平台失败时抛 [StorageClearError]。
  Future<void> clear();
}
