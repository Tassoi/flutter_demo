import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_template/core/error/app_error.dart';
import 'package:flutter_template/core/network/network_cancellation_token.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/state/create_test_provider_container.dart';

final _asyncListSourceProvider = Provider<_AsyncListSource>((_) {
  throw StateError('Async state tests must override their data source.');
});

final _reloadSignalProvider = NotifierProvider<_ReloadSignalController, int>(
  _ReloadSignalController.new,
);

final _asyncListProvider =
    AutoDisposeAsyncNotifierProvider<_AsyncListController, List<int>>(
      _AsyncListController.new,
      name: 'asyncLifecycleContract',
    );

void main() {
  test('initial load emits loading and non-empty data', () async {
    final source = _ControlledAsyncListSource();
    final container = _createContainer(source);
    final states = <AsyncValue<List<int>>>[];
    final subscription = container.listen<AsyncValue<List<int>>>(
      _asyncListProvider,
      (_, next) => states.add(next),
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    expect(container.read(_asyncListProvider).isLoading, isTrue);
    expect(source.requests, hasLength(1));

    source.requests.single.succeed(<int>[1, 2]);
    expect(await container.read(_asyncListProvider.future), <int>[1, 2]);
    expect(container.read(_asyncListProvider).valueOrNull, <int>[1, 2]);
    expect(states.first.isLoading, isTrue);
    expect(states.last.valueOrNull, <int>[1, 2]);
  });

  test('an empty collection remains successful data', () async {
    final source = _ControlledAsyncListSource();
    final container = _createContainer(source);
    final subscription = container.listen<AsyncValue<List<int>>>(
      _asyncListProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    source.requests.single.succeed(const <int>[]);
    expect(await container.read(_asyncListProvider.future), isEmpty);

    final state = container.read(_asyncListProvider);
    expect(state.hasValue, isTrue);
    expect(state.hasError, isFalse);
    expect(state.valueOrNull, isEmpty);
  });

  test(
    'failures become stable errors and retry ignores duplicate taps',
    () async {
      final source = _ControlledAsyncListSource();
      final container = _createContainer(source);
      final subscription = container.listen<AsyncValue<List<int>>>(
        _asyncListProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      final firstResult = container.read(_asyncListProvider.future);

      source.requests.single.fail(
        StateError('private-source-token'),
        StackTrace.current,
      );
      await expectLater(firstResult, throwsA(isA<UnexpectedAppError>()));

      final failedState = container.read(_asyncListProvider);
      expect(failedState.error, isA<UnexpectedAppError>());
      expect(
        failedState.error.toString(),
        isNot(contains('private-source-token')),
      );

      final retry = container.read(_asyncListProvider.notifier).retry();
      expect(container.read(_asyncListProvider).isLoading, isTrue);
      expect(source.requests, hasLength(2));

      await container.read(_asyncListProvider.notifier).retry();
      expect(source.requests, hasLength(2));

      source.requests.last.succeed(<int>[7]);
      await retry;

      expect(container.read(_asyncListProvider).valueOrNull, <int>[7]);
    },
  );

  test('auto dispose cancels work and ignores a late completion', () async {
    final source = _ControlledAsyncListSource();
    final container = _createContainer(source);
    final subscription = container.listen<AsyncValue<List<int>>>(
      _asyncListProvider,
      (_, _) {},
      fireImmediately: true,
    );
    final firstRequest = source.requests.single;

    subscription.close();
    await container.pump();

    expect(firstRequest.cancellationToken.isCancelled, isTrue);

    firstRequest.succeed(<int>[99]);
    await container.pump();

    final replacementSubscription = container.listen<AsyncValue<List<int>>>(
      _asyncListProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(replacementSubscription.close);
    expect(source.requests, hasLength(2));
    expect(container.read(_asyncListProvider).isLoading, isTrue);

    source.requests.last.succeed(const <int>[]);
    expect(await container.read(_asyncListProvider.future), isEmpty);
  });

  test('dependency rebuild cancels stale work and remains reusable', () async {
    final source = _ControlledAsyncListSource();
    final container = _createContainer(source);
    final subscription = container.listen<AsyncValue<List<int>>>(
      _asyncListProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    final staleRequest = source.requests.single;

    container.read(_reloadSignalProvider.notifier).advance();
    await container.pump();

    expect(staleRequest.cancellationToken.isCancelled, isTrue);
    expect(source.requests, hasLength(2));

    source.requests.last.succeed(<int>[3]);
    expect(await container.read(_asyncListProvider.future), <int>[3]);

    staleRequest.succeed(<int>[99]);
    await container.pump();
    expect(container.read(_asyncListProvider).valueOrNull, <int>[3]);

    final retry = container.read(_asyncListProvider.notifier).retry();
    expect(source.requests, hasLength(3));
    source.requests.last.succeed(<int>[4]);
    await retry;
    expect(container.read(_asyncListProvider).valueOrNull, <int>[4]);
  });
}

ProviderContainer _createContainer(_AsyncListSource source) {
  return createTestProviderContainer(
    overrides: <Override>[_asyncListSourceProvider.overrideWithValue(source)],
  );
}

abstract interface class _AsyncListSource {
  Future<List<int>> load(NetworkCancellationToken cancellationToken);
}

final class _AsyncListController extends AutoDisposeAsyncNotifier<List<int>> {
  static const AppErrorMapper _errorMapper = AppErrorMapper();

  NetworkCancellationToken? _activeCancellationToken;
  var _isDisposed = false;

  @override
  Future<List<int>> build() {
    // Riverpod 在依赖变化时可能保留 Notifier 实例并重新执行 build，因此必须重置上一轮
    // onDispose 设置的标记；否则重建后的 retry 会被误判为销毁后调用。
    _isDisposed = false;
    ref.watch(_reloadSignalProvider);
    ref.onDispose(() {
      _isDisposed = true;
      final cancellationToken = _activeCancellationToken;
      _activeCancellationToken = null;
      cancellationToken?.cancel();
    });
    return _load();
  }

  Future<void> retry() async {
    if (_isDisposed || state.isLoading) {
      return;
    }

    // loading 在调用数据源前同步发布，使同一事件循环中的重复点击也会被上方分支忽略。
    state = const AsyncLoading<List<int>>();
    try {
      final value = await _load();
      if (!_isDisposed) {
        state = AsyncData<List<int>>(value);
      }
    } on Object catch (error, stackTrace) {
      if (!_isDisposed) {
        state = AsyncError<List<int>>(
          _errorMapper.fromUnexpected(error),
          stackTrace,
        );
      }
    }
  }

  Future<List<int>> _load() async {
    final cancellationToken = NetworkCancellationToken();
    _activeCancellationToken = cancellationToken;
    final source = ref.read(_asyncListSourceProvider);
    try {
      return await source.load(cancellationToken);
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(_errorMapper.fromUnexpected(error), stackTrace);
    } finally {
      if (identical(_activeCancellationToken, cancellationToken)) {
        _activeCancellationToken = null;
      }
    }
  }
}

final class _ReloadSignalController extends Notifier<int> {
  @override
  int build() => 0;

  void advance() {
    state++;
  }
}

final class _ControlledAsyncListSource implements _AsyncListSource {
  final List<_PendingListRequest> requests = <_PendingListRequest>[];

  @override
  Future<List<int>> load(NetworkCancellationToken cancellationToken) {
    final request = _PendingListRequest(cancellationToken);
    requests.add(request);
    return request.future;
  }
}

final class _PendingListRequest {
  _PendingListRequest(this.cancellationToken);

  final NetworkCancellationToken cancellationToken;
  final Completer<List<int>> _completer = Completer<List<int>>();

  Future<List<int>> get future => _completer.future;

  void succeed(List<int> value) {
    _completer.complete(List<int>.unmodifiable(value));
  }

  void fail(Object error, StackTrace stackTrace) {
    _completer.completeError(error, stackTrace);
  }
}
