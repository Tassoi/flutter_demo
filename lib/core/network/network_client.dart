import 'dart:async';

import 'package:flutter_template/core/network/network_cancellation_token.dart';
import 'package:flutter_template/core/network/network_request.dart';
import 'package:flutter_template/core/network/network_response.dart';

/// 把已完成基础 JSON 转换的响应 payload 映射为 Repository 所需类型。
///
/// decoder 可以同步或异步返回。它应只执行数据形状校验和 DTO 构造；业务规则应留在
/// Repository/domain。decoder 抛出的任意异常都会在网络边界折叠为
/// `NetworkResponseParseError`，原始响应与异常不会进入 UI 或日志。
typedef NetworkResponseDecoder<T> = FutureOr<T> Function(Object? payload);

/// Feature 与 Repository 使用的项目自有网络客户端契约。
///
/// 接口只暴露项目类型，不包含 Dio、Response、Options 或 CancelToken。默认实现负责
/// Base URL、公共 header、超时、凭据、取消、JSON 转换、错误映射和安全日志；调用方只
/// 描述一次请求并提供明确 decoder。
abstract interface class NetworkClient {
  /// 发送 [request]，解析成功 payload 并返回项目自有响应。
  ///
  /// [cancellationToken] 可省略；提供后，调用其 `cancel()` 会取消所有仍在使用同一令牌
  /// 的请求。非成功状态、超时、连接失败、取消、凭据缺失和解析失败只抛项目自有
  /// `AppError` 子类型。请求模型本身非法会在创建 [NetworkRequest] 时抛 [ArgumentError]。
  Future<NetworkResponse<T>> send<T>(
    NetworkRequest request, {
    required NetworkResponseDecoder<T> decoder,
    NetworkCancellationToken? cancellationToken,
  });

  /// 取消当前活跃请求并释放底层连接资源。
  ///
  /// 关闭操作必须幂等。关闭后再次 [send] 属于生命周期编程错误并抛出固定 [StateError]，
  /// 不会伪装成可重试的网络错误。
  void close();
}
