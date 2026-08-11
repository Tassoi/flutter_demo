import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_template/app/config/app_config.dart';
import 'package:flutter_template/app/localization/app_locale.dart';
import 'package:flutter_template/app/localization/app_locale_persistence.dart';
import 'package:flutter_template/app/state/app_locale_controller.dart';
import 'package:flutter_template/app/state/app_state_scope.dart';
import 'package:flutter_template/app/template_app.dart';
import 'package:flutter_template/features/auth/presentation/auth_session_controller.dart';
import 'package:flutter_template/features/example/data/bundled_example_repository.dart';
import 'package:flutter_template/features/example/presentation/example_detail_controller.dart';
import 'package:flutter_template/shared/assets/generated/template_icons.g.dart';
import 'package:flutter_template/shared/layout/app_screen_adaptation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/features/auth/auth_credentials_fixture.dart';
import '../support/features/auth/controlled_auth_credential_persistence.dart';
import '../support/features/auth/controlled_auth_gateway.dart';
import '../support/features/auth/mutable_auth_clock.dart';
import '../support/storage/in_memory_preference_store.dart';
import '../support/widgets/test_widget_environment.dart';

void main() {
  testWidgets(
    'phase two runtime capabilities cooperate in the complete application',
    (tester) async {
      final viewport = supportedPhoneViewports[3];
      final now = DateTime.utc(2029, DateTime.january, 1, 12);
      final gateway = ControlledAuthGateway();
      final authPersistence = ControlledAuthCredentialPersistence();
      final localePersistence = PreferenceStoreAppLocalePersistence(
        InMemoryPreferenceStore(),
      );

      await pumpTestWidget(
        tester,
        _applicationUnderTest(
          gateway: gateway,
          authPersistence: authPersistence,
          localePersistence: localePersistence,
          clock: MutableAuthClock(now),
        ),
        surfaceSize: viewport.size,
        padding: viewport.safeInsets,
        viewPadding: viewport.safeInsets,
      );
      await tester.pumpAndSettle();

      expect(find.byType(AppScreenAdaptation), findsOneWidget);
      expect(find.byKey(const Key('template-home-route')), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Icon && widget.icon == TemplateIcons.language,
        ),
        findsOneWidget,
      );
      expect(TemplateIcons.language.fontFamily, TemplateIcons.fontFamily);

      await tester.tap(find.byKey(const Key('language-menu')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is CheckedPopupMenuItem<AppLocalePreference> &&
              widget.value == AppLocalePreference.chinese,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('打开受保护页面'), findsOneWidget);
      expect(await localePersistence.load(), AppLocalePreference.chinese);

      await tester.tap(find.byKey(const Key('open-protected-area')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('auth-sign-in-route')), findsOneWidget);
      expect(find.text('登录'), findsWidgets);

      await tester.enterText(
        find.byKey(const Key('auth-identifier-field')),
        'fixture-integration-account',
      );
      await tester.enterText(
        find.byKey(const Key('auth-password-field')),
        'fixture-integration-password',
      );
      await tester.tap(find.byKey(const Key('auth-submit')));
      await tester.pump();
      expect(gateway.signInOperations, hasLength(1));

      gateway.signInOperations.single.succeed(
        createAuthCredentialsFixture(
          generation: 'phase-two-integration',
          accessExpiresAt: now.add(const Duration(hours: 1)),
          refreshExpiresAt: now.add(const Duration(days: 1)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('auth-account-route')), findsOneWidget);
      expect(find.text('受保护页面'), findsOneWidget);
      expect(find.textContaining('fixture-integration'), findsNothing);
      expect(authPersistence.storedCredentials, isNotNull);

      await tester.tap(find.byKey(const Key('auth-sign-out')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('auth-sign-in-route')), findsOneWidget);
      expect(authPersistence.storedCredentials, isNull);

      await tester.tap(find.byKey(const Key('auth-return-home')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('template-home-route')), findsOneWidget);
      expect(find.text('打开示例详情'), findsOneWidget);

      await tester.tap(find.byKey(const Key('open-example-detail')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('template-detail-route')), findsOneWidget);
      expect(find.text('示例详情'), findsOneWidget);
      expect(find.text('条目编号：1'), findsOneWidget);
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).locale,
        const Locale('zh'),
      );
      expect(tester.takeException(), isNull);
    },
  );
}

Widget _applicationUnderTest({
  required ControlledAuthGateway gateway,
  required ControlledAuthCredentialPersistence authPersistence,
  required AppLocalePreferencePersistence localePersistence,
  required MutableAuthClock clock,
}) {
  return AppStateScope(
    overrides: <Override>[
      exampleRepositoryProvider.overrideWithValue(
        const BundledExampleRepository(),
      ),
      appInitialLocalePreferenceProvider.overrideWithValue(
        AppLocalePreference.english,
      ),
      appLocalePreferencePersistenceProvider.overrideWithValue(
        localePersistence,
      ),
      authGatewayProvider.overrideWithValue(gateway),
      authCredentialPersistenceProvider.overrideWithValue(authPersistence),
      authClockProvider.overrideWithValue(clock),
    ],
    child: TemplateApp(config: AppConfig.fromValues(environment: 'dev')),
  );
}
