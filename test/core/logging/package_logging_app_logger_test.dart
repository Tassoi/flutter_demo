import 'dart:convert';

import 'package:flutter_template/core/logging/app_log_level.dart';
import 'package:flutter_template/core/logging/app_logger.dart';
import 'package:flutter_template/core/logging/console_log_sink.dart';
import 'package:flutter_template/core/logging/log_redactor.dart';
import 'package:flutter_template/core/logging/package_logging_app_logger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PackageLoggingAppLogger', () {
    test('writes deterministic structured and redacted records', () async {
      final sink = _MemoryLogSink();
      final logger = PackageLoggingAppLogger(
        category: 'app.test',
        minimumLevel: AppLogLevel.debug,
        sink: sink,
        now: () => DateTime.parse('2026-08-09T10:20:30+08:00'),
      );
      addTearDown(logger.close);
      final error = StateError(
        'Authorization: Bearer private-error-token\n'
        'email=person@example.invalid',
      );
      final stackTrace = StackTrace.fromString(
        'password=private-stack-password at package:test/file.dart',
      );

      logger.log(
        AppLogLevel.error,
        event: 'test.operation_failed',
        message: 'Request for person@example.invalid failed.',
        context: <String, Object?>{
          'authorization': 'Bearer private-context-token',
          'nested': <String, Object?>{
            'password': 'private-context-password',
            'attempt': 2,
          },
        },
        error: error,
        stackTrace: stackTrace,
      );

      final record = sink.records.single;
      expect(record.timestamp, DateTime.utc(2026, 8, 9, 2, 20, 30));
      expect(record.level, AppLogLevel.error);
      expect(record.category, 'app.test');
      expect(record.event, 'test.operation_failed');
      expect(record.message, 'Request for [REDACTED_EMAIL] failed.');
      expect(record.context['authorization'], LogRedactor.redactedValue);
      expect(
        (record.context['nested']! as Map<String, Object?>)['password'],
        LogRedactor.redactedValue,
      );
      expect(record.errorType, 'StateError');
      expect(record.errorMessage, isNot(contains('private-error-token')));
      expect(record.errorMessage, isNot(contains('person@example.invalid')));
      expect(record.stackTrace, isNot(contains('private-stack-password')));

      final serialized = jsonEncode(record.toJson());
      for (final secret in [
        'private-context-token',
        'private-context-password',
        'private-error-token',
        'private-stack-password',
        'person@example.invalid',
      ]) {
        expect(serialized, isNot(contains(secret)));
      }
    });

    test('filters below-threshold events before evaluating errors', () async {
      final sink = _MemoryLogSink();
      final logger = PackageLoggingAppLogger(
        category: 'app.threshold',
        minimumLevel: AppLogLevel.warning,
        sink: sink,
      );
      addTearDown(logger.close);
      final error = _CountingError();

      logger.log(AppLogLevel.debug, event: 'test.debug_event', error: error);
      logger.log(AppLogLevel.info, event: 'test.info_event', error: error);
      logger.log(AppLogLevel.warning, event: 'test.warning_event');
      logger.log(AppLogLevel.error, event: 'test.error_event');

      expect(error.toStringCalls, 0);
      expect(sink.records.map((record) => record.event), [
        'test.warning_event',
        'test.error_event',
      ]);
    });

    test('production policy omits raw error and stack details', () async {
      final sink = _MemoryLogSink();
      final logger = PackageLoggingAppLogger(
        category: 'app.production',
        minimumLevel: AppLogLevel.warning,
        sink: sink,
        includeErrorMessage: false,
        includeStackTrace: false,
      );
      addTearDown(logger.close);

      logger.log(
        AppLogLevel.error,
        event: 'test.production_failure',
        error: StateError('private-production-error'),
        stackTrace: StackTrace.fromString('private-production-stack'),
      );

      final record = sink.records.single;
      expect(record.errorType, 'StateError');
      expect(record.errorMessage, isNull);
      expect(record.stackTrace, isNull);
      expect(record.toString(), isNot(contains('private-production-error')));
      expect(record.toString(), isNot(contains('private-production-stack')));
    });

    test('isolates sink and fallback writer failures', () async {
      final fallbackMessages = <String>[];
      final logger = PackageLoggingAppLogger(
        category: 'app.failure',
        minimumLevel: AppLogLevel.debug,
        sink: _ThrowingLogSink(),
        writeFallback: (message) {
          fallbackMessages.add(message);
          throw StateError('private-fallback-error');
        },
      );
      addTearDown(logger.close);

      expect(
        () => logger.log(
          AppLogLevel.error,
          event: 'test.sink_failure',
          message: 'private-message-is-redacted-by-structure-only',
        ),
        returnsNormally,
      );
      expect(fallbackMessages, [
        'A structured log record could not be written.',
      ]);
      expect(
        fallbackMessages.single,
        isNot(contains('private-fallback-error')),
      );
    });

    test('isolates failures before a record reaches the sink', () async {
      final sink = _MemoryLogSink();
      final fallbackMessages = <String>[];
      final logger = PackageLoggingAppLogger(
        category: 'app.pipeline',
        minimumLevel: AppLogLevel.debug,
        sink: sink,
        now: () => throw StateError('private-clock-failure'),
        writeFallback: fallbackMessages.add,
      );
      addTearDown(logger.close);

      expect(
        () => logger.log(
          AppLogLevel.error,
          event: 'test.pipeline_failure',
          context: const <String, Object?>{'token': 'private-token'},
        ),
        returnsNormally,
      );
      expect(sink.records, isEmpty);
      expect(fallbackMessages, [
        'A structured log record could not be written.',
      ]);
      expect(fallbackMessages.single, isNot(contains('private-clock-failure')));
      expect(fallbackMessages.single, isNot(contains('private-token')));
    });

    test('rejects dynamic event names and writes nothing', () async {
      final sink = _MemoryLogSink();
      final logger = PackageLoggingAppLogger(
        category: 'app.validation',
        minimumLevel: AppLogLevel.debug,
        sink: sink,
      );
      addTearDown(logger.close);

      Object? eventFailure;
      try {
        logger.log(AppLogLevel.info, event: 'User private@example.invalid');
      } on Object catch (error) {
        eventFailure = error;
      }
      expect(eventFailure, isA<ArgumentError>());
      expect(
        eventFailure.toString(),
        isNot(contains('private@example.invalid')),
      );
      expect(sink.records, isEmpty);
      Object? categoryFailure;
      try {
        PackageLoggingAppLogger(
          category: 'Invalid Category',
          minimumLevel: AppLogLevel.info,
          sink: sink,
        );
      } on Object catch (error) {
        categoryFailure = error;
      }
      expect(categoryFailure, isA<ArgumentError>());
      expect(categoryFailure.toString(), isNot(contains('Invalid Category')));
    });

    test('close is idempotent and rejects later writes', () async {
      final logger = PackageLoggingAppLogger(
        category: 'app.lifecycle',
        minimumLevel: AppLogLevel.debug,
        sink: _MemoryLogSink(),
      );

      await logger.close();
      await logger.close();

      expect(
        () => logger.log(AppLogLevel.info, event: 'test.after_close'),
        throwsA(isA<StateError>()),
      );
    });
  });

  test('ConsoleLogSink emits one valid JSON object', () {
    final lines = <String>[];
    final sink = ConsoleLogSink(writeLine: lines.add);
    final record = AppLogRecord(
      timestamp: DateTime.utc(2026, 8, 9),
      level: AppLogLevel.info,
      category: 'app.test',
      event: 'test.console_output',
      message: 'safe message',
      context: const <String, Object?>{'attempt': 1},
    );

    sink.write(record);

    expect(lines, hasLength(1));
    final json = jsonDecode(lines.single) as Map<String, Object?>;
    expect(json['event'], 'test.console_output');
    expect(json['context'], <String, Object?>{'attempt': 1});
  });
}

final class _MemoryLogSink implements AppLogSink {
  final List<AppLogRecord> records = [];

  @override
  void write(AppLogRecord record) {
    records.add(record);
  }
}

final class _ThrowingLogSink implements AppLogSink {
  @override
  void write(AppLogRecord record) {
    throw StateError('private-sink-error');
  }
}

final class _CountingError {
  int toStringCalls = 0;

  @override
  String toString() {
    toStringCalls++;
    return 'private-counting-error';
  }
}
