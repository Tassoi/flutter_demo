import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

const Map<String, ({String displayName, String suffix})> _environmentContracts =
    <String, ({String displayName, String suffix})>{
      'dev': (displayName: 'Flutter Template Dev', suffix: '.dev'),
      'staging': (displayName: 'Flutter Template Staging', suffix: '.staging'),
      'prod': (displayName: 'Flutter Template', suffix: ''),
    };

const List<String> _requiredPaths = <String>[
  'pubspec.yaml',
  'lib/app/config/app_config.dart',
  'config/dev.example.json',
  'config/staging.example.json',
  'config/prod.example.json',
  'android/app/build.gradle.kts',
  'android/app/src/main/AndroidManifest.xml',
  'android/app/src/main/res/drawable/launch_background.xml',
  'android/app/src/main/res/drawable-v21/launch_background.xml',
  'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
  'android/app/src/main/res/values-v31/styles.xml',
  'android/app/src/main/res/values-night-v31/styles.xml',
  'ios/Flutter/Debug.xcconfig',
  'ios/Flutter/Release.xcconfig',
  'ios/Flutter/Debug-dev.xcconfig',
  'ios/Flutter/Profile-dev.xcconfig',
  'ios/Flutter/Release-dev.xcconfig',
  'ios/Flutter/Debug-staging.xcconfig',
  'ios/Flutter/Profile-staging.xcconfig',
  'ios/Flutter/Release-staging.xcconfig',
  'ios/Flutter/Debug-prod.xcconfig',
  'ios/Flutter/Profile-prod.xcconfig',
  'ios/Flutter/Release-prod.xcconfig',
  'ios/Podfile',
  'ios/Runner/Info.plist',
  'ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json',
  'ios/Runner/Assets.xcassets/LaunchBackground.imageset/Contents.json',
  'ios/Runner/Assets.xcassets/LaunchImage.imageset/Contents.json',
  'ios/Runner/Base.lproj/LaunchScreen.storyboard',
  'ios/Runner/Runner.entitlements',
  'ios/Runner.xcodeproj/project.pbxproj',
  'ios/Runner.xcodeproj/xcshareddata/xcschemes/dev.xcscheme',
  'ios/Runner.xcodeproj/xcshareddata/xcschemes/staging.xcscheme',
  'ios/Runner.xcodeproj/xcshareddata/xcschemes/prod.xcscheme',
  'ios/Runner.xcworkspace/contents.xcworkspacedata',
];

/// 核对 Dart、Android 与 iOS 是否实现同一套三环境契约。
///
/// [files] 的键是使用 `/` 分隔的项目相对路径，值是文件内容。检查器只理解本脚手架
/// 明确维护的 Gradle、PBX、scheme、Podfile 和 plist 形状，不试图成为通用构建文件
/// 解析器。返回值按规则编号和路径排序，保证本地与 CI 的诊断顺序可复现。
///
/// 本函数不访问文件系统，也不会生成或修改平台工程；CLI 读取固定文件后调用它，测试
/// 则可以用内存夹具覆盖正常、漂移和缺失配置行为。
List<String> validatePlatformEnvironments(Map<String, String> files) {
  final List<String> violations = <String>[];

  for (final String path in _requiredPaths) {
    if (!files.containsKey(path)) {
      violations.add('[PLATFORM_MISSING_FILE] $path 缺少必需的环境配置文件。');
    }
  }

  final String? pubspec = files['pubspec.yaml'];
  if (pubspec != null) {
    _validateFlutterFontRegistration(pubspec, violations);
  }

  final String? dartConfig = files['lib/app/config/app_config.dart'];
  if (dartConfig != null) {
    _validateDartConfig(dartConfig, violations);
  }
  _validateExampleConfigs(files, violations);
  _validateBrandingResources(files, violations);

  final String? androidGradle = files['android/app/build.gradle.kts'];
  if (androidGradle != null) {
    _validateAndroidGradle(androidGradle, violations);
  }
  final String? androidManifest =
      files['android/app/src/main/AndroidManifest.xml'];
  if (androidManifest != null) {
    _validateAndroidManifest(androidManifest, violations);
  }

  final String? xcodeProject = files['ios/Runner.xcodeproj/project.pbxproj'];
  if (xcodeProject != null) {
    _validateXcodeProject(xcodeProject, violations);
  }
  _validateSchemes(files, violations);

  final String? podfile = files['ios/Podfile'];
  if (podfile != null) {
    _validatePodfile(podfile, violations);
  }
  _validateIosSupportFiles(files, violations);

  if (files.containsKey(
    'ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme',
  )) {
    violations.add(
      '[PLATFORM_IOS_SCHEME] '
      'ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme '
      '不得保留绕过环境选择的通用 scheme。',
    );
  }

  violations.sort();
  return violations;
}

void _validateFlutterFontRegistration(String content, List<String> violations) {
  try {
    final Object? document = loadYaml(content);
    final Object? flutter = document is YamlMap ? document['flutter'] : null;
    final Object? fonts = flutter is YamlMap ? flutter['fonts'] : null;
    final List<YamlMap> matching =
        fonts is YamlList
            ? fonts
                .whereType<YamlMap>()
                .where((YamlMap entry) => entry['family'] == 'TemplateIcons')
                .toList()
            : <YamlMap>[];
    final Object? entries =
        matching.length == 1 ? matching.single['fonts'] : null;
    final bool valid =
        entries is YamlList &&
        entries.length == 1 &&
        entries.single is YamlMap &&
        (entries.single as YamlMap)['asset'] ==
            'assets/fonts/template_icons.otf';
    if (!valid) {
      violations.add(
        '[PLATFORM_FLUTTER_ICON_FONT] pubspec.yaml 必须为 Android/iOS '
        '注册固定 TemplateIcons OTF。',
      );
    }
  } on Object {
    violations.add('[PLATFORM_FLUTTER_ICON_FONT] pubspec.yaml 无法解析固定字体注册。');
  }
}

/// 从项目根目录读取固定配置并执行原生环境一致性检查。
///
/// 可选参数 `--root <path>` 只改变读取根目录。命令不会调用 Flutter、Gradle、Xcode 或
/// CocoaPods，也不会写入文件；检查失败返回非零退出码。
void main(List<String> arguments) {
  late final Directory projectRoot;
  try {
    projectRoot = _resolveProjectRoot(arguments);
  } on FormatException catch (error) {
    stderr.writeln('原生环境检查参数错误：${error.message}');
    stderr.writeln(
      '用法：dart tool/ci/check_platform_environments.dart [--root <path>]',
    );
    exitCode = 64;
    return;
  }

  final Map<String, String> files = <String, String>{};
  for (final String relativePath in _requiredPaths) {
    final File file = File(_joinPath(projectRoot.path, relativePath));
    if (_isRegularFile(file)) {
      files[relativePath] = file.readAsStringSync();
    }
  }

  const String genericSchemePath =
      'ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme';
  final File genericScheme = File(
    _joinPath(projectRoot.path, genericSchemePath),
  );
  if (_isRegularFile(genericScheme)) {
    files[genericSchemePath] = genericScheme.readAsStringSync();
  }

  final List<String> violations = validatePlatformEnvironments(files);
  if (violations.isNotEmpty) {
    stderr.writeln('原生环境配置检查失败，共 ${violations.length} 项：');
    for (final String violation in violations) {
      stderr.writeln('- $violation');
    }
    exitCode = 1;
    return;
  }

  stdout.writeln(
    '原生环境配置检查通过，共核对 '
    '${_environmentContracts.length} 个环境和 ${_requiredPaths.length} 个文件。',
  );
}

void _validateDartConfig(String content, List<String> violations) {
  if (!content.contains(
        'factory AppConfig.fromDartDefines({String? nativeFlavor = appFlavor})',
      ) ||
      !content.contains('nativeFlavor != environment.name')) {
    violations.add(
      '[PLATFORM_DART_CONTRACT] lib/app/config/app_config.dart '
      '缺少 flavor 与 APP_ENV 的启动期精确比对。',
    );
  }

  for (final MapEntry<String, ({String displayName, String suffix})> entry
      in _environmentContracts.entries) {
    final RegExpMatch? match = RegExp(
      'AppEnvironment\\.${RegExp.escape(entry.key)}\\s*=>\\s*\\('
      r'([\s\S]*?)\n\s*\),',
    ).firstMatch(content);
    final String? block = match?.group(1);
    if (block == null ||
        !block.contains("appName: '${entry.value.displayName}'") ||
        !block.contains("packageNameSuffix: '${entry.value.suffix}'")) {
      violations.add(
        '[PLATFORM_DART_CONTRACT] lib/app/config/app_config.dart '
        '${entry.key} 的展示名或包名后缀与平台契约不一致。',
      );
    }
  }
}

void _validateExampleConfigs(
  Map<String, String> files,
  List<String> violations,
) {
  for (final String environment in _environmentContracts.keys) {
    final String path = 'config/$environment.example.json';
    final String? content = files[path];
    if (content == null) {
      continue;
    }

    try {
      final Object? decoded = jsonDecode(content);
      if (decoded is! Map<String, Object?> ||
          decoded['APP_ENV'] != environment ||
          decoded['API_BASE_URL'] is! String ||
          !(decoded['API_BASE_URL']! as String).contains('.invalid')) {
        violations.add(
          '[PLATFORM_EXAMPLE_CONFIG] $path 必须选择 $environment '
          '并仅使用 .invalid 示例地址。',
        );
      }
    } on FormatException {
      violations.add('[PLATFORM_EXAMPLE_CONFIG] $path 不是合法 JSON。');
    }
  }
}

void _validateAndroidGradle(String content, List<String> violations) {
  if (!content.contains('flavorDimensions += "environment"')) {
    violations.add(
      '[PLATFORM_ANDROID_FLAVOR] android/app/build.gradle.kts '
      '缺少唯一 environment flavor 维度。',
    );
  }
  if (content.contains('signingConfigs.getByName("debug")')) {
    violations.add(
      '[PLATFORM_ANDROID_SIGNING] android/app/build.gradle.kts '
      'release 不得回退到 debug 签名。',
    );
  }
  const List<String> requiredEntrypointMarkers = <String>[
    'environmentlessBuildTasks',
    '"assembleDebug"',
    '"assembleProfile"',
    '"assembleRelease"',
    '"bundleDebug"',
    '"bundleProfile"',
    '"bundleRelease"',
    'gradle.startParameter.taskNames',
    "substringAfterLast(':')",
    '.firstOrNull { it in environmentlessBuildTasks }',
    'if (requestedEnvironmentlessBuildTask != null)',
    'throw GradleException(',
  ];
  if (!requiredEntrypointMarkers.every(content.contains)) {
    violations.add(
      '[PLATFORM_ANDROID_ENTRYPOINT] android/app/build.gradle.kts '
      '必须在依赖执行前拒绝没有显式 flavor 的聚合 APK/AAB 任务。',
    );
  }

  for (final MapEntry<String, ({String displayName, String suffix})> entry
      in _environmentContracts.entries) {
    final String? block = _extractBraceBlock(
      content: content,
      marker: 'create("${entry.key}")',
    );
    final bool suffixMatches =
        entry.value.suffix.isEmpty
            ? block != null && !block.contains('applicationIdSuffix')
            : block?.contains(
                  'applicationIdSuffix = "${entry.value.suffix}"',
                ) ??
                false;
    if (block == null ||
        !block.contains('dimension = "environment"') ||
        !suffixMatches ||
        !block.contains(
          'resValue("string", "app_name", "${entry.value.displayName}")',
        ) ||
        !block.contains(
          'resValue("string", "app_environment", "${entry.key}")',
        )) {
      violations.add(
        '[PLATFORM_ANDROID_FLAVOR] android/app/build.gradle.kts '
        '${entry.key} 的维度、后缀、展示名或环境资源不一致。',
      );
    }
  }
}

void _validateAndroidManifest(String content, List<String> violations) {
  final bool hasInternetPermission = RegExp(
    r'''<uses-permission\b[^>]*\bandroid:name\s*=\s*["']android\.permission\.INTERNET["'][^>]*/?>''',
  ).hasMatch(content);
  if (!hasInternetPermission) {
    violations.add(
      '[PLATFORM_ANDROID_NETWORK_PERMISSION] '
      'android/app/src/main/AndroidManifest.xml 必须声明 INTERNET 权限，'
      '保证 release 变体可以使用项目网络层。',
    );
  }
  if (!content.contains('android:allowBackup="false"')) {
    violations.add(
      '[PLATFORM_ANDROID_STORAGE_SECURITY] '
      'android/app/src/main/AndroidManifest.xml 必须禁用系统备份，'
      '避免恢复无法由原设备 Keystore 解密的安全存储密文。',
    );
  }
  if (_countOccurrences(content, 'android:icon="@mipmap/ic_launcher"') != 1) {
    violations.add(
      '[PLATFORM_ANDROID_BRANDING] android/app/src/main/AndroidManifest.xml '
      '必须唯一引用公共 @mipmap/ic_launcher。',
    );
  }

  const List<String> markers = <String>[
    'android:label="@string/app_name"',
    'android:name="com.example.flutter_template.APP_ENV"',
    'android:value="@string/app_environment"',
  ];
  if (!markers.every(content.contains)) {
    violations.add(
      '[PLATFORM_ANDROID_MANIFEST] android/app/src/main/AndroidManifest.xml '
      '没有通过 flavor 资源读取展示名和环境标识。',
    );
  }
}

void _validateXcodeProject(String content, List<String> violations) {
  final List<({String body, String id})> blocks =
      _extractXcodeConfigurationBlocks(content);

  for (final MapEntry<String, ({String displayName, String suffix})> entry
      in _environmentContracts.entries) {
    for (final String mode in const <String>['Debug', 'Profile', 'Release']) {
      final String configuration = '$mode-${entry.key}';
      final List<({String body, String id})> matching =
          blocks
              .where(
                (({String body, String id}) block) =>
                    block.body.contains('name = "$configuration";'),
              )
              .toList();
      if (matching.length != 3) {
        violations.add(
          '[PLATFORM_IOS_CONFIG] ios/Runner.xcodeproj/project.pbxproj '
          '$configuration 必须分别存在于 Project、Runner 和 RunnerTests。',
        );
        continue;
      }

      final List<({String body, String id})> appBlocks =
          matching
              .where(
                (({String body, String id}) block) =>
                    block.body.contains('INFOPLIST_FILE = Runner/Info.plist;'),
              )
              .toList();
      final List<({String body, String id})> testBlocks =
          matching
              .where(
                (({String body, String id}) block) =>
                    block.body.contains('TEST_HOST = '),
              )
              .toList();
      if (appBlocks.length != 1 || testBlocks.length != 1) {
        violations.add(
          '[PLATFORM_IOS_CONFIG] ios/Runner.xcodeproj/project.pbxproj '
          '$configuration 无法唯一对应 Runner 与 RunnerTests。',
        );
        continue;
      }

      final String appBlock = appBlocks.single.body;
      final String expectedBundleId =
          'com.example.flutterTemplate${entry.value.suffix}';
      final String expectedBaseConfig = '$configuration.xcconfig';
      if (!appBlock.contains('APP_ENV = ${entry.key};') ||
          !appBlock.contains(
            'APP_DISPLAY_NAME = "${entry.value.displayName}";',
          ) ||
          !appBlock.contains(
            'PRODUCT_BUNDLE_IDENTIFIER = $expectedBundleId;',
          ) ||
          !appBlock.contains('ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;') ||
          !appBlock.contains(expectedBaseConfig)) {
        violations.add(
          '[PLATFORM_IOS_CONFIG] ios/Runner.xcodeproj/project.pbxproj '
          '$configuration 的环境、展示名、bundle id、AppIcon 或基础配置不一致。',
        );
      }

      final String testBundleId = '$expectedBundleId.RunnerTests';
      if (!testBlocks.single.body.contains(
        'PRODUCT_BUNDLE_IDENTIFIER = $testBundleId;',
      )) {
        violations.add(
          '[PLATFORM_IOS_CONFIG] ios/Runner.xcodeproj/project.pbxproj '
          '$configuration 的 RunnerTests bundle id 不一致。',
        );
      }

      for (final ({String body, String id}) block in matching) {
        if (_countOccurrences(content, block.id) < 2) {
          violations.add(
            '[PLATFORM_IOS_CONFIG] ios/Runner.xcodeproj/project.pbxproj '
            '$configuration 的配置对象没有加入 configuration list。',
          );
        }
      }
    }
  }

  if (_countOccurrences(
        content,
        'defaultConfigurationName = "Release-prod";',
      ) !=
      3) {
    violations.add(
      '[PLATFORM_IOS_CONFIG] ios/Runner.xcodeproj/project.pbxproj '
      '三个 configuration list 必须使用安全的 Release-prod 默认值。',
    );
  }
  if (RegExp(r'name = (?:Debug|Profile|Release);').hasMatch(content)) {
    violations.add(
      '[PLATFORM_IOS_CONFIG] ios/Runner.xcodeproj/project.pbxproj '
      '不得保留不带环境后缀的通用 build configuration。',
    );
  }
}

void _validateBrandingResources(
  Map<String, String> files,
  List<String> violations,
) {
  final String adaptiveIcon =
      files['android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml'] ?? '';
  if (!adaptiveIcon.contains('@drawable/ic_launcher_background') ||
      !adaptiveIcon.contains('@drawable/ic_launcher_foreground') ||
      !adaptiveIcon.contains('@drawable/ic_launcher_monochrome')) {
    violations.add(
      '[PLATFORM_ANDROID_BRANDING] Adaptive Icon 必须引用公共背景、前景和单色图层。',
    );
  }

  for (final String path in <String>[
    'android/app/src/main/res/drawable/launch_background.xml',
    'android/app/src/main/res/drawable-v21/launch_background.xml',
  ]) {
    final String content = files[path] ?? '';
    if (!content.contains('@drawable/background') ||
        !content.contains('@drawable/splash')) {
      violations.add('[PLATFORM_ANDROID_BRANDING] $path 必须引用公共背景和启动 Logo。');
    }
  }
  for (final String path in <String>[
    'android/app/src/main/res/values-v31/styles.xml',
    'android/app/src/main/res/values-night-v31/styles.xml',
  ]) {
    final String content = files[path] ?? '';
    if (!content.contains('android:windowSplashScreenBackground') ||
        !content.contains('@drawable/android12splash')) {
      violations.add(
        '[PLATFORM_ANDROID_BRANDING] $path 必须引用 Android 12 公共启动资源。',
      );
    }
  }

  final String appIcon =
      files['ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json'] ??
      '';
  final String launchImage =
      files['ios/Runner/Assets.xcassets/LaunchImage.imageset/Contents.json'] ??
      '';
  final String launchBackground =
      files['ios/Runner/Assets.xcassets/LaunchBackground.imageset/Contents.json'] ??
      '';
  final String launchScreen =
      files['ios/Runner/Base.lproj/LaunchScreen.storyboard'] ?? '';
  if (!appIcon.contains('Icon-App-1024x1024@1x.png')) {
    violations.add(
      '[PLATFORM_IOS_BRANDING] AppIcon Catalog 缺少 1024 x 1024 marketing 图标。',
    );
  }
  if (!launchImage.contains('LaunchImage.png') ||
      !launchImage.contains('LaunchImage@2x.png') ||
      !launchImage.contains('LaunchImage@3x.png') ||
      !launchBackground.contains('background.png') ||
      !launchScreen.contains('image="LaunchImage"') ||
      !launchScreen.contains('image="LaunchBackground"')) {
    violations.add(
      '[PLATFORM_IOS_BRANDING] iOS LaunchScreen 必须引用公共 Logo 与背景 Catalog。',
    );
  }
}

void _validateSchemes(Map<String, String> files, List<String> violations) {
  for (final String environment in _environmentContracts.keys) {
    final String path =
        'ios/Runner.xcodeproj/xcshareddata/xcschemes/$environment.xcscheme';
    final String? content = files[path];
    if (content == null) {
      continue;
    }
    final List<String> configurations =
        RegExp(r'buildConfiguration\s*=\s*"([^"]+)"')
            .allMatches(content)
            .map((RegExpMatch match) => match.group(1)!)
            .toList();
    final List<String> expected = <String>[
      'Debug-$environment',
      'Debug-$environment',
      'Profile-$environment',
      'Debug-$environment',
      'Release-$environment',
    ];
    if (!_sameStrings(configurations, expected) ||
        !content.contains('BlueprintName = "Runner"') ||
        !content.contains('BlueprintName = "RunnerTests"')) {
      violations.add(
        '[PLATFORM_IOS_SCHEME] $path 的 Test、Run、Profile、Analyze、Archive '
        '映射或测试目标不完整。',
      );
    }
  }
}

void _validatePodfile(String content, List<String> violations) {
  for (final String environment in _environmentContracts.keys) {
    for (final String mode in const <String>['Debug', 'Profile', 'Release']) {
      final String podMode = mode == 'Debug' ? 'debug' : 'release';
      if (!content.contains("'$mode-$environment' => :$podMode,")) {
        violations.add(
          '[PLATFORM_IOS_PODFILE] ios/Podfile 缺少 '
          '$mode-$environment => :$podMode 映射。',
        );
      }
    }
  }
}

void _validateIosSupportFiles(
  Map<String, String> files,
  List<String> violations,
) {
  final String? infoPlist = files['ios/Runner/Info.plist'];
  if (infoPlist != null &&
      (!infoPlist.contains(r'<string>$(APP_DISPLAY_NAME)</string>') ||
          !infoPlist.contains('<key>AppEnvironment</key>') ||
          !infoPlist.contains(r'<string>$(APP_ENV)</string>'))) {
    violations.add(
      '[PLATFORM_IOS_PLIST] ios/Runner/Info.plist '
      '没有读取展示名或环境 build setting。',
    );
  }
  if (infoPlist != null &&
      !RegExp(
        r'<key>\s*CFBundleLocalizations\s*</key>\s*'
        r'<array>\s*<string>\s*en\s*</string>\s*'
        r'<string>\s*zh\s*</string>\s*</array>',
      ).hasMatch(infoPlist)) {
    violations.add(
      '[PLATFORM_IOS_LOCALIZATIONS] ios/Runner/Info.plist '
      '必须按 en、zh 顺序声明当前生成资源。',
    );
  }

  final String? entitlements = files['ios/Runner/Runner.entitlements'];
  if (entitlements != null &&
      !RegExp(
        r'<key>\s*keychain-access-groups\s*</key>\s*<array\s*/>',
      ).hasMatch(entitlements)) {
    violations.add(
      '[PLATFORM_IOS_STORAGE_SECURITY] ios/Runner/Runner.entitlements '
      '必须保留当前不共享、不跨设备同步的空 Keychain access group 契约。',
    );
  }

  final String? debugConfig = files['ios/Flutter/Debug.xcconfig'];
  final String? releaseConfig = files['ios/Flutter/Release.xcconfig'];
  final String? workspace =
      files['ios/Runner.xcworkspace/contents.xcworkspacedata'];
  final bool commonConfigsMatch =
      debugConfig == null ||
      releaseConfig == null ||
      (_containsFlutterCommonSettings(debugConfig) &&
          _containsFlutterCommonSettings(releaseConfig));
  bool environmentConfigsMatch = true;
  for (final String environment in _environmentContracts.keys) {
    for (final String mode in const <String>['Debug', 'Profile', 'Release']) {
      final String path = 'ios/Flutter/$mode-$environment.xcconfig';
      final String? content = files[path];
      if (content == null) {
        continue;
      }
      final String podsConfiguration = '$mode-$environment'.toLowerCase();
      final String commonConfiguration =
          mode == 'Debug' ? 'Debug.xcconfig' : 'Release.xcconfig';
      if (!content.contains(
            '#include? "Pods/Target Support Files/Pods-Runner/'
            'Pods-Runner.$podsConfiguration.xcconfig"',
          ) ||
          !content.contains('#include "$commonConfiguration"')) {
        environmentConfigsMatch = false;
      }
    }
  }
  if (!commonConfigsMatch ||
      !environmentConfigsMatch ||
      (workspace != null && !workspace.contains('group:Pods/Pods.xcodeproj'))) {
    violations.add(
      '[PLATFORM_IOS_COCOAPODS] iOS xcconfig 或 workspace '
      '缺少与完整 build configuration 对应的 CocoaPods 接线。',
    );
  }
}

bool _containsFlutterCommonSettings(String content) {
  return content.contains('#include "Generated.xcconfig"') &&
      content.contains('CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements') &&
      !content.contains('Pods-Runner.');
}

List<({String body, String id})> _extractXcodeConfigurationBlocks(
  String content,
) {
  final List<({String body, String id})> blocks =
      <({String body, String id})>[];
  final RegExp header = RegExp(
    r'([0-9A-F]{24}) /\* [^*]+ \*/ = \{\s*isa = XCBuildConfiguration;',
  );
  for (final RegExpMatch match in header.allMatches(content)) {
    final int braceStart = content.indexOf('{', match.start);
    final String? body = _extractBraceBlockAt(content, braceStart);
    if (body != null) {
      blocks.add((body: body, id: match.group(1)!));
    }
  }
  return blocks;
}

String? _extractBraceBlock({required String content, required String marker}) {
  final int markerStart = content.indexOf(marker);
  if (markerStart < 0) {
    return null;
  }
  return _extractBraceBlockAt(content, content.indexOf('{', markerStart));
}

String? _extractBraceBlockAt(String content, int braceStart) {
  if (braceStart < 0) {
    return null;
  }
  int depth = 0;
  for (int index = braceStart; index < content.length; index += 1) {
    final String character = content[index];
    if (character == '{') {
      depth += 1;
    } else if (character == '}') {
      depth -= 1;
      if (depth == 0) {
        return content.substring(braceStart, index + 1);
      }
    }
  }
  return null;
}

int _countOccurrences(String content, String value) {
  int count = 0;
  int start = 0;
  while (true) {
    final int index = content.indexOf(value, start);
    if (index < 0) {
      return count;
    }
    count += 1;
    start = index + value.length;
  }
}

bool _sameStrings(List<String> actual, List<String> expected) {
  if (actual.length != expected.length) {
    return false;
  }
  for (int index = 0; index < actual.length; index += 1) {
    if (actual[index] != expected[index]) {
      return false;
    }
  }
  return true;
}

Directory _resolveProjectRoot(List<String> arguments) {
  if (arguments.isEmpty) {
    return Directory.current.absolute;
  }
  if (arguments.length == 2 && arguments.first == '--root') {
    if (arguments.last.trim().isEmpty) {
      throw const FormatException('--root 不能为空。');
    }
    return Directory(arguments.last).absolute;
  }
  throw const FormatException('只支持可选参数 --root <path>。');
}

String _joinPath(String root, String relativePath) {
  return <String>[
    root,
    ...relativePath.split('/'),
  ].join(Platform.pathSeparator);
}

bool _isRegularFile(File file) {
  return FileSystemEntity.typeSync(file.path, followLinks: false) ==
      FileSystemEntityType.file;
}
