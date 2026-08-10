import 'package:flutter/material.dart';
import 'package:flutter_template/app/theme/app_theme.dart';
import 'package:flutter_template/shared/widgets/app_confirmation_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/widgets/test_widget_environment.dart';

void main() {
  testWidgets(
    'confirmation dialog returns explicit cancel and confirm results',
    (tester) async {
      bool? result;

      await tester.pumpWidget(
        _dialogHost(
          onPressed: (context) async {
            result = await showAppConfirmationDialog(
              context,
              title: 'Remove item?',
              message: 'This change cannot be undone.',
              cancelLabel: 'Keep item',
              confirmLabel: 'Remove item',
              isDestructive: true,
            );
          },
        ),
      );

      await tester.tap(find.text('Open dialog'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('This change cannot be undone.'), findsOneWidget);
      expect(
        tester
            .getSize(
              find.ancestor(
                of: find.text('Keep item'),
                matching: find.byType(TextButton),
              ),
            )
            .height,
        greaterThanOrEqualTo(48),
      );
      expect(
        tester
            .getSize(
              find.ancestor(
                of: find.text('Remove item'),
                matching: find.byWidgetPredicate(
                  (widget) => widget is FilledButton,
                ),
              ),
            )
            .height,
        greaterThanOrEqualTo(48),
      );

      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(result, isNull);

      await tester.tap(find.text('Keep item'));
      await tester.pumpAndSettle();
      expect(result, isFalse);

      result = null;
      await tester.tap(find.text('Open dialog'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(result, isFalse);

      result = null;
      await tester.tap(find.text('Open dialog'));
      await tester.pumpAndSettle();
      final confirmButtonFinder = find.ancestor(
        of: find.text('Remove item'),
        matching: find.byWidgetPredicate((widget) => widget is FilledButton),
      );
      final confirmButton = tester.widget<FilledButton>(confirmButtonFinder);
      final buttonContext = tester.element(confirmButtonFinder);
      expect(
        confirmButton.style?.backgroundColor?.resolve(<WidgetState>{}),
        Theme.of(buttonContext).colorScheme.error,
      );

      await tester.tap(find.text('Remove item'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('confirmation dialog accepts only the first explicit decision', (
    tester,
  ) async {
    bool? result;
    await tester.pumpWidget(
      _dialogHost(
        onPressed: (context) async {
          result = await showAppConfirmationDialog(
            context,
            title: 'Apply change?',
            message: 'Choose one result.',
            cancelLabel: 'Cancel',
            confirmLabel: 'Apply',
          );
        },
      ),
    );

    await tester.tap(find.text('Open dialog'));
    await tester.pumpAndSettle();
    final cancelButton = tester.widget<TextButton>(
      find.ancestor(of: find.text('Cancel'), matching: find.byType(TextButton)),
    );
    final confirmButton = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Apply'),
        matching: find.byWidgetPredicate((widget) => widget is FilledButton),
      ),
    );

    cancelButton.onPressed!();
    confirmButton.onPressed!();
    await tester.pumpAndSettle();

    expect(result, isFalse);
    expect(find.byKey(const Key('dialog-host')), findsOneWidget);
    expect(find.text('Open dialog'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('confirmation dialog ignores actions after a system pop', (
    tester,
  ) async {
    bool? result;
    await tester.pumpWidget(
      _dialogHost(
        onPressed: (context) async {
          result = await showAppConfirmationDialog(
            context,
            title: 'Apply change?',
            message: 'Choose one result.',
            cancelLabel: 'Cancel',
            confirmLabel: 'Apply',
          );
        },
      ),
    );

    await tester.tap(find.text('Open dialog'));
    await tester.pumpAndSettle();
    final confirmButton = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Apply'),
        matching: find.byWidgetPredicate((widget) => widget is FilledButton),
      ),
    );

    await tester.binding.handlePopRoute();
    confirmButton.onPressed!();
    await tester.pumpAndSettle();

    expect(result, isFalse);
    expect(find.byKey(const Key('dialog-host')), findsOneWidget);
    expect(find.text('Open dialog'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('confirmation dialog fits narrow large-text content', (
    tester,
  ) async {
    bool? result;

    await pumpTestWidget(
      tester,
      _dialogHost(
        textScaler: largeTestTextScaler,
        onPressed: (context) async {
          result = await showAppConfirmationDialog(
            context,
            title: 'Confirm the requested operation',
            message: List<String>.filled(
              4,
              'Review all details before continuing with this operation.',
            ).join(' '),
            cancelLabel: 'Return without changing anything',
            confirmLabel: 'Continue with this operation',
          );
        },
      ),
      surfaceSize: narrowPhoneSurfaceSize,
    );

    await tester.tap(find.text('Open dialog'));
    await tester.pumpAndSettle();

    final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
    expect(dialog.scrollable, isTrue);
    expect(find.byType(OverflowBar), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('Continue with this operation'));
    await tester.tap(find.text('Continue with this operation'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('confirmation dialog rejects blank labels before navigation', (
    tester,
  ) async {
    await tester.pumpWidget(_dialogHost(onPressed: (_) {}));
    final context = tester.element(find.byKey(const Key('dialog-host')));

    await expectLater(
      showAppConfirmationDialog(
        context,
        title: ' ',
        message: 'Details',
        cancelLabel: 'Cancel',
        confirmLabel: 'Confirm',
      ),
      throwsArgumentError,
    );
    expect(find.byType(AlertDialog), findsNothing);
  });
}

Widget _dialogHost({
  required DialogLauncher onPressed,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  return MaterialApp(
    theme: AppTheme.light(),
    builder: createTestMediaQueryBuilder(textScaler: textScaler),
    home: Builder(
      key: const Key('dialog-host'),
      builder:
          (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => onPressed(context),
                child: const Text('Open dialog'),
              ),
            ),
          ),
    ),
  );
}

typedef DialogLauncher = void Function(BuildContext context);
