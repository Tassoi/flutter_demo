import 'package:flutter_template/app/localization/app_locale.dart';
import 'package:flutter_template/core/error/app_error.dart';
import 'package:flutter_template/core/storage/preference_key.dart';
import 'package:flutter_template/core/storage/preference_store.dart';

/// 应用语言偏好的最小持久化边界。
///
/// Controller 只依赖此接口，不接触普通存储插件、物理键或序列化值。实现必须把语言偏好视为
/// 可恢复且非敏感的数据；读取失败可以由启动层降级为跟随系统，写入失败则由交互层向用户提供
/// 安全反馈，不能转存到安全凭据存储。
abstract interface class AppLocalePreferencePersistence {
  /// 读取上次显式选择；不存在或值已过期时返回跟随系统。
  Future<AppLocalePreference> load();

  /// 保存 [preference]。
  ///
  /// 跟随系统必须删除显式值，而不是写入设备当前语言，否则设备语言变化后应用会错误地保持
  /// 旧 locale。底层失败应继续以稳定存储错误抛出，不得伪装为成功。
  Future<void> save(AppLocalePreference preference);
}

/// 平台普通偏好在启动时不可创建时使用的显式失败实现。
///
/// 正式应用用本实现区分“存储不可用”和测试预览的无持久化模式。读取仍安全回到跟随系统；
/// 每次写入都返回不含插件详情的 [StorageWriteError]，使 Controller 回滚并让 UI 展示安全反馈，
/// 不能把只在内存生效的选择伪装为已经保存。
final class UnavailableAppLocalePreferencePersistence
    implements AppLocalePreferencePersistence {
  /// 创建无状态的不可用持久化边界。
  const UnavailableAppLocalePreferencePersistence();

  @override
  Future<AppLocalePreference> load() async => AppLocalePreference.system;

  @override
  Future<void> save(AppLocalePreference preference) async {
    throw const StorageWriteError();
  }
}

/// 使用项目 [PreferenceStore] 保存应用语言的默认实现。
///
/// 本实现只持有项目自有普通偏好接口，shared_preferences 类型仍限制在 core adapter 内。
/// 存储协议使用固定 `en`/`zh` 值；未知值由 [parseStoredAppLocalePreference] 降级处理。
final class PreferenceStoreAppLocalePersistence
    implements AppLocalePreferencePersistence {
  /// 使用 [store] 创建语言偏好持久化实现。
  const PreferenceStoreAppLocalePersistence(this._store);

  static final PreferenceKey _preferenceKey = PreferenceKey(
    'appearance.locale',
  );

  final PreferenceStore _store;

  @override
  Future<AppLocalePreference> load() async {
    final String stored = await _store.readString(
      _preferenceKey,
      defaultValue: '',
    );
    return parseStoredAppLocalePreference(stored);
  }

  @override
  Future<void> save(AppLocalePreference preference) {
    if (preference == AppLocalePreference.system) {
      return _store.remove(_preferenceKey);
    }
    return _store.writeString(_preferenceKey, preference.storageValue);
  }
}
