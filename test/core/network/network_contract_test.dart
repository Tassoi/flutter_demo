import 'package:flutter_template/core/network/network_cancellation_token.dart';
import 'package:flutter_template/core/network/network_credential_provider.dart';
import 'package:flutter_template/core/network/network_request.dart';
import 'package:flutter_template/core/network/network_response.dart';
import 'package:flutter_template/core/network/network_timeouts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NetworkRequest', () {
    test('freezes valid request data and keeps toString free of payloads', () {
      final tags = <Object?>['stable'];
      final query = <String, Object?>{'page': 2, 'tags': tags};
      final nested = <String, Object?>{'value': 'private-body-value'};
      final body = <String, Object?>{
        'nested': nested,
        'items': <Object?>[1, true, null],
      };
      final headers = <String, String>{'X-Trace-Mode': 'private-header-value'};

      final request = NetworkRequest(
        operation: 'catalog.load_items',
        method: NetworkMethod.post,
        path: 'v1/catalog/items',
        queryParameters: query,
        headers: headers,
        body: body,
        requiresCredential: true,
      );

      tags.add('changed');
      query['page'] = 9;
      nested['value'] = 'changed';
      headers['X-Trace-Mode'] = 'changed';

      expect(request.queryParameters['page'], 2);
      expect(request.queryParameters['tags'], <Object?>['stable']);
      expect(request.headers, <String, String>{
        'x-trace-mode': 'private-header-value',
      });
      expect(
        (request.body! as Map<String, Object?>)['nested'],
        <String, Object?>{'value': 'private-body-value'},
      );
      expect(() => request.queryParameters['page'] = 3, throwsUnsupportedError);
      expect(
        () => (request.body! as Map<String, Object?>)['new'] = 'value',
        throwsUnsupportedError,
      );

      final rendered = request.toString();
      expect(rendered, contains('catalog.load_items'));
      expect(rendered, isNot(contains('v1/catalog/items')));
      expect(rendered, isNot(contains('private-header-value')));
      expect(rendered, isNot(contains('private-body-value')));
    });

    test('rejects dynamic operation names without echoing input', () {
      const privateOperation = 'User.private-person@example.invalid';

      expect(
        () => NetworkRequest(
          operation: privateOperation,
          method: NetworkMethod.get,
          path: 'items',
        ),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.toString(),
            'message',
            isNot(contains(privateOperation)),
          ),
        ),
      );
    });

    test('rejects absolute, injected, traversing and ambiguous paths', () {
      const invalidPaths = <String>[
        'https://api.example.invalid/private-path',
        '/private-path',
        'items?token=private-query',
        'items#private-fragment',
        'items/../private-path',
        'items/%2e%2e/private-path',
        'items/%252e%252e/private-path',
        r'items\private-path',
        ' items',
        'items/%2Fprivate-path',
      ];

      for (final path in invalidPaths) {
        Object? failure;
        try {
          NetworkRequest(
            operation: 'catalog.load_items',
            method: NetworkMethod.get,
            path: path,
          );
        } on Object catch (error) {
          failure = error;
        }
        expect(failure, isA<ArgumentError>(), reason: path);
        expect(failure.toString(), isNot(contains('private')), reason: path);
      }
    });

    test('rejects credentials and malformed values in query or headers', () {
      final invalidQueryCases = <Map<String, Object?>>[
        <String, Object?>{'token': 'private-query-token'},
        <String, Object?>{'auth_token': 'private-query-token'},
        <String, Object?>{'access_token': 'private-query-token'},
        <String, Object?>{'bad&key': 'private-query-value'},
        <String, Object?>{'filter': DateTime.utc(2026)},
        <String, Object?>{
          'filter': <String, Object?>{'nested': true},
        },
        <String, Object?>{'page': double.nan},
      ];
      for (final query in invalidQueryCases) {
        expect(
          () => NetworkRequest(
            operation: 'catalog.load_items',
            method: NetworkMethod.get,
            path: 'items',
            queryParameters: query,
          ),
          throwsA(isA<ArgumentError>()),
        );
      }

      final invalidHeaderCases = <Map<String, String>>[
        <String, String>{'Authorization': 'Bearer private-token'},
        <String, String>{'X-Auth-Token': 'private-auth-token'},
        <String, String>{'X-API-Key': 'private-api-key'},
        <String, String>{'Content-Length': '123'},
        <String, String>{'X-Trace': 'safe\r\nprivate-injected-header'},
      ];
      for (final headers in invalidHeaderCases) {
        Object? failure;
        try {
          NetworkRequest(
            operation: 'catalog.load_items',
            method: NetworkMethod.get,
            path: 'items',
            headers: headers,
          );
        } on Object catch (error) {
          failure = error;
        }
        expect(failure, isA<ArgumentError>());
        expect(failure.toString(), isNot(contains('private')));
      }
    });

    test('accepts JSON objects and arrays but rejects unsafe bodies', () {
      expect(
        NetworkRequest(
          operation: 'catalog.create_items',
          method: NetworkMethod.post,
          path: 'items',
          body: <Object?>[1, 'two', true, null],
        ).body,
        <Object?>[1, 'two', true, null],
      );

      final cyclic = <Object?>[];
      cyclic.add(cyclic);
      final invalidBodies = <Object?>[
        'raw-body',
        <String, Object?>{'createdAt': DateTime.utc(2026)},
        <Object?, Object?>{1: 'non-string-key'},
        <String, Object?>{'number': double.infinity},
        cyclic,
      ];
      for (final body in invalidBodies) {
        expect(
          () => NetworkRequest(
            operation: 'catalog.create_items',
            method: NetworkMethod.post,
            path: 'items',
            body: body,
          ),
          throwsA(isA<ArgumentError>()),
        );
      }

      expect(
        () => NetworkRequest(
          operation: 'catalog.load_items',
          method: NetworkMethod.get,
          path: 'items',
          body: <String, Object?>{'unexpected': true},
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('maps every supported method to its wire name', () {
      expect(NetworkMethod.values.map((method) => method.wireName), <String>[
        'GET',
        'POST',
        'PUT',
        'PATCH',
        'DELETE',
      ]);
    });
  });

  group('NetworkCredential', () {
    test('normalizes its header and always redacts its value', () {
      final credential = NetworkCredential(
        headerName: 'Authorization',
        headerValue: 'Bearer private-runtime-token',
      );

      expect(credential.headerName, 'authorization');
      expect(credential.headerValue, 'Bearer private-runtime-token');
      expect(credential.toString(), contains('[REDACTED]'));
      expect(credential.toString(), isNot(contains('private-runtime-token')));
    });

    test('rejects unsafe names and values without echoing secrets', () {
      final builders = <NetworkCredential Function()>[
        () => NetworkCredential(
          headerName: 'Cookie',
          headerValue: 'private-cookie',
        ),
        () =>
            NetworkCredential(headerName: 'Content-Length', headerValue: '123'),
        () => NetworkCredential(
          headerName: 'Bad Header private-name',
          headerValue: 'private-value',
        ),
        () => NetworkCredential(
          headerName: 'Authorization',
          headerValue: ' Bearer private-value',
        ),
        () => NetworkCredential(
          headerName: 'Authorization',
          headerValue: 'Bearer private-value\nInjected: private',
        ),
      ];

      for (final build in builders) {
        Object? failure;
        try {
          build();
        } on Object catch (error) {
          failure = error;
        }
        expect(failure, isA<ArgumentError>());
        expect(failure.toString(), isNot(contains('private')));
      }
    });

    test('default provider returns no credential', () async {
      const provider = NoNetworkCredentialProvider();

      expect(await provider.loadCredential(), isNull);
    });
  });

  group('NetworkCancellationToken', () {
    test('notifies once, supports unregister and is idempotent', () {
      final token = NetworkCancellationToken();
      var retainedCalls = 0;
      var removedCalls = 0;
      final unregisterRetained = token.register(() => retainedCalls++);
      final unregisterRemoved = token.register(() => removedCalls++);
      unregisterRemoved();
      unregisterRemoved();

      token.cancel();
      token.cancel();
      unregisterRetained();

      expect(token.isCancelled, isTrue);
      expect(retainedCalls, 1);
      expect(removedCalls, 0);
      expect(token.toString(), isNot(contains('Closure')));
    });

    test('immediately notifies late listeners and isolates failures', () {
      final token = NetworkCancellationToken();
      var secondListenerCalls = 0;
      token.register(() => throw StateError('private-listener-error'));
      token.register(() => secondListenerCalls++);

      expect(token.cancel, returnsNormally);
      expect(secondListenerCalls, 1);

      var lateCalls = 0;
      final unregister = token.register(() => lateCalls++);
      unregister();
      expect(lateCalls, 1);
    });

    test('treats duplicate callback registrations independently', () {
      final token = NetworkCancellationToken();
      var calls = 0;
      void listener() => calls++;
      token.register(listener);
      token.register(listener);

      token.cancel();

      expect(calls, 2);
    });
  });

  group('NetworkTimeouts', () {
    test('provides bounded defaults and accepts positive overrides', () {
      expect(NetworkTimeouts.defaults.connect, const Duration(seconds: 10));
      expect(NetworkTimeouts.defaults.send, const Duration(seconds: 15));
      expect(NetworkTimeouts.defaults.receive, const Duration(seconds: 20));
      expect(NetworkTimeouts.defaults.transform, const Duration(seconds: 5));

      final custom = NetworkTimeouts(
        connect: const Duration(seconds: 1),
        send: const Duration(seconds: 2),
        receive: const Duration(seconds: 3),
        transform: const Duration(seconds: 4),
      );
      expect(custom.connect, const Duration(seconds: 1));
      expect(custom.transform, const Duration(seconds: 4));
    });

    test('rejects zero or negative timeouts', () {
      expect(
        () => NetworkTimeouts(connect: Duration.zero),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => NetworkTimeouts(send: const Duration(microseconds: -1)),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => NetworkTimeouts(receive: Duration.zero),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => NetworkTimeouts(transform: Duration.zero),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('NetworkResponse', () {
    test('keeps payload out of toString and validates status codes', () {
      final response = NetworkResponse<String>(
        statusCode: 200,
        data: 'private-response-payload',
      );

      expect(response.toString(), 'NetworkResponse<String>(statusCode: 200)');
      expect(response.toString(), isNot(contains('private-response-payload')));
      expect(
        () => NetworkResponse<void>(statusCode: 99, data: null),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => NetworkResponse<void>(statusCode: 600, data: null),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
