import 'package:flutter_template/core/network/network_cancellation_token.dart';
import 'package:flutter_template/features/example/domain/example_item.dart';

/// 示例项的数据访问契约。
///
/// 接口由 Feature domain 拥有，具体实现可以读取 bundled 数据或使用项目自有网络客户端；
/// 调用方不会接触 Dio、JSON 或平台插件类型。`null` 明确表示读取成功但没有匹配项，不应
/// 转换为错误。实现失败时应优先抛稳定 `AppError`；未知异常会由状态 Controller 最终折叠。
abstract interface class ExampleRepository {
  /// 读取 [itemId] 对应的示例项。
  ///
  /// [itemId] 必须为正整数。[cancellationToken] 与发起读取的页面状态生命周期绑定；实现
  /// 必须尽快响应取消，并且取消后不得继续提交具有业务副作用的操作。返回 Future 完成时
  /// 得到 [ExampleItem] 或成功空值 `null`。本读取是幂等操作，因此页面可以显式重试。
  Future<ExampleItem?> loadItem({
    required int itemId,
    required NetworkCancellationToken cancellationToken,
  });
}
