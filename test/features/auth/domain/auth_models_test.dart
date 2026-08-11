import 'package:flutter_template/core/network/network_cancellation_token.dart';
import 'package:flutter_template/features/auth/data/unconfigured_auth_gateway.dart';
import 'package:flutter_template/features/auth/domain/auth_credentials.dart';
import 'package:flutter_template/features/auth/domain/auth_failure.dart';
import 'package:flutter_template/features/auth/domain/auth_gateway.dart';
import 'package:flutter_template/features/auth/domain/auth_session_state.dart';
import 'package:flutter_template/features/auth/routing/auth_route_contract.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuthCredentials', () {
    test('normalizes expiry values and applies exact validity boundaries', () {
      final credentials = AuthCredentials(
        accessCredential: 'fixture-access',
        refreshCredential: 'fixture-refresh',
        accessExpiresAt: DateTime(2030, 1, 1, 8),
        refreshExpiresAt: DateTime(2030, 1, 2, 8),
      );

      expect(credentials.accessExpiresAt.isUtc, isTrue);
      expect(credentials.refreshExpiresAt.isUtc, isTrue);
      expect(
        credentials.isAccessUsableAt(
          credentials.accessExpiresAt.subtract(const Duration(microseconds: 1)),
        ),
        isTrue,
      );
      expect(
        credentials.isAccessUsableAt(credentials.accessExpiresAt),
        isFalse,
      );
      expect(
        credentials.isRefreshUsableAt(credentials.refreshExpiresAt),
        isFalse,
      );
    });

    test('rejects invalid credential values without echoing them', () {
      for (final invalid in <String>[
        '',
        ' leading',
        'trailing ',
        'line\nfeed',
      ]) {
        expect(
          () => AuthCredentials(
            accessCredential: invalid,
            refreshCredential: 'fixture-refresh',
            accessExpiresAt: DateTime.utc(2030),
            refreshExpiresAt: DateTime.utc(2031),
          ),
          throwsA(
            isA<ArgumentError>().having(
              (error) => error.message,
              'fixed message',
              'Authentication credential is invalid.',
            ),
          ),
        );
      }
      expect(
        () => AuthCredentials(
          accessCredential: 'fixture-access',
          refreshCredential: 'fixture-refresh',
          accessExpiresAt: DateTime.utc(2031),
          refreshExpiresAt: DateTime.utc(2030),
        ),
        throwsArgumentError,
      );
    });

    test('never exposes either credential through toString', () {
      final credentials = AuthCredentials(
        accessCredential: 'fixture-private-access',
        refreshCredential: 'fixture-private-refresh',
        accessExpiresAt: DateTime.utc(2030),
        refreshExpiresAt: DateTime.utc(2031),
      );

      expect(credentials.toString(), 'AuthCredentials([REDACTED])');
      expect(credentials.toString(), isNot(contains('fixture-private-access')));
      expect(
        credentials.toString(),
        isNot(contains('fixture-private-refresh')),
      );
    });
  });

  group('AuthSignInRequest', () {
    test('normalizes only the identifier and redacts both inputs', () {
      final request = AuthSignInRequest(
        identifier: '  fixture-account  ',
        password: ' fixture password ',
      );

      expect(request.identifier, 'fixture-account');
      expect(request.password, ' fixture password ');
      expect(request.toString(), 'AuthSignInRequest([REDACTED])');
      expect(request.toString(), isNot(contains('fixture-account')));
      expect(request.toString(), isNot(contains('fixture password')));
    });

    test('rejects empty and control-character inputs with fixed errors', () {
      expect(
        () => AuthSignInRequest(identifier: ' ', password: 'fixture'),
        throwsArgumentError,
      );
      expect(
        () => AuthSignInRequest(
          identifier: 'fixture-account',
          password: 'fixture\npassword',
        ),
        throwsArgumentError,
      );
    });
  });

  test('session states and failures contain only stable classifications', () {
    const failure = AuthSignInRejectedFailure();
    const state = AuthSessionState.failure(failure);

    expect(state.phase, AuthSessionPhase.failure);
    expect(state.isAuthenticated, isFalse);
    expect(state.isRestoring, isFalse);
    expect(state.toString(), contains('auth.sign_in_rejected'));
    expect(failure.toString(), contains('auth.sign_in_rejected'));
  });

  test(
    'unconfigured gateway never creates a local production session',
    () async {
      const gateway = UnconfiguredAuthGateway();
      final request = AuthSignInRequest(
        identifier: 'fixture-account',
        password: 'fixture-password',
      );

      await expectLater(
        gateway.signIn(request, cancellationToken: NetworkCancellationToken()),
        throwsA(isA<AuthServiceUnavailableFailure>()),
      );
      await expectLater(
        gateway.refresh(
          refreshCredential: 'fixture-refresh',
          cancellationToken: NetworkCancellationToken(),
        ),
        throwsA(isA<AuthSessionExpiredFailure>()),
      );
    },
  );

  group('AuthRouteContract', () {
    test('builds only canonical protected return locations', () {
      final signIn = AuthRouteContract.signInLocation(
        returnTo: Uri.parse('/account'),
      );
      final loading = AuthRouteContract.sessionLoadingLocation(
        returnTo: Uri.parse('/account'),
      );

      expect(signIn.path, AuthRouteContract.signInPath);
      expect(
        signIn.queryParameters[AuthRouteContract.returnToQueryParameter],
        AuthRouteContract.protectedLocation,
      );
      expect(loading.path, AuthRouteContract.sessionLoadingPath);
      expect(
        AuthRouteContract.tryParseReturnTo('/account'),
        Uri(path: '/account'),
      );
    });

    test('drops external, ambiguous and dynamic return targets', () {
      for (final value in <String>[
        'https://example.invalid/account',
        '//example.invalid/account',
        '/account?credential=fixture',
        '/account#fragment',
        '/sign-in',
        '/missing',
      ]) {
        expect(AuthRouteContract.tryParseReturnTo(value), isNull);
      }

      final signIn = AuthRouteContract.signInLocation(
        returnTo: Uri.parse('https://example.invalid/account'),
      );
      expect(signIn.query, isEmpty);
    });
  });
}
