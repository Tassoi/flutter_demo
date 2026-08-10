/// 安全存储使用的稳定逻辑键。
///
/// 键名必须是源码定义的小写点分名称，例如 `auth.refresh_token`，不能包含用户输入或其他
/// 动态标识。与普通 [PreferenceKey] 不同，本类型允许描述凭据用途，但 [toString] 始终
/// 隐藏名称，避免诊断输出暴露应用保存了哪类敏感状态。
final class SecureStorageKey {
  /// 创建经过格式校验的安全存储键。
  ///
  /// [name] 最长 120 个 ASCII 字符，每段以小写字母开头，后续只允许小写字母、数字和
  /// 下划线。非法输入抛出的 [ArgumentError] 不回显原始名称。
  factory SecureStorageKey(String name) {
    if (name.length > _maximumSecureKeyLength ||
        !_secureKeyPattern.hasMatch(name)) {
      throw ArgumentError(
        'Secure storage key must be a stable lowercase name.',
      );
    }
    return SecureStorageKey._(name);
  }

  const SecureStorageKey._(this.name);

  /// 只供安全存储 adapter 形成物理键的逻辑名称。
  ///
  /// 调用方不得记录、展示或从用户输入动态构造该值。
  final String name;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is SecureStorageKey && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'SecureStorageKey([REDACTED])';
}

const _maximumSecureKeyLength = 120;
final _secureKeyPattern = RegExp(r'^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*$');
