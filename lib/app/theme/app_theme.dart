import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_template/app/theme/app_typography.dart';
import 'package:flutter_template/shared/design/app_layout_tokens.dart';
import 'package:flutter_template/shared/layout/app_screen_adaptation.dart';

/// 应用 Material 3 亮暗主题的唯一组装入口。
///
/// 颜色、排版和常用组件外观在此集中组合。Feature 应通过 [Theme.of] 和项目布局 token
/// 获取语义值，不应导入私有色板或复制颜色常量。[light] 与 [dark] 每次返回独立
/// [ThemeData]，不读取环境、平台存储或全局可变状态。正常应用必须从适配根下的 context
/// 创建主题；启动失败页使用明确的 fallback 入口，不把插件初始化变成安全回退的前置条件。
abstract final class AppTheme {
  /// 在项目设计单位已经初始化后创建亮色 Material 3 主题。
  static ThemeData light(BuildContext context) => _build(
    colorScheme: _lightColorScheme,
    designUnit: (value) => context.du(value),
    textTheme: AppTypography.textTheme(context, _lightColorScheme),
  );

  /// 在项目设计单位已经初始化后创建暗色 Material 3 主题。
  static ThemeData dark(BuildContext context) => _build(
    colorScheme: _darkColorScheme,
    designUnit: (value) => context.du(value),
    textTheme: AppTypography.textTheme(context, _darkColorScheme),
  );

  /// 创建不依赖适配器、资源或其他启动结果的亮色安全 fallback 主题。
  static ThemeData fallbackLight() => _build(
    colorScheme: _lightColorScheme,
    designUnit: _identityDesignUnit,
    textTheme: AppTypography.fallbackTextTheme(_lightColorScheme),
  );

  /// 创建不依赖适配器、资源或其他启动结果的暗色安全 fallback 主题。
  static ThemeData fallbackDark() => _build(
    colorScheme: _darkColorScheme,
    designUnit: _identityDesignUnit,
    textTheme: AppTypography.fallbackTextTheme(_darkColorScheme),
  );

  static ThemeData _build({
    required ColorScheme colorScheme,
    required double Function(num value) designUnit,
    required TextTheme textTheme,
  }) {
    final mediumRadius = BorderRadius.all(
      Radius.circular(designUnit(AppRadii.medium)),
    );
    final standardShape = RoundedRectangleBorder(borderRadius: mediumRadius);
    final inputBorder = OutlineInputBorder(
      borderRadius: mediumRadius,
      borderSide: BorderSide(color: colorScheme.outline, width: designUnit(1)),
    );
    final minimumTouchTarget = math.max(48.0, designUnit(48));
    final sharedButtonStyle = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(
        Size(designUnit(AppSpacing.xxxl), minimumTouchTarget),
      ),
      padding: WidgetStatePropertyAll(
        EdgeInsets.symmetric(
          horizontal: designUnit(AppSpacing.lg),
          vertical: designUnit(AppSpacing.sm),
        ),
      ),
      shape: WidgetStatePropertyAll(standardShape),
      iconSize: WidgetStatePropertyAll(designUnit(20)),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      textTheme: textTheme,
      iconTheme: IconThemeData(
        color: colorScheme.onSurfaceVariant,
        size: designUnit(AppSpacing.lg),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: const Color(0x00000000),
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        clipBehavior: Clip.antiAlias,
        color: colorScheme.surfaceContainerLow,
        surfaceTintColor: const Color(0x00000000),
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: standardShape,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surfaceContainerHigh,
        surfaceTintColor: const Color(0x00000000),
        elevation: 0,
        shape: standardShape,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerLow,
        contentPadding: EdgeInsets.symmetric(
          horizontal: designUnit(AppSpacing.md),
          vertical: designUnit(AppSpacing.sm),
        ),
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
          borderSide: BorderSide(
            color: colorScheme.primary,
            width: designUnit(2),
          ),
        ),
        errorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: colorScheme.error),
        ),
        focusedErrorBorder: inputBorder.copyWith(
          borderSide: BorderSide(
            color: colorScheme.error,
            width: designUnit(2),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(style: sharedButtonStyle),
      outlinedButtonTheme: OutlinedButtonThemeData(style: sharedButtonStyle),
      textButtonTheme: TextButtonThemeData(style: sharedButtonStyle),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          minimumSize: WidgetStatePropertyAll(Size.square(minimumTouchTarget)),
          padding: WidgetStatePropertyAll(
            EdgeInsets.all(designUnit(AppSpacing.xs)),
          ),
          iconSize: WidgetStatePropertyAll(designUnit(AppSpacing.lg)),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant,
        thickness: designUnit(1),
        space: designUnit(AppSpacing.md),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: colorScheme.primary,
        selectionColor: colorScheme.primaryContainer,
        selectionHandleColor: colorScheme.primary,
      ),
    );
  }
}

double _identityDesignUnit(num value) => value.toDouble();

// 模板色板刻意组合青绿、暖红与蓝色语义角色，避免默认界面退化成单一色相。
const _lightColorScheme = ColorScheme(
  brightness: Brightness.light,
  primary: Color(0xFF006B5F),
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFF9EF2DF),
  onPrimaryContainer: Color(0xFF00201B),
  secondary: Color(0xFF8A4F43),
  onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: Color(0xFFFFDAD2),
  onSecondaryContainer: Color(0xFF35100A),
  tertiary: Color(0xFF3E5F8A),
  onTertiary: Color(0xFFFFFFFF),
  tertiaryContainer: Color(0xFFD6E3FF),
  onTertiaryContainer: Color(0xFF071C36),
  error: Color(0xFFBA1A1A),
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFFFFDAD6),
  onErrorContainer: Color(0xFF410002),
  surface: Color(0xFFF8FAF7),
  onSurface: Color(0xFF191C1B),
  surfaceDim: Color(0xFFD8DBD8),
  surfaceBright: Color(0xFFF8FAF7),
  surfaceContainerLowest: Color(0xFFFFFFFF),
  surfaceContainerLow: Color(0xFFF2F4F1),
  surfaceContainer: Color(0xFFECEEEB),
  surfaceContainerHigh: Color(0xFFE6E9E6),
  surfaceContainerHighest: Color(0xFFE1E3E0),
  onSurfaceVariant: Color(0xFF404946),
  outline: Color(0xFF707976),
  outlineVariant: Color(0xFFBFC9C5),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
  inverseSurface: Color(0xFF2D3130),
  onInverseSurface: Color(0xFFEFF1EE),
  inversePrimary: Color(0xFF82D5C3),
  surfaceTint: Color(0xFF006B5F),
);

const _darkColorScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFF82D5C3),
  onPrimary: Color(0xFF00382F),
  primaryContainer: Color(0xFF005047),
  onPrimaryContainer: Color(0xFF9EF2DF),
  secondary: Color(0xFFFFB4A5),
  onSecondary: Color(0xFF532019),
  secondaryContainer: Color(0xFF6E362D),
  onSecondaryContainer: Color(0xFFFFDAD2),
  tertiary: Color(0xFFA9C7F7),
  onTertiary: Color(0xFF0D305C),
  tertiaryContainer: Color(0xFF264775),
  onTertiaryContainer: Color(0xFFD6E3FF),
  error: Color(0xFFFFB4AB),
  onError: Color(0xFF690005),
  errorContainer: Color(0xFF93000A),
  onErrorContainer: Color(0xFFFFDAD6),
  surface: Color(0xFF101412),
  onSurface: Color(0xFFE1E3E0),
  surfaceDim: Color(0xFF101412),
  surfaceBright: Color(0xFF363A38),
  surfaceContainerLowest: Color(0xFF0C0F0E),
  surfaceContainerLow: Color(0xFF191C1B),
  surfaceContainer: Color(0xFF1D201F),
  surfaceContainerHigh: Color(0xFF272A28),
  surfaceContainerHighest: Color(0xFF323532),
  onSurfaceVariant: Color(0xFFBFC9C5),
  outline: Color(0xFF89938F),
  outlineVariant: Color(0xFF404946),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
  inverseSurface: Color(0xFFE1E3E0),
  onInverseSurface: Color(0xFF2D3130),
  inversePrimary: Color(0xFF006B5F),
  surfaceTint: Color(0xFF82D5C3),
);
