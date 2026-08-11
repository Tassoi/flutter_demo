import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_template/app/localization/app_locale.dart';
import 'package:flutter_template/app/localization/app_localizations.dart';
import 'package:flutter_template/app/router/app_router.dart';
import 'package:flutter_template/app/state/app_locale_controller.dart';
import 'package:flutter_template/app/state/app_state_scope.dart';
import 'package:flutter_template/app/theme/app_theme.dart';
import 'package:flutter_template/features/example/data/bundled_example_repository.dart';
import 'package:flutter_template/features/example/presentation/example_detail_controller.dart';
import 'package:flutter_template/shared/assets/generated/template_icons.g.dart';
import 'package:flutter_template/shared/layout/app_screen_adaptation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/widgets/test_widget_environment.dart';

void main() {
  setUpAll(() async {
    // Widget 测试不会像平台应用包一样自动注册 pubspec 字体；Golden 必须显式加载
    // 生产 OTF，否则自定义 IconData 会被缺字方框替代并形成误导性的稳定基线。
    final FontLoader loader = FontLoader(TemplateIcons.fontFamily)
      ..addFont(rootBundle.load('assets/fonts/template_icons.otf'));
    await loader.load();
  });

  testWidgets(
    'home page matches the reference mobile golden',
    (tester) async {
      final router = AppRouter(appName: 'Flutter Template');
      final originalDisableShadows = debugDisableShadows;
      debugDisableShadows = true;
      try {
        await pumpTestWidget(
          tester,
          _goldenRouterHost(router),
          surfaceSize: referencePhoneSurfaceSize,
          padding: _referenceSafeInsets,
          viewPadding: _referenceSafeInsets,
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('template-home-route')), findsOneWidget);
        await expectLater(
          find.byKey(_goldenSurfaceKey),
          matchesGoldenFile(_goldenBaseline('home_reference_375x812.png')),
        );
        expect(tester.takeException(), isNull);
      } finally {
        router.dispose();
        debugDisableShadows = originalDisableShadows;
      }
    },
    skip: _goldenHostDirectory == null,
  );

  testWidgets(
    'example detail matches the reference mobile golden',
    (tester) async {
      final router = AppRouter(appName: 'Flutter Template');
      final originalDisableShadows = debugDisableShadows;
      debugDisableShadows = true;
      try {
        await pumpTestWidget(
          tester,
          _goldenRouterHost(router),
          surfaceSize: referencePhoneSurfaceSize,
          padding: _referenceSafeInsets,
          viewPadding: _referenceSafeInsets,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('open-example-detail')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('template-detail-route')), findsOneWidget);
        expect(find.text('Example record'), findsOneWidget);
        await expectLater(
          find.byKey(_goldenSurfaceKey),
          matchesGoldenFile(
            _goldenBaseline('example_detail_reference_375x812.png'),
          ),
        );
        expect(tester.takeException(), isNull);
      } finally {
        router.dispose();
        debugDisableShadows = originalDisableShadows;
      }
    },
    skip: _goldenHostDirectory == null,
  );
}

const Key _goldenSurfaceKey = Key('mobile-golden-surface');
const EdgeInsets _referenceSafeInsets = EdgeInsets.only(top: 44, bottom: 34);
final String? _goldenHostDirectory =
    Platform.isLinux
        ? 'linux'
        : Platform.isWindows
        ? 'windows'
        : null;

/// 返回当前受支持测试宿主的零容差 Golden 基线路径。
///
/// Ahem 固定字形和度量，但 Windows 与 Linux Flutter tester 对字形边缘的栅格化仍有一像素差异。
/// 两个平台因此维护各自经过审查的精确 PNG，而不是使用会掩盖小型真实回归的全局差异阈值。
/// 调用仅发生在未被 [testWidgets] 跳过的受支持宿主；新增宿主必须先生成并审查独立基线。
String _goldenBaseline(String fileName) {
  final hostDirectory = _goldenHostDirectory;
  if (hostDirectory == null) {
    throw StateError('当前测试宿主没有经过审查的 Golden 基线。');
  }
  return 'baselines/$hostDirectory/$fileName';
}

Widget _goldenRouterHost(AppRouter router) {
  final mediaQueryBuilder = createTestMediaQueryBuilder(
    padding: _referenceSafeInsets,
    viewPadding: _referenceSafeInsets,
  );

  return AppStateScope(
    overrides: <Override>[
      exampleRepositoryProvider.overrideWithValue(
        const BundledExampleRepository(),
      ),
      appInitialLocalePreferenceProvider.overrideWithValue(
        AppLocalePreference.english,
      ),
    ],
    child: AppScreenAdaptation(
      builder: (adaptedContext) {
        final theme = AppTheme.light(adaptedContext);
        final goldenTheme = theme.copyWith(
          // Ahem 只固定像素基线的字形和度量；生产主题仍保留平台系统字体与 TextScaler。
          textTheme: theme.textTheme.apply(fontFamily: 'Ahem'),
          primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: 'Ahem'),
        );

        return MaterialApp.router(
          debugShowCheckedModeBanner: false,
          theme: goldenTheme,
          themeAnimationDuration: Duration.zero,
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          localeListResolutionCallback: resolveAppLocale,
          routerConfig: router.routerConfig,
          builder:
              (context, child) => mediaQueryBuilder(
                context,
                RepaintBoundary(key: _goldenSurfaceKey, child: child!),
              ),
        );
      },
    ),
  );
}
