import 'package:flutter/widgets.dart';
import 'package:flutter_template/app/localization/app_locale.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppLocalePreference', () {
    test('maps explicit selections without inventing region variants', () {
      expect(AppLocalePreference.system.explicitLocale, isNull);
      expect(AppLocalePreference.english.explicitLocale, const Locale('en'));
      expect(AppLocalePreference.chinese.explicitLocale, const Locale('zh'));
      expect(AppLocalePreference.english.storageValue, 'en');
      expect(AppLocalePreference.chinese.storageValue, 'zh');
    });

    test('falls back safely for missing or obsolete stored values', () {
      expect(parseStoredAppLocalePreference('en'), AppLocalePreference.english);
      expect(parseStoredAppLocalePreference('zh'), AppLocalePreference.chinese);
      expect(
        parseStoredAppLocalePreference('system'),
        AppLocalePreference.system,
      );
      expect(
        parseStoredAppLocalePreference('unsupported-region'),
        AppLocalePreference.system,
      );
    });
  });

  group('resolveAppLocale', () {
    const List<Locale> supported = <Locale>[Locale('en'), Locale('zh')];

    test('matches supported language codes in device priority order', () {
      const requested = <Locale>[Locale('fr'), Locale('zh', 'TW')];

      expect(resolveAppLocale(requested, supported), const Locale('zh'));
      expect(
        resolveAppLocale(const <Locale>[Locale('en', 'US')], supported),
        const Locale('en'),
      );
    });

    test('uses English for null, empty, or unsupported locale lists', () {
      expect(resolveAppLocale(null, supported), const Locale('en'));
      expect(resolveAppLocale(const <Locale>[], supported), const Locale('en'));
      expect(
        resolveAppLocale(const <Locale>[Locale('ar')], supported),
        const Locale('en'),
      );
    });
  });
}
