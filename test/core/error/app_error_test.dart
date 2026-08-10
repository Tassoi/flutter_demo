import 'package:flutter_template/core/error/app_error.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const mapper = AppErrorMapper();

  group('AppErrorMapper', () {
    test('maps malformed configuration without retaining raw details', () {
      final rawError = FormatException(
        'Authorization: Bearer private-token-placeholder',
      );

      final mapped = mapper.fromConfiguration(rawError);

      expect(mapped, isA<AppConfigurationError>());
      expect(mapped.code, 'configuration.invalid');
      expect(
        mapped.displayMessage,
        'The application configuration is invalid.',
      );
      expect(
        mapped.toString(),
        'AppConfigurationError(code: configuration.invalid)',
      );
      expect(mapped.toString(), isNot(contains('private-token-placeholder')));
      expect(
        mapped.displayMessage,
        isNot(contains('private-token-placeholder')),
      );
    });

    test('maps an unknown configuration failure to unavailable', () {
      final mapped = mapper.fromConfiguration(StateError('disk failure'));

      expect(mapped, isA<AppConfigurationError>());
      expect(mapped.code, 'configuration.unavailable');
    });

    test('keeps an existing stable error instance', () {
      const existing = UnexpectedAppError();

      expect(mapper.fromConfiguration(existing), same(existing));
      expect(mapper.fromUnexpected(existing), same(existing));
    });

    test('does not infer configuration semantics without that boundary', () {
      expect(
        mapper.fromUnexpected(const FormatException('malformed dependency')),
        isA<UnexpectedAppError>(),
      );
    });
  });

  group('network errors', () {
    test('expose stable codes without retaining transport details', () {
      final errors = <AppError>[
        const NetworkConnectionError(),
        const NetworkTimeoutError(),
        const NetworkCancelledError(),
        NetworkResponseError(statusCode: 503),
        const NetworkResponseParseError(),
        const NetworkCredentialsUnavailableError(),
      ];

      expect(errors.map((error) => error.code), <String>[
        'network.connection',
        'network.timeout',
        'network.cancelled',
        'network.response',
        'network.parse',
        'network.credentials_unavailable',
      ]);
      for (final error in errors) {
        expect(error.toString(), isNot(contains('private-transport-detail')));
        expect(
          error.displayMessage,
          isNot(contains('private-transport-detail')),
        );
      }
    });

    test('response error retains only a validated status code', () {
      final error = NetworkResponseError(statusCode: 429);

      expect(error.statusCode, 429);
      expect(error.toString(), 'NetworkResponseError(code: network.response)');
      expect(
        () => NetworkResponseError(statusCode: 99),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => NetworkResponseError(statusCode: 600),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('storage errors', () {
    test('expose operation codes without retaining keys or values', () {
      final errors = <AppError>[
        const StorageInitializationError(),
        const StorageReadError(),
        const StorageWriteError(),
        const StorageDeleteError(),
        const StorageClearError(),
      ];

      expect(errors.map((error) => error.code), <String>[
        'storage.initialization',
        'storage.read',
        'storage.write',
        'storage.delete',
        'storage.clear',
      ]);
      for (final error in errors) {
        expect(error.toString(), isNot(contains('private-storage-value')));
        expect(error.displayMessage, isNot(contains('private-storage-value')));
      }
    });
  });
}
