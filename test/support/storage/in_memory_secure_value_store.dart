import 'package:flutter_template/core/storage/secure_storage_key.dart';
import 'package:flutter_template/core/storage/secure_value_store.dart';

/// 仅供自动化测试使用的内存安全存储。
///
/// 值只驻留于测试进程内存，不提供任何真实加密保证，因此不得在生产组装中使用。
final class InMemorySecureValueStore implements SecureValueStore {
  /// 使用可选的 [initialValues] 创建测试存储，并复制调用方集合。
  InMemorySecureValueStore({
    Map<SecureStorageKey, String> initialValues = const {},
  }) : _values = <String, String>{
         for (final entry in initialValues.entries) entry.key.name: entry.value,
       };

  final Map<String, String> _values;

  @override
  Future<String?> read(SecureStorageKey key) async => _values[key.name];

  @override
  Future<void> write(SecureStorageKey key, String value) async {
    _values[key.name] = value;
  }

  @override
  Future<void> delete(SecureStorageKey key) async {
    _values.remove(key.name);
  }

  @override
  Future<void> clear() async {
    _values.clear();
  }
}
