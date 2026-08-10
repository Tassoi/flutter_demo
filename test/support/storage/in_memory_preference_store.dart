import 'package:flutter_template/core/error/app_error.dart';
import 'package:flutter_template/core/storage/preference_key.dart';
import 'package:flutter_template/core/storage/preference_store.dart';

/// 仅供自动化测试使用的内存普通偏好存储。
///
/// 实现遵守生产契约的默认值、类型错误和集合复制语义，但不会触碰平台通道或磁盘。
final class InMemoryPreferenceStore implements PreferenceStore {
  /// 使用可选的 [initialValues] 创建测试存储。
  ///
  /// 初始值只允许普通偏好支持的五种类型；非法值会以不回显内容的 [ArgumentError]
  /// 失败，避免测试替身表现出生产实现无法提供的能力。
  InMemoryPreferenceStore({Map<PreferenceKey, Object> initialValues = const {}})
    : _values = <String, Object>{
        for (final entry in initialValues.entries)
          entry.key.name: _copySupportedValue(entry.value),
      };

  final Map<String, Object> _values;

  @override
  Future<bool> readBool(
    PreferenceKey key, {
    required bool defaultValue,
  }) async => _readScalar<bool>(key, defaultValue);

  @override
  Future<int> readInt(PreferenceKey key, {required int defaultValue}) async =>
      _readScalar<int>(key, defaultValue);

  @override
  Future<double> readDouble(
    PreferenceKey key, {
    required double defaultValue,
  }) async {
    if (!defaultValue.isFinite) {
      throw ArgumentError('Preference doubles must be finite.');
    }
    return _readScalar<double>(key, defaultValue);
  }

  @override
  Future<String> readString(
    PreferenceKey key, {
    required String defaultValue,
  }) async => _readScalar<String>(key, defaultValue);

  @override
  Future<List<String>> readStringList(
    PreferenceKey key, {
    required List<String> defaultValue,
  }) async {
    final value = _values[key.name];
    if (value == null) {
      return List<String>.unmodifiable(defaultValue);
    }
    if (value is! List<String>) {
      throw const StorageReadError();
    }
    return List<String>.unmodifiable(value);
  }

  @override
  Future<void> writeBool(PreferenceKey key, bool value) async {
    _values[key.name] = value;
  }

  @override
  Future<void> writeInt(PreferenceKey key, int value) async {
    _values[key.name] = value;
  }

  @override
  Future<void> writeDouble(PreferenceKey key, double value) async {
    if (!value.isFinite) {
      throw ArgumentError('Preference doubles must be finite.');
    }
    _values[key.name] = value;
  }

  @override
  Future<void> writeString(PreferenceKey key, String value) async {
    _values[key.name] = value;
  }

  @override
  Future<void> writeStringList(PreferenceKey key, List<String> value) async {
    _values[key.name] = List<String>.unmodifiable(value);
  }

  @override
  Future<void> remove(PreferenceKey key) async {
    _values.remove(key.name);
  }

  @override
  Future<void> clear() async {
    _values.clear();
  }

  T _readScalar<T>(PreferenceKey key, T defaultValue) {
    final value = _values[key.name];
    if (value == null) {
      return defaultValue;
    }
    if (value is! T) {
      throw const StorageReadError();
    }
    return value as T;
  }

  static Object _copySupportedValue(Object value) {
    if (value is bool || value is int || value is String) {
      return value;
    }
    if (value is double && value.isFinite) {
      return value;
    }
    if (value is List<String>) {
      return List<String>.unmodifiable(value);
    }
    throw ArgumentError('Initial preference value type is not supported.');
  }
}
