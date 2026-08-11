import 'package:flutter_template/app/localization/app_locale.dart';
import 'package:flutter_template/app/localization/app_locale_persistence.dart';
import 'package:flutter_template/core/error/app_error.dart';
import 'package:flutter_template/core/storage/preference_key.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/storage/in_memory_preference_store.dart';

void main() {
  final localeKey = PreferenceKey('appearance.locale');

  test('loads, saves, and removes explicit locale preferences', () async {
    final store = InMemoryPreferenceStore();
    final persistence = PreferenceStoreAppLocalePersistence(store);

    expect(await persistence.load(), AppLocalePreference.system);

    await persistence.save(AppLocalePreference.chinese);
    expect(await persistence.load(), AppLocalePreference.chinese);
    expect(await store.readString(localeKey, defaultValue: 'missing'), 'zh');

    await persistence.save(AppLocalePreference.system);
    expect(await persistence.load(), AppLocalePreference.system);
    expect(
      await store.readString(localeKey, defaultValue: 'missing'),
      'missing',
    );
  });

  test(
    'treats an obsolete stored locale as a recoverable preference',
    () async {
      final store = InMemoryPreferenceStore(
        initialValues: <PreferenceKey, Object>{localeKey: 'fr-CA'},
      );
      final persistence = PreferenceStoreAppLocalePersistence(store);

      expect(await persistence.load(), AppLocalePreference.system);
    },
  );

  test(
    'unavailable production storage never reports a saved selection',
    () async {
      const persistence = UnavailableAppLocalePreferencePersistence();

      expect(await persistence.load(), AppLocalePreference.system);
      expect(
        () => persistence.save(AppLocalePreference.chinese),
        throwsA(isA<StorageWriteError>()),
      );
    },
  );
}
