import 'package:flutter/widgets.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// 应用唯一的手机设计稿参考尺寸。
///
/// 宽度 `375` 是所有普通几何尺寸和字号的换算基准，高度 `812` 只用于记录设计稿画布，
/// 不参与独立纵向缩放。具体项目若要更换设计稿基准，必须只修改本常量并重新执行完整尺寸
/// 矩阵测试；不得按页面、环境或设备定义不同基准。
const Size appDesignSize = Size(375, 812);

/// 在应用根部初始化统一的 Android/iOS 手机设计单位。
///
/// 本 Widget 是 `flutter_screenutil` 的唯一运行时适配边界。它先按 [appDesignSize] 配置
/// ScreenUtil，再把只包含宽度比例的项目作用域放到 [builder] 下方。调用方因此只能通过
/// [AppDesignUnitContext.du] 与 [AppDesignUnitContext.dsp] 使用稳定项目 API，不会接触
/// `.w`、`.h`、`.sp` 或其他插件类型。
///
/// [builder] 会在 ScreenUtil 已完成当前 View 指标配置后执行，因此其中可以安全创建会消费
/// 设计单位的主题和页面。View 宽度变化时作用域会更新依赖者；系统文字缩放、SafeArea、
/// 状态栏、手势区和键盘 Insets 均不在这里改写，仍由 Flutter 的 MediaQuery 提供实际值。
/// 应用只能挂载一个该根节点，启动失败 fallback 则应继续保持无插件依赖。
final class AppScreenAdaptation extends StatelessWidget {
  /// 创建一个在设计单位作用域内延迟构造内容的应用根节点。
  const AppScreenAdaptation({required this.builder, super.key});

  /// 在适配上下文已经可用后构造应用内容。
  ///
  /// 不使用预先构造的 `child`，是为了避免主题或其他根对象在 ScreenUtil 初始化前读取
  /// `du/dsp`。传入的 BuildContext 位于项目作用域下方，可以直接调用这两个 API。
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: appDesignSize,
      splitScreenMode: false,
      minTextAdapt: false,
      rebuildFactor: RebuildFactors.size,
      enableScaleWH: _enableDesignScaling,
      enableScaleText: _enableDesignScaling,
      fontSizeResolver: FontSizeResolvers.width,
      builder: (context, _) {
        final widthScale = ScreenUtil().scaleWidth;
        if (!widthScale.isFinite || widthScale <= 0) {
          throw StateError(
            'The mobile design width scale must be finite and positive.',
          );
        }

        return _AppDesignUnitScope(
          widthScale: widthScale,
          // 额外的 Builder 确保调用方收到的 context 位于刚创建的项目作用域下方，而不是
          // ScreenUtilInit 自身的上级 context；否则根主题首次构造时仍无法读取 du/dsp。
          child: Builder(builder: builder),
        );
      },
    );
  }
}

/// 通过 BuildContext 读取项目手机设计单位。
///
/// 使用 context 作为入口可以把初始化状态和 View 指标变化交给 Flutter 继承树管理，避免
/// 进程级可变比例泄漏到其他测试或嵌套应用。Feature 与共享 Widget 可以导入本文件，但不得
/// 导入 `flutter_screenutil`。
extension AppDesignUnitContext on BuildContext {
  /// 把非负、有限的设计稿几何值按当前 View 宽度换算为逻辑像素。
  ///
  /// 宽、高、间距、圆角和图标尺寸都应使用同一 [du] 比例。SafeArea、状态栏、系统手势区、
  /// 键盘 Insets 和其他 MediaQuery 平台值已经是实际逻辑像素，禁止再次传给本方法。
  /// [designValue] 为负数、NaN 或无穷大时抛 [ArgumentError]；缺少
  /// [AppScreenAdaptation] 祖先时抛 [StateError]。需要表达负向位移时，应先换算正值再在
  /// 调用处取负数，使长度输入的非负约束保持明确。
  double du(num designValue) {
    return _scaleDesignValue(
      context: this,
      designValue: designValue,
      parameterName: 'designValue',
    );
  }

  /// 把非负、有限的设计稿字号按当前 View 宽度换算为 Flutter 字号。
  ///
  /// [dsp] 只应用与 [du] 相同的设计比例，不读取也不预乘系统文字倍率。将返回值交给
  /// TextStyle 后，Flutter 会通过当前 MediaQuery 的 `TextScaler` 再应用一次用户无障碍
  /// 缩放；调用方不得用 `TextScaler.noScaling` 抵消该行为。
  ///
  /// [designFontSize] 为负数、NaN 或无穷大时抛 [ArgumentError]；缺少根适配上下文时抛
  /// [StateError]。
  double dsp(num designFontSize) {
    return _scaleDesignValue(
      context: this,
      designValue: designFontSize,
      parameterName: 'designFontSize',
    );
  }
}

/// 向项目子树提供一个已经验证的宽度比例。
///
/// 作用域只保存项目值，不暴露 ScreenUtil。指标更新时只有比例实际变化才通知依赖者；高度、
/// Insets 或文字倍率变化不会伪造新的几何比例，它们继续沿各自 Flutter 继承数据传播。
final class _AppDesignUnitScope extends InheritedWidget {
  const _AppDesignUnitScope({required this.widthScale, required super.child});

  final double widthScale;

  static _AppDesignUnitScope read(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<_AppDesignUnitScope>();
    if (scope == null) {
      throw StateError(
        'AppScreenAdaptation must be mounted before using design units.',
      );
    }
    return scope;
  }

  @override
  bool updateShouldNotify(_AppDesignUnitScope oldWidget) {
    return widthScale != oldWidget.widthScale;
  }
}

double _scaleDesignValue({
  required BuildContext context,
  required num designValue,
  required String parameterName,
}) {
  final value = designValue.toDouble();
  if (!value.isFinite || value < 0) {
    throw ArgumentError.value(
      designValue,
      parameterName,
      'Design values must be finite and non-negative.',
    );
  }
  return value * _AppDesignUnitScope.read(context).widthScale;
}

bool _enableDesignScaling() => true;
