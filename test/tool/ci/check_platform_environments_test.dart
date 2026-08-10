import 'package:flutter_test/flutter_test.dart';

import '../../../tool/ci/check_platform_environments.dart';

void main() {
  group('validatePlatformEnvironments', () {
    test('accepts one complete and aligned three-environment contract', () {
      final List<String> violations = validatePlatformEnvironments(
        _validFiles(),
      );

      expect(violations, isEmpty);
    });

    test('reports Android and iOS values that drift from Dart', () {
      final Map<String, String> files = _validFiles();
      files['android/app/build.gradle.kts'] =
          files['android/app/build.gradle.kts']!.replaceFirst(
            'applicationIdSuffix = ".dev"',
            '.debug',
          );
      files['ios/Runner.xcodeproj/project.pbxproj'] =
          files['ios/Runner.xcodeproj/project.pbxproj']!.replaceFirst(
            'APP_DISPLAY_NAME = "Flutter Template Staging";',
            'APP_DISPLAY_NAME = "Staging Drift";',
          );

      final List<String> violations = validatePlatformEnvironments(files);

      expect(
        violations.map((String violation) => violation.split(' ').first),
        containsAll(<String>{
          '[PLATFORM_ANDROID_FLAVOR]',
          '[PLATFORM_IOS_CONFIG]',
        }),
      );
    });

    test('reports a missing flavor scheme and a generic fallback', () {
      final Map<String, String> files =
          _validFiles()
            ..remove(
              'ios/Runner.xcodeproj/xcshareddata/xcschemes/prod.xcscheme',
            )
            ..['ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme'] =
                '<Scheme />';
      files['ios/Podfile'] = files['ios/Podfile']!.replaceFirst(
        "'Release-prod' => :release,",
        '',
      );

      final List<String> violations = validatePlatformEnvironments(files);

      expect(
        violations.map((String violation) => violation.split(' ').first),
        containsAll(<String>{
          '[PLATFORM_IOS_PODFILE]',
          '[PLATFORM_IOS_SCHEME]',
          '[PLATFORM_MISSING_FILE]',
        }),
      );
    });

    test('rejects release builds that silently use the debug key', () {
      final Map<String, String> files = _validFiles();
      files['android/app/build.gradle.kts'] =
          '${files['android/app/build.gradle.kts']}\n'
          'signingConfig = signingConfigs.getByName("debug")';

      final List<String> violations = validatePlatformEnvironments(files);

      expect(violations, contains(contains('[PLATFORM_ANDROID_SIGNING]')));
    });

    test('rejects a main manifest without release network access', () {
      final Map<String, String> files = _validFiles();
      files['android/app/src/main/AndroidManifest.xml'] =
          files['android/app/src/main/AndroidManifest.xml']!.replaceFirst(
            '<uses-permission android:name="android.permission.INTERNET" />',
            '',
          );

      final List<String> violations = validatePlatformEnvironments(files);

      expect(
        violations,
        contains(contains('[PLATFORM_ANDROID_NETWORK_PERMISSION]')),
      );
    });

    test('rejects weakened Android backup and iOS Keychain boundaries', () {
      final Map<String, String> files = _validFiles();
      files['android/app/src/main/AndroidManifest.xml'] =
          files['android/app/src/main/AndroidManifest.xml']!.replaceFirst(
            'android:allowBackup="false"',
            'android:allowBackup="true"',
          );
      files['ios/Runner/Runner.entitlements'] =
          files['ios/Runner/Runner.entitlements']!.replaceFirst(
            '<key>keychain-access-groups</key>',
            '<key>unrelated-capability</key>',
          );

      final List<String> violations = validatePlatformEnvironments(files);

      expect(
        violations.map((String violation) => violation.split(' ').first),
        containsAll(<String>{
          '[PLATFORM_ANDROID_STORAGE_SECURITY]',
          '[PLATFORM_IOS_STORAGE_SECURITY]',
        }),
      );
    });

    test('rejects an environment-independent Android AAB entrypoint', () {
      final Map<String, String> files = _validFiles();
      files['android/app/build.gradle.kts'] =
          files['android/app/build.gradle.kts']!.replaceFirst(
            '"bundleRelease"',
            '"bundleCandidate"',
          );

      final List<String> violations = validatePlatformEnvironments(files);

      expect(violations, contains(contains('[PLATFORM_ANDROID_ENTRYPOINT]')));
    });

    test('rejects an Android guard that runs after flavor dependencies', () {
      final Map<String, String> files = _validFiles();
      files['android/app/build.gradle.kts'] =
          files['android/app/build.gradle.kts']!.replaceFirst(
            '''
val requestedEnvironmentlessBuildTask =
    gradle.startParameter.taskNames
        .asSequence()
        .map { it.substringAfterLast(':') }
        .firstOrNull { it in environmentlessBuildTasks }
if (requestedEnvironmentlessBuildTask != null) {
  throw GradleException("An environment flavor is required.")
}
''',
            '''
tasks.matching { it.name in environmentlessBuildTasks }.configureEach {
  doFirst {
    throw GradleException("An environment flavor is required.")
  }
}
''',
          );

      final List<String> violations = validatePlatformEnvironments(files);

      expect(violations, contains(contains('[PLATFORM_ANDROID_ENTRYPOINT]')));
    });

    test('rejects a CocoaPods include for the wrong Xcode configuration', () {
      final Map<String, String> files = _validFiles();
      files['ios/Flutter/Profile-staging.xcconfig'] =
          files['ios/Flutter/Profile-staging.xcconfig']!.replaceFirst(
            'Pods-Runner.profile-staging.xcconfig',
            'Pods-Runner.release.xcconfig',
          );

      final List<String> violations = validatePlatformEnvironments(files);

      expect(violations, contains(contains('[PLATFORM_IOS_COCOAPODS]')));
    });
  });
}

Map<String, String> _validFiles() {
  final Map<String, String> files = <String, String>{
    'lib/app/config/app_config.dart': '''
factory AppConfig.fromDartDefines({String? nativeFlavor = appFlavor}) {}
if (nativeFlavor != environment.name) {}
AppEnvironment.dev => (
  appName: 'Flutter Template Dev',
  packageNameSuffix: '.dev',
),
AppEnvironment.staging => (
  appName: 'Flutter Template Staging',
  packageNameSuffix: '.staging',
),
AppEnvironment.prod => (
  appName: 'Flutter Template',
  packageNameSuffix: '',
),
''',
    'config/dev.example.json':
        '{"APP_ENV":"dev","API_BASE_URL":"https://dev.invalid/"}',
    'config/staging.example.json':
        '{"APP_ENV":"staging","API_BASE_URL":"https://staging.invalid/"}',
    'config/prod.example.json':
        '{"APP_ENV":"prod","API_BASE_URL":"https://prod.invalid/"}',
    'android/app/build.gradle.kts': _validAndroidGradle(),
    'android/app/src/main/AndroidManifest.xml': '''
<uses-permission android:name="android.permission.INTERNET" />
<application
  android:label="@string/app_name"
  android:allowBackup="false">
  <meta-data
    android:name="com.example.flutter_template.APP_ENV"
    android:value="@string/app_environment" />
</application>
''',
    'ios/Flutter/Debug.xcconfig': '''
#include "Generated.xcconfig"
CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements
''',
    'ios/Flutter/Release.xcconfig': '''
#include "Generated.xcconfig"
CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements
''',
    'ios/Podfile': _validPodfile(),
    'ios/Runner/Info.plist': r'''
<string>$(APP_DISPLAY_NAME)</string>
<key>AppEnvironment</key>
<string>$(APP_ENV)</string>
''',
    'ios/Runner/Runner.entitlements': '''
<key>keychain-access-groups</key>
<array/>
''',
    'ios/Runner.xcodeproj/project.pbxproj': _validXcodeProject(),
    'ios/Runner.xcworkspace/contents.xcworkspacedata':
        'group:Pods/Pods.xcodeproj',
  };

  for (final String environment in const <String>['dev', 'staging', 'prod']) {
    files['ios/Runner.xcodeproj/xcshareddata/xcschemes/$environment.xcscheme'] =
        _validScheme(environment);
    for (final String mode in const <String>['Debug', 'Profile', 'Release']) {
      files['ios/Flutter/$mode-$environment.xcconfig'] = '''
#include? "Pods/Target Support Files/Pods-Runner/Pods-Runner.${mode.toLowerCase()}-$environment.xcconfig"
#include "${mode == 'Debug' ? 'Debug' : 'Release'}.xcconfig"
''';
    }
  }
  return files;
}

String _validAndroidGradle() {
  return '''
android {
  flavorDimensions += "environment"
  productFlavors {
    create("dev") {
      dimension = "environment"
      applicationIdSuffix = ".dev"
      resValue("string", "app_name", "Flutter Template Dev")
      resValue("string", "app_environment", "dev")
    }
    create("staging") {
      dimension = "environment"
      applicationIdSuffix = ".staging"
      resValue("string", "app_name", "Flutter Template Staging")
      resValue("string", "app_environment", "staging")
    }
    create("prod") {
      dimension = "environment"
      resValue("string", "app_name", "Flutter Template")
      resValue("string", "app_environment", "prod")
    }
  }
}
val environmentlessBuildTasks = setOf(
  "assembleDebug",
  "assembleProfile",
  "assembleRelease",
  "bundleDebug",
  "bundleProfile",
  "bundleRelease",
)
val requestedEnvironmentlessBuildTask =
    gradle.startParameter.taskNames
        .asSequence()
        .map { it.substringAfterLast(':') }
        .firstOrNull { it in environmentlessBuildTasks }
if (requestedEnvironmentlessBuildTask != null) {
  throw GradleException("An environment flavor is required.")
}
''';
}

String _validPodfile() {
  final StringBuffer result = StringBuffer();
  for (final String environment in const <String>['dev', 'staging', 'prod']) {
    for (final String mode in const <String>['Debug', 'Profile', 'Release']) {
      result.writeln(
        "'$mode-$environment' => :${mode == 'Debug' ? 'debug' : 'release'},",
      );
    }
  }
  return result.toString();
}

String _validXcodeProject() {
  const Map<String, ({String displayName, String suffix})> contracts =
      <String, ({String displayName, String suffix})>{
        'dev': (displayName: 'Flutter Template Dev', suffix: '.dev'),
        'staging': (
          displayName: 'Flutter Template Staging',
          suffix: '.staging',
        ),
        'prod': (displayName: 'Flutter Template', suffix: ''),
      };
  final StringBuffer definitions = StringBuffer();
  final StringBuffer references = StringBuffer();
  int id = 1;

  for (final MapEntry<String, ({String displayName, String suffix})> entry
      in contracts.entries) {
    for (final String mode in const <String>['Debug', 'Profile', 'Release']) {
      final String configuration = '$mode-${entry.key}';
      for (final String owner in const <String>['project', 'app', 'test']) {
        final String objectId = id
            .toRadixString(16)
            .toUpperCase()
            .padLeft(24, '0');
        id += 1;
        definitions
          ..writeln('$objectId /* $configuration */ = {')
          ..writeln('  isa = XCBuildConfiguration;');
        if (owner == 'app') {
          definitions.writeln(
            '  baseConfigurationReference = 000000000000000000000000 '
            '/* $configuration.xcconfig */;',
          );
        }
        definitions.writeln('  buildSettings = {');
        if (owner == 'app') {
          definitions
            ..writeln('    APP_ENV = ${entry.key};')
            ..writeln('    APP_DISPLAY_NAME = "${entry.value.displayName}";')
            ..writeln('    INFOPLIST_FILE = Runner/Info.plist;')
            ..writeln(
              '    PRODUCT_BUNDLE_IDENTIFIER = '
              'com.example.flutterTemplate${entry.value.suffix};',
            );
        } else if (owner == 'test') {
          definitions
            ..writeln('    TEST_HOST = Runner;')
            ..writeln(
              '    PRODUCT_BUNDLE_IDENTIFIER = '
              'com.example.flutterTemplate${entry.value.suffix}.RunnerTests;',
            );
        }
        definitions
          ..writeln('  };')
          ..writeln('  name = "$configuration";')
          ..writeln('};');
        references.writeln('$objectId,');
      }
    }
  }

  return '''
$definitions
$references
defaultConfigurationName = "Release-prod";
defaultConfigurationName = "Release-prod";
defaultConfigurationName = "Release-prod";
''';
}

String _validScheme(String environment) {
  return '''
<Scheme>
  <TestAction buildConfiguration = "Debug-$environment" />
  <LaunchAction buildConfiguration = "Debug-$environment" />
  <ProfileAction buildConfiguration = "Profile-$environment" />
  <AnalyzeAction buildConfiguration = "Debug-$environment" />
  <ArchiveAction buildConfiguration = "Release-$environment" />
  <BuildableReference BlueprintName = "Runner" />
  <BuildableReference BlueprintName = "RunnerTests" />
</Scheme>
''';
}
