import 'package:flutter/foundation.dart';
import 'package:flutter_template/core/error/app_error.dart';
import 'package:flutter_template/core/storage/preference_key.dart';
import 'package:flutter_template/core/storage/preference_store.dart';
import 'package:flutter_template/core/storage/storage_error_mapper.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 使用 [SharedPreferencesAsync] 的唯一普通偏好 adapter。
///
/// Feature 与 Repository 只能依赖 [PreferenceStore]，不得导入本文件或 shared_preferences。
/// adapter 使用异步无缓存 API，确保每次读取都观察平台当前值；它不会把普通偏好提升为
/// 关键数据存储，也不会提供认证凭据的降级路径。
///
/// 逻辑键统一加上 [namespacePrefix]。清理时先读取平台键快照，再使用明确 allow-list 删除
/// 当前 namespace，避免误删原生代码或其他插件的数据。多个 adapter 实例或外部原生写入
/// 仍可能并发变化，因此 `clear()` 不是跨进程事务；调用方必须等待冲突操作。
final class SharedPreferencesPreferenceStore implements PreferenceStore {
  /// 创建生产 adapter，并把同步插件构造失败映射为 [StorageInitializationError]。
  ///
  /// [preferencesFactory] 只用于 adapter 单元测试注入可控插件替身。生产调用方必须省略；
  /// 插件实例不会通过 [PreferenceStore] 暴露给 Feature。
  factory SharedPreferencesPreferenceStore({
    @visibleForTesting SharedPreferencesAsync Function()? preferencesFactory,
  }) {
    try {
      final preferences =
          (preferencesFactory ?? () => SharedPreferencesAsync())();
      return SharedPreferencesPreferenceStore._(preferences);
    } on Object catch (error) {
      throw _errorMapper.fromInitialization(error);
    }
  }

  const SharedPreferencesPreferenceStore._(this._preferences);

  /// 该 adapter 在平台普通偏好文件中独占的物理键前缀。
  ///
  /// 更改此值会让既有偏好不可见，必须附带显式迁移；应用重命名不应自动改变它。
  static const String namespacePrefix = 'app.preferences.';

  static const _errorMapper = StorageErrorMapper();

  final SharedPreferencesAsync _preferences;

  @override
  Future<bool> readBool(PreferenceKey key, {required bool defaultValue}) =>
      _read(
        () async =>
            await _preferences.getBool(_physicalKey(key)) ?? defaultValue,
      );

  @override
  Future<int> readInt(PreferenceKey key, {required int defaultValue}) => _read(
    () async => await _preferences.getInt(_physicalKey(key)) ?? defaultValue,
  );

  @override
  Future<double> readDouble(
    PreferenceKey key, {
    required double defaultValue,
  }) async {
    if (!defaultValue.isFinite) {
      throw ArgumentError('Preference doubles must be finite.');
    }
    return _read(() async {
      final stored = await _preferences.getDouble(_physicalKey(key));
      if (stored == null) {
        return defaultValue;
      }
      if (!stored.isFinite) {
        // 本 adapter 会阻止新写入非有限值，但旧版本、原生代码或其他进程仍可能留下
        // 非法平台数据。读取边界必须拒绝它，不能让 NaN/Infinity 污染布局或业务计算。
        throw const StorageReadError();
      }
      return stored;
    });
  }

  @override
  Future<String> readString(
    PreferenceKey key, {
    required String defaultValue,
  }) => _read(
    () async => await _preferences.getString(_physicalKey(key)) ?? defaultValue,
  );

  @override
  Future<List<String>> readStringList(
    PreferenceKey key, {
    required List<String> defaultValue,
  }) {
    // 默认列表在首次 await 前复制，调用方即使随后修改原对象也不会改变本次读取结果。
    final fallback = List<String>.unmodifiable(defaultValue);
    return _read(() async {
      final stored = await _preferences.getStringList(_physicalKey(key));
      return List<String>.unmodifiable(stored ?? fallback);
    });
  }

  @override
  Future<void> writeBool(PreferenceKey key, bool value) =>
      _write(() => _preferences.setBool(_physicalKey(key), value));

  @override
  Future<void> writeInt(PreferenceKey key, int value) =>
      _write(() => _preferences.setInt(_physicalKey(key), value));

  @override
  Future<void> writeDouble(PreferenceKey key, double value) async {
    if (!value.isFinite) {
      throw ArgumentError('Preference doubles must be finite.');
    }
    await _write(() => _preferences.setDouble(_physicalKey(key), value));
  }

  @override
  Future<void> writeString(PreferenceKey key, String value) =>
      _write(() => _preferences.setString(_physicalKey(key), value));

  @override
  Future<void> writeStringList(PreferenceKey key, List<String> value) {
    // 插件调用可能异步读取列表；先冻结副本，避免调用方并发修改造成写入内容不确定。
    final frozenValue = List<String>.unmodifiable(value);
    return _write(
      () => _preferences.setStringList(_physicalKey(key), frozenValue),
    );
  }

  @override
  Future<void> remove(PreferenceKey key) =>
      _delete(() => _preferences.remove(_physicalKey(key)));

  @override
  Future<void> clear() => _clear(() async {
    final platformKeys = await _preferences.getKeys();
    final ownedKeys =
        platformKeys.where((key) => key.startsWith(namespacePrefix)).toSet();
    if (ownedKeys.isEmpty) {
      // 空 allow-list 的插件语义可能随实现变化；直接返回可证明不会退化为无范围清理。
      return;
    }
    await _preferences.clear(allowList: ownedKeys);
  });

  String _physicalKey(PreferenceKey key) => '$namespacePrefix${key.name}';

  Future<T> _read<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on Object catch (error) {
      throw _errorMapper.fromRead(error);
    }
  }

  Future<void> _write(Future<void> Function() operation) async {
    try {
      await operation();
    } on Object catch (error) {
      throw _errorMapper.fromWrite(error);
    }
  }

  Future<void> _delete(Future<void> Function() operation) async {
    try {
      await operation();
    } on Object catch (error) {
      throw _errorMapper.fromDelete(error);
    }
  }

  Future<void> _clear(Future<void> Function() operation) async {
    try {
      await operation();
    } on Object catch (error) {
      throw _errorMapper.fromClear(error);
    }
  }
}
