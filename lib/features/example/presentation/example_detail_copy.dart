import 'package:flutter_template/core/error/app_error.dart';

/// 把稳定应用错误转换为当前语言安全文案的 Feature 边界。
typedef ExampleErrorMessageResolver = String Function(AppError error);

/// 使用当前语言数字规则格式化示例条目标识的 Feature 边界。
typedef ExampleItemIdentifierFormatter = String Function(int itemId);

/// 示例详情页所需的全部用户可见文案和格式化能力。
///
/// 类型位于 Feature 内，应用路由层用当前 `AppLocalizations` 创建实例并注入页面。这样 Feature
/// 不反向依赖 `app/` 或 Flutter 生成类，删除示例模块也不会要求修改本地化基础设施实现。
/// Repository 返回的标题和描述属于示例领域数据，不包含在本模型中。
final class ExampleDetailCopy {
  /// 创建一次页面构建使用的不可变文案集合。
  ///
  /// [errorMessage] 只能依据稳定 [AppError.code] 返回安全文案，不能暴露底层异常；
  /// [itemIdentifier] 必须显式使用当前 locale 格式化数字，不能依赖全局 Intl 默认值。
  const ExampleDetailCopy({
    required this.loadingMessage,
    required this.errorTitle,
    required this.retryLabel,
    required this.emptyTitle,
    required this.emptyMessage,
    required this.backToHomeLabel,
    required this.backTooltip,
    required this.pageTitle,
    required this.errorMessage,
    required this.itemIdentifier,
  });

  /// 首次加载和显式重试期间的状态文案。
  final String loadingMessage;

  /// 加载失败状态的固定标题。
  final String errorTitle;

  /// 加载失败状态的重试操作文案。
  final String retryLabel;

  /// 成功返回空数据时的标题。
  final String emptyTitle;

  /// 成功返回空数据时的说明。
  final String emptyMessage;

  /// 从空状态返回首页的操作文案。
  final String backToHomeLabel;

  /// 顶部返回图标供辅助技术和长按提示使用的文案。
  final String backTooltip;

  /// 详情页固定标题。
  final String pageTitle;

  /// 当前语言的稳定应用错误映射。
  final ExampleErrorMessageResolver errorMessage;

  /// 当前语言的示例条目标识格式化器。
  final ExampleItemIdentifierFormatter itemIdentifier;
}
