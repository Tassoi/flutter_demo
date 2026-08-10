import 'package:flutter_template/app/config/app_environment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppEnvironment.parse', () {
    test('parses every supported value', () {
      expect(AppEnvironment.parse('dev'), AppEnvironment.dev);
      expect(AppEnvironment.parse('staging'), AppEnvironment.staging);
      expect(AppEnvironment.parse('prod'), AppEnvironment.prod);
    });

    test('rejects a missing environment', () {
      expect(() => AppEnvironment.parse(''), throwsA(isA<FormatException>()));
    });

    test('rejects unknown or silently normalized values', () {
      for (final value in ['qa', 'DEV', ' dev', 'prod ']) {
        expect(
          () => AppEnvironment.parse(value),
          throwsA(isA<FormatException>()),
          reason: 'Unexpectedly accepted "$value".',
        );
      }
    });
  });
}
