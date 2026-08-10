import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_template/core/error/app_error.dart';
import 'package:flutter_template/features/example/domain/example_item.dart';
import 'package:flutter_template/features/example/presentation/example_detail_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/features/example/controlled_example_repository.dart';
import '../../../support/features/example/example_item_fixture.dart';
import '../../../support/state/create_test_provider_container.dart';

void main() {
  test('loads one item and exposes the family route argument', () async {
    final repository = ControlledExampleRepository();
    final container = _createContainer(repository);
    final provider = exampleDetailProvider(7);
    final states = <AsyncValue<ExampleItem?>>[];
    final subscription = container.listen<AsyncValue<ExampleItem?>>(
      provider,
      (_, next) => states.add(next),
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    expect(states.single.isLoading, isTrue);
    expect(repository.requests.single.itemId, 7);

    repository.requests.single.succeed(
      createExampleItemFixture(id: 7, description: 'Description'),
    );
    final item = await container.read(provider.future);

    expect(item?.id, 7);
    expect(container.read(provider).valueOrNull?.title, 'Example record');
  });

  test('keeps a missing item as successful empty data', () async {
    final repository = ControlledExampleRepository();
    final container = _createContainer(repository);
    final provider = exampleDetailProvider(8);
    final subscription = container.listen<AsyncValue<ExampleItem?>>(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    repository.requests.single.succeed(null);
    expect(await container.read(provider.future), isNull);

    final state = container.read(provider);
    expect(state.hasValue, isTrue);
    expect(state.hasError, isFalse);
    expect(state.valueOrNull, isNull);
  });

  test('maps private failures and allows only one active retry', () async {
    final repository = ControlledExampleRepository();
    final container = _createContainer(repository);
    final provider = exampleDetailProvider(9);
    final subscription = container.listen<AsyncValue<ExampleItem?>>(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    final initialResult = container.read(provider.future);
    final initialExpectation = expectLater(
      initialResult,
      throwsA(isA<UnexpectedAppError>()),
    );

    repository.requests.single.fail(
      StateError('private-repository-token'),
      StackTrace.current,
    );
    await initialExpectation;

    final failedState = container.read(provider);
    expect(failedState.error, isA<UnexpectedAppError>());
    expect(
      failedState.error.toString(),
      isNot(contains('private-repository-token')),
    );

    final controller = container.read(provider.notifier);
    final retry = controller.retry();
    final duplicateRetry = controller.retry();
    await duplicateRetry;

    expect(container.read(provider).isLoading, isTrue);
    expect(repository.requests, hasLength(2));

    repository.requests.last.succeed(
      createExampleItemFixture(
        id: 9,
        title: 'Recovered',
        description: 'Available again',
      ),
    );
    await retry;

    expect(container.read(provider).valueOrNull?.title, 'Recovered');
  });

  test('maps a retry failure and remains available for recovery', () async {
    final repository = ControlledExampleRepository();
    final container = _createContainer(repository);
    final provider = exampleDetailProvider(14);
    final subscription = container.listen<AsyncValue<ExampleItem?>>(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    repository.requests.single.succeed(createExampleItemFixture(id: 14));
    await container.read(provider.future);
    final controller = container.read(provider.notifier);

    final failedRetry = controller.retry();
    repository.requests.last.fail(
      StateError('private-retry-token'),
      StackTrace.current,
    );
    await failedRetry;

    final failedState = container.read(provider);
    expect(failedState.error, isA<UnexpectedAppError>());
    expect(
      failedState.error.toString(),
      isNot(contains('private-retry-token')),
    );

    final recovery = controller.retry();
    expect(repository.requests, hasLength(3));
    repository.requests.last.succeed(
      createExampleItemFixture(id: 14, title: 'Recovered again'),
    );
    await recovery;

    expect(container.read(provider).valueOrNull?.title, 'Recovered again');
  });

  test('preserves a stable application error from the repository', () async {
    final repository = ControlledExampleRepository();
    final container = _createContainer(repository);
    final provider = exampleDetailProvider(13);
    final subscription = container.listen<AsyncValue<ExampleItem?>>(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    const failure = NetworkTimeoutError();
    final result = container.read(provider.future);

    repository.requests.single.fail(failure, StackTrace.current);

    await expectLater(result, throwsA(same(failure)));
    expect(container.read(provider).error, same(failure));
  });

  test('auto dispose cancels work and late data cannot revive state', () async {
    final repository = ControlledExampleRepository();
    final container = _createContainer(repository);
    final provider = exampleDetailProvider(10);
    final subscription = container.listen<AsyncValue<ExampleItem?>>(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    final staleRequest = repository.requests.single;

    subscription.close();
    await container.pump();

    expect(staleRequest.cancellationToken.isCancelled, isTrue);
    staleRequest.succeed(
      createExampleItemFixture(
        id: 10,
        title: 'Stale',
        description: 'Late data',
      ),
    );
    await container.pump();

    final replacementSubscription = container.listen<AsyncValue<ExampleItem?>>(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(replacementSubscription.close);
    expect(repository.requests, hasLength(2));
    expect(container.read(provider).isLoading, isTrue);

    repository.requests.last.succeed(null);
    expect(await container.read(provider.future), isNull);
  });

  test('maps a missing application override to a stable error', () async {
    final container = createTestProviderContainer();
    final provider = exampleDetailProvider(11);
    final subscription = container.listen<AsyncValue<ExampleItem?>>(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    await expectLater(
      container.read(provider.future),
      throwsA(isA<UnexpectedAppError>()),
    );

    final state = container.read(provider);
    expect(state.error, isA<UnexpectedAppError>());
    expect(state.error.toString(), isNot(contains('must be overridden')));
  });

  test(
    'rejects a non-positive family argument before repository access',
    () async {
      final repository = ControlledExampleRepository();
      final container = _createContainer(repository);
      final provider = exampleDetailProvider(0);
      final subscription = container.listen<AsyncValue<ExampleItem?>>(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      await expectLater(
        container.read(provider.future),
        throwsA(isA<UnexpectedAppError>()),
      );

      expect(repository.requests, isEmpty);
      expect(
        container.read(provider).error.toString(),
        isNot(contains('must be positive')),
      );
    },
  );

  test(
    'dependency rebuild cancels stale work and ignores its late failure',
    () async {
      final repository = ControlledExampleRepository();
      final container = _createContainer(repository);
      final provider = exampleDetailProvider(12);
      final subscription = container.listen<AsyncValue<ExampleItem?>>(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      final staleRequest = repository.requests.single;

      container.invalidate(exampleRepositoryProvider);
      await container.pump();

      expect(staleRequest.cancellationToken.isCancelled, isTrue);
      expect(repository.requests, hasLength(2));
      final replacementRequest = repository.requests.last;
      replacementRequest.succeed(
        createExampleItemFixture(
          id: 12,
          title: 'Current',
          description: 'Replacement data',
        ),
      );
      expect((await container.read(provider.future))?.title, 'Current');

      staleRequest.fail(
        StateError('private-stale-repository-token'),
        StackTrace.current,
      );
      await container.pump();

      expect(container.read(provider).valueOrNull?.title, 'Current');
    },
  );
}

ProviderContainer _createContainer(ControlledExampleRepository repository) {
  return createTestProviderContainer(
    overrides: <Override>[
      exampleRepositoryProvider.overrideWithValue(repository),
    ],
  );
}
