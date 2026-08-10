import 'dart:collection';

/// 在日志进入 package logger 或 sink 前统一清理敏感数据。
///
/// redactor 同时使用字段名和自由文本模式：结构化 context 中的凭据/隐私字段会整值替换，
/// message、异常和堆栈中的常见 Authorization、Token、密码、邮箱与电话号码形式会再次
/// 扫描。URI 会整体移除 user info、query 与 fragment，未知对象不会调用 `toString()`，
/// 避免任意实现绕过脱敏。
///
/// 递归深度、集合元素数和文本长度都有上限，并检测循环引用，防止日志本身造成栈溢出、
/// 大量内存分配或阻塞 UI isolate。该类不承诺识别任意自然语言中的个人数据；调用方仍
/// 必须使用稳定 message，并把动态数据放入具有准确字段名的 context。
final class LogRedactor {
  /// 创建具有确定资源上限的日志脱敏器。
  const LogRedactor({
    this.maxDepth = 6,
    this.maxCollectionItems = 50,
    this.maxTextLength = 2048,
  }) : assert(maxDepth > 0),
       assert(maxCollectionItems > 0),
       assert(maxTextLength >= 32);

  /// 敏感字段统一使用的替代值。
  static const redactedValue = '[REDACTED]';

  /// 超过深度、元素或文本上限时使用的标记。
  static const truncatedValue = '[TRUNCATED]';

  /// 检测到循环引用时使用的标记。
  static const circularValue = '[CIRCULAR]';

  /// 输入对象无法安全遍历或格式化时使用的标记。
  static const unavailableValue = '[UNAVAILABLE]';

  /// 允许递归进入的最大层数。
  final int maxDepth;

  /// 每个 Map 或 Iterable 最多保留的元素数。
  final int maxCollectionItems;

  /// 单个 message、异常或堆栈最多保留的字符数。
  final int maxTextLength;

  static final _nonAlphaNumeric = RegExp('[^a-z0-9]');
  static final _headerPattern = RegExp(
    r'\b(authorization|proxy-authorization|cookie|set-cookie)\s*:\s*[^\r\n]+',
    caseSensitive: false,
  );
  static final _authorizationSchemePattern = RegExp(
    r'\b(Bearer|Basic)\s+[A-Za-z0-9._~+/=-]+',
    caseSensitive: false,
  );
  static final _quotedFieldPattern = RegExp(
    r'''(["'](?:authorization|proxy-authorization|token|auth[_-]?token|bearer[_-]?token|access[_-]?token|refresh[_-]?token|id[_-]?token|api[_-]?token|oauth[_-]?token|x[_-]?auth[_-]?token|api[_-]?key|x[_-]?api[_-]?key|password|passcode|pin|secret|client[_-]?secret|credential|cookie|set-cookie|session(?:[_-]?id)?|email|phone|mobile|address|user[_-]?id|device[_-]?id|ip[_-]?address)["']\s*:\s*["'])(.*?)(["'])''',
    caseSensitive: false,
  );
  static final _labeledValuePattern = RegExp(
    r'''\b(authorization|proxy-authorization|token|auth[_-]?token|bearer[_-]?token|access[_-]?token|refresh[_-]?token|id[_-]?token|api[_-]?token|oauth[_-]?token|api[_-]?key|password|passcode|pin|secret|client[_-]?secret|credential|cookie|set-cookie|session(?:[_-]?id)?|email|phone|mobile|address|user[_-]?id|device[_-]?id|ip[_-]?address)\b(\s*[:=]\s*)(?:"[^"\r\n]*"|'[^'\r\n]*'|[^,\s;&}\]]+)''',
    caseSensitive: false,
  );
  static final _emailPattern = RegExp(
    r'[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}',
    caseSensitive: false,
  );
  static final _phonePattern = RegExp(r'\b\d(?:[\s().-]*\d){9,14}\b');

  static const _sensitiveKeys = <String>{
    'authorization',
    'proxyauthorization',
    'cookie',
    'setcookie',
    'token',
    'accesstoken',
    'refreshtoken',
    'idtoken',
    'apikey',
    'password',
    'passcode',
    'pin',
    'secret',
    'clientsecret',
    'credential',
    'session',
    'sessionid',
    'email',
    'emailaddress',
    'name',
    'username',
    'displayname',
    'phone',
    'phonenumber',
    'mobile',
    'firstname',
    'lastname',
    'fullname',
    'address',
    'streetaddress',
    'postalcode',
    'zipcode',
    'userid',
    'customerid',
    'accountid',
    'deviceid',
    'ip',
    'ipaddress',
    'latitude',
    'longitude',
    'dateofbirth',
    'birthdate',
    'dob',
    'ssn',
    'nationalid',
    'passport',
    'cardnumber',
    'creditcard',
  };

  /// 递归清理 [context] 并返回深度不可变、JSON-safe 的新 Map。
  ///
  /// 输入不会被修改。字符串 key 会参与敏感字段判断；非字符串 key 只保留其类型名称。
  Map<String, Object?> redactContext(Map<String, Object?> context) {
    final seen = HashSet<Object>.identity();
    return _redactMap(context, depth: 0, seen: seen);
  }

  /// 清理 message 或其他自由文本中的常见敏感形式。
  String redactText(String text) {
    final inputWasTruncated = text.length > maxTextLength;
    final boundedInput =
        inputWasTruncated ? text.substring(0, maxTextLength) : text;
    var result = boundedInput.replaceAllMapped(_headerPattern, (match) {
      return '${match.group(1)}: $redactedValue';
    });
    result = result.replaceAllMapped(_authorizationSchemePattern, (match) {
      return '${match.group(1)} $redactedValue';
    });
    result = result.replaceAllMapped(_quotedFieldPattern, (match) {
      return '${match.group(1)}$redactedValue${match.group(3)}';
    });
    result = result.replaceAllMapped(_labeledValuePattern, (match) {
      return '${match.group(1)}${match.group(2)}$redactedValue';
    });
    result = result.replaceAll(_emailPattern, '[REDACTED_EMAIL]');
    result = result.replaceAll(_phonePattern, '[REDACTED_PHONE]');

    final outputWasTruncated = result.length > maxTextLength;
    if (!inputWasTruncated && !outputWasTruncated) {
      return result;
    }
    final boundedOutput =
        outputWasTruncated ? result.substring(0, maxTextLength) : result;
    return '$boundedOutput$truncatedValue';
  }

  /// 安全格式化并清理 [error]，即使其 `toString()` 自身抛出也不会失败。
  String redactError(Object error) {
    try {
      return redactText(error.toString());
    } on Object {
      return '<error message unavailable>';
    }
  }

  /// 格式化并清理 [stackTrace]，同时应用统一文本长度上限。
  String redactStackTrace(StackTrace stackTrace) {
    try {
      return redactText(stackTrace.toString());
    } on Object {
      return unavailableValue;
    }
  }

  Map<String, Object?> _redactMap(
    Map<Object?, Object?> input, {
    required int depth,
    required HashSet<Object> seen,
  }) {
    if (depth >= maxDepth) {
      return const <String, Object?>{'__truncated__': truncatedValue};
    }
    if (!seen.add(input)) {
      return const <String, Object?>{'__circular__': circularValue};
    }

    try {
      final output = <String, Object?>{};
      var index = 0;
      for (final entry in input.entries) {
        if (index >= maxCollectionItems) {
          output['__truncated__'] = truncatedValue;
          break;
        }
        final rawKey =
            entry.key is String
                ? entry.key! as String
                : '<${entry.key.runtimeType}>';
        final safeKey = redactText(rawKey);
        output[safeKey] = _redactValue(
          entry.value,
          key: rawKey,
          depth: depth + 1,
          seen: seen,
        );
        index++;
      }
      return Map<String, Object?>.unmodifiable(output);
    } on Object {
      // 自定义 Map 可以在读取 entries 或 key 时抛错；失败时丢弃全部部分结果，避免把
      // 未完成脱敏的数据误认为可安全输出。
      return const <String, Object?>{'__unavailable__': unavailableValue};
    } finally {
      seen.remove(input);
    }
  }

  Object? _redactValue(
    Object? value, {
    required String? key,
    required int depth,
    required HashSet<Object> seen,
  }) {
    if (key != null && _isSensitiveKey(key)) {
      return redactedValue;
    }
    if (value == null || value is int || value is bool) {
      return value;
    }
    if (value is double) {
      // JSON 不接受 NaN 与正负 Infinity。用稳定字符串保留诊断语义，避免控制台 sink
      // 在序列化阶段丢弃整条已经完成脱敏的记录。
      return value.isFinite ? value : value.toString();
    }
    if (value is String) {
      return redactText(value);
    }
    if (value is DateTime) {
      return value.toUtc().toIso8601String();
    }
    if (value is Uri) {
      return _redactUri(value);
    }
    if (value is Enum) {
      return value.name;
    }
    if (depth >= maxDepth) {
      return truncatedValue;
    }
    if (value is Map) {
      return _redactMap(value, depth: depth, seen: seen);
    }
    if (value is Iterable) {
      if (!seen.add(value)) {
        return circularValue;
      }
      try {
        final output = <Object?>[];
        var index = 0;
        for (final item in value) {
          if (index >= maxCollectionItems) {
            output.add(truncatedValue);
            break;
          }
          output.add(
            _redactValue(item, key: null, depth: depth + 1, seen: seen),
          );
          index++;
        }
        return List<Object?>.unmodifiable(output);
      } on Object {
        // 自定义 Iterable 的 iterator 可能抛错。返回固定标记比保留部分集合更容易证明
        // 不会把尚未遍历到的敏感值带入 sink。
        return unavailableValue;
      } finally {
        seen.remove(value);
      }
    }

    // 任意对象的 toString() 可能包含凭据且行为不可控；只保留类型即可定位调用方误用。
    return '<${value.runtimeType}>';
  }

  bool _isSensitiveKey(String key) {
    final normalized = key.toLowerCase().replaceAll(_nonAlphaNumeric, '');
    return _sensitiveKeys.contains(normalized) ||
        normalized.startsWith('authorization') ||
        normalized.startsWith('proxyauthorization') ||
        normalized.startsWith('authtoken') ||
        normalized.startsWith('token') ||
        normalized.startsWith('accesstoken') ||
        normalized.startsWith('refreshtoken') ||
        normalized.startsWith('idtoken') ||
        normalized.startsWith('apikey') ||
        normalized.startsWith('password') ||
        normalized.startsWith('passcode') ||
        normalized.startsWith('secret') ||
        normalized.startsWith('credential') ||
        normalized.startsWith('cookie') ||
        normalized.startsWith('session') ||
        normalized.endsWith('token') ||
        normalized.endsWith('password') ||
        normalized.endsWith('secret') ||
        normalized.endsWith('credential') ||
        normalized.endsWith('email') ||
        normalized.endsWith('phone') ||
        normalized.endsWith('phonenumber') ||
        normalized.endsWith('mobile') ||
        normalized.endsWith('address') ||
        normalized.endsWith('userid') ||
        normalized.endsWith('customerid') ||
        normalized.endsWith('accountid') ||
        normalized.endsWith('deviceid') ||
        normalized.endsWith('ipaddress') ||
        normalized.endsWith('birthdate') ||
        normalized.endsWith('passport') ||
        normalized.endsWith('cardnumber');
  }

  String _redactUri(Uri value) {
    // URI 中的 user info 常直接携带用户名和密码，query/fragment 也经常承载 Token 或
    // 个人标识。无论参数名是否已知都整段移除，避免 URL 编码绕过自由文本正则。
    final safeBase = value.replace(userInfo: '', query: '', fragment: '');
    final removedParts = <String>[
      if (value.userInfo.isNotEmpty) 'userInfo=$redactedValue',
      if (value.hasQuery) 'query=$redactedValue',
      if (value.hasFragment) 'fragment=$redactedValue',
    ];
    final suffix = removedParts.isEmpty ? '' : ' (${removedParts.join(', ')})';
    return redactText('$safeBase$suffix');
  }
}
