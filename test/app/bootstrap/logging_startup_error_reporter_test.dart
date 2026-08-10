import 'package:flutter_template/app/bootstrap/logging_startup_error_reporter.dart';
import 'package:flutter_template/app/bootstrap/startup_error_reporter.dart';
import 'package:flutter_template/core/logging/app_log_level.dart';
import 'package:flutter_template/core/logging/app_logger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps configuration failures and forwards structured context', () {
    final logger = _RecordingAppLogger();
    final fallback = _RecordingStartupErrorReporter();
    final reporter = LoggingStartupErrorReporter(
      logger: logger,
      fallbackReporter: fallback,
    );
    final error = FormatException('private-configuration-value');
    final stackTrace = StackTrace.current;

    reporter.report(
      error: error,
      stackTrace: stackTrace,
      source: StartupErrorSource.configuration,
    );

    final call = logger.calls.single;
    expect(call.level, AppLogLevel.error);
    expect(call.event, 'startup.unhandled_error');
    expect(call.context, <String, Object?>{
      'source': 'configuration',
      'errorCode': 'configuration.invalid',
    });
    expect(call.error, same(error));
    expect(call.stackTrace, same(stackTrace));
    expect(fallback.reports, isEmpty);
  });

  test('does not treat an assembly FormatException as configuration', () {
    final logger = _RecordingAppLogger();
    final reporter = LoggingStartupErrorReporter(
      logger: logger,
      fallbackReporter: _RecordingStartupErrorReporter(),
    );

    reporter.report(
      error: const FormatException('dependency payload is malformed'),
      stackTrace: StackTrace.current,
      source: StartupErrorSource.initialization,
    );

    expect(logger.calls.single.context['errorCode'], 'unexpected');
    expect(logger.calls.single.context['source'], 'initialization');
  });

  test('uses unexpected code outside the configuration boundary', () {
    final logger = _RecordingAppLogger();
    final reporter = LoggingStartupErrorReporter(
      logger: logger,
      fallbackReporter: _RecordingStartupErrorReporter(),
    );

    reporter.report(
      error: StateError('framework failure'),
      stackTrace: StackTrace.current,
      source: StartupErrorSource.flutterFramework,
    );

    expect(logger.calls.single.context['errorCode'], 'unexpected');
    expect(logger.calls.single.context['source'], 'flutterFramework');
  });

  test('falls back without throwing when structured logging fails', () {
    final fallback = _RecordingStartupErrorReporter();
    final reporter = LoggingStartupErrorReporter(
      logger: _ThrowingAppLogger(),
      fallbackReporter: fallback,
    );
    final error = StateError('private-original-error');
    final stackTrace = StackTrace.current;

    expect(
      () => reporter.report(
        error: error,
        stackTrace: stackTrace,
        source: StartupErrorSource.rootZone,
      ),
      returnsNormally,
    );
    expect(fallback.reports.single.error, same(error));
    expect(fallback.reports.single.stackTrace, same(stackTrace));
    expect(fallback.reports.single.source, StartupErrorSource.rootZone);
  });

  test('swallows a final fallback contract violation', () {
    final reporter = LoggingStartupErrorReporter(
      logger: _ThrowingAppLogger(),
      fallbackReporter: _ThrowingStartupErrorReporter(),
    );

    expect(
      () => reporter.report(
        error: StateError('failure'),
        stackTrace: StackTrace.current,
        source: StartupErrorSource.platformDispatcher,
      ),
      returnsNormally,
    );
  });
}

final class _RecordingAppLogger implements AppLogger {
  final List<_LogCall> calls = [];

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
    calls.add(
      _LogCall(
        level: level,
        event: event,
        context: context,
        error: error,
        stackTrace: stackTrace,
      ),
    );
  }

  @override
  Future<void> close() async {}
}

final class _ThrowingAppLogger implements AppLogger {
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

final class _RecordingStartupErrorReporter implements StartupErrorReporter {
  final List<_StartupReport> reports = [];

  @override
  void report({
    required Object error,
    required StackTrace stackTrace,
    required StartupErrorSource source,
  }) {
    reports.add(
      _StartupReport(error: error, stackTrace: stackTrace, source: source),
    );
  }
}

final class _ThrowingStartupErrorReporter implements StartupErrorReporter {
  @override
  void report({
    required Object error,
    required StackTrace stackTrace,
    required StartupErrorSource source,
  }) {
    throw StateError('private-fallback-failure');
  }
}

final class _LogCall {
  const _LogCall({
    required this.level,
    required this.event,
    required this.context,
    required this.error,
    required this.stackTrace,
  });

  final AppLogLevel level;
  final String event;
  final Map<String, Object?> context;
  final Object? error;
  final StackTrace? stackTrace;
}

final class _StartupReport {
  const _StartupReport({
    required this.error,
    required this.stackTrace,
    required this.source,
  });

  final Object error;
  final StackTrace stackTrace;
  final StartupErrorSource source;
}
