/// 网络客户端返回给 Repository 的不可变响应。
///
/// 响应只保留 HTTP [statusCode] 和已经由调用方 decoder 转换的 [data]。原始响应
/// header、Cookie、请求信息、Dio Response 与响应正文都不会跨过基础设施边界，减少插件
/// 耦合和敏感数据被意外记录的风险。
final class NetworkResponse<T> {
  /// 创建一个项目自有响应。
  ///
  /// [statusCode] 必须是 100 到 599 之间的有效 HTTP 状态码，否则抛出不包含响应内容的
  /// [ArgumentError]。正式 Dio adapter 只会为成功状态创建本类型；公开构造函数主要供
  /// Repository 测试替身复用。
  NetworkResponse({required this.statusCode, required this.data}) {
    if (statusCode < 100 || statusCode > 599) {
      throw ArgumentError('Status code must be a valid HTTP status code.');
    }
  }

  /// 服务端返回的成功 HTTP 状态码。
  final int statusCode;

  /// 已经由本次请求 decoder 转换的项目数据。
  final T data;

  @override
  String toString() {
    // data 可能含个人数据或业务敏感值，调试输出只保留类型和状态码。
    return 'NetworkResponse<$T>(statusCode: $statusCode)';
  }
}
