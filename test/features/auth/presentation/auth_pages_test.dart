import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_template/app/config/app_config.dart';
import 'package:flutter_template/app/localization/app_locale.dart';
import 'package:flutter_template/app/state/app_locale_controller.dart';
import 'package:flutter_template/app/state/app_state_scope.dart';
import 'package:flutter_template/app/template_app.dart';
import 'package:flutter_template/app/theme/app_theme.dart';
import 'package:flutter_template/features/auth/domain/auth_failure.dart';
import 'package:flutter_template/features/auth/presentation/auth_session_controller.dart';
import 'package:flutter_template/features/auth/presentation/auth_sign_in_page.dart';
import 'package:flutter_template/features/example/data/bundled_example_repository.dart';
import 'package:flutter_template/features/example/presentation/example_detail_controller.dart';
import 'package:flutter_template/shared/layout/app_screen_adaptation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/features/auth/auth_credentials_fixture.dart';
import '../../../support/features/auth/controlled_auth_credential_persistence.dart';
import '../../../support/features/auth/controlled_auth_gateway.dart';
import '../../../support/features/auth/mutable_auth_clock.dart';
import '../../../support/widgets/test_widget_environment.dart';

void main() {
  final now = DateTime.utc(2029, DateTime.january, 1, 12);

  testWidgets('unknown gateway failure is safe and clears submitted password', (
    tester,
  ) async {
    final persistence = ControlledAuthCredentialPersistence();
    await pumpTestWidget(
      tester,
      _applicationUnderTest(
        gateway: ControlledAuthGateway(),
        persistence: persistence,
        clock: MutableAuthClock(now),
      ),
      surfaceSize: referencePhoneSurfaceSize,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open-protected-area')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('auth-sign-in-route')), findsOneWidget);

    await tester.tap(find.byKey(const Key('auth-submit')));
    await tester.pump();
    expect(find.text('Enter your account.'), findsOneWidget);
    expect(find.text('Enter your password.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('auth-identifier-field')),
      'fixture-account',
    );
    await tester.enterText(
      find.byKey(const Key('auth-password-field')),
      'fixture-password',
    );
    await tester.tap(find.byKey(const Key('auth-password-visibility')));
    await tester.pump();
    expect(
      tester.widget<EditableText>(find.byType(EditableText).last).obscureText,
      isFalse,
    );

    // production 默认 gateway 与测试受控 gateway 的错误语义相同；本用例主动让 fake 返回
    // 明确不可用，避免依赖真实网络或账号。
    final gateway = _providerContainer(tester).read(authGatewayProvider);
    expect(gateway, isA<ControlledAuthGateway>());
    final controlledGateway = gateway as ControlledAuthGateway;
    await tester.tap(find.byKey(const Key('auth-submit')));
    await tester.pump();
    controlledGateway.signInOperations.single.fail(
      const _UnavailableAuthException(),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sign-in could not be completed.'), findsOneWidget);
    expect(find.text('fixture-password'), findsNothing);
    expect(
      tester.widget<EditableText>(find.byType(EditableText).last).obscureText,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'successful sign-in returns to protected page and sign-out redirects',
    (tester) async {
      final gateway = ControlledAuthGateway();
      final persistence = ControlledAuthCredentialPersistence();
      await pumpTestWidget(
        tester,
        _applicationUnderTest(
          gateway: gateway,
          persistence: persistence,
          clock: MutableAuthClock(now),
        ),
        surfaceSize: referencePhoneSurfaceSize,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('open-protected-area')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('auth-identifier-field')),
        'fixture-account',
      );
      await tester.enterText(
        find.byKey(const Key('auth-password-field')),
        'fixture-password',
      );
      await tester.tap(find.byKey(const Key('auth-submit')));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(gateway.signInOperations, hasLength(1));

      gateway.signInOperations.single.succeed(
        createAuthCredentialsFixture(
          generation: 'widget',
          accessExpiresAt: now.add(const Duration(hours: 1)),
          refreshExpiresAt: now.add(const Duration(days: 1)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('auth-account-route')), findsOneWidget);
      expect(find.text('Your session is active.'), findsOneWidget);
      expect(find.textContaining('fixture-account'), findsNothing);
      expect(find.textContaining('fixture-password'), findsNothing);

      await tester.tap(find.byKey(const Key('auth-sign-out')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('auth-sign-in-route')), findsOneWidget);
      expect(persistence.storedCredentials, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('protected navigation waits for startup restoration', (
    tester,
  ) async {
    final loadGate = Completer<void>();
    final persistence =
        ControlledAuthCredentialPersistence()..loadGate = loadGate;
    await pumpTestWidget(
      tester,
      _applicationUnderTest(
        gateway: ControlledAuthGateway(),
        persistence: persistence,
        clock: MutableAuthClock(now),
      ),
      surfaceSize: referencePhoneSurfaceSize,
    );
    await tester.pump();

    expect(find.byKey(const Key('template-home-route')), findsOneWidget);
    await tester.tap(find.byKey(const Key('open-protected-area')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('auth-session-loading-route')), findsOneWidget);
    expect(find.textContaining('/account'), findsNothing);

    loadGate.complete();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('auth-sign-in-route')), findsOneWidget);
    expect(find.byKey(const Key('auth-session-loading-route')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('valid startup session opens the protected page after loading', (
    tester,
  ) async {
    final loadGate = Completer<void>();
    final persistence = ControlledAuthCredentialPersistence(
      storedCredentials: createAuthCredentialsFixture(
        generation: 'startup-widget',
        accessExpiresAt: now.add(const Duration(hours: 1)),
        refreshExpiresAt: now.add(const Duration(days: 1)),
      ),
    )..loadGate = loadGate;
    await pumpTestWidget(
      tester,
      _applicationUnderTest(
        gateway: ControlledAuthGateway(),
        persistence: persistence,
        clock: MutableAuthClock(now),
      ),
      surfaceSize: referencePhoneSurfaceSize,
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('open-protected-area')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('auth-session-loading-route')), findsOneWidget);

    loadGate.complete();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('auth-account-route')), findsOneWidget);
    expect(find.text('Your session is active.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'sign-in controls remain reachable on a narrow large-text phone',
    (tester) async {
      await pumpTestWidget(
        tester,
        _signInPageUnderTest(
          gateway: ControlledAuthGateway(),
          persistence: ControlledAuthCredentialPersistence(),
          clock: MutableAuthClock(now),
        ),
        surfaceSize: narrowPhoneSurfaceSize,
      );
      await tester.pumpAndSettle();

      final submit = find.byKey(const Key('auth-submit'));
      await tester.ensureVisible(submit);
      await tester.pump();

      expect(submit, findsOneWidget);
      expect(tester.getSize(submit).height, greaterThanOrEqualTo(48));
      expect(find.byKey(const Key('auth-return-home')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

Widget _signInPageUnderTest({
  required ControlledAuthGateway gateway,
  required ControlledAuthCredentialPersistence persistence,
  required MutableAuthClock clock,
}) {
  return AppStateScope(
    overrides: <Override>[
      authGatewayProvider.overrideWithValue(gateway),
      authCredentialPersistenceProvider.overrideWithValue(persistence),
      authClockProvider.overrideWithValue(clock),
    ],
    child: AppScreenAdaptation(
      builder:
          (adaptedContext) => MaterialApp(
            theme: AppTheme.light(adaptedContext),
            builder: createTestMediaQueryBuilder(
              textScaler: largeTestTextScaler,
            ),
            home: AuthSignInPage(
              copy: AuthSignInCopy(
                pageTitle: 'Sign in',
                identifierLabel: 'Account',
                passwordLabel: 'Password',
                identifierRequired: 'Enter your account.',
                passwordRequired: 'Enter your password.',
                showPasswordTooltip: 'Show password',
                hidePasswordTooltip: 'Hide password',
                submitLabel: 'Sign in',
                returnHomeLabel: 'Return home',
                failureMessage: _safeFailureMessage,
              ),
              onReturnHome: _noOp,
            ),
          ),
    ),
  );
}

String _safeFailureMessage(AuthFailure failure) => 'Sign-in failed.';

void _noOp() {}

Widget _applicationUnderTest({
  required ControlledAuthGateway gateway,
  required ControlledAuthCredentialPersistence persistence,
  required MutableAuthClock clock,
}) {
  return AppStateScope(
    overrides: <Override>[
      exampleRepositoryProvider.overrideWithValue(BundledExampleRepository()),
      appInitialLocalePreferenceProvider.overrideWithValue(
        AppLocalePreference.english,
      ),
      authGatewayProvider.overrideWithValue(gateway),
      authCredentialPersistenceProvider.overrideWithValue(persistence),
      authClockProvider.overrideWithValue(clock),
    ],
    child: TemplateApp(config: AppConfig.fromValues(environment: 'dev')),
  );
}

ProviderContainer _providerContainer(WidgetTester tester) {
  final context = tester.element(find.byType(MaterialApp));
  return ProviderScope.containerOf(context, listen: false);
}

/// 只用于验证未知 gateway 异常会被折叠且不进入 UI。
final class _UnavailableAuthException implements Exception {
  const _UnavailableAuthException();
}
