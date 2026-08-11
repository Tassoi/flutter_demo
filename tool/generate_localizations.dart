import 'dart:convert';
import 'dart:io';

/// 本地化生成器唯一接受的 `lib/app/localization/l10n.yaml` 配置。
///
/// 配置采用完整字节契约，而不是在工具内实现一个不完整的 YAML 解析器。新增语言或调整
/// Flutter 生成选项时，必须同时审查此常量、ARB 资源、生成文件清单和相关测试；不匹配会在
/// 官方生成器运行前失败，因此任意输出目录不能借配置漂移越过本工具的白名单。
const String requiredLocalizationConfiguration =
    '''arb-dir: lib/app/localization/arb
template-arb-file: app_en.arb
output-dir: lib/app/localization/generated
output-localization-file: app_localizations.dart
output-class: AppLocalizations
synthetic-package: false
required-resource-attributes: true
nullable-getter: false
header-file: generated_header.txt
untranslated-messages-file: lib/app/localization/generated/untranslated_messages.json
preferred-supported-locales:
  - en
  - zh
format: true
use-escaping: true
use-named-parameters: true
suppress-warnings: false
''';

/// 所有生成 Dart 文件必须携带的中文来源标记。
const String requiredGeneratedLocalizationHeader =
    '''/// 此文件由 `dart run tool/generate_localizations.dart` 基于 ARB 资源生成。
/// 请勿手工修改；更新 `lib/app/localization/arb/` 后重新运行生成命令。
''';

/// 仓库内唯一允许维护的本地化生成配置路径。
///
/// 该文件有意不放在仓库根目录。Flutter 3.29 的编译目标只要发现根目录 `l10n.yaml`，就会在
/// `flutter run`、`flutter test` 或平台构建时直接重写生成文件，绕过本工具的中文注释归一化
/// 与写入前验证。专项工具会把此配置复制到系统临时项目的根目录后再调用官方生成器，因此既
/// 保留官方工具链，也不会让普通开发命令修改已提交产物。
const String localizationConfigurationPath = 'lib/app/localization/l10n.yaml';

const Set<String> _expectedResourceFiles = <String>{
  'app_en.arb',
  'app_zh.arb',
  'generated_header.txt',
};
const Set<String> _expectedOutputFiles = <String>{
  'app_localizations.dart',
  'app_localizations_en.dart',
  'app_localizations_zh.dart',
  'untranslated_messages.json',
};
const String _resourceDirectoryPath = 'lib/app/localization/arb';
const String _outputDirectoryPath = 'lib/app/localization/generated';
const String _flutterConfigurationFileName = 'l10n.yaml';
const String _flutterLocalizationDependencyFile = 'gen_localizations.d';
const String _templateResourceFile = 'app_en.arb';
const Set<String> _supportedLocales = <String>{'en', 'zh'};
final RegExp _hanCharacterPattern = RegExp(r'[\u3400-\u9fff]');

const String _rawBaseClassDocumentation =
    '''/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
''';

const String _chineseBaseClassDocumentation = '''/// 提供当前 Widget 树的类型安全本地化文案。
///
/// 调用方通过 [AppLocalizations.of] 读取当前语言资源。应用根必须注册
/// [localizationsDelegates] 与 [supportedLocales]；Feature 不应自行创建代理或维护另一份
/// 支持语言列表。人工维护源仅位于 ARB 目录，本文件必须通过仓库生成命令更新。
''';

const String _rawDelegateDocumentation =
    '''  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
''';

const String _chineseDelegateDocumentation =
    '''  /// 应用文案代理与 Flutter Material、Cupertino、Widget 默认代理的固定集合。
  ///
  /// 应用若需要新增代理，应在根部显式追加；Feature 不得复制或改写本列表。
''';

const String _stagingPubspec = '''name: flutter_template_localization_staging
publish_to: "none"
environment:
  sdk: ">=3.7.0 <3.8.0"
dependencies:
  flutter:
    sdk: flutter
  flutter_localizations:
    sdk: flutter
  intl: 0.19.0
flutter:
  generate: true
''';

/// 校验本地化配置和人工维护资源的完整性。
///
/// [configuration] 必须与仓库固定配置逐字节一致。[resources] 的键是 ARB 目录中的文件名，
/// 值是 UTF-8 文本；当前只接受英语模板、中文资源和中文生成头。每个用户文案都必须在两种
/// locale 中存在且非空，并在各自的 `@key` 元数据中提供中文说明。占位符若存在，也必须为
/// 每个占位符提供中文说明。
///
/// 返回稳定排序且不包含实际文案内容的违规列表，便于 CI 报告问题而不把未来可能出现的
/// 用户数据复制到日志。函数不访问文件系统，也不会修改输入。
List<String> validateLocalizationInputs({
  required String configuration,
  required Map<String, String> resources,
}) {
  final List<String> violations = <String>[];
  if (_normalizeLineEndings(configuration) !=
      requiredLocalizationConfiguration) {
    violations.add(
      '[L10N_CONFIG_DRIFT] $localizationConfigurationPath 与受支持的固定配置不一致。',
    );
  }

  final Set<String> resourceNames = resources.keys.toSet();
  if (!_sameStringSet(resourceNames, _expectedResourceFiles)) {
    violations.add('[L10N_RESOURCE_MANIFEST] ARB 输入目录文件清单不符合约定。');
  }
  if (_normalizeLineEndings(resources['generated_header.txt'] ?? '') !=
      requiredGeneratedLocalizationHeader) {
    violations.add('[L10N_HEADER_INVALID] 生成文件头必须使用固定中文来源说明。');
  }

  final Map<String, Map<String, Object?>> decodedResources =
      <String, Map<String, Object?>>{};
  for (final String fileName in <String>['app_en.arb', 'app_zh.arb']) {
    final String? source = resources[fileName];
    if (source == null) {
      continue;
    }
    try {
      final Object? decoded = jsonDecode(source);
      if (decoded is! Map<String, Object?>) {
        violations.add('[L10N_ARB_OBJECT] $fileName 顶层必须是 JSON 对象。');
        continue;
      }
      decodedResources[fileName] = decoded;
    } on FormatException {
      violations.add('[L10N_ARB_JSON] $fileName 不是合法 JSON。');
    }
  }

  final Map<String, Set<String>> messageKeys = <String, Set<String>>{};
  for (final MapEntry<String, Map<String, Object?>> resource
      in decodedResources.entries) {
    final String fileName = resource.key;
    final Map<String, Object?> values = resource.value;
    final String expectedLocale = fileName == 'app_en.arb' ? 'en' : 'zh';
    if (values['@@locale'] != expectedLocale ||
        !_supportedLocales.contains(expectedLocale)) {
      violations.add('[L10N_LOCALE_INVALID] $fileName 的 locale 声明无效。');
    }

    final Set<String> keys =
        values.keys.where((String key) => !key.startsWith('@')).toSet();
    messageKeys[fileName] = keys;
    for (final String key in keys) {
      final Object? message = values[key];
      if (message is! String || message.isEmpty) {
        violations.add('[L10N_MESSAGE_EMPTY] $fileName 的 $key 必须是非空文案。');
      }

      final Object? rawMetadata = values['@$key'];
      if (rawMetadata is! Map<String, Object?>) {
        violations.add('[L10N_METADATA_MISSING] $fileName 的 $key 缺少元数据。');
        continue;
      }
      final Object? description = rawMetadata['description'];
      if (description is! String ||
          !_hanCharacterPattern.hasMatch(description)) {
        violations.add('[L10N_DESCRIPTION_CHINESE] $fileName 的 $key 缺少中文说明。');
      }

      final Object? rawPlaceholders = rawMetadata['placeholders'];
      if (rawPlaceholders == null) {
        continue;
      }
      if (rawPlaceholders is! Map<String, Object?>) {
        violations.add(
          '[L10N_PLACEHOLDERS_INVALID] $fileName 的 $key 占位符元数据无效。',
        );
        continue;
      }
      for (final MapEntry<String, Object?> placeholder
          in rawPlaceholders.entries) {
        final Object? rawPlaceholder = placeholder.value;
        final Object? placeholderDescription =
            rawPlaceholder is Map<String, Object?>
                ? rawPlaceholder['description']
                : null;
        if (placeholderDescription is! String ||
            !_hanCharacterPattern.hasMatch(placeholderDescription)) {
          violations.add(
            '[L10N_PLACEHOLDER_DESCRIPTION] $fileName 的 $key.${placeholder.key} 缺少中文说明。',
          );
        }
      }
    }
  }

  final Set<String>? templateKeys = messageKeys[_templateResourceFile];
  for (final MapEntry<String, Set<String>> resource in messageKeys.entries) {
    if (templateKeys != null && !_sameStringSet(resource.value, templateKeys)) {
      violations.add('[L10N_KEYSET_MISMATCH] ${resource.key} 的文案键与英语模板不一致。');
    }
  }

  violations.sort();
  return violations;
}

/// 把 Flutter 3.29 官方生成器的已知英文注释转换为中文。
///
/// [relativePath] 必须是固定输出清单中的 Dart 文件名，[source] 必须包含固定中文生成头。
/// 主文件会移除自动附加的英语资源示例，并把类、代理、支持语言和查找分支说明替换为中文；
/// 英语与中文实现文件只替换各自的类说明。[expectedMessageCount] 用于证明每个模板文案都
/// 恰好移除了一段官方英语示例，防止 Flutter 模板升级后静默漏转。
///
/// 未知英文注释、模板片段漂移或数量不匹配会抛 [FormatException]。调用方必须先在临时目录
/// 完成本函数和全部输出验证，再触碰仓库目标目录。
String normalizeGeneratedLocalizationSource({
  required String relativePath,
  required String source,
  required int expectedMessageCount,
}) {
  var normalized = _normalizeLineEndings(source);
  if (!normalized.startsWith('$requiredGeneratedLocalizationHeader\n')) {
    throw FormatException('$relativePath 缺少固定中文生成头。');
  }

  switch (relativePath) {
    case 'app_localizations.dart':
      normalized = _replaceExactlyOnce(
        source: normalized,
        before: _rawBaseClassDocumentation,
        after: _chineseBaseClassDocumentation,
        label: '本地化基类说明',
      );
      normalized = _replaceExactlyOnce(
        source: normalized,
        before: _rawDelegateDocumentation,
        after: _chineseDelegateDocumentation,
        label: '代理列表说明',
      );
      normalized = _replaceExactlyOnce(
        source: normalized,
        before:
            "  /// A list of this localizations delegate's supported locales.\n",
        after: '  /// 当前生成产物明确支持的语言列表。\n',
        label: '支持语言说明',
      );
      normalized = _replaceExactlyOnce(
        source: normalized,
        before: '  // Lookup logic when only language code is specified.\n',
        after: '  // 当前只维护通用语言码；地区变体由应用根解析到对应通用语言。\n',
        label: '语言查找说明',
      );
      final _MessageExampleRemoval removal = _removeEnglishMessageExamples(
        normalized,
      );
      if (removal.count != expectedMessageCount) {
        throw FormatException(
          '英语文案示例数量应为 $expectedMessageCount，实际为 ${removal.count}。',
        );
      }
      normalized = removal.source;
    case 'app_localizations_en.dart':
      normalized = _replaceExactlyOnce(
        source: normalized,
        before: '/// The translations for English (`en`).\n',
        after: '/// 英语（`en`）文案实现。\n',
        label: '英语实现说明',
      );
    case 'app_localizations_zh.dart':
      normalized = _replaceExactlyOnce(
        source: normalized,
        before: '/// The translations for Chinese (`zh`).\n',
        after: '/// 中文（`zh`）文案实现。\n',
        label: '中文实现说明',
      );
    default:
      throw FormatException('不支持规范化 $relativePath。');
  }

  _rejectUnknownGeneratedComments(relativePath, normalized);
  return normalized.endsWith('\n') ? normalized : '$normalized\n';
}

/// 比较临时生成结果与仓库已提交结果，不执行任何写入。
///
/// [expected] 和 [actual] 的键都是生成目录下的直接文件名，值是原始字节。文件缺失、出现
/// 白名单外文件或同名文件字节变化都会返回稳定违规项；实际内容不会进入消息。该纯函数是
/// `--check` 严格只读语义的核心，调用方只负责从临时目录和项目目录读取字节。
List<String> compareLocalizationOutputs({
  required Map<String, List<int>> expected,
  required Map<String, List<int>> actual,
}) {
  final List<String> violations = <String>[];
  final Set<String> allNames = <String>{...expected.keys, ...actual.keys};
  final List<String> sortedNames = allNames.toList()..sort();
  for (final String name in sortedNames) {
    final List<int>? expectedBytes = expected[name];
    final List<int>? actualBytes = actual[name];
    if (expectedBytes == null) {
      violations.add('[L10N_OUTPUT_UNEXPECTED] $name 不在生成产物白名单中。');
    } else if (actualBytes == null) {
      violations.add('[L10N_OUTPUT_MISSING] $name 尚未生成。');
    } else if (!_sameBytes(expectedBytes, actualBytes)) {
      violations.add('[L10N_OUTPUT_STALE] $name 已过期。');
    }
  }
  return violations;
}

/// 验证本地化配置不会被 Flutter 普通编译流程直接消费。
///
/// [projectRoot] 必须包含 [localizationConfigurationPath] 与固定 ARB 目录，同时不得包含根目录
/// `l10n.yaml`。后一个约束防止 Flutter 3.29 在测试、运行或构建前绕过专项工具重写中文生成
/// 注释。函数只读取文件系统并返回稳定错误码，不创建目录或修改任何输入。
List<String> validateLocalizationProjectLayout(Directory projectRoot) {
  final List<String> violations = <String>[];
  final File rootConfiguration = File(
    _join(projectRoot.path, _flutterConfigurationFileName),
  );
  if (rootConfiguration.existsSync()) {
    violations.add(
      '[L10N_ROOT_CONFIG_FORBIDDEN] 根目录 l10n.yaml 会让 Flutter 构建绕过专项生成器。',
    );
  }

  final File configuration = File(
    _join(projectRoot.path, localizationConfigurationPath),
  );
  if (!configuration.existsSync()) {
    violations.add('[L10N_CONFIG_MISSING] 缺少 $localizationConfigurationPath。');
  }

  final Directory resourceDirectory = Directory(
    _join(projectRoot.path, _resourceDirectoryPath),
  );
  if (!resourceDirectory.existsSync()) {
    violations.add('[L10N_RESOURCE_DIRECTORY_MISSING] 缺少 ARB 输入目录。');
  }

  final Directory flutterBuildCache = Directory(
    _join(projectRoot.path, '.dart_tool/flutter_build'),
  );
  if (flutterBuildCache.existsSync()) {
    final bool hasLegacyDependencyFile = flutterBuildCache
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .any(
          (File file) =>
              _basename(file.path) == _flutterLocalizationDependencyFile,
        );
    if (hasLegacyDependencyFile) {
      violations.add(
        '[L10N_LEGACY_BUILD_CACHE] 旧 Flutter 本地化构建缓存可能删除已提交产物；请先执行 flutter clean。',
      );
    }
  }
  return violations;
}

/// 生成或只读检查项目本地化产物。
///
/// 支持 `--check` 和 `--root <path>`。无论模式如何，官方 Flutter 生成器都只在系统临时
/// 目录运行；全部 ARB、缺失翻译、文件清单与中文注释验证通过后，普通模式才整体替换固定
/// 输出目录，检查模式则只做字节比较。参数错误返回 64，生成或检查失败返回 1。
Future<void> main(List<String> arguments) async {
  late final _GeneratorOptions options;
  try {
    options = _parseOptions(arguments);
  } on FormatException catch (error) {
    stderr.writeln('本地化生成参数错误：${error.message}');
    stderr.writeln(
      '用法：dart run tool/generate_localizations.dart [--check] [--root <path>]',
    );
    exitCode = 64;
    return;
  }

  try {
    final List<String> layoutViolations = validateLocalizationProjectLayout(
      options.projectRoot,
    );
    if (layoutViolations.isNotEmpty) {
      _writeViolations('本地化项目结构检查失败', layoutViolations);
      exitCode = 1;
      return;
    }

    final _LocalizationInputs inputs = _readInputs(options.projectRoot);
    final List<String> inputViolations = validateLocalizationInputs(
      configuration: inputs.configuration,
      resources: inputs.resources,
    );
    if (inputViolations.isNotEmpty) {
      _writeViolations('本地化输入检查失败', inputViolations);
      exitCode = 1;
      return;
    }

    final int messageCount = _readTemplateMessageCount(
      inputs.resources[_templateResourceFile]!,
    );
    final Map<String, List<int>> expected = await _generateInStaging(
      inputs: inputs,
      expectedMessageCount: messageCount,
    );
    if (options.checkOnly) {
      final Map<String, List<int>> actual = _readOutputDirectory(
        options.projectRoot,
      );
      final List<String> violations = compareLocalizationOutputs(
        expected: expected,
        actual: actual,
      );
      if (violations.isNotEmpty) {
        _writeViolations('本地化生成产物检查失败', violations);
        exitCode = 1;
        return;
      }
      stdout.writeln('本地化生成产物检查通过：资源完整且已提交文件为最新。');
      return;
    }

    _replaceOutputDirectoryAtomically(options.projectRoot, expected);
    stdout.writeln('本地化生成完成：已验证并更新 ${expected.length} 个文件。');
  } on _GeneratorProcessException catch (error) {
    stderr.writeln('本地化生成失败：官方 Flutter 生成器返回 ${error.exitCode}。');
    if (error.output.trim().isNotEmpty) {
      stderr.writeln(error.output.trim());
    }
    exitCode = 1;
  } on FileSystemException catch (error) {
    stderr.writeln('本地化生成失败：无法安全读写所需文件（${error.message}）。');
    exitCode = 1;
  } on FormatException catch (error) {
    stderr.writeln('本地化生成失败：${error.message}');
    exitCode = 1;
  } on ProcessException catch (error) {
    stderr.writeln('本地化生成失败：无法执行 Flutter（${error.message}）。');
    exitCode = 1;
  }
}

_LocalizationInputs _readInputs(Directory projectRoot) {
  final File configuration = File(
    _join(projectRoot.path, localizationConfigurationPath),
  );
  final Directory resourceDirectory = Directory(
    _join(projectRoot.path, _resourceDirectoryPath),
  );
  final Map<String, String> resources = <String, String>{};
  for (final FileSystemEntity entity in resourceDirectory.listSync()) {
    if (entity is! File) {
      resources[_basename(entity.path)] = '';
      continue;
    }
    resources[_basename(entity.path)] = entity.readAsStringSync();
  }
  return _LocalizationInputs(
    configuration: configuration.readAsStringSync(),
    resources: resources,
  );
}

Future<Map<String, List<int>>> _generateInStaging({
  required _LocalizationInputs inputs,
  required int expectedMessageCount,
}) async {
  final Directory stagingRoot = Directory.systemTemp.createTempSync(
    'flutter-template-l10n-',
  );
  try {
    File(
      _join(stagingRoot.path, 'pubspec.yaml'),
    ).writeAsStringSync(_stagingPubspec, flush: true);
    File(
      _join(stagingRoot.path, _flutterConfigurationFileName),
    ).writeAsStringSync(requiredLocalizationConfiguration, flush: true);
    final Directory stagingResources = Directory(
      _join(stagingRoot.path, _resourceDirectoryPath),
    )..createSync(recursive: true);
    for (final String name in _expectedResourceFiles) {
      File(
        _join(stagingResources.path, name),
      ).writeAsStringSync(inputs.resources[name]!, flush: true);
    }

    final ProcessResult result = await Process.run(
      'flutter',
      const <String>['gen-l10n'],
      workingDirectory: stagingRoot.path,
      runInShell: Platform.isWindows,
    );
    if (result.exitCode != 0) {
      throw _GeneratorProcessException(
        exitCode: result.exitCode,
        output: '${result.stdout}\n${result.stderr}',
      );
    }

    final Directory outputDirectory = Directory(
      _join(stagingRoot.path, _outputDirectoryPath),
    );
    final Map<String, List<int>> rawOutputs = _readFlatDirectory(
      outputDirectory,
    );
    if (!_sameStringSet(rawOutputs.keys.toSet(), _expectedOutputFiles)) {
      throw const FormatException('官方生成器输出了非预期文件清单。');
    }

    final Object? untranslated = jsonDecode(
      utf8.decode(rawOutputs['untranslated_messages.json']!),
    );
    if (untranslated is! Map<String, Object?> || untranslated.isNotEmpty) {
      throw const FormatException('存在缺失翻译，生成产物不会更新。');
    }

    final Map<String, List<int>> normalized = <String, List<int>>{
      'untranslated_messages.json': utf8.encode('{}'),
    };
    for (final String name in <String>[
      'app_localizations.dart',
      'app_localizations_en.dart',
      'app_localizations_zh.dart',
    ]) {
      final String source = utf8.decode(rawOutputs[name]!);
      normalized[name] = utf8.encode(
        normalizeGeneratedLocalizationSource(
          relativePath: name,
          source: source,
          expectedMessageCount: expectedMessageCount,
        ),
      );
    }
    return normalized;
  } finally {
    if (stagingRoot.existsSync()) {
      stagingRoot.deleteSync(recursive: true);
    }
  }
}

Map<String, List<int>> _readOutputDirectory(Directory projectRoot) {
  final Directory output = Directory(
    _join(projectRoot.path, _outputDirectoryPath),
  );
  return output.existsSync()
      ? _readFlatDirectory(output)
      : <String, List<int>>{};
}

Map<String, List<int>> _readFlatDirectory(Directory directory) {
  if (!directory.existsSync()) {
    return <String, List<int>>{};
  }
  final Map<String, List<int>> outputs = <String, List<int>>{};
  for (final FileSystemEntity entity in directory.listSync(recursive: true)) {
    final String relativePath = _relativeTo(directory.path, entity.path);
    if (entity is File) {
      outputs[relativePath] = entity.readAsBytesSync();
    } else {
      outputs['$relativePath/'] = const <int>[];
    }
  }
  return outputs;
}

void _replaceOutputDirectoryAtomically(
  Directory projectRoot,
  Map<String, List<int>> outputs,
) {
  final Directory target = Directory(
    _join(projectRoot.path, _outputDirectoryPath),
  );
  target.parent.createSync(recursive: true);
  final Directory incoming = target.parent.createTempSync('.l10n-next-');
  Directory? backup;
  try {
    final List<String> names = outputs.keys.toList()..sort();
    for (final String name in names) {
      File(
        _join(incoming.path, name),
      ).writeAsBytesSync(outputs[name]!, flush: true);
    }

    if (target.existsSync()) {
      backup = target.parent.createTempSync('.l10n-backup-');
      backup.deleteSync();
      target.renameSync(backup.path);
    }
    try {
      incoming.renameSync(target.path);
    } on Object {
      if (backup != null && backup.existsSync() && !target.existsSync()) {
        backup.renameSync(target.path);
      }
      rethrow;
    }
    if (backup != null && backup.existsSync()) {
      backup.deleteSync(recursive: true);
    }
  } finally {
    if (incoming.existsSync()) {
      incoming.deleteSync(recursive: true);
    }
  }
}

int _readTemplateMessageCount(String templateSource) {
  final Object? decoded = jsonDecode(templateSource);
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('英语 ARB 模板顶层必须是 JSON 对象。');
  }
  return decoded.keys.where((String key) => !key.startsWith('@')).length;
}

_MessageExampleRemoval _removeEnglishMessageExamples(String source) {
  final List<String> lines = source.split('\n');
  final List<String> output = <String>[];
  var count = 0;
  for (var index = 0; index < lines.length; index += 1) {
    final String line = lines[index];
    if (line != '  /// In en, this message translates to:') {
      output.add(line);
      continue;
    }
    if (output.isEmpty || output.last != '  ///') {
      throw const FormatException('官方英语文案示例前缺少预期空文档行。');
    }
    if (index + 1 >= lines.length ||
        !lines[index + 1].startsWith("  /// **'") ||
        !lines[index + 1].endsWith("'**")) {
      throw const FormatException('官方英语文案示例格式发生变化。');
    }
    output.removeLast();
    index += 1;
    count += 1;
  }
  return _MessageExampleRemoval(source: output.join('\n'), count: count);
}

void _rejectUnknownGeneratedComments(String relativePath, String source) {
  const Set<String> allowedTechnicalComments = <String>{
    '// ignore: unused_import',
    '// ignore_for_file: type=lint',
  };
  final List<String> lines = source.split('\n');
  for (var index = 0; index < lines.length; index += 1) {
    final String comment = lines[index].trimLeft();
    if (!comment.startsWith('//')) {
      continue;
    }
    if (allowedTechnicalComments.contains(comment)) {
      continue;
    }
    final String body = comment.substring(comment.startsWith('///') ? 3 : 2);
    if (body.trim().isEmpty || _hanCharacterPattern.hasMatch(body)) {
      continue;
    }
    throw FormatException('$relativePath 第 ${index + 1} 行存在未知英文生成注释。');
  }
}

String _replaceExactlyOnce({
  required String source,
  required String before,
  required String after,
  required String label,
}) {
  final int first = source.indexOf(before);
  if (first < 0 || first != source.lastIndexOf(before)) {
    throw FormatException('Flutter 生成模板的$label发生变化。');
  }
  return source.replaceRange(first, first + before.length, after);
}

_GeneratorOptions _parseOptions(List<String> arguments) {
  var checkOnly = false;
  Directory projectRoot = Directory.current;
  for (var index = 0; index < arguments.length; index += 1) {
    switch (arguments[index]) {
      case '--check':
        if (checkOnly) {
          throw const FormatException('不得重复传入 --check。');
        }
        checkOnly = true;
      case '--root':
        if (index + 1 >= arguments.length || arguments[index + 1].isEmpty) {
          throw const FormatException('--root 必须紧跟目录路径。');
        }
        index += 1;
        projectRoot = Directory(arguments[index]).absolute;
      default:
        throw FormatException('未知参数 ${arguments[index]}。');
    }
  }
  return _GeneratorOptions(projectRoot: projectRoot, checkOnly: checkOnly);
}

void _writeViolations(String title, List<String> violations) {
  stderr.writeln('$title，共 ${violations.length} 项：');
  for (final String violation in violations) {
    stderr.writeln('- $violation');
  }
}

String _normalizeLineEndings(String source) =>
    source.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

String _join(String root, String relativePath) =>
    '$root${Platform.pathSeparator}${relativePath.replaceAll('/', Platform.pathSeparator)}';

String _basename(String path) =>
    path
        .split(Platform.pathSeparator)
        .where((String part) => part.isNotEmpty)
        .last;

String _relativeTo(String root, String path) {
  final String prefix = '$root${Platform.pathSeparator}';
  if (!path.startsWith(prefix)) {
    throw const FormatException('生成文件不在受控输出目录中。');
  }
  return path.substring(prefix.length).replaceAll(Platform.pathSeparator, '/');
}

bool _sameStringSet(Set<String> left, Set<String> right) =>
    left.length == right.length && left.containsAll(right);

bool _sameBytes(List<int> left, List<int> right) {
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

final class _LocalizationInputs {
  const _LocalizationInputs({
    required this.configuration,
    required this.resources,
  });

  final String configuration;
  final Map<String, String> resources;
}

final class _GeneratorOptions {
  const _GeneratorOptions({required this.projectRoot, required this.checkOnly});

  final Directory projectRoot;
  final bool checkOnly;
}

final class _MessageExampleRemoval {
  const _MessageExampleRemoval({required this.source, required this.count});

  final String source;
  final int count;
}

final class _GeneratorProcessException implements Exception {
  const _GeneratorProcessException({
    required this.exitCode,
    required this.output,
  });

  final int exitCode;
  final String output;
}
