import 'dart:async';
import 'dart:collection';

import 'package:flutter_template/core/error/app_error.dart';
import 'package:flutter_template/core/network/network_cancellation_token.dart';
import 'package:flutter_template/core/network/network_client.dart';
import 'package:flutter_template/core/network/network_credential_provider.dart';
import 'package:flutter_template/core/network/network_request.dart';
import 'package:flutter_template/core/network/network_response.dart';
import 'package:flutter_template/features/auth/data/authenticated_network_client.dart';
import 'package:flutter_template/features/auth/domain/auth_session_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'passes successful and public 401 requests through without refresh',
    () async {
      final successBase = _ScriptedNetworkClient(<_NetworkOutcome>[
        const _PayloadOutcome(<String, Object?>{'value': 7}),
      ]);
      final successCoordinator = _ControlledSessionCoordinator();
      final successClient = AuthenticatedNetworkClient(
        baseClient: successBase,
        sessionCoordinator: successCoordinator,
      );
      addTearDown(successClient.close);

      final response = await successClient.send<int>(
        _request(requiresCredential: true),
        decoder:
            (payload) => (payload! as Map<String, Object?>)['value']! as int,
      );
      expect(response.data, 7);
      expect(successCoordinator.refreshCallCount, 0);

      final publicFailure = NetworkResponseError(statusCode: 401);
      final publicBase = _ScriptedNetworkClient(<_NetworkOutcome>[
        _FailureOutcome(publicFailure),
      ]);
      final publicCoordinator = _ControlledSessionCoordinator();
      final publicClient = AuthenticatedNetworkClient(
        baseClient: publicBase,
        sessionCoordinator: publicCoordinator,
      );
      addTearDown(publicClient.close);

      await expectLater(
        publicClient.send<Object?>(
          _request(requiresCredential: false),
          decoder: (payload) => payload,
        ),
        throwsA(same(publicFailure)),
      );
      expect(publicCoordinator.refreshCallCount, 0);
      expect(publicBase.requests, hasLength(1));
    },
  );

  test('refreshes and replays a protected GET at most once', () async {
    final firstFailure = NetworkResponseError(statusCode: 401);
    final base = _ScriptedNetworkClient(<_NetworkOutcome>[
      _FailureOutcome(firstFailure),
      const _PayloadOutcome('recovered'),
    ]);
    final coordinator = _ControlledSessionCoordinator();
    final client = AuthenticatedNetworkClient(
      baseClient: base,
      sessionCoordinator: coordinator,
    );
    addTearDown(client.close);

    final result = client.send<String>(
      _request(requiresCredential: true),
      decoder: (payload) => payload! as String,
    );
    await coordinator.firstRefreshRequested;
    coordinator.succeedRefresh();

    expect((await result).data, 'recovered');
    expect(coordinator.refreshCallCount, 1);
    expect(coordinator.refreshWorkCount, 1);
    expect(base.requests, hasLength(2));
  });

  test(
    'concurrent protected GET requests wait for one refresh work item',
    () async {
      final base = _ScriptedNetworkClient(<_NetworkOutcome>[
        _FailureOutcome(NetworkResponseError(statusCode: 401)),
        _FailureOutcome(NetworkResponseError(statusCode: 401)),
        const _PayloadOutcome('first'),
        const _PayloadOutcome('second'),
      ]);
      final coordinator = _ControlledSessionCoordinator();
      final client = AuthenticatedNetworkClient(
        baseClient: base,
        sessionCoordinator: coordinator,
      );
      addTearDown(client.close);

      final first = client.send<String>(
        _request(operation: 'auth.first', requiresCredential: true),
        decoder: (payload) => payload! as String,
      );
      final second = client.send<String>(
        _request(operation: 'auth.second', requiresCredential: true),
        decoder: (payload) => payload! as String,
      );
      await coordinator.firstRefreshRequested;
      coordinator.succeedRefresh();

      final responses = await Future.wait(<Future<NetworkResponse<String>>>[
        first,
        second,
      ]);
      expect(responses.map((response) => response.data), <String>[
        'first',
        'second',
      ]);
      expect(coordinator.refreshCallCount, 2);
      expect(coordinator.refreshWorkCount, 1);
      expect(base.requests, hasLength(4));
    },
  );

  test(
    'default non-GET refreshes the session but returns the original 401',
    () async {
      final original = NetworkResponseError(statusCode: 401);
      final base = _ScriptedNetworkClient(<_NetworkOutcome>[
        _FailureOutcome(original),
      ]);
      final coordinator = _ControlledSessionCoordinator();
      final client = AuthenticatedNetworkClient(
        baseClient: base,
        sessionCoordinator: coordinator,
      );
      addTearDown(client.close);

      final result = client.send<Object?>(
        _request(
          method: NetworkMethod.post,
          requiresCredential: true,
          body: <String, Object?>{'action': 'fixture'},
        ),
        decoder: (payload) => payload,
      );
      await coordinator.firstRefreshRequested;
      coordinator.succeedRefresh();

      await expectLater(result, throwsA(same(original)));
      expect(base.requests, hasLength(1));
      expect(coordinator.refreshWorkCount, 1);
    },
  );

  test('explicitly idempotent non-GET can replay once', () async {
    final base = _ScriptedNetworkClient(<_NetworkOutcome>[
      _FailureOutcome(NetworkResponseError(statusCode: 401)),
      const _PayloadOutcome('updated'),
    ]);
    final coordinator = _ControlledSessionCoordinator();
    final client = AuthenticatedNetworkClient(
      baseClient: base,
      sessionCoordinator: coordinator,
    );
    addTearDown(client.close);

    final result = client.send<String>(
      _request(
        method: NetworkMethod.post,
        requiresCredential: true,
        replayPolicy: NetworkRequestReplayPolicy.explicitlyIdempotent,
        body: <String, Object?>{'action': 'fixture'},
      ),
      decoder: (payload) => payload! as String,
    );
    await coordinator.firstRefreshRequested;
    coordinator.succeedRefresh();

    expect((await result).data, 'updated');
    expect(base.requests, hasLength(2));
  });

  test('refresh failure preserves the first safe 401', () async {
    final original = NetworkResponseError(statusCode: 401);
    final base = _ScriptedNetworkClient(<_NetworkOutcome>[
      _FailureOutcome(original),
    ]);
    final coordinator = _ControlledSessionCoordinator();
    final client = AuthenticatedNetworkClient(
      baseClient: base,
      sessionCoordinator: coordinator,
    );
    addTearDown(client.close);

    final result = client.send<Object?>(
      _request(requiresCredential: true),
      decoder: (payload) => payload,
    );
    await coordinator.firstRefreshRequested;
    coordinator.failRefresh(StateError('private-refresh-detail'));

    await expectLater(result, throwsA(same(original)));
    expect(base.requests, hasLength(1));
  });

  test('a response from an earlier session generation is cancelled', () async {
    final base = _ScriptedNetworkClient(<_NetworkOutcome>[
      const _PayloadOutcome('stale-account-data'),
    ]);
    final coordinator = _ControlledSessionCoordinator();
    final client = AuthenticatedNetworkClient(
      baseClient: base,
      sessionCoordinator: coordinator,
    );
    addTearDown(client.close);

    final result = client.send<String>(
      _request(requiresCredential: true),
      decoder: (payload) => payload! as String,
    );
    coordinator.beginNewSession();

    await expectLater(result, throwsA(isA<NetworkCancelledError>()));
    expect(coordinator.refreshCallCount, 0);
    expect(coordinator.invalidateCount, 0);
    expect(base.requests, hasLength(1));
  });

  test('a stale 401 cannot refresh or replay a newer session', () async {
    final base = _ScriptedNetworkClient(<_NetworkOutcome>[
      _FailureOutcome(NetworkResponseError(statusCode: 401)),
    ]);
    final coordinator = _ControlledSessionCoordinator();
    final client = AuthenticatedNetworkClient(
      baseClient: base,
      sessionCoordinator: coordinator,
    );
    addTearDown(client.close);

    final result = client.send<Object?>(
      _request(requiresCredential: true),
      decoder: (payload) => payload,
    );
    coordinator.beginNewSession();

    await expectLater(result, throwsA(isA<NetworkCancelledError>()));
    expect(coordinator.refreshCallCount, 0);
    expect(coordinator.invalidateCount, 0);
    expect(base.requests, hasLength(1));
  });

  test('a session change while awaiting refresh prevents replay', () async {
    final base = _ScriptedNetworkClient(<_NetworkOutcome>[
      _FailureOutcome(NetworkResponseError(statusCode: 401)),
      const _PayloadOutcome('must-not-be-delivered'),
    ]);
    final coordinator = _ControlledSessionCoordinator();
    final client = AuthenticatedNetworkClient(
      baseClient: base,
      sessionCoordinator: coordinator,
    );
    addTearDown(client.close);

    final result = client.send<String>(
      _request(requiresCredential: true),
      decoder: (payload) => payload! as String,
    );
    await coordinator.firstRefreshRequested;
    coordinator.succeedRefresh();
    coordinator.beginNewSession();

    await expectLater(result, throwsA(isA<NetworkCancelledError>()));
    expect(coordinator.refreshCallCount, 1);
    expect(coordinator.invalidateCount, 0);
    expect(base.requests, hasLength(1));
  });

  test(
    'caller cancellation does not cancel another request shared refresh',
    () async {
      final base = _ScriptedNetworkClient(<_NetworkOutcome>[
        _FailureOutcome(NetworkResponseError(statusCode: 401)),
        _FailureOutcome(NetworkResponseError(statusCode: 401)),
        const _PayloadOutcome('remaining-caller'),
      ]);
      final coordinator = _ControlledSessionCoordinator();
      final client = AuthenticatedNetworkClient(
        baseClient: base,
        sessionCoordinator: coordinator,
      );
      addTearDown(client.close);
      final cancelledCaller = NetworkCancellationToken();

      final first = client.send<String>(
        _request(operation: 'auth.cancelled', requiresCredential: true),
        decoder: (payload) => payload! as String,
        cancellationToken: cancelledCaller,
      );
      final second = client.send<String>(
        _request(operation: 'auth.remaining', requiresCredential: true),
        decoder: (payload) => payload! as String,
      );
      await coordinator.firstRefreshRequested;

      cancelledCaller.cancel();
      await expectLater(first, throwsA(isA<NetworkCancelledError>()));
      expect(coordinator.refreshIsCompleted, isFalse);

      coordinator.succeedRefresh();
      expect((await second).data, 'remaining-caller');
      expect(coordinator.refreshWorkCount, 1);
      expect(base.requests, hasLength(3));
    },
  );

  test('a second 401 invalidates the session without a retry loop', () async {
    final retryFailure = NetworkResponseError(statusCode: 401);
    final base = _ScriptedNetworkClient(<_NetworkOutcome>[
      _FailureOutcome(NetworkResponseError(statusCode: 401)),
      _FailureOutcome(retryFailure),
    ]);
    final coordinator = _ControlledSessionCoordinator();
    final client = AuthenticatedNetworkClient(
      baseClient: base,
      sessionCoordinator: coordinator,
    );
    addTearDown(client.close);

    final result = client.send<Object?>(
      _request(requiresCredential: true),
      decoder: (payload) => payload,
    );
    await coordinator.firstRefreshRequested;
    coordinator.succeedRefresh();

    await expectLater(result, throwsA(same(retryFailure)));
    expect(coordinator.invalidateCount, 1);
    expect(base.requests, hasLength(2));
  });

  test('close is idempotent and rejects later sends', () async {
    final base = _ScriptedNetworkClient(<_NetworkOutcome>[]);
    final client = AuthenticatedNetworkClient(
      baseClient: base,
      sessionCoordinator: _ControlledSessionCoordinator(),
    );

    client.close();
    client.close();

    expect(base.closeCount, 1);
    await expectLater(
      client.send<Object?>(
        _request(requiresCredential: true),
        decoder: (payload) => payload,
      ),
      throwsStateError,
    );
  });
}

NetworkRequest _request({
  String operation = 'auth.load',
  NetworkMethod method = NetworkMethod.get,
  bool requiresCredential = false,
  NetworkRequestReplayPolicy replayPolicy =
      NetworkRequestReplayPolicy.safeMethodOnly,
  Object? body,
}) {
  return NetworkRequest(
    operation: operation,
    method: method,
    path: 'fixture',
    requiresCredential: requiresCredential,
    replayPolicy: replayPolicy,
    body: body,
  );
}

sealed class _NetworkOutcome {
  const _NetworkOutcome();
}

final class _PayloadOutcome extends _NetworkOutcome {
  const _PayloadOutcome(this.payload);

  final Object? payload;
}

final class _FailureOutcome extends _NetworkOutcome {
  const _FailureOutcome(this.error);

  final AppError error;
}

final class _ScriptedNetworkClient implements NetworkClient {
  _ScriptedNetworkClient(Iterable<_NetworkOutcome> outcomes)
    : _outcomes = Queue<_NetworkOutcome>.of(outcomes);

  final Queue<_NetworkOutcome> _outcomes;
  final List<NetworkRequest> requests = <NetworkRequest>[];
  var closeCount = 0;
  var _isClosed = false;

  @override
  Future<NetworkResponse<T>> send<T>(
    NetworkRequest request, {
    required NetworkResponseDecoder<T> decoder,
    NetworkCancellationToken? cancellationToken,
  }) async {
    if (_isClosed) {
      throw StateError('Scripted network client is closed.');
    }
    requests.add(request);
    if (_outcomes.isEmpty) {
      throw StateError('No scripted network outcome remains.');
    }
    final outcome = _outcomes.removeFirst();
    switch (outcome) {
      case _FailureOutcome(:final error):
        throw error;
      case _PayloadOutcome(:final payload):
        final data = await decoder(payload);
        return NetworkResponse<T>(statusCode: 200, data: data);
    }
  }

  @override
  void close() {
    if (_isClosed) {
      return;
    }
    _isClosed = true;
    closeCount++;
  }
}

final class _ControlledSessionCoordinator implements AuthSessionCoordinator {
  final Completer<void> _firstRefreshRequested = Completer<void>();
  Completer<void>? _refreshOperation;
  var refreshCallCount = 0;
  var refreshWorkCount = 0;
  var invalidateCount = 0;
  var _sessionGeneration = 1;

  Future<void> get firstRefreshRequested => _firstRefreshRequested.future;
  bool get refreshIsCompleted => _refreshOperation?.isCompleted ?? false;

  @override
  int get sessionGeneration => _sessionGeneration;

  void beginNewSession() {
    _sessionGeneration++;
  }

  @override
  Future<NetworkCredential?> loadNetworkCredential() async => null;

  @override
  Future<void> refreshSession() {
    refreshCallCount++;
    if (!_firstRefreshRequested.isCompleted) {
      _firstRefreshRequested.complete();
    }
    final existing = _refreshOperation;
    if (existing != null) {
      return existing.future;
    }
    refreshWorkCount++;
    final operation = Completer<void>();
    _refreshOperation = operation;
    return operation.future;
  }

  void succeedRefresh() {
    final operation = _refreshOperation;
    if (operation != null && !operation.isCompleted) {
      operation.complete();
    }
  }

  void failRefresh(Object error) {
    final operation = _refreshOperation;
    if (operation != null && !operation.isCompleted) {
      operation.completeError(error, StackTrace.current);
    }
  }

  @override
  Future<void> invalidateSession() async {
    invalidateCount++;
    _sessionGeneration++;
  }
}
