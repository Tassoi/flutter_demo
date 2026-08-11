import 'package:flutter_template/app/localization/app_localizations.dart';
import 'package:flutter_template/app/localization/generated/app_localizations_en.dart';
import 'package:flutter_template/app/localization/generated/app_localizations_zh.dart';
import 'package:flutter_template/core/error/app_error.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('zh');
  });

  test('formats plurals, numbers, and dates with each instance locale', () {
    final previousDefaultLocale = Intl.defaultLocale;
    addTearDown(() {
      Intl.defaultLocale = previousDefaultLocale;
    });
    Intl.defaultLocale = 'fr';
    final english = AppLocalizationsEn();
    final chinese = AppLocalizationsZh();
    final date = DateTime(2026, 7, 14);

    expect(english.exampleItemCount(count: 0), 'No example items');
    expect(english.exampleItemCount(count: 1), '1 example item');
    expect(english.exampleItemCount(count: 2), '2 example items');
    expect(chinese.exampleItemCount(count: 0), '0 个示例条目');
    expect(chinese.exampleItemCount(count: 2), '2 个示例条目');
    expect(english.exampleItemIdentifier(itemId: 12345), 'Item #12,345');
    expect(chinese.exampleItemIdentifier(itemId: 12345), '条目编号：12,345');
    expect(english.exampleUpdatedOn(date: date), 'Updated Jul 14, 2026');
    expect(chinese.exampleUpdatedOn(date: date), '更新于 2026年7月14日');
  });

  test(
    'maps every stable application error code without using its fallback',
    () {
      final localizations = AppLocalizationsZh();
      final errors = <AppError>[
        const AppConfigurationError.invalid(),
        const AppConfigurationError.unavailable(),
        const StorageInitializationError(),
        const StorageReadError(),
        const StorageWriteError(),
        const StorageDeleteError(),
        const StorageClearError(),
        const NetworkConnectionError(),
        const NetworkTimeoutError(),
        const NetworkCancelledError(),
        NetworkResponseError(statusCode: 503),
        const NetworkResponseParseError(),
        const NetworkCredentialsUnavailableError(),
        const UnexpectedAppError(),
      ];

      final localized = errors
          .map((AppError error) => localizeAppError(localizations, error))
          .toList(growable: false);

      expect(localized, everyElement(isNot(contains('The '))));
      expect(localized, containsAll(<String>['应用配置无效。', '无法连接服务。', '出现了问题。']));
      expect(localized, isNot(contains(errors.first.displayMessage)));
    },
  );
}
