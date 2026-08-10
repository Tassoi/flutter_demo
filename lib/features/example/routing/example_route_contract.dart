/// 示例 Feature 对应用组装层公开的路由契约。
///
/// 本类型只定义详情路径、参数名称和稳定的 ID 编解码规则，不创建全局 Router，也不依赖
/// go_router。应用层负责把 [detailPath] 注册到唯一 Router；Feature 后续页面只能通过
/// [detailLocation] 构造位置，不能持有或配置全局导航器。
///
/// 当前正整数 ID 是中立示例的路由标识，不代表后端数据库主键。替换示例 Repository 时必须
/// 维持该公开 URL 契约，或把变化作为显式路由迁移处理。
abstract final class ExampleRouteContract {
  /// 详情路由在父级首页下使用的相对路径。
  static const String detailPath = 'example/:itemId';

  /// 详情路由的稳定名称。
  static const String detailRouteName = 'example.detail';

  /// 详情路径中的参数名称。
  static const String itemIdParameter = 'itemId';

  /// 公共 URL 接受的最大示例项 ID。
  ///
  /// 九位上限使链接在所有目标平台上都能按普通整数处理，同时阻止无界数字字符串进入
  /// 解析和展示层。更改上限会改变既有深链的有效集合，需要迁移说明和回归测试。
  static const int maximumItemId = 999999999;

  static final RegExp _canonicalItemId = RegExp(r'^[1-9][0-9]{0,8}$');

  /// 为 [itemId] 构造规范的应用内详情位置。
  ///
  /// [itemId] 必须位于 1 到 [maximumItemId]。返回的 [Uri] 没有 scheme、authority、
  /// query 或 fragment，可以直接交给应用导航 API。非法值会在导航前抛出
  /// [ArgumentError]，避免生成随后只能落入错误页的链接。
  static Uri detailLocation(int itemId) {
    if (itemId < 1 || itemId > maximumItemId) {
      throw ArgumentError('Example item ID is outside the route contract.');
    }
    return Uri(path: '/example/$itemId');
  }

  /// 尝试把路径参数解析为规范的示例项 ID。
  ///
  /// 缺失、空白、符号、前导零、非十进制字符和超出 [maximumItemId] 的值都返回
  /// `null`；函数不会抛出或在错误文本中回显原始 URL 数据。应用路由层据此展示稳定的
  /// 非法参数状态，Feature 页面只会收到已经验证的正整数。
  static int? tryParseItemId(String? value) {
    if (value == null || !_canonicalItemId.hasMatch(value)) {
      return null;
    }
    final itemId = int.tryParse(value);
    if (itemId == null || itemId > maximumItemId) {
      return null;
    }
    return itemId;
  }
}
