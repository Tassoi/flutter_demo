import 'package:flutter/material.dart';
import 'package:flutter_template/app/localization/app_locale.dart';
import 'package:flutter_template/app/localization/app_localizations.dart';
import 'package:flutter_template/app/router/app_route_redirect_policy.dart';
import 'package:flutter_template/app/router/app_router.dart';
import 'package:flutter_template/app/state/app_state_scope.dart';
import 'package:flutter_template/app/theme/app_theme.dart';
import 'package:flutter_template/features/example/data/bundled_example_repository.dart';
import 'package:flutter_template/features/example/presentation/example_detail_controller.dart';
import 'package:flutter_template/features/example/routing/example_route_contract.dart';
import 'package:flutter_template/shared/layout/app_screen_adaptation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/widgets/test_widget_environment.dart';

void main() {
  test('validates construction and disposes idempotently', () {
    expect(() => AppRouter(appName: ' '), throwsArgumentError);

    final router = AppRouter(appName: 'Flutter Template');
    router.dispose();
    router.dispose();

    expect(() => router.routerConfig, throwsStateError);
  });

  testWidgets('home and detail routes stay inside the shell navigator', (
    tester,
  ) async {
    final router = AppRouter(appName: 'Flutter Template Dev');
    addTearDown(router.dispose);

    await pumpTestWidget(
      tester,
      _routerHost(router),
      surfaceSize: referencePhoneSurfaceSize,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('app-route-shell')), findsOneWidget);
    expect(find.byKey(const Key('template-home-route')), findsOneWidget);
    expect(find.text('Flutter Template Dev'), findsOneWidget);
    expect(find.byType(Navigator), findsNWidgets(2));
    expect(
      tester.getSize(find.byKey(const Key('open-example-detail'))).height,
      greaterThanOrEqualTo(48),
    );

    final homeContext = tester.element(
      find.byKey(const Key('template-home-route')),
    );
    GoRouter.of(
      homeContext,
    ).go(ExampleRouteContract.detailLocation(42).toString());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('template-detail-route')), findsOneWidget);
    expect(find.byKey(const Key('example-item-id')), findsOneWidget);
    expect(find.text('Item #42'), findsOneWidget);
    expect(_currentUri(tester), Uri(path: '/example/42'));
    expect(
      tester.getSize(find.byKey(const Key('example-detail-back'))).height,
      greaterThanOrEqualTo(48),
    );

    final detailContext = tester.element(
      find.byKey(const Key('template-detail-route')),
    );
    expect(
      Navigator.of(detailContext),
      isNot(same(Navigator.of(detailContext, rootNavigator: true))),
    );

    await tester.tap(find.byKey(const Key('example-detail-back')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('template-home-route')), findsOneWidget);
    expect(_currentUri(tester), Uri(path: '/'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('repeated detail back commands cannot pop past home', (
    tester,
  ) async {
    final router = AppRouter(appName: 'Flutter Template');
    addTearDown(router.dispose);
    await pumpTestWidget(
      tester,
      _routerHost(router),
      surfaceSize: referencePhoneSurfaceSize,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open-example-detail')));
    await tester.pumpAndSettle();
    final backButton = tester.widget<IconButton>(
      find.byKey(const Key('example-detail-back')),
    );

    // 两次同步调用模拟退出动画开始前的快速重复触发；第二次不得继续弹出首页所在路由。
    backButton.onPressed!();
    backButton.onPressed!();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('template-home-route')), findsOneWidget);
    expect(find.byKey(const Key('app-route-shell')), findsOneWidget);
    expect(_currentUri(tester), Uri(path: '/'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid detail parameters render a stable safe state', (
    tester,
  ) async {
    final router = AppRouter(appName: 'Flutter Template');
    addTearDown(router.dispose);
    await pumpTestWidget(
      tester,
      _routerHost(router),
      surfaceSize: referencePhoneSurfaceSize,
    );
    await tester.pumpAndSettle();

    for (final location in <String>[
      '/example/0',
      '/example/01',
      '/example/not-an-item',
      '/example/1000000000',
    ]) {
      final context = _routingContext(tester);
      GoRouter.of(context).go(location);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('invalid-route-parameter')), findsOneWidget);
      expect(find.textContaining(location), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('unknown locations never expose the rejected URI', (
    tester,
  ) async {
    final router = AppRouter(appName: 'Flutter Template');
    addTearDown(router.dispose);
    await pumpTestWidget(
      tester,
      _routerHost(router),
      surfaceSize: referencePhoneSurfaceSize,
    );
    await tester.pumpAndSettle();

    final context = tester.element(
      find.byKey(const Key('template-home-route')),
    );
    GoRouter.of(
      context,
    ).go('/missing/private-route-token?credential=private-value');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('unknown-route')), findsOneWidget);
    expect(find.textContaining('private-route-token'), findsNothing);
    expect(find.textContaining('private-value'), findsNothing);

    await tester.tap(find.text('Return home'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('template-home-route')), findsOneWidget);
    expect(_currentUri(tester), Uri(path: '/'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a replaceable policy redirects using project route data', (
    tester,
  ) async {
    final policy = _RecordingRedirectPolicy();
    final router = AppRouter(
      appName: 'Flutter Template',
      redirectPolicy: policy,
    );
    addTearDown(router.dispose);
    await pumpTestWidget(
      tester,
      _routerHost(router),
      surfaceSize: referencePhoneSurfaceSize,
    );
    await tester.pumpAndSettle();

    final context = tester.element(
      find.byKey(const Key('template-home-route')),
    );
    GoRouter.of(context).go(ExampleRouteContract.detailLocation(7).toString());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('template-home-route')), findsOneWidget);
    expect(_currentUri(tester), Uri(path: '/'));
    expect(policy.requests, contains(Uri(path: '/example/7')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('unsafe redirect targets use the safe route problem page', (
    tester,
  ) async {
    final router = AppRouter(
      appName: 'Flutter Template',
      redirectPolicy: const _UnsafeRedirectPolicy(),
    );
    addTearDown(router.dispose);
    await pumpTestWidget(
      tester,
      _routerHost(router),
      surfaceSize: referencePhoneSurfaceSize,
    );
    await tester.pumpAndSettle();

    final context = tester.element(
      find.byKey(const Key('template-home-route')),
    );
    GoRouter.of(context).go(ExampleRouteContract.detailLocation(2).toString());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('unknown-route')), findsOneWidget);
    expect(find.textContaining('private-redirect-token'), findsNothing);
    expect(find.textContaining('credential'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('redirect policy failures never expose exception details', (
    tester,
  ) async {
    final router = AppRouter(
      appName: 'Flutter Template',
      redirectPolicy: const _ThrowingRedirectPolicy(),
    );
    addTearDown(router.dispose);
    await pumpTestWidget(
      tester,
      _routerHost(router),
      surfaceSize: referencePhoneSurfaceSize,
    );
    await tester.pumpAndSettle();

    final context = tester.element(
      find.byKey(const Key('template-home-route')),
    );
    GoRouter.of(context).go(ExampleRouteContract.detailLocation(3).toString());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('unknown-route')), findsOneWidget);
    expect(find.textContaining('private-policy-credential'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('route states fit a narrow viewport with large text', (
    tester,
  ) async {
    final router = AppRouter(appName: 'Flutter Template');
    addTearDown(router.dispose);
    await pumpTestWidget(
      tester,
      _routerHost(router, textScaler: largeTestTextScaler),
      surfaceSize: narrowPhoneSurfaceSize,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    var context = tester.element(find.byKey(const Key('template-home-route')));
    GoRouter.of(context).go(ExampleRouteContract.detailLocation(9).toString());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('template-detail-route')), findsOneWidget);
    expect(tester.takeException(), isNull);

    context = tester.element(find.byKey(const Key('template-detail-route')));
    GoRouter.of(context).go('/example/invalid-private-value');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('invalid-route-parameter')), findsOneWidget);
    expect(find.textContaining('invalid-private-value'), findsNothing);
    expect(tester.takeException(), isNull);

    context = tester.element(find.byKey(const Key('app-route-problem')));
    GoRouter.of(context).go('/missing/private-route-token');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('unknown-route')), findsOneWidget);
    expect(find.textContaining('private-route-token'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Widget _routerHost(
  AppRouter router, {
  TextScaler textScaler = TextScaler.noScaling,
}) {
  return AppStateScope(
    overrides: [
      exampleRepositoryProvider.overrideWithValue(BundledExampleRepository()),
    ],
    child: AppScreenAdaptation(
      builder:
          (adaptedContext) => MaterialApp.router(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(adaptedContext),
            darkTheme: AppTheme.dark(adaptedContext),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            localeListResolutionCallback: resolveAppLocale,
            routerConfig: router.routerConfig,
            builder: createTestMediaQueryBuilder(textScaler: textScaler),
          ),
    ),
  );
}

BuildContext _routingContext(WidgetTester tester) {
  for (final key in const <Key>[
    Key('app-route-problem'),
    Key('template-detail-route'),
    Key('template-home-route'),
  ]) {
    final candidate = find.byKey(key);
    if (candidate.evaluate().isNotEmpty) {
      return tester.element(candidate);
    }
  }
  throw StateError('No active route context was found in the test tree.');
}

Uri _currentUri(WidgetTester tester) {
  return GoRouter.of(_routingContext(tester)).state.uri;
}

final class _RecordingRedirectPolicy implements AppRouteRedirectPolicy {
  final List<Uri> requests = <Uri>[];

  @override
  Uri? redirect(AppRouteRedirectRequest request) {
    requests.add(request.uri);
    if (request.uri.path == '/example/7') {
      return Uri(path: '/');
    }
    // 返回当前 URI 也必须视为放行，不能形成自重定向循环。
    return request.uri;
  }
}

final class _UnsafeRedirectPolicy implements AppRouteRedirectPolicy {
  const _UnsafeRedirectPolicy();

  @override
  Uri? redirect(AppRouteRedirectRequest request) {
    if (request.uri.path != '/example/2') {
      return null;
    }
    return Uri.parse(
      'https://api.example.invalid/private-redirect-token'
      '?credential=private-value',
    );
  }
}

final class _ThrowingRedirectPolicy implements AppRouteRedirectPolicy {
  const _ThrowingRedirectPolicy();

  @override
  Uri? redirect(AppRouteRedirectRequest request) {
    if (request.uri.path == '/example/3') {
      throw StateError('private-policy-credential');
    }
    return null;
  }
}
