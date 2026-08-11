import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_template/app/config/app_config.dart';
import 'package:flutter_template/app/localization/app_locale.dart';
import 'package:flutter_template/app/localization/app_locale_persistence.dart';
import 'package:flutter_template/app/router/app_route_redirect_policy.dart';
import 'package:flutter_template/app/state/app_locale_controller.dart';
import 'package:flutter_template/app/state/app_state_scope.dart';
import 'package:flutter_template/app/state/app_theme_mode_controller.dart';
import 'package:flutter_template/app/template_app.dart';
import 'package:flutter_template/features/example/data/bundled_example_repository.dart';
import 'package:flutter_template/features/example/presentation/example_detail_controller.dart';
import 'package:flutter_template/shared/layout/app_screen_adaptation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/storage/in_memory_preference_store.dart';
import '../support/widgets/test_widget_environment.dart';

void main() {
  testWidgets('renders the selected environment application name', (
    tester,
  ) async {
    final config = AppConfig.fromValues(environment: 'dev');

    await pumpTestWidget(
      tester,
      _applicationUnderTest(config),
      surfaceSize: referencePhoneSurfaceSize,
    );
    await tester.pumpAndSettle();

    expect(find.text('Flutter Template Dev'), findsOneWidget);
    expect(find.byKey(const Key('template-app-symbol')), findsOneWidget);
    expect(find.byType(AppScreenAdaptation), findsOneWidget);
    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.themeMode, ThemeMode.system);
    expect(materialApp.theme?.useMaterial3, isTrue);
    expect(materialApp.darkTheme?.useMaterial3, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('responds to the application theme mode controller', (
    tester,
  ) async {
    final config = AppConfig.fromValues(environment: 'staging');
    await pumpTestWidget(
      tester,
      _applicationUnderTest(config),
      surfaceSize: referencePhoneSurfaceSize,
    );
    await tester.pumpAndSettle();
    final container = _providerContainer(tester);

    for (final entry
        in <ThemeMode, Brightness>{
          ThemeMode.light: Brightness.light,
          ThemeMode.dark: Brightness.dark,
        }.entries) {
      container.read(appThemeModeProvider.notifier).setThemeMode(entry.key);
      await tester.pumpAndSettle();

      final textContext = tester.element(find.text('Flutter Template Staging'));
      expect(Theme.of(textContext).brightness, entry.value);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('theme updates preserve the current router location', (
    tester,
  ) async {
    final config = AppConfig.fromValues(environment: 'staging');

    await pumpTestWidget(
      tester,
      _applicationUnderTest(config),
      surfaceSize: referencePhoneSurfaceSize,
    );
    await tester.pumpAndSettle();
    final container = _providerContainer(tester);
    container.read(appThemeModeProvider.notifier).setThemeMode(ThemeMode.light);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-example-detail')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('template-detail-route')), findsOneWidget);

    container.read(appThemeModeProvider.notifier).setThemeMode(ThemeMode.dark);
    await tester.pumpAndSettle();

    final detailContext = tester.element(
      find.byKey(const Key('template-detail-route')),
    );
    expect(Theme.of(detailContext).brightness, Brightness.dark);
    expect(find.text('Item #1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('language menu switches immediately and preserves navigation', (
    tester,
  ) async {
    final config = AppConfig.fromValues(environment: 'dev');
    final store = InMemoryPreferenceStore();
    final persistence = PreferenceStoreAppLocalePersistence(store);
    await pumpTestWidget(
      tester,
      _applicationUnderTest(config, localePersistence: persistence),
      surfaceSize: referencePhoneSurfaceSize,
    );
    await tester.pumpAndSettle();
    final container = _providerContainer(tester);

    await tester.tap(find.byKey(const Key('language-menu')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is CheckedPopupMenuItem<AppLocalePreference> &&
            widget.value == AppLocalePreference.chinese,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      container.read(appLocalePreferenceProvider),
      AppLocalePreference.chinese,
    );
    expect(find.text('打开示例详情'), findsOneWidget);
    expect(find.text('1 个示例条目'), findsOneWidget);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).locale,
      const Locale('zh'),
    );
    expect(
      Directionality.of(
        tester.element(find.byKey(const Key('template-home-route'))),
      ),
      TextDirection.ltr,
    );
    expect(await persistence.load(), AppLocalePreference.chinese);

    await tester.tap(find.byKey(const Key('open-example-detail')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('template-detail-route')), findsOneWidget);
    expect(find.text('示例详情'), findsOneWidget);
    expect(find.text('条目编号：1'), findsOneWidget);
    final shellNavigator = tester.state<NavigatorState>(
      find.byType(Navigator).last,
    );

    final saved = await container
        .read(appLocalePreferenceProvider.notifier)
        .setPreference(AppLocalePreference.english);
    await tester.pumpAndSettle();

    expect(saved, isTrue);
    expect(find.byKey(const Key('template-detail-route')), findsOneWidget);
    expect(find.text('Example detail'), findsOneWidget);
    expect(find.text('Item #1'), findsOneWidget);
    expect(
      tester.state<NavigatorState>(find.byType(Navigator).last),
      same(shellNavigator),
    );
    expect(await persistence.load(), AppLocalePreference.english);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed language persistence rolls back with safe feedback', (
    tester,
  ) async {
    final config = AppConfig.fromValues(environment: 'dev');
    await pumpTestWidget(
      tester,
      _applicationUnderTest(
        config,
        localePersistence: const _FailingLocalePersistence(),
      ),
      surfaceSize: referencePhoneSurfaceSize,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('language-menu')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is CheckedPopupMenuItem<AppLocalePreference> &&
            widget.value == AppLocalePreference.chinese,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Open example detail'), findsOneWidget);
    expect(find.text('打开示例详情'), findsNothing);
    expect(
      find.text('Language preference could not be saved.'),
      findsOneWidget,
    );
    expect(
      _providerContainer(tester).read(appLocalePreferenceProvider),
      AppLocalePreference.english,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('replaces the router safely when application inputs change', (
    tester,
  ) async {
    final devConfig = AppConfig.fromValues(environment: 'dev');
    final stagingConfig = AppConfig.fromValues(environment: 'staging');

    await pumpTestWidget(
      tester,
      _applicationUnderTest(devConfig),
      surfaceSize: referencePhoneSurfaceSize,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-example-detail')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('template-detail-route')), findsOneWidget);

    // 配置变化会替换 Router；旧 Router 的释放不得影响 MaterialApp 切换到新配置。
    await tester.pumpWidget(_applicationUnderTest(stagingConfig));
    await tester.pumpAndSettle();

    expect(find.text('Flutter Template Staging'), findsOneWidget);
    expect(find.byKey(const Key('template-home-route')), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 策略实例变化同样必须替换 Router，并让随后导航使用新策略而非已释放的旧配置。
    await tester.pumpWidget(
      _applicationUnderTest(
        stagingConfig,
        redirectPolicy: const _RedirectExampleToHomePolicy(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-example-detail')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('template-home-route')), findsOneWidget);
    expect(find.byKey(const Key('template-detail-route')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fits a narrow phone viewport', (tester) async {
    final config = AppConfig.fromValues(environment: 'prod');

    await pumpTestWidget(
      tester,
      _applicationUnderTest(config),
      surfaceSize: narrowPhoneSurfaceSize,
    );
    await tester.pumpAndSettle();

    expect(find.text('Flutter Template'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget _applicationUnderTest(
  AppConfig config, {
  AppRouteRedirectPolicy redirectPolicy =
      const AllowAllAppRouteRedirectPolicy(),
  AppLocalePreference initialLocalePreference = AppLocalePreference.english,
  AppLocalePreferencePersistence? localePersistence,
}) {
  return AppStateScope(
    overrides: [
      exampleRepositoryProvider.overrideWithValue(BundledExampleRepository()),
      appInitialLocalePreferenceProvider.overrideWithValue(
        initialLocalePreference,
      ),
      appLocalePreferencePersistenceProvider.overrideWithValue(
        localePersistence,
      ),
    ],
    child: TemplateApp(config: config, redirectPolicy: redirectPolicy),
  );
}

ProviderContainer _providerContainer(WidgetTester tester) {
  final context = tester.element(find.byType(MaterialApp));
  return ProviderScope.containerOf(context, listen: false);
}

final class _RedirectExampleToHomePolicy implements AppRouteRedirectPolicy {
  const _RedirectExampleToHomePolicy();

  @override
  Uri? redirect(AppRouteRedirectRequest request) {
    return request.uri.path.startsWith('/example/') ? Uri(path: '/') : null;
  }
}

final class _FailingLocalePersistence
    implements AppLocalePreferencePersistence {
  const _FailingLocalePersistence();

  @override
  Future<AppLocalePreference> load() async => AppLocalePreference.system;

  @override
  Future<void> save(AppLocalePreference preference) {
    return Future<void>.error(StateError('controlled preference failure'));
  }
}
