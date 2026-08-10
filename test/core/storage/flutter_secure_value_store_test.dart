import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_template/core/error/app_error.dart';
import 'package:flutter_template/core/storage/flutter_secure_value_store.dart';
import 'package:flutter_template/core/storage/secure_storage_key.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FlutterSecureValueStore', () {
    test('maps synchronous plugin initialization failures', () {
      const privateDetail = 'private-secure-initialization';

      expect(
        () => FlutterSecureValueStore(
          storageFactory:
              ({
                required AndroidOptions androidOptions,
                required IOSOptions iosOptions,
              }) => throw StateError(privateDetail),
        ),
        throwsA(
          isA<StorageInitializationError>()
              .having((error) => error.code, 'code', 'storage.initialization')
              .having(
                (error) => error.toString(),
                'diagnostic',
                isNot(contains(privateDetail)),
              ),
        ),
      );
    });

    test('reads absence and supports write, delete and clear', () async {
      final backend = _FakeFlutterSecureStorage();
      final store = _storeWithBackend(backend);
      final accessKey = SecureStorageKey('auth.access_token');
      final refreshKey = SecureStorageKey('auth.refresh_token');

      expect(await store.read(accessKey), isNull);
      await store.write(accessKey, 'private-access-value');
      await store.write(refreshKey, 'private-refresh-value');
      expect(
        backend.values['${FlutterSecureValueStore.keyPrefix}auth.access_token'],
        'private-access-value',
      );
      expect(await store.read(accessKey), 'private-access-value');

      await store.delete(accessKey);
      expect(await store.read(accessKey), isNull);
      expect(await store.read(refreshKey), 'private-refresh-value');

      await store.clear();
      expect(await store.read(refreshKey), isNull);
      expect(backend.deleteAllCallCount, 1);
    });

    test('maps read, write, delete and clear plugin failures safely', () async {
      final backend = _FakeFlutterSecureStorage();
      final store = _storeWithBackend(backend);
      final key = SecureStorageKey('auth.access_token');

      backend.failingMethods.add('read');
      await expectLater(
        store.read(key),
        throwsA(
          isA<StorageReadError>().having(
            (error) => error.toString(),
            'diagnostic',
            isNot(contains('private-secure-plugin-detail')),
          ),
        ),
      );
      backend.failingMethods.clear();

      backend.failingMethods.add('write');
      await expectLater(
        store.write(key, 'private-access-value'),
        throwsA(isA<StorageWriteError>()),
      );
      backend.failingMethods.clear();

      backend.failingMethods.add('delete');
      await expectLater(store.delete(key), throwsA(isA<StorageDeleteError>()));
      backend.failingMethods.clear();

      backend.failingMethods.add('deleteAll');
      await expectLater(store.clear(), throwsA(isA<StorageClearError>()));
    });

    test('pins migration identifiers and platform security options', () {
      late AndroidOptions capturedAndroidOptions;
      late IOSOptions capturedIosOptions;
      FlutterSecureValueStore(
        storageFactory: ({
          required AndroidOptions androidOptions,
          required IOSOptions iosOptions,
        }) {
          capturedAndroidOptions = androidOptions;
          capturedIosOptions = iosOptions;
          return _FakeFlutterSecureStorage();
        },
      );

      expect(FlutterSecureValueStore.keyPrefix, 'app.secure.');
      expect(
        FlutterSecureValueStore.androidStorageNamespace,
        'app_secure_storage',
      );
      expect(FlutterSecureValueStore.appleService, 'app.secure_storage');
      expect(
        capturedAndroidOptions.toMap(),
        containsPair('resetOnError', 'false'),
      );
      expect(
        capturedAndroidOptions.toMap(),
        containsPair('migrateOnAlgorithmChange', 'true'),
      );
      expect(
        capturedAndroidOptions.toMap(),
        containsPair('migrateWithBackup', 'true'),
      );
      expect(
        capturedAndroidOptions.toMap(),
        containsPair('enforceBiometrics', 'false'),
      );
      expect(
        capturedAndroidOptions.toMap(),
        containsPair(
          'keyCipherAlgorithm',
          'RSA_ECB_OAEPwithSHA_256andMGF1Padding',
        ),
      );
      expect(
        capturedAndroidOptions.toMap(),
        containsPair('storageCipherAlgorithm', 'AES_GCM_NoPadding'),
      );
      expect(
        capturedAndroidOptions.storageNamespace,
        FlutterSecureValueStore.androidStorageNamespace,
      );
      expect(
        capturedIosOptions.accountName,
        FlutterSecureValueStore.appleService,
      );
      expect(
        capturedIosOptions.accessibility,
        KeychainAccessibility.unlocked_this_device,
      );
      expect(capturedIosOptions.synchronizable, isFalse);
    });
  });
}

FlutterSecureValueStore _storeWithBackend(FlutterSecureStorage backend) =>
    FlutterSecureValueStore(
      storageFactory:
          ({
            required AndroidOptions androidOptions,
            required IOSOptions iosOptions,
          }) => backend,
    );

final class _FakeFlutterSecureStorage extends FlutterSecureStorage {
  _FakeFlutterSecureStorage();

  final Map<String, String> values = <String, String>{};
  final Set<String> failingMethods = <String>{};
  int deleteAllCallCount = 0;

  void _before(String method) {
    if (failingMethods.contains(method)) {
      throw StateError('private-secure-plugin-detail');
    }
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _before('read');
    return values[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _before('write');
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _before('delete');
    values.remove(key);
  }

  @override
  Future<void> deleteAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _before('deleteAll');
    deleteAllCallCount += 1;
    values.clear();
  }
}
