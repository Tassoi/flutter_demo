import 'package:flutter/material.dart';
import 'package:flutter_template/app/bootstrap/startup_failure_app.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/widgets/test_widget_environment.dart';

void main() {
  testWidgets('renders a safe accessible status on a narrow viewport', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    try {
      await pumpTestWidget(
        tester,
        const StartupFailureApp(),
        surfaceSize: narrowPhoneSurfaceSize,
      );

      final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(materialApp.themeMode, ThemeMode.system);
      expect(materialApp.theme?.useMaterial3, isTrue);
      expect(materialApp.darkTheme?.useMaterial3, isTrue);
      expect(find.text('The application could not start.'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Application startup failed'),
        findsOneWidget,
      );
      expect(find.textContaining('FormatException'), findsNothing);
      expect(find.textContaining('private-token-placeholder'), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('follows a supported Chinese system locale', (tester) async {
    tester.platformDispatcher.localesTestValue = const <Locale>[Locale('zh')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    await pumpTestWidget(
      tester,
      const StartupFailureApp(),
      surfaceSize: narrowPhoneSurfaceSize,
    );

    expect(find.text('应用无法启动。'), findsOneWidget);
    expect(find.bySemanticsLabel('应用启动失败'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
