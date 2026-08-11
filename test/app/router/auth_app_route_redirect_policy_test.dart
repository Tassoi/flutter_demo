import 'package:flutter_template/app/router/app_route_redirect_policy.dart';
import 'package:flutter_template/app/router/auth_app_route_redirect_policy.dart';
import 'package:flutter_template/features/auth/domain/auth_failure.dart';
import 'package:flutter_template/features/auth/domain/auth_session_state.dart';
import 'package:flutter_template/features/auth/routing/auth_route_contract.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AuthSessionState session;
  late AuthAppRouteRedirectPolicy policy;

  setUp(() {
    session = const AuthSessionState.signedOut();
    policy = AuthAppRouteRedirectPolicy(sessionStateReader: () => session);
  });

  test('keeps public routes available in every session phase', () {
    for (final state in <AuthSessionState>[
      const AuthSessionState.restoring(),
      const AuthSessionState.signedOut(),
      const AuthSessionState.signingIn(),
      const AuthSessionState.authenticated(),
      const AuthSessionState.failure(AuthPersistenceFailure()),
    ]) {
      session = state;
      expect(_redirect(policy, Uri(path: '/')), isNull);
      expect(_redirect(policy, Uri(path: '/example/1')), isNull);
    }
  });

  test('protected route uses loading, sign-in and allow states', () {
    session = const AuthSessionState.restoring();
    final loading = _redirect(policy, Uri.parse('/account?private=value'));
    expect(loading?.path, AuthRouteContract.sessionLoadingPath);
    expect(
      loading?.queryParameters[AuthRouteContract.returnToQueryParameter],
      AuthRouteContract.protectedLocation,
    );
    expect(loading.toString(), isNot(contains('private')));

    session = const AuthSessionState.signedOut();
    final signIn = _redirect(policy, Uri.parse('/account?private=value'));
    expect(signIn?.path, AuthRouteContract.signInPath);
    expect(
      signIn?.queryParameters[AuthRouteContract.returnToQueryParameter],
      AuthRouteContract.protectedLocation,
    );
    expect(signIn.toString(), isNot(contains('private')));

    session = const AuthSessionState.authenticated();
    expect(_redirect(policy, Uri(path: '/account')), isNull);
  });

  test('loading route resolves after restoration without loops', () {
    final loading = AuthRouteContract.sessionLoadingLocation(
      returnTo: Uri(path: '/account'),
    );

    session = const AuthSessionState.restoring();
    expect(_redirect(policy, loading), isNull);

    session = const AuthSessionState.signedOut();
    final signIn = _redirect(policy, loading);
    expect(signIn?.path, AuthRouteContract.signInPath);
    expect(
      signIn?.queryParameters[AuthRouteContract.returnToQueryParameter],
      '/account',
    );

    session = const AuthSessionState.authenticated();
    expect(_redirect(policy, loading), Uri(path: '/account'));
  });

  test('authenticated sign-in restores only a validated internal target', () {
    session = const AuthSessionState.authenticated();

    expect(
      _redirect(
        policy,
        AuthRouteContract.signInLocation(returnTo: Uri(path: '/account')),
      ),
      Uri(path: '/account'),
    );
    expect(_redirect(policy, Uri(path: '/sign-in')), Uri(path: '/'));
    expect(
      _redirect(
        policy,
        Uri.parse('/sign-in?returnTo=https%3A%2F%2Fexample.invalid%2Faccount'),
      ),
      Uri(path: '/'),
    );
    expect(
      _redirect(policy, Uri.parse('/sign-in?returnTo=%2Fsign-in')),
      Uri(path: '/'),
    );
  });

  test('signed-out and failed states stay on the sign-in route', () {
    for (final state in <AuthSessionState>[
      const AuthSessionState.signedOut(),
      const AuthSessionState.signingIn(),
      const AuthSessionState.failure(AuthSessionExpiredFailure()),
    ]) {
      session = state;
      expect(
        _redirect(
          policy,
          AuthRouteContract.signInLocation(returnTo: Uri(path: '/account')),
        ),
        isNull,
      );
    }
  });

  test(
    'direct loading route with unsafe return data reaches a safe endpoint',
    () {
      final unsafeLoading = Uri.parse(
        '/session-loading?returnTo=https%3A%2F%2Fexample.invalid%2Fprivate',
      );

      session = const AuthSessionState.signedOut();
      expect(_redirect(policy, unsafeLoading), Uri(path: '/sign-in'));

      session = const AuthSessionState.authenticated();
      expect(_redirect(policy, unsafeLoading), Uri(path: '/'));
    },
  );
}

Uri? _redirect(AuthAppRouteRedirectPolicy policy, Uri uri) {
  return policy.redirect(AppRouteRedirectRequest(uri: uri));
}
