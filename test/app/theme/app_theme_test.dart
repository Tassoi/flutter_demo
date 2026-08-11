import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_template/app/theme/app_theme.dart';
import 'package:flutter_template/shared/design/app_layout_tokens.dart';
import 'package:flutter_template/shared/layout/app_screen_adaptation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/widgets/test_widget_environment.dart';

void main() {
  group('AppTheme', () {
    testWidgets('builds distinct Material 3 themes inside the adapted root', (
      tester,
    ) async {
      configureTestView(tester, referencePhoneSurfaceSize);
      late ThemeData light;
      late ThemeData dark;

      await tester.pumpWidget(
        AppScreenAdaptation(
          builder: (context) {
            light = AppTheme.light(context);
            dark = AppTheme.dark(context);
            return const SizedBox.shrink();
          },
        ),
      );
      await tester.pump();

      expect(light.useMaterial3, isTrue);
      expect(dark.useMaterial3, isTrue);
      expect(light.brightness, Brightness.light);
      expect(dark.brightness, Brightness.dark);
      expect(light.colorScheme.primary, isNot(dark.colorScheme.primary));
      expect(light.scaffoldBackgroundColor, light.colorScheme.surface);
      expect(dark.scaffoldBackgroundColor, dark.colorScheme.surface);
      expect(tester.takeException(), isNull);
    });

    test('keeps the startup fallback independent at the reference scale', () {
      final light = AppTheme.fallbackLight();
      final dark = AppTheme.fallbackDark();

      expect(light.textTheme.bodyLarge?.fontSize, 16);
      expect(dark.textTheme.bodyLarge?.fontSize, 16);
      expect(_cardRadius(light), AppRadii.medium);
      expect(_cardRadius(dark), AppRadii.medium);
      expect(
        light.filledButtonTheme.style?.minimumSize?.resolve(<WidgetState>{}),
        const Size(64, 48),
      );
    });

    test('keeps key semantic color pairs readable', () {
      for (final theme in <ThemeData>[
        AppTheme.fallbackLight(),
        AppTheme.fallbackDark(),
      ]) {
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

    testWidgets('scales typography and component tokens at every viewport', (
      tester,
    ) async {
      configureTestView(tester, supportedPhoneViewports.first.size);
      late ThemeData theme;
      final host = AppScreenAdaptation(
        builder: (context) {
          theme = AppTheme.light(context);
          return const SizedBox.shrink();
        },
      );

      for (final viewport in supportedPhoneViewports) {
        tester.view.physicalSize = viewport.size;
        await tester.pumpWidget(host);
        await tester.pump();

        final scale = viewport.size.width / appDesignSize.width;
        final expectedTouchTarget = math.max(48.0, 48 * scale);
        final inputPadding =
            theme.inputDecorationTheme.contentPadding! as EdgeInsets;
        final inputBorder =
            theme.inputDecorationTheme.border! as OutlineInputBorder;
        final buttonSize = theme.filledButtonTheme.style?.minimumSize?.resolve(
          <WidgetState>{},
        );

        expect(
          theme.textTheme.bodyLarge?.fontSize,
          closeTo(16 * scale, _epsilon),
          reason: viewport.name,
        );
        expect(
          _cardRadius(theme),
          closeTo(AppRadii.medium * scale, _epsilon),
          reason: viewport.name,
        );
        expect(
          inputBorder.borderRadius.topLeft.x,
          closeTo(AppRadii.medium * scale, _epsilon),
          reason: viewport.name,
        );
        expect(
          inputPadding.left,
          closeTo(AppSpacing.md * scale, _epsilon),
          reason: viewport.name,
        );
        expect(
          theme.dividerTheme.thickness,
          closeTo(scale, _epsilon),
          reason: viewport.name,
        );
        expect(
          theme.iconTheme.size,
          closeTo(AppSpacing.lg * scale, _epsilon),
          reason: viewport.name,
        );
        expect(
          buttonSize?.height,
          closeTo(expectedTouchTarget, _epsilon),
          reason: viewport.name,
        );
        expect(
          buttonSize?.width,
          closeTo(AppSpacing.xxxl * scale, _epsilon),
          reason: viewport.name,
        );
        for (final style in _allTextStyles(theme.textTheme)) {
          expect(style, isNotNull, reason: viewport.name);
          expect(style!.letterSpacing, 0, reason: viewport.name);
        }
        expect(tester.takeException(), isNull, reason: viewport.name);
      }
    });
  });

  test('layout tokens remain a small monotonic design scale', () {
    final spacingValues = <double>[
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

const double _epsilon = 0.0001;

double _cardRadius(ThemeData theme) {
  final shape = theme.cardTheme.shape! as RoundedRectangleBorder;
  final radius = shape.borderRadius as BorderRadius;
  return radius.topLeft.x;
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
