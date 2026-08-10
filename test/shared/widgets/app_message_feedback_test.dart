import 'package:flutter/material.dart';
import 'package:flutter_template/app/theme/app_theme.dart';
import 'package:flutter_template/shared/widgets/app_message_feedback.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/widgets/test_widget_environment.dart';

void main() {
  testWidgets('message feedback maps every kind to a themed visual', (
    tester,
  ) async {
    await tester.pumpWidget(_feedbackHost());
    final context = tester.element(find.byKey(const Key('feedback-host')));
    final scheme = Theme.of(context).colorScheme;
    final expectations = <AppMessageKind, ({IconData icon, Color color})>{
      AppMessageKind.information: (
        icon: Icons.info_outline,
        color: scheme.tertiaryContainer,
      ),
      AppMessageKind.success: (
        icon: Icons.check_circle_outline,
        color: scheme.primaryContainer,
      ),
      AppMessageKind.warning: (
        icon: Icons.warning_amber_rounded,
        color: scheme.secondaryContainer,
      ),
      AppMessageKind.error: (
        icon: Icons.error_outline,
        color: scheme.errorContainer,
      ),
    };

    for (final entry in expectations.entries) {
      showAppMessageFeedback(
        context,
        message: 'Message for ${entry.key.name}',
        kind: entry.key,
      );
      await tester.pumpAndSettle();

      final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snackBar.backgroundColor, entry.value.color);
      expect(snackBar.showCloseIcon, isTrue);
      expect(find.byIcon(entry.value.icon), findsOneWidget);
      expect(
        find.bySemanticsLabel('Message for ${entry.key.name}'),
        findsOneWidget,
      );
    }

    expect(tester.takeException(), isNull);
  });

  testWidgets('message action runs once and replacement drops stale feedback', (
    tester,
  ) async {
    var actionCount = 0;
    await tester.pumpWidget(_feedbackHost());
    final context = tester.element(find.byKey(const Key('feedback-host')));

    showAppMessageFeedback(
      context,
      message: 'First message',
      actionLabel: 'Undo',
      onAction: () => actionCount += 1,
    );
    await tester.pumpAndSettle();
    final actionButton = tester.widget<TextButton>(
      find.ancestor(of: find.text('Undo'), matching: find.byType(TextButton)),
    );
    actionButton.onPressed!();
    actionButton.onPressed!();
    await tester.pumpAndSettle();
    expect(actionCount, 1);

    showAppMessageFeedback(context, message: 'Stale message');
    await tester.pumpAndSettle();
    showAppMessageFeedback(context, message: 'Newest message');
    await tester.pumpAndSettle();

    expect(find.text('Stale message'), findsNothing);
    expect(find.text('Newest message'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('message action preserves feedback shown by its callback', (
    tester,
  ) async {
    await tester.pumpWidget(_feedbackHost());
    final context = tester.element(find.byKey(const Key('feedback-host')));

    showAppMessageFeedback(
      context,
      message: 'Initial message',
      actionLabel: 'Continue',
      onAction: () {
        showAppMessageFeedback(
          context,
          message: 'Follow-up message',
          duration: const Duration(days: 1),
        );
      },
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Initial message'), findsNothing);
    expect(find.text('Follow-up message'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('message feedback fits a narrow viewport with large text', (
    tester,
  ) async {
    await pumpTestWidget(
      tester,
      _feedbackHost(textScaler: largeTestTextScaler),
      surfaceSize: narrowPhoneSurfaceSize,
    );
    final context = tester.element(find.byKey(const Key('feedback-host')));

    showAppMessageFeedback(
      context,
      message: 'The requested operation completed with additional information.',
      kind: AppMessageKind.warning,
      actionLabel: 'Review details',
      onAction: () {},
    );
    await tester.pumpAndSettle();

    expect(find.text('Review details'), findsOneWidget);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'message feedback validates content before touching messenger state',
    (tester) async {
      await tester.pumpWidget(_feedbackHost());
      final context = tester.element(find.byKey(const Key('feedback-host')));

      expect(
        () => showAppMessageFeedback(context, message: ' '),
        throwsArgumentError,
      );
      expect(
        () => showAppMessageFeedback(
          context,
          message: 'Message',
          actionLabel: 'Undo',
        ),
        throwsArgumentError,
      );
      expect(
        () => showAppMessageFeedback(
          context,
          message: 'Message',
          duration: Duration.zero,
        ),
        throwsArgumentError,
      );
      expect(find.byType(SnackBar), findsNothing);
    },
  );
}

Widget _feedbackHost({TextScaler textScaler = TextScaler.noScaling}) {
  return MaterialApp(
    theme: AppTheme.light(),
    builder: createTestMediaQueryBuilder(textScaler: textScaler),
    home: const Scaffold(body: SizedBox.expand(key: Key('feedback-host'))),
  );
}
