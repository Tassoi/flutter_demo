import 'dart:collection';

import 'package:flutter_template/core/logging/log_redactor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LogRedactor', () {
    test('redacts nested credentials and privacy fields by key', () {
      const redactor = LogRedactor();
      final context = <String, Object?>{
        'authorization': 'Bearer private-token-placeholder',
        'profile': <String, Object?>{
          'email': 'person@example.invalid',
          'phoneNumber': '13800138000',
          'displayValue': 'safe-value',
        },
        'items': <Object?>[
          'token=private-list-token',
          <String, Object?>{'client_secret': 'private-client-secret'},
        ],
        'requestUri': Uri.parse(
          'https://private-user:private-password@api.example.invalid/items'
          '?access_token=private-query-token#private-fragment',
        ),
        'authTokenValue': 'private-prefixed-token',
        'contactEmail': 'person@example.invalid',
        'notANumber': double.nan,
        'positiveInfinity': double.infinity,
      };

      final result = redactor.redactContext(context);
      final profile = result['profile']! as Map<String, Object?>;
      final items = result['items']! as List<Object?>;
      final nestedItem = items[1]! as Map<String, Object?>;

      expect(result['authorization'], LogRedactor.redactedValue);
      expect(profile['email'], LogRedactor.redactedValue);
      expect(profile['phoneNumber'], LogRedactor.redactedValue);
      expect(profile['displayValue'], 'safe-value');
      expect(items[0], contains(LogRedactor.redactedValue));
      expect(items[0], isNot(contains('private-list-token')));
      expect(nestedItem['client_secret'], LogRedactor.redactedValue);
      expect(result['requestUri'], isNot(contains('private-query-token')));
      expect(result['requestUri'], isNot(contains('private-user')));
      expect(result['requestUri'], isNot(contains('private-password')));
      expect(result['requestUri'], isNot(contains('private-fragment')));
      expect(result['authTokenValue'], LogRedactor.redactedValue);
      expect(result['contactEmail'], LogRedactor.redactedValue);
      expect(result['notANumber'], 'NaN');
      expect(result['positiveInfinity'], 'Infinity');
      expect(() => result['new'] = 'value', throwsA(isA<UnsupportedError>()));
      expect(() => profile['new'] = 'value', throwsA(isA<UnsupportedError>()));
    });

    test('redacts common secrets and personal data in free text', () {
      const redactor = LogRedactor();
      const raw =
          'Authorization: Bearer private-header-token\n'
          'password=private-password '
          '{"client_secret":"private secret with spaces"} '
          'person@example.invalid 13800138000';

      final result = redactor.redactText(raw);

      expect(result, contains('Authorization: ${LogRedactor.redactedValue}'));
      expect(result, contains('password=${LogRedactor.redactedValue}'));
      expect(result, contains('[REDACTED_EMAIL]'));
      expect(result, contains('[REDACTED_PHONE]'));
      for (final secret in [
        'private-header-token',
        'private-password',
        'private secret with spaces',
        'person@example.invalid',
        '13800138000',
      ]) {
        expect(result, isNot(contains(secret)));
      }
    });

    test('redacts quoted labeled values and cookie assignments', () {
      const redactor = LogRedactor();
      const raw =
          'token="private token with spaces" '
          "password='private password with spaces' "
          'cookie=session=private-cookie-value '
          '{"auth_token":"private-auth-token"}';

      final result = redactor.redactText(raw);

      expect(
        result,
        'token=${LogRedactor.redactedValue} '
        'password=${LogRedactor.redactedValue} '
        'cookie=${LogRedactor.redactedValue} '
        '{"auth_token":"${LogRedactor.redactedValue}"}',
      );
      expect(result, isNot(contains('private')));
    });

    test('bounds depth, collection size, text length, and cycles', () {
      const redactor = LogRedactor(
        maxDepth: 3,
        maxCollectionItems: 2,
        maxTextLength: 32,
      );
      final cycle = <String, Object?>{};
      cycle['self'] = cycle;

      final result = redactor.redactContext(<String, Object?>{
        'cycle': cycle,
        'deep': <String, Object?>{
          'nested': <String, Object?>{
            'deeper': <String, Object?>{'value': 'not-retained'},
          },
        },
        'list': <int>[1, 2, 3],
      });
      final cycleResult = result['cycle']! as Map<String, Object?>;
      final cycleMarker = cycleResult['self']! as Map<String, Object?>;
      final deepResult = result['deep']! as Map<String, Object?>;
      final nestedResult = deepResult['nested']! as Map<String, Object?>;

      expect(cycleMarker['__circular__'], LogRedactor.circularValue);
      expect(nestedResult['deeper'], LogRedactor.truncatedValue);
      expect(result['__truncated__'], LogRedactor.truncatedValue);
      expect(
        redactor.redactText(List<String>.filled(64, 'x').join()),
        endsWith(LogRedactor.truncatedValue),
      );
    });

    test('never calls toString on unsupported context objects', () {
      const redactor = LogRedactor();

      final result = redactor.redactContext(<String, Object?>{
        'value': _ThrowingToString(),
      });

      expect(result['value'], '<_ThrowingToString>');
      expect(
        redactor.redactError(_ThrowingToString()),
        '<error message unavailable>',
      );
    });

    test('fails closed for throwing collections and stack traces', () {
      const redactor = LogRedactor();

      final context = redactor.redactContext(<String, Object?>{
        'map': _ThrowingMap(),
        'items': _ThrowingIterable(),
      });
      final failedMap = context['map']! as Map<String, Object?>;

      expect(failedMap['__unavailable__'], LogRedactor.unavailableValue);
      expect(context['items'], LogRedactor.unavailableValue);
      expect(
        redactor.redactContext(_ThrowingMap())['__unavailable__'],
        LogRedactor.unavailableValue,
      );
      expect(
        redactor.redactStackTrace(_ThrowingStackTrace()),
        LogRedactor.unavailableValue,
      );
    });
  });
}

final class _ThrowingToString {
  @override
  String toString() {
    throw StateError('private-to-string-value');
  }
}

final class _ThrowingMap extends MapBase<String, Object?> {
  @override
  Object? operator [](Object? key) => null;

  @override
  void operator []=(String key, Object? value) {}

  @override
  void clear() {}

  @override
  Iterable<String> get keys => throw StateError('private-map-value');

  @override
  Object? remove(Object? key) => null;
}

final class _ThrowingIterable extends IterableBase<Object?> {
  @override
  Iterator<Object?> get iterator => throw StateError('private-list-value');
}

final class _ThrowingStackTrace implements StackTrace {
  @override
  String toString() {
    throw StateError('private-stack-value');
  }
}
