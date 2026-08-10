import 'package:flutter/widgets.dart';

/// 应用布局使用的固定间距刻度。
///
/// Widget 应优先组合这些值，避免在 Feature 中散落无法整体调整的数字。该刻度只表达
/// 逻辑像素，不按屏幕宽度缩放；安全区、键盘 Insets 和文字缩放仍必须使用 Flutter
/// 提供的真实平台值。第二阶段的移动端屏幕适配不会改变这些平台 Insets。
///
/// token 位于 `shared/design`，使 `app/` 的主题组装和跨 Feature 组件都能依赖同一来源，
/// 同时避免 `shared/` 反向依赖 composition root。
abstract final class AppSpacing {
  /// 极紧凑间距，用于相邻小元素之间的最小分隔。
  static const double xxs = 4;

  /// 紧凑间距，用于图标与短标签等紧密组合。
  static const double xs = 8;

  /// 小间距，用于同一控件内部的内容分隔。
  static const double sm = 12;

  /// 默认间距，用于常规内容与控件内边距。
  static const double md = 16;

  /// 大间距，用于页面边缘和内容组之间的分隔。
  static const double lg = 24;

  /// 加大间距，用于主要区块之间的留白。
  static const double xl = 32;

  /// 超大间距，用于少量需要明确层级的页面区域。
  static const double xxl = 48;

  /// 最大基础间距，也可作为小型示例图形的稳定边长。
  static const double xxxl = 64;
}

/// 应用组件使用的圆角刻度。
///
/// 卡片、输入框和弹窗默认使用不超过 8 逻辑像素的圆角，保持模板安静、紧凑且适合
/// 高频操作界面。Feature 不应自行创建新的全局圆角体系；确有局部视觉语义时应在对应
/// Widget 内说明原因。
abstract final class AppRadii {
  /// 小型控件和轻量边框使用的圆角半径。
  static const double small = 4;

  /// 卡片、输入框和弹窗使用的默认圆角半径。
  static const double medium = 8;

  /// 由 [small] 构造的四角统一边界。
  static const BorderRadius smallBorderRadius = BorderRadius.all(
    Radius.circular(small),
  );

  /// 由 [medium] 构造的四角统一边界。
  static const BorderRadius mediumBorderRadius = BorderRadius.all(
    Radius.circular(medium),
  );
}
