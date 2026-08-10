/// 示例 Feature 展示的不可变领域实体。
///
/// [ExampleItem] 只保存页面真正需要的 ID、标题和说明，不包含网络 DTO、JSON、插件对象或
/// 导航状态。构造时会去除文字两端空白并限制长度，使远端或替换数据源不能把无界文本直接
/// 带入 Widget 树；校验错误使用固定文案，不回显可能含私密内容的输入。
final class ExampleItem {
  /// 创建一个经过领域边界校验的示例项。
  ///
  /// [id] 必须为正整数；[title] 与 [description] 去除两端空白后必须非空，并分别不超过
  /// [maximumTitleLength] 与 [maximumDescriptionLength]。非法输入抛出固定
  /// [ArgumentError]。本类型没有 I/O、缓存或可变状态。
  factory ExampleItem({
    required int id,
    required String title,
    required String description,
  }) {
    final normalizedTitle = title.trim();
    final normalizedDescription = description.trim();
    if (id <= 0) {
      throw ArgumentError('Example item ID must be positive.');
    }
    if (normalizedTitle.isEmpty ||
        normalizedTitle.length > maximumTitleLength) {
      throw ArgumentError('Example item title is invalid.');
    }
    if (normalizedDescription.isEmpty ||
        normalizedDescription.length > maximumDescriptionLength) {
      throw ArgumentError('Example item description is invalid.');
    }
    return ExampleItem._(
      id: id,
      title: normalizedTitle,
      description: normalizedDescription,
    );
  }

  const ExampleItem._({
    required this.id,
    required this.title,
    required this.description,
  });

  /// 标题允许的最大 Unicode code unit 数量。
  static const int maximumTitleLength = 80;

  /// 说明允许的最大 Unicode code unit 数量。
  static const int maximumDescriptionLength = 600;

  /// 示例项的稳定正整数标识。
  final int id;

  /// 已去除两端空白、可直接展示的标题。
  final String title;

  /// 已去除两端空白、可直接展示的说明。
  final String description;

  /// 返回只包含已验证 ID 的安全诊断文本。
  ///
  /// 标题和说明可能来自外部数据源，因此本方法有意不输出这两个字段。调用方不得把本方法
  /// 当成序列化格式；需要传输数据时应在所属数据边界定义明确 DTO。
  @override
  String toString() {
    // 标题和说明可能来自线上数据，诊断字符串只保留已验证 ID，避免测试失败或日志误带正文。
    return 'ExampleItem(id: $id)';
  }
}
