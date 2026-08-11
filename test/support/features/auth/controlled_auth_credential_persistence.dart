import 'dart:async';

import 'package:flutter_template/features/auth/data/auth_credential_persistence.dart';
import 'package:flutter_template/features/auth/domain/auth_credentials.dart';

/// 可控制延迟与失败的内存认证持久化测试替身。
///
/// 本类型只在测试进程保存 [AuthCredentials]，不提供加密保证且不得用于 production。计数器与
/// gate 用于证明 controller 串行化存储、退出删除和迟到结果顺序；失败对象由测试提供，但
/// production 状态与日志必须折叠它们，不能回显。
final class ControlledAuthCredentialPersistence
    implements AuthCredentialPersistence {
  /// 使用可选初始 [storedCredentials] 创建替身。
  ControlledAuthCredentialPersistence({this.storedCredentials});

  /// 当前模拟安全 envelope；`null` 表示不存在。
  AuthCredentials? storedCredentials;

  final Completer<void> _firstLoadStarted = Completer<void>();
  final Completer<void> _firstSaveStarted = Completer<void>();
  final Completer<void> _firstClearStarted = Completer<void>();

  /// 对应操作在继续前等待的可选 gate。
  Completer<void>? loadGate;
  Completer<void>? saveGate;
  Completer<void>? clearGate;

  /// 对应操作要抛出的可选受控失败。
  Exception? loadFailure;
  Exception? saveFailure;
  Exception? clearFailure;

  /// 各操作实际进入 adapter 的次数。
  var loadCount = 0;
  var saveCount = 0;
  var clearCount = 0;

  /// 第一次读取已经进入持久化边界的确定性信号。
  Future<void> get firstLoadStarted => _firstLoadStarted.future;

  /// 第一次保存已经进入持久化边界的确定性信号。
  Future<void> get firstSaveStarted => _firstSaveStarted.future;

  /// 第一次清理已经进入持久化边界的确定性信号。
  Future<void> get firstClearStarted => _firstClearStarted.future;

  @override
  Future<AuthCredentials?> load() async {
    loadCount++;
    if (!_firstLoadStarted.isCompleted) {
      _firstLoadStarted.complete();
    }
    await loadGate?.future;
    final failure = loadFailure;
    if (failure != null) {
      throw failure;
    }
    return storedCredentials;
  }

  @override
  Future<void> save(AuthCredentials credentials) async {
    saveCount++;
    if (!_firstSaveStarted.isCompleted) {
      _firstSaveStarted.complete();
    }
    await saveGate?.future;
    final failure = saveFailure;
    if (failure != null) {
      throw failure;
    }
    storedCredentials = credentials;
  }

  @override
  Future<void> clear() async {
    clearCount++;
    if (!_firstClearStarted.isCompleted) {
      _firstClearStarted.complete();
    }
    await clearGate?.future;
    final failure = clearFailure;
    if (failure != null) {
      throw failure;
    }
    storedCredentials = null;
  }
}
