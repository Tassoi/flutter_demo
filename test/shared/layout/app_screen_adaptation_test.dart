import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_template/shared/layout/app_screen_adaptation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppScreenAdaptation', () {
    testWidgets('uses one width ratio at reference, narrow, and wide sizes', (
      tester,
    ) async {
      _configureTestView(tester, appDesignSize);
      const host = AppScreenAdaptation(builder: _buildDesignUnitProbe);

      await tester.pumpWidget(host);
      await tester.pump();
      _expectProbeScale(tester, 1);

      tester.view.physicalSize = const Size(320, 568);
      await tester.pump();
      _expectProbeScale(tester, 320 / appDesignSize.width);

      tester.view.physicalSize = const Size(430, 932);
      await tester.pump();
      _expectProbeScale(tester, 430 / appDesignSize.width);
      expect(tester.takeException(), isNull);
    });

    testWidgets('keeps Flutter system text scaling after dsp conversion', (
      tester,
    ) async {
      _configureTestView(tester, appDesignSize);

      await tester.pumpWidget(
        AppScreenAdaptation(
          builder:
              (_) => const MediaQuery(
                data: MediaQueryData(
                  size: appDesignSize,
                  textScaler: TextScaler.linear(2),
                ),
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: _TextScaleProbe(),
                ),
              ),
        ),
      );
      await tester.pump();

      final text = tester.widget<Text>(find.byKey(_textProbeKey));
      final paragraph = tester.renderObject<RenderParagraph>(
        find.byKey(_textProbeKey),
      );
      final context = tester.element(find.byKey(_textProbeKey));

      expect(text.style?.fontSize, 16);
      expect(MediaQuery.textScalerOf(context).scale(16), 32);
      expect(paragraph.textScaler.scale(16), 32);
      expect(tester.takeException(), isNull);
    });

    testWidgets('reports a missing root adaptation context', (tester) async {
      late BuildContext uninitializedContext;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (context) {
              uninitializedContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(() => uninitializedContext.du(1), throwsStateError);
      expect(() => uninitializedContext.dsp(1), throwsStateError);
      expect(tester.takeException(), isNull);
    });

    testWidgets('rejects a non-positive view width during initialization', (
      tester,
    ) async {
      _configureTestView(tester, const Size(0, 812));

      await tester.pumpWidget(
        const AppScreenAdaptation(builder: _buildDesignUnitProbe),
      );

      expect(tester.takeException(), isA<StateError>());
    });

    testWidgets('rejects negative and non-finite design values before use', (
      tester,
    ) async {
      _configureTestView(tester, appDesignSize);
      late BuildContext adaptedContext;

      await tester.pumpWidget(
        AppScreenAdaptation(
          builder: (context) {
            adaptedContext = context;
            return const SizedBox.shrink();
          },
        ),
      );
      await tester.pump();

      expect(adaptedContext.du(0), 0);
      expect(adaptedContext.dsp(0), 0);
      expect(() => adaptedContext.du(-1), throwsArgumentError);
      expect(() => adaptedContext.du(double.nan), throwsArgumentError);
      expect(() => adaptedContext.du(double.infinity), throwsArgumentError);
      expect(() => adaptedContext.dsp(-1), throwsArgumentError);
      expect(
        () => adaptedContext.dsp(double.negativeInfinity),
        throwsArgumentError,
      );
      expect(tester.takeException(), isNull);
    });
  });
}

const Key _geometryProbeKey = Key('design-unit-geometry-probe');
const Key _textProbeKey = Key('design-unit-text-probe');

void _configureTestView(WidgetTester tester, Size logicalSize) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = logicalSize;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _buildDesignUnitProbe(BuildContext context) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        key: _geometryProbeKey,
        width: context.du(100),
        height: context.du(40),
        child: Text(
          'probe',
          key: _textProbeKey,
          style: TextStyle(fontSize: context.dsp(16)),
        ),
      ),
    ),
  );
}

void _expectProbeScale(WidgetTester tester, double expectedScale) {
  final size = tester.getSize(find.byKey(_geometryProbeKey));
  final text = tester.widget<Text>(find.byKey(_textProbeKey));

  expect(size.width, closeTo(100 * expectedScale, 0.000001));
  expect(size.height, closeTo(40 * expectedScale, 0.000001));
  expect(text.style?.fontSize, closeTo(16 * expectedScale, 0.000001));
}

final class _TextScaleProbe extends StatelessWidget {
  const _TextScaleProbe();

  @override
  Widget build(BuildContext context) {
    return Text(
      'system scale probe',
      key: _textProbeKey,
      style: TextStyle(fontSize: context.dsp(16)),
    );
  }
}
