import 'package:flutter/material.dart';
import 'package:flutter_template/shared/layout/app_safe_scrollable_scaffold.dart';
import 'package:flutter_template/shared/layout/app_screen_adaptation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppSafeScrollableScaffold', () {
    testWidgets('keeps system safe areas raw across the required viewports', (
      tester,
    ) async {
      _configureTestView(tester, _viewportCases.first.size);

      for (final viewport in _viewportCases) {
        tester.view.physicalSize = viewport.size;
        final mediaQueryData = MediaQueryData(
          size: viewport.size,
          padding: viewport.safeInsets,
          viewPadding: viewport.safeInsets,
          textScaler: TextScaler.noScaling,
        );

        await tester.pumpWidget(_pageHost(mediaQueryData: mediaQueryData));
        await tester.pumpAndSettle();

        final scale = viewport.size.width / appDesignSize.width;
        final designPadding = 16 * scale;
        final contentRect = tester.getRect(find.byKey(_contentProbeKey));
        final actionRect = tester.getRect(find.byKey(_actionProbeKey));
        final scrollRect = tester.getRect(find.byType(CustomScrollView));

        expect(
          scrollRect,
          _closeToRect(
            Rect.fromLTRB(
              viewport.safeInsets.left,
              viewport.safeInsets.top,
              viewport.size.width - viewport.safeInsets.right,
              viewport.size.height - viewport.safeInsets.bottom,
            ),
          ),
          reason: viewport.name,
        );
        expect(
          contentRect.left,
          closeTo(viewport.safeInsets.left + designPadding, _epsilon),
          reason: viewport.name,
        );
        expect(
          contentRect.top,
          closeTo(viewport.safeInsets.top + designPadding, _epsilon),
          reason: viewport.name,
        );
        expect(
          actionRect.right,
          closeTo(
            viewport.size.width - viewport.safeInsets.right - designPadding,
            _epsilon,
          ),
          reason: viewport.name,
        );
        expect(
          actionRect.bottom,
          closeTo(
            viewport.size.height - viewport.safeInsets.bottom - designPadding,
            _epsilon,
          ),
          reason: viewport.name,
        );
        expect(tester.takeException(), isNull, reason: viewport.name);
      }
    });

    testWidgets('keeps a large-text action reachable on a short screen', (
      tester,
    ) async {
      const size = Size(320, 568);
      const safeInsets = EdgeInsets.only(top: 24, bottom: 16);
      _configureTestView(tester, size);
      var actionCount = 0;

      await tester.pumpWidget(
        _pageHost(
          mediaQueryData: const MediaQueryData(
            size: size,
            padding: safeInsets,
            viewPadding: safeInsets,
            textScaler: TextScaler.linear(2),
          ),
          content: const _LongTextContent(),
          bottomAction: SizedBox(
            key: _actionProbeKey,
            height: 48,
            child: FilledButton(
              onPressed: () => actionCount += 1,
              child: Text('Continue'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
      expect(scrollable.position.maxScrollExtent, greaterThan(0));
      expect(
        MediaQuery.textScalerOf(
          tester.element(find.byKey(_largeTextProbeKey)),
        ).scale(16),
        32,
      );

      await tester.ensureVisible(find.byKey(_actionProbeKey));
      await tester.pumpAndSettle();
      final actionRect = tester.getRect(find.byKey(_actionProbeKey));
      final scrollRect = tester.getRect(find.byType(CustomScrollView));
      expect(actionRect.top, greaterThanOrEqualTo(scrollRect.top - _epsilon));
      expect(
        actionRect.bottom,
        lessThanOrEqualTo(scrollRect.bottom + _epsilon),
      );

      await tester.tap(find.byType(FilledButton));
      expect(actionCount, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('uses the raw keyboard inset and keeps actions scrollable', (
      tester,
    ) async {
      const size = Size(430, 932);
      const viewPadding = EdgeInsets.only(top: 44, bottom: 34);
      const keyboardInset = 300.0;
      _configureTestView(tester, size);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      var actionCount = 0;

      await tester.pumpWidget(
        _pageHost(
          mediaQueryData: const MediaQueryData(
            size: size,
            padding: viewPadding,
            viewPadding: viewPadding,
          ),
          scrollController: controller,
          content: const _KeyboardContent(),
          bottomAction: SizedBox(
            key: _actionProbeKey,
            height: 48,
            child: FilledButton(
              onPressed: () => actionCount += 1,
              child: Text('Submit'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byType(CustomScrollView)).bottom,
        closeTo(size.height - viewPadding.bottom, _epsilon),
      );

      await tester.tap(find.byKey(_textFieldKey));
      await tester.pump();
      await tester.pumpWidget(
        _pageHost(
          mediaQueryData: const MediaQueryData(
            size: size,
            padding: EdgeInsets.only(top: 44),
            viewPadding: viewPadding,
            viewInsets: EdgeInsets.only(bottom: keyboardInset),
          ),
          scrollController: controller,
          content: const _KeyboardContent(),
          bottomAction: SizedBox(
            key: _actionProbeKey,
            height: 48,
            child: FilledButton(
              onPressed: () => actionCount += 1,
              child: Text('Submit'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      final scrollRect = tester.getRect(find.byType(CustomScrollView));
      expect(scaffold.resizeToAvoidBottomInset, isFalse);
      expect(scrollRect.top, closeTo(viewPadding.top, _epsilon));
      expect(scrollRect.bottom, closeTo(size.height - keyboardInset, _epsilon));
      expect(
        MediaQuery.viewInsetsOf(
          tester.element(find.byKey(_textFieldKey)),
        ).bottom,
        keyboardInset,
      );

      await tester.ensureVisible(find.byKey(_actionProbeKey));
      await tester.pumpAndSettle();
      final actionRect = tester.getRect(find.byKey(_actionProbeKey));
      expect(actionRect.top, greaterThanOrEqualTo(scrollRect.top - _epsilon));
      expect(
        actionRect.bottom,
        lessThanOrEqualTo(scrollRect.bottom + _epsilon),
      );

      await tester.tap(find.byType(FilledButton));
      expect(actionCount, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('keeps ownership of an external scroll controller', (
      tester,
    ) async {
      const size = Size(375, 812);
      _configureTestView(tester, size);
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _pageHost(
          mediaQueryData: const MediaQueryData(size: size),
          scrollController: controller,
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.hasClients, isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(controller.hasClients, isFalse);
      expect(() => controller.addListener(_emptyListener), returnsNormally);
      controller.removeListener(_emptyListener);
      expect(tester.takeException(), isNull);
    });

    testWidgets('rejects invalid design content padding', (tester) async {
      const size = Size(375, 812);
      _configureTestView(tester, size);

      await tester.pumpWidget(
        _pageHost(
          mediaQueryData: const MediaQueryData(size: size),
          contentPadding: const EdgeInsets.only(left: -1),
        ),
      );

      expect(tester.takeException(), isA<ArgumentError>());
    });
  });
}

const double _epsilon = 0.0001;
const Key _contentProbeKey = Key('safe-page-content-probe');
const Key _actionProbeKey = Key('safe-page-action-probe');
const Key _largeTextProbeKey = Key('safe-page-large-text-probe');
const Key _textFieldKey = Key('safe-page-text-field');

void _emptyListener() {}

const List<_ViewportCase> _viewportCases = <_ViewportCase>[
  _ViewportCase(
    name: 'narrow portrait',
    size: Size(320, 568),
    safeInsets: EdgeInsets.only(top: 24, bottom: 16),
  ),
  _ViewportCase(
    name: 'reference portrait',
    size: Size(375, 812),
    safeInsets: EdgeInsets.only(top: 44, bottom: 34),
  ),
  _ViewportCase(
    name: 'wide portrait',
    size: Size(430, 932),
    safeInsets: EdgeInsets.fromLTRB(8, 47, 10, 34),
  ),
  _ViewportCase(
    name: 'phone landscape',
    size: Size(800, 360),
    safeInsets: EdgeInsets.fromLTRB(44, 0, 20, 21),
  ),
];

Widget _pageHost({
  required MediaQueryData mediaQueryData,
  Widget content = const SizedBox(key: _contentProbeKey, height: 40),
  Widget? bottomAction = const SizedBox(key: _actionProbeKey, height: 48),
  EdgeInsetsGeometry? contentPadding,
  ScrollController? scrollController,
}) {
  return AppScreenAdaptation(
    builder: (adaptedContext) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        builder:
            (context, child) => MediaQuery(data: mediaQueryData, child: child!),
        home: AppSafeScrollableScaffold(
          content: content,
          bottomAction: bottomAction,
          contentPadding:
              contentPadding ?? EdgeInsets.all(adaptedContext.du(16)),
          scrollController: scrollController,
        ),
      );
    },
  );
}

void _configureTestView(WidgetTester tester, Size logicalSize) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = logicalSize;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Matcher _closeToRect(Rect expected) {
  return isA<Rect>()
      .having((rect) => rect.left, 'left', closeTo(expected.left, _epsilon))
      .having((rect) => rect.top, 'top', closeTo(expected.top, _epsilon))
      .having((rect) => rect.right, 'right', closeTo(expected.right, _epsilon))
      .having(
        (rect) => rect.bottom,
        'bottom',
        closeTo(expected.bottom, _epsilon),
      );
}

final class _ViewportCase {
  const _ViewportCase({
    required this.name,
    required this.size,
    required this.safeInsets,
  });

  final String name;
  final Size size;
  final EdgeInsets safeInsets;
}

final class _LongTextContent extends StatelessWidget {
  const _LongTextContent();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Accessible layout probe',
          key: _largeTextProbeKey,
          style: const TextStyle(fontSize: 16),
        ),
        for (var index = 0; index < 8; index++)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'Long content remains readable instead of shrinking to fit.',
            ),
          ),
      ],
    );
  }
}

final class _KeyboardContent extends StatelessWidget {
  const _KeyboardContent();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TextField(key: _textFieldKey),
        SizedBox(height: 640),
        Text('End of keyboard test content'),
      ],
    );
  }
}
