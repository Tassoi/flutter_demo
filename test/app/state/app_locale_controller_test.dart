import 'dart:async';

import 'package:flutter_template/app/localization/app_locale.dart';
import 'package:flutter_template/app/localization/app_locale_persistence.dart';
import 'package:flutter_template/app/state/app_locale_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/state/create_test_provider_container.dart';

void main() {
  test('updates immediately and persists an explicit selection', () async {
    final persistence = _ControlledLocalePersistence();
    final container = createTestProviderContainer(
      overrides: [
        appLocalePreferencePersistenceProvider.overrideWithValue(persistence),
      ],
    );
    final controller = container.read(appLocalePreferenceProvider.notifier);

    final result = controller.setPreference(AppLocalePreference.chinese);
    expect(
      container.read(appLocalePreferenceProvider),
      AppLocalePreference.chinese,
    );

    final request = await persistence.takeRequest();
    expect(request.preference, AppLocalePreference.chinese);
    request.succeed();
    expect(await result, isTrue);
  });

  test('rolls the latest failed write back to the last saved value', () async {
    final persistence = _ControlledLocalePersistence();
    final container = createTestProviderContainer(
      overrides: [
        appInitialLocalePreferenceProvider.overrideWithValue(
          AppLocalePreference.english,
        ),
        appLocalePreferencePersistenceProvider.overrideWithValue(persistence),
      ],
    );
    final controller = container.read(appLocalePreferenceProvider.notifier);

    final result = controller.setPreference(AppLocalePreference.chinese);
    final request = await persistence.takeRequest();
    request.fail();

    expect(await result, isFalse);
    expect(
      container.read(appLocalePreferenceProvider),
      AppLocalePreference.english,
    );
  });

  test('an older failure cannot overwrite a newer queued selection', () async {
    final persistence = _ControlledLocalePersistence();
    final container = createTestProviderContainer(
      overrides: [
        appLocalePreferencePersistenceProvider.overrideWithValue(persistence),
      ],
    );
    final controller = container.read(appLocalePreferenceProvider.notifier);

    final englishResult = controller.setPreference(AppLocalePreference.english);
    final englishRequest = await persistence.takeRequest();
    final chineseResult = controller.setPreference(AppLocalePreference.chinese);
    englishRequest.fail();

    expect(await englishResult, isFalse);
    expect(
      container.read(appLocalePreferenceProvider),
      AppLocalePreference.chinese,
    );

    final chineseRequest = await persistence.takeRequest();
    expect(chineseRequest.preference, AppLocalePreference.chinese);
    chineseRequest.succeed();
    expect(await chineseResult, isTrue);
    expect(
      container.read(appLocalePreferenceProvider),
      AppLocalePreference.chinese,
    );
  });
}

final class _ControlledLocalePersistence
    implements AppLocalePreferencePersistence {
  final List<_SaveRequest> _requests = <_SaveRequest>[];
  Completer<_SaveRequest>? _requestWaiter;

  @override
  Future<AppLocalePreference> load() async => AppLocalePreference.system;

  @override
  Future<void> save(AppLocalePreference preference) {
    final request = _SaveRequest(preference);
    final waiter = _requestWaiter;
    if (waiter == null) {
      _requests.add(request);
    } else {
      _requestWaiter = null;
      waiter.complete(request);
    }
    return request.completion.future;
  }

  Future<_SaveRequest> takeRequest() {
    if (_requests.isNotEmpty) {
      return Future<_SaveRequest>.value(_requests.removeAt(0));
    }
    if (_requestWaiter != null) {
      throw StateError('Only one request waiter is supported.');
    }
    _requestWaiter = Completer<_SaveRequest>();
    return _requestWaiter!.future;
  }
}

final class _SaveRequest {
  _SaveRequest(this.preference);

  final AppLocalePreference preference;
  final Completer<void> completion = Completer<void>();

  void succeed() {
    completion.complete();
  }

  void fail() {
    completion.completeError(StateError('controlled locale write failure'));
  }
}
