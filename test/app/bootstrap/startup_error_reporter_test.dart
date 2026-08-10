import 'package:flutter_template/app/bootstrap/startup_error_reporter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('safe reporter never writes raw error or stack details', () {
    final messages = <String>[];
    final reporter = SafeStartupErrorReporter(writeMessage: messages.add);
    final failure = FormatException('Bearer private-token-placeholder');
    final stackTrace = StackTrace.fromString(
      'password=private-password-placeholder',
    );

    reporter.report(
      error: failure,
      stackTrace: stackTrace,
      source: StartupErrorSource.configuration,
    );

    expect(messages, [
      'Application error captured at the configuration boundary '
          '(code: configuration.invalid).',
    ]);
    expect(messages.single, isNot(contains('private-token-placeholder')));
    expect(messages.single, isNot(contains('private-password-placeholder')));
    expect(messages.single, isNot(contains('FormatException')));
  });

  test('safe reporter isolates a final writer failure', () {
    final reporter = SafeStartupErrorReporter(
      writeMessage: (_) {
        throw StateError('private-writer-failure');
      },
    );

    expect(
      () => reporter.report(
        error: StateError('private-original-failure'),
        stackTrace: StackTrace.fromString('private-stack-trace'),
        source: StartupErrorSource.rootZone,
      ),
      returnsNormally,
    );
  });

  test('deferred reporter switches once without replaying earlier errors', () {
    final fallback = _RecordingReporter();
    final structured = _RecordingReporter();
    final reporter = DeferredStartupErrorReporter(fallbackReporter: fallback);
    final beforeBinding = StateError('before binding');
    final afterBinding = StateError('after binding');

    reporter.report(
      error: beforeBinding,
      stackTrace: StackTrace.current,
      source: StartupErrorSource.configuration,
    );
    reporter.bind(structured);
    reporter.report(
      error: afterBinding,
      stackTrace: StackTrace.current,
      source: StartupErrorSource.rootZone,
    );

    expect(fallback.errors, hasLength(1));
    expect(fallback.errors.single, same(beforeBinding));
    expect(structured.errors, hasLength(1));
    expect(structured.errors.single, same(afterBinding));
    expect(() => reporter.bind(structured), throwsA(isA<StateError>()));
  });
}

final class _RecordingReporter implements StartupErrorReporter {
  final List<Object> errors = [];

  @override
  void report({
    required Object error,
    required StackTrace stackTrace,
    required StartupErrorSource source,
  }) {
    errors.add(error);
  }
}
