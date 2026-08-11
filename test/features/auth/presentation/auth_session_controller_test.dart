import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_template/core/error/app_error.dart';
import 'package:flutter_template/core/logging/app_log_level.dart';
import 'package:flutter_template/core/logging/app_logger.dart';
import 'package:flutter_template/core/network/network_cancellation_token.dart';
import 'package:flutter_template/features/auth/domain/auth_credentials.dart';
import 'package:flutter_template/features/auth/domain/auth_failure.dart';
import 'package:flutter_template/features/auth/domain/auth_gateway.dart';
import 'package:flutter_template/features/auth/domain/auth_session_state.dart';
import 'package:flutter_template/features/auth/presentation/auth_session_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/features/auth/auth_credentials_fixture.dart';
import '../../../support/features/auth/controlled_auth_credential_persistence.dart';
import '../../../support/features/auth/controlled_auth_gateway.dart';
import '../../../support/features/auth/mutable_auth_clock.dart';

void main() {
  final now = DateTime.utc(2029, DateTime.january, 1, 12);

  test('missing startup envelope settles as signed out', () async {
    final persistence = ControlledAuthCredentialPersistence();
    final container = _createContainer(
      gateway: ControlledAuthGateway(),
      persistence: persistence,
      clock: MutableAuthClock(now),
    );
    final controller = container.read(authSessionProvider.notifier);

    expect(
      container.read(authSessionProvider).phase,
      AuthSessionPhase.restoring,
    );
    await controller.restorationCompleted;

    expect(
      container.read(authSessionProvider).phase,
      AuthSessionPhase.signedOut,
    );
    expect(persistence.loadCount, 1);
    expect(await controller.loadNetworkCredential(), isNull);
  });

  test(
    'restores a valid session without refreshing or exposing it in state',
    () async {
      final credentials = createAuthCredentialsFixture(
        accessExpiresAt: now.add(const Duration(hours: 1)),
        refreshExpiresAt: now.add(const Duration(days: 1)),
      );
      final gateway = ControlledAuthGateway();
      final persistence = ControlledAuthCredentialPersistence(
        storedCredentials: credentials,
      );
      final container = _createContainer(
        gateway: gateway,
        persistence: persistence,
        clock: MutableAuthClock(now),
      );
      final controller = container.read(authSessionProvider.notifier);

      await controller.restorationCompleted;

      final state = container.read(authSessionProvider);
      expect(state.phase, AuthSessionPhase.authenticated);
      expect(state.toString(), isNot(contains(credentials.accessCredential)));
      expect(state.toString(), isNot(contains(credentials.refreshCredential)));
      expect(gateway.refreshOperations, isEmpty);
      final networkCredential = await controller.loadNetworkCredential();
      expect(networkCredential?.headerName, 'authorization');
      expect(
        networkCredential?.headerValue,
        'Bearer ${credentials.accessCredential}',
      );
      expect(
        networkCredential.toString(),
        isNot(contains(credentials.accessCredential)),
      );
    },
  );

  test(
    'refreshes an expired access credential during startup restoration',
    () async {
      final gateway = ControlledAuthGateway();
      final persistence = ControlledAuthCredentialPersistence(
        storedCredentials: createAuthCredentialsFixture(
          generation: 'expired',
          accessExpiresAt: now.subtract(const Duration(minutes: 1)),
          refreshExpiresAt: now.add(const Duration(days: 1)),
        ),
      );
      final container = _createContainer(
        gateway: gateway,
        persistence: persistence,
        clock: MutableAuthClock(now),
      );
      final controller = container.read(authSessionProvider.notifier);
      await gateway.firstRefreshRequested;

      gateway.refreshOperations.single.succeed(
        createAuthCredentialsFixture(
          generation: 'restored',
          accessExpiresAt: now.add(const Duration(hours: 1)),
          refreshExpiresAt: now.add(const Duration(days: 2)),
        ),
      );
      await controller.restorationCompleted;

      expect(gateway.refreshOperations, hasLength(1));
      expect(persistence.saveCount, 1);
      expect(
        container.read(authSessionProvider).phase,
        AuthSessionPhase.authenticated,
      );
    },
  );

  test(
    'maps startup storage failure and never treats it as authenticated',
    () async {
      final persistence =
          ControlledAuthCredentialPersistence()
            ..loadFailure = const AuthPersistenceFailure();
      final container = _createContainer(
        gateway: ControlledAuthGateway(),
        persistence: persistence,
        clock: MutableAuthClock(now),
      );
      final controller = container.read(authSessionProvider.notifier);

      await controller.restorationCompleted;

      final state = container.read(authSessionProvider);
      expect(state.phase, AuthSessionPhase.failure);
      expect(state.failure, isA<AuthPersistenceFailure>());
      expect(await controller.loadNetworkCredential(), isNull);
      expect(persistence.clearCount, 1);
    },
  );

  test(
    'sign in persists before authentication and suppresses duplicates',
    () async {
      final gateway = ControlledAuthGateway();
      final persistence = ControlledAuthCredentialPersistence();
      final logger = _RecordingAppLogger();
      final container = _createContainer(
        gateway: gateway,
        persistence: persistence,
        clock: MutableAuthClock(now),
        logger: logger,
      );
      final controller = container.read(authSessionProvider.notifier);
      await controller.restorationCompleted;

      final signIn = controller.signIn(
        identifier: 'fixture-account',
        password: 'fixture-password',
      );
      final duplicate = controller.signIn(
        identifier: 'other-fixture-account',
        password: 'other-fixture-password',
      );
      await gateway.firstSignInRequested;

      expect(await duplicate, isFalse);
      expect(gateway.signInOperations, hasLength(1));
      expect(
        gateway.safeSignInDescriptions.single,
        'AuthSignInRequest([REDACTED])',
      );
      expect(
        container.read(authSessionProvider).phase,
        AuthSessionPhase.signingIn,
      );

      gateway.signInOperations.single.succeed(
        createAuthCredentialsFixture(
          generation: 'signed-in',
          accessExpiresAt: now.add(const Duration(hours: 1)),
          refreshExpiresAt: now.add(const Duration(days: 1)),
        ),
      );
      expect(await signIn, isTrue);

      expect(persistence.clearCount, 1);
      expect(persistence.saveCount, 1);
      expect(
        container.read(authSessionProvider).phase,
        AuthSessionPhase.authenticated,
      );
      expect(
        logger.events.map((event) => event.event),
        contains('auth.sign_in_succeeded'),
      );
      expect(logger.serialized, isNot(contains('fixture-account')));
      expect(logger.serialized, isNot(contains('fixture-password')));
      expect(logger.events.every((event) => event.context.isEmpty), isTrue);
      expect(logger.events.every((event) => event.error == null), isTrue);
    },
  );

  test('maps rejected and network login failures to stable states', () async {
    for (final scenario in <(Object, Type)>[
      (const AuthSignInRejectedFailure(), AuthSignInRejectedFailure),
      (const NetworkConnectionError(), AuthServiceUnavailableFailure),
    ]) {
      final gateway = ControlledAuthGateway();
      final container = _createContainer(
        gateway: gateway,
        persistence: ControlledAuthCredentialPersistence(),
        clock: MutableAuthClock(now),
      );
      final controller = container.read(authSessionProvider.notifier);
      await controller.restorationCompleted;

      final signIn = controller.signIn(
        identifier: 'fixture-account',
        password: 'fixture-password',
      );
      await gateway.firstSignInRequested;
      gateway.signInOperations.single.fail(scenario.$1);

      expect(await signIn, isFalse);
      final state = container.read(authSessionProvider);
      expect(state.phase, AuthSessionPhase.failure);
      expect(state.failure.runtimeType, scenario.$2);
      expect(state.toString(), isNot(contains('fixture-password')));
    }
  });

  test(
    'credential save failure fails closed and clears uncertain data',
    () async {
      final gateway = ControlledAuthGateway();
      final persistence =
          ControlledAuthCredentialPersistence()
            ..saveFailure = const AuthPersistenceFailure();
      final container = _createContainer(
        gateway: gateway,
        persistence: persistence,
        clock: MutableAuthClock(now),
      );
      final controller = container.read(authSessionProvider.notifier);
      await controller.restorationCompleted;

      final signIn = controller.signIn(
        identifier: 'fixture-account',
        password: 'fixture-password',
      );
      await gateway.firstSignInRequested;
      gateway.signInOperations.single.succeed(
        createAuthCredentialsFixture(
          accessExpiresAt: now.add(const Duration(hours: 1)),
          refreshExpiresAt: now.add(const Duration(days: 1)),
        ),
      );

      expect(await signIn, isFalse);
      expect(
        container.read(authSessionProvider).failure,
        isA<AuthPersistenceFailure>(),
      );
      expect(await controller.loadNetworkCredential(), isNull);
      expect(persistence.clearCount, 2);
    },
  );

  test(
    'invalid programmatic login cannot discard an authenticated session',
    () async {
      final credentials = createAuthCredentialsFixture(
        accessExpiresAt: now.add(const Duration(hours: 1)),
        refreshExpiresAt: now.add(const Duration(days: 1)),
      );
      final persistence = ControlledAuthCredentialPersistence(
        storedCredentials: credentials,
      );
      final container = _createContainer(
        gateway: ControlledAuthGateway(),
        persistence: persistence,
        clock: MutableAuthClock(now),
      );
      final controller = container.read(authSessionProvider.notifier);
      await controller.restorationCompleted;

      final signedIn = await controller.signIn(
        identifier: 'invalid\u0000identifier',
        password: 'fixture-password',
      );

      expect(signedIn, isFalse);
      expect(
        container.read(authSessionProvider).phase,
        AuthSessionPhase.authenticated,
      );
      expect(persistence.clearCount, 0);
      expect(
        (await controller.loadNetworkCredential())?.headerValue,
        'Bearer ${credentials.accessCredential}',
      );
    },
  );

  test(
    'sign out clears memory before I/O and reports delete failure',
    () async {
      final gateway = ControlledAuthGateway();
      final persistence = ControlledAuthCredentialPersistence(
        storedCredentials: createAuthCredentialsFixture(
          accessExpiresAt: now.add(const Duration(hours: 1)),
          refreshExpiresAt: now.add(const Duration(days: 1)),
        ),
      );
      final container = _createContainer(
        gateway: gateway,
        persistence: persistence,
        clock: MutableAuthClock(now),
      );
      final controller = container.read(authSessionProvider.notifier);
      await controller.restorationCompleted;
      persistence.clearFailure = const AuthPersistenceFailure();

      final signOut = controller.signOut();

      expect(
        container.read(authSessionProvider).phase,
        AuthSessionPhase.signedOut,
      );
      expect(await controller.loadNetworkCredential(), isNull);
      expect(await signOut, isFalse);
      expect(
        container.read(authSessionProvider).failure,
        isA<AuthPersistenceFailure>(),
      );
    },
  );

  test('concurrent refresh callers share one gateway operation', () async {
    final gateway = ControlledAuthGateway();
    final persistence = ControlledAuthCredentialPersistence(
      storedCredentials: createAuthCredentialsFixture(
        accessExpiresAt: now.add(const Duration(hours: 1)),
        refreshExpiresAt: now.add(const Duration(days: 1)),
      ),
    );
    final container = _createContainer(
      gateway: gateway,
      persistence: persistence,
      clock: MutableAuthClock(now),
    );
    final controller = container.read(authSessionProvider.notifier);
    await controller.restorationCompleted;

    final first = controller.refreshSession();
    final second = controller.refreshSession();
    await gateway.firstRefreshRequested;

    expect(gateway.refreshOperations, hasLength(1));
    gateway.refreshOperations.single.succeed(
      createAuthCredentialsFixture(
        generation: 'refreshed',
        accessExpiresAt: now.add(const Duration(hours: 2)),
        refreshExpiresAt: now.add(const Duration(days: 2)),
      ),
    );
    await Future.wait<void>(<Future<void>>[first, second]);

    expect(gateway.refreshOperations, hasLength(1));
    expect(persistence.saveCount, 1);
    expect(
      container.read(authSessionProvider).phase,
      AuthSessionPhase.authenticated,
    );
  });

  test(
    'synchronous refresh failure invalidates without retaining its future',
    () async {
      final gateway = _SynchronousRefreshFailureGateway();
      final persistence = ControlledAuthCredentialPersistence(
        storedCredentials: createAuthCredentialsFixture(
          accessExpiresAt: now.add(const Duration(hours: 1)),
          refreshExpiresAt: now.add(const Duration(days: 1)),
        ),
      );
      final container = _createContainer(
        gateway: gateway,
        persistence: persistence,
        clock: MutableAuthClock(now),
      );
      final controller = container.read(authSessionProvider.notifier);
      await controller.restorationCompleted;

      final firstRefresh = controller.refreshSession();
      await expectLater(
        firstRefresh,
        throwsA(isA<AuthSessionExpiredFailure>()),
      );
      final secondRefresh = controller.refreshSession();

      expect(identical(firstRefresh, secondRefresh), isFalse);
      await expectLater(
        secondRefresh,
        throwsA(isA<AuthSessionExpiredFailure>()),
      );
      expect(gateway.refreshCount, 1);
      expect(persistence.clearCount, 2);
      expect(
        container.read(authSessionProvider).failure,
        isA<AuthSessionExpiredFailure>(),
      );
    },
  );

  test(
    'refresh failure invalidates memory and clears the secure envelope',
    () async {
      final gateway = ControlledAuthGateway();
      final persistence = ControlledAuthCredentialPersistence(
        storedCredentials: createAuthCredentialsFixture(
          accessExpiresAt: now.add(const Duration(hours: 1)),
          refreshExpiresAt: now.add(const Duration(days: 1)),
        ),
      );
      final container = _createContainer(
        gateway: gateway,
        persistence: persistence,
        clock: MutableAuthClock(now),
      );
      final controller = container.read(authSessionProvider.notifier);
      await controller.restorationCompleted;

      final refresh = controller.refreshSession();
      await gateway.firstRefreshRequested;
      gateway.refreshOperations.single.fail(const NetworkTimeoutError());

      await expectLater(refresh, throwsA(isA<AuthSessionExpiredFailure>()));
      expect(
        container.read(authSessionProvider).failure,
        isA<AuthSessionExpiredFailure>(),
      );
      expect(await controller.loadNetworkCredential(), isNull);
      expect(persistence.storedCredentials, isNull);
      expect(persistence.clearCount, 1);
    },
  );

  test(
    'sign out cancels refresh and its late result cannot revive state',
    () async {
      final gateway = ControlledAuthGateway();
      final persistence = ControlledAuthCredentialPersistence(
        storedCredentials: createAuthCredentialsFixture(
          accessExpiresAt: now.add(const Duration(hours: 1)),
          refreshExpiresAt: now.add(const Duration(days: 1)),
        ),
      );
      final container = _createContainer(
        gateway: gateway,
        persistence: persistence,
        clock: MutableAuthClock(now),
      );
      final controller = container.read(authSessionProvider.notifier);
      await controller.restorationCompleted;

      final refresh = controller.refreshSession();
      await gateway.firstRefreshRequested;
      final operation = gateway.refreshOperations.single;
      final signOut = controller.signOut();

      expect(operation.cancellationToken.isCancelled, isTrue);
      expect(
        container.read(authSessionProvider).phase,
        AuthSessionPhase.signedOut,
      );
      operation.succeed(
        createAuthCredentialsFixture(
          generation: 'late',
          accessExpiresAt: now.add(const Duration(hours: 2)),
          refreshExpiresAt: now.add(const Duration(days: 2)),
        ),
      );

      await expectLater(refresh, throwsA(isA<NetworkCancelledError>()));
      expect(await signOut, isTrue);
      expect(persistence.saveCount, 0);
      expect(persistence.storedCredentials, isNull);
      expect(
        container.read(authSessionProvider).phase,
        AuthSessionPhase.signedOut,
      );
    },
  );

  test(
    'sign out cancels login and its late result cannot create a session',
    () async {
      final gateway = ControlledAuthGateway();
      final persistence = ControlledAuthCredentialPersistence();
      final container = _createContainer(
        gateway: gateway,
        persistence: persistence,
        clock: MutableAuthClock(now),
      );
      final controller = container.read(authSessionProvider.notifier);
      await controller.restorationCompleted;

      final signIn = controller.signIn(
        identifier: 'fixture-account',
        password: 'fixture-password',
      );
      await gateway.firstSignInRequested;
      final operation = gateway.signInOperations.single;
      final signOut = controller.signOut();

      expect(operation.cancellationToken.isCancelled, isTrue);
      operation.succeed(
        createAuthCredentialsFixture(
          generation: 'late-login',
          accessExpiresAt: now.add(const Duration(hours: 1)),
          refreshExpiresAt: now.add(const Duration(days: 1)),
        ),
      );

      expect(await signIn, isFalse);
      expect(await signOut, isTrue);
      expect(persistence.saveCount, 0);
      expect(persistence.storedCredentials, isNull);
      expect(
        container.read(authSessionProvider).phase,
        AuthSessionPhase.signedOut,
      );
    },
  );

  test(
    'serialized storage makes logout win over an in-flight refresh save',
    () async {
      final gateway = ControlledAuthGateway();
      final persistence = ControlledAuthCredentialPersistence(
        storedCredentials: createAuthCredentialsFixture(
          accessExpiresAt: now.add(const Duration(hours: 1)),
          refreshExpiresAt: now.add(const Duration(days: 1)),
        ),
      )..saveGate = Completer<void>();
      final container = _createContainer(
        gateway: gateway,
        persistence: persistence,
        clock: MutableAuthClock(now),
      );
      final controller = container.read(authSessionProvider.notifier);
      await controller.restorationCompleted;

      final refresh = controller.refreshSession();
      await gateway.firstRefreshRequested;
      gateway.refreshOperations.single.succeed(
        createAuthCredentialsFixture(
          generation: 'saving',
          accessExpiresAt: now.add(const Duration(hours: 2)),
          refreshExpiresAt: now.add(const Duration(days: 2)),
        ),
      );
      await persistence.firstSaveStarted;

      final signOut = controller.signOut();
      expect(
        container.read(authSessionProvider).phase,
        AuthSessionPhase.signedOut,
      );
      persistence.saveGate!.complete();

      await expectLater(refresh, throwsA(isA<NetworkCancelledError>()));
      expect(await signOut, isTrue);
      expect(persistence.storedCredentials, isNull);
      expect(
        container.read(authSessionProvider).phase,
        AuthSessionPhase.signedOut,
      );
    },
  );

  test(
    'disposing the provider cancels login and ignores its late success',
    () async {
      final gateway = ControlledAuthGateway();
      final persistence = ControlledAuthCredentialPersistence();
      final container = _createContainer(
        gateway: gateway,
        persistence: persistence,
        clock: MutableAuthClock(now),
        registerTearDown: false,
      );
      final controller = container.read(authSessionProvider.notifier);
      await controller.restorationCompleted;
      final signIn = controller.signIn(
        identifier: 'fixture-account',
        password: 'fixture-password',
      );
      await gateway.firstSignInRequested;
      final operation = gateway.signInOperations.single;

      container.dispose();
      expect(operation.cancellationToken.isCancelled, isTrue);
      operation.succeed(
        createAuthCredentialsFixture(
          generation: 'late-disposed',
          accessExpiresAt: now.add(const Duration(hours: 1)),
          refreshExpiresAt: now.add(const Duration(days: 1)),
        ),
      );

      expect(await signIn, isFalse);
      expect(persistence.saveCount, 0);
    },
  );

  test(
    'expired runtime access credential triggers one refresh before injection',
    () async {
      final clock = MutableAuthClock(now);
      final gateway = ControlledAuthGateway();
      final persistence = ControlledAuthCredentialPersistence(
        storedCredentials: createAuthCredentialsFixture(
          generation: 'initial',
          accessExpiresAt: now.add(const Duration(minutes: 1)),
          refreshExpiresAt: now.add(const Duration(days: 1)),
        ),
      );
      final container = _createContainer(
        gateway: gateway,
        persistence: persistence,
        clock: clock,
      );
      final controller = container.read(authSessionProvider.notifier);
      await controller.restorationCompleted;
      clock.currentTime = now.add(const Duration(minutes: 2));

      final credentialFuture = controller.loadNetworkCredential();
      await gateway.firstRefreshRequested;
      gateway.refreshOperations.single.succeed(
        createAuthCredentialsFixture(
          generation: 'runtime-refresh',
          accessExpiresAt: now.add(const Duration(hours: 1)),
          refreshExpiresAt: now.add(const Duration(days: 2)),
        ),
      );
      final credential = await credentialFuture;

      expect(gateway.refreshOperations, hasLength(1));
      expect(credential?.headerValue, 'Bearer fixture-access-runtime-refresh');
    },
  );
}

ProviderContainer _createContainer({
  required AuthGateway gateway,
  required ControlledAuthCredentialPersistence persistence,
  required MutableAuthClock clock,
  AppLogger? logger,
  bool registerTearDown = true,
}) {
  final container = ProviderContainer(
    overrides: <Override>[
      authGatewayProvider.overrideWithValue(gateway),
      authCredentialPersistenceProvider.overrideWithValue(persistence),
      authClockProvider.overrideWithValue(clock),
      authLoggerProvider.overrideWithValue(logger),
    ],
  );
  if (registerTearDown) {
    addTearDown(container.dispose);
  }
  return container;
}

final class _SynchronousRefreshFailureGateway implements AuthGateway {
  var refreshCount = 0;

  @override
  Future<AuthCredentials> signIn(
    AuthSignInRequest request, {
    required NetworkCancellationToken cancellationToken,
  }) {
    return Future<AuthCredentials>.error(const AuthServiceUnavailableFailure());
  }

  @override
  Future<AuthCredentials> refresh({
    required String refreshCredential,
    required NetworkCancellationToken cancellationToken,
  }) {
    refreshCount++;
    throw const AuthSessionExpiredFailure();
  }
}

final class _RecordingAppLogger implements AppLogger {
  final List<_RecordedAuthLogEvent> events = <_RecordedAuthLogEvent>[];

  @override
  AppLogLevel get minimumLevel => AppLogLevel.debug;

  String get serialized => events.join('\n');

  @override
  void log(
    AppLogLevel level, {
    required String event,
    String message = '',
    Map<String, Object?> context = const <String, Object?>{},
    Object? error,
    StackTrace? stackTrace,
  }) {
    events.add(
      _RecordedAuthLogEvent(
        level: level,
        event: event,
        message: message,
        context: Map<String, Object?>.of(context),
        error: error,
        stackTrace: stackTrace,
      ),
    );
  }

  @override
  Future<void> close() async {}
}

final class _RecordedAuthLogEvent {
  const _RecordedAuthLogEvent({
    required this.level,
    required this.event,
    required this.message,
    required this.context,
    required this.error,
    required this.stackTrace,
  });

  final AppLogLevel level;
  final String event;
  final String message;
  final Map<String, Object?> context;
  final Object? error;
  final StackTrace? stackTrace;

  @override
  String toString() {
    return '$level|$event|$message|$context|${error.runtimeType}|'
        '${stackTrace == null}';
  }
}
