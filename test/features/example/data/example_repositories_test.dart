import 'package:flutter_template/core/error/app_error.dart';
import 'package:flutter_template/core/network/network_cancellation_token.dart';
import 'package:flutter_template/core/network/network_client.dart';
import 'package:flutter_template/core/network/network_request.dart';
import 'package:flutter_template/core/network/network_response.dart';
import 'package:flutter_template/features/example/data/bundled_example_repository.dart';
import 'package:flutter_template/features/example/data/network_example_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BundledExampleRepository', () {
    test('returns one deterministic item without external state', () async {
      final repository = BundledExampleRepository();

      final item = await repository.loadItem(
        itemId: 1,
        cancellationToken: NetworkCancellationToken(),
      );
      final missing = await repository.loadItem(
        itemId: 2,
        cancellationToken: NetworkCancellationToken(),
      );

      expect(item?.id, 1);
      expect(item?.title, isNotEmpty);
      expect(missing, isNull);
    });

    test('honors cancellation before resolving bundled data', () async {
      final cancellationToken = NetworkCancellationToken()..cancel();

      await expectLater(
        BundledExampleRepository().loadItem(
          itemId: 1,
          cancellationToken: cancellationToken,
        ),
        throwsA(isA<NetworkCancelledError>()),
      );
    });

    test('rejects a non-positive item identifier before lookup', () async {
      await expectLater(
        BundledExampleRepository().loadItem(
          itemId: 0,
          cancellationToken: NetworkCancellationToken(),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('NetworkExampleRepository', () {
    test('builds a public request and decodes a matching item', () async {
      final networkClient = _StubNetworkClient(
        payload: <String, Object?>{
          'id': 7,
          'title': '  Example record  ',
          'description': '  A neutral description.  ',
        },
      );
      final repository = NetworkExampleRepository(networkClient: networkClient);
      final cancellationToken = NetworkCancellationToken();

      final item = await repository.loadItem(
        itemId: 7,
        cancellationToken: cancellationToken,
      );

      expect(item?.id, 7);
      expect(item?.title, 'Example record');
      expect(item?.description, 'A neutral description.');
      expect(networkClient.requests, hasLength(1));
      final request = networkClient.requests.single;
      expect(request.operation, 'example.load_item');
      expect(request.method, NetworkMethod.get);
      expect(request.path, 'examples/7');
      expect(request.queryParameters, isEmpty);
      expect(request.headers, isEmpty);
      expect(request.body, isNull);
      expect(request.requiresCredential, isFalse);
      expect(networkClient.cancellationTokens.single, same(cancellationToken));
      expect(networkClient.closeCount, 0);
    });

    test('treats a null response payload as successful empty data', () async {
      final repository = NetworkExampleRepository(
        networkClient: _StubNetworkClient(payload: null),
      );

      final item = await repository.loadItem(
        itemId: 8,
        cancellationToken: NetworkCancellationToken(),
      );

      expect(item, isNull);
    });

    test(
      'maps malformed and mismatched payloads to a stable parse error',
      () async {
        for (final payload in <Object?>[
          const <Object?>[],
          <String, Object?>{'id': 9},
          <String, Object?>{
            'id': 10,
            'title': 'Wrong item',
            'description': 'The identifier does not match.',
          },
          <String, Object?>{
            'id': 9,
            'title': ' ',
            'description': 'private-response-description-token',
          },
        ]) {
          final repository = NetworkExampleRepository(
            networkClient: _StubNetworkClient(payload: payload),
          );

          await expectLater(
            repository.loadItem(
              itemId: 9,
              cancellationToken: NetworkCancellationToken(),
            ),
            throwsA(
              isA<NetworkResponseParseError>().having(
                (error) => error.toString(),
                'safe diagnostic text',
                isNot(contains('private-response-description-token')),
              ),
            ),
          );
        }
      },
    );

    test('preserves stable transport errors and rejects invalid IDs', () async {
      const failure = NetworkConnectionError();
      final networkClient = _StubNetworkClient(failure: failure);
      final repository = NetworkExampleRepository(networkClient: networkClient);

      await expectLater(
        repository.loadItem(
          itemId: 4,
          cancellationToken: NetworkCancellationToken(),
        ),
        throwsA(same(failure)),
      );
      await expectLater(
        repository.loadItem(
          itemId: 0,
          cancellationToken: NetworkCancellationToken(),
        ),
        throwsArgumentError,
      );
      expect(networkClient.requests, hasLength(1));
    });
  });
}

final class _StubNetworkClient implements NetworkClient {
  _StubNetworkClient({this.payload, this.failure});

  final Object? payload;
  final AppError? failure;
  final List<NetworkRequest> requests = <NetworkRequest>[];
  final List<NetworkCancellationToken?> cancellationTokens =
      <NetworkCancellationToken?>[];
  var closeCount = 0;
  var _isClosed = false;

  @override
  Future<NetworkResponse<T>> send<T>(
    NetworkRequest request, {
    required NetworkResponseDecoder<T> decoder,
    NetworkCancellationToken? cancellationToken,
  }) async {
    if (_isClosed) {
      throw StateError('The test network client is closed.');
    }
    requests.add(request);
    cancellationTokens.add(cancellationToken);
    final currentFailure = failure;
    if (currentFailure != null) {
      throw currentFailure;
    }

    try {
      final data = await decoder(payload);
      return NetworkResponse<T>(statusCode: 200, data: data);
    } on AppError {
      rethrow;
    } on Object catch (_, stackTrace) {
      Error.throwWithStackTrace(const NetworkResponseParseError(), stackTrace);
    }
  }

  @override
  void close() {
    closeCount++;
    _isClosed = true;
  }
}
