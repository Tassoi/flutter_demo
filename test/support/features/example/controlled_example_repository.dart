import 'dart:async';

import 'package:flutter_template/core/network/network_cancellation_token.dart';
import 'package:flutter_template/features/example/domain/example_item.dart';
import 'package:flutter_template/features/example/domain/example_repository.dart';

/// 为示例 Feature 状态与 Widget 测试提供完全可控的 Repository。
///
/// 每次 [loadItem] 都只登记请求并返回未完成 Future；测试必须通过 [requests] 中对应请求
/// 显式完成成功、空或失败结果。该替身不使用 Timer、文件、网络或平台通道，因此可以确定
/// 地验证并发、取消和迟到结果，而不会把测试行为带入 production。
final class ControlledExampleRepository implements ExampleRepository {
  /// 按调用顺序保存尚未或已经完成的请求。
  final List<ControlledExampleRequest> requests = <ControlledExampleRequest>[];

  @override
  Future<ExampleItem?> loadItem({
    required int itemId,
    required NetworkCancellationToken cancellationToken,
  }) {
    final request = ControlledExampleRequest(
      itemId: itemId,
      cancellationToken: cancellationToken,
    );
    requests.add(request);
    return request.future;
  }
}

/// 一次可由测试显式结算的示例项读取。
final class ControlledExampleRequest {
  /// 创建尚未完成的请求记录。
  ControlledExampleRequest({
    required this.itemId,
    required this.cancellationToken,
  });

  /// Controller 交给 Repository 的已验证示例项 ID。
  final int itemId;

  /// 与本次页面状态生命周期绑定的项目取消令牌。
  final NetworkCancellationToken cancellationToken;

  final Completer<ExampleItem?> _completer = Completer<ExampleItem?>();

  /// 本次读取返回给 Controller 的 Future。
  Future<ExampleItem?> get future => _completer.future;

  /// 使用 [item] 完成本次读取；`null` 表示成功但没有匹配项。
  void succeed(ExampleItem? item) {
    _completer.complete(item);
  }

  /// 使用 [error] 和原始 [stackTrace] 让本次读取失败。
  void fail(Object error, StackTrace stackTrace) {
    _completer.completeError(error, stackTrace);
  }
}
