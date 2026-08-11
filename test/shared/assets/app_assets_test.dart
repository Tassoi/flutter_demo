import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_template/app/theme/app_theme.dart';
import 'package:flutter_template/shared/assets/app_assets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppSvgAsset', () {
    testWidgets('loads a bundled SVG through the typed catalog', (
      tester,
    ) async {
      const assetKey = Key('typed-svg-asset');
      const semanticsLabel = 'Template layers';
      final semantics = tester.ensureSemantics();

      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.fallbackLight(),
            home: Center(
              child: AppAssets.templateLayers.image(
                key: assetKey,
                width: 64,
                height: 64,
                color: AppTheme.fallbackLight().colorScheme.tertiary,
                semanticsLabel: semanticsLabel,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final picture = tester.widget<SvgPicture>(find.byKey(assetKey));
        expect(picture.width, 64);
        expect(picture.height, 64);
        expect(picture.semanticsLabel, semanticsLabel);
        expect(picture.excludeFromSemantics, isFalse);
        expect(find.bySemanticsLabel(semanticsLabel), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });

    test('treats a missing semantic label as an explicit decorative asset', () {
      final picture =
          AppAssets.templateLayers.image(width: 24, height: 24) as SvgPicture;

      expect(picture.semanticsLabel, isNull);
      expect(picture.excludeFromSemantics, isTrue);
    });

    test('rejects unstable dimensions and blank semantic labels', () {
      expect(
        () => AppAssets.templateLayers.image(width: 0, height: 24),
        throwsArgumentError,
      );
      expect(
        () =>
            AppAssets.templateLayers.image(width: 24, height: double.infinity),
        throwsArgumentError,
      );
      expect(
        () => AppAssets.templateLayers.image(
          width: 24,
          height: 24,
          semanticsLabel: '   ',
        ),
        throwsArgumentError,
      );
    });
  });
}
