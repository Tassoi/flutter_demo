import 'package:flutter_template/core/error/app_error.dart';
import 'package:flutter_template/core/storage/preference_key.dart';
import 'package:flutter_template/core/storage/shared_preferences_preference_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('SharedPreferencesPreferenceStore', () {
    test('maps synchronous plugin initialization failures', () {
      const privateDetail = 'private-preferences-initialization';

      expect(
        () => SharedPreferencesPreferenceStore(
          preferencesFactory: () => throw StateError(privateDetail),
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

    test('uses its namespace and supports every preference type', () async {
      final backend = _FakeSharedPreferencesAsync();
      final store = SharedPreferencesPreferenceStore(
        preferencesFactory: () => backend,
      );
      final boolKey = PreferenceKey('appearance.use_dark_mode');
      final intKey = PreferenceKey('feed.page_size');
      final doubleKey = PreferenceKey('reader.text_scale');
      final stringKey = PreferenceKey('appearance.theme_mode');
      final listKey = PreferenceKey('feed.visible_sections');

      await store.writeBool(boolKey, true);
      await store.writeInt(intKey, 40);
      await store.writeDouble(doubleKey, 1.25);
      await store.writeString(stringKey, 'dark');
      await store.writeStringList(listKey, const ['recent', 'saved']);

      const prefix = SharedPreferencesPreferenceStore.namespacePrefix;
      expect(backend.values['${prefix}appearance.use_dark_mode'], isTrue);
      expect(backend.values['${prefix}feed.page_size'], 40);
      expect(backend.values['${prefix}reader.text_scale'], 1.25);
      expect(backend.values['${prefix}appearance.theme_mode'], 'dark');
      expect(backend.values['${prefix}feed.visible_sections'], <String>[
        'recent',
        'saved',
      ]);

      expect(await store.readBool(boolKey, defaultValue: false), isTrue);
      expect(await store.readInt(intKey, defaultValue: 20), 40);
      expect(await store.readDouble(doubleKey, defaultValue: 1), 1.25);
      expect(await store.readString(stringKey, defaultValue: 'system'), 'dark');
      expect(
        await store.readStringList(listKey, defaultValue: const []),
        <String>['recent', 'saved'],
      );
    });

    test('returns defaults and defensively copies string lists', () async {
      final backend = _FakeSharedPreferencesAsync();
      final store = SharedPreferencesPreferenceStore(
        preferencesFactory: () => backend,
      );
      final listKey = PreferenceKey('feed.visible_sections');
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
      expect(
        await store.readString(
          PreferenceKey('appearance.missing_mode'),
          defaultValue: 'system',
        ),
        'system',
      );
    });

    test('remove and clear only affect adapter-owned keys', () async {
      const prefix = SharedPreferencesPreferenceStore.namespacePrefix;
      final backend = _FakeSharedPreferencesAsync(<String, Object?>{
        '${prefix}appearance.theme_mode': 'dark',
        '${prefix}feed.page_size': 40,
        'other.plugin.value': 'must-remain',
      });
      final store = SharedPreferencesPreferenceStore(
        preferencesFactory: () => backend,
      );

      await store.remove(PreferenceKey('appearance.theme_mode'));
      expect(backend.values, isNot(contains('${prefix}appearance.theme_mode')));
      expect(backend.values['${prefix}feed.page_size'], 40);

      await store.clear();
      expect(backend.values['${prefix}feed.page_size'], isNull);
      expect(backend.values['other.plugin.value'], 'must-remain');
      expect(backend.lastClearAllowList, <String>{'${prefix}feed.page_size'});
    });

    test(
      'does not invoke an unrestricted clear for an empty namespace',
      () async {
        final backend = _FakeSharedPreferencesAsync(<String, Object?>{
          'other.plugin.value': 'must-remain',
        });
        final store = SharedPreferencesPreferenceStore(
          preferencesFactory: () => backend,
        );

        await store.clear();

        expect(backend.values['other.plugin.value'], 'must-remain');
        expect(backend.clearCallCount, 0);
      },
    );

    test('maps read, write, delete and clear plugin failures', () async {
      final backend = _FakeSharedPreferencesAsync(<String, Object?>{
        '${SharedPreferencesPreferenceStore.namespacePrefix}feed.page_size': 20,
      });
      final store = SharedPreferencesPreferenceStore(
        preferencesFactory: () => backend,
      );
      final key = PreferenceKey('feed.page_size');

      backend.failingMethods.add('getInt');
      await expectLater(
        store.readInt(key, defaultValue: 10),
        throwsA(isA<StorageReadError>()),
      );
      backend.failingMethods.clear();

      backend.failingMethods.add('setInt');
      await expectLater(
        store.writeInt(key, 30),
        throwsA(isA<StorageWriteError>()),
      );
      backend.failingMethods.clear();

      backend.failingMethods.add('remove');
      await expectLater(store.remove(key), throwsA(isA<StorageDeleteError>()));
      backend.failingMethods.clear();

      backend.failingMethods.add('clear');
      await expectLater(store.clear(), throwsA(isA<StorageClearError>()));
    });

    test('rejects non-finite doubles before reaching the plugin', () async {
      final backend = _FakeSharedPreferencesAsync();
      final store = SharedPreferencesPreferenceStore(
        preferencesFactory: () => backend,
      );

      await expectLater(
        store.writeDouble(PreferenceKey('reader.text_scale'), double.infinity),
        throwsA(isA<ArgumentError>()),
      );
      expect(backend.invocations, isEmpty);
    });

    test('rejects non-finite doubles read from platform storage', () async {
      const prefix = SharedPreferencesPreferenceStore.namespacePrefix;
      final backend = _FakeSharedPreferencesAsync();
      final store = SharedPreferencesPreferenceStore(
        preferencesFactory: () => backend,
      );
      final key = PreferenceKey('reader.text_scale');

      for (final value in <double>[
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        backend.values['${prefix}reader.text_scale'] = value;

        await expectLater(
          store.readDouble(key, defaultValue: 1),
          throwsA(isA<StorageReadError>()),
          reason: value.toString(),
        );
      }
    });
  });
}

final class _FakeSharedPreferencesAsync implements SharedPreferencesAsync {
  _FakeSharedPreferencesAsync([Map<String, Object?> initialValues = const {}])
    : values = Map<String, Object?>.of(initialValues);

  final Map<String, Object?> values;
  final Set<String> failingMethods = <String>{};
  final List<String> invocations = <String>[];
  final _FakeInvocationState _state = _FakeInvocationState();

  Set<String>? get lastClearAllowList => _state.lastClearAllowList;

  int get clearCallCount => _state.clearCallCount;

  void _before(String method) {
    invocations.add(method);
    if (failingMethods.contains(method)) {
      throw StateError('private-shared-preferences-plugin-detail');
    }
  }

  @override
  Future<Set<String>> getKeys({Set<String>? allowList}) async {
    _before('getKeys');
    return values.keys.where((key) => allowList?.contains(key) ?? true).toSet();
  }

  @override
  Future<Map<String, Object?>> getAll({Set<String>? allowList}) async {
    _before('getAll');
    return <String, Object?>{
      for (final entry in values.entries)
        if (allowList?.contains(entry.key) ?? true) entry.key: entry.value,
    };
  }

  @override
  Future<bool?> getBool(String key) async {
    _before('getBool');
    return values[key] as bool?;
  }

  @override
  Future<int?> getInt(String key) async {
    _before('getInt');
    return values[key] as int?;
  }

  @override
  Future<double?> getDouble(String key) async {
    _before('getDouble');
    return values[key] as double?;
  }

  @override
  Future<String?> getString(String key) async {
    _before('getString');
    return values[key] as String?;
  }

  @override
  Future<List<String>?> getStringList(String key) async {
    _before('getStringList');
    return values[key] as List<String>?;
  }

  @override
  Future<bool> containsKey(String key) async {
    _before('containsKey');
    return values.containsKey(key);
  }

  @override
  Future<void> setBool(String key, bool value) async {
    _before('setBool');
    values[key] = value;
  }

  @override
  Future<void> setInt(String key, int value) async {
    _before('setInt');
    values[key] = value;
  }

  @override
  Future<void> setDouble(String key, double value) async {
    _before('setDouble');
    values[key] = value;
  }

  @override
  Future<void> setString(String key, String value) async {
    _before('setString');
    values[key] = value;
  }

  @override
  Future<void> setStringList(String key, List<String> value) async {
    _before('setStringList');
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    _before('remove');
    values.remove(key);
  }

  @override
  Future<void> clear({Set<String>? allowList}) async {
    _before('clear');
    _state.clearCallCount += 1;
    _state.lastClearAllowList =
        allowList == null ? null : Set<String>.of(allowList);
    if (allowList == null) {
      values.clear();
      return;
    }
    for (final key in allowList) {
      values.remove(key);
    }
  }
}

final class _FakeInvocationState {
  Set<String>? lastClearAllowList;
  int clearCallCount = 0;
}
