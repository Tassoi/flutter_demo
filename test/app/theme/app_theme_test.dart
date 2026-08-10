import 'package:flutter/material.dart';
import 'package:flutter_template/app/theme/app_theme.dart';
import 'package:flutter_template/shared/design/app_layout_tokens.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppTheme', () {
    test('builds distinct Material 3 light and dark themes', () {
      final light = AppTheme.light();
      final dark = AppTheme.dark();

      expect(light.useMaterial3, isTrue);
      expect(dark.useMaterial3, isTrue);
      expect(light.brightness, Brightness.light);
      expect(dark.brightness, Brightness.dark);
      expect(light.colorScheme.primary, isNot(dark.colorScheme.primary));
      expect(light.scaffoldBackgroundColor, light.colorScheme.surface);
      expect(dark.scaffoldBackgroundColor, dark.colorScheme.surface);
    });

    test('keeps key semantic color pairs readable', () {
      for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
        final scheme = theme.colorScheme;

        expect(
          _contrastRatio(scheme.primary, scheme.onPrimary),
          greaterThan(4.5),
        );
        expect(
          _contrastRatio(scheme.secondary, scheme.onSecondary),
          greaterThan(4.5),
        );
        expect(
          _contrastRatio(scheme.tertiary, scheme.onTertiary),
          greaterThan(4.5),
        );
        expect(
          _contrastRatio(scheme.surface, scheme.onSurface),
          greaterThan(4.5),
        );
        expect(_contrastRatio(scheme.error, scheme.onError), greaterThan(4.5));
        expect(
          _contrastRatio(scheme.primaryContainer, scheme.onPrimaryContainer),
          greaterThan(4.5),
        );
        expect(
          _contrastRatio(
            scheme.secondaryContainer,
            scheme.onSecondaryContainer,
          ),
          greaterThan(4.5),
        );
        expect(
          _contrastRatio(scheme.tertiaryContainer, scheme.onTertiaryContainer),
          greaterThan(4.5),
        );
        expect(
          _contrastRatio(scheme.errorContainer, scheme.onErrorContainer),
          greaterThan(4.5),
        );
      }
    });

    test('applies the shared radius and typography rules', () {
      for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
        final cardShape = theme.cardTheme.shape;
        final dialogShape = theme.dialogTheme.shape;
        final inputBorder = theme.inputDecorationTheme.border;

        expect(cardShape, isA<RoundedRectangleBorder>());
        expect(
          (cardShape! as RoundedRectangleBorder).borderRadius,
          AppRadii.mediumBorderRadius,
        );
        expect(dialogShape, isA<RoundedRectangleBorder>());
        expect(
          (dialogShape! as RoundedRectangleBorder).borderRadius,
          AppRadii.mediumBorderRadius,
        );
        expect(inputBorder, isA<OutlineInputBorder>());
        expect(
          (inputBorder! as OutlineInputBorder).borderRadius,
          AppRadii.mediumBorderRadius,
        );

        for (final style in _allTextStyles(theme.textTheme)) {
          expect(style, isNotNull);
          expect(style!.letterSpacing, 0);
        }
      }
    });
  });

  test('layout tokens form a small monotonic scale', () {
    final List<double> spacingValues = <double>[
      AppSpacing.xxs,
      AppSpacing.xs,
      AppSpacing.sm,
      AppSpacing.md,
      AppSpacing.lg,
      AppSpacing.xl,
      AppSpacing.xxl,
      AppSpacing.xxxl,
    ];

    expect(
      spacingValues,
      orderedEquals(<double>[4, 8, 12, 16, 24, 32, 48, 64]),
    );
    expect(AppRadii.small, 4);
    expect(AppRadii.medium, 8);
  });
}

List<TextStyle?> _allTextStyles(TextTheme textTheme) => <TextStyle?>[
  textTheme.displayLarge,
  textTheme.displayMedium,
  textTheme.displaySmall,
  textTheme.headlineLarge,
  textTheme.headlineMedium,
  textTheme.headlineSmall,
  textTheme.titleLarge,
  textTheme.titleMedium,
  textTheme.titleSmall,
  textTheme.bodyLarge,
  textTheme.bodyMedium,
  textTheme.bodySmall,
  textTheme.labelLarge,
  textTheme.labelMedium,
  textTheme.labelSmall,
];

double _contrastRatio(Color first, Color second) {
  final firstLuminance = first.computeLuminance();
  final secondLuminance = second.computeLuminance();
  final lighter =
      firstLuminance > secondLuminance ? firstLuminance : secondLuminance;
  final darker =
      firstLuminance > secondLuminance ? secondLuminance : firstLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}
