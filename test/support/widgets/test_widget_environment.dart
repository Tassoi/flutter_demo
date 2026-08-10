import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// 代表需要重点验证的窄屏手机逻辑尺寸。
///
/// 该尺寸用于发现小屏设备上的溢出和不可达操作，不表示脚手架只支持这一种屏幕。
const Size narrowPhoneSurfaceSize = Size(320, 568);

/// 代表无障碍布局测试使用的放大文字比例。
const TextScaler largeTestTextScaler = TextScaler.linear(2);

/// 在可选的 [surfaceSize] 下挂载 [widget]，并只推进第一个 Widget 帧。
///
/// 设置测试表面后会自动注册恢复逻辑，防止尺寸泄漏到随后执行的测试。该方法有意不调用
/// `pumpAndSettle`：动画、异步状态和路由转换应由测试显式推进所需帧，避免持续动画让测试
/// 挂起，也避免辅助方法掩盖实际状态时序。
Future<void> pumpTestWidget(
  WidgetTester tester,
  Widget widget, {
  Size? surfaceSize,
}) async {
  if (surfaceSize != null) {
    await tester.binding.setSurfaceSize(surfaceSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }
  await tester.pumpWidget(widget);
}

/// 创建只覆盖文字缩放设置的测试应用 Builder。
///
/// 其余 [MediaQueryData] 从当前测试绑定继承，因此表面尺寸、安全区域和平台设置仍由各测试
/// 明确控制。默认禁用缩放以获得确定基线；无障碍布局测试应传入 [largeTestTextScaler]。
TransitionBuilder createTestMediaQueryBuilder({
  TextScaler textScaler = TextScaler.noScaling,
}) {
  return (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: textScaler),
    child: child!,
  );
}
