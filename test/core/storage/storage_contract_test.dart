import 'package:flutter_template/core/error/app_error.dart';
import 'package:flutter_template/core/storage/preference_key.dart';
import 'package:flutter_template/core/storage/secure_storage_key.dart';
import 'package:flutter_template/core/storage/storage_error_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/storage/in_memory_preference_store.dart';
import '../../support/storage/in_memory_secure_value_store.dart';

void main() {
  group('storage keys', () {
    test('preference keys are stable value objects', () {
      final first = PreferenceKey('appearance.theme_mode');
      final second = PreferenceKey('appearance.theme_mode');

      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(first.name, 'appearance.theme_mode');
      expect(first.toString(), 'PreferenceKey(appearance.theme_mode)');
    });

    test('preference keys reject malformed or credential-like names', () {
      const invalidNames = <String>[
        '',
        ' Appearance.theme_mode',
        'appearance..theme_mode',
        'appearance.theme-mode',
        'auth.refresh_token',
        'account.password',
        'service.api_key',
        'transport.bearer',
        'service.client_secret',
        'auth.jwt',
        'auth.session',
        'browser.cookie',
        'profile.private_key',
      ];

      for (final name in invalidNames) {
        Object? failure;
        try {
          PreferenceKey(name);
        } on Object catch (error) {
          failure = error;
        }
        expect(failure, isA<ArgumentError>(), reason: name);
        if (name.isNotEmpty) {
          expect(failure.toString(), isNot(contains(name)), reason: name);
        }
      }
    });

    test('secure keys accept credential names but redact diagnostics', () {
      final first = SecureStorageKey('auth.refresh_token');
      final second = SecureStorageKey('auth.refresh_token');

      expect(first, second);
      expect(first.name, 'auth.refresh_token');
      expect(first.toString(), 'SecureStorageKey([REDACTED])');
      expect(first.toString(), isNot(contains('refresh_token')));
    });

    test('secure keys reject dynamic or malformed names without echoing', () {
      const privateName = 'User.private-person@example.invalid';

      expect(
        () => SecureStorageKey(privateName),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.toString(),
            'message',
            isNot(contains(privateName)),
          ),
        ),
      );
    });
  });

  group('StorageErrorMapper', () {
    const mapper = StorageErrorMapper();

    test('maps every operation without retaining plugin details', () {
      final raw = StateError('private-platform-storage-detail');
      final errors = <AppError>[
        mapper.fromInitialization(raw),
        mapper.fromRead(raw),
        mapper.fromWrite(raw),
        mapper.fromDelete(raw),
        mapper.fromClear(raw),
      ];

      expect(errors.map((error) => error.code), <String>[
        'storage.initialization',
        'storage.read',
        'storage.write',
        'storage.delete',
        'storage.clear',
      ]);
      for (final error in errors) {
        expect(error.toString(), isNot(contains('private-platform')));
        expect(error.displayMessage, isNot(contains('private-platform')));
      }
    });

    test('preserves an existing stable application error', () {
      const existing = UnexpectedAppError();

      expect(mapper.fromInitialization(existing), same(existing));
      expect(mapper.fromRead(existing), same(existing));
      expect(mapper.fromWrite(existing), same(existing));
      expect(mapper.fromDelete(existing), same(existing));
      expect(mapper.fromClear(existing), same(existing));
    });
  });

  group('InMemoryPreferenceStore', () {
    final boolKey = PreferenceKey('appearance.use_dark_mode');
    final intKey = PreferenceKey('feed.page_size');
    final doubleKey = PreferenceKey('reader.text_scale');
    final stringKey = PreferenceKey('appearance.theme_mode');
    final listKey = PreferenceKey('feed.visible_sections');

    test('returns explicit defaults when values are absent', () async {
      final store = InMemoryPreferenceStore();

      expect(await store.readBool(boolKey, defaultValue: false), isFalse);
      expect(await store.readInt(intKey, defaultValue: 20), 20);
      expect(await store.readDouble(doubleKey, defaultValue: 1), 1);
      expect(
        await store.readString(stringKey, defaultValue: 'system'),
        'system',
      );
      expect(
        await store.readStringList(listKey, defaultValue: const ['all']),
        <String>['all'],
      );
    });

    test('writes and reads every supported preference type', () async {
      final store = InMemoryPreferenceStore();

      await store.writeBool(boolKey, true);
      await store.writeInt(intKey, 40);
      await store.writeDouble(doubleKey, 1.25);
      await store.writeString(stringKey, 'dark');
      await store.writeStringList(listKey, const ['recent', 'saved']);

      expect(await store.readBool(boolKey, defaultValue: false), isTrue);
      expect(await store.readInt(intKey, defaultValue: 20), 40);
      expect(await store.readDouble(doubleKey, defaultValue: 1), 1.25);
      expect(await store.readString(stringKey, defaultValue: 'system'), 'dark');
      expect(
        await store.readStringList(listKey, defaultValue: const []),
        <String>['recent', 'saved'],
      );
    });

    test('defensively copies list inputs, outputs and defaults', () async {
      final store = InMemoryPreferenceStore();
      final input = <String>['recent'];
      await store.writeStringList(listKey, input);
      input.add('mutated');

      final stored = await store.readStringList(
        listKey,
        defaultValue: const [],
      );
      expect(stored, <String>['recent']);
      expect(() => stored.add('changed'), throwsUnsupportedError);

      final fallback = <String>['all'];
      final missing = await store.readStringList(
        PreferenceKey('feed.missing_sections'),
        defaultValue: fallback,
      );
      fallback.add('mutated');
      expect(missing, <String>['all']);
      expect(() => missing.add('changed'), throwsUnsupportedError);
    });

    test('maps stored type mismatches to a stable read error', () async {
      final store = InMemoryPreferenceStore();
      await store.writeString(stringKey, 'dark');

      await expectLater(
        store.readBool(stringKey, defaultValue: false),
        throwsA(isA<StorageReadError>()),
      );
    });

    test('removes one value and clears all values', () async {
      final store = InMemoryPreferenceStore();
      await store.writeBool(boolKey, true);
      await store.writeString(stringKey, 'dark');

      await store.remove(boolKey);
      expect(await store.readBool(boolKey, defaultValue: false), isFalse);
      expect(await store.readString(stringKey, defaultValue: 'system'), 'dark');

      await store.clear();
      expect(
        await store.readString(stringKey, defaultValue: 'system'),
        'system',
      );
    });

    test('rejects unsupported initial values and non-finite doubles', () async {
      expect(
        () => InMemoryPreferenceStore(
          initialValues: <PreferenceKey, Object>{stringKey: DateTime.utc(2026)},
        ),
        throwsA(isA<ArgumentError>()),
      );
      final store = InMemoryPreferenceStore();
      await expectLater(
        store.writeDouble(doubleKey, double.nan),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        store.readDouble(doubleKey, defaultValue: double.infinity),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('InMemorySecureValueStore', () {
    final accessKey = SecureStorageKey('auth.access_token');
    final refreshKey = SecureStorageKey('auth.refresh_token');

    test('distinguishes absence and supports write/delete/clear', () async {
      final store = InMemorySecureValueStore();

      expect(await store.read(accessKey), isNull);
      await store.write(accessKey, 'private-access-value');
      await store.write(refreshKey, 'private-refresh-value');
      expect(await store.read(accessKey), 'private-access-value');

      await store.delete(accessKey);
      expect(await store.read(accessKey), isNull);
      expect(await store.read(refreshKey), 'private-refresh-value');

      await store.clear();
      expect(await store.read(refreshKey), isNull);
    });

    test('copies initial values', () async {
      final initial = <SecureStorageKey, String>{
        accessKey: 'private-access-value',
      };
      final store = InMemorySecureValueStore(initialValues: initial);
      initial[accessKey] = 'mutated';

      expect(await store.read(accessKey), 'private-access-value');
    });
  });
}
