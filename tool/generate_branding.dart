import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_launcher_icons/config/config.dart' as launcher_config;
import 'package:flutter_launcher_icons/logger.dart';
import 'package:flutter_launcher_icons/main.dart' as launcher;
import 'package:flutter_native_splash/cli_commands.dart' as native_splash;
import 'package:image/image.dart' as image;
import 'package:xml/xml.dart';
import 'package:yaml/yaml.dart';

const String brandingDirectoryPath = 'assets/branding';
const String launcherConfigurationPath = 'flutter_launcher_icons.yaml';
const String splashConfigurationPath = 'flutter_native_splash.yaml';
const String brandingLicensePath = 'assets/branding/LICENSE.md';

const Set<String> _requiredSourceNames = <String>{
  'app_icon.png',
  'app_icon_foreground.png',
  'app_icon_background.png',
  'splash_logo.png',
};
const String _monochromeSourceName = 'app_icon_monochrome.png';
const Set<String> _allowedBrandingDirectoryNames = <String>{
  ..._requiredSourceNames,
  _monochromeSourceName,
  'LICENSE.md',
};
const Set<String> _launcherRequiredKeys = <String>{
  'android',
  'ios',
  'image_path',
  'min_sdk_android',
  'adaptive_icon_background',
  'adaptive_icon_foreground',
  'adaptive_icon_foreground_inset',
  'remove_alpha_ios',
  'background_color_ios',
};
const Set<String> _splashRequiredKeys = <String>{
  'android',
  'ios',
  'web',
  'color',
  'image',
  'fullscreen',
  'android_12',
};
const Set<String> _android12SplashKeys = <String>{
  'color',
  'icon_background_color',
  'image',
};
const List<String> _androidDensities = <String>[
  'mdpi',
  'hdpi',
  'xhdpi',
  'xxhdpi',
  'xxxhdpi',
];
const Map<String, int> _regularAndroidIconSizes = <String, int>{
  'mdpi': 48,
  'hdpi': 72,
  'xhdpi': 96,
  'xxhdpi': 144,
  'xxxhdpi': 192,
};
const Map<String, int> _adaptiveAndroidIconSizes = <String, int>{
  'mdpi': 108,
  'hdpi': 162,
  'xhdpi': 216,
  'xxhdpi': 324,
  'xxxhdpi': 432,
};
const Map<String, int> _splashAndroidImageSizes = <String, int>{
  'mdpi': 256,
  'hdpi': 384,
  'xhdpi': 512,
  'xxhdpi': 768,
  'xxxhdpi': 1024,
};
const Map<String, int> _iosIconSizes = <String, int>{
  'Icon-App-20x20@1x.png': 20,
  'Icon-App-20x20@2x.png': 40,
  'Icon-App-20x20@3x.png': 60,
  'Icon-App-29x29@1x.png': 29,
  'Icon-App-29x29@2x.png': 58,
  'Icon-App-29x29@3x.png': 87,
  'Icon-App-40x40@1x.png': 40,
  'Icon-App-40x40@2x.png': 80,
  'Icon-App-40x40@3x.png': 120,
  'Icon-App-50x50@1x.png': 50,
  'Icon-App-50x50@2x.png': 100,
  'Icon-App-57x57@1x.png': 57,
  'Icon-App-57x57@2x.png': 114,
  'Icon-App-60x60@2x.png': 120,
  'Icon-App-60x60@3x.png': 180,
  'Icon-App-72x72@1x.png': 72,
  'Icon-App-72x72@2x.png': 144,
  'Icon-App-76x76@1x.png': 76,
  'Icon-App-76x76@2x.png': 152,
  'Icon-App-83.5x83.5@2x.png': 167,
  'Icon-App-1024x1024@1x.png': 1024,
};
const Map<String, int> _iosLaunchImageSizes = <String, int>{
  'LaunchImage.png': 256,
  'LaunchImage@2x.png': 512,
  'LaunchImage@3x.png': 768,
};
const List<String> _stagingBaseFiles = <String>[
  'android/app/src/main/AndroidManifest.xml',
  'android/app/src/main/res/drawable/launch_background.xml',
  'android/app/src/main/res/drawable-v21/launch_background.xml',
  'android/app/src/main/res/values/styles.xml',
  'android/app/src/main/res/values-night/styles.xml',
  'ios/Runner.xcodeproj/project.pbxproj',
  'ios/Runner/Base.lproj/LaunchScreen.storyboard',
  'ios/Runner/Info.plist',
];
const List<String> _stagingBaseDirectories = <String>[
  'ios/Runner/Assets.xcassets/AppIcon.appiconset',
  'ios/Runner/Assets.xcassets/LaunchImage.imageset',
];
const String _iosProjectPath = 'ios/Runner.xcodeproj/project.pbxproj';
const String _iosInfoPlistPath = 'ios/Runner/Info.plist';
const String _iosAppIconDirectory =
    'ios/Runner/Assets.xcassets/AppIcon.appiconset';
const String _iosLaunchImageDirectory =
    'ios/Runner/Assets.xcassets/LaunchImage.imageset';
const String _iosLaunchBackgroundDirectory =
    'ios/Runner/Assets.xcassets/LaunchBackground.imageset';
const Set<String> _normalizedAndroid12StylePaths = <String>{
  'android/app/src/main/res/values-v31/styles.xml',
  'android/app/src/main/res/values-night-v31/styles.xml',
};
final RegExp _hexColorPattern = RegExp(r'^#[0-9A-Fa-f]{6}$');

/// 品牌生成器在内存中接收的全部人工维护输入。
///
/// [sourceImages] 的键只允许是 `assets/branding/` 下的固定 PNG 文件名；值是原始文件
/// 字节。完整应用图标、Adaptive Icon 前景/背景和启动 Logo 是必需项，Android 13+
/// 单色图标可以连同 launcher 配置中的对应字段一起省略。该对象不读取网络，也不会把
/// 配置或许可证当成第二份图片源。
final class BrandingInputs {
  /// 创建一组待预检的品牌源、权利声明和固定工具配置。
  BrandingInputs({
    required Map<String, Uint8List> sourceImages,
    required this.licenseSource,
    required this.launcherConfiguration,
    required this.splashConfiguration,
    required this.pubspecSource,
  }) : sourceImages = Map<String, Uint8List>.unmodifiable(
         sourceImages.map(
           (String name, Uint8List bytes) =>
               MapEntry<String, Uint8List>(name, Uint8List.fromList(bytes)),
         ),
       );

  /// 固定文件名到原始 PNG 字节的只读映射。
  final Map<String, Uint8List> sourceImages;

  /// 图片来源、授权范围与正式替换责任的 Markdown 文本。
  final String licenseSource;

  /// 根目录唯一 launcher icon YAML 配置。
  final String launcherConfiguration;

  /// 根目录唯一 native splash YAML 配置。
  final String splashConfiguration;

  /// 用于核对三个精确开发依赖及 runtime assets 边界的 `pubspec.yaml`。
  final String pubspecSource;

  /// 当前输入是否明确提供 Android 13+ 单色图标。
  bool get hasMonochrome => sourceImages.containsKey(_monochromeSourceName);
}

/// 两个上游工具在隔离暂存项目中生成并通过白名单验证的完整产物。
///
/// [files] 的键全部是 Android/iOS 项目相对路径。调用方不得逐个手工写入这些字节，
/// 应使用 [replaceBrandingOutputs]，以便在任一安装失败时恢复整组旧资源。
final class BrandingOutputs {
  /// 创建一组已经通过暂存生成的候选产物。
  BrandingOutputs({
    required Map<String, Uint8List> files,
    required this.monochromeEnabled,
  }) : files = Map<String, Uint8List>.unmodifiable(
         files.map(
           (String path, Uint8List bytes) =>
               MapEntry<String, Uint8List>(path, Uint8List.fromList(bytes)),
         ),
       );

  /// 白名单相对路径到候选文件字节的只读映射。
  final Map<String, Uint8List> files;

  /// 本轮是否应安装 Android 13+ 单色资源。
  final bool monochromeEnabled;
}

/// 品牌预检、暂存生成、漂移检查或事务安装失败时使用的稳定错误。
///
/// [violations] 只包含规则编号、受控相对路径和安全说明，不复制图片、许可证原文或上游
/// 异常详情。CLI 会逐项输出并返回非零退出码。
final class BrandingGenerationException implements Exception {
  /// 创建一个至少包含一项违规信息的品牌生成错误。
  BrandingGenerationException(Iterable<String> violations)
    : violations = List<String>.unmodifiable(violations) {
    if (this.violations.isEmpty) {
      throw ArgumentError.value(violations, 'violations', '不得为空。');
    }
  }

  /// 已按稳定顺序排列的违规信息。
  final List<String> violations;

  @override
  String toString() => violations.join('\n');
}

/// 校验品牌图片、权利声明、两份唯一配置和精确开发依赖。
///
/// 本函数只处理内存输入，不访问平台目录也不写文件。它验证真实 PNG、固定 1024 方形
/// 画布、不透明完整图/背景、透明前景、Android `108x108` 图层中心 `66x66` 安全区、
/// 单色灰度、配置平台范围和图片权利声明。返回空列表才允许调用上游生成工具。
List<String> validateBrandingInputs(BrandingInputs inputs) {
  final List<String> violations = <String>[];
  final Set<String> expectedSourceNames = <String>{
    ..._requiredSourceNames,
    if (inputs.hasMonochrome) _monochromeSourceName,
  };
  if (!_sameStringSet(inputs.sourceImages.keys.toSet(), expectedSourceNames)) {
    violations.add(
      '[BRANDING_SOURCE_MANIFEST] $brandingDirectoryPath 的 PNG 文件清单不符合固定契约。',
    );
  }

  final Map<String, image.Image> decoded = <String, image.Image>{};
  for (final String name in inputs.sourceImages.keys.toList()..sort()) {
    final Uint8List bytes = inputs.sourceImages[name]!;
    if (!_hasPngSignature(bytes)) {
      violations.add(
        '[BRANDING_PNG_FORMAT] $brandingDirectoryPath/$name 不是 PNG 文件。',
      );
      continue;
    }
    try {
      final image.Image? value = image.decodePng(bytes);
      if (value == null || value.frames.length != 1) {
        violations.add(
          '[BRANDING_PNG_DECODE] $brandingDirectoryPath/$name 必须是单帧有效 PNG。',
        );
        continue;
      }
      decoded[name] = value;
    } on Object {
      violations.add(
        '[BRANDING_PNG_DECODE] $brandingDirectoryPath/$name 必须是单帧有效 PNG。',
      );
    }
  }

  for (final MapEntry<String, image.Image> entry in decoded.entries) {
    if (entry.value.width != 1024 || entry.value.height != 1024) {
      violations.add(
        '[BRANDING_IMAGE_SIZE] $brandingDirectoryPath/${entry.key} '
        '必须为 1024 x 1024。',
      );
    }
  }

  _validateOpaqueImage(decoded['app_icon.png'], 'app_icon.png', violations);
  _validateOpaqueImage(
    decoded['app_icon_background.png'],
    'app_icon_background.png',
    violations,
  );
  _validateTransparentSafeImage(
    decoded['app_icon_foreground.png'],
    'app_icon_foreground.png',
    violations,
  );
  _validateTransparentSafeImage(
    decoded['splash_logo.png'],
    'splash_logo.png',
    violations,
  );
  if (inputs.hasMonochrome) {
    _validateTransparentSafeImage(
      decoded[_monochromeSourceName],
      _monochromeSourceName,
      violations,
      requireGrayscale: true,
    );
  }

  _validateLicense(inputs, violations);
  _validateLauncherConfiguration(inputs, violations);
  _validateSplashConfiguration(inputs.splashConfiguration, violations);
  _validateBrandingDependencies(inputs.pubspecSource, violations);
  violations.sort();
  return violations;
}

/// 从项目根读取固定品牌输入，不跟随源目录或文件符号链接。
///
/// 缺失文件会保留为空输入并由 [validateBrandingInputs] 给出稳定规则错误；未知文件、子目录、
/// 符号链接或不可读取路径会立即失败，防止上游工具在未登记输入上工作。
BrandingInputs readBrandingInputs(Directory projectRoot) {
  final Directory brandingDirectory = Directory(
    _joinPath(projectRoot.path, brandingDirectoryPath),
  );
  if (!_isRegularDirectoryAt(projectRoot, brandingDirectoryPath)) {
    throw BrandingGenerationException(<String>[
      '[BRANDING_SOURCE_DIRECTORY] $brandingDirectoryPath 必须是普通目录且不得为符号链接。',
    ]);
  }

  final Set<String> names = <String>{};
  for (final FileSystemEntity entity in brandingDirectory.listSync(
    followLinks: false,
  )) {
    final String name = _basename(entity.path);
    final FileSystemEntityType type = FileSystemEntity.typeSync(
      entity.path,
      followLinks: false,
    );
    if (type != FileSystemEntityType.file ||
        !_allowedBrandingDirectoryNames.contains(name)) {
      throw BrandingGenerationException(<String>[
        '[BRANDING_SOURCE_ENTRY] $brandingDirectoryPath/$name 不是允许的普通输入文件。',
      ]);
    }
    names.add(name);
  }

  final Map<String, Uint8List> images = <String, Uint8List>{};
  for (final String name in <String>{
    ..._requiredSourceNames,
    _monochromeSourceName,
  }) {
    if (!names.contains(name)) {
      continue;
    }
    images[name] =
        File(_joinPath(brandingDirectory.path, name)).readAsBytesSync();
  }

  return BrandingInputs(
    sourceImages: images,
    licenseSource: _readTextIfRegular(projectRoot, brandingLicensePath),
    launcherConfiguration: _readTextIfRegular(
      projectRoot,
      launcherConfigurationPath,
    ),
    splashConfiguration: _readTextIfRegular(
      projectRoot,
      splashConfigurationPath,
    ),
    pubspecSource: _readTextIfRegular(projectRoot, 'pubspec.yaml'),
  );
}

/// 在系统临时项目中调用锁定的 launcher 与 splash 工具并收集白名单产物。
///
/// 真实工作区在本阶段保持只读。工具只复制上游确实需要的最小平台骨架，先对全部输入和
/// 三环境公共引用做预检，再在临时目录生成。`flutter_launcher_icons 0.14.4` 对当前 Xcode
/// 工程的 Swift Asset Symbols 设置存在过宽替换行为；本函数验证该已知变化后恢复原 PBX
/// 字节。splash 对 `fullscreen: false` 只会重排 plist 并加入显式 false，本函数完成语义
/// 对比后同样恢复原 plist，从而不覆盖国际化或其他用户维护键。
Future<BrandingOutputs> buildBrandingOutputs({
  required Directory projectRoot,
}) async {
  final BrandingInputs inputs = readBrandingInputs(projectRoot);
  final List<String> violations = <String>[
    ...validateBrandingInputs(inputs),
    ...validateBrandingPlatformContract(projectRoot),
  ]..sort();
  if (violations.isNotEmpty) {
    throw BrandingGenerationException(violations);
  }

  final Directory stagingRoot = Directory.systemTemp.createTempSync(
    'flutter-template-branding-',
  );
  try {
    _prepareStagingProject(projectRoot, stagingRoot, inputs);
    final Map<String, Uint8List> before = _snapshotNativeFiles(stagingRoot);
    final Uint8List originalProject = Uint8List.fromList(
      before[_iosProjectPath]!,
    );
    final Uint8List originalInfoPlist = Uint8List.fromList(
      before[_iosInfoPlistPath]!,
    );

    final String previousCurrentDirectory = Directory.current.path;
    try {
      Directory.current = stagingRoot.path;
      final launcher_config.Config? configuration = launcher_config
          .Config.loadConfigFromPath(launcherConfigurationPath, '.');
      if (configuration == null) {
        throw BrandingGenerationException(<String>[
          '[BRANDING_LAUNCHER_CONFIG] $launcherConfigurationPath 无法由锁定工具读取。',
        ]);
      }
      await launcher.createIconsFromConfig(
        configuration,
        FLILogger(false),
        '.',
      );
      _restoreKnownLauncherProjectMutation(stagingRoot, originalProject);

      native_splash.createSplash(path: splashConfigurationPath, flavor: null);
      _restoreKnownSplashPlistMutation(stagingRoot, originalInfoPlist);
    } on BrandingGenerationException {
      rethrow;
    } on Object {
      throw BrandingGenerationException(<String>[
        '[BRANDING_UPSTREAM_FAILED] 锁定的品牌上游工具未能完成隔离生成。',
      ]);
    } finally {
      Directory.current = previousCurrentDirectory;
    }

    final Set<String> expectedPaths = _expectedOutputPaths(
      monochromeEnabled: inputs.hasMonochrome,
    );
    final Map<String, Uint8List> after = _snapshotNativeFiles(stagingRoot);
    final Set<String> changedPaths = _changedFilePaths(before, after);
    final List<String> unexpectedChanges =
        changedPaths
            .where((String path) => !expectedPaths.contains(path))
            .toList()
          ..sort();
    if (unexpectedChanges.isNotEmpty) {
      throw BrandingGenerationException(<String>[
        for (final String path in unexpectedChanges)
          '[BRANDING_UPSTREAM_WHITELIST] 上游工具尝试修改非白名单目标 $path。',
      ]);
    }

    final Map<String, Uint8List> outputFiles = <String, Uint8List>{};
    for (final String path in expectedPaths.toList()..sort()) {
      final Uint8List? bytes = after[path];
      if (bytes != null) {
        outputFiles[path] = _normalizeGeneratedOutput(path, bytes);
      }
    }
    final BrandingOutputs outputs = BrandingOutputs(
      files: outputFiles,
      monochromeEnabled: inputs.hasMonochrome,
    );
    final List<String> outputViolations = validateBrandingOutputs(outputs);
    if (outputViolations.isNotEmpty) {
      throw BrandingGenerationException(outputViolations);
    }
    return outputs;
  } finally {
    if (stagingRoot.existsSync()) {
      stagingRoot.deleteSync(recursive: true);
    }
  }
}

/// 校验暂存生成结果的文件清单、图片尺寸/Alpha 与平台引用。
///
/// 该函数不访问工作区。它要求 launcher 和 splash 的职责产物齐全，iOS AppIcon 均为不透明
/// RGB，Asset Catalog 文件名与固定图片清单一致，Android Adaptive/Android 12 XML 和 iOS
/// LaunchScreen 都引用公共资源。任一未知或缺失路径都会在安装前失败。
List<String> validateBrandingOutputs(BrandingOutputs outputs) {
  final List<String> violations = <String>[];
  final Set<String> expectedPaths = _expectedOutputPaths(
    monochromeEnabled: outputs.monochromeEnabled,
  );
  if (!_sameStringSet(outputs.files.keys.toSet(), expectedPaths)) {
    violations.add('[BRANDING_OUTPUT_MANIFEST] 暂存品牌产物文件清单不符合固定白名单。');
  }

  final Map<String, int> expectedPngSizes = _expectedPngSizes(
    monochromeEnabled: outputs.monochromeEnabled,
  );
  for (final MapEntry<String, int> entry in expectedPngSizes.entries) {
    final Uint8List? bytes = outputs.files[entry.key];
    if (bytes == null) {
      continue;
    }
    final image.Image? decoded = _decodeOutputPng(entry.key, bytes, violations);
    if (decoded == null) {
      continue;
    }
    if (decoded.width != entry.value || decoded.height != entry.value) {
      violations.add(
        '[BRANDING_OUTPUT_SIZE] ${entry.key} 必须为 '
        '${entry.value} x ${entry.value}。',
      );
    }
    if (entry.key.startsWith(
          'ios/Runner/Assets.xcassets/AppIcon.appiconset/',
        ) &&
        _hasAnyTransparentPixel(decoded)) {
      violations.add('[BRANDING_IOS_ALPHA] ${entry.key} 不得包含透明像素。');
    }
  }

  _validateAndroidOutputReferences(outputs, violations);
  _validateIosOutputReferences(outputs, violations);
  violations.sort();
  return violations;
}

/// 核对三环境是否共同继承 Android `src/main` 与同一个 iOS AppIcon/LaunchScreen。
///
/// 本检查拒绝环境专属 launcher/splash 配置、Android flavor 资源和非 `AppIcon` 的 Xcode
/// 应用图标名。它不会运行 Gradle 或 Xcode，也不修改任何平台文件。
List<String> validateBrandingPlatformContract(Directory projectRoot) {
  final List<String> violations = <String>[];
  for (final String path in _stagingBaseFiles) {
    if (!_isRegularFileAt(projectRoot, path)) {
      violations.add('[BRANDING_PLATFORM_BASE] $path 缺少品牌工具所需的平台基础文件。');
    }
  }
  for (final String path in _stagingBaseDirectories) {
    if (!_isRegularDirectoryAt(projectRoot, path)) {
      violations.add('[BRANDING_PLATFORM_BASE] $path 必须是普通平台资源目录。');
    }
  }

  final String androidManifest = _readTextIfRegular(
    projectRoot,
    'android/app/src/main/AndroidManifest.xml',
  );
  if (!_containsExactlyOnce(
    androidManifest,
    'android:icon="@mipmap/ic_launcher"',
  )) {
    violations.add(
      '[BRANDING_ANDROID_MANIFEST] Android 主 Manifest 必须唯一引用 @mipmap/ic_launcher。',
    );
  }

  final String xcodeProject = _readTextIfRegular(projectRoot, _iosProjectPath);
  final Iterable<RegExpMatch> iconNameMatches = RegExp(
    r'ASSETCATALOG_COMPILER_APPICON_NAME\s*=\s*([^;]+);',
  ).allMatches(xcodeProject);
  if (iconNameMatches.isEmpty ||
      iconNameMatches.any(
        (RegExpMatch match) => match.group(1)?.trim() != 'AppIcon',
      )) {
    violations.add(
      '[BRANDING_IOS_APPICON_REFERENCE] 所有 iOS 构建配置必须共同引用 AppIcon。',
    );
  }

  for (final String environment in <String>['dev', 'staging', 'prod']) {
    for (final String prefix in <String>[
      'flutter_launcher_icons-$environment.yaml',
      'flutter_native_splash-$environment.yaml',
    ]) {
      if (File(_joinPath(projectRoot.path, prefix)).existsSync()) {
        violations.add('[BRANDING_ENV_CONFIG] $prefix 会制造环境专属品牌配置，必须移除。');
      }
    }
    final Directory resourceDirectory = Directory(
      _joinPath(projectRoot.path, 'android/app/src/$environment/res'),
    );
    final FileSystemEntityType resourceDirectoryType =
        FileSystemEntity.typeSync(resourceDirectory.path, followLinks: false);
    if (resourceDirectoryType == FileSystemEntityType.notFound) {
      continue;
    }
    if (!_isRegularDirectoryAt(
      projectRoot,
      'android/app/src/$environment/res',
    )) {
      violations.add(
        '[BRANDING_ENV_RESOURCE] android/app/src/$environment/res '
        '必须是普通目录且不得为符号链接。',
      );
      continue;
    }
    for (final FileSystemEntity entity in resourceDirectory.listSync(
      recursive: true,
      followLinks: false,
    )) {
      final FileSystemEntityType entityType = FileSystemEntity.typeSync(
        entity.path,
        followLinks: false,
      );
      if (entityType == FileSystemEntityType.directory) {
        continue;
      }
      final String name = _basename(entity.path);
      if (entityType != FileSystemEntityType.file) {
        violations.add(
          '[BRANDING_ENV_RESOURCE] android/app/src/$environment/res/$name '
          '不得是符号链接或特殊文件。',
        );
        continue;
      }
      if (_isBrandingResourceFileName(name)) {
        violations.add(
          '[BRANDING_ENV_RESOURCE] android/app/src/$environment/res '
          '不得包含环境专属 $name。',
        );
      }
    }
  }

  violations.sort();
  return violations;
}

/// 将已验证产物按同文件系统暂存、备份和回滚边界安装到平台目录。
///
/// 相同字节不会重写。真正变化的目标会先完整写入项目 `.dart_tool` 下的同卷暂存区并回读，
/// 再逐个以 rename 安装；旧文件始终先移入备份区。任一回调或文件操作失败时会逆序恢复全部
/// 已触碰目标，并清理本轮新建的空目录。[beforeInstall] 仅用于测试注入确定失败，生产调用
/// 应保持为空。若回滚自身失败，工具保留唯一备份并返回专门错误，调用方不得继续生成。
void replaceBrandingOutputs({
  required Directory projectRoot,
  required BrandingOutputs outputs,
  void Function(String relativePath)? beforeInstall,
}) {
  final Set<String> potentialTargets = <String>{
    ...outputs.files.keys,
    ..._monochromeOutputPaths(),
  };
  final List<String> violations = validateBrandingOutputs(outputs);
  if (violations.isNotEmpty) {
    violations.sort();
    throw BrandingGenerationException(violations);
  }

  // 所有目标的每一级现存路径都必须先确认为普通目录或普通文件。受管 Catalog 的枚举也要
  // 排在这一步之后，否则父目录链接可能让未知文件名从工作区外进入诊断信息。
  _collectSafeOutputPaths(projectRoot, potentialTargets, violations);
  if (violations.isNotEmpty) {
    violations.sort();
    throw BrandingGenerationException(violations);
  }

  violations.addAll(_validateOwnedOutputEntries(projectRoot, outputs));
  violations.sort();
  if (violations.isNotEmpty) {
    throw BrandingGenerationException(violations);
  }

  final List<String> changingTargets = <String>[];
  for (final String path in potentialTargets.toList()..sort()) {
    final File target = File(_joinPath(projectRoot.path, path));
    final Uint8List? expected = outputs.files[path];
    if (expected == null) {
      if (target.existsSync()) {
        changingTargets.add(path);
      }
      continue;
    }
    if (!target.existsSync() ||
        !_bytesEqual(target.readAsBytesSync(), expected)) {
      changingTargets.add(path);
    }
  }
  if (changingTargets.isEmpty) {
    return;
  }

  final Map<String, bool> originalDirectories = _captureParentDirectories(
    projectRoot,
    changingTargets,
  );
  final Directory transactionRoot = _createTransactionDirectory(projectRoot);
  final Directory candidateRoot = Directory(
    _joinPath(transactionRoot.path, 'candidate'),
  );
  final Directory backupRoot = Directory(
    _joinPath(transactionRoot.path, 'backup'),
  );
  final List<String> touched = <String>[];

  try {
    for (final String path in changingTargets) {
      final Uint8List? bytes = outputs.files[path];
      if (bytes == null) {
        continue;
      }
      final File candidate = File(_joinPath(candidateRoot.path, path));
      candidate.parent.createSync(recursive: true);
      candidate.writeAsBytesSync(bytes, flush: true);
      if (!_bytesEqual(candidate.readAsBytesSync(), bytes)) {
        throw const FileSystemException('candidate verification failed');
      }
    }

    for (final String path in changingTargets) {
      beforeInstall?.call(path);
      final File target = File(_joinPath(projectRoot.path, path));
      final File backup = File(_joinPath(backupRoot.path, path));
      final bool existed = target.existsSync();
      if (existed) {
        backup.parent.createSync(recursive: true);
        target.renameSync(backup.path);
      }
      touched.add(path);

      final Uint8List? expected = outputs.files[path];
      if (expected == null) {
        continue;
      }
      target.parent.createSync(recursive: true);
      File(_joinPath(candidateRoot.path, path)).renameSync(target.path);
    }
  } on Object {
    try {
      for (final String path in touched.reversed) {
        final File target = File(_joinPath(projectRoot.path, path));
        final File backup = File(_joinPath(backupRoot.path, path));
        if (target.existsSync()) {
          target.deleteSync();
        }
        if (backup.existsSync()) {
          target.parent.createSync(recursive: true);
          backup.renameSync(target.path);
        }
      }
      _removeNewEmptyDirectories(projectRoot, originalDirectories);
      transactionRoot.deleteSync(recursive: true);
    } on Object {
      throw BrandingGenerationException(<String>[
        '[BRANDING_ROLLBACK_FAILED] 品牌资源回滚失败；'
            '请保留 ${_basename(transactionRoot.path)} 并按文档人工恢复。',
      ]);
    }
    throw BrandingGenerationException(<String>[
      '[BRANDING_INSTALL_FAILED] 品牌资源安装失败，旧产物已完整恢复。',
    ]);
  }

  transactionRoot.deleteSync(recursive: true);
}

/// 逐字节比较已验证候选与工作区平台产物，并执行公共环境/目录清单检查。
///
/// 本函数严格只读，不创建暂存目录、不修改 mtime。它区分缺失、陈旧、可选单色残留和受管
/// Asset Catalog 额外文件；返回空列表表示当前原生产物与相同输入重新生成的结果一致。
List<String> findBrandingOutputDrift({
  required Directory projectRoot,
  required BrandingOutputs expected,
}) {
  final List<String> violations = validateBrandingOutputs(expected);
  if (violations.isNotEmpty) {
    violations.sort();
    return violations;
  }

  final Set<String> pathsToInspect = <String>{
    ...expected.files.keys,
    if (!expected.monochromeEnabled) ..._monochromeOutputPaths(),
  };
  final Set<String> safePaths = _collectSafeOutputPaths(
    projectRoot,
    pathsToInspect,
    violations,
  );
  if (violations.isNotEmpty) {
    violations.sort();
    return violations;
  }

  // 只有全部受管输出路径均确认不会经过链接后，才读取平台配置并枚举 Asset Catalog。
  violations.addAll(validateBrandingPlatformContract(projectRoot));
  violations.addAll(_validateOwnedOutputEntries(projectRoot, expected));
  for (final String path in expected.files.keys.toList()..sort()) {
    if (!safePaths.contains(path)) {
      continue;
    }
    final File target = File(_joinPath(projectRoot.path, path));
    if (!target.existsSync()) {
      violations.add('[BRANDING_OUTPUT_MISSING] $path 缺少生成产物。');
    } else if (!_bytesEqual(target.readAsBytesSync(), expected.files[path]!)) {
      violations.add('[BRANDING_OUTPUT_STALE] $path 已过期。');
    }
  }
  if (!expected.monochromeEnabled) {
    for (final String path in _monochromeOutputPaths()) {
      if (!safePaths.contains(path)) {
        continue;
      }
      if (File(_joinPath(projectRoot.path, path)).existsSync()) {
        violations.add('[BRANDING_OUTPUT_STALE] $path 是已禁用单色图标的残留产物。');
      }
    }
  }
  violations.sort();
  return violations;
}

/// 执行品牌生成 CLI，并返回适合测试断言的退出码。
///
/// 支持的唯一模式是默认生成或 `--check` 只读检查；`--root` 仅用于临时项目测试。参数错误
/// 返回 64，输入/生成/漂移失败返回 1，成功返回 0。错误文本不回显图片或上游异常。
Future<int> runBrandingGenerator(
  List<String> arguments, {
  StringSink? output,
  StringSink? errorOutput,
}) async {
  final StringSink stdoutSink = output ?? stdout;
  final StringSink stderrSink = errorOutput ?? stderr;
  late final ({Directory root, bool check}) options;
  try {
    options = _parseArguments(arguments);
  } on FormatException catch (error) {
    stderrSink.writeln('品牌资源生成参数错误：${error.message}');
    stderrSink.writeln(
      '用法：dart run tool/generate_branding.dart [--check] [--root <path>]',
    );
    return 64;
  }

  try {
    final BrandingOutputs outputs = await buildBrandingOutputs(
      projectRoot: options.root,
    );
    if (options.check) {
      final List<String> violations = findBrandingOutputDrift(
        projectRoot: options.root,
        expected: outputs,
      );
      if (violations.isNotEmpty) {
        throw BrandingGenerationException(violations);
      }
      stdoutSink.writeln(
        '品牌资源检查通过，共核对 ${outputs.files.length} 个 Android/iOS 产物。',
      );
      return 0;
    }

    replaceBrandingOutputs(projectRoot: options.root, outputs: outputs);
    stdoutSink.writeln(
      '品牌资源生成完成，共同步 ${outputs.files.length} 个 Android/iOS 白名单产物。',
    );
    return 0;
  } on BrandingGenerationException catch (error) {
    stderrSink.writeln('品牌资源生成失败，共 ${error.violations.length} 项：');
    for (final String violation in error.violations) {
      stderrSink.writeln('- $violation');
    }
    return 1;
  } on Object {
    stderrSink.writeln('品牌资源生成失败：发生未分类的本地工具错误。');
    return 1;
  }
}

Future<void> main(List<String> arguments) async {
  exitCode = await runBrandingGenerator(arguments);
}

void _validateOpaqueImage(
  image.Image? decoded,
  String name,
  List<String> violations,
) {
  if (decoded == null) {
    return;
  }
  if (_hasAnyTransparentPixel(decoded)) {
    violations.add(
      '[BRANDING_IMAGE_ALPHA] $brandingDirectoryPath/$name 必须完全不透明。',
    );
  }
}

void _validateTransparentSafeImage(
  image.Image? decoded,
  String name,
  List<String> violations, {
  bool requireGrayscale = false,
}) {
  if (decoded == null) {
    return;
  }
  var hasTransparent = false;
  var hasVisible = false;
  var grayscale = true;
  var minimumX = decoded.width;
  var minimumY = decoded.height;
  var maximumX = -1;
  var maximumY = -1;
  for (final image.Pixel pixel in decoded) {
    final int alpha = pixel.a.toInt();
    if (alpha == 0) {
      hasTransparent = true;
      continue;
    }
    hasVisible = true;
    minimumX = pixel.x < minimumX ? pixel.x : minimumX;
    minimumY = pixel.y < minimumY ? pixel.y : minimumY;
    maximumX = pixel.x > maximumX ? pixel.x : maximumX;
    maximumY = pixel.y > maximumY ? pixel.y : maximumY;
    if (pixel.r.toInt() != pixel.g.toInt() ||
        pixel.g.toInt() != pixel.b.toInt()) {
      grayscale = false;
    }
  }
  if (!hasTransparent || !hasVisible) {
    violations.add(
      '[BRANDING_TRANSPARENT_LAYER] $brandingDirectoryPath/$name '
      '必须同时包含透明画布和可见图形。',
    );
    return;
  }
  if (decoded.width == 1024 && decoded.height == 1024) {
    final int safeMinimum = (decoded.width * 21 / 108).ceil();
    final int safeMaximum = (decoded.width * 87 / 108).floor() - 1;
    if (minimumX < safeMinimum ||
        minimumY < safeMinimum ||
        maximumX > safeMaximum ||
        maximumY > safeMaximum) {
      violations.add(
        '[BRANDING_ADAPTIVE_SAFE_ZONE] $brandingDirectoryPath/$name 的可见像素'
        '必须位于 108 x 108 图层中心 66 x 66 安全区。',
      );
    }
  }
  if (requireGrayscale && !grayscale) {
    violations.add(
      '[BRANDING_MONOCHROME_COLOR] $brandingDirectoryPath/$name '
      '的可见像素必须为灰度，平台只使用其 Alpha 蒙版。',
    );
  }
}

void _validateLicense(BrandingInputs inputs, List<String> violations) {
  final String license = _normalizeLineEndings(inputs.licenseSource).trim();
  if (license.length < 160 ||
      !license.contains('权利') ||
      !license.contains('授权')) {
    violations.add(
      '[BRANDING_LICENSE_MISSING] $brandingLicensePath '
      '必须记录来源、权利范围与正式替换责任。',
    );
    return;
  }
  for (final String name in inputs.sourceImages.keys.toList()..sort()) {
    if (!license.contains('`$name`')) {
      violations.add(
        '[BRANDING_LICENSE_SOURCE] $brandingLicensePath 未登记 $name。',
      );
    }
  }
}

void _validateLauncherConfiguration(
  BrandingInputs inputs,
  List<String> violations,
) {
  final Map<String, Object?>? root = _decodeYamlMap(
    inputs.launcherConfiguration,
    launcherConfigurationPath,
    '[BRANDING_LAUNCHER_CONFIG]',
    violations,
  );
  if (root == null) {
    return;
  }
  if (!_sameStringSet(root.keys.toSet(), <String>{'flutter_launcher_icons'})) {
    violations.add(
      '[BRANDING_LAUNCHER_CONFIG] $launcherConfigurationPath '
      '顶层只能包含 flutter_launcher_icons。',
    );
    return;
  }
  final Object? rawConfiguration = root['flutter_launcher_icons'];
  if (rawConfiguration is! Map<String, Object?>) {
    violations.add(
      '[BRANDING_LAUNCHER_CONFIG] $launcherConfigurationPath 配置主体无效。',
    );
    return;
  }
  final Set<String> expectedKeys = <String>{
    ..._launcherRequiredKeys,
    if (inputs.hasMonochrome) 'adaptive_icon_monochrome',
  };
  if (!_sameStringSet(rawConfiguration.keys.toSet(), expectedKeys)) {
    violations.add(
      '[BRANDING_LAUNCHER_CONFIG] $launcherConfigurationPath '
      '字段清单与 Android/iOS 固定契约不一致。',
    );
  }

  final Map<String, Object?> expectedValues = <String, Object?>{
    'android': true,
    'ios': true,
    'image_path': '$brandingDirectoryPath/app_icon.png',
    'min_sdk_android': 21,
    'adaptive_icon_background':
        '$brandingDirectoryPath/app_icon_background.png',
    'adaptive_icon_foreground':
        '$brandingDirectoryPath/app_icon_foreground.png',
    'adaptive_icon_foreground_inset': 0,
    'remove_alpha_ios': true,
    if (inputs.hasMonochrome)
      'adaptive_icon_monochrome':
          '$brandingDirectoryPath/$_monochromeSourceName',
  };
  for (final MapEntry<String, Object?> expected in expectedValues.entries) {
    if (rawConfiguration[expected.key] != expected.value) {
      violations.add(
        '[BRANDING_LAUNCHER_VALUE] $launcherConfigurationPath 的 '
        '${expected.key} 不符合固定配置。',
      );
    }
  }
  final Object? backgroundColor = rawConfiguration['background_color_ios'];
  if (backgroundColor is! String ||
      !_hexColorPattern.hasMatch(backgroundColor)) {
    violations.add(
      '[BRANDING_COLOR] $launcherConfigurationPath 的 '
      'background_color_ios 必须为 #RRGGBB。',
    );
  }
}

void _validateSplashConfiguration(String source, List<String> violations) {
  final Map<String, Object?>? root = _decodeYamlMap(
    source,
    splashConfigurationPath,
    '[BRANDING_SPLASH_CONFIG]',
    violations,
  );
  if (root == null) {
    return;
  }
  if (!_sameStringSet(root.keys.toSet(), <String>{'flutter_native_splash'})) {
    violations.add(
      '[BRANDING_SPLASH_CONFIG] $splashConfigurationPath '
      '顶层只能包含 flutter_native_splash。',
    );
    return;
  }
  final Object? rawConfiguration = root['flutter_native_splash'];
  if (rawConfiguration is! Map<String, Object?>) {
    violations.add('[BRANDING_SPLASH_CONFIG] $splashConfigurationPath 配置主体无效。');
    return;
  }
  if (!_sameStringSet(rawConfiguration.keys.toSet(), _splashRequiredKeys)) {
    violations.add(
      '[BRANDING_SPLASH_CONFIG] $splashConfigurationPath '
      '字段清单与 Android/iOS 固定契约不一致。',
    );
  }
  final Map<String, Object?> expectedValues = <String, Object?>{
    'android': true,
    'ios': true,
    'web': false,
    'image': '$brandingDirectoryPath/splash_logo.png',
    'fullscreen': false,
  };
  for (final MapEntry<String, Object?> expected in expectedValues.entries) {
    if (rawConfiguration[expected.key] != expected.value) {
      violations.add(
        '[BRANDING_SPLASH_VALUE] $splashConfigurationPath 的 '
        '${expected.key} 不符合固定配置。',
      );
    }
  }
  final Object? rawColor = rawConfiguration['color'];
  if (rawColor is! String || !_hexColorPattern.hasMatch(rawColor)) {
    violations.add(
      '[BRANDING_COLOR] $splashConfigurationPath 的 color 必须为 #RRGGBB。',
    );
  }
  final Object? rawAndroid12 = rawConfiguration['android_12'];
  if (rawAndroid12 is! Map<String, Object?> ||
      !_sameStringSet(rawAndroid12.keys.toSet(), _android12SplashKeys)) {
    violations.add(
      '[BRANDING_ANDROID12_CONFIG] $splashConfigurationPath 的 '
      'android_12 字段清单无效。',
    );
    return;
  }
  if (rawAndroid12['image'] != '$brandingDirectoryPath/splash_logo.png' ||
      rawAndroid12['color'] != rawColor ||
      rawAndroid12['icon_background_color'] != rawColor) {
    violations.add('[BRANDING_ANDROID12_VALUE] Android 12 必须复用同一 Logo 与背景色。');
  }
}

void _validateBrandingDependencies(
  String pubspecSource,
  List<String> violations,
) {
  final Map<String, Object?>? root = _decodeYamlMap(
    pubspecSource,
    'pubspec.yaml',
    '[BRANDING_PUBSPEC]',
    violations,
  );
  if (root == null) {
    return;
  }
  final Object? rawDevDependencies = root['dev_dependencies'];
  if (rawDevDependencies is! Map<String, Object?> ||
      rawDevDependencies['flutter_launcher_icons']?.toString() != '0.14.4' ||
      rawDevDependencies['flutter_native_splash']?.toString() != '2.4.6' ||
      rawDevDependencies['image']?.toString() != '4.8.0') {
    violations.add(
      '[BRANDING_DEPENDENCIES] pubspec.yaml 必须精确锁定 launcher 0.14.4、'
      'splash 2.4.6 与 image 4.8.0 开发依赖。',
    );
  }
  final Object? rawFlutter = root['flutter'];
  final Object? rawAssets =
      rawFlutter is Map<String, Object?> ? rawFlutter['assets'] : null;
  if (rawAssets is List<Object?> &&
      rawAssets.any(
        (Object? value) =>
            value.toString().startsWith('$brandingDirectoryPath/'),
      )) {
    violations.add(
      '[BRANDING_RUNTIME_ASSET] 品牌生成源不得注册为 Flutter runtime assets。',
    );
  }
}

Map<String, Object?>? _decodeYamlMap(
  String source,
  String path,
  String code,
  List<String> violations,
) {
  if (source.isEmpty) {
    violations.add('$code $path 缺失或不可读取。');
    return null;
  }
  try {
    final Object? decoded = loadYaml(source);
    if (decoded is! YamlMap) {
      violations.add('$code $path 顶层必须是 YAML 对象。');
      return null;
    }
    return _convertYamlMap(decoded);
  } on Object {
    violations.add('$code $path 不是合法 YAML。');
    return null;
  }
}

Map<String, Object?> _convertYamlMap(YamlMap source) {
  return <String, Object?>{
    for (final MapEntry<Object?, Object?> entry in source.entries)
      entry.key.toString(): _convertYamlValue(entry.value),
  };
}

Object? _convertYamlValue(Object? value) {
  if (value is YamlMap) {
    return _convertYamlMap(value);
  }
  if (value is YamlList) {
    return <Object?>[for (final Object? item in value) _convertYamlValue(item)];
  }
  return value;
}

bool _hasPngSignature(Uint8List bytes) {
  const List<int> signature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
  return bytes.length >= signature.length &&
      List<int>.generate(
        signature.length,
        (int index) => bytes[index],
      ).asMap().entries.every(
        (MapEntry<int, int> entry) => entry.value == signature[entry.key],
      );
}

bool _hasAnyTransparentPixel(image.Image decoded) {
  for (final image.Pixel pixel in decoded) {
    if (pixel.a.toInt() != 255) {
      return true;
    }
  }
  return false;
}

void _prepareStagingProject(
  Directory projectRoot,
  Directory stagingRoot,
  BrandingInputs inputs,
) {
  for (final String path in _stagingBaseFiles) {
    _copyFile(projectRoot, stagingRoot, path);
  }
  for (final String path in _stagingBaseDirectories) {
    _copyDirectory(projectRoot, stagingRoot, path);
  }
  for (final MapEntry<String, Uint8List> source
      in inputs.sourceImages.entries) {
    final File target = File(
      _joinPath(stagingRoot.path, '$brandingDirectoryPath/${source.key}'),
    );
    target.parent.createSync(recursive: true);
    target.writeAsBytesSync(source.value);
  }
  File(_joinPath(stagingRoot.path, brandingLicensePath))
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(inputs.licenseSource);
  File(
    _joinPath(stagingRoot.path, launcherConfigurationPath),
  ).writeAsStringSync(inputs.launcherConfiguration);
  File(
    _joinPath(stagingRoot.path, splashConfigurationPath),
  ).writeAsStringSync(inputs.splashConfiguration);
}

void _copyFile(Directory fromRoot, Directory toRoot, String relativePath) {
  final File source = File(_joinPath(fromRoot.path, relativePath));
  final File target = File(_joinPath(toRoot.path, relativePath));
  target.parent.createSync(recursive: true);
  target.writeAsBytesSync(source.readAsBytesSync());
}

void _copyDirectory(Directory fromRoot, Directory toRoot, String relativePath) {
  final Directory source = Directory(_joinPath(fromRoot.path, relativePath));
  final Directory target = Directory(_joinPath(toRoot.path, relativePath))
    ..createSync(recursive: true);
  for (final FileSystemEntity entity in source.listSync(
    recursive: true,
    followLinks: false,
  )) {
    final FileSystemEntityType type = FileSystemEntity.typeSync(
      entity.path,
      followLinks: false,
    );
    final String suffix = entity.path.substring(source.path.length + 1);
    final String targetPath = _joinPath(
      target.path,
      suffix.replaceAll(Platform.pathSeparator, '/'),
    );
    if (type == FileSystemEntityType.directory) {
      Directory(targetPath).createSync(recursive: true);
    } else if (type == FileSystemEntityType.file) {
      final File targetFile = File(targetPath);
      targetFile.parent.createSync(recursive: true);
      targetFile.writeAsBytesSync(File(entity.path).readAsBytesSync());
    } else {
      throw BrandingGenerationException(<String>[
        '[BRANDING_PLATFORM_SYMLINK] $relativePath 包含不允许的符号链接或特殊文件。',
      ]);
    }
  }
}

Map<String, Uint8List> _snapshotNativeFiles(Directory root) {
  final Map<String, Uint8List> result = <String, Uint8List>{};
  for (final String directoryName in <String>['android', 'ios']) {
    final Directory directory = Directory(_joinPath(root.path, directoryName));
    if (!directory.existsSync()) {
      continue;
    }
    for (final FileSystemEntity entity in directory.listSync(
      recursive: true,
      followLinks: false,
    )) {
      if (FileSystemEntity.typeSync(entity.path, followLinks: false) !=
          FileSystemEntityType.file) {
        continue;
      }
      final String relative = entity.path
          .substring(root.path.length + 1)
          .replaceAll(Platform.pathSeparator, '/');
      result[relative] = File(entity.path).readAsBytesSync();
    }
  }
  return result;
}

Set<String> _changedFilePaths(
  Map<String, Uint8List> before,
  Map<String, Uint8List> after,
) {
  final Set<String> paths = <String>{...before.keys, ...after.keys};
  return <String>{
    for (final String path in paths)
      if (before[path] == null ||
          after[path] == null ||
          !_bytesEqual(before[path]!, after[path]!))
        path,
  };
}

void _restoreKnownLauncherProjectMutation(
  Directory stagingRoot,
  Uint8List originalBytes,
) {
  final File projectFile = File(_joinPath(stagingRoot.path, _iosProjectPath));
  final String original = utf8.decode(originalBytes);
  final String transformed = projectFile.readAsStringSync();
  const String originalSymbolSetting =
      'ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;';
  const String damagedSymbolSetting =
      'ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = AppIcon;';
  final String repaired = transformed.replaceAll(
    damagedSymbolSetting,
    originalSymbolSetting,
  );
  if (repaired != original || !original.contains(originalSymbolSetting)) {
    throw BrandingGenerationException(<String>[
      '[BRANDING_IOS_PROJECT_MUTATION] launcher 工具产生了未知的 Xcode 工程修改。',
    ]);
  }
  projectFile.writeAsBytesSync(originalBytes);
}

void _restoreKnownSplashPlistMutation(
  Directory stagingRoot,
  Uint8List originalBytes,
) {
  final File plistFile = File(_joinPath(stagingRoot.path, _iosInfoPlistPath));
  final Map<String, Object?> original = _decodePlistDictionary(
    utf8.decode(originalBytes),
  );
  final Map<String, Object?> transformed = _decodePlistDictionary(
    plistFile.readAsStringSync(),
  );
  final Object? statusBarHidden = transformed.remove('UIStatusBarHidden');
  if (statusBarHidden != false || !_deepEquals(original, transformed)) {
    throw BrandingGenerationException(<String>[
      '[BRANDING_IOS_PLIST_MUTATION] splash 工具产生了未知的 Info.plist 修改。',
    ]);
  }
  plistFile.writeAsBytesSync(originalBytes);
}

Map<String, Object?> _decodePlistDictionary(String source) {
  try {
    final XmlDocument document = XmlDocument.parse(source);
    final XmlElement? dictionary =
        document.rootElement.childElements
            .where((XmlElement element) => element.name.local == 'dict')
            .firstOrNull;
    if (dictionary == null) {
      throw const FormatException('missing dict');
    }
    return _decodePlistDictElement(dictionary);
  } on BrandingGenerationException {
    rethrow;
  } on Object {
    throw BrandingGenerationException(<String>[
      '[BRANDING_IOS_PLIST_INVALID] $_iosInfoPlistPath 不是受支持的 plist。',
    ]);
  }
}

Map<String, Object?> _decodePlistDictElement(XmlElement dictionary) {
  final List<XmlElement> children = dictionary.childElements.toList();
  if (children.length.isOdd) {
    throw const FormatException('invalid dict pairs');
  }
  final Map<String, Object?> result = <String, Object?>{};
  for (var index = 0; index < children.length; index += 2) {
    final XmlElement key = children[index];
    if (key.name.local != 'key' || result.containsKey(key.innerText)) {
      throw const FormatException('invalid dict key');
    }
    result[key.innerText] = _decodePlistElement(children[index + 1]);
  }
  return result;
}

Object? _decodePlistElement(XmlElement element) {
  return switch (element.name.local) {
    'string' => element.innerText,
    'true' => true,
    'false' => false,
    'array' => <Object?>[
      for (final XmlElement child in element.childElements)
        _decodePlistElement(child),
    ],
    'dict' => _decodePlistDictElement(element),
    _ => throw const FormatException('unsupported plist value'),
  };
}

bool _deepEquals(Object? left, Object? right) {
  if (left is Map<String, Object?> && right is Map<String, Object?>) {
    return _sameStringSet(left.keys.toSet(), right.keys.toSet()) &&
        left.keys.every((String key) => _deepEquals(left[key], right[key]));
  }
  if (left is List<Object?> && right is List<Object?>) {
    return left.length == right.length &&
        List<int>.generate(
          left.length,
          (int index) => index,
        ).every((int index) => _deepEquals(left[index], right[index]));
  }
  return left == right;
}

Set<String> _expectedOutputPaths({required bool monochromeEnabled}) {
  return <String>{
    for (final String density in _androidDensities)
      'android/app/src/main/res/mipmap-$density/ic_launcher.png',
    for (final String density in _androidDensities)
      'android/app/src/main/res/drawable-$density/ic_launcher_background.png',
    for (final String density in _androidDensities)
      'android/app/src/main/res/drawable-$density/ic_launcher_foreground.png',
    if (monochromeEnabled)
      for (final String density in _androidDensities)
        'android/app/src/main/res/drawable-$density/ic_launcher_monochrome.png',
    'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
    for (final String density in _androidDensities)
      'android/app/src/main/res/drawable-$density/splash.png',
    for (final String density in _androidDensities)
      'android/app/src/main/res/drawable-$density/android12splash.png',
    for (final String density in _androidDensities)
      'android/app/src/main/res/drawable-night-$density/android12splash.png',
    'android/app/src/main/res/drawable/background.png',
    'android/app/src/main/res/drawable-v21/background.png',
    'android/app/src/main/res/drawable/launch_background.xml',
    'android/app/src/main/res/drawable-v21/launch_background.xml',
    'android/app/src/main/res/values/styles.xml',
    'android/app/src/main/res/values-night/styles.xml',
    'android/app/src/main/res/values-v31/styles.xml',
    'android/app/src/main/res/values-night-v31/styles.xml',
    for (final String name in _iosIconSizes.keys) '$_iosAppIconDirectory/$name',
    '$_iosAppIconDirectory/Contents.json',
    for (final String name in _iosLaunchImageSizes.keys)
      '$_iosLaunchImageDirectory/$name',
    '$_iosLaunchImageDirectory/Contents.json',
    '$_iosLaunchBackgroundDirectory/background.png',
    '$_iosLaunchBackgroundDirectory/Contents.json',
    'ios/Runner/Base.lproj/LaunchScreen.storyboard',
  };
}

Set<String> _monochromeOutputPaths() {
  return <String>{
    for (final String density in _androidDensities)
      'android/app/src/main/res/drawable-$density/ic_launcher_monochrome.png',
  };
}

Map<String, int> _expectedPngSizes({required bool monochromeEnabled}) {
  return <String, int>{
    for (final MapEntry<String, int> entry in _regularAndroidIconSizes.entries)
      'android/app/src/main/res/mipmap-${entry.key}/ic_launcher.png':
          entry.value,
    for (final MapEntry<String, int> entry in _adaptiveAndroidIconSizes.entries)
      'android/app/src/main/res/drawable-${entry.key}/ic_launcher_background.png':
          entry.value,
    for (final MapEntry<String, int> entry in _adaptiveAndroidIconSizes.entries)
      'android/app/src/main/res/drawable-${entry.key}/ic_launcher_foreground.png':
          entry.value,
    if (monochromeEnabled)
      for (final MapEntry<String, int> entry
          in _adaptiveAndroidIconSizes.entries)
        'android/app/src/main/res/drawable-${entry.key}/ic_launcher_monochrome.png':
            entry.value,
    for (final MapEntry<String, int> entry in _splashAndroidImageSizes.entries)
      'android/app/src/main/res/drawable-${entry.key}/splash.png': entry.value,
    for (final MapEntry<String, int> entry in _splashAndroidImageSizes.entries)
      'android/app/src/main/res/drawable-${entry.key}/android12splash.png':
          entry.value,
    for (final MapEntry<String, int> entry in _splashAndroidImageSizes.entries)
      'android/app/src/main/res/drawable-night-${entry.key}/android12splash.png':
          entry.value,
    'android/app/src/main/res/drawable/background.png': 1,
    'android/app/src/main/res/drawable-v21/background.png': 1,
    for (final MapEntry<String, int> entry in _iosIconSizes.entries)
      '$_iosAppIconDirectory/${entry.key}': entry.value,
    for (final MapEntry<String, int> entry in _iosLaunchImageSizes.entries)
      '$_iosLaunchImageDirectory/${entry.key}': entry.value,
    '$_iosLaunchBackgroundDirectory/background.png': 1,
  };
}

image.Image? _decodeOutputPng(
  String path,
  Uint8List bytes,
  List<String> violations,
) {
  if (!_hasPngSignature(bytes)) {
    violations.add('[BRANDING_OUTPUT_PNG] $path 不是 PNG 文件。');
    return null;
  }
  try {
    final image.Image? decoded = image.decodePng(bytes);
    if (decoded == null || decoded.frames.length != 1) {
      violations.add('[BRANDING_OUTPUT_PNG] $path 不是单帧有效 PNG。');
      return null;
    }
    return decoded;
  } on Object {
    violations.add('[BRANDING_OUTPUT_PNG] $path 不是单帧有效 PNG。');
    return null;
  }
}

void _validateAndroidOutputReferences(
  BrandingOutputs outputs,
  List<String> violations,
) {
  final String adaptiveXml = _utf8Output(
    outputs,
    'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
    violations,
  );
  final List<String> adaptiveMarkers = <String>[
    '@drawable/ic_launcher_background',
    '@drawable/ic_launcher_foreground',
    if (outputs.monochromeEnabled) '@drawable/ic_launcher_monochrome',
  ];
  if (adaptiveMarkers.any((String marker) => !adaptiveXml.contains(marker)) ||
      (!outputs.monochromeEnabled && adaptiveXml.contains('<monochrome>'))) {
    violations.add(
      '[BRANDING_ANDROID_ADAPTIVE_XML] Adaptive Icon XML 未精确引用当前图层。',
    );
  }

  for (final String path in <String>[
    'android/app/src/main/res/drawable/launch_background.xml',
    'android/app/src/main/res/drawable-v21/launch_background.xml',
  ]) {
    final String source = _utf8Output(outputs, path, violations);
    if (!source.contains('@drawable/background') ||
        !source.contains('@drawable/splash') ||
        !_isValidXml(source)) {
      violations.add('[BRANDING_ANDROID_LAUNCH_XML] $path 未引用公共背景与启动 Logo。');
    }
  }

  for (final String path in <String>[
    'android/app/src/main/res/values/styles.xml',
    'android/app/src/main/res/values-night/styles.xml',
  ]) {
    final String source = _utf8Output(outputs, path, violations);
    if (!source.contains('@drawable/launch_background') ||
        !_isValidXml(source)) {
      violations.add('[BRANDING_ANDROID_STYLE] $path 未引用旧版启动资源。');
    }
  }
  for (final String path in <String>[
    'android/app/src/main/res/values-v31/styles.xml',
    'android/app/src/main/res/values-night-v31/styles.xml',
  ]) {
    final String source = _utf8Output(outputs, path, violations);
    if (!source.contains('android:windowSplashScreenBackground') ||
        !source.contains('@drawable/android12splash') ||
        !_isValidXml(source)) {
      violations.add('[BRANDING_ANDROID12_STYLE] $path 未引用 Android 12 启动资源。');
    }
  }
}

void _validateIosOutputReferences(
  BrandingOutputs outputs,
  List<String> violations,
) {
  final Set<String>? iconNames = _assetCatalogFileNames(
    _utf8Output(outputs, '$_iosAppIconDirectory/Contents.json', violations),
  );
  if (iconNames == null ||
      !_sameStringSet(iconNames, _iosIconSizes.keys.toSet())) {
    violations.add(
      '[BRANDING_IOS_ICON_CATALOG] AppIcon Contents.json 与完整图标清单不一致。',
    );
  }

  final Set<String>? launchNames = _assetCatalogFileNames(
    _utf8Output(outputs, '$_iosLaunchImageDirectory/Contents.json', violations),
  );
  if (launchNames == null ||
      !_sameStringSet(launchNames, _iosLaunchImageSizes.keys.toSet())) {
    violations.add(
      '[BRANDING_IOS_LAUNCH_CATALOG] LaunchImage Contents.json 清单无效。',
    );
  }

  final Set<String>? backgroundNames = _assetCatalogFileNames(
    _utf8Output(
      outputs,
      '$_iosLaunchBackgroundDirectory/Contents.json',
      violations,
    ),
  );
  if (backgroundNames == null ||
      !_sameStringSet(backgroundNames, <String>{'background.png'})) {
    violations.add(
      '[BRANDING_IOS_BACKGROUND_CATALOG] LaunchBackground Contents.json 清单无效。',
    );
  }

  final String storyboard = _utf8Output(
    outputs,
    'ios/Runner/Base.lproj/LaunchScreen.storyboard',
    violations,
  );
  if (!storyboard.contains('image="LaunchImage"') ||
      !storyboard.contains('image="LaunchBackground"') ||
      !_isValidXml(storyboard)) {
    violations.add(
      '[BRANDING_IOS_LAUNCH_STORYBOARD] LaunchScreen 未同时引用 Logo 与背景。',
    );
  }
}

String _utf8Output(
  BrandingOutputs outputs,
  String path,
  List<String> violations,
) {
  final Uint8List? bytes = outputs.files[path];
  if (bytes == null) {
    return '';
  }
  try {
    return utf8.decode(bytes);
  } on FormatException {
    violations.add('[BRANDING_OUTPUT_UTF8] $path 不是合法 UTF-8 文本。');
    return '';
  }
}

Set<String>? _assetCatalogFileNames(String source) {
  try {
    final Object? decoded = jsonDecode(source);
    if (decoded is! Map<String, Object?> ||
        decoded['images'] is! List<Object?>) {
      return null;
    }
    final Set<String> names = <String>{};
    for (final Object? entry in decoded['images']! as List<Object?>) {
      if (entry is! Map<String, Object?>) {
        return null;
      }
      final Object? filename = entry['filename'];
      if (filename == null) {
        continue;
      }
      if (filename is! String || filename.isEmpty) {
        return null;
      }
      // 同一物理 PNG 可以同时服务 iPhone 与 iPad 槽位；这里只核对实际文件集合。
      names.add(filename);
    }
    return names;
  } on Object {
    return null;
  }
}

bool _isValidXml(String source) {
  try {
    XmlDocument.parse(source);
    return true;
  } on Object {
    return false;
  }
}

List<String> _validateOwnedOutputEntries(
  Directory projectRoot,
  BrandingOutputs outputs,
) {
  final List<String> violations = <String>[];
  final Map<String, Set<String>> allowedNames = <String, Set<String>>{
    _iosAppIconDirectory: <String>{..._iosIconSizes.keys, 'Contents.json'},
    _iosLaunchImageDirectory: <String>{
      ..._iosLaunchImageSizes.keys,
      'Contents.json',
      'README.md',
    },
    _iosLaunchBackgroundDirectory: <String>{'background.png', 'Contents.json'},
  };
  for (final MapEntry<String, Set<String>> contract in allowedNames.entries) {
    final Directory directory = Directory(
      _joinPath(projectRoot.path, contract.key),
    );
    final FileSystemEntityType directoryType = FileSystemEntity.typeSync(
      directory.path,
      followLinks: false,
    );
    if (directoryType == FileSystemEntityType.notFound) {
      continue;
    }
    if (directoryType != FileSystemEntityType.directory) {
      violations.add(
        '[BRANDING_OUTPUT_UNEXPECTED] ${contract.key} '
        '必须是普通目录且不得为符号链接。',
      );
      continue;
    }
    for (final FileSystemEntity entity in directory.listSync(
      followLinks: false,
    )) {
      final String name = _basename(entity.path);
      final FileSystemEntityType type = FileSystemEntity.typeSync(
        entity.path,
        followLinks: false,
      );
      if (type != FileSystemEntityType.file || !contract.value.contains(name)) {
        violations.add(
          '[BRANDING_OUTPUT_UNEXPECTED] ${contract.key}/$name '
          '不是品牌生成器允许管理的文件。',
        );
      }
    }
  }
  violations.sort();
  return violations;
}

void _assertInstallPathSafe(Directory root, String relativePath) {
  final List<String> segments = relativePath.split('/');
  var current = root.path;
  for (var index = 0; index < segments.length; index += 1) {
    current = _joinPath(current, segments[index]);
    final FileSystemEntityType type = FileSystemEntity.typeSync(
      current,
      followLinks: false,
    );
    if (type == FileSystemEntityType.notFound) {
      continue;
    }
    final bool isLast = index == segments.length - 1;
    final bool valid =
        isLast
            ? type == FileSystemEntityType.file
            : type == FileSystemEntityType.directory;
    if (!valid) {
      throw BrandingGenerationException(<String>[
        '[BRANDING_OUTPUT_PATH] $relativePath 包含符号链接或非预期路径类型。',
      ]);
    }
  }
}

Set<String> _collectSafeOutputPaths(
  Directory root,
  Iterable<String> relativePaths,
  List<String> violations,
) {
  final Set<String> safePaths = <String>{};
  for (final String path in relativePaths.toSet().toList()..sort()) {
    try {
      _assertInstallPathSafe(root, path);
      safePaths.add(path);
    } on BrandingGenerationException catch (error) {
      // 先收集全部路径违规，再由调用方决定终止安装或跳过只读比较；任何不安全目标都不会
      // 在类型检查之前被 File.exists/read 跟随，从而避免读取链接指向的工作区外内容。
      violations.addAll(error.violations);
    }
  }
  return safePaths;
}

Map<String, bool> _captureParentDirectories(
  Directory root,
  Iterable<String> targets,
) {
  final Set<String> directories = <String>{};
  for (final String target in targets) {
    final List<String> segments = target.split('/')..removeLast();
    for (var length = 1; length <= segments.length; length += 1) {
      directories.add(segments.take(length).join('/'));
    }
  }
  return <String, bool>{
    for (final String directory in directories)
      directory: Directory(_joinPath(root.path, directory)).existsSync(),
  };
}

void _removeNewEmptyDirectories(
  Directory root,
  Map<String, bool> originalDirectories,
) {
  final List<String> paths =
      originalDirectories.entries
          .where((MapEntry<String, bool> entry) => !entry.value)
          .map((MapEntry<String, bool> entry) => entry.key)
          .toList()
        ..sort(
          (String left, String right) =>
              right.split('/').length.compareTo(left.split('/').length),
        );
  for (final String path in paths) {
    final Directory directory = Directory(_joinPath(root.path, path));
    if (directory.existsSync() && directory.listSync().isEmpty) {
      directory.deleteSync();
    }
  }
}

Directory _createTransactionDirectory(Directory projectRoot) {
  final Directory dartTool = Directory(
    _joinPath(projectRoot.path, '.dart_tool'),
  );
  final FileSystemEntityType type = FileSystemEntity.typeSync(
    dartTool.path,
    followLinks: false,
  );
  if (type == FileSystemEntityType.notFound) {
    dartTool.createSync();
  } else if (type != FileSystemEntityType.directory) {
    throw BrandingGenerationException(<String>[
      '[BRANDING_STAGING_PATH] .dart_tool 必须是普通目录且不得为符号链接。',
    ]);
  }
  return dartTool.createTempSync('branding_install_');
}

({Directory root, bool check}) _parseArguments(List<String> arguments) {
  var check = false;
  Directory root = Directory.current;
  var index = 0;
  while (index < arguments.length) {
    final String argument = arguments[index];
    if (argument == '--check' && !check) {
      check = true;
      index += 1;
      continue;
    }
    if (argument == '--root' && index + 1 < arguments.length) {
      root = Directory(arguments[index + 1]).absolute;
      index += 2;
      continue;
    }
    throw FormatException('不支持参数 $argument。');
  }
  if (!root.existsSync()) {
    throw const FormatException('--root 必须指向已存在的项目目录。');
  }
  return (root: root, check: check);
}

String _readTextIfRegular(Directory root, String relativePath) {
  final File file = File(_joinPath(root.path, relativePath));
  return _isRegularFileAt(root, relativePath) ? file.readAsStringSync() : '';
}

bool _isRegularFileAt(Directory root, String relativePath) {
  return _hasSafePathType(root, relativePath, FileSystemEntityType.file);
}

bool _isRegularDirectoryAt(Directory root, String relativePath) {
  return _hasSafePathType(root, relativePath, FileSystemEntityType.directory);
}

bool _hasSafePathType(
  Directory root,
  String relativePath,
  FileSystemEntityType expectedLeafType,
) {
  final List<String> segments = relativePath.split('/');
  var current = root.path;
  for (var index = 0; index < segments.length; index += 1) {
    current = _joinPath(current, segments[index]);
    final FileSystemEntityType type = FileSystemEntity.typeSync(
      current,
      followLinks: false,
    );
    if (index == segments.length - 1) {
      return type == expectedLeafType;
    }
    if (type != FileSystemEntityType.directory) {
      return false;
    }
  }
  return false;
}

bool _isBrandingResourceFileName(String name) {
  final String resourceName = name.split('.').first;
  return resourceName == 'ic_launcher' ||
      resourceName.startsWith('ic_launcher_') ||
      resourceName == 'splash' ||
      resourceName == 'android12splash' ||
      resourceName == 'background' ||
      resourceName == 'launch_background';
}

bool _containsExactlyOnce(String source, String value) {
  final int first = source.indexOf(value);
  return first >= 0 && source.indexOf(value, first + value.length) < 0;
}

bool _sameStringSet(Set<String> left, Set<String> right) {
  return left.length == right.length && left.containsAll(right);
}

bool _bytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

Uint8List _normalizeGeneratedOutput(String path, Uint8List bytes) {
  if (!_normalizedAndroid12StylePaths.contains(path)) {
    return Uint8List.fromList(bytes);
  }

  // splash 2.4.6 会在新建的 v31 styles 注释空行中留下缩进空格。这里只规范化
  // 这两个原本不存在的受管输出，避免改动继承自用户工作区的既有 XML 行尾风格。
  final String normalized = _normalizeLineEndings(
    utf8.decode(bytes),
  ).replaceAll(RegExp(r'[ \t]+$', multiLine: true), '');
  return Uint8List.fromList(utf8.encode(normalized));
}

String _normalizeLineEndings(String source) {
  return source.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
}

String _joinPath(String root, String relativePath) {
  final String suffix = relativePath
      .split('/')
      .where((String segment) => segment.isNotEmpty)
      .join(Platform.pathSeparator);
  return suffix.isEmpty ? root : '$root${Platform.pathSeparator}$suffix';
}

String _basename(String path) {
  return path
      .split(RegExp(r'[/\\]'))
      .where((String segment) => segment.isNotEmpty)
      .last;
}
