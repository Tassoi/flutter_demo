/// 普通偏好存储使用的稳定逻辑键。
///
/// 键名必须是小写点分名称，例如 `appearance.theme_mode`，且只能来自源码中的稳定定义，
/// 不能拼接用户 ID、邮箱或其他运行时数据。[PreferenceKey] 会拒绝明显描述 Token、密码、
/// Cookie、API key 等凭据的名称，减少把敏感值误写进普通存储的机会。
///
/// 键名校验只能阻止显而易见的误用，不能识别任意敏感值。调用方仍必须把凭据、密钥和
/// 需要加密的个人数据交给 `SecureValueStore`，不能通过使用模糊键名绕过边界。
final class PreferenceKey {
  /// 创建经过格式与敏感用途校验的普通偏好键。
  ///
  /// [name] 最长 120 个 ASCII 字符，每段以小写字母开头，后续只允许小写字母、数字和
  /// 下划线。非法输入抛出的 [ArgumentError] 使用固定文案，不回显原始名称。
  factory PreferenceKey(String name) {
    if (name.length > _maximumKeyLength || !_keyPattern.hasMatch(name)) {
      throw ArgumentError('Preference key must be a stable lowercase name.');
    }

    final normalized = name.replaceAll(_nonAlphaNumericPattern, '');
    if (_credentialMarkers.any(normalized.contains)) {
      throw ArgumentError('Preference keys must not describe credentials.');
    }
    return PreferenceKey._(name);
  }

  const PreferenceKey._(this.name);

  /// 不包含物理 namespace 的逻辑键名。
  final String name;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is PreferenceKey && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'PreferenceKey($name)';
}

const _maximumKeyLength = 120;
final _keyPattern = RegExp(r'^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*$');
final _nonAlphaNumericPattern = RegExp(r'[^a-z0-9]');
const _credentialMarkers = <String>[
  'authorization',
  'accesstoken',
  'refreshtoken',
  'idtoken',
  'authtoken',
  'oauthtoken',
  'token',
  'apikey',
  'bearer',
  'clientsecret',
  'secret',
  'password',
  'passwd',
  'passcode',
  'credential',
  'cookie',
  'jwt',
  'privatekey',
  'session',
  'sessionid',
];
