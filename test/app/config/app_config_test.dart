import 'package:flutter_template/app/config/app_config.dart';
import 'package:flutter_template/app/config/app_environment.dart';
import 'package:flutter_test/flutter_test.dart';

const _compiledEnvironment = String.fromEnvironment('APP_ENV');
const _compiledApiBaseUrl = String.fromEnvironment('API_BASE_URL');

void main() {
  test('reads Dart defines or rejects a build with no APP_ENV', () {
    if (_compiledEnvironment.isEmpty) {
      expect(AppConfig.fromDartDefines, throwsA(isA<FormatException>()));
      return;
    }

    final config = AppConfig.fromDartDefines(
      nativeFlavor: _compiledEnvironment,
    );

    expect(config.environment.name, _compiledEnvironment);
    if (_compiledApiBaseUrl.isNotEmpty) {
      expect(config.apiBaseUri, Uri.parse(_compiledApiBaseUrl));
    }
  });

  group('AppConfig.fromValues', () {
    test('resolves the development profile', () {
      final config = AppConfig.fromValues(environment: 'dev');

      expect(config.environment, AppEnvironment.dev);
      expect(config.apiBaseUri, Uri.parse('https://api.dev.example.invalid/'));
      expect(config.minimumLogLevel, AppLogLevel.debug);
      expect(config.appName, 'Flutter Template Dev');
      expect(config.packageNameSuffix, '.dev');
    });

    test('resolves the staging profile', () {
      final config = AppConfig.fromValues(environment: 'staging');

      expect(config.environment, AppEnvironment.staging);
      expect(
        config.apiBaseUri,
        Uri.parse('https://api.staging.example.invalid/'),
      );
      expect(config.minimumLogLevel, AppLogLevel.info);
      expect(config.appName, 'Flutter Template Staging');
      expect(config.packageNameSuffix, '.staging');
    });

    test('resolves the production profile', () {
      final config = AppConfig.fromValues(environment: 'prod');

      expect(config.environment, AppEnvironment.prod);
      expect(config.apiBaseUri, Uri.parse('https://api.example.invalid/'));
      expect(config.minimumLogLevel, AppLogLevel.warning);
      expect(config.appName, 'Flutter Template');
      expect(config.packageNameSuffix, isEmpty);
    });

    test('accepts every native flavor when it matches APP_ENV', () {
      for (final environment in ['dev', 'staging', 'prod']) {
        final config = AppConfig.fromValues(
          environment: environment,
          nativeFlavor: environment,
        );

        expect(config.environment.name, environment);
      }
    });

    test('allows a missing native flavor for pure Dart callers', () {
      final config = AppConfig.fromValues(environment: 'dev');

      expect(config.environment, AppEnvironment.dev);
    });

    test('rejects a native flavor that differs from APP_ENV', () {
      for (final nativeFlavor in ['prod', 'DEV', ' dev', 'qa']) {
        expect(
          () => AppConfig.fromValues(
            environment: 'dev',
            nativeFlavor: nativeFlavor,
          ),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              'The native flavor must exactly match APP_ENV.',
            ),
          ),
          reason: 'Unexpectedly accepted native flavor "$nativeFlavor".',
        );
      }
    });

    test('uses only non-routable hosts for defaults', () {
      for (final environment in ['dev', 'staging', 'prod']) {
        final config = AppConfig.fromValues(environment: environment);

        expect(config.apiBaseUri.host.endsWith('.invalid'), isTrue);
      }
    });

    test('normalizes an overridden base path', () {
      final config = AppConfig.fromValues(
        environment: 'dev',
        apiBaseUrl: 'http://localhost:8080/v1',
      );

      expect(config.apiBaseUri, Uri.parse('http://localhost:8080/v1/'));
      expect(config.apiBaseUri.resolve('users').path, '/v1/users');
    });

    test('rejects an insecure production endpoint', () {
      expect(
        () => AppConfig.fromValues(
          environment: 'prod',
          apiBaseUrl: 'http://api.example.invalid/',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects malformed or unsafe endpoint shapes', () {
      for (final value in [
        '/relative',
        'ftp://api.example.invalid/',
        'https://user:placeholder@api.example.invalid/',
        'https://api.example.invalid/?tenant=example',
        'https://api.example.invalid/#fragment',
      ]) {
        expect(
          () => AppConfig.fromValues(environment: 'dev', apiBaseUrl: value),
          throwsA(isA<FormatException>()),
          reason: 'Unexpectedly accepted "$value".',
        );
      }
    });

    test('does not copy a rejected endpoint into the exception', () {
      const unsafeValue =
          'https://user:private-placeholder@api.example.invalid/';

      expect(
        () => AppConfig.fromValues(environment: 'dev', apiBaseUrl: unsafeValue),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            isNot(contains('private-placeholder')),
          ),
        ),
      );
    });
  });
}
