import 'dart:convert';

import 'package:flutter_template/core/storage/secure_storage_key.dart';
import 'package:flutter_template/core/storage/secure_value_store.dart';
import 'package:flutter_template/features/auth/data/auth_credential_persistence.dart';
import 'package:flutter_template/features/auth/data/secure_auth_credential_persistence.dart';
import 'package:flutter_template/features/auth/domain/auth_failure.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/features/auth/auth_credentials_fixture.dart';
import '../../../support/storage/in_memory_secure_value_store.dart';

void main() {
  final sessionKey = SecureStorageKey('auth.session');

  test('round trips one versioned secure envelope and clears it', () async {
    final secureStore = InMemorySecureValueStore();
    final persistence = SecureAuthCredentialPersistence(secureStore);
    final credentials = createAuthCredentialsFixture();

    expect(await persistence.load(), isNull);
    await persistence.save(credentials);

    final encoded = await secureStore.read(sessionKey);
    expect(encoded, isNotNull);
    final decoded = jsonDecode(encoded!) as Map<String, Object?>;
    expect(decoded.keys, <String>{
      'schemaVersion',
      'accessCredential',
      'refreshCredential',
      'accessExpiresAtMs',
      'refreshExpiresAtMs',
    });
    expect(decoded['schemaVersion'], 1);
    expect(decoded, isNot(contains('password')));

    final restored = await persistence.load();
    expect(restored, isNotNull);
    expect(restored!.accessCredential, credentials.accessCredential);
    expect(restored.refreshCredential, credentials.refreshCredential);
    expect(restored.accessExpiresAt, credentials.accessExpiresAt);
    expect(restored.refreshExpiresAt, credentials.refreshExpiresAt);

    await persistence.clear();
    expect(await persistence.load(), isNull);
  });

  test(
    'rejects malformed, incomplete, extra and unknown-schema data',
    () async {
      final invalidValues = <String>[
        'not-json',
        '{}',
        jsonEncode(<String, Object?>{
          'schemaVersion': 2,
          'accessCredential': 'fixture-access',
          'refreshCredential': 'fixture-refresh',
          'accessExpiresAtMs': 1893456000000,
          'refreshExpiresAtMs': 1893542400000,
        }),
        jsonEncode(<String, Object?>{
          'schemaVersion': 1,
          'accessCredential': 'fixture-access',
          'refreshCredential': 'fixture-refresh',
          'accessExpiresAtMs': 1893456000000,
          'refreshExpiresAtMs': 1893542400000,
          'unexpected': true,
        }),
        jsonEncode(<String, Object?>{
          'schemaVersion': 1,
          'accessCredential': 'fixture-access',
          'refreshCredential': 'fixture-refresh',
          'accessExpiresAtMs': 1893542400000,
          'refreshExpiresAtMs': 1893456000000,
        }),
      ];

      for (final invalidValue in invalidValues) {
        final secureStore = InMemorySecureValueStore(
          initialValues: <SecureStorageKey, String>{sessionKey: invalidValue},
        );
        final persistence = SecureAuthCredentialPersistence(secureStore);

        await expectLater(
          persistence.load(),
          throwsA(
            isA<AuthPersistenceFailure>().having(
              (failure) => failure.toString(),
              'safe failure',
              isNot(contains('fixture-access')),
            ),
          ),
        );
      }
    },
  );

  test(
    'maps every secure store operation failure to a stable result',
    () async {
      for (final operation in _SecureOperation.values) {
        final persistence = SecureAuthCredentialPersistence(
          _FailingSecureValueStore(operation),
        );
        final future = switch (operation) {
          _SecureOperation.read => persistence.load(),
          _SecureOperation.write => persistence.save(
            createAuthCredentialsFixture(),
          ),
          _SecureOperation.delete => persistence.clear(),
        };

        await expectLater(
          future,
          throwsA(
            isA<AuthPersistenceFailure>().having(
              (failure) => failure.toString(),
              'safe failure',
              isNot(contains('private-storage-detail')),
            ),
          ),
        );
      }
    },
  );

  test('unconfigured persistence fails closed on save', () async {
    const persistence = UnconfiguredAuthCredentialPersistence();

    expect(await persistence.load(), isNull);
    await persistence.clear();
    await expectLater(
      persistence.save(createAuthCredentialsFixture()),
      throwsA(isA<AuthPersistenceFailure>()),
    );
  });
}

enum _SecureOperation { read, write, delete }

final class _FailingSecureValueStore implements SecureValueStore {
  const _FailingSecureValueStore(this.operation);

  final _SecureOperation operation;

  @override
  Future<String?> read(SecureStorageKey key) {
    if (operation == _SecureOperation.read) {
      throw StateError('private-storage-detail');
    }
    return Future<String?>.value(null);
  }

  @override
  Future<void> write(SecureStorageKey key, String value) {
    if (operation == _SecureOperation.write) {
      throw StateError('private-storage-detail');
    }
    return Future<void>.value();
  }

  @override
  Future<void> delete(SecureStorageKey key) {
    if (operation == _SecureOperation.delete) {
      throw StateError('private-storage-detail');
    }
    return Future<void>.value();
  }

  @override
  Future<void> clear() async {}
}
