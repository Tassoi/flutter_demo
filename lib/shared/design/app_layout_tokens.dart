import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_template/shared/layout/app_screen_adaptation.dart';

/// 应用布局使用的固定间距刻度。
///
/// Widget 应优先组合这些设计稿源值，避免在 Feature 中散落无法整体调整的数字。正常应用
/// 必须在 [AppScreenAdaptation] 下通过 [AppDesignUnitContext.du] 解析这些值，不能把常量
/// 直接当成设备逻辑像素。安全区、键盘 Insets 和其他平台值不属于本刻度，也不得参与换算。
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
/// 卡片、输入框和弹窗默认使用不超过 8 设计单位的圆角，保持模板安静、紧凑且适合高频操作
/// 界面。正常应用必须先通过 [AppDesignUnitContext.du] 解析半径；Feature 不应自行创建新的
/// 全局圆角体系，确有局部视觉语义时应在对应 Widget 内说明原因。
abstract final class AppRadii {
  /// 小型控件和轻量边框使用的圆角半径。
  static const double small = 4;

  /// 卡片、输入框和弹窗使用的默认圆角半径。
  static const double medium = 8;
}

/// 应用中需要同时满足设计比例与平台可用性的尺寸下限。
///
/// 普通几何值可以随宽度缩小，但可点击目标若在窄屏同步缩到 48 逻辑像素以下，会损害触摸和
/// 无障碍可用性。[minimumTouchTarget] 因此把设计稿的 48 单位按宽度换算后，再以真实 48
/// 逻辑像素作为下限；宽屏仍可按设计比例放大。该规则只用于交互边界，不能用来钳制普通
/// 间距、图标、文字或系统 Insets。
abstract final class AppDimensions {
  /// 解析按钮、图标按钮等主要交互元素的最小边长。
  static double minimumTouchTarget(BuildContext context) {
    return math.max(48.0, context.du(48));
  }
}
