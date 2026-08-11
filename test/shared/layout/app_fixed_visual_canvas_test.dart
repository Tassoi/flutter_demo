import 'package:flutter/widgets.dart';
import 'package:flutter_template/shared/layout/app_fixed_visual_canvas.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppFixedVisualCanvas', () {
    testWidgets('makes contain letterboxing and cover cropping explicit', (
      tester,
    ) async {
      await tester.pumpWidget(_canvasHost(fit: AppFixedCanvasFit.contain));

      var canvasRect = tester.getRect(find.byKey(_canvasHostKey));
      var visualRect = tester.getRect(find.byKey(_visualProbeKey));
      var fittedBox = tester.widget<FittedBox>(find.byType(FittedBox));
      expect(
        visualRect,
        Rect.fromLTWH(canvasRect.left + 50, canvasRect.top, 100, 200),
      );
      expect(fittedBox.fit, BoxFit.contain);
      expect(fittedBox.clipBehavior, Clip.none);

      await tester.pumpWidget(_canvasHost(fit: AppFixedCanvasFit.cover));

      canvasRect = tester.getRect(find.byKey(_canvasHostKey));
      visualRect = tester.getRect(find.byKey(_visualProbeKey));
      fittedBox = tester.widget<FittedBox>(find.byType(FittedBox));
      expect(
        visualRect,
        Rect.fromLTWH(canvasRect.left, canvasRect.top - 100, 200, 400),
      );
      expect(fittedBox.fit, BoxFit.cover);
      expect(fittedBox.clipBehavior, Clip.hardEdge);
      expect(tester.takeException(), isNull);
    });

    testWidgets('rejects invalid design sizes', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 200,
            height: 200,
            child: AppFixedVisualCanvas(
              designSize: Size.zero,
              child: SizedBox.expand(),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isA<ArgumentError>());
    });

    testWidgets('rejects an unbounded target before laying out the canvas', (
      tester,
    ) async {
      late BuildContext hostContext;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (context) {
              hostContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      const canvas = AppFixedVisualCanvas(
        designSize: Size(100, 200),
        child: SizedBox.expand(),
      );
      final layoutBuilder = canvas.build(hostContext) as LayoutBuilder;

      expect(
        () => layoutBuilder.builder(
          hostContext,
          const BoxConstraints(maxWidth: double.infinity, maxHeight: 200),
        ),
        throwsStateError,
      );
      expect(tester.takeException(), isNull);
    });
  });
}

const Key _canvasHostKey = Key('fixed-canvas-host');
const Key _visualProbeKey = Key('fixed-canvas-visual-probe');

Widget _canvasHost({required AppFixedCanvasFit fit}) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: Center(
      child: SizedBox(
        key: _canvasHostKey,
        width: 200,
        height: 200,
        child: AppFixedVisualCanvas(
          designSize: const Size(100, 200),
          fit: fit,
          child: const ColoredBox(
            key: _visualProbeKey,
            color: Color(0xFF000000),
          ),
        ),
      ),
    ),
  );
}
