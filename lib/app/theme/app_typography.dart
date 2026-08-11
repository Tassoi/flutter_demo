import 'package:flutter/material.dart';
import 'package:flutter_template/shared/layout/app_screen_adaptation.dart';

/// 应用统一的 Material 3 排版刻度。
///
/// [textTheme] 把设计字号、行高、字重和零字距绑定到当前 [ColorScheme]，业务 Widget
/// 应从 `Theme.of(context).textTheme` 读取语义样式，而不是直接依赖本类。模板暂不捆绑
/// 第三方字体，因而继续使用 Android/iOS 的系统字体与 Flutter fallback；引入字体文件
/// 时必须同时核对许可证、登记 pubspec 资源并更新资源 ADR。
abstract final class AppTypography {
  /// 为 [colorScheme] 创建完整且按项目设计宽度换算字号的文字主题。
  ///
  /// [context] 必须位于 [AppScreenAdaptation] 下方。这里只把设计字号通过
  /// [AppDesignUnitContext.dsp] 换算一次，Flutter 随后仍会按用户无障碍文字缩放设置调整
  /// 最终排版；调用方不得通过固定 TextScaler 抵消系统设置。返回对象没有缓存和副作用。
  static TextTheme textTheme(BuildContext context, ColorScheme colorScheme) {
    return _apply(colorScheme, fontSizeFactor: context.dsp(1));
  }

  /// 为不依赖正常应用初始化结果的安全 fallback 创建 1:1 文字主题。
  ///
  /// 该入口只供启动失败应用使用，不能让正常页面借此绕过 [textTheme] 的设计单位换算。
  /// 1:1 只表示设计字号不按屏幕宽度换算，Flutter 的系统文字缩放仍然保留。
  static TextTheme fallbackTextTheme(ColorScheme colorScheme) {
    return _apply(colorScheme, fontSizeFactor: 1);
  }

  static TextTheme _apply(
    ColorScheme colorScheme, {
    required double fontSizeFactor,
  }) {
    return _base.apply(
      bodyColor: colorScheme.onSurface,
      displayColor: colorScheme.onSurface,
      fontSizeFactor: fontSizeFactor,
    );
  }

  static const _base = TextTheme(
    displayLarge: TextStyle(
      fontSize: 57,
      height: 64 / 57,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
    ),
    displayMedium: TextStyle(
      fontSize: 45,
      height: 52 / 45,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
    ),
    displaySmall: TextStyle(
      fontSize: 36,
      height: 44 / 36,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
    ),
    headlineLarge: TextStyle(
      fontSize: 32,
      height: 40 / 32,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
    ),
    headlineMedium: TextStyle(
      fontSize: 28,
      height: 36 / 28,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
    ),
    headlineSmall: TextStyle(
      fontSize: 24,
      height: 32 / 24,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
    ),
    titleLarge: TextStyle(
      fontSize: 22,
      height: 28 / 22,
      fontWeight: FontWeight.w500,
      letterSpacing: 0,
    ),
    titleMedium: TextStyle(
      fontSize: 16,
      height: 24 / 16,
      fontWeight: FontWeight.w500,
      letterSpacing: 0,
    ),
    titleSmall: TextStyle(
      fontSize: 14,
      height: 20 / 14,
      fontWeight: FontWeight.w500,
      letterSpacing: 0,
    ),
    bodyLarge: TextStyle(
      fontSize: 16,
      height: 24 / 16,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
    ),
    bodyMedium: TextStyle(
      fontSize: 14,
      height: 20 / 14,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
    ),
    bodySmall: TextStyle(
      fontSize: 12,
      height: 16 / 12,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
    ),
    labelLarge: TextStyle(
      fontSize: 14,
      height: 20 / 14,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
    ),
    labelMedium: TextStyle(
      fontSize: 12,
      height: 16 / 12,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
    ),
    labelSmall: TextStyle(
      fontSize: 11,
      height: 16 / 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
    ),
  );
}
