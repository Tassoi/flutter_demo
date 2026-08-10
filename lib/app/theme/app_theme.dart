import 'package:flutter/material.dart';
import 'package:flutter_template/app/theme/app_typography.dart';
import 'package:flutter_template/shared/design/app_layout_tokens.dart';

/// 应用 Material 3 亮暗主题的唯一组装入口。
///
/// 颜色、排版和常用组件外观在此集中组合。Feature 应通过 [Theme.of] 和项目布局 token
/// 获取语义值，不应导入私有色板或复制颜色常量。[light] 与 [dark] 每次返回独立
/// [ThemeData]，不读取环境、平台存储或全局可变状态，因此正常应用和启动失败 fallback
/// 都可以安全使用。
abstract final class AppTheme {
  /// 创建亮色 Material 3 主题。
  static ThemeData light() => _build(_lightColorScheme);

  /// 创建暗色 Material 3 主题。
  static ThemeData dark() => _build(_darkColorScheme);

  static ThemeData _build(ColorScheme colorScheme) {
    final standardShape = RoundedRectangleBorder(
      borderRadius: AppRadii.mediumBorderRadius,
    );
    final inputBorder = OutlineInputBorder(
      borderRadius: AppRadii.mediumBorderRadius,
      borderSide: BorderSide(color: colorScheme.outline),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      textTheme: AppTypography.textTheme(colorScheme),
      iconTheme: IconThemeData(color: colorScheme.onSurfaceVariant),
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
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        errorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: colorScheme.error),
        ),
        focusedErrorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: colorScheme.error, width: 2),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant,
        thickness: 1,
        space: AppSpacing.md,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: colorScheme.primary,
        selectionColor: colorScheme.primaryContainer,
        selectionHandleColor: colorScheme.primary,
      ),
    );
  }
}

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
