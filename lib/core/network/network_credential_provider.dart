/// 单次受保护请求要注入的网络凭据。
///
/// 凭据由 [NetworkCredentialProvider] 在运行时返回，不得来自 Dart define、源码常量或
/// 普通偏好存储。[headerValue] 只供网络 adapter 发送，调用方不得记录、缓存或展示它；
/// 本类型的 [toString] 永远使用固定脱敏标记。
final class NetworkCredential {
  /// 创建一个使用指定 HTTP header 的凭据。
  ///
  /// [headerName] 会统一为小写，必须是合法 HTTP token，且不能是 Cookie、Set-Cookie
  /// 或 Proxy-Authorization；本阶段不提供 Cookie 会话或代理认证。常见值可以使用
  /// `authorization` 或 `x-api-key`。[headerValue] 必须非空、无首尾空格且不含控制字符。
  /// 非法输入抛出的 [ArgumentError] 不回显原始名称或值。
  factory NetworkCredential({
    required String headerName,
    required String headerValue,
  }) {
    final normalizedName = headerName.toLowerCase();
    if (!_credentialHeaderNamePattern.hasMatch(headerName) ||
        _forbiddenCredentialHeaders.contains(normalizedName)) {
      throw ArgumentError('Credential header name is not supported.');
    }
    if (headerValue.isEmpty ||
        headerValue != headerValue.trim() ||
        _credentialControlCharacterPattern.hasMatch(headerValue)) {
      throw ArgumentError('Credential header value is invalid.');
    }
    return NetworkCredential._(
      headerName: normalizedName,
      headerValue: headerValue,
    );
  }

  const NetworkCredential._({
    required this.headerName,
    required this.headerValue,
  });

  /// 传输层要写入的规范化小写 header 名称。
  final String headerName;

  /// 只允许传输层读取的敏感 header 值。
  final String headerValue;

  @override
  String toString() {
    return 'NetworkCredential(headerName: $headerName, '
        'headerValue: [REDACTED])';
  }
}

final _credentialHeaderNamePattern = RegExp(r"^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$");
final _credentialControlCharacterPattern = RegExp(r'[\x00-\x1F\x7F]');
const _forbiddenCredentialHeaders = <String>{
  'cookie',
  'set-cookie',
  'proxy-authorization',
  'host',
  'content-length',
  'transfer-encoding',
  'connection',
  'content-type',
  'accept',
};

/// 为受保护请求按需读取凭据的可替换边界。
///
/// Dio adapter 只在请求明确设置 `requiresCredential` 时调用本接口，并且每个请求重新
/// 读取，不在网络层缓存值。因此凭据轮换立即生效，并发请求也可能并发调用实现。实现应
/// 自己保证并发读取安全，并在不再需要时由其所属存储层管理生命周期。
///
/// 返回 `null` 或抛出异常都会被转换为稳定的 `network.credentials_unavailable`，原始
/// 异常不会进入请求日志。此接口不定义登录、Token 刷新、会话失效或退出行为，这些属于
/// 第二阶段认证模块。
abstract interface class NetworkCredentialProvider {
  /// 读取当前请求可用的凭据；没有凭据时返回 `null`。
  Future<NetworkCredential?> loadCredential();
}

/// 默认不提供任何凭据的安全实现。
///
/// 未启用认证的应用使用本实现。公开请求不会调用它；误把请求标记为需要凭据时会在发送
/// 前得到稳定失败，而不是无认证地访问服务端。
final class NoNetworkCredentialProvider implements NetworkCredentialProvider {
  /// 创建无状态的空凭据提供者。
  const NoNetworkCredentialProvider();

  @override
  Future<NetworkCredential?> loadCredential() async => null;
}
