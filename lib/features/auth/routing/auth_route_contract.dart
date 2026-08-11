/// 认证 Feature 对应用唯一 Router 公开的纯 Dart 路由契约。
///
/// Feature 不创建 Router，也不导入 go_router。当前模板只提供一个受保护示例位置，因而
/// `returnTo` 只接受该规范路径；增加其他受保护页面时必须显式扩展白名单和重定向测试，
/// 不能把任意深链原样带过登录流程。
abstract final class AuthRouteContract {
  /// 登录页的站内绝对路径。
  static const String signInPath = '/sign-in';

  /// 启动恢复期间固定加载页的站内绝对路径。
  static const String sessionLoadingPath = '/session-loading';

  /// 受保护示例页注册在首页 Shell 下的相对路径。
  static const String protectedPath = 'account';

  /// 受保护示例页的规范站内绝对位置。
  static const String protectedLocation = '/account';

  /// 登录与加载位置携带已校验返回目标时使用的 query 名称。
  static const String returnToQueryParameter = 'returnTo';

  /// 判断 [uri] 是否属于当前明确受保护的位置。
  ///
  /// query 和 fragment 不参与保护判断，但后续形成 `returnTo` 时会被删除，避免动态深链
  /// 数据穿过认证页面或进入日志。
  static bool isProtected(Uri uri) => uri.path == protectedLocation;

  /// 从外部 query 值解析允许在认证后恢复的站内位置。
  ///
  /// 只接受恰好等于 [protectedLocation] 且不含 scheme、authority、userinfo、query 或
  /// fragment 的值。非法输入返回 `null`，不会抛出或回显原字符串。
  static Uri? tryParseReturnTo(String? value) {
    if (value == null) {
      return null;
    }
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.hasScheme ||
        uri.hasAuthority ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.path != protectedLocation) {
      return null;
    }
    return Uri(path: protectedLocation);
  }

  /// 创建登录页位置，只保留经过白名单验证的 [returnTo]。
  static Uri signInLocation({Uri? returnTo}) {
    final safeReturnTo = tryParseReturnTo(returnTo?.toString());
    return Uri(
      path: signInPath,
      queryParameters:
          safeReturnTo == null
              ? null
              : <String, String>{
                returnToQueryParameter: safeReturnTo.toString(),
              },
    );
  }

  /// 创建恢复加载页位置，只保留经过白名单验证的 [returnTo]。
  static Uri sessionLoadingLocation({required Uri returnTo}) {
    final safeReturnTo = tryParseReturnTo(returnTo.toString());
    return Uri(
      path: sessionLoadingPath,
      queryParameters:
          safeReturnTo == null
              ? null
              : <String, String>{
                returnToQueryParameter: safeReturnTo.toString(),
              },
    );
  }
}
