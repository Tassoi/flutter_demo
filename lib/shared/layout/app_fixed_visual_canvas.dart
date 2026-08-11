import 'package:flutter/widgets.dart';

/// 固定视觉画布填充目标区域时允许采用的策略。
///
/// 该枚举有意只保留 [contain] 与 [cover]，避免普通页面借由拉伸、按高度缩放或其他模式
/// 掩盖布局问题。选择策略时必须由具体视觉稿明确接受留白或裁切。
enum AppFixedCanvasFit {
  /// 完整显示画布并保留目标区域中无法填满的空间，不裁切内容。
  contain,

  /// 等比填满目标区域，并裁切超出区域的画布边缘。
  cover,
}

/// 在有界区域内等比呈现海报、活动视觉等固定坐标画布。
///
/// 本组件是普通响应式布局的显式例外：它把 [designSize] 作为一个整体通过 [FittedBox]
/// 缩放，而不是让画布内部元素逐项调用 `du`。只能用于已经确认具有固定画布语义的视觉内容，
/// 不得包裹表单、列表、导航、状态页面或依赖稳定点击尺寸的普通交互界面。
///
/// 本组件不读取或消费 SafeArea、状态栏、系统手势区和键盘 Insets。调用方必须先在页面层
/// 确定画布允许占用的安全有界区域；不得把系统 Insets 乘以画布比例。使用 [AppFixedCanvasFit.cover]
/// 会裁切边缘，关键文字、品牌标识和必要操作必须位于视觉稿定义的安全内容区，并通过具体页面
/// 的截图或矩形测试验证。
final class AppFixedVisualCanvas extends StatelessWidget {
  /// 创建固定尺寸的视觉画布。
  const AppFixedVisualCanvas({
    required this.designSize,
    required this.child,
    this.fit = AppFixedCanvasFit.contain,
    this.alignment = Alignment.center,
    super.key,
  });

  /// 视觉稿内部使用的固定坐标尺寸。
  ///
  /// 宽高必须有限且大于零；该值不应直接使用设备尺寸或系统 Insets 计算。
  final Size designSize;

  /// 在 [designSize] 坐标系中布局的视觉内容。
  final Widget child;

  /// 画布完整保留或填满裁切的明确策略。
  final AppFixedCanvasFit fit;

  /// 画布比例与目标区域比例不一致时的对齐方式。
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    if (!_isFinitePositive(designSize.width) ||
        !_isFinitePositive(designSize.height)) {
      throw ArgumentError.value(
        designSize,
        'designSize',
        'Fixed canvas dimensions must be finite and positive.',
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth || !constraints.hasBoundedHeight) {
          throw StateError(
            'AppFixedVisualCanvas requires bounded width and height.',
          );
        }

        final boxFit = switch (fit) {
          AppFixedCanvasFit.contain => BoxFit.contain,
          AppFixedCanvasFit.cover => BoxFit.cover,
        };

        return FittedBox(
          fit: boxFit,
          alignment: alignment,
          clipBehavior:
              fit == AppFixedCanvasFit.cover ? Clip.hardEdge : Clip.none,
          child: SizedBox.fromSize(size: designSize, child: child),
        );
      },
    );
  }
}

bool _isFinitePositive(double value) => value.isFinite && value > 0;
