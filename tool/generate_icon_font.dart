import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:icon_font_generator/icon_font_generator.dart';
import 'package:xml/xml.dart';
import 'package:yaml/yaml.dart';

const String _manifestPath = 'assets/icons/icon_font_manifest.json';
const String _licensePath = 'assets/icons/LICENSE.md';
const String _svgDirectoryPath = 'assets/icons/svg';
const String _fontAssetPath = 'assets/fonts/template_icons.otf';
const String _dartOutputPath =
    'lib/shared/assets/generated/template_icons.g.dart';
const String _fontFamily = 'TemplateIcons';
const int _firstCodepoint = 0xE000;
const int _lastCodepoint = 0xF8FF;
const int _sfntChecksumMagic = 0xB1B0AFBA;
const int _fixedLongDateTimeSeconds = 3029529600;
const String _fixedCopyright = 'Copyright icon_font_generator 2000';
const Set<String> _topLevelManifestKeys = <String>{
  'schemaVersion',
  'fontFamily',
  'fontAsset',
  'dartOutput',
  'licenseFile',
  'nextCodepoint',
  'licenses',
  'glyphs',
};
const Set<String> _commonGlyphKeys = <String>{
  'name',
  'codepoint',
  'status',
  'description',
  'licenseId',
  'matchTextDirection',
};
const Set<String> _dartReservedWords = <String>{
  'abstract',
  'as',
  'assert',
  'async',
  'await',
  'base',
  'break',
  'case',
  'catch',
  'class',
  'const',
  'continue',
  'covariant',
  'default',
  'deferred',
  'do',
  'dynamic',
  'else',
  'enum',
  'export',
  'extends',
  'extension',
  'external',
  'factory',
  'false',
  'final',
  'finally',
  'for',
  'function',
  'get',
  'hide',
  'if',
  'implements',
  'import',
  'in',
  'interface',
  'is',
  'late',
  'library',
  'mixin',
  'new',
  'null',
  'of',
  'on',
  'operator',
  'part',
  'required',
  'rethrow',
  'return',
  'sealed',
  'set',
  'show',
  'static',
  'super',
  'switch',
  'sync',
  'this',
  'throw',
  'true',
  'try',
  'typedef',
  'var',
  'void',
  'when',
  'while',
  'with',
  'yield',
};
final RegExp _glyphNamePattern = RegExp(r'^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$');
final RegExp _licenseIdPattern = RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$');
final RegExp _spdxPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9.+-]*$');
final RegExp _hanCharacterPattern = RegExp(r'[\u3400-\u9fff]');

/// SVG 字体生成器在内存中接收的完整人工维护输入。
///
/// [svgSources] 的键只能是 `assets/icons/svg/` 下的文件名，不包含目录前缀；值是 UTF-8
/// SVG 文本。该对象不推断路径、不读取网络，也不把清单当作第二份图形源。调用
/// [validateIconFontInputs] 或 [buildIconFontOutputs] 时才会执行严格结构校验。
final class IconFontInputs {
  /// 创建一组可验证的 SVG 字体输入。
  const IconFontInputs({
    required this.manifestSource,
    required this.licenseSource,
    required this.svgSources,
    required this.pubspecSource,
  });

  /// 稳定身份清单的 JSON 文本。
  final String manifestSource;

  /// 字形来源与再分发许可证的 Markdown 文本。
  final String licenseSource;

  /// 原始 SVG 文件名到文本的映射。
  final Map<String, String> svgSources;

  /// 用于核对工具依赖与字体注册的 `pubspec.yaml` 文本。
  final String pubspecSource;
}

/// 一次确定性生成得到的两个受控产物。
///
/// [fontBytes] 是经过时间元数据归一化和完整校验和修复的 OTF；[dartSource] 只包含活动
/// glyph 的类型安全 `IconData` 映射。调用方不得分别写入两者，应使用
/// [replaceIconFontOutputs] 保持失败回滚边界。
final class IconFontOutputs {
  /// 创建已经在内存中验证的生成结果。
  IconFontOutputs({required Uint8List fontBytes, required this.dartSource})
    : fontBytes = Uint8List.fromList(fontBytes);

  /// 最终 OTF 文件的字节。
  final Uint8List fontBytes;

  /// 最终生成 Dart 文件的 UTF-8 文本。
  final String dartSource;
}

/// 从生成字体结构中读取的可验证元数据。
///
/// 该对象用于测试和写入前复核，不承担字体渲染。所有 codepoint 都来自字体 `cmap`
/// format 12 子表；映射包含退休占位槽，因此调用方应结合清单判断哪些图标公开给业务代码。
final class IconFontInspection {
  /// 创建一个只读字体检查结果。
  IconFontInspection({
    required this.familyName,
    required this.created,
    required this.modified,
    required this.copyright,
    required this.glyphCount,
    required Map<int, int> codepointToGlyph,
  }) : codepointToGlyph = Map<int, int>.unmodifiable(codepointToGlyph);

  /// OTF `name` 表中的字体 family。
  final String familyName;

  /// `head` 表中已归一化的创建时间。
  final DateTime created;

  /// `head` 表中已归一化的修改时间。
  final DateTime modified;

  /// `name` 表中已归一化的版权字段。
  final String copyright;

  /// 包含 `.notdef`、空格、活动字形和退休占位的总 glyph 数。
  final int glyphCount;

  /// Unicode codepoint 到字体 glyph ID 的稳定映射。
  final Map<int, int> codepointToGlyph;
}

/// 生成、检查或事务写入失败时使用的稳定错误。
///
/// [violations] 只包含规则编号、受控相对路径和安全中文说明，不复制 SVG、许可证或未来可能
/// 包含敏感信息的原始文本。CLI 会逐项输出并返回非零退出码。
final class IconFontGenerationException implements Exception {
  /// 创建一个至少包含一条违规信息的生成错误。
  IconFontGenerationException(Iterable<String> violations)
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

/// 校验 SVG 字体的清单、许可证、原始 SVG、工具依赖和 Flutter 字体注册。
///
/// 函数不访问文件系统且不生成字体。它会尽可能收集全部违规，再按稳定顺序返回。空列表表示
/// 输入可以交给 [buildIconFontOutputs]；非空时调用方不得写入任何生成目标。
List<String> validateIconFontInputs(IconFontInputs inputs) {
  return _validateAndParseInputs(inputs).violations;
}

/// 基于唯一 SVG 图形源生成确定性的 OTF 与中文 Dart 映射。
///
/// 生成前会重新执行 [validateIconFontInputs] 的全部规则。清单按 codepoint 排序后传给固定的
/// `icon_font_generator 4.0.0` API；退休槽使用零面积占位轮廓保留后续位置，但不会输出公共
/// `IconData`。字体的当前时间与年份随后以 OTF 表结构归一化，并重算每张表及全字体校验和。
/// 任一阶段失败都会抛出 [IconFontGenerationException]，不会访问生成目标。
IconFontOutputs buildIconFontOutputs(IconFontInputs inputs) {
  final _InputValidation validation = _validateAndParseInputs(inputs);
  if (validation.violations.isNotEmpty || validation.manifest == null) {
    throw IconFontGenerationException(validation.violations);
  }
  final _IconFontManifest manifest = validation.manifest!;

  try {
    final List<GenericGlyph> glyphs = <GenericGlyph>[
      for (final _GlyphManifestEntry entry in manifest.glyphs)
        entry.glyph ?? _retiredPlaceholder(entry.name),
    ];
    final OpenTypeFont font = OpenTypeFont.createFromGlyphs(
      glyphList: glyphs,
      fontName: _fontFamily,
      description: 'Deterministic semantic icons for Flutter Template',
      achVendID: 'FTPL',
      useOpenType: true,
      usePostV2: true,
      normalize: true,
    );
    final ByteData encoded = OTFWriter().write(font);
    final Uint8List rawBytes = Uint8List.fromList(
      encoded.buffer.asUint8List(encoded.offsetInBytes, encoded.lengthInBytes),
    );
    final Uint8List normalized = _normalizeFontMetadata(rawBytes);
    final IconFontInspection inspection = inspectIconFont(normalized);
    _validateGeneratedFont(inspection, manifest);

    return IconFontOutputs(
      fontBytes: normalized,
      dartSource: _emitDartSource(manifest),
    );
  } on IconFontGenerationException {
    rethrow;
  } on Object {
    throw IconFontGenerationException(const <String>[
      '[ICON_FONT_BUILD_FAILED] 固定字体工具无法根据已验证输入生成 OTF。',
    ]);
  }
}

/// 解析并验证一个生成 OTF 的 family、时间、版权、校验和和 `cmap`。
///
/// 字体损坏、表越界、缺少必需表、非 format 0 `name`、缺少 format 12 `cmap` 或任一校验和
/// 不一致时抛出 [FormatException]。本函数不修改传入字节，也不信任文件扩展名。
IconFontInspection inspectIconFont(Uint8List fontBytes) {
  final Uint8List bytes = Uint8List.fromList(fontBytes);
  final Map<String, _SfntTable> tables = _parseSfntTables(bytes);
  final _SfntTable? head = tables['head'];
  final _SfntTable? name = tables['name'];
  final _SfntTable? cmap = tables['cmap'];
  if (head == null || name == null || cmap == null) {
    throw const FormatException('字体缺少 head、name 或 cmap 必需表。');
  }
  if (head.length < 54) {
    throw const FormatException('head 表长度无效。');
  }

  final Uint8List checksumCopy = Uint8List.fromList(bytes);
  final ByteData checksumData = ByteData.sublistView(checksumCopy);
  checksumData.setUint32(head.offset + 8, 0);
  for (final _SfntTable table in tables.values) {
    final int actual = _calculateChecksum(
      checksumCopy,
      table.offset,
      table.length,
    );
    if (actual != table.checksum) {
      throw FormatException('${table.tag} 表校验和无效。');
    }
  }
  if (_calculateChecksum(bytes, 0, bytes.length) != _sfntChecksumMagic) {
    throw const FormatException('全字体校验和无效。');
  }

  final OpenTypeFont parsed = OpenTypeFont.fromByteData(
    ByteData.sublistView(bytes),
  );
  final Map<int, List<String>> names = _readNameStrings(bytes, name);
  final List<String> copyrightValues = names[0] ?? const <String>[];
  if (copyrightValues.isEmpty || copyrightValues.toSet().length != 1) {
    throw const FormatException('name 表版权记录不完整或不一致。');
  }

  return IconFontInspection(
    familyName: parsed.familyName,
    created: parsed.head.created,
    modified: parsed.head.modified,
    copyright: copyrightValues.first,
    glyphCount: parsed.maxp.numGlyphs,
    codepointToGlyph: _readFormat12Cmap(bytes, cmap),
  );
}

/// 只读比较项目中的 OTF 与 Dart 文件是否和期望生成结果逐字节一致。
///
/// 返回值为空表示产物最新；缺失、无法读取和内容过期使用不同稳定规则编号。函数不会创建
/// 目录、更新 mtime 或修复文件，适合 CI 的 `--check` 路径。
List<String> compareIconFontOutputs({
  required Directory projectRoot,
  required IconFontOutputs expected,
}) {
  final List<String> violations = <String>[];
  final List<({String path, List<int> expectedBytes})> targets =
      <({String path, List<int> expectedBytes})>[
        (path: _fontAssetPath, expectedBytes: expected.fontBytes),
        (
          path: _dartOutputPath,
          expectedBytes: utf8.encode(expected.dartSource),
        ),
      ];

  for (final ({List<int> expectedBytes, String path}) target in targets) {
    final File file = File(_joinPath(projectRoot.path, target.path));
    final FileSystemEntityType type = FileSystemEntity.typeSync(
      file.path,
      followLinks: false,
    );
    if (type == FileSystemEntityType.notFound) {
      violations.add('[ICON_FONT_OUTPUT_MISSING] ${target.path} 尚未生成。');
      continue;
    }
    if (type != FileSystemEntityType.file) {
      violations.add('[ICON_FONT_OUTPUT_UNSAFE] ${target.path} 必须是普通文件。');
      continue;
    }
    try {
      if (!_bytesEqual(file.readAsBytesSync(), target.expectedBytes)) {
        violations.add('[ICON_FONT_OUTPUT_STALE] ${target.path} 已过期。');
      }
    } on FileSystemException {
      violations.add('[ICON_FONT_OUTPUT_UNREADABLE] ${target.path} 无法读取。');
    }
  }
  violations.sort();
  return violations;
}

/// 对一个项目根执行完整且只读的 SVG 字体过期检查。
///
/// 函数读取固定输入、在内存构建期望结果，并仅在系统临时目录回读验证；项目目录只读取两个
/// 生成目标。输入无效或字体构建失败会抛出 [IconFontGenerationException]，产物缺失或过期
/// 则作为稳定违规列表返回。无论成功失败，都不会创建项目内 `.dart_tool` 或修改 mtime。
List<String> checkIconFontProject(Directory projectRoot) {
  final IconFontInputs inputs = readIconFontInputs(projectRoot);
  final IconFontOutputs outputs = buildIconFontOutputs(inputs);
  _verifyTemporaryRoundTrip(outputs);
  return compareIconFontOutputs(projectRoot: projectRoot, expected: outputs);
}

/// 以可回滚事务替换项目中的字体和 Dart 生成文件。
///
/// 两个新文件先写入项目 `.dart_tool` 下的同文件系统暂存目录并重新读取验证；旧文件随后移动
/// 到备份区，新文件才按固定顺序安装。任一安装失败会删除本轮已安装文件并恢复所有旧文件。
/// [beforeInstall] 仅用于测试注入确定的文件系统故障，生产 CLI 必须省略；回调接收即将安装的
/// 项目相对路径。函数只触碰两个固定输出与自己的临时目录，不会改写 SVG、清单或许可证。
void replaceIconFontOutputs({
  required Directory projectRoot,
  required IconFontOutputs outputs,
  void Function(String relativePath)? beforeInstall,
}) {
  final IconFontInspection inspection = inspectIconFont(outputs.fontBytes);
  _validateOutputBundle(outputs, inspection);

  final Directory toolDirectory = Directory(
    _joinPath(projectRoot.path, '.dart_tool'),
  );
  _rejectSymlinkComponents(projectRoot, '.dart_tool/staging');
  toolDirectory.createSync(recursive: true);
  final Directory staging = Directory(
    _joinPath(
      toolDirectory.path,
      'icon_font_${pid}_${DateTime.now().microsecondsSinceEpoch}',
    ),
  )..createSync();

  bool preserveStagingForRecovery = false;
  try {
    final File stagedFont = File(_joinPath(staging.path, 'template_icons.otf'));
    final File stagedDart = File(
      _joinPath(staging.path, 'template_icons.g.dart'),
    );
    stagedFont.writeAsBytesSync(outputs.fontBytes, flush: true);
    stagedDart.writeAsStringSync(
      outputs.dartSource,
      encoding: utf8,
      flush: true,
    );
    if (!_bytesEqual(stagedFont.readAsBytesSync(), outputs.fontBytes) ||
        stagedDart.readAsStringSync(encoding: utf8) != outputs.dartSource) {
      throw const FileSystemException('暂存产物回读不一致。');
    }
    inspectIconFont(stagedFont.readAsBytesSync());

    final List<_StagedTarget> targets = <_StagedTarget>[
      _StagedTarget(
        relativePath: _fontAssetPath,
        stagedFile: stagedFont,
        targetFile: File(_joinPath(projectRoot.path, _fontAssetPath)),
      ),
      _StagedTarget(
        relativePath: _dartOutputPath,
        stagedFile: stagedDart,
        targetFile: File(_joinPath(projectRoot.path, _dartOutputPath)),
      ),
    ];
    _commitStagedTargets(
      projectRoot: projectRoot,
      staging: staging,
      targets: targets,
      beforeInstall: beforeInstall,
    );
  } on IconFontGenerationException catch (error) {
    preserveStagingForRecovery = error.violations.any(
      (String violation) => violation.startsWith('[ICON_FONT_ROLLBACK_FAILED]'),
    );
    rethrow;
  } on Object {
    throw IconFontGenerationException(const <String>[
      '[ICON_FONT_WRITE_FAILED] 生成产物写入失败，旧版本已按事务边界恢复。',
    ]);
  } finally {
    if (!preserveStagingForRecovery && staging.existsSync()) {
      staging.deleteSync(recursive: true);
    }
  }
}

/// 从一个项目根目录读取固定位置的 SVG 字体输入。
///
/// 文件缺失会保留为空输入并由 [validateIconFontInputs] 给出稳定规则；符号链接、子目录、
/// 非 SVG 条目或无效 UTF-8 会立即抛出 [IconFontGenerationException]，避免工具越过明确的
/// 人工维护目录。函数不会跟随链接，也不会写入文件。
IconFontInputs readIconFontInputs(Directory projectRoot) {
  final String manifest = _readOptionalUtf8(projectRoot, _manifestPath);
  final String license = _readOptionalUtf8(projectRoot, _licensePath);
  final String pubspec = _readOptionalUtf8(projectRoot, 'pubspec.yaml');
  final Directory svgDirectory = Directory(
    _joinPath(projectRoot.path, _svgDirectoryPath),
  );
  final Map<String, String> svgSources = <String, String>{};
  final FileSystemEntityType directoryType = FileSystemEntity.typeSync(
    svgDirectory.path,
    followLinks: false,
  );
  if (directoryType == FileSystemEntityType.link) {
    throw IconFontGenerationException(const <String>[
      '[ICON_FONT_SOURCE_SYMLINK] assets/icons/svg 不得是符号链接。',
    ]);
  }
  if (directoryType == FileSystemEntityType.directory) {
    final List<FileSystemEntity> entities = svgDirectory.listSync(
      followLinks: false,
    )..sort((FileSystemEntity left, FileSystemEntity right) {
      return left.path.compareTo(right.path);
    });
    for (final FileSystemEntity entity in entities) {
      final FileSystemEntityType type = FileSystemEntity.typeSync(
        entity.path,
        followLinks: false,
      );
      final String name = _basename(entity.path);
      if (type != FileSystemEntityType.file || !name.endsWith('.svg')) {
        throw IconFontGenerationException(const <String>[
          '[ICON_FONT_SOURCE_ENTRY] SVG 输入目录只能包含普通 .svg 文件。',
        ]);
      }
      try {
        svgSources[name] = File(entity.path).readAsStringSync(encoding: utf8);
      } on Object {
        throw IconFontGenerationException(<String>[
          '[ICON_FONT_SOURCE_UNREADABLE] $_svgDirectoryPath/$name 无法按 UTF-8 读取。',
        ]);
      }
    }
  }

  return IconFontInputs(
    manifestSource: manifest,
    licenseSource: license,
    svgSources: Map<String, String>.unmodifiable(svgSources),
    pubspecSource: pubspec,
  );
}

/// 执行 SVG 字体生成或只读过期检查。
///
/// 支持 `--check` 与 `--root <path>`；无 `--check` 时才调用事务写入。参数错误返回 64，输入、
/// 生成或漂移错误返回 1，成功返回 0。该函数设置进程 [exitCode]，不启动 Flutter 或平台构建。
void main(List<String> arguments) {
  late final _GeneratorArguments parsed;
  try {
    parsed = _parseArguments(arguments);
  } on FormatException catch (error) {
    stderr.writeln('SVG 字体生成参数错误：${error.message}');
    stderr.writeln(
      '用法：dart run tool/generate_icon_font.dart [--check] [--root <path>]',
    );
    exitCode = 64;
    return;
  }

  try {
    if (parsed.checkOnly) {
      final List<String> violations = checkIconFontProject(parsed.projectRoot);
      if (violations.isNotEmpty) {
        throw IconFontGenerationException(violations);
      }
      stdout.writeln('SVG 字体生成产物检查通过。');
      return;
    }

    final IconFontInputs inputs = readIconFontInputs(parsed.projectRoot);
    final IconFontOutputs outputs = buildIconFontOutputs(inputs);
    replaceIconFontOutputs(projectRoot: parsed.projectRoot, outputs: outputs);
    stdout.writeln('SVG 字体生成完成：$_fontAssetPath、$_dartOutputPath。');
  } on IconFontGenerationException catch (error) {
    stderr.writeln('SVG 字体生成失败，共 ${error.violations.length} 项：');
    for (final String violation in error.violations) {
      stderr.writeln('- $violation');
    }
    exitCode = 1;
  } on Object {
    stderr.writeln('SVG 字体生成失败：出现未分类错误，项目输出未被确认更新。');
    exitCode = 1;
  }
}

final class _InputValidation {
  const _InputValidation({required this.violations, this.manifest});

  final List<String> violations;
  final _IconFontManifest? manifest;
}

final class _IconFontManifest {
  const _IconFontManifest({required this.glyphs});

  final List<_GlyphManifestEntry> glyphs;
}

final class _GlyphManifestEntry {
  const _GlyphManifestEntry({
    required this.name,
    required this.codepoint,
    required this.status,
    required this.description,
    required this.licenseId,
    required this.matchTextDirection,
    this.svgFileName,
    this.glyph,
  });

  final String name;
  final int codepoint;
  final String status;
  final String description;
  final String licenseId;
  final bool matchTextDirection;
  final String? svgFileName;
  final GenericGlyph? glyph;

  bool get isActive => status == 'active';

  _GlyphManifestEntry withGlyph(GenericGlyph parsedGlyph) {
    return _GlyphManifestEntry(
      name: name,
      codepoint: codepoint,
      status: status,
      description: description,
      licenseId: licenseId,
      matchTextDirection: matchTextDirection,
      svgFileName: svgFileName,
      glyph: parsedGlyph,
    );
  }
}

final class _LicenseManifestEntry {
  const _LicenseManifestEntry({
    required this.id,
    required this.spdx,
    required this.source,
  });

  final String id;
  final String spdx;
  final String source;
}

_InputValidation _validateAndParseInputs(IconFontInputs inputs) {
  final List<String> violations = <String>[];
  _validatePubspec(inputs.pubspecSource, violations);

  if (inputs.manifestSource.trim().isEmpty) {
    violations.add('[ICON_FONT_MANIFEST_MISSING] $_manifestPath 缺失或为空。');
    violations.sort();
    return _InputValidation(violations: List<String>.unmodifiable(violations));
  }

  final Map<String, Object?>? manifestMap = _decodeManifest(
    inputs.manifestSource,
    violations,
  );
  if (manifestMap == null) {
    violations.sort();
    return _InputValidation(violations: List<String>.unmodifiable(violations));
  }
  if (!_sameKeys(manifestMap.keys, _topLevelManifestKeys)) {
    violations.add('[ICON_FONT_MANIFEST_KEYS] 清单顶层字段必须与 schema v1 固定契约一致。');
  }
  if (manifestMap['schemaVersion'] != 1) {
    violations.add('[ICON_FONT_SCHEMA_VERSION] 清单 schemaVersion 必须为 1。');
  }
  if (manifestMap['fontFamily'] != _fontFamily ||
      manifestMap['fontAsset'] != _fontAssetPath ||
      manifestMap['dartOutput'] != _dartOutputPath ||
      manifestMap['licenseFile'] != _licensePath) {
    violations.add('[ICON_FONT_OUTPUT_CONTRACT] 字体 family 或固定输出路径发生漂移。');
  }
  final Object? rawNextCodepoint = manifestMap['nextCodepoint'];
  final int? nextCodepoint =
      rawNextCodepoint is String ? _parseCodepoint(rawNextCodepoint) : null;
  if (nextCodepoint == null ||
      nextCodepoint < _firstCodepoint + 1 ||
      nextCodepoint > _lastCodepoint + 1) {
    violations.add(
      '[ICON_FONT_NEXT_CODEPOINT] nextCodepoint 必须是历史槽位之后的有效 PUA 边界。',
    );
  }

  final Map<String, _LicenseManifestEntry> licenses = _parseLicenses(
    manifestMap['licenses'],
    violations,
  );
  List<_GlyphManifestEntry> glyphs = _parseGlyphEntries(
    manifestMap['glyphs'],
    violations,
  );

  final Set<String> names = <String>{};
  final Set<int> codepoints = <int>{};
  final Set<String> identifiers = <String>{'fontFamily'};
  for (final _GlyphManifestEntry glyph in glyphs) {
    if (!names.add(glyph.name)) {
      violations.add('[ICON_FONT_GLYPH_NAME_DUPLICATE] 清单包含重复 glyph 名称。');
    }
    if (!codepoints.add(glyph.codepoint)) {
      violations.add('[ICON_FONT_CODEPOINT_DUPLICATE] 清单包含重复 codepoint。');
    }
    final String identifier = _toLowerCamelCase(glyph.name);
    if (!identifiers.add(identifier) ||
        _dartReservedWords.contains(identifier)) {
      violations.add('[ICON_FONT_DART_IDENTIFIER] glyph 名称会产生冲突或保留的 Dart 标识符。');
    }
    if (!licenses.containsKey(glyph.licenseId)) {
      violations.add('[ICON_FONT_LICENSE_REFERENCE] glyph 引用了未登记的许可证。');
    }
  }

  glyphs = List<_GlyphManifestEntry>.of(glyphs)
    ..sort((_GlyphManifestEntry left, _GlyphManifestEntry right) {
      return left.codepoint.compareTo(right.codepoint);
    });
  if (glyphs.isNotEmpty) {
    for (int index = 0; index < glyphs.length; index += 1) {
      if (glyphs[index].codepoint != _firstCodepoint + index) {
        violations.add(
          '[ICON_FONT_CODEPOINT_SEQUENCE] codepoint 必须从 0xE000 连续保留；删除项应改为 retired。',
        );
        break;
      }
    }
  }
  if (nextCodepoint != null &&
      nextCodepoint != _firstCodepoint + glyphs.length) {
    violations.add(
      '[ICON_FONT_NEXT_CODEPOINT] 删除 glyph 时必须保留 retired 槽，nextCodepoint 不得后退。',
    );
  }

  final Set<String> expectedSvgFiles =
      glyphs
          .where((_GlyphManifestEntry glyph) => glyph.isActive)
          .map((_GlyphManifestEntry glyph) => glyph.svgFileName!)
          .toSet();
  if (!_sameKeys(inputs.svgSources.keys, expectedSvgFiles)) {
    violations.add('[ICON_FONT_SVG_MANIFEST] SVG 目录必须与清单中的活动 glyph 精确对应。');
  }

  final Map<String, String> fingerprints = <String, String>{};
  final List<_GlyphManifestEntry> parsedGlyphs = <_GlyphManifestEntry>[];
  for (final _GlyphManifestEntry glyph in glyphs) {
    if (!glyph.isActive) {
      parsedGlyphs.add(glyph);
      continue;
    }
    final String? source = inputs.svgSources[glyph.svgFileName];
    if (source == null) {
      parsedGlyphs.add(glyph);
      continue;
    }
    final _ParsedSvg? parsed = _parseSvg(
      name: glyph.name,
      source: source,
      violations: violations,
    );
    if (parsed == null) {
      parsedGlyphs.add(glyph);
      continue;
    }
    final String? existingName = fingerprints[parsed.fingerprint];
    if (existingName != null) {
      violations.add('[ICON_FONT_SVG_DUPLICATE] 两个活动 glyph 使用相同的轮廓。');
    } else {
      fingerprints[parsed.fingerprint] = glyph.name;
    }
    parsedGlyphs.add(glyph.withGlyph(parsed.glyph));
  }
  glyphs = parsedGlyphs;

  _validateLicenseDocument(inputs.licenseSource, licenses, glyphs, violations);

  violations.sort();
  return _InputValidation(
    violations: List<String>.unmodifiable(violations),
    manifest: _IconFontManifest(
      glyphs: List<_GlyphManifestEntry>.unmodifiable(glyphs),
    ),
  );
}

Map<String, Object?>? _decodeManifest(String source, List<String> violations) {
  try {
    final Object? decoded = jsonDecode(source);
    final Map<String, Object?>? map = _stringObjectMap(decoded);
    if (map == null) {
      violations.add('[ICON_FONT_MANIFEST_OBJECT] 清单顶层必须是 JSON 对象。');
    }
    return map;
  } on FormatException {
    violations.add('[ICON_FONT_MANIFEST_JSON] 清单不是合法 JSON。');
    return null;
  }
}

Map<String, _LicenseManifestEntry> _parseLicenses(
  Object? rawLicenses,
  List<String> violations,
) {
  final Map<String, Object?>? licenseMap = _stringObjectMap(rawLicenses);
  if (licenseMap == null || licenseMap.isEmpty) {
    violations.add('[ICON_FONT_LICENSE_MAP] 清单必须登记至少一个许可证。');
    return <String, _LicenseManifestEntry>{};
  }

  final Map<String, _LicenseManifestEntry> licenses =
      <String, _LicenseManifestEntry>{};
  final List<String> ids = licenseMap.keys.toList()..sort();
  for (final String id in ids) {
    final Map<String, Object?>? value = _stringObjectMap(licenseMap[id]);
    if (!_licenseIdPattern.hasMatch(id) ||
        value == null ||
        !_sameKeys(value.keys, const <String>{'spdx', 'source'})) {
      violations.add('[ICON_FONT_LICENSE_ENTRY] 许可证条目名称或字段无效。');
      continue;
    }
    final Object? rawSpdx = value['spdx'];
    final Object? rawSource = value['source'];
    if (rawSpdx is! String || !_spdxPattern.hasMatch(rawSpdx)) {
      violations.add('[ICON_FONT_LICENSE_SPDX] 许可证 SPDX 标识无效。');
      continue;
    }
    if (rawSource is! String ||
        rawSource.trim() != rawSource ||
        rawSource.isEmpty ||
        rawSource.length > 160 ||
        rawSource.contains(RegExp(r'[\r\n\x00]'))) {
      violations.add('[ICON_FONT_LICENSE_SOURCE] 许可证来源说明必须是安全的单行文本。');
      continue;
    }
    licenses[id] = _LicenseManifestEntry(
      id: id,
      spdx: rawSpdx,
      source: rawSource,
    );
  }
  return licenses;
}

List<_GlyphManifestEntry> _parseGlyphEntries(
  Object? rawGlyphs,
  List<String> violations,
) {
  if (rawGlyphs is! List<Object?> || rawGlyphs.isEmpty) {
    violations.add('[ICON_FONT_GLYPH_LIST] 清单必须包含至少一个 glyph。');
    return <_GlyphManifestEntry>[];
  }

  final List<_GlyphManifestEntry> glyphs = <_GlyphManifestEntry>[];
  for (int index = 0; index < rawGlyphs.length; index += 1) {
    final Map<String, Object?>? map = _stringObjectMap(rawGlyphs[index]);
    if (map == null) {
      violations.add('[ICON_FONT_GLYPH_OBJECT] glyph 条目必须是 JSON 对象。');
      continue;
    }
    final Object? rawStatus = map['status'];
    final String? status = rawStatus is String ? rawStatus : null;
    final Set<String> expectedKeys = <String>{
      ..._commonGlyphKeys,
      if (status == 'active') 'svg',
      if (status == 'retired') 'retiredReason',
    };
    if ((status != 'active' && status != 'retired') ||
        !_sameKeys(map.keys, expectedKeys)) {
      violations.add('[ICON_FONT_GLYPH_KEYS] glyph 状态或字段集合无效。');
      continue;
    }

    final Object? rawName = map['name'];
    final Object? rawCodepoint = map['codepoint'];
    final Object? rawDescription = map['description'];
    final Object? rawLicenseId = map['licenseId'];
    final Object? rawMatchDirection = map['matchTextDirection'];
    final int? codepoint =
        rawCodepoint is String ? _parseCodepoint(rawCodepoint) : null;
    bool valid = true;
    if (rawName is! String || !_glyphNamePattern.hasMatch(rawName)) {
      violations.add('[ICON_FONT_GLYPH_NAME] glyph 名称必须是规范 lower_snake_case。');
      valid = false;
    }
    if (codepoint == null ||
        codepoint < _firstCodepoint ||
        codepoint > _lastCodepoint) {
      violations.add('[ICON_FONT_CODEPOINT] codepoint 必须是 PUA 内的大写 0xXXXX。');
      valid = false;
    }
    if (rawDescription is! String ||
        rawDescription.trim() != rawDescription ||
        rawDescription.isEmpty ||
        rawDescription.length > 100 ||
        rawDescription.contains(RegExp(r'[\r\n\x00]')) ||
        !_hanCharacterPattern.hasMatch(rawDescription)) {
      violations.add('[ICON_FONT_DESCRIPTION] glyph 必须提供安全的单行中文说明。');
      valid = false;
    }
    if (rawLicenseId is! String || !_licenseIdPattern.hasMatch(rawLicenseId)) {
      violations.add('[ICON_FONT_LICENSE_ID] glyph 的 licenseId 无效。');
      valid = false;
    }
    if (rawMatchDirection is! bool) {
      violations.add('[ICON_FONT_DIRECTION_FLAG] matchTextDirection 必须是布尔值。');
      valid = false;
    }

    String? svgFileName;
    if (status == 'active') {
      final Object? rawSvg = map['svg'];
      final String? expectedPath =
          rawName is String ? 'svg/$rawName.svg' : null;
      if (rawSvg is! String || rawSvg != expectedPath) {
        violations.add('[ICON_FONT_SVG_PATH] 活动 glyph 的 SVG 路径必须由名称精确推导。');
        valid = false;
      } else {
        svgFileName = '$rawName.svg';
      }
    } else {
      final Object? retiredReason = map['retiredReason'];
      if (retiredReason is! String ||
          retiredReason.trim() != retiredReason ||
          retiredReason.isEmpty ||
          retiredReason.length > 120 ||
          retiredReason.contains(RegExp(r'[\r\n\x00]')) ||
          !_hanCharacterPattern.hasMatch(retiredReason)) {
        violations.add('[ICON_FONT_RETIRED_REASON] 退休 glyph 必须说明中文原因。');
        valid = false;
      }
    }
    if (!valid) {
      continue;
    }

    glyphs.add(
      _GlyphManifestEntry(
        name: rawName as String,
        codepoint: codepoint!,
        status: status!,
        description: rawDescription as String,
        licenseId: rawLicenseId as String,
        matchTextDirection: rawMatchDirection as bool,
        svgFileName: svgFileName,
      ),
    );
  }
  return glyphs;
}

void _validateLicenseDocument(
  String source,
  Map<String, _LicenseManifestEntry> licenses,
  List<_GlyphManifestEntry> glyphs,
  List<String> violations,
) {
  if (source.trim().isEmpty) {
    violations.add('[ICON_FONT_LICENSE_MISSING] $_licensePath 缺失或为空。');
    return;
  }
  final Set<String> referenced =
      glyphs.map((_GlyphManifestEntry glyph) => glyph.licenseId).toSet();
  if (!_sameKeys(licenses.keys, referenced)) {
    violations.add('[ICON_FONT_LICENSE_UNUSED] 许可证登记必须与 glyph 引用精确对应。');
  }
  for (final _LicenseManifestEntry license in licenses.values) {
    if (!source.contains('## ${license.id}') ||
        !source.contains('- SPDX: ${license.spdx}') ||
        !source.contains('- Source: ${license.source}')) {
      violations.add('[ICON_FONT_LICENSE_MARKER] 许可证文档缺少清单对应的来源标记。');
    }
    if (license.spdx == 'MIT' &&
        (!source.contains('Permission is hereby granted, free of charge') ||
            !source.contains('THE SOFTWARE IS PROVIDED "AS IS"'))) {
      violations.add('[ICON_FONT_LICENSE_TEXT] MIT 字形必须包含完整许可正文。');
    }
  }
}

void _validatePubspec(String source, List<String> violations) {
  if (source.trim().isEmpty) {
    violations.add('[ICON_FONT_PUBSPEC_MISSING] pubspec.yaml 缺失或为空。');
    return;
  }
  try {
    final Object? document = loadYaml(source);
    if (document is! YamlMap) {
      violations.add('[ICON_FONT_PUBSPEC_OBJECT] pubspec.yaml 顶层必须是映射。');
      return;
    }
    final Object? runtimeDependencies = document['dependencies'];
    if (runtimeDependencies is YamlMap &&
        runtimeDependencies.containsKey('icon_font_generator')) {
      violations.add('[ICON_FONT_TOOL_RUNTIME] 字体生成器不得成为运行时依赖。');
    }
    final Object? devDependencies = document['dev_dependencies'];
    if (devDependencies is! YamlMap ||
        devDependencies['icon_font_generator']?.toString() != '4.0.0' ||
        devDependencies['xml']?.toString() != '6.5.0' ||
        devDependencies['yaml']?.toString() != '3.1.3') {
      violations.add('[ICON_FONT_TOOL_VERSION] 字体工具及直接解析依赖必须精确锁定。');
    }

    final Object? flutter = document['flutter'];
    final Object? rawFonts = flutter is YamlMap ? flutter['fonts'] : null;
    if (rawFonts is! YamlList) {
      violations.add('[ICON_FONT_PUBSPEC_FONT] pubspec.yaml 缺少字体注册。');
      return;
    }
    final List<YamlMap> matching =
        rawFonts
            .whereType<YamlMap>()
            .where((YamlMap entry) => entry['family'] == _fontFamily)
            .toList();
    if (matching.length != 1) {
      violations.add('[ICON_FONT_PUBSPEC_FAMILY] TemplateIcons 必须且只能注册一次。');
      return;
    }
    final YamlMap registration = matching.single;
    final Object? registeredFonts = registration['fonts'];
    final bool validRegistration =
        _sameKeys(registration.keys.whereType<String>(), const <String>{
          'family',
          'fonts',
        }) &&
        registeredFonts is YamlList &&
        registeredFonts.length == 1 &&
        registeredFonts.single is YamlMap &&
        _sameKeys(
          (registeredFonts.single as YamlMap).keys.whereType<String>(),
          const <String>{'asset'},
        ) &&
        (registeredFonts.single as YamlMap)['asset'] == _fontAssetPath;
    if (!validRegistration) {
      violations.add('[ICON_FONT_PUBSPEC_ASSET] TemplateIcons 必须只注册固定 OTF 资源。');
    }
  } on YamlException {
    violations.add('[ICON_FONT_PUBSPEC_YAML] pubspec.yaml 不是合法 YAML。');
  } on Object {
    violations.add('[ICON_FONT_PUBSPEC_YAML] pubspec.yaml 结构无法解析。');
  }
}

final class _ParsedSvg {
  const _ParsedSvg({required this.glyph, required this.fingerprint});

  final GenericGlyph glyph;
  final String fingerprint;
}

_ParsedSvg? _parseSvg({
  required String name,
  required String source,
  required List<String> violations,
}) {
  if (source.length > 256 * 1024) {
    violations.add('[ICON_FONT_SVG_SIZE] SVG 输入超过 256 KiB 上限。');
    return null;
  }
  try {
    final XmlDocument document = XmlDocument.parse(source);
    final XmlElement root = document.rootElement;
    bool structureValid = true;
    for (final XmlNode node in document.children) {
      if (node == root || node is XmlDeclaration) {
        continue;
      }
      if (node is XmlText && node.value.trim().isEmpty) {
        continue;
      }
      structureValid = false;
    }
    if (root.name.local != 'svg' ||
        root.name.namespaceUri != 'http://www.w3.org/2000/svg') {
      structureValid = false;
    }
    final Set<String> rootAttributes =
        root.attributes
            .map((XmlAttribute attribute) => attribute.name.qualified)
            .toSet();
    if (!_sameKeys(rootAttributes, const <String>{'xmlns', 'viewBox'})) {
      structureValid = false;
    }
    final List<double>? viewBox =
        root
            .getAttribute('viewBox')
            ?.trim()
            .split(RegExp(r'[\s,]+'))
            .map(double.tryParse)
            .whereType<double>()
            .toList();
    if (viewBox == null ||
        viewBox.length != 4 ||
        viewBox[0] != 0 ||
        viewBox[1] != 0 ||
        viewBox[2] != 24 ||
        viewBox[3] != 24) {
      structureValid = false;
    }
    final List<XmlElement> paths = root.childElements.toList();
    if (paths.isEmpty ||
        paths.any((XmlElement element) => element.name.local != 'path')) {
      structureValid = false;
    }
    for (final XmlNode child in root.children) {
      if (child is XmlElement) {
        if (child.name.local != 'path' ||
            !_sameKeys(
              child.attributes.map(
                (XmlAttribute attribute) => attribute.name.qualified,
              ),
              const <String>{'d'},
            ) ||
            (child.getAttribute('d')?.trim().isEmpty ?? true)) {
          structureValid = false;
        }
      } else if (child is! XmlText || child.value.trim().isNotEmpty) {
        structureValid = false;
      }
    }
    if (!structureValid) {
      violations.add(
        '[ICON_FONT_SVG_STRUCTURE] $name.svg 只能使用 24x24 根节点和直接 path/d 轮廓。',
      );
      return null;
    }

    final Svg svg = Svg.parse(name, source, ignoreShapes: true);
    final GenericGlyph glyph = GenericGlyph.fromSvg(svg);
    final GenericGlyphMetrics metrics = glyph.metrics;
    if (glyph.outlines.isEmpty ||
        metrics.width <= 0 ||
        metrics.height <= 0 ||
        metrics.xMin < 0 ||
        metrics.yMin < 0 ||
        metrics.xMax > 24 ||
        metrics.yMax > 24) {
      violations.add(
        '[ICON_FONT_SVG_BOUNDS] $name.svg 必须包含位于 24x24 画布内的非空二维轮廓。',
      );
      return null;
    }
    return _ParsedSvg(glyph: glyph, fingerprint: _glyphFingerprint(glyph));
  } on Object {
    violations.add('[ICON_FONT_SVG_INVALID] $name.svg 无法解析为受支持的路径。');
    return null;
  }
}

String _glyphFingerprint(GenericGlyph glyph) {
  final StringBuffer buffer = StringBuffer();
  for (final Outline outline in glyph.outlines) {
    buffer
      ..write(outline.fillRule.name)
      ..write('|')
      ..write(outline.hasCompactCurves)
      ..write('|')
      ..write(outline.hasQuadCurves)
      ..write('|');
    for (int index = 0; index < outline.pointList.length; index += 1) {
      final point = outline.pointList[index];
      buffer
        ..write(point.x.toStringAsFixed(8))
        ..write(',')
        ..write(point.y.toStringAsFixed(8))
        ..write(',')
        ..write(outline.isOnCurveList[index] ? '1' : '0')
        ..write(';');
    }
    buffer.write('/');
  }
  return buffer.toString();
}

GenericGlyph _retiredPlaceholder(String name) {
  final Svg svg = Svg.parse(
    '_retired_$name',
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">'
        '<path d="M0 0 L1 0 L0 0 Z"/>'
        '</svg>',
    ignoreShapes: true,
  );
  return GenericGlyph.fromSvg(svg);
}

Uint8List _normalizeFontMetadata(Uint8List rawBytes) {
  final Uint8List bytes = Uint8List.fromList(rawBytes);
  final Map<String, _SfntTable> tables = _parseSfntTables(bytes);
  final _SfntTable? head = tables['head'];
  final _SfntTable? name = tables['name'];
  if (head == null || name == null || head.length < 54) {
    throw const FormatException('生成字体缺少可归一化的 head/name 表。');
  }
  final ByteData data = ByteData.sublistView(bytes);
  data
    ..setUint32(head.offset + 8, 0)
    ..setInt64(head.offset + 20, _fixedLongDateTimeSeconds)
    ..setInt64(head.offset + 28, _fixedLongDateTimeSeconds);
  _normalizeCopyrightRecords(bytes, name);

  for (final _SfntTable table in tables.values) {
    final int checksum = _calculateChecksum(bytes, table.offset, table.length);
    data.setUint32(table.directoryOffset + 4, checksum);
  }
  final int adjustment = (_sfntChecksumMagic -
          _calculateChecksum(bytes, 0, bytes.length))
      .toUnsigned(32);
  data.setUint32(head.offset + 8, adjustment);
  return bytes;
}

void _normalizeCopyrightRecords(Uint8List bytes, _SfntTable name) {
  final ByteData data = ByteData.sublistView(bytes);
  if (name.length < 6 || data.getUint16(name.offset) != 0) {
    throw const FormatException('name 表必须使用 format 0。');
  }
  final int count = data.getUint16(name.offset + 2);
  final int stringOffset = data.getUint16(name.offset + 4);
  int replacements = 0;
  for (int index = 0; index < count; index += 1) {
    final int recordOffset = name.offset + 6 + index * 12;
    if (recordOffset + 12 > name.offset + name.length) {
      throw const FormatException('name 记录越界。');
    }
    final int platform = data.getUint16(recordOffset);
    final int nameId = data.getUint16(recordOffset + 6);
    final int length = data.getUint16(recordOffset + 8);
    final int offset = data.getUint16(recordOffset + 10);
    if (nameId != 0) {
      continue;
    }
    final int absolute = name.offset + stringOffset + offset;
    if (absolute < name.offset ||
        absolute + length > name.offset + name.length) {
      throw const FormatException('name 字符串越界。');
    }
    final String current = _decodeNameString(bytes, platform, absolute, length);
    if (!RegExp(r'^Copyright icon_font_generator \d{4}$').hasMatch(current)) {
      throw const FormatException('字体工具版权字段格式发生未知变化。');
    }
    final List<int> replacement = _encodeNameString(_fixedCopyright, platform);
    if (replacement.length != length) {
      throw const FormatException('归一化版权字段长度发生变化。');
    }
    bytes.setRange(absolute, absolute + length, replacement);
    replacements += 1;
  }
  if (replacements != 2) {
    throw const FormatException('字体工具版权记录数量发生未知变化。');
  }
}

void _validateGeneratedFont(
  IconFontInspection inspection,
  _IconFontManifest manifest,
) {
  final DateTime fixed = DateTime.utc(2000);
  final List<String> violations = <String>[];
  if (inspection.familyName != _fontFamily) {
    violations.add('[ICON_FONT_METADATA_FAMILY] 生成字体 family 不正确。');
  }
  if (inspection.created != fixed || inspection.modified != fixed) {
    violations.add('[ICON_FONT_METADATA_TIME] 生成字体仍包含不稳定时间。');
  }
  if (inspection.copyright != _fixedCopyright) {
    violations.add('[ICON_FONT_METADATA_COPYRIGHT] 生成字体仍包含不稳定年份。');
  }
  if (inspection.glyphCount != manifest.glyphs.length + 2) {
    violations.add('[ICON_FONT_GLYPH_COUNT] 生成字体 glyph 数量不正确。');
  }
  for (int index = 0; index < manifest.glyphs.length; index += 1) {
    final int codepoint = _firstCodepoint + index;
    if (inspection.codepointToGlyph[codepoint] != index + 2) {
      violations.add('[ICON_FONT_CMAP] 生成字体 codepoint 与 glyph ID 不一致。');
      break;
    }
  }
  if (violations.isNotEmpty) {
    throw IconFontGenerationException(violations);
  }
}

void _validateOutputBundle(
  IconFontOutputs outputs,
  IconFontInspection inspection,
) {
  final DateTime fixed = DateTime.utc(2000);
  final List<String> violations = <String>[];
  if (inspection.familyName != _fontFamily ||
      inspection.created != fixed ||
      inspection.modified != fixed ||
      inspection.copyright != _fixedCopyright) {
    violations.add('[ICON_FONT_OUTPUT_METADATA] 待写入字体不符合固定 family 或确定性元数据契约。');
  }
  if (outputs.dartSource.contains('\r') ||
      !outputs.dartSource.endsWith('\n') ||
      !outputs.dartSource.startsWith(
        '// 此文件由 `dart run tool/generate_icon_font.dart` 基于 SVG 清单生成。',
      ) ||
      !outputs.dartSource.contains(
        "static const String fontFamily = '$_fontFamily';",
      )) {
    violations.add('[ICON_FONT_OUTPUT_DART] 待写入 Dart 文件缺少固定中文生成标记或 family。');
  }
  if (violations.isNotEmpty) {
    throw IconFontGenerationException(violations);
  }
}

String _emitDartSource(_IconFontManifest manifest) {
  final StringBuffer output =
      StringBuffer()
        ..writeln(
          '// 此文件由 `dart run tool/generate_icon_font.dart` 基于 SVG 清单生成。',
        )
        ..writeln('// 请勿手工修改；更新 `assets/icons/` 后重新运行生成命令。')
        ..writeln()
        ..writeln("import 'package:flutter/widgets.dart';")
        ..writeln()
        ..writeln('/// 应用内单色语义图标的类型安全入口。')
        ..writeln('///')
        ..writeln('/// 字形来自 `assets/icons/svg/`，稳定 codepoint 由清单维护。此类只暴露活动')
        ..writeln('/// 图标；退休槽仍保留在字体中，避免后续图标映射发生位移。')
        ..writeln('abstract final class TemplateIcons {')
        ..writeln('  /// Flutter 资源注册使用的固定字体 family。')
        ..writeln("  static const String fontFamily = '$_fontFamily';");

  for (final _GlyphManifestEntry glyph in manifest.glyphs) {
    if (!glyph.isActive) {
      continue;
    }
    output
      ..writeln()
      ..writeln('  /// ${glyph.description}');
    final String identifier = _toLowerCamelCase(glyph.name);
    final String codepoint = '0x${glyph.codepoint.toRadixString(16)}';
    final String oneLine =
        '  static const IconData $identifier = IconData($codepoint, '
        'fontFamily: fontFamily'
        '${glyph.matchTextDirection ? ', matchTextDirection: true' : ''});';
    if (oneLine.length <= 80) {
      output.writeln(oneLine);
    } else {
      output
        ..writeln('  static const IconData $identifier = IconData(')
        ..writeln('    $codepoint,')
        ..writeln('    fontFamily: fontFamily,');
      if (glyph.matchTextDirection) {
        output.writeln('    matchTextDirection: true,');
      }
      output.writeln('  );');
    }
  }
  output.writeln('}');
  return output.toString();
}

final class _SfntTable {
  const _SfntTable({
    required this.tag,
    required this.checksum,
    required this.offset,
    required this.length,
    required this.directoryOffset,
  });

  final String tag;
  final int checksum;
  final int offset;
  final int length;
  final int directoryOffset;
}

Map<String, _SfntTable> _parseSfntTables(Uint8List bytes) {
  if (bytes.length < 12) {
    throw const FormatException('字体文件过短。');
  }
  final ByteData data = ByteData.sublistView(bytes);
  if (data.getUint32(0) != 0x4F54544F) {
    throw const FormatException('字体必须是 OpenType/CFF。');
  }
  final int count = data.getUint16(4);
  if (count == 0 || 12 + count * 16 > bytes.length) {
    throw const FormatException('字体表目录无效。');
  }
  final Map<String, _SfntTable> tables = <String, _SfntTable>{};
  for (int index = 0; index < count; index += 1) {
    final int directoryOffset = 12 + index * 16;
    final String tag = String.fromCharCodes(
      bytes.sublist(directoryOffset, directoryOffset + 4),
    );
    final int checksum = data.getUint32(directoryOffset + 4);
    final int offset = data.getUint32(directoryOffset + 8);
    final int length = data.getUint32(directoryOffset + 12);
    if (tag.length != 4 ||
        tables.containsKey(tag) ||
        offset < 12 + count * 16 ||
        length <= 0 ||
        offset > bytes.length ||
        length > bytes.length - offset) {
      throw const FormatException('字体表目录包含重复或越界记录。');
    }
    tables[tag] = _SfntTable(
      tag: tag,
      checksum: checksum,
      offset: offset,
      length: length,
      directoryOffset: directoryOffset,
    );
  }
  return tables;
}

Map<int, List<String>> _readNameStrings(Uint8List bytes, _SfntTable name) {
  final ByteData data = ByteData.sublistView(bytes);
  if (data.getUint16(name.offset) != 0) {
    throw const FormatException('name 表不是 format 0。');
  }
  final int count = data.getUint16(name.offset + 2);
  final int storageOffset = data.getUint16(name.offset + 4);
  final Map<int, List<String>> output = <int, List<String>>{};
  for (int index = 0; index < count; index += 1) {
    final int record = name.offset + 6 + index * 12;
    if (record + 12 > name.offset + name.length) {
      throw const FormatException('name 表记录越界。');
    }
    final int platform = data.getUint16(record);
    final int nameId = data.getUint16(record + 6);
    final int length = data.getUint16(record + 8);
    final int relativeOffset = data.getUint16(record + 10);
    final int absolute = name.offset + storageOffset + relativeOffset;
    if (absolute + length > name.offset + name.length) {
      throw const FormatException('name 表字符串越界。');
    }
    output
        .putIfAbsent(nameId, () => <String>[])
        .add(_decodeNameString(bytes, platform, absolute, length));
  }
  return output;
}

Map<int, int> _readFormat12Cmap(Uint8List bytes, _SfntTable cmap) {
  final ByteData data = ByteData.sublistView(bytes);
  if (cmap.length < 4) {
    throw const FormatException('cmap 表过短。');
  }
  final int count = data.getUint16(cmap.offset + 2);
  int? subtableOffset;
  for (int index = 0; index < count; index += 1) {
    final int record = cmap.offset + 4 + index * 8;
    if (record + 8 > cmap.offset + cmap.length) {
      throw const FormatException('cmap 编码记录越界。');
    }
    final int platform = data.getUint16(record);
    final int encoding = data.getUint16(record + 2);
    final int relative = data.getUint32(record + 4);
    final int candidate = cmap.offset + relative;
    if ((platform == 3 && encoding == 10) || (platform == 0 && encoding == 4)) {
      if (candidate + 16 <= cmap.offset + cmap.length &&
          data.getUint16(candidate) == 12) {
        subtableOffset = candidate;
        break;
      }
    }
  }
  if (subtableOffset == null) {
    throw const FormatException('cmap 缺少受支持的 format 12 子表。');
  }
  final int length = data.getUint32(subtableOffset + 4);
  final int groups = data.getUint32(subtableOffset + 12);
  if (length < 16 ||
      subtableOffset + length > cmap.offset + cmap.length ||
      16 + groups * 12 > length) {
    throw const FormatException('cmap format 12 长度无效。');
  }
  final Map<int, int> mapping = <int, int>{};
  for (int index = 0; index < groups; index += 1) {
    final int group = subtableOffset + 16 + index * 12;
    final int start = data.getUint32(group);
    final int end = data.getUint32(group + 4);
    final int firstGlyph = data.getUint32(group + 8);
    if (end < start || end - start > _lastCodepoint) {
      throw const FormatException('cmap format 12 分组无效。');
    }
    for (int codepoint = start; codepoint <= end; codepoint += 1) {
      mapping[codepoint] = firstGlyph + codepoint - start;
    }
  }
  return mapping;
}

String _decodeNameString(
  Uint8List bytes,
  int platform,
  int offset,
  int length,
) {
  if (platform == 1) {
    return String.fromCharCodes(bytes.sublist(offset, offset + length));
  }
  if (platform == 3 && length.isEven) {
    final ByteData data = ByteData.sublistView(bytes);
    return String.fromCharCodes(<int>[
      for (int index = 0; index < length; index += 2)
        data.getUint16(offset + index),
    ]);
  }
  throw const FormatException('name 表使用了不支持的字符串编码。');
}

List<int> _encodeNameString(String value, int platform) {
  if (platform == 1) {
    if (value.codeUnits.any((int unit) => unit > 0xFF)) {
      throw const FormatException('Macintosh name 字符串不是单字节。');
    }
    return value.codeUnits;
  }
  if (platform == 3) {
    return <int>[
      for (final int unit in value.codeUnits) ...<int>[unit >> 8, unit & 0xFF],
    ];
  }
  throw const FormatException('name 表使用了不支持的字符串编码。');
}

int _calculateChecksum(Uint8List bytes, int offset, int length) {
  int sum = 0;
  for (int position = 0; position < length; position += 4) {
    int value = 0;
    for (int byteIndex = 0; byteIndex < 4; byteIndex += 1) {
      value <<= 8;
      final int sourceIndex = offset + position + byteIndex;
      if (position + byteIndex < length) {
        value |= bytes[sourceIndex];
      }
    }
    sum = (sum + value).toUnsigned(32);
  }
  return sum;
}

final class _StagedTarget {
  const _StagedTarget({
    required this.relativePath,
    required this.stagedFile,
    required this.targetFile,
  });

  final String relativePath;
  final File stagedFile;
  final File targetFile;
}

void _commitStagedTargets({
  required Directory projectRoot,
  required Directory staging,
  required List<_StagedTarget> targets,
  required void Function(String relativePath)? beforeInstall,
}) {
  final Directory backupDirectory = Directory(
    _joinPath(staging.path, 'backups'),
  )..createSync();
  final Map<_StagedTarget, File> backups = <_StagedTarget, File>{};
  final List<_StagedTarget> installed = <_StagedTarget>[];

  try {
    for (int index = 0; index < targets.length; index += 1) {
      final _StagedTarget target = targets[index];
      _prepareTargetPath(projectRoot, target);
      if (target.targetFile.existsSync()) {
        final File backup = File(_joinPath(backupDirectory.path, '$index'));
        target.targetFile.renameSync(backup.path);
        backups[target] = backup;
      }
    }
    for (final _StagedTarget target in targets) {
      beforeInstall?.call(target.relativePath);
      target.stagedFile.renameSync(target.targetFile.path);
      installed.add(target);
    }
  } on Object {
    bool rollbackFailed = false;
    for (final _StagedTarget target in installed.reversed) {
      try {
        if (target.targetFile.existsSync()) {
          target.targetFile.deleteSync();
        }
      } on Object {
        rollbackFailed = true;
      }
    }
    for (final MapEntry<_StagedTarget, File> backup
        in backups.entries.toList().reversed) {
      try {
        if (!backup.value.existsSync()) {
          rollbackFailed = true;
          continue;
        }
        backup.value.renameSync(backup.key.targetFile.path);
      } on Object {
        rollbackFailed = true;
      }
    }
    if (rollbackFailed) {
      throw IconFontGenerationException(const <String>[
        '[ICON_FONT_ROLLBACK_FAILED] 写入失败且旧产物无法完整恢复；备份保留在 .dart_tool/icon_font_*，必须人工检查两个固定目标。',
      ]);
    }
    rethrow;
  }
}

void _prepareTargetPath(Directory projectRoot, _StagedTarget target) {
  final FileSystemEntityType targetType = FileSystemEntity.typeSync(
    target.targetFile.path,
    followLinks: false,
  );
  if (targetType != FileSystemEntityType.notFound &&
      targetType != FileSystemEntityType.file) {
    throw const FileSystemException('输出目标不是普通文件。');
  }
  final Directory parent = target.targetFile.parent;
  _rejectSymlinkComponents(projectRoot, target.relativePath);
  parent.createSync(recursive: true);
  if (FileSystemEntity.typeSync(parent.path, followLinks: false) !=
      FileSystemEntityType.directory) {
    throw const FileSystemException('输出父路径不是目录。');
  }
}

void _verifyTemporaryRoundTrip(IconFontOutputs outputs) {
  final Directory temporary = Directory.systemTemp.createTempSync(
    'flutter_template_icon_font_check_',
  );
  try {
    final File font = File(_joinPath(temporary.path, 'font.otf'));
    final File dart = File(_joinPath(temporary.path, 'icons.dart'));
    font.writeAsBytesSync(outputs.fontBytes, flush: true);
    dart.writeAsStringSync(outputs.dartSource, encoding: utf8, flush: true);
    if (!_bytesEqual(font.readAsBytesSync(), outputs.fontBytes) ||
        dart.readAsStringSync(encoding: utf8) != outputs.dartSource) {
      throw IconFontGenerationException(const <String>[
        '[ICON_FONT_TEMP_VERIFY] 临时生成产物回读不一致。',
      ]);
    }
    inspectIconFont(font.readAsBytesSync());
  } finally {
    if (temporary.existsSync()) {
      temporary.deleteSync(recursive: true);
    }
  }
}

final class _GeneratorArguments {
  const _GeneratorArguments({
    required this.projectRoot,
    required this.checkOnly,
  });

  final Directory projectRoot;
  final bool checkOnly;
}

_GeneratorArguments _parseArguments(List<String> arguments) {
  bool checkOnly = false;
  Directory? projectRoot;
  for (int index = 0; index < arguments.length; index += 1) {
    final String argument = arguments[index];
    if (argument == '--check' && !checkOnly) {
      checkOnly = true;
      continue;
    }
    if (argument == '--root' && projectRoot == null) {
      if (index + 1 >= arguments.length || arguments[index + 1].isEmpty) {
        throw const FormatException('--root 必须提供项目路径。');
      }
      projectRoot = Directory(arguments[index + 1]).absolute;
      index += 1;
      continue;
    }
    throw FormatException('不支持或重复的参数 `$argument`。');
  }
  return _GeneratorArguments(
    projectRoot: projectRoot ?? Directory.current.absolute,
    checkOnly: checkOnly,
  );
}

String _readOptionalUtf8(Directory root, String relativePath) {
  final File file = File(_joinPath(root.path, relativePath));
  final FileSystemEntityType type = FileSystemEntity.typeSync(
    file.path,
    followLinks: false,
  );
  if (type == FileSystemEntityType.notFound) {
    return '';
  }
  if (type != FileSystemEntityType.file) {
    throw IconFontGenerationException(<String>[
      '[ICON_FONT_INPUT_UNSAFE] $relativePath 必须是普通文件且不得为符号链接。',
    ]);
  }
  try {
    return file.readAsStringSync(encoding: utf8);
  } on Object {
    throw IconFontGenerationException(<String>[
      '[ICON_FONT_INPUT_UNREADABLE] $relativePath 无法按 UTF-8 读取。',
    ]);
  }
}

void _rejectSymlinkComponents(Directory root, String relativePath) {
  final List<String> segments = relativePath.split('/');
  String current = root.path;
  final int parentCount = segments.length - 1;
  for (int index = 0; index < parentCount; index += 1) {
    current = _joinPath(current, segments[index]);
    final FileSystemEntityType type = FileSystemEntity.typeSync(
      current,
      followLinks: false,
    );
    if (type == FileSystemEntityType.link) {
      throw IconFontGenerationException(<String>[
        '[ICON_FONT_OUTPUT_SYMLINK] $relativePath 不得经过符号链接。',
      ]);
    }
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.directory) {
      throw IconFontGenerationException(<String>[
        '[ICON_FONT_OUTPUT_PARENT] $relativePath 的父路径必须是目录。',
      ]);
    }
  }
}

Map<String, Object?>? _stringObjectMap(Object? value) {
  if (value is! Map<Object?, Object?>) {
    return null;
  }
  final Map<String, Object?> result = <String, Object?>{};
  for (final MapEntry<Object?, Object?> entry in value.entries) {
    if (entry.key is! String) {
      return null;
    }
    result[entry.key! as String] = entry.value;
  }
  return result;
}

int? _parseCodepoint(String value) {
  if (!RegExp(r'^0x[0-9A-F]{4}$').hasMatch(value)) {
    return null;
  }
  return int.tryParse(value.substring(2), radix: 16);
}

String _toLowerCamelCase(String name) {
  final List<String> parts = name.split('_');
  return parts.first +
      parts.skip(1).map((String part) {
        return '${part[0].toUpperCase()}${part.substring(1)}';
      }).join();
}

bool _sameKeys(Iterable<String> actual, Set<String> expected) {
  final Set<String> actualSet = actual.toSet();
  return actualSet.length == expected.length && actualSet.containsAll(expected);
}

bool _bytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) {
    return false;
  }
  for (int index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

String _joinPath(String parent, String child) {
  final String normalizedChild = child.replaceAll('/', Platform.pathSeparator);
  return '$parent${Platform.pathSeparator}$normalizedChild';
}

String _basename(String path) {
  final int separator = path.lastIndexOf(Platform.pathSeparator);
  return separator == -1 ? path : path.substring(separator + 1);
}
