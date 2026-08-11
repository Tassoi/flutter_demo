import 'dart:io';

final RegExp _directivePattern = RegExp(
  r'^\s*(?:import|export)\s+.*?;',
  multiLine: true,
  dotAll: true,
);
final RegExp _directiveUriPattern = RegExp(r'''['"]([^'"]+)['"]''');
final RegExp _featurePresentationPattern = RegExp(
  r'^lib/features/[^/]+/presentation/',
);

const Map<String, String> _singleAdapterPackages = <String, String>{
  'dio': 'lib/core/network/dio_network_client.dart',
  'flutter_screenutil': 'lib/shared/layout/app_screen_adaptation.dart',
  'flutter_secure_storage': 'lib/core/storage/flutter_secure_value_store.dart',
  'flutter_svg': 'lib/shared/assets/app_assets.dart',
  'go_router': 'lib/app/router/app_router.dart',
  'logging': 'lib/core/logging/package_logging_app_logger.dart',
  'shared_preferences':
      'lib/core/storage/shared_preferences_preference_store.dart',
};
const Set<String> _toolOnlyPackages = <String>{
  'flutter_launcher_icons',
  'flutter_native_splash',
  'icon_font_generator',
  'image',
  'xml',
  'yaml',
};
const String _generatedLocalizationPath = 'lib/app/localization/generated/';

/// 检查 Dart 源码是否遵守项目分层和第三方包使用边界。
///
/// [sources] 的键必须是相对项目根目录、使用 `/` 分隔的 `lib/*.dart`
/// 路径，值是对应源码。[packageName] 是 `pubspec.yaml` 中的包名，用于把
/// `package:` URI 解析回项目路径。返回值经过排序，因此本地与 CI 的错误顺序
/// 稳定；每条错误都包含规则编号、源文件和行号。
///
/// 此函数只分析 `import` 与 `export` 指令，不访问文件系统。CLI 负责读取文件，
/// 测试可以直接传入内存源码验证正常、边界和失败行为。
List<String> validateArchitecture({
  required Map<String, String> sources,
  required String packageName,
}) {
  final List<String> violations = <String>[];

  for (final MapEntry<String, String> source in sources.entries) {
    final String sourcePath = _normalizePath(source.key);
    if (!sourcePath.startsWith('lib/') || !sourcePath.endsWith('.dart')) {
      violations.add(
        '[ARCH_INVALID_SOURCE] $sourcePath:1 '
        '架构检查只接受 lib/ 下的 Dart 源码。',
      );
      continue;
    }

    for (final RegExpMatch directive in _directivePattern.allMatches(
      source.value,
    )) {
      final String directiveText = directive.group(0)!;
      for (final RegExpMatch uriMatch in _directiveUriPattern.allMatches(
        directiveText,
      )) {
        final String importUri = uriMatch.group(1)!;
        final int line = _lineNumber(
          source.value,
          directive.start + uriMatch.start,
        );
        _validateDirective(
          sourcePath: sourcePath,
          importUri: importUri,
          line: line,
          packageName: packageName,
          violations: violations,
        );
      }
    }
  }

  violations.sort();
  return violations;
}

/// 从当前项目读取源码并执行架构边界检查。
///
/// 可选参数 `--root <path>` 仅用于 CI 或从其他目录调用；未传入时使用当前目录。
/// 检查失败返回非零退出码，不会修改任何源码或生成产物。
void main(List<String> arguments) {
  late final Directory projectRoot;
  try {
    projectRoot = _resolveProjectRoot(arguments);
  } on FormatException catch (error) {
    stderr.writeln('架构检查参数错误：${error.message}');
    stderr.writeln('用法：dart tool/ci/check_architecture.dart [--root <path>]');
    exitCode = 64;
    return;
  }

  final File pubspec = File(
    '${projectRoot.path}${Platform.pathSeparator}pubspec.yaml',
  );
  final Directory libDirectory = Directory(
    '${projectRoot.path}${Platform.pathSeparator}lib',
  );
  if (!_isRegularFile(pubspec) || !_isDirectory(libDirectory)) {
    stderr.writeln('架构检查失败：项目根目录缺少 pubspec.yaml 或 lib/。');
    exitCode = 1;
    return;
  }

  late final String packageName;
  try {
    packageName = _readPackageName(pubspec.readAsStringSync());
  } on FormatException catch (error) {
    stderr.writeln('架构检查失败：${error.message}');
    exitCode = 1;
    return;
  }
  final Map<String, String> sources = _readDartSources(
    projectRoot: projectRoot,
    libDirectory: libDirectory,
  );
  final List<String> violations = validateArchitecture(
    sources: sources,
    packageName: packageName,
  );

  if (violations.isNotEmpty) {
    stderr.writeln('架构边界检查失败，共 ${violations.length} 项：');
    for (final String violation in violations) {
      stderr.writeln('- $violation');
    }
    exitCode = 1;
    return;
  }

  stdout.writeln('架构边界检查通过，共检查 ${sources.length} 个 Dart 文件。');
}

void _validateDirective({
  required String sourcePath,
  required String importUri,
  required int line,
  required String packageName,
  required List<String> violations,
}) {
  final Uri? parsedUri = Uri.tryParse(importUri);
  if (parsedUri == null) {
    violations.add('[ARCH_INVALID_URI] $sourcePath:$line 无法解析导入 URI。');
    return;
  }

  if (parsedUri.scheme.isEmpty) {
    if (_isAllowedGeneratedLocalizationImport(sourcePath, importUri)) {
      return;
    }
    violations.add(
      '[ARCH_RELATIVE_IMPORT] $sourcePath:$line '
      'lib/ 内必须使用 package 导入，禁止相对导入 `$importUri`。',
    );
    return;
  }

  if (parsedUri.scheme != 'package') {
    return;
  }

  final List<String> segments = parsedUri.pathSegments;
  if (segments.isEmpty) {
    violations.add('[ARCH_INVALID_URI] $sourcePath:$line package URI 缺少包名。');
    return;
  }

  final String importedPackage = segments.first;
  if (importedPackage == packageName) {
    _validateProjectDependency(
      sourcePath: sourcePath,
      parsedUri: parsedUri,
      line: line,
      packageName: packageName,
      violations: violations,
    );
    return;
  }

  _validateRestrictedPackage(
    sourcePath: sourcePath,
    importedPackage: importedPackage,
    line: line,
    violations: violations,
  );
}

bool _isAllowedGeneratedLocalizationImport(
  String sourcePath,
  String importUri,
) {
  return switch ((sourcePath, importUri)) {
    (
      'lib/app/localization/generated/app_localizations.dart',
      'app_localizations_en.dart' || 'app_localizations_zh.dart',
    ) =>
      true,
    (
      'lib/app/localization/generated/app_localizations_en.dart' ||
          'lib/app/localization/generated/app_localizations_zh.dart',
      'app_localizations.dart',
    ) =>
      true,
    _ => false,
  };
}

void _validateProjectDependency({
  required String sourcePath,
  required Uri parsedUri,
  required int line,
  required String packageName,
  required List<String> violations,
}) {
  final List<String> uriSegments = parsedUri.pathSegments;
  if (parsedUri.hasAuthority ||
      parsedUri.hasQuery ||
      parsedUri.hasFragment ||
      uriSegments.length < 2 ||
      uriSegments.first != packageName) {
    violations.add(
      '[ARCH_INVALID_PROJECT_IMPORT] $sourcePath:$line '
      '项目 package URI 必须是无 authority、query、fragment 的 lib/ 内路径。',
    );
    return;
  }

  final List<String> importedSegments = <String>['lib', ...uriSegments.skip(1)];
  if (importedSegments.any(
    (String segment) =>
        segment.isEmpty ||
        segment == '.' ||
        segment == '..' ||
        segment.contains('\\'),
  )) {
    violations.add(
      '[ARCH_INVALID_PROJECT_IMPORT] $sourcePath:$line '
      '项目导入路径不得包含空段、`.` 或 `..`。',
    );
    return;
  }
  final String importedPath = importedSegments.join('/');

  if (sourcePath == 'lib/main.dart' && !importedPath.startsWith('lib/app/')) {
    violations.add(
      '[ARCH_MAIN_BOUNDARY] $sourcePath:$line '
      '最小入口只能导入 app/ 组装层。',
    );
  }

  final String? sourceLayer = _layerOf(sourcePath);
  final String? importedLayer = _layerOf(importedPath);
  if ((sourceLayer == 'core' || sourceLayer == 'shared') &&
      (importedLayer == 'app' || importedLayer == 'features')) {
    violations.add(
      '[ARCH_REVERSE_DEPENDENCY] $sourcePath:$line '
      '$sourceLayer/ 不得反向依赖 $importedLayer/。',
    );
  }

  if (sourceLayer != 'features') {
    return;
  }

  if (importedLayer == 'app') {
    violations.add(
      '[ARCH_FEATURE_APP_DEPENDENCY] $sourcePath:$line '
      'Feature 不得依赖 app/ 组装层。',
    );
  }

  if (importedLayer == 'features') {
    final String? sourceFeature = _featureName(sourcePath);
    final String? importedFeature = _featureName(importedPath);
    if (sourceFeature == null ||
        importedFeature == null ||
        sourceFeature != importedFeature) {
      violations.add(
        '[ARCH_CROSS_FEATURE_DEPENDENCY] $sourcePath:$line '
        'Feature 不得导入其他 Feature 的内部实现。',
      );
    }
  }
}

void _validateRestrictedPackage({
  required String sourcePath,
  required String importedPackage,
  required int line,
  required List<String> violations,
}) {
  if (_toolOnlyPackages.contains(importedPackage)) {
    violations.add(
      '[ARCH_TOOL_DEPENDENCY] $sourcePath:$line '
      '`$importedPackage` 只能由 tool/ 下的仓库生成器使用，不得进入运行时代码。',
    );
    return;
  }

  if (importedPackage == 'intl' || importedPackage == 'flutter_localizations') {
    if (!sourcePath.startsWith(_generatedLocalizationPath)) {
      violations.add(
        '[ARCH_LOCALIZATION_BOUNDARY] $sourcePath:$line '
        '`$importedPackage` 只能由 Flutter 本地化生成产物使用。',
      );
    }
    return;
  }

  if (importedPackage == 'flutter_riverpod') {
    final bool allowed =
        sourcePath.startsWith('lib/app/') ||
        _featurePresentationPattern.hasMatch(sourcePath);
    if (!allowed) {
      violations.add(
        '[ARCH_RIVERPOD_BOUNDARY] $sourcePath:$line '
        'Riverpod 只能用于 app/ 组装或 Feature presentation。',
      );
    }
    return;
  }

  final String? allowedPath = _singleAdapterPackages[importedPackage];
  if (allowedPath != null && sourcePath != allowedPath) {
    violations.add(
      '[ARCH_ADAPTER_BOUNDARY] $sourcePath:$line '
      '`$importedPackage` 只能由 $allowedPath 适配。',
    );
  }
}

Map<String, String> _readDartSources({
  required Directory projectRoot,
  required Directory libDirectory,
}) {
  final List<File> files =
      libDirectory
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((File file) => file.path.endsWith('.dart'))
          .toList()
        ..sort((File left, File right) => left.path.compareTo(right.path));
  final Map<String, String> sources = <String, String>{};
  final String rootPrefix = '${projectRoot.path}${Platform.pathSeparator}';
  for (final File file in files) {
    final String relativePath = file.path.substring(rootPrefix.length);
    sources[_normalizePath(relativePath)] = file.readAsStringSync();
  }
  return sources;
}

String _readPackageName(String pubspecContent) {
  final RegExpMatch? match = RegExp(
    r'^name:\s*([a-z][a-z0-9_]*)\s*(?:#.*)?$',
    multiLine: true,
  ).firstMatch(pubspecContent);
  if (match == null) {
    throw const FormatException('pubspec.yaml 缺少合法的顶层 name。');
  }
  return match.group(1)!;
}

Directory _resolveProjectRoot(List<String> arguments) {
  if (arguments.isEmpty) {
    return Directory.current.absolute;
  }
  if (arguments.length == 2 && arguments.first == '--root') {
    return Directory(arguments[1]).absolute;
  }
  throw const FormatException('只支持可选参数 `--root <path>`。');
}

String _normalizePath(String path) => path.replaceAll('\\', '/');

bool _isRegularFile(File file) {
  return FileSystemEntity.typeSync(file.path, followLinks: false) ==
      FileSystemEntityType.file;
}

bool _isDirectory(Directory directory) {
  return FileSystemEntity.typeSync(directory.path, followLinks: false) ==
      FileSystemEntityType.directory;
}

String? _layerOf(String path) {
  final List<String> segments = path.split('/');
  return segments.length >= 3 && segments.first == 'lib' ? segments[1] : null;
}

String? _featureName(String path) {
  final List<String> segments = path.split('/');
  return segments.length >= 4 &&
          segments.first == 'lib' &&
          segments[1] == 'features'
      ? segments[2]
      : null;
}

int _lineNumber(String source, int offset) {
  return RegExp(r'\n').allMatches(source.substring(0, offset)).length + 1;
}
