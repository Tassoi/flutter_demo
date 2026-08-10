import 'package:flutter_template/core/network/network_cancellation_token.dart';
import 'package:flutter_template/core/network/network_client.dart';
import 'package:flutter_template/core/network/network_request.dart';
import 'package:flutter_template/features/example/domain/example_item.dart';
import 'package:flutter_template/features/example/domain/example_repository.dart';

/// 通过项目自有 [NetworkClient] 读取示例项的 Repository 实现。
///
/// 本类型只构造稳定 operation、相对 endpoint 并校验响应形状，不依赖 Dio 或任何插件
/// 类型。请求是公开、幂等的 GET，不读取认证凭据。传入的 [NetworkClient] 生命周期由
/// `app/` 组装层拥有；Repository 不关闭共享客户端，页面销毁只通过取消令牌终止本次读取。
///
/// 服务端成功响应可以为 `null`，或包含 `id`、`title`、`description` 的 JSON object。
/// 缺字段、类型错误、ID 不匹配或领域文字校验失败都会由 NetworkClient decoder 边界转换
/// 为稳定解析错误，原始 payload 不进入 UI 或日志。
final class NetworkExampleRepository implements ExampleRepository {
  /// 创建使用 [networkClient] 的示例 Repository。
  const NetworkExampleRepository({required NetworkClient networkClient})
    : _networkClient = networkClient;

  final NetworkClient _networkClient;

  /// 读取 [itemId] 对应的公开示例项。
  ///
  /// [itemId] 必须为正整数；[cancellationToken] 原样传给共享 NetworkClient。方法发送一次
  /// GET，不自动重试、不读取凭据，也不接管客户端释放。成功空响应返回 `null`；传输错误
  /// 保持既有 `AppError`，无效响应由客户端 decoder 边界转换为稳定解析错误。
  @override
  Future<ExampleItem?> loadItem({
    required int itemId,
    required NetworkCancellationToken cancellationToken,
  }) async {
    if (itemId <= 0) {
      throw ArgumentError('Example item ID must be positive.');
    }

    final response = await _networkClient.send<ExampleItem?>(
      NetworkRequest(
        operation: 'example.load_item',
        method: NetworkMethod.get,
        path: 'examples/$itemId',
      ),
      cancellationToken: cancellationToken,
      decoder: (payload) => _decodeItem(payload, expectedItemId: itemId),
    );
    return response.data;
  }
}

ExampleItem? _decodeItem(Object? payload, {required int expectedItemId}) {
  if (payload == null) {
    return null;
  }
  if (payload is! Map<String, Object?>) {
    throw const FormatException('Example item payload must be an object.');
  }

  final id = payload['id'];
  final title = payload['title'];
  final description = payload['description'];
  if (id is! int ||
      id != expectedItemId ||
      title is! String ||
      description is! String) {
    // 响应字段可能含线上数据；异常只描述固定形状问题，不回显 ID、标题或说明。
    throw const FormatException('Example item payload has an invalid shape.');
  }

  try {
    return ExampleItem(id: id, title: title, description: description);
  } on ArgumentError {
    // 领域校验错误同样折叠为固定解析失败，避免被拒正文通过异常文本跨越数据边界。
    throw const FormatException('Example item payload has invalid values.');
  }
}
