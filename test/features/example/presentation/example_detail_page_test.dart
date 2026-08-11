import 'package:flutter/material.dart';
import 'package:flutter_template/app/state/app_state_scope.dart';
import 'package:flutter_template/app/theme/app_theme.dart';
import 'package:flutter_template/core/error/app_error.dart';
import 'package:flutter_template/features/example/domain/example_item.dart';
import 'package:flutter_template/features/example/presentation/example_detail_controller.dart';
import 'package:flutter_template/features/example/presentation/example_detail_copy.dart';
import 'package:flutter_template/features/example/presentation/example_detail_page.dart';
import 'package:flutter_template/shared/layout/app_screen_adaptation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/features/example/controlled_example_repository.dart';
import '../../../support/features/example/example_item_fixture.dart';
import '../../../support/widgets/test_widget_environment.dart';

void main() {
  testWidgets('renders loading, data and the application-owned back action', (
    tester,
  ) async {
    final repository = ControlledExampleRepository();
    var backCount = 0;
    await pumpTestWidget(
      tester,
      _pageHost(repository: repository, onBack: () => backCount++),
      surfaceSize: referencePhoneSurfaceSize,
    );

    expect(find.byKey(const Key('example-detail-loading')), findsOneWidget);
    expect(repository.requests.single.itemId, 1);

    repository.requests.single.succeed(createExampleItemFixture());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('example-detail-data')), findsOneWidget);
    expect(find.text('Example record'), findsOneWidget);
    expect(
      find.text('A neutral description for the selected record.'),
      findsOneWidget,
    );
    expect(find.text('Item #1'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('example-detail-back'))).height,
      greaterThanOrEqualTo(48),
    );

    await tester.tap(find.byKey(const Key('example-detail-back')));
    expect(backCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders successful empty data and forwards its exit action', (
    tester,
  ) async {
    final repository = ControlledExampleRepository();
    var backCount = 0;
    await pumpTestWidget(
      tester,
      _pageHost(repository: repository, onBack: () => backCount++),
      surfaceSize: referencePhoneSurfaceSize,
    );

    repository.requests.single.succeed(null);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('example-detail-empty')), findsOneWidget);
    expect(find.text('Item unavailable'), findsOneWidget);
    await tester.tap(find.text('Back to home'));
    expect(backCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows a stable error and retries through the controller', (
    tester,
  ) async {
    final repository = ControlledExampleRepository();
    await pumpTestWidget(
      tester,
      _pageHost(repository: repository),
      surfaceSize: referencePhoneSurfaceSize,
    );

    repository.requests.single.fail(
      StateError('private-page-token'),
      StackTrace.current,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('example-detail-error')), findsOneWidget);
    expect(find.text('Something went wrong.'), findsOneWidget);
    expect(find.textContaining('private-page-token'), findsNothing);

    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(find.byKey(const Key('example-detail-loading')), findsOneWidget);
    expect(repository.requests, hasLength(2));

    repository.requests.last.succeed(
      createExampleItemFixture(
        title: 'Recovered',
        description: 'Available again',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('example-detail-data')), findsOneWidget);
    expect(find.text('Recovered'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('data fits a narrow short viewport with large text', (
    tester,
  ) async {
    final repository = ControlledExampleRepository();
    await pumpTestWidget(
      tester,
      _pageHost(repository: repository, textScaler: largeTestTextScaler),
      surfaceSize: narrowPhoneSurfaceSize,
    );

    repository.requests.single.succeed(
      createExampleItemFixture(
        id: 1,
        title: List<String>.filled(ExampleItem.maximumTitleLength, 'W').join(),
        description:
            List<String>.filled(
              ExampleItem.maximumDescriptionLength,
              'x',
            ).join(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('example-detail-data')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('other states fit a narrow short viewport with large text', (
    tester,
  ) async {
    final repository = ControlledExampleRepository();
    await pumpTestWidget(
      tester,
      _pageHost(repository: repository, textScaler: largeTestTextScaler),
      surfaceSize: narrowPhoneSurfaceSize,
    );

    expect(find.byKey(const Key('example-detail-loading')), findsOneWidget);
    expect(tester.takeException(), isNull);

    repository.requests.single.fail(
      StateError('private-narrow-page-token'),
      StackTrace.current,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('example-detail-error')), findsOneWidget);
    expect(find.textContaining('private-narrow-page-token'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('Try again'));
    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(find.byKey(const Key('example-detail-loading')), findsOneWidget);
    repository.requests.last.succeed(null);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('example-detail-empty')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget _pageHost({
  required ControlledExampleRepository repository,
  VoidCallback? onBack,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  return AppStateScope(
    overrides: [exampleRepositoryProvider.overrideWithValue(repository)],
    child: AppScreenAdaptation(
      builder:
          (adaptedContext) => MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(adaptedContext),
            home: ExampleDetailPage(
              itemId: 1,
              copy: _englishCopy,
              onBack: onBack ?? () {},
            ),
            builder: createTestMediaQueryBuilder(textScaler: textScaler),
          ),
    ),
  );
}

final ExampleDetailCopy _englishCopy = ExampleDetailCopy(
  loadingMessage: 'Loading example item',
  errorTitle: 'Unable to load item',
  retryLabel: 'Try again',
  emptyTitle: 'Item unavailable',
  emptyMessage: 'No example item exists for this link.',
  backToHomeLabel: 'Back to home',
  backTooltip: 'Back',
  pageTitle: 'Example detail',
  errorMessage: (AppError _) => 'Something went wrong.',
  itemIdentifier: (int itemId) => 'Item #$itemId',
);
