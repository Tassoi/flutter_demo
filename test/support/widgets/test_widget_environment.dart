import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// 代表需要重点验证的窄屏手机逻辑尺寸。
///
/// 该尺寸用于发现小屏设备上的溢出和不可达操作，不表示脚手架只支持这一种屏幕。
const Size narrowPhoneSurfaceSize = Size(320, 568);

/// 与项目设计稿一致的参考手机逻辑尺寸。
const Size referencePhoneSurfaceSize = Size(375, 812);

/// 第二阶段手机页面必须覆盖的完整视口矩阵。
///
/// 每个案例同时给出 Flutter 已换算好的安全区逻辑值。测试把这些值直接交给 MediaQuery，
/// 不通过项目设计单位换算；横屏案例包含左右安全区，用于发现只处理上下边缘的页面。
const List<TestPhoneViewport> supportedPhoneViewports = <TestPhoneViewport>[
  TestPhoneViewport(
    name: 'narrow phone',
    size: Size(320, 568),
    safeInsets: EdgeInsets.only(top: 24, bottom: 16),
  ),
  TestPhoneViewport(
    name: 'regular Android',
    size: Size(360, 800),
    safeInsets: EdgeInsets.only(top: 24, bottom: 24),
  ),
  TestPhoneViewport(
    name: 'reference phone',
    size: referencePhoneSurfaceSize,
    safeInsets: EdgeInsets.only(top: 44, bottom: 34),
  ),
  TestPhoneViewport(
    name: 'regular iPhone',
    size: Size(390, 844),
    safeInsets: EdgeInsets.only(top: 47, bottom: 34),
  ),
  TestPhoneViewport(
    name: 'wide phone',
    size: Size(430, 932),
    safeInsets: EdgeInsets.fromLTRB(8, 47, 10, 34),
  ),
  TestPhoneViewport(
    name: 'phone landscape',
    size: Size(800, 360),
    safeInsets: EdgeInsets.fromLTRB(44, 0, 20, 21),
  ),
];

/// 一个用于布局契约测试的手机视口及其原始系统安全区。
final class TestPhoneViewport {
  /// 创建名称稳定的逻辑视口案例。
  const TestPhoneViewport({
    required this.name,
    required this.size,
    required this.safeInsets,
  });

  /// 测试报告中使用的可读名称。
  final String name;

  /// Flutter 页面使用的逻辑宽高。
  final Size size;

  /// 不参与 `du/dsp` 换算的系统逻辑安全区。
  final EdgeInsets safeInsets;
}

/// 代表无障碍布局测试使用的放大文字比例。
const TextScaler largeTestTextScaler = TextScaler.linear(2);

/// 在可选的 [surfaceSize] 与原始平台 Insets 下挂载 [widget]，并只推进第一个 Widget 帧。
///
/// [padding]、[viewPadding] 和 [viewInsets] 都是 Flutter 已换算的实际逻辑值，不经过
/// `du/dsp`。设置测试表面后会自动注册恢复逻辑，防止尺寸或 Insets 泄漏到随后执行的测试。
/// 该方法有意不调用 `pumpAndSettle`：动画、异步状态和路由转换应由测试显式推进所需帧，
/// 避免持续动画让测试挂起，也避免辅助方法掩盖实际状态时序。
Future<void> pumpTestWidget(
  WidgetTester tester,
  Widget widget, {
  Size? surfaceSize,
  EdgeInsets padding = EdgeInsets.zero,
  EdgeInsets viewPadding = EdgeInsets.zero,
  EdgeInsets viewInsets = EdgeInsets.zero,
}) async {
  if (surfaceSize != null) {
    configureTestView(
      tester,
      surfaceSize,
      padding: padding,
      viewPadding: viewPadding,
      viewInsets: viewInsets,
    );
  }
  await tester.pumpWidget(widget);
}

/// 把测试 FlutterView 配置为指定逻辑尺寸和平台 Insets，并在用例结束后恢复全部指标。
///
/// ScreenUtil 读取 View 的物理尺寸和像素比，只调用 `setSurfaceSize` 不足以改变其输入。
/// 本方法固定测试像素比为 1，使 [logicalSize] 同时成为物理和逻辑尺寸，并注册 teardown
/// 防止比例状态泄漏到其他文件或随机顺序测试。[padding]、[viewPadding] 和 [viewInsets]
/// 会同时写入底层测试 View，使位于 SafeArea 下方的代码仍能读取未消费的平台原始值；
/// 调用后仍由测试决定何时 pump Widget。
void configureTestView(
  WidgetTester tester,
  Size logicalSize, {
  EdgeInsets padding = EdgeInsets.zero,
  EdgeInsets viewPadding = EdgeInsets.zero,
  EdgeInsets viewInsets = EdgeInsets.zero,
}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = logicalSize;
  tester.view.padding = _fakeViewPadding(padding);
  tester.view.viewPadding = _fakeViewPadding(viewPadding);
  tester.view.viewInsets = _fakeViewPadding(viewInsets);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewPadding);
  addTearDown(tester.view.resetViewInsets);
}

FakeViewPadding _fakeViewPadding(EdgeInsets insets) {
  return FakeViewPadding(
    left: insets.left,
    top: insets.top,
    right: insets.right,
    bottom: insets.bottom,
  );
}

/// 创建只覆盖文字缩放设置的测试应用 Builder。
///
/// 其余 [MediaQueryData] 从当前测试绑定继承，因此表面尺寸、安全区域和平台设置仍由各测试
/// 明确控制。默认禁用缩放以获得确定基线；无障碍布局测试应传入 [largeTestTextScaler]。
TransitionBuilder createTestMediaQueryBuilder({
  TextScaler textScaler = TextScaler.noScaling,
  EdgeInsets? padding,
  EdgeInsets? viewPadding,
  EdgeInsets? viewInsets,
}) {
  return (context, child) {
    final current = MediaQuery.of(context);
    return MediaQuery(
      data: current.copyWith(
        textScaler: textScaler,
        padding: padding ?? current.padding,
        viewPadding: viewPadding ?? current.viewPadding,
        viewInsets: viewInsets ?? current.viewInsets,
      ),
      child: child!,
    );
  };
}
