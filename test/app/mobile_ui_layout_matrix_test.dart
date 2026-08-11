import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_template/app/localization/app_locale.dart';
import 'package:flutter_template/app/localization/app_localizations.dart';
import 'package:flutter_template/app/router/app_router.dart';
import 'package:flutter_template/app/state/app_locale_controller.dart';
import 'package:flutter_template/app/state/app_state_scope.dart';
import 'package:flutter_template/app/theme/app_theme.dart';
import 'package:flutter_template/features/example/data/bundled_example_repository.dart';
import 'package:flutter_template/features/example/presentation/example_detail_controller.dart';
import 'package:flutter_template/shared/layout/app_screen_adaptation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/widgets/test_widget_environment.dart';

void main() {
  for (final localeCase in _localeCases) {
    for (final viewport in supportedPhoneViewports) {
      for (final textScaleCase in _textScaleCases) {
        testWidgets('core route flow fits ${viewport.name} with '
            '${textScaleCase.name} in ${localeCase.name}', (tester) async {
          final router = AppRouter(appName: _appName);
          final semanticsHandle = tester.ensureSemantics();
          try {
            await pumpTestWidget(
              tester,
              _routerHost(
                router: router,
                viewport: viewport,
                textScaler: textScaleCase.scaler,
                localePreference: localeCase.preference,
              ),
              surfaceSize: viewport.size,
              padding: viewport.safeInsets,
              viewPadding: viewport.safeInsets,
            );
            await tester.pumpAndSettle();

            final home = find.byKey(const Key('template-home-route'));
            final homeAction = find.byKey(const Key('open-example-detail'));
            expect(home, findsOneWidget);
            expect(Directionality.of(tester.element(home)), TextDirection.ltr);
            _expectHeaderSemantics(tester, find.text(_appName));
            await _expectScrollableActionIsReachable(
              tester,
              action: homeAction,
              page: home,
              reason: '${viewport.name}/${textScaleCase.name} home action',
            );
            _expectButtonSemantics(tester, homeAction);

            await tester.tap(homeAction);
            await tester.pumpAndSettle();

            final detail = find.byKey(const Key('template-detail-route'));
            final detailBack = find.byKey(const Key('example-detail-back'));
            expect(detail, findsOneWidget);
            expect(find.text('Example record'), findsOneWidget);
            _expectHeaderSemantics(tester, find.text('Example record'));
            _expectTargetInside(
              tester,
              target: detailBack,
              bounds: _safeRect(viewport),
              reason: '${viewport.name}/${textScaleCase.name} detail back',
            );
            _expectButtonSemantics(tester, detailBack);

            await tester.tap(detailBack);
            await tester.pumpAndSettle();
            expect(home, findsOneWidget);

            final homeContext = tester.element(home);
            GoRouter.of(homeContext).go('/missing/private-layout-probe');
            await tester.pumpAndSettle();

            final problem = find.byKey(const Key('app-route-problem'));
            final returnHome = find.byKey(const Key('return-home'));
            expect(problem, findsOneWidget);
            expect(find.byKey(const Key('unknown-route')), findsOneWidget);
            expect(find.textContaining('private-layout-probe'), findsNothing);
            _expectHeaderSemantics(
              tester,
              find.text(localeCase.unknownRouteTitle),
            );
            await _expectScrollableActionIsReachable(
              tester,
              action: returnHome,
              page: problem,
              reason: '${viewport.name}/${textScaleCase.name} return action',
            );
            _expectButtonSemantics(tester, returnHome);

            await tester.tap(returnHome);
            await tester.pumpAndSettle();
            expect(home, findsOneWidget);
            expect(tester.takeException(), isNull);
          } finally {
            router.dispose();
            semanticsHandle.dispose();
          }
        });
      }
    }
  }
}

const String _appName = 'Flutter Template';
const double _geometryTolerance = 0.01;

const List<({String name, TextScaler scaler})> _textScaleCases =
    <({String name, TextScaler scaler})>[
      (name: 'normal text', scaler: TextScaler.noScaling),
      (name: '200% system text', scaler: largeTestTextScaler),
    ];

const List<
  ({String name, AppLocalePreference preference, String unknownRouteTitle})
>
_localeCases =
    <({String name, AppLocalePreference preference, String unknownRouteTitle})>[
      (
        name: 'English',
        preference: AppLocalePreference.english,
        unknownRouteTitle: 'Page not found',
      ),
      (
        name: 'Chinese',
        preference: AppLocalePreference.chinese,
        unknownRouteTitle: '页面不存在',
      ),
    ];

Widget _routerHost({
  required AppRouter router,
  required TestPhoneViewport viewport,
  required TextScaler textScaler,
  required AppLocalePreference localePreference,
}) {
  return AppStateScope(
    overrides: <Override>[
      exampleRepositoryProvider.overrideWithValue(
        const BundledExampleRepository(),
      ),
      appInitialLocalePreferenceProvider.overrideWithValue(localePreference),
    ],
    child: AppScreenAdaptation(
      builder:
          (adaptedContext) => MaterialApp.router(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(adaptedContext),
            darkTheme: AppTheme.dark(adaptedContext),
            locale: localePreference.explicitLocale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            localeListResolutionCallback: resolveAppLocale,
            routerConfig: router.routerConfig,
            builder: createTestMediaQueryBuilder(
              textScaler: textScaler,
              padding: viewport.safeInsets,
              viewPadding: viewport.safeInsets,
            ),
          ),
    ),
  );
}

Future<void> _expectScrollableActionIsReachable(
  WidgetTester tester, {
  required Finder action,
  required Finder page,
  required String reason,
}) async {
  final scrollView = find.descendant(
    of: page,
    matching: find.byType(CustomScrollView),
  );
  expect(scrollView, findsOneWidget, reason: reason);

  await tester.ensureVisible(action);
  await tester.pumpAndSettle();
  _expectTargetInside(
    tester,
    target: action,
    bounds: tester.getRect(scrollView),
    reason: reason,
  );
}

void _expectTargetInside(
  WidgetTester tester, {
  required Finder target,
  required Rect bounds,
  required String reason,
}) {
  final targetRect = tester.getRect(target);
  expect(
    targetRect.left,
    greaterThanOrEqualTo(bounds.left - _geometryTolerance),
    reason: reason,
  );
  expect(
    targetRect.top,
    greaterThanOrEqualTo(bounds.top - _geometryTolerance),
    reason: reason,
  );
  expect(
    targetRect.right,
    lessThanOrEqualTo(bounds.right + _geometryTolerance),
    reason: reason,
  );
  expect(
    targetRect.bottom,
    lessThanOrEqualTo(bounds.bottom + _geometryTolerance),
    reason: reason,
  );
  expect(
    targetRect.width,
    greaterThanOrEqualTo(48 - _geometryTolerance),
    reason: reason,
  );
  expect(
    targetRect.height,
    greaterThanOrEqualTo(48 - _geometryTolerance),
    reason: reason,
  );
}

Rect _safeRect(TestPhoneViewport viewport) {
  return Rect.fromLTRB(
    viewport.safeInsets.left,
    viewport.safeInsets.top,
    viewport.size.width - viewport.safeInsets.right,
    viewport.size.height - viewport.safeInsets.bottom,
  );
}

void _expectHeaderSemantics(WidgetTester tester, Finder finder) {
  expect(tester.getSemantics(finder).hasFlag(SemanticsFlag.isHeader), isTrue);
}

void _expectButtonSemantics(WidgetTester tester, Finder finder) {
  final semantics = tester.getSemantics(finder);
  expect(semantics.hasFlag(SemanticsFlag.isButton), isTrue);
  expect(semantics.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
}
