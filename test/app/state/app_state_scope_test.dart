import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_template/app/state/app_state_scope.dart';
import 'package:flutter_template/app/state/app_theme_mode_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/state/create_test_provider_container.dart';

void main() {
  testWidgets('root state scope applies overrides and owns container disposal', (
    tester,
  ) async {
    var disposeCount = 0;
    final dependencyProvider = Provider<String>((_) => 'production');
    final lifecycleProvider = Provider<int>((ref) {
      ref.onDispose(() => disposeCount++);
      return 1;
    });
    BuildContext? consumerContext;

    await tester.pumpWidget(
      AppStateScope(
        overrides: <Override>[
          dependencyProvider.overrideWithValue('replacement'),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            consumerContext = context;
            return Text(
              '${ref.watch(dependencyProvider)}:${ref.watch(lifecycleProvider)}',
              textDirection: TextDirection.ltr,
            );
          },
        ),
      ),
    );

    expect(find.text('replacement:1'), findsOneWidget);
    final container = ProviderScope.containerOf(
      consumerContext!,
      listen: false,
    );

    await tester.pumpWidget(const SizedBox.shrink());

    expect(disposeCount, 1);
    expect(() => container.read(dependencyProvider), throwsStateError);
  });

  testWidgets('root state scope applies replacement overrides on rebuild', (
    tester,
  ) async {
    final dependencyProvider = Provider<String>((_) => 'production');

    Widget applicationWith(String value) {
      return AppStateScope(
        overrides: <Override>[dependencyProvider.overrideWithValue(value)],
        child: Consumer(
          builder:
              (_, ref, _) => Text(
                ref.watch(dependencyProvider),
                textDirection: TextDirection.ltr,
              ),
        ),
      );
    }

    await tester.pumpWidget(applicationWith('first'));
    expect(find.text('first'), findsOneWidget);

    await tester.pumpWidget(applicationWith('replacement'));
    await tester.pump();

    expect(find.text('replacement'), findsOneWidget);
    expect(find.text('first'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('theme mode controller has a stable default and ignores duplicates', () {
    final container = createTestProviderContainer();
    final states = <ThemeMode>[];
    final subscription = container.listen<ThemeMode>(
      appThemeModeProvider,
      (_, next) => states.add(next),
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    final controller = container.read(appThemeModeProvider.notifier);
    controller.setThemeMode(ThemeMode.dark);
    controller.setThemeMode(ThemeMode.dark);
    controller.setThemeMode(ThemeMode.light);

    expect(container.read(appThemeModeProvider), ThemeMode.light);
    expect(states, <ThemeMode>[
      ThemeMode.system,
      ThemeMode.dark,
      ThemeMode.light,
    ]);
  });
}
