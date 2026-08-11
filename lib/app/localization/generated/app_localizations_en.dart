/// 此文件由 `dart run tool/generate_localizations.dart` 基于 ARB 资源生成。
/// 请勿手工修改；更新 `lib/app/localization/arb/` 后重新运行生成命令。

// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// 英语（`en`）文案实现。
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get applicationUnavailableTitle => 'Application unavailable';

  @override
  String get applicationStartupFailedMessage =>
      'The application could not start.';

  @override
  String get applicationStartupFailedSemantics => 'Application startup failed';

  @override
  String get unableToRenderContent => 'Unable to render this content.';

  @override
  String get languageMenuTooltip => 'Change language';

  @override
  String get languageFollowSystem => 'Follow system';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageChinese => 'Chinese';

  @override
  String get languagePreferenceSaveFailed =>
      'Language preference could not be saved.';

  @override
  String get openProtectedArea => 'Open protected area';

  @override
  String get authSignInTitle => 'Sign in';

  @override
  String get authIdentifierLabel => 'Account';

  @override
  String get authPasswordLabel => 'Password';

  @override
  String get authIdentifierRequired => 'Enter your account.';

  @override
  String get authPasswordRequired => 'Enter your password.';

  @override
  String get authShowPassword => 'Show password';

  @override
  String get authHidePassword => 'Hide password';

  @override
  String get authSubmitSignIn => 'Sign in';

  @override
  String get authSessionLoading => 'Restoring session';

  @override
  String get authAccountTitle => 'Protected area';

  @override
  String get authSessionActive => 'Your session is active.';

  @override
  String get authSignOut => 'Sign out';

  @override
  String get authFailureUnavailable => 'The sign-in service is unavailable.';

  @override
  String get authFailureRejected => 'The account or password was not accepted.';

  @override
  String get authFailureSessionExpired =>
      'Your session expired. Sign in again.';

  @override
  String get authFailurePersistence => 'Secure session storage is unavailable.';

  @override
  String get authFailureUnexpected => 'Sign-in could not be completed.';

  @override
  String get openExampleDetail => 'Open example detail';

  @override
  String get invalidExampleLinkTitle => 'Invalid example link';

  @override
  String get invalidExampleLinkMessage =>
      'This example item link cannot be opened.';

  @override
  String get pageNotFoundTitle => 'Page not found';

  @override
  String get pageNotFoundMessage => 'The requested page is unavailable.';

  @override
  String get returnHome => 'Return home';

  @override
  String get exampleDetailLoading => 'Loading example item';

  @override
  String get exampleDetailErrorTitle => 'Unable to load item';

  @override
  String get tryAgain => 'Try again';

  @override
  String get exampleItemUnavailableTitle => 'Item unavailable';

  @override
  String get exampleItemUnavailableMessage =>
      'No example item exists for this link.';

  @override
  String get backToHome => 'Back to home';

  @override
  String get back => 'Back';

  @override
  String get exampleDetailTitle => 'Example detail';

  @override
  String exampleItemIdentifier({required int itemId}) {
    final intl.NumberFormat itemIdNumberFormat = intl
        .NumberFormat.decimalPattern(localeName);
    final String itemIdString = itemIdNumberFormat.format(itemId);

    return 'Item #$itemIdString';
  }

  @override
  String exampleItemCount({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count example items',
      one: '1 example item',
      zero: 'No example items',
    );
    return '$_temp0';
  }

  @override
  String exampleUpdatedOn({required DateTime date}) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'Updated $dateString';
  }

  @override
  String get errorConfigurationInvalid =>
      'The application configuration is invalid.';

  @override
  String get errorConfigurationUnavailable =>
      'The application configuration is unavailable.';

  @override
  String get errorStorageUnavailable => 'Local storage is unavailable.';

  @override
  String get errorStorageRead => 'Local data could not be read.';

  @override
  String get errorStorageWrite => 'Local data could not be saved.';

  @override
  String get errorStorageDelete => 'Local data could not be removed.';

  @override
  String get errorStorageClear => 'Local data could not be cleared.';

  @override
  String get errorNetworkConnection => 'Unable to connect to the service.';

  @override
  String get errorNetworkTimeout => 'The request took too long.';

  @override
  String get errorNetworkCancelled => 'The request was cancelled.';

  @override
  String get errorNetworkResponse =>
      'The service could not complete the request.';

  @override
  String get errorNetworkParse =>
      'The service returned an unexpected response.';

  @override
  String get errorCredentialsUnavailable =>
      'Credentials are unavailable for this request.';

  @override
  String get errorUnexpected => 'Something went wrong.';
}
