import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_template/app/theme/app_theme.dart';
import 'package:flutter_template/shared/layout/app_screen_adaptation.dart';
import 'package:flutter_template/shared/widgets/app_confirmation_dialog.dart';
import 'package:flutter_template/shared/widgets/app_message_feedback.dart';
import 'package:flutter_template/shared/widgets/app_state_views.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/widgets/test_widget_environment.dart';

void main() {
  for (final viewport in supportedPhoneViewports) {
    for (final textScaleCase in _textScaleCases) {
      testWidgets(
        'shared states and feedback fit ${viewport.name} with ${textScaleCase.name}',
        (tester) async {
          final semanticsHandle = tester.ensureSemantics();
          try {
            configureTestView(
              tester,
              viewport.size,
              padding: viewport.safeInsets,
              viewPadding: viewport.safeInsets,
            );
            var actionCount = 0;

            await tester.pumpWidget(
              _widgetHost(
                viewport: viewport,
                textScaler: textScaleCase.scaler,
                child: AppLoadingState(
                  message: 'Loading the requested template data',
                ),
              ),
            );
            await tester.pump();
            final loadingSemantics = tester.getSemantics(
              find.byType(AppLoadingState),
            );
            expect(
              loadingSemantics.getSemanticsData().label,
              'Loading the requested template data',
            );
            expect(
              loadingSemantics.hasFlag(SemanticsFlag.isLiveRegion),
              isTrue,
            );
            expect(tester.takeException(), isNull);

            const emptyActionKey = Key('matrix-empty-action');
            await tester.pumpWidget(
              _widgetHost(
                viewport: viewport,
                textScaler: textScaleCase.scaler,
                child: AppEmptyState(
                  title: 'No template records yet',
                  message:
                      'Create a record when the project is ready to continue.',
                  action: OutlinedButton.icon(
                    key: emptyActionKey,
                    onPressed: () => actionCount += 1,
                    icon: const Icon(Icons.add),
                    label: const Text('Create template record'),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            await _expectStateActionIsReachable(
              tester,
              state: find.byType(AppEmptyState),
              action: find.byKey(emptyActionKey),
              reason: '${viewport.name}/${textScaleCase.name} empty action',
            );
            final emptyScrollView = find.descendant(
              of: find.byType(AppEmptyState),
              matching: find.byType(SingleChildScrollView),
            );
            _expectChildInsideParent(
              tester,
              child: find.text('Create template record'),
              parent: find.byKey(emptyActionKey),
              reason: '${viewport.name}/${textScaleCase.name} empty label',
            );
            await _tapVisibleTarget(
              tester,
              target: find.byKey(emptyActionKey),
              visibleBounds: tester.getRect(emptyScrollView),
            );
            expect(actionCount, 1);

            const retryActionText = 'Retry loading template data';
            await tester.pumpWidget(
              _widgetHost(
                viewport: viewport,
                textScaler: textScaleCase.scaler,
                child: AppErrorState(
                  title: 'Template data could not be loaded',
                  message:
                      'The operation is safe to retry and no private details are shown.',
                  retryLabel: retryActionText,
                  onRetry: () => actionCount += 1,
                ),
              ),
            );
            await tester.pumpAndSettle();
            final retryAction = find.ancestor(
              of: find.text(retryActionText),
              matching: find.byWidgetPredicate(
                (widget) => widget is FilledButton,
              ),
            );
            await _expectStateActionIsReachable(
              tester,
              state: find.byType(AppErrorState),
              action: retryAction,
              reason: '${viewport.name}/${textScaleCase.name} retry action',
            );
            _expectChildInsideParent(
              tester,
              child: find.text(retryActionText),
              parent: retryAction,
              reason: '${viewport.name}/${textScaleCase.name} retry label',
            );
            await _tapVisibleTarget(
              tester,
              target: retryAction,
              visibleBounds: tester.getRect(
                find.descendant(
                  of: find.byType(AppErrorState),
                  matching: find.byType(SingleChildScrollView),
                ),
              ),
            );
            expect(actionCount, 2);

            const overlayHostKey = Key('matrix-overlay-host');
            await tester.pumpWidget(
              _widgetHost(
                viewport: viewport,
                textScaler: textScaleCase.scaler,
                child: const SizedBox.expand(key: overlayHostKey),
              ),
            );
            await tester.pumpAndSettle();
            final overlayContext = tester.element(find.byKey(overlayHostKey));
            final dialogResult = showAppConfirmationDialog(
              overlayContext,
              title: 'Confirm the template operation',
              message:
                  'Review this intentionally long message before choosing the explicit action.',
              cancelLabel: 'Keep the current template state',
              confirmLabel: 'Apply the requested template operation',
            );
            await tester.pumpAndSettle();

            final confirmAction = find.ancestor(
              of: find.text('Apply the requested template operation'),
              matching: find.byType(FilledButton),
            );
            final dialogScrollView = find.descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(SingleChildScrollView),
            );
            await _expectScrollableTargetIsReachable(
              tester,
              target: confirmAction,
              scrollView: dialogScrollView,
              outerBounds: _safeRect(viewport),
              reason: '${viewport.name}/${textScaleCase.name} dialog action',
            );
            _expectButtonSemantics(tester, confirmAction);
            _expectChildInsideParent(
              tester,
              child: find.text('Apply the requested template operation'),
              parent: confirmAction,
              reason: '${viewport.name}/${textScaleCase.name} dialog label',
            );
            await _tapVisibleTarget(
              tester,
              target: confirmAction,
              visibleBounds: tester.getRect(dialogScrollView),
            );
            await tester.pumpAndSettle();
            expect(await dialogResult, isTrue);

            showAppMessageFeedback(
              overlayContext,
              message:
                  'The template operation completed with additional information for review.',
              kind: AppMessageKind.warning,
              duration: const Duration(days: 1),
              actionLabel: 'Review the completed template operation',
              onAction: () => actionCount += 1,
            );
            await tester.pumpAndSettle();

            final feedbackAction = find.ancestor(
              of: find.text('Review the completed template operation'),
              matching: find.byType(TextButton),
            );
            final feedbackScrollView = find.descendant(
              of: find.byType(SnackBar),
              matching: find.byType(SingleChildScrollView),
            );
            await _expectScrollableTargetIsReachable(
              tester,
              target: feedbackAction,
              scrollView: feedbackScrollView,
              outerBounds: _safeRect(viewport),
              reason: '${viewport.name}/${textScaleCase.name} feedback action',
            );
            _expectButtonSemantics(tester, feedbackAction);
            _expectChildInsideParent(
              tester,
              child: find.text('Review the completed template operation'),
              parent: feedbackAction,
              reason: '${viewport.name}/${textScaleCase.name} feedback label',
            );
            expect(
              find.bySemanticsLabel(
                'The template operation completed with additional information for review.',
              ),
              findsOneWidget,
            );

            await _tapVisibleTarget(
              tester,
              target: feedbackAction,
              visibleBounds: tester.getRect(feedbackScrollView),
            );
            await tester.pumpAndSettle();
            expect(actionCount, 3);
            expect(find.byType(SnackBar), findsNothing);
            expect(tester.takeException(), isNull);
          } finally {
            semanticsHandle.dispose();
          }
        },
      );
    }
  }
}

const double _geometryTolerance = 0.01;

const List<({String name, TextScaler scaler})> _textScaleCases =
    <({String name, TextScaler scaler})>[
      (name: 'normal text', scaler: TextScaler.noScaling),
      (name: '200% system text', scaler: largeTestTextScaler),
    ];

Widget _widgetHost({
  required TestPhoneViewport viewport,
  required TextScaler textScaler,
  required Widget child,
}) {
  return AppScreenAdaptation(
    builder:
        (adaptedContext) => MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(adaptedContext),
          builder: createTestMediaQueryBuilder(
            textScaler: textScaler,
            padding: viewport.safeInsets,
            viewPadding: viewport.safeInsets,
          ),
          home: Scaffold(body: SafeArea(child: child)),
        ),
  );
}

Future<void> _expectStateActionIsReachable(
  WidgetTester tester, {
  required Finder state,
  required Finder action,
  required String reason,
}) async {
  final scrollView = find.descendant(
    of: state,
    matching: find.byType(SingleChildScrollView),
  );
  await _expectScrollableTargetIsReachable(
    tester,
    target: action,
    scrollView: scrollView,
    reason: reason,
  );
  _expectButtonSemantics(tester, action);
}

Future<void> _expectScrollableTargetIsReachable(
  WidgetTester tester, {
  required Finder target,
  required Finder scrollView,
  required String reason,
  Rect? outerBounds,
}) async {
  expect(scrollView, findsOneWidget, reason: reason);
  final scrollBounds = tester.getRect(scrollView);
  if (outerBounds != null) {
    _expectRectInside(
      target: scrollBounds,
      bounds: outerBounds,
      reason: '$reason scroll viewport',
    );
  }

  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  var targetRect = tester.getRect(target);
  _expectTargetWidthAndMinimumSize(
    target: targetRect,
    bounds: scrollBounds,
    reason: reason,
  );

  if (targetRect.height <= scrollBounds.height + _geometryTolerance) {
    _expectRectInside(target: targetRect, bounds: scrollBounds, reason: reason);
    return;
  }

  // 极端宽度比例叠加系统大字体时，完整按钮可能高于短横屏视口。此时不压缩系统文字，
  // 而是分别验证按钮顶部和底部都能由同一个滚动容器到达，并保留可点击的可见交集。
  expect(
    targetRect.top,
    closeTo(scrollBounds.top, _geometryTolerance),
    reason: '$reason top edge',
  );
  final scrollable = find.descendant(
    of: scrollView,
    matching: find.byType(Scrollable),
  );
  expect(scrollable, findsOneWidget, reason: reason);
  final scrollableState = tester.state<ScrollableState>(scrollable);
  scrollableState.position.jumpTo(scrollableState.position.maxScrollExtent);
  await tester.pump();

  targetRect = tester.getRect(target);
  expect(
    targetRect.bottom,
    lessThanOrEqualTo(scrollBounds.bottom + _geometryTolerance),
    reason: '$reason bottom edge; target=$targetRect, bounds=$scrollBounds',
  );
  expect(
    targetRect.bottom,
    greaterThan(scrollBounds.top),
    reason: '$reason visible bottom intersection',
  );
}

void _expectTargetWidthAndMinimumSize({
  required Rect target,
  required Rect bounds,
  required String reason,
}) {
  final geometryReason = '$reason; target=$target, bounds=$bounds';
  expect(
    target.left,
    greaterThanOrEqualTo(bounds.left - _geometryTolerance),
    reason: geometryReason,
  );
  expect(
    target.right,
    lessThanOrEqualTo(bounds.right + _geometryTolerance),
    reason: geometryReason,
  );
  expect(
    target.width,
    greaterThanOrEqualTo(48 - _geometryTolerance),
    reason: geometryReason,
  );
  expect(
    target.height,
    greaterThanOrEqualTo(48 - _geometryTolerance),
    reason: geometryReason,
  );
}

void _expectRectInside({
  required Rect target,
  required Rect bounds,
  required String reason,
}) {
  final geometryReason = '$reason; target=$target, bounds=$bounds';
  expect(
    target.left,
    greaterThanOrEqualTo(bounds.left - _geometryTolerance),
    reason: geometryReason,
  );
  expect(
    target.top,
    greaterThanOrEqualTo(bounds.top - _geometryTolerance),
    reason: geometryReason,
  );
  expect(
    target.right,
    lessThanOrEqualTo(bounds.right + _geometryTolerance),
    reason: geometryReason,
  );
  expect(
    target.bottom,
    lessThanOrEqualTo(bounds.bottom + _geometryTolerance),
    reason: geometryReason,
  );
}

void _expectChildInsideParent(
  WidgetTester tester, {
  required Finder child,
  required Finder parent,
  required String reason,
}) {
  _expectRectInside(
    target: tester.getRect(child),
    bounds: tester.getRect(parent),
    reason: reason,
  );
}

Future<void> _tapVisibleTarget(
  WidgetTester tester, {
  required Finder target,
  required Rect visibleBounds,
}) async {
  final visibleTarget = tester.getRect(target).intersect(visibleBounds);
  expect(visibleTarget.isEmpty, isFalse);
  await tester.tapAt(visibleTarget.center);
}

Rect _safeRect(TestPhoneViewport viewport) {
  return Rect.fromLTRB(
    viewport.safeInsets.left,
    viewport.safeInsets.top,
    viewport.size.width - viewport.safeInsets.right,
    viewport.size.height - viewport.safeInsets.bottom,
  );
}

void _expectButtonSemantics(WidgetTester tester, Finder finder) {
  final semantics = tester.getSemantics(finder);
  expect(semantics.hasFlag(SemanticsFlag.isButton), isTrue);
  expect(semantics.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
}
