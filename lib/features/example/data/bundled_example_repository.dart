import 'package:flutter_template/core/error/app_error.dart';
import 'package:flutter_template/core/network/network_cancellation_token.dart';
import 'package:flutter_template/features/example/domain/example_item.dart';
import 'package:flutter_template/features/example/domain/example_repository.dart';

/// 从模板内置常量提供一个可离线运行的示例项。
///
/// 该实现是脚手架默认值：它不访问网络、存储、文件、时钟或平台通道，因此占位
/// `.invalid` API 配置也能直接运行。它不是缓存层或 Mock 服务；真实项目应在应用组装点
/// 使用 [ExampleRepository] override 替换为自己的实现，并可完整删除本 Feature。
final class BundledExampleRepository implements ExampleRepository {
  /// 创建不持有资源和动态状态的 bundled Repository。
  const BundledExampleRepository();

  static final Map<int, ExampleItem> _items =
      Map<int, ExampleItem>.unmodifiable(<int, ExampleItem>{
        1: ExampleItem(
          id: 1,
          title: 'Example record',
          description: 'A neutral record included with the starter project.',
        ),
      });

  /// 从只读 bundled 集合读取 [itemId]。
  ///
  /// 已取消时抛出稳定 [NetworkCancelledError]；缺少匹配项返回 `null`。本实现没有需要
  /// 释放的资源，也不会在进程内缓存调用结果之外的动态状态。
  @override
  Future<ExampleItem?> loadItem({
    required int itemId,
    required NetworkCancellationToken cancellationToken,
  }) async {
    if (itemId <= 0) {
      throw ArgumentError('Example item ID must be positive.');
    }
    if (cancellationToken.isCancelled) {
      throw const NetworkCancelledError();
    }
    return _items[itemId];
  }
}
