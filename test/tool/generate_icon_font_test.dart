import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/generate_icon_font.dart';

void main() {
  late IconFontInputs projectInputs;

  setUp(() {
    projectInputs = readIconFontInputs(Directory.current);
  });

  group('SVG 字体输入与确定性生成', () {
    test('真实输入生成固定 family、时间、codepoint 和中文 Dart 映射', () {
      expect(validateIconFontInputs(projectInputs), isEmpty);

      final IconFontOutputs first = buildIconFontOutputs(projectInputs);
      final IconFontOutputs second = buildIconFontOutputs(projectInputs);
      final IconFontInspection inspection = inspectIconFont(first.fontBytes);

      expect(second.fontBytes, orderedEquals(first.fontBytes));
      expect(second.dartSource, first.dartSource);
      expect(inspection.familyName, 'TemplateIcons');
      expect(inspection.created, DateTime.utc(2000));
      expect(inspection.modified, DateTime.utc(2000));
      expect(inspection.copyright, 'Copyright icon_font_generator 2000');
      expect(inspection.glyphCount, 4);
      expect(inspection.codepointToGlyph[0xE000], 2);
      expect(inspection.codepointToGlyph[0xE001], 3);
      expect(first.dartSource, contains('请勿手工修改'));
      expect(first.dartSource, contains('static const IconData language'));
      expect(first.dartSource, contains('static const IconData check'));
      expect(first.dartSource, isNot(contains('Generated using')));
    });

    test('重排清单不会改变字体或 Dart 的任一字节', () {
      final Map<String, Object?> manifest = _decodeManifest(projectInputs);
      final List<Object?> glyphs = List<Object?>.of(
        manifest['glyphs']! as List<Object?>,
      );
      manifest['glyphs'] = glyphs.reversed.toList();
      final IconFontInputs reordered = _replaceInputs(
        projectInputs,
        manifest: manifest,
      );

      final IconFontOutputs original = buildIconFontOutputs(projectInputs);
      final IconFontOutputs changed = buildIconFontOutputs(reordered);

      expect(changed.fontBytes, orderedEquals(original.fontBytes));
      expect(changed.dartSource, original.dartSource);
    });

    test('追加和退休只改变对应槽位，不移动已有映射', () {
      final Map<String, Object?> appendedManifest = _decodeManifest(
        projectInputs,
      );
      final List<Object?> appendedGlyphs = List<Object?>.of(
        appendedManifest['glyphs']! as List<Object?>,
      )..add(<String, Object?>{
        'name': 'sample_box',
        'codepoint': '0xE002',
        'status': 'active',
        'description': '用于验证追加编号稳定性的方框图标。',
        'licenseId': 'template-original',
        'matchTextDirection': false,
        'svg': 'svg/sample_box.svg',
      });
      appendedManifest
        ..['glyphs'] = appendedGlyphs
        ..['nextCodepoint'] = '0xE003';
      final IconFontInputs appendedInputs = _replaceInputs(
        projectInputs,
        manifest: appendedManifest,
        svgSources: <String, String>{
          ...projectInputs.svgSources,
          'sample_box.svg': _sampleBoxSvg,
        },
      );

      final IconFontOutputs appended = buildIconFontOutputs(appendedInputs);
      final IconFontInspection appendedInspection = inspectIconFont(
        appended.fontBytes,
      );
      expect(appendedInspection.codepointToGlyph[0xE000], 2);
      expect(appendedInspection.codepointToGlyph[0xE001], 3);
      expect(appendedInspection.codepointToGlyph[0xE002], 4);
      expect(appended.dartSource, contains('IconData sampleBox'));

      final Map<String, Object?> retiredManifest = _decodeManifest(
        appendedInputs,
      );
      final List<Object?> retiredGlyphs = List<Object?>.of(
        retiredManifest['glyphs']! as List<Object?>,
      );
      final Map<String, Object?> retiredLanguage =
          Map<String, Object?>.of(retiredGlyphs.first! as Map<String, Object?>)
            ..remove('svg')
            ..['status'] = 'retired'
            ..['retiredReason'] = '示例退休，用于证明历史 codepoint 不会被复用。';
      retiredGlyphs[0] = retiredLanguage;
      retiredManifest['glyphs'] = retiredGlyphs;
      final Map<String, String> retiredSources = Map<String, String>.of(
        appendedInputs.svgSources,
      )..remove('language.svg');

      final IconFontOutputs retired = buildIconFontOutputs(
        _replaceInputs(
          appendedInputs,
          manifest: retiredManifest,
          svgSources: retiredSources,
        ),
      );
      final IconFontInspection retiredInspection = inspectIconFont(
        retired.fontBytes,
      );
      expect(retiredInspection.codepointToGlyph[0xE000], 2);
      expect(retiredInspection.codepointToGlyph[0xE001], 3);
      expect(retiredInspection.codepointToGlyph[0xE002], 4);
      expect(retired.dartSource, isNot(contains('IconData language')));
      expect(retired.dartSource, contains('IconData check'));
      expect(retired.dartSource, contains('IconData sampleBox'));
    });

    test('删除尾部条目但保留历史 nextCodepoint 会要求 retired 墓碑', () {
      final Map<String, Object?> manifest = _decodeManifest(projectInputs);
      final List<Object?> glyphs = List<Object?>.of(
        manifest['glyphs']! as List<Object?>,
      )..removeLast();
      manifest['glyphs'] = glyphs;
      final Map<String, String> sources = Map<String, String>.of(
        projectInputs.svgSources,
      )..remove('check.svg');

      final List<String> violations = validateIconFontInputs(
        _replaceInputs(projectInputs, manifest: manifest, svgSources: sources),
      );

      expect(violations, contains(startsWith('[ICON_FONT_NEXT_CODEPOINT]')));
    });
  });

  group('SVG 字体失败预检', () {
    test('同时拒绝重复名称、重复 codepoint 和目录清单漂移', () {
      final Map<String, Object?> manifest = _decodeManifest(projectInputs);
      final List<Object?> glyphs = List<Object?>.of(
        manifest['glyphs']! as List<Object?>,
      );
      final Map<String, Object?> duplicate =
          Map<String, Object?>.of(glyphs.last! as Map<String, Object?>)
            ..['name'] = 'language'
            ..['codepoint'] = '0xE000'
            ..['svg'] = 'svg/language.svg';
      glyphs[1] = duplicate;
      manifest['glyphs'] = glyphs;

      final List<String> violations = validateIconFontInputs(
        _replaceInputs(projectInputs, manifest: manifest),
      );

      expect(
        _violationCodes(violations),
        containsAll(<String>{
          '[ICON_FONT_GLYPH_NAME_DUPLICATE]',
          '[ICON_FONT_CODEPOINT_DUPLICATE]',
          '[ICON_FONT_CODEPOINT_SEQUENCE]',
          '[ICON_FONT_SVG_MANIFEST]',
        }),
      );
    });

    test('许可证缺失会在字体构建前失败', () {
      final IconFontInputs missingLicense = IconFontInputs(
        manifestSource: projectInputs.manifestSource,
        licenseSource: '',
        svgSources: projectInputs.svgSources,
        pubspecSource: projectInputs.pubspecSource,
      );

      final List<String> violations = validateIconFontInputs(missingLicense);

      expect(violations, contains(startsWith('[ICON_FONT_LICENSE_MISSING]')));
      expect(
        () => buildIconFontOutputs(missingLicense),
        throwsA(isA<IconFontGenerationException>()),
      );
    });

    test('不支持的 shape、样式和损坏 XML 都有稳定错误', () {
      final IconFontInputs unsupportedShape = _replaceInputs(
        projectInputs,
        svgSources: <String, String>{
          ...projectInputs.svgSources,
          'language.svg':
              '<svg xmlns="http://www.w3.org/2000/svg" '
              'viewBox="0 0 24 24"><rect x="2" y="2" width="20" '
              'height="20"/></svg>',
        },
      );
      final IconFontInputs styledPath = _replaceInputs(
        projectInputs,
        svgSources: <String, String>{
          ...projectInputs.svgSources,
          'language.svg':
              '<svg xmlns="http://www.w3.org/2000/svg" '
              'viewBox="0 0 24 24"><path fill="red" '
              'd="M2 2 H22 V22 H2 Z"/></svg>',
        },
      );
      final IconFontInputs brokenXml = _replaceInputs(
        projectInputs,
        svgSources: <String, String>{
          ...projectInputs.svgSources,
          'language.svg': '<svg><path d="M0 0"',
        },
      );

      expect(
        validateIconFontInputs(unsupportedShape),
        contains(startsWith('[ICON_FONT_SVG_STRUCTURE]')),
      );
      expect(
        validateIconFontInputs(styledPath),
        contains(startsWith('[ICON_FONT_SVG_STRUCTURE]')),
      );
      expect(
        validateIconFontInputs(brokenXml),
        contains(startsWith('[ICON_FONT_SVG_INVALID]')),
      );
    });
  });

  group('SVG 字体输出事务与只读检查', () {
    test('第二个目标安装失败会完整恢复两个旧文件', () {
      final Directory root = Directory.systemTemp.createTempSync(
        'flutter-template-icon-font-rollback-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final File oldFont =
          _fileIn(root, 'assets/fonts/template_icons.otf')
            ..createSync(recursive: true)
            ..writeAsBytesSync(<int>[1, 2, 3]);
      final File oldDart =
          _fileIn(root, 'lib/shared/assets/generated/template_icons.g.dart')
            ..createSync(recursive: true)
            ..writeAsStringSync('old dart output');
      final IconFontOutputs outputs = buildIconFontOutputs(projectInputs);

      expect(
        () => replaceIconFontOutputs(
          projectRoot: root,
          outputs: outputs,
          beforeInstall: (String relativePath) {
            if (relativePath.endsWith('.dart')) {
              throw const FileSystemException('injected write failure');
            }
          },
        ),
        throwsA(
          isA<IconFontGenerationException>().having(
            (IconFontGenerationException error) => error.violations,
            'violations',
            contains(startsWith('[ICON_FONT_WRITE_FAILED]')),
          ),
        ),
      );
      expect(oldFont.readAsBytesSync(), <int>[1, 2, 3]);
      expect(oldDart.readAsStringSync(), 'old dart output');
      expect(Directory(_pathIn(root, '.dart_tool')).listSync(), isEmpty);

      replaceIconFontOutputs(projectRoot: root, outputs: outputs);
      expect(
        compareIconFontOutputs(projectRoot: root, expected: outputs),
        isEmpty,
      );
    });

    test('外部干扰导致回滚失败时保留暂存备份供人工恢复', () {
      final Directory root = Directory.systemTemp.createTempSync(
        'flutter-template-icon-font-recovery-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      _fileIn(root, 'assets/fonts/template_icons.otf')
        ..createSync(recursive: true)
        ..writeAsBytesSync(<int>[7, 8, 9]);
      final File oldDart =
          _fileIn(root, 'lib/shared/assets/generated/template_icons.g.dart')
            ..createSync(recursive: true)
            ..writeAsStringSync('recover this dart output');
      final IconFontOutputs outputs = buildIconFontOutputs(projectInputs);

      expect(
        () => replaceIconFontOutputs(
          projectRoot: root,
          outputs: outputs,
          beforeInstall: (String relativePath) {
            if (relativePath.endsWith('.dart')) {
              // 旧 Dart 已移动到备份区；用同名目录模拟外部进程抢占目标，
              // 使备份无法原名恢复，从而验证灾难恢复文件不会被 finally 清除。
              Directory(oldDart.path).createSync();
              throw const FileSystemException('injected rollback failure');
            }
          },
        ),
        throwsA(
          isA<IconFontGenerationException>().having(
            (IconFontGenerationException error) => error.violations,
            'violations',
            contains(startsWith('[ICON_FONT_ROLLBACK_FAILED]')),
          ),
        ),
      );

      final Directory dartTool = Directory(_pathIn(root, '.dart_tool'));
      final List<File> recoveryFiles =
          dartTool
              .listSync(recursive: true, followLinks: false)
              .whereType<File>()
              .where(
                (File file) => file.path.contains(
                  '${Platform.pathSeparator}backups${Platform.pathSeparator}',
                ),
              )
              .toList();
      expect(recoveryFiles, hasLength(1));
      expect(
        recoveryFiles.single.readAsStringSync(),
        'recover this dart output',
      );
      expect(
        _fileIn(root, 'assets/fonts/template_icons.otf').readAsBytesSync(),
        <int>[7, 8, 9],
      );
    });

    test('--check 核心路径只读，并稳定发现过期字体', () {
      final Directory root = Directory.systemTemp.createTempSync(
        'flutter-template-icon-font-check-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      _createProjectCopy(root, projectInputs);
      final IconFontOutputs outputs = buildIconFontOutputs(projectInputs);
      replaceIconFontOutputs(projectRoot: root, outputs: outputs);
      final Directory dartTool = Directory(_pathIn(root, '.dart_tool'));
      if (dartTool.existsSync()) {
        dartTool.deleteSync(recursive: true);
      }
      final Map<String, String> before = _snapshotTree(root);

      expect(checkIconFontProject(root), isEmpty);
      expect(_snapshotTree(root), before);
      expect(dartTool.existsSync(), isFalse);

      final File font = _fileIn(root, 'assets/fonts/template_icons.otf');
      final List<int> staleBytes = font.readAsBytesSync();
      staleBytes[staleBytes.length - 1] ^= 0x01;
      font.writeAsBytesSync(staleBytes, flush: true);
      final Map<String, String> staleBefore = _snapshotTree(root);

      expect(
        checkIconFontProject(root),
        contains(startsWith('[ICON_FONT_OUTPUT_STALE]')),
      );
      expect(_snapshotTree(root), staleBefore);
      expect(dartTool.existsSync(), isFalse);
    });
  });
}

const String _sampleBoxSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">'
    '<path d="M4 4 H20 V20 H4 Z"/>'
    '</svg>';

Map<String, Object?> _decodeManifest(IconFontInputs inputs) {
  return jsonDecode(inputs.manifestSource) as Map<String, Object?>;
}

IconFontInputs _replaceInputs(
  IconFontInputs original, {
  Map<String, Object?>? manifest,
  Map<String, String>? svgSources,
}) {
  return IconFontInputs(
    manifestSource:
        manifest == null
            ? original.manifestSource
            : '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
    licenseSource: original.licenseSource,
    svgSources: svgSources ?? original.svgSources,
    pubspecSource: original.pubspecSource,
  );
}

Set<String> _violationCodes(List<String> violations) {
  return violations
      .map((String violation) => violation.split(' ').first)
      .toSet();
}

void _createProjectCopy(Directory root, IconFontInputs inputs) {
  _fileIn(root, 'pubspec.yaml')
    ..createSync(recursive: true)
    ..writeAsStringSync(inputs.pubspecSource);
  _fileIn(root, 'assets/icons/icon_font_manifest.json')
    ..createSync(recursive: true)
    ..writeAsStringSync(inputs.manifestSource);
  _fileIn(root, 'assets/icons/LICENSE.md')
    ..createSync(recursive: true)
    ..writeAsStringSync(inputs.licenseSource);
  for (final MapEntry<String, String> svg in inputs.svgSources.entries) {
    _fileIn(root, 'assets/icons/svg/${svg.key}')
      ..createSync(recursive: true)
      ..writeAsStringSync(svg.value);
  }
}

Map<String, String> _snapshotTree(Directory root) {
  final List<FileSystemEntity> entities = root.listSync(
    recursive: true,
    followLinks: false,
  )..sort((FileSystemEntity left, FileSystemEntity right) {
    return left.path.compareTo(right.path);
  });
  return <String, String>{
    for (final FileSystemEntity entity in entities)
      entity.path.substring(
        root.path.length,
      ): switch (FileSystemEntity.typeSync(entity.path, followLinks: false)) {
        FileSystemEntityType.file =>
          'file:${File(entity.path).lastModifiedSync().microsecondsSinceEpoch}:'
              '${base64Encode(File(entity.path).readAsBytesSync())}',
        FileSystemEntityType.directory => 'directory',
        FileSystemEntityType.link => 'link',
        _ => 'other',
      },
  };
}

File _fileIn(Directory root, String relativePath) {
  return File(_pathIn(root, relativePath));
}

String _pathIn(Directory root, String relativePath) {
  return '${root.path}${Platform.pathSeparator}'
      '${relativePath.replaceAll('/', Platform.pathSeparator)}';
}
