import 'dart:collection';

/// 网络层支持的 HTTP 方法。
///
/// 枚举有意只覆盖当前 JSON API 的常用方法，不暴露 Dio 的字符串方法或 Options。
/// 如果后续确实需要上传、下载或流式请求，应通过新的明确契约扩展，而不是让 Feature
/// 直接传递插件参数。
enum NetworkMethod {
  /// 读取资源，不允许携带请求体。
  get,

  /// 创建资源或触发服务端动作。
  post,

  /// 完整替换资源。
  put,

  /// 部分更新资源。
  patch,

  /// 删除资源。
  delete;

  /// 发送到传输层的标准大写方法名。
  String get wireName => name.toUpperCase();
}

/// 由 Repository 交给 [NetworkClient] 的不可变请求描述。
///
/// 本类型只接受相对 endpoint、非敏感 query/header 和 JSON object/array 请求体。绝对
/// URL、路径穿越、URL 中的凭据参数、认证 header 以及不可 JSON 编码的对象会在接触 Dio
/// 前被拒绝。这样 Feature 无法绕过集中 Base URL、凭据提供者或安全日志边界。
///
/// [operation] 是日志与诊断使用的稳定小写点分名称，例如 `catalog.load_items`。它不能
/// 包含用户 ID、搜索词或其他动态值；日志从不读取 [path]、[queryParameters]、[headers]
/// 或 [body]。构造过程会深拷贝并冻结集合，调用方后续修改原始对象不会改变待发送内容。
final class NetworkRequest {
  NetworkRequest._({
    required this.operation,
    required this.method,
    required this.path,
    required this.queryParameters,
    required this.headers,
    required this.body,
    required this.requiresCredential,
  });

  /// 创建一个经过安全约束验证的请求。
  ///
  /// [path] 必须相对已配置的 Base URL，且不得包含 query、fragment、反斜杠或编码后的
  /// `.`、`..`、`/`、`\\`、`?`、`#`、`%`。query 必须通过 [queryParameters]
  /// 单独提供，使传输层能够确定地编码。
  ///
  /// [headers] 只用于非敏感业务 header。`Authorization`、Cookie、API key 等凭据必须
  /// 通过 [NetworkCredentialProvider] 注入；已知敏感 header 会被直接拒绝。
  /// [body] 为 `null` 或 JSON object/array，GET 请求不得携带 body。
  ///
  /// 任一输入不满足契约时抛出不回显原始值的 [ArgumentError]。这是调用方编程错误，
  /// 不会被转换为可重试的 [AppError]。
  factory NetworkRequest({
    required String operation,
    required NetworkMethod method,
    required String path,
    Map<String, Object?> queryParameters = const {},
    Map<String, String> headers = const {},
    Object? body,
    bool requiresCredential = false,
  }) {
    if (!_operationPattern.hasMatch(operation)) {
      throw ArgumentError(
        'Operation must be a stable lowercase dot-separated name.',
      );
    }
    _validateRelativePath(path);
    if (method == NetworkMethod.get && body != null) {
      throw ArgumentError('GET requests cannot contain a request body.');
    }

    return NetworkRequest._(
      operation: operation,
      method: method,
      path: path,
      queryParameters: _freezeQueryParameters(queryParameters),
      headers: _freezeHeaders(headers),
      body: _freezeBody(body),
      requiresCredential: requiresCredential,
    );
  }

  static final _operationPattern = RegExp(
    r'^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*$',
  );

  /// 用于安全日志聚合的稳定操作名。
  final String operation;

  /// 请求使用的项目自有 HTTP 方法。
  final NetworkMethod method;

  /// 相对于客户端 Base URL 的 endpoint。
  final String path;

  /// 已深冻结、由传输层统一编码的非敏感 query 参数。
  final Map<String, Object?> queryParameters;

  /// 已验证并统一为小写名称的非敏感请求 header。
  final Map<String, String> headers;

  /// 已深冻结的 JSON object/array；`null` 表示没有请求体。
  final Object? body;

  /// 是否要求凭据提供者为本次请求注入凭据。
  final bool requiresCredential;

  @override
  String toString() {
    // 请求对象可能被调试工具隐式格式化，因此只暴露稳定元数据，不输出任何线上的数据。
    return 'NetworkRequest(operation: $operation, method: ${method.name}, '
        'requiresCredential: $requiresCredential)';
  }
}

final _headerNamePattern = RegExp(r"^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$");
final _controlCharacterPattern = RegExp(r'[\x00-\x1F\x7F]');
final _queryKeyForbiddenCharacterPattern = RegExp(r'[\x00-\x20\x7F&=#]');
final _hexPairPattern = RegExp(r'%[0-9a-fA-F]{2}');
final _nonAlphaNumericPattern = RegExp(r'[^a-z0-9]');

const _sensitiveHeaderNames = <String>{
  'authorization',
  'proxy-authorization',
  'cookie',
  'set-cookie',
  'token',
  'x-token',
  'x-auth-token',
  'x-access-token',
  'x-refresh-token',
  'x-client-secret',
  'x-api-key',
  'api-key',
  'host',
  'content-length',
  'transfer-encoding',
  'connection',
  'content-type',
};
const _sensitiveQueryNames = <String>{
  'authorization',
  'token',
  'authtoken',
  'bearertoken',
  'accesstoken',
  'refreshtoken',
  'idtoken',
  'apitoken',
  'oauthtoken',
  'apikey',
  'clientsecret',
  'password',
  'secret',
  'credential',
  'session',
  'sessionid',
};
const _maxJsonDepth = 64;

void _validateRelativePath(String path) {
  if (path != path.trim() ||
      path.startsWith('/') ||
      path.contains('\\') ||
      _controlCharacterPattern.hasMatch(path)) {
    throw ArgumentError('Request path must be a safe relative endpoint.');
  }

  final uri = Uri.tryParse(path);
  if (uri == null ||
      uri.isAbsolute ||
      uri.hasAuthority ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw ArgumentError('Request path must be a safe relative endpoint.');
  }

  for (final rawSegment in path.split('/')) {
    late final String decodedSegment;
    try {
      decodedSegment = Uri.decodeComponent(rawSegment);
    } on Object {
      throw ArgumentError('Request path must be a safe relative endpoint.');
    }

    // 服务端和代理可能在不同阶段再次解码。拒绝解码后仍含百分号转义或分隔符的段，
    // 可以避免双重编码把看似普通的 endpoint 变成路径穿越或 query 注入。
    if (decodedSegment == '.' ||
        decodedSegment == '..' ||
        decodedSegment.contains('/') ||
        decodedSegment.contains('\\') ||
        decodedSegment.contains('?') ||
        decodedSegment.contains('#') ||
        _hexPairPattern.hasMatch(decodedSegment) ||
        _controlCharacterPattern.hasMatch(decodedSegment)) {
      throw ArgumentError('Request path must be a safe relative endpoint.');
    }
  }
}

Map<String, Object?> _freezeQueryParameters(Map<String, Object?> input) {
  try {
    final output = <String, Object?>{};
    for (final entry in input.entries) {
      final key = entry.key;
      final normalizedKey = key.toLowerCase().replaceAll(
        _nonAlphaNumericPattern,
        '',
      );
      if (key.isEmpty ||
          key != key.trim() ||
          _queryKeyForbiddenCharacterPattern.hasMatch(key) ||
          _sensitiveQueryNames.contains(normalizedKey)) {
        throw const _InvalidNetworkValue();
      }
      output[key] = _freezeQueryValue(entry.value);
    }
    return Map<String, Object?>.unmodifiable(output);
  } on Object {
    throw ArgumentError(
      'Query parameters must contain only safe names and scalar values.',
    );
  }
}

Object? _freezeQueryValue(Object? value) {
  if (value == null || value is String || value is bool || value is int) {
    return value;
  }
  if (value is double) {
    if (!value.isFinite) {
      throw const _InvalidNetworkValue();
    }
    return value;
  }
  if (value is List) {
    final output = <Object?>[];
    for (final item in value) {
      if (item is List || item is Map) {
        throw const _InvalidNetworkValue();
      }
      output.add(_freezeQueryValue(item));
    }
    return List<Object?>.unmodifiable(output);
  }
  throw const _InvalidNetworkValue();
}

Map<String, String> _freezeHeaders(Map<String, String> input) {
  try {
    final output = <String, String>{};
    for (final entry in input.entries) {
      final normalizedName = entry.key.toLowerCase();
      if (!_headerNamePattern.hasMatch(entry.key) ||
          _sensitiveHeaderNames.contains(normalizedName) ||
          _controlCharacterPattern.hasMatch(entry.value)) {
        throw const _InvalidNetworkValue();
      }
      output[normalizedName] = entry.value;
    }
    return Map<String, String>.unmodifiable(output);
  } on Object {
    throw ArgumentError(
      'Request headers must be valid and must not contain credentials.',
    );
  }
}

Object? _freezeBody(Object? input) {
  if (input == null) {
    return null;
  }
  if (input is! Map && input is! List) {
    throw ArgumentError('Request body must be a JSON object or array.');
  }

  try {
    return _freezeJsonValue(input, depth: 0, seen: HashSet<Object>.identity());
  } on Object {
    throw ArgumentError(
      'Request body must be an acyclic JSON object or array.',
    );
  }
}

Object? _freezeJsonValue(
  Object? value, {
  required int depth,
  required HashSet<Object> seen,
}) {
  if (value == null || value is String || value is bool || value is int) {
    return value;
  }
  if (value is double) {
    if (!value.isFinite) {
      throw const _InvalidNetworkValue();
    }
    return value;
  }
  if (depth >= _maxJsonDepth) {
    throw const _InvalidNetworkValue();
  }
  if (value is Map) {
    if (!seen.add(value)) {
      throw const _InvalidNetworkValue();
    }
    try {
      final output = <String, Object?>{};
      for (final entry in value.entries) {
        final key = entry.key;
        if (key is! String) {
          throw const _InvalidNetworkValue();
        }
        output[key] = _freezeJsonValue(
          entry.value,
          depth: depth + 1,
          seen: seen,
        );
      }
      return Map<String, Object?>.unmodifiable(output);
    } finally {
      seen.remove(value);
    }
  }
  if (value is List) {
    if (!seen.add(value)) {
      throw const _InvalidNetworkValue();
    }
    try {
      final output = <Object?>[];
      for (final item in value) {
        output.add(_freezeJsonValue(item, depth: depth + 1, seen: seen));
      }
      return List<Object?>.unmodifiable(output);
    } finally {
      seen.remove(value);
    }
  }
  throw const _InvalidNetworkValue();
}

final class _InvalidNetworkValue implements Exception {
  const _InvalidNetworkValue();
}
