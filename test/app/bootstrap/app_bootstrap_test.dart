import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_template/app/bootstrap/app_bootstrap.dart';
import 'package:flutter_template/app/bootstrap/app_bootstrap_runtime.dart';
import 'package:flutter_template/app/bootstrap/startup_error_reporter.dart';
import 'package:flutter_template/app/bootstrap/startup_failure_app.dart';
import 'package:flutter_template/app/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppBootstrap', () {
    test(
      'waits for application assembly and preserves startup order',
      () async {
        final events = <String>[];
        final runtime = _RecordingBootstrapRuntime(events);
        final reporter = _RecordingStartupErrorReporter();
        final config = AppConfig.fromValues(environment: 'dev');
        const application = SizedBox.shrink();
        final assembly = Completer<Widget>();
        final bootstrap = AppBootstrap(
          runtime: runtime,
          errorReporter: reporter,
          loadConfig: () {
            events.add('config');
            return config;
          },
          assembleApplication: (receivedConfig) {
            events.add('assemble');
            expect(receivedConfig, same(config));
            return assembly.future;
          },
          buildFailureApplication: () {
            events.add('failure');
            return const StartupFailureApp();
          },
        );

        final startup = bootstrap.run();

        expect(events, ['binding', 'handlers', 'config', 'assemble']);
        expect(runtime.applications, isEmpty);

        assembly.complete(application);
        await startup;

        expect(events, ['binding', 'handlers', 'config', 'assemble', 'run']);
        expect(runtime.applications.single, same(application));
        expect(runtime.installedReporter, same(reporter));
        expect(reporter.reports, isEmpty);
      },
    );

    test('reports configuration failure and runs the safe fallback', () async {
      final events = <String>[];
      final runtime = _RecordingBootstrapRuntime(events);
      final reporter = _RecordingStartupErrorReporter();
      final failure = FormatException('API_KEY=private-placeholder');
      const fallback = StartupFailureApp();
      final bootstrap = AppBootstrap(
        runtime: runtime,
        errorReporter: reporter,
        loadConfig: () {
          events.add('config');
          throw failure;
        },
        assembleApplication: (_) {
          events.add('assemble');
          return Future<Widget>.value(const SizedBox.shrink());
        },
        buildFailureApplication: () {
          events.add('failure');
          return fallback;
        },
      );

      await bootstrap.run();

      expect(events, ['binding', 'handlers', 'config', 'failure', 'run']);
      expect(runtime.applications.single, same(fallback));
      expect(reporter.reports, hasLength(1));
      expect(reporter.reports.single.error, same(failure));
      expect(reporter.reports.single.source, StartupErrorSource.configuration);
    });

    test(
      'reports asynchronous assembly failure and runs the fallback',
      () async {
        final events = <String>[];
        final runtime = _RecordingBootstrapRuntime(events);
        final reporter = _RecordingStartupErrorReporter();
        final failure = StateError('dependency initialization failed');
        final failureStack = StackTrace.current;
        const fallback = StartupFailureApp();
        final bootstrap = AppBootstrap(
          runtime: runtime,
          errorReporter: reporter,
          loadConfig: () {
            events.add('config');
            return AppConfig.fromValues(environment: 'staging');
          },
          assembleApplication: (_) {
            events.add('assemble');
            return Future<Widget>.error(failure, failureStack);
          },
          buildFailureApplication: () {
            events.add('failure');
            return fallback;
          },
        );

        await bootstrap.run();

        expect(events, [
          'binding',
          'handlers',
          'config',
          'assemble',
          'failure',
          'run',
        ]);
        expect(runtime.applications.single, same(fallback));
        expect(reporter.reports.single.error, same(failure));
        expect(reporter.reports.single.stackTrace, same(failureStack));
        expect(
          reporter.reports.single.source,
          StartupErrorSource.initialization,
        );
      },
    );
  });

  group('runBootstrapInGuardedZone', () {
    test('captures a synchronous bootstrap failure', () {
      final reporter = _RecordingStartupErrorReporter();
      final failure = StateError('synchronous startup failure');

      runBootstrapInGuardedZone(
        bootstrap: () {
          throw failure;
        },
        errorReporter: reporter,
      );

      expect(reporter.reports, hasLength(1));
      expect(reporter.reports.single.error, same(failure));
      expect(reporter.reports.single.source, StartupErrorSource.rootZone);
    });

    test(
      'captures an unhandled asynchronous failure without a delay',
      () async {
        final reporter = _RecordingStartupErrorReporter();
        final failure = StateError('asynchronous startup failure');

        runBootstrapInGuardedZone(
          bootstrap: () async {
            scheduleMicrotask(() {
              throw failure;
            });
          },
          errorReporter: reporter,
        );

        final report = await reporter.firstReport;

        expect(report.error, same(failure));
        expect(report.source, StartupErrorSource.rootZone);
        expect(reporter.reports, hasLength(1));
      },
    );
  });
}

final class _RecordingBootstrapRuntime implements AppBootstrapRuntime {
  _RecordingBootstrapRuntime(this.events);

  final List<String> events;
  final List<Widget> applications = [];
  StartupErrorReporter? installedReporter;

  @override
  void ensureBindingInitialized() {
    events.add('binding');
  }

  @override
  void installUncaughtErrorHandlers(StartupErrorReporter errorReporter) {
    events.add('handlers');
    installedReporter = errorReporter;
  }

  @override
  void runApplication(Widget application) {
    events.add('run');
    applications.add(application);
  }
}

final class _RecordingStartupErrorReporter implements StartupErrorReporter {
  final List<_ReportedStartupError> reports = [];
  final Completer<_ReportedStartupError> _firstReport = Completer();

  Future<_ReportedStartupError> get firstReport => _firstReport.future;

  @override
  void report({
    required Object error,
    required StackTrace stackTrace,
    required StartupErrorSource source,
  }) {
    final report = _ReportedStartupError(
      error: error,
      stackTrace: stackTrace,
      source: source,
    );
    reports.add(report);
    if (!_firstReport.isCompleted) {
      _firstReport.complete(report);
    }
  }
}

final class _ReportedStartupError {
  const _ReportedStartupError({
    required this.error,
    required this.stackTrace,
    required this.source,
  });

  final Object error;
  final StackTrace stackTrace;
  final StartupErrorSource source;
}
