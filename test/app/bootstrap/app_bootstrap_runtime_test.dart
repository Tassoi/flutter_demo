import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_template/app/bootstrap/app_bootstrap_runtime.dart';
import 'package:flutter_template/app/bootstrap/startup_error_reporter.dart';
import 'package:flutter_template/app/localization/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Flutter runtime forwards errors and localizes its safe widget', (
    tester,
  ) async {
    final previousFlutterHandler = FlutterError.onError;
    final previousPlatformHandler = PlatformDispatcher.instance.onError;
    final previousErrorWidgetBuilder = ErrorWidget.builder;
    addTearDown(() {
      FlutterError.onError = previousFlutterHandler;
      PlatformDispatcher.instance.onError = previousPlatformHandler;
      ErrorWidget.builder = previousErrorWidgetBuilder;
    });
    final reporter = _RecordingStartupErrorReporter();
    const runtime = FlutterAppBootstrapRuntime();
    final frameworkFailure = StateError('framework failure');
    final frameworkStack = StackTrace.current;
    final platformFailure = StateError('platform failure');
    final platformStack = StackTrace.current;

    runtime.ensureBindingInitialized();
    runtime.installUncaughtErrorHandlers(reporter);
    FlutterError.onError!(
      FlutterErrorDetails(
        exception: frameworkFailure,
        stack: frameworkStack,
        library: 'bootstrap test',
      ),
    );
    final wasHandled = PlatformDispatcher.instance.onError!(
      platformFailure,
      platformStack,
    );
    final errorWidget = ErrorWidget.builder(
      FlutterErrorDetails(
        exception: StateError('Bearer private-token-placeholder'),
      ),
    );

    expect(wasHandled, isTrue);
    expect(reporter.reports, hasLength(2));
    expect(reporter.reports[0].error, same(frameworkFailure));
    expect(reporter.reports[0].stackTrace, same(frameworkStack));
    expect(reporter.reports[0].source, StartupErrorSource.flutterFramework);
    expect(reporter.reports[1].error, same(platformFailure));
    expect(reporter.reports[1].stackTrace, same(platformStack));
    expect(reporter.reports[1].source, StartupErrorSource.platformDispatcher);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: errorWidget,
      ),
    );

    final renderedError = tester.widget<ErrorWidget>(find.byType(ErrorWidget));
    expect(renderedError.message, '无法显示此内容。');
    expect(renderedError.message, isNot(contains('private-token-placeholder')));
  });
}

final class _RecordingStartupErrorReporter implements StartupErrorReporter {
  final List<_ReportedStartupError> reports = [];

  @override
  void report({
    required Object error,
    required StackTrace stackTrace,
    required StartupErrorSource source,
  }) {
    reports.add(
      _ReportedStartupError(
        error: error,
        stackTrace: stackTrace,
        source: source,
      ),
    );
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
