import 'package:flutter/material.dart';
import 'package:flutter_template/app/theme/app_theme.dart';
import 'package:flutter_template/shared/layout/app_screen_adaptation.dart';
import 'package:flutter_template/shared/widgets/app_state_views.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/widgets/test_widget_environment.dart';

void main() {
  testWidgets('loading state has a stable indicator and one live status', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    try {
      await pumpTestWidget(
        tester,
        _testApp(AppLoadingState(message: 'Loading records')),
        surfaceSize: referencePhoneSurfaceSize,
      );

      final indicator = find.byType(CircularProgressIndicator);
      expect(indicator, findsOneWidget);
      expect(tester.getSize(indicator), const Size.square(32));
      expect(find.bySemanticsLabel('Loading records'), findsOneWidget);
      expect(find.text('Loading records'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('empty state keeps caller content and action semantics', (
    tester,
  ) async {
    var actionCount = 0;

    await pumpTestWidget(
      tester,
      _testApp(
        AppEmptyState(
          title: 'No records',
          message: 'Change the filters and try again.',
          action: FilledButton(
            onPressed: () => actionCount += 1,
            child: const Text('Reset filters'),
          ),
        ),
      ),
      surfaceSize: referencePhoneSurfaceSize,
    );

    expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
    expect(find.text('No records'), findsOneWidget);
    expect(find.text('Change the filters and try again.'), findsOneWidget);
    expect(
      tester.getSize(find.byType(FilledButton)).height,
      greaterThanOrEqualTo(48),
    );

    await tester.tap(find.text('Reset filters'));
    expect(actionCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('error state exposes and invokes its optional retry action', (
    tester,
  ) async {
    var retryCount = 0;
    final semantics = tester.ensureSemantics();

    try {
      await pumpTestWidget(
        tester,
        _testApp(
          AppErrorState(
            title: 'Could not load records',
            message: 'Check the connection before trying again.',
            retryLabel: 'Try again',
            onRetry: () => retryCount += 1,
          ),
        ),
        surfaceSize: referencePhoneSurfaceSize,
      );

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsOneWidget);
      expect(find.bySemanticsLabel('Could not load records'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      expect(retryCount, 1);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('state content scrolls on a narrow screen with large text', (
    tester,
  ) async {
    var retryCount = 0;

    await pumpTestWidget(
      tester,
      _testApp(
        AppErrorState(
          title: 'The requested information could not be displayed',
          message: List<String>.filled(
            5,
            'Review the current connection and then repeat the operation.',
          ).join(' '),
          retryLabel: 'Repeat the operation',
          onRetry: () => retryCount += 1,
        ),
        textScaler: largeTestTextScaler,
      ),
      surfaceSize: narrowPhoneSurfaceSize,
    );

    expect(find.byType(SingleChildScrollView), findsOneWidget);
    await tester.ensureVisible(find.text('Repeat the operation'));
    await tester.tap(find.text('Repeat the operation'));
    expect(retryCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('state views reject invalid custom padding', (tester) async {
    await pumpTestWidget(
      tester,
      _testApp(
        AppLoadingState(
          message: 'Loading',
          padding: const EdgeInsets.only(left: -1),
        ),
      ),
      surfaceSize: referencePhoneSurfaceSize,
    );

    expect(tester.takeException(), isA<ArgumentError>());
  });

  test(
    'state views reject blank accessible copy and incomplete retry data',
    () {
      expect(() => AppLoadingState(message: '   '), throwsArgumentError);
      expect(
        () => AppEmptyState(title: '', message: 'Details'),
        throwsArgumentError,
      );
      expect(
        () => AppErrorState(
          title: 'Failure',
          message: 'Details',
          retryLabel: 'Retry',
        ),
        throwsArgumentError,
      );
    },
  );
}

Widget _testApp(Widget child, {TextScaler textScaler = TextScaler.noScaling}) {
  return AppScreenAdaptation(
    builder:
        (adaptedContext) => MaterialApp(
          theme: AppTheme.light(adaptedContext),
          builder: createTestMediaQueryBuilder(textScaler: textScaler),
          home: Scaffold(body: child),
        ),
  );
}
