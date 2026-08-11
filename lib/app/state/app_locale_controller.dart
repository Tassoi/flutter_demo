import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_template/app/localization/app_locale.dart';
import 'package:flutter_template/app/localization/app_locale_persistence.dart';

/// 应用组装层提供的初始语言偏好。
///
/// 正式启动会在创建 ProviderScope 前读取普通偏好并覆盖本值；预览和未接平台存储的测试默认
/// 跟随系统。读取失败不能让应用启动失败，因此也应覆盖或保留该安全默认值。
final appInitialLocalePreferenceProvider = Provider<AppLocalePreference>(
  (_) => AppLocalePreference.system,
  name: 'appInitialLocalePreference',
);

/// 应用语言偏好的可选持久化实现。
///
/// 正式组装层应覆盖为 [PreferenceStoreAppLocalePersistence]。默认 `null` 让纯 Widget 预览
/// 保持可切换但不触碰平台；它不是生产降级存储，也不得用于保存认证或其他敏感数据。
final appLocalePreferencePersistenceProvider =
    Provider<AppLocalePreferencePersistence?>(
      (_) => null,
      name: 'appLocalePreferencePersistence',
    );

/// 当前应用语言策略及其唯一修改入口。
///
/// 同步状态更新让 `MaterialApp` 无需重启即可重建 locale；持久化则由 Controller 串行执行，
/// 避免快速连续选择乱序落盘。调用方应等待 [AppLocaleController.setPreference] 的结果，并在
/// `false` 时只展示安全本地化反馈。
final appLocalePreferenceProvider =
    NotifierProvider<AppLocaleController, AppLocalePreference>(
      AppLocaleController.new,
      name: 'appLocalePreference',
    );

/// 管理应用语言选择、写入顺序和失败回滚的状态单元。
///
/// 每次不同选择会立即更新内存状态，然后进入单一持久化队列。队列中的成功操作按实际完成
/// 顺序更新“最后已保存值”；只有当前最新请求失败时才回滚，较早请求失败不能覆盖用户随后
/// 的选择。Provider 销毁后仍允许已经交给平台的写入自然结束，但不会再修改已释放状态。
final class AppLocaleController extends Notifier<AppLocalePreference> {
  AppLocalePreferencePersistence? _persistence;
  late AppLocalePreference _lastPersisted;
  Future<void> _persistenceTail = Future<void>.value();
  Future<bool>? _latestResult;
  AppLocalePreference? _latestRequested;
  var _requestGeneration = 0;
  var _isDisposed = false;

  /// 使用组装层提供的已验证初值建立同步状态。
  @override
  AppLocalePreference build() {
    final AppLocalePreference initial = ref.watch(
      appInitialLocalePreferenceProvider,
    );
    _persistence = ref.watch(appLocalePreferencePersistenceProvider);
    _lastPersisted = initial;
    _isDisposed = false;
    ref.onDispose(() {
      _isDisposed = true;
    });
    return initial;
  }

  /// 立即切换到 [preference]，并按顺序保存该选择。
  ///
  /// 返回 `true` 表示本次状态已经持久化，或当前预览环境明确没有持久化实现；返回 `false`
  /// 表示写入失败且最新 UI 状态已经回滚到最后一次成功值。重复选择当前值不会产生额外 I/O；
  /// 如果同一值仍在写入，则多个调用方会共享同一个结果。
  ///
  /// 本方法不会抛出存储异常或记录偏好值。交互层不得据此重试循环；应让用户决定是否再次
  /// 选择，避免平台存储持续失败时制造写入风暴。
  Future<bool> setPreference(AppLocalePreference preference) {
    if (state == preference) {
      if (_latestRequested == preference && _latestResult != null) {
        return _latestResult!;
      }
      return Future<bool>.value(true);
    }

    state = preference;
    final int generation = ++_requestGeneration;
    final Future<bool> result = _persist(
      preference: preference,
      generation: generation,
    );
    _latestRequested = preference;
    _latestResult = result;
    return result;
  }

  Future<bool> _persist({
    required AppLocalePreference preference,
    required int generation,
  }) async {
    final Future<void> operation = _persistenceTail.then((_) async {
      await _persistence?.save(preference);
      _lastPersisted = preference;
    });
    _persistenceTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );

    try {
      await operation;
      return true;
    } on Object {
      // 较早请求失败时，用户可能已经选择了新语言。只有最新代次仍对应当前状态时才回滚，
      // 否则旧失败会把随后成功或仍在排队的选择错误覆盖。
      if (!_isDisposed &&
          generation == _requestGeneration &&
          state == preference) {
        state = _lastPersisted;
      }
      return false;
    }
  }
}
