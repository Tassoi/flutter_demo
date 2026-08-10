import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_template/core/error/app_error.dart';
import 'package:flutter_template/core/logging/app_log_level.dart';
import 'package:flutter_template/core/logging/app_logger.dart';
import 'package:flutter_template/core/logging/package_logging_app_logger.dart';
import 'package:flutter_template/core/network/dio_network_client.dart';
import 'package:flutter_template/core/network/network_cancellation_token.dart';
import 'package:flutter_template/core/network/network_credential_provider.dart';
import 'package:flutter_template/core/network/network_request.dart';
import 'package:flutter_template/core/network/network_timeouts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DioNetworkClient request pipeline', () {
    test(
      'applies base URL, timeouts, headers, JSON body and decoder',
      () async {
        final commonHeaders = <String, String>{'X-App-Version': '0.1.0'};
        final adapter = _FakeHttpClientAdapter((options, _, _) async {
          expect(options.uri.scheme, 'https');
          expect(options.uri.host, 'api.example.invalid');
          expect(options.uri.path, '/api/v1/catalog/items');
          expect(options.method, 'POST');
          expect(options.queryParameters, <String, Object?>{
            'page': 2,
            'tag': <Object?>['stable', 'current'],
          });
          expect(options.headers['accept'], Headers.jsonContentType);
          expect(options.headers['x-app-version'], '0.1.0');
          expect(options.headers['x-trace-mode'], 'safe-trace');
          expect(options.headers['content-type'], Headers.jsonContentType);
          expect(options.data, <String, Object?>{'name': 'example'});
          expect(options.connectTimeout, const Duration(seconds: 1));
          expect(options.sendTimeout, const Duration(seconds: 2));
          expect(options.receiveTimeout, const Duration(seconds: 3));
          expect(options.transformTimeout, const Duration(seconds: 4));
          expect(options.followRedirects, isFalse);
          expect(options.receiveDataWhenStatusError, isFalse);
          return _jsonResponse('{"value":7}', statusCode: 201);
        });
        final logger = _RecordingLogger();
        final client = DioNetworkClient.withHttpClientAdapter(
          baseUri: Uri.parse('https://api.example.invalid/api/v1'),
          logger: logger,
          httpClientAdapter: adapter,
          timeouts: NetworkTimeouts(
            connect: const Duration(seconds: 1),
            send: const Duration(seconds: 2),
            receive: const Duration(seconds: 3),
            transform: const Duration(seconds: 4),
          ),
          commonHeaders: commonHeaders,
        );
        addTearDown(client.close);
        commonHeaders['X-App-Version'] = 'changed-after-construction';

        final response = await client.send<int>(
          NetworkRequest(
            operation: 'catalog.create_item',
            method: NetworkMethod.post,
            path: 'catalog/items',
            queryParameters: <String, Object?>{
              'page': 2,
              'tag': <Object?>['stable', 'current'],
            },
            headers: const <String, String>{'X-Trace-Mode': 'safe-trace'},
            body: const <String, Object?>{'name': 'example'},
          ),
          decoder: (payload) async {
            final json = payload! as Map<String, Object?>;
            return json['value']! as int;
          },
        );

        expect(response.statusCode, 201);
        expect(response.data, 7);
        expect(adapter.fetchCount, 1);
        expect(logger.calls.map((call) => call.event), <String>[
          'network.request_started',
          'network.request_succeeded',
        ]);
      },
    );

    test('keeps non-success response body out of errors and logs', () async {
      const privateBody = '{"password":"private-response-password","broken":';
      var decoderCalls = 0;
      final adapter = _FakeHttpClientAdapter((_, _, _) async {
        return _jsonResponse(privateBody, statusCode: 503);
      });
      final logger = _RecordingLogger();
      final client = _client(adapter: adapter, logger: logger);
      addTearDown(client.close);

      final failure = await _captureFailure(
        client.send<Object?>(
          _getRequest(),
          decoder: (payload) {
            decoderCalls++;
            return payload;
          },
        ),
      );

      expect(failure, isA<NetworkResponseError>());
      expect((failure as NetworkResponseError).statusCode, 503);
      expect(failure.code, 'network.response');
      expect(failure.toString(), isNot(contains(privateBody)));
      expect(decoderCalls, 0);
      expect(logger.serialized, isNot(contains('private-response-password')));
      final failedLog = logger.calls.last;
      expect(failedLog.context['statusCode'], 503);
      expect(failedLog.error, isA<NetworkResponseError>());
    });

    test('maps every Dio timeout category to one stable error', () async {
      const types = <DioExceptionType>[
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
        DioExceptionType.transformTimeout,
      ];

      for (final type in types) {
        final adapter = _FakeHttpClientAdapter((options, _, _) async {
          throw DioException(
            requestOptions: options,
            type: type,
            error: StateError('private-timeout-detail'),
          );
        });
        final logger = _RecordingLogger();
        final client = _client(adapter: adapter, logger: logger);

        final failure = await _captureFailure(
          client.send<Object?>(_getRequest(), decoder: (payload) => payload),
        );

        expect(failure, isA<NetworkTimeoutError>(), reason: type.name);
        expect(failure.toString(), isNot(contains('private-timeout-detail')));
        expect(logger.serialized, isNot(contains('private-timeout-detail')));
        client.close();
      }
    });

    test('maps connection categories and unknown failures precisely', () async {
      const connectionTypes = <DioExceptionType>[
        DioExceptionType.badCertificate,
        DioExceptionType.connectionError,
      ];
      for (final type in connectionTypes) {
        final adapter = _FakeHttpClientAdapter((options, _, _) async {
          throw DioException(requestOptions: options, type: type);
        });
        final client = _client(adapter: adapter, logger: _RecordingLogger());
        final failure = await _captureFailure(
          client.send<Object?>(_getRequest(), decoder: (payload) => payload),
        );
        expect(failure, isA<NetworkConnectionError>(), reason: type.name);
        client.close();
      }

      final unknownAdapter = _FakeHttpClientAdapter((options, _, _) async {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.unknown,
          error: StateError('private-unknown-error'),
        );
      });
      final unknownLogger = _RecordingLogger();
      final unknownClient = _client(
        adapter: unknownAdapter,
        logger: unknownLogger,
      );
      final unknownFailure = await _captureFailure(
        unknownClient.send<Object?>(
          _getRequest(),
          decoder: (payload) => payload,
        ),
      );
      expect(unknownFailure, isA<UnexpectedAppError>());
      expect(
        unknownLogger.serialized,
        isNot(contains('private-unknown-error')),
      );
      unknownClient.close();
    });

    test('maps malformed JSON before invoking the request decoder', () async {
      var decoderCalls = 0;
      final adapter = _FakeHttpClientAdapter((_, _, _) async {
        return _jsonResponse('{"value":private-malformed-json}');
      });
      final logger = _RecordingLogger();
      final client = _client(adapter: adapter, logger: logger);
      addTearDown(client.close);

      final failure = await _captureFailure(
        client.send<Object?>(
          _getRequest(),
          decoder: (payload) {
            decoderCalls++;
            return payload;
          },
        ),
      );

      expect(failure, isA<NetworkResponseParseError>());
      expect(decoderCalls, 0);
      expect(logger.serialized, isNot(contains('private-malformed-json')));
    });

    test(
      'maps decoder failures without logging payload or raw exception',
      () async {
        final adapter = _FakeHttpClientAdapter((_, _, _) async {
          return _jsonResponse('{"value":"private-response-value"}');
        });
        final logger = _RecordingLogger();
        final client = _client(adapter: adapter, logger: logger);
        addTearDown(client.close);

        final failure = await _captureFailure(
          client.send<int>(
            _getRequest(),
            decoder: (_) {
              throw StateError('private-decoder-error');
            },
          ),
        );

        expect(failure, isA<NetworkResponseParseError>());
        expect(logger.serialized, isNot(contains('private-response-value')));
        expect(logger.serialized, isNot(contains('private-decoder-error')));
        expect(logger.calls.last.error, isA<NetworkResponseParseError>());
      },
    );

    test('isolates logger failures from successful requests', () async {
      final adapter = _FakeHttpClientAdapter((_, _, _) async {
        return _jsonResponse('{"value":1}');
      });
      final client = _client(adapter: adapter, logger: _ThrowingLogger());
      addTearDown(client.close);

      final response = await client.send<int>(
        _getRequest(),
        decoder: (payload) {
          return (payload! as Map<String, Object?>)['value']! as int;
        },
      );

      expect(response.data, 1);
    });
  });

  group('DioNetworkClient credential boundary', () {
    test('injects a fresh credential only for protected requests', () async {
      final provider = _StubCredentialProvider(() async {
        return NetworkCredential(
          headerName: 'Authorization',
          headerValue: 'Bearer private-runtime-token',
        );
      });
      final seenAuthorization = <Object?>[];
      final adapter = _FakeHttpClientAdapter((options, _, _) async {
        seenAuthorization.add(options.headers['authorization']);
        return _jsonResponse('{"ok":true}');
      });
      final logger = _RecordingLogger();
      final client = _client(
        adapter: adapter,
        logger: logger,
        credentialProvider: provider,
      );
      addTearDown(client.close);

      await client.send<bool>(
        _getRequest(),
        decoder: (payload) {
          return (payload! as Map<String, Object?>)['ok']! as bool;
        },
      );
      await client.send<bool>(
        NetworkRequest(
          operation: 'catalog.load_private_items',
          method: NetworkMethod.get,
          path: 'private-items',
          requiresCredential: true,
        ),
        decoder: (payload) {
          return (payload! as Map<String, Object?>)['ok']! as bool;
        },
      );

      expect(provider.calls, 1);
      expect(seenAuthorization, <Object?>[
        null,
        'Bearer private-runtime-token',
      ]);
      expect(logger.serialized, isNot(contains('private-runtime-token')));
    });

    test(
      'fails before transport when credentials are missing or fail',
      () async {
        final providers = <_StubCredentialProvider>[
          _StubCredentialProvider(() async => null),
          _StubCredentialProvider(
            () async => throw StateError('private-provider-error'),
          ),
        ];

        for (final provider in providers) {
          final adapter = _FakeHttpClientAdapter((_, _, _) async {
            fail('Transport must not run without a credential.');
          });
          final logger = _RecordingLogger();
          final client = _client(
            adapter: adapter,
            logger: logger,
            credentialProvider: provider,
          );

          final failure = await _captureFailure(
            client.send<Object?>(
              NetworkRequest(
                operation: 'catalog.load_private_items',
                method: NetworkMethod.get,
                path: 'private-items',
                requiresCredential: true,
              ),
              decoder: (payload) => payload,
            ),
          );

          expect(failure, isA<NetworkCredentialsUnavailableError>());
          expect(adapter.fetchCount, 0);
          expect(provider.calls, 1);
          expect(logger.serialized, isNot(contains('private-provider-error')));
          client.close();
        }
      },
    );

    test('never sends a runtime credential over HTTP', () async {
      final provider = _StubCredentialProvider(() async {
        return NetworkCredential(
          headerName: 'Authorization',
          headerValue: 'Bearer private-runtime-token',
        );
      });
      final adapter = _FakeHttpClientAdapter((_, _, _) async {
        fail('Insecure transport must not receive a protected request.');
      });
      final client = DioNetworkClient.withHttpClientAdapter(
        baseUri: Uri.parse('http://localhost:8080/api/'),
        logger: _RecordingLogger(),
        httpClientAdapter: adapter,
        credentialProvider: provider,
      );
      addTearDown(client.close);

      final failure = await _captureFailure(
        client.send<Object?>(
          NetworkRequest(
            operation: 'catalog.load_private_items',
            method: NetworkMethod.get,
            path: 'private-items',
            requiresCredential: true,
          ),
          decoder: (payload) => payload,
        ),
      );

      expect(failure, isA<NetworkCredentialsUnavailableError>());
      expect(provider.calls, 0);
      expect(adapter.fetchCount, 0);
    });

    test(
      'cancellation completes while the credential provider stays pending',
      () async {
        final providerStarted = Completer<void>();
        final pendingCredential = Completer<NetworkCredential?>();
        final provider = _StubCredentialProvider(() {
          providerStarted.complete();
          return pendingCredential.future;
        });
        final adapter = _FakeHttpClientAdapter((_, _, _) async {
          fail('A cancelled credential lookup must not reach transport.');
        });
        final client = _client(
          adapter: adapter,
          logger: _RecordingLogger(),
          credentialProvider: provider,
        );
        addTearDown(client.close);
        final token = NetworkCancellationToken();

        final requestFuture = client.send<Object?>(
          NetworkRequest(
            operation: 'catalog.load_private_items',
            method: NetworkMethod.get,
            path: 'private-items',
            requiresCredential: true,
          ),
          decoder: (payload) => payload,
          cancellationToken: token,
        );
        await providerStarted.future;
        token.cancel();

        expect(
          await _captureFailure(requestFuture),
          isA<NetworkCancelledError>(),
        );
        expect(provider.calls, 1);
        expect(adapter.fetchCount, 0);
      },
    );

    test(
      'late credential completion after cancellation never reaches transport',
      () async {
        final providerStarted = Completer<void>();
        final pendingCredential = Completer<NetworkCredential?>();
        final provider = _StubCredentialProvider(() {
          providerStarted.complete();
          return pendingCredential.future;
        });
        final adapter = _FakeHttpClientAdapter((_, _, _) async {
          fail('A cancelled credential lookup must not reach transport.');
        });
        final client = _client(
          adapter: adapter,
          logger: _RecordingLogger(),
          credentialProvider: provider,
        );
        addTearDown(client.close);
        final token = NetworkCancellationToken();

        final requestFuture = client.send<Object?>(
          NetworkRequest(
            operation: 'catalog.load_private_items',
            method: NetworkMethod.get,
            path: 'private-items',
            requiresCredential: true,
          ),
          decoder: (payload) => payload,
          cancellationToken: token,
        );
        await providerStarted.future;
        token.cancel();
        pendingCredential.complete(
          NetworkCredential(
            headerName: 'Authorization',
            headerValue: 'Bearer private-late-token',
          ),
        );

        expect(
          await _captureFailure(requestFuture),
          isA<NetworkCancelledError>(),
        );
        expect(adapter.fetchCount, 0);
      },
    );
  });

  group('DioNetworkClient cancellation and lifecycle', () {
    test(
      'maps a token cancelled before send without reaching transport',
      () async {
        final token = NetworkCancellationToken()..cancel();
        final adapter = _FakeHttpClientAdapter((_, _, _) async {
          fail('A pre-cancelled request must not reach transport.');
        });
        final client = _client(adapter: adapter, logger: _RecordingLogger());
        addTearDown(client.close);

        final failure = await _captureFailure(
          client.send<Object?>(
            _getRequest(),
            decoder: (payload) => payload,
            cancellationToken: token,
          ),
        );

        expect(failure, isA<NetworkCancelledError>());
        expect(adapter.fetchCount, 0);
      },
    );

    test('cancels an in-flight adapter without using delays', () async {
      final started = Completer<void>();
      final cancellationReachedAdapter = Completer<void>();
      final pendingResponse = Completer<ResponseBody>();
      final adapter = _FakeHttpClientAdapter((_, _, cancelFuture) {
        cancelFuture!.then((_) {
          if (!cancellationReachedAdapter.isCompleted) {
            cancellationReachedAdapter.complete();
          }
        });
        started.complete();
        return pendingResponse.future;
      });
      final logger = _RecordingLogger();
      final client = _client(adapter: adapter, logger: logger);
      addTearDown(client.close);
      final token = NetworkCancellationToken();

      final requestFuture = client.send<Object?>(
        _getRequest(),
        decoder: (payload) => payload,
        cancellationToken: token,
      );
      await started.future;
      token.cancel();
      final failure = await _captureFailure(requestFuture);
      await cancellationReachedAdapter.future;

      expect(failure, isA<NetworkCancelledError>());
      expect(logger.calls.last.level, AppLogLevel.info);
      expect(logger.calls.last.context['errorCode'], 'network.cancelled');
    });

    test('one project token cancels multiple concurrent requests', () async {
      final bothStarted = Completer<void>();
      late final _FakeHttpClientAdapter adapter;
      adapter = _FakeHttpClientAdapter((_, _, _) {
        if (adapter.fetchCount == 2 && !bothStarted.isCompleted) {
          bothStarted.complete();
        }
        return Completer<ResponseBody>().future;
      });
      final client = DioNetworkClient.withHttpClientAdapter(
        baseUri: Uri.parse('https://api.example.invalid/api/'),
        logger: _RecordingLogger(),
        httpClientAdapter: adapter,
      );
      addTearDown(client.close);
      final token = NetworkCancellationToken();

      final first = client.send<Object?>(
        _getRequest(),
        decoder: (payload) => payload,
        cancellationToken: token,
      );
      final second = client.send<Object?>(
        NetworkRequest(
          operation: 'catalog.load_more_items',
          method: NetworkMethod.get,
          path: 'more-items',
        ),
        decoder: (payload) => payload,
        cancellationToken: token,
      );
      await bothStarted.future;
      token.cancel();

      final failures = await Future.wait<Object>([
        _captureFailure(first),
        _captureFailure(second),
      ]);
      expect(failures, everyElement(isA<NetworkCancelledError>()));
    });

    test('honors cancellation that occurs during an async decoder', () async {
      final decoderStarted = Completer<void>();
      final finishDecoder = Completer<void>();
      final decoderFinished = Completer<void>();
      final adapter = _FakeHttpClientAdapter((_, _, _) async {
        return _jsonResponse('{"value":1}');
      });
      final client = _client(adapter: adapter, logger: _RecordingLogger());
      addTearDown(client.close);
      final token = NetworkCancellationToken();

      final requestFuture = client.send<int>(
        _getRequest(),
        decoder: (payload) async {
          decoderStarted.complete();
          await finishDecoder.future;
          decoderFinished.complete();
          return (payload! as Map<String, Object?>)['value']! as int;
        },
        cancellationToken: token,
      );
      await decoderStarted.future;
      token.cancel();

      expect(
        await _captureFailure(requestFuture),
        isA<NetworkCancelledError>(),
      );
      finishDecoder.complete();
      await decoderFinished.future;
    });

    test(
      'close cancels active work, is idempotent and rejects later sends',
      () async {
        final started = Completer<void>();
        final pendingResponse = Completer<ResponseBody>();
        final adapter = _FakeHttpClientAdapter((_, _, _) {
          started.complete();
          return pendingResponse.future;
        });
        final client = _client(adapter: adapter, logger: _RecordingLogger());

        final requestFuture = client.send<Object?>(
          _getRequest(),
          decoder: (payload) => payload,
        );
        await started.future;
        client.close();
        client.close();

        expect(
          await _captureFailure(requestFuture),
          isA<NetworkCancelledError>(),
        );
        expect(adapter.closeCount, 1);
        expect(adapter.lastCloseWasForced, isTrue);
        await expectLater(
          client.send<Object?>(_getRequest(), decoder: (payload) => payload),
          throwsA(isA<StateError>()),
        );
      },
    );
  });

  group('DioNetworkClient privacy and configuration', () {
    test(
      'real structured logger never receives request or response secrets',
      () async {
        final sink = _MemoryLogSink();
        final logger = PackageLoggingAppLogger(
          category: 'network.test',
          minimumLevel: AppLogLevel.debug,
          sink: sink,
          now: () => DateTime.utc(2026, 8, 9),
        );
        final provider = _StubCredentialProvider(() async {
          return NetworkCredential(
            headerName: 'Authorization',
            headerValue: 'Bearer private-runtime-token',
          );
        });
        final adapter = _FakeHttpClientAdapter((options, _, _) async {
          expect(
            options.headers['authorization'],
            'Bearer private-runtime-token',
          );
          return _jsonResponse('{"result":"private-response-value"}');
        });
        final client = DioNetworkClient.withHttpClientAdapter(
          baseUri: Uri.parse(
            'https://api.example.invalid/private-base-segment/',
          ),
          logger: logger,
          httpClientAdapter: adapter,
          credentialProvider: provider,
        );
        addTearDown(() async {
          client.close();
          await logger.close();
        });

        final response = await client.send<String>(
          NetworkRequest(
            operation: 'profile.load_summary',
            method: NetworkMethod.post,
            path: 'private-path-segment',
            queryParameters: const <String, Object?>{
              'search': 'private-query-value',
            },
            headers: const <String, String>{
              'X-Trace-Mode': 'private-header-value',
            },
            body: const <String, Object?>{'payload': 'private-body-value'},
            requiresCredential: true,
          ),
          decoder: (payload) {
            return (payload! as Map<String, Object?>)['result']! as String;
          },
        );

        expect(response.data, 'private-response-value');
        expect(sink.records.map((record) => record.event), <String>[
          'network.request_started',
          'network.request_succeeded',
        ]);
        final serialized = jsonEncode(
          sink.records.map((record) => record.toJson()).toList(),
        );
        for (final secret in <String>[
          'private-runtime-token',
          'private-base-segment',
          'private-path-segment',
          'private-query-value',
          'private-header-value',
          'private-body-value',
          'private-response-value',
        ]) {
          expect(serialized, isNot(contains(secret)));
        }
      },
    );

    test('rejects unsafe base URI and common headers without echoing data', () {
      final adapter = _FakeHttpClientAdapter((_, _, _) async {
        return _jsonResponse('{}');
      });
      final logger = _RecordingLogger();

      Object? uriFailure;
      try {
        DioNetworkClient.withHttpClientAdapter(
          baseUri: Uri.parse(
            'https://person:private-password@api.example.invalid/',
          ),
          logger: logger,
          httpClientAdapter: adapter,
        );
      } on Object catch (error) {
        uriFailure = error;
      }
      expect(uriFailure, isA<ArgumentError>());
      expect(uriFailure.toString(), isNot(contains('private-password')));

      expect(
        () => DioNetworkClient.withHttpClientAdapter(
          baseUri: Uri.parse(
            'https://api.example.invalid/base/%252e%252e/private-path/',
          ),
          logger: logger,
          httpClientAdapter: adapter,
        ),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.toString(),
            'message',
            isNot(contains('private-path')),
          ),
        ),
      );

      Object? headerFailure;
      try {
        DioNetworkClient.withHttpClientAdapter(
          baseUri: Uri.parse('https://api.example.invalid/'),
          logger: logger,
          httpClientAdapter: adapter,
          commonHeaders: const <String, String>{
            'Authorization': 'Bearer private-common-token',
          },
        );
      } on Object catch (error) {
        headerFailure = error;
      }
      expect(headerFailure, isA<ArgumentError>());
      expect(headerFailure.toString(), isNot(contains('private-common-token')));
      expect(
        () => DioNetworkClient.withHttpClientAdapter(
          baseUri: Uri.parse('https://api.example.invalid/'),
          logger: logger,
          httpClientAdapter: adapter,
          commonHeaders: const <String, String>{
            'X-Auth-Token': 'private-common-auth-token',
          },
        ),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.toString(),
            'message',
            isNot(contains('private-common-auth-token')),
          ),
        ),
      );
    });
  });
}

DioNetworkClient _client({
  required _FakeHttpClientAdapter adapter,
  required AppLogger logger,
  NetworkCredentialProvider credentialProvider =
      const NoNetworkCredentialProvider(),
}) {
  return DioNetworkClient.withHttpClientAdapter(
    baseUri: Uri.parse('https://api.example.invalid/api/'),
    logger: logger,
    httpClientAdapter: adapter,
    credentialProvider: credentialProvider,
  );
}

NetworkRequest _getRequest() {
  return NetworkRequest(
    operation: 'catalog.load_items',
    method: NetworkMethod.get,
    path: 'items',
  );
}

ResponseBody _jsonResponse(String body, {int statusCode = 200}) {
  return ResponseBody.fromString(
    body,
    statusCode,
    headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
    },
  );
}

Future<Object> _captureFailure(Future<Object?> future) async {
  try {
    await future;
  } on Object catch (error) {
    return error;
  }
  fail('Expected the Future to fail.');
}

typedef _FetchHandler =
    Future<ResponseBody> Function(
      RequestOptions options,
      Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture,
    );

final class _FakeHttpClientAdapter implements HttpClientAdapter {
  _FakeHttpClientAdapter(this._handler);

  final _FetchHandler _handler;
  int fetchCount = 0;
  int closeCount = 0;
  bool? lastCloseWasForced;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    fetchCount++;
    return _handler(options, requestStream, cancelFuture);
  }

  @override
  void close({bool force = false}) {
    closeCount++;
    lastCloseWasForced = force;
  }
}

final class _StubCredentialProvider implements NetworkCredentialProvider {
  _StubCredentialProvider(this._load);

  final Future<NetworkCredential?> Function() _load;
  int calls = 0;

  @override
  Future<NetworkCredential?> loadCredential() {
    calls++;
    return _load();
  }
}

final class _LogCall {
  const _LogCall({
    required this.level,
    required this.event,
    required this.message,
    required this.context,
    required this.error,
  });

  final AppLogLevel level;
  final String event;
  final String message;
  final Map<String, Object?> context;
  final Object? error;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'level': level.name,
      'event': event,
      'message': message,
      'context': context,
      'error': error?.toString(),
    };
  }
}

final class _RecordingLogger implements AppLogger {
  final List<_LogCall> calls = <_LogCall>[];
  bool _isClosed = false;

  @override
  AppLogLevel get minimumLevel => AppLogLevel.debug;

  String get serialized =>
      jsonEncode(calls.map((call) => call.toJson()).toList(growable: false));

  @override
  void log(
    AppLogLevel level, {
    required String event,
    String message = '',
    Map<String, Object?> context = const {},
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (_isClosed) {
      throw StateError('Logger is closed.');
    }
    calls.add(
      _LogCall(
        level: level,
        event: event,
        message: message,
        context: Map<String, Object?>.unmodifiable(context),
        error: error,
      ),
    );
  }

  @override
  Future<void> close() async {
    _isClosed = true;
  }
}

final class _ThrowingLogger implements AppLogger {
  @override
  AppLogLevel get minimumLevel => AppLogLevel.debug;

  @override
  void log(
    AppLogLevel level, {
    required String event,
    String message = '',
    Map<String, Object?> context = const {},
    Object? error,
    StackTrace? stackTrace,
  }) {
    throw StateError('private-logger-failure');
  }

  @override
  Future<void> close() async {}
}

final class _MemoryLogSink implements AppLogSink {
  final List<AppLogRecord> records = <AppLogRecord>[];

  @override
  void write(AppLogRecord record) {
    records.add(record);
  }
}
