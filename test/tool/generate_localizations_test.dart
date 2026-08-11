import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/generate_localizations.dart';

void main() {
  group('validateLocalizationInputs', () {
    late Map<String, String> resources;

    setUp(() {
      resources = <String, String>{
        'app_en.arb':
            File('lib/app/localization/arb/app_en.arb').readAsStringSync(),
        'app_zh.arb':
            File('lib/app/localization/arb/app_zh.arb').readAsStringSync(),
        'generated_header.txt':
            File(
              'lib/app/localization/arb/generated_header.txt',
            ).readAsStringSync(),
      };
    });

    test('接受完整的英语与中文资源', () {
      expect(
        validateLocalizationInputs(
          configuration: File(localizationConfigurationPath).readAsStringSync(),
          resources: resources,
        ),
        isEmpty,
      );
    });

    test('同时报告缺失翻译与非中文元数据', () {
      final Map<String, Object?> chinese =
          jsonDecode(resources['app_zh.arb']!) as Map<String, Object?>;
      chinese.remove('returnHome');
      chinese.remove('@returnHome');
      final Map<String, Object?> english =
          jsonDecode(resources['app_en.arb']!) as Map<String, Object?>;
      english['@back'] = <String, Object?>{'description': 'Back button label.'};
      resources['app_zh.arb'] = jsonEncode(chinese);
      resources['app_en.arb'] = jsonEncode(english);

      final List<String> violations = validateLocalizationInputs(
        configuration: requiredLocalizationConfiguration,
        resources: resources,
      );

      expect(
        violations.map((String violation) => violation.split(' ').first),
        containsAll(<String>{
          '[L10N_DESCRIPTION_CHINESE]',
          '[L10N_KEYSET_MISMATCH]',
        }),
      );
    });

    test('拒绝配置或输入文件清单漂移', () {
      resources['notes.txt'] = 'not generated';

      final List<String> violations = validateLocalizationInputs(
        configuration: '$requiredLocalizationConfiguration\n',
        resources: resources,
      );

      expect(
        violations.map((String violation) => violation.split(' ').first),
        containsAll(<String>{
          '[L10N_CONFIG_DRIFT]',
          '[L10N_RESOURCE_MANIFEST]',
        }),
      );
    });
  });

  group('validateLocalizationProjectLayout', () {
    test('仓库配置与 Flutter 根目录自动生成入口隔离', () {
      expect(validateLocalizationProjectLayout(Directory.current), isEmpty);
      expect(File('l10n.yaml').existsSync(), isFalse);
    });

    test('拒绝会让普通构建覆写中文产物的根目录配置', () {
      final Directory projectRoot = Directory.systemTemp.createTempSync(
        'flutter-template-l10n-layout-',
      );
      addTearDown(() => projectRoot.deleteSync(recursive: true));
      _createMinimumLocalizationLayout(projectRoot);
      File(
        _pathIn(projectRoot, 'l10n.yaml'),
      ).writeAsStringSync(requiredLocalizationConfiguration);

      expect(
        validateLocalizationProjectLayout(projectRoot),
        contains(startsWith('[L10N_ROOT_CONFIG_FORBIDDEN]')),
      );
    });

    test('拒绝可能在下次构建删除提交产物的旧依赖缓存', () {
      final Directory projectRoot = Directory.systemTemp.createTempSync(
        'flutter-template-l10n-cache-',
      );
      addTearDown(() => projectRoot.deleteSync(recursive: true));
      _createMinimumLocalizationLayout(projectRoot);
      File(
          _pathIn(
            projectRoot,
            '.dart_tool/flutter_build/probe/gen_localizations.d',
          ),
        )
        ..createSync(recursive: true)
        ..writeAsStringSync('legacy output: l10n.yaml');

      expect(
        validateLocalizationProjectLayout(projectRoot),
        contains(startsWith('[L10N_LEGACY_BUILD_CACHE]')),
      );
    });
  });

  group('normalizeGeneratedLocalizationSource', () {
    test('把已知英语实现说明转换为中文', () {
      final String normalized = normalizeGeneratedLocalizationSource(
        relativePath: 'app_localizations_en.dart',
        expectedMessageCount: 0,
        source: '''$requiredGeneratedLocalizationHeader
// ignore: unused_import
// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn {}
''',
      );

      expect(normalized, contains('/// 英语（`en`）文案实现。'));
      expect(normalized, isNot(contains('The translations for English')));
    });

    test('未知英文注释会在写入前失败', () {
      expect(
        () => normalizeGeneratedLocalizationSource(
          relativePath: 'app_localizations_en.dart',
          expectedMessageCount: 0,
          source: '''$requiredGeneratedLocalizationHeader
// ignore_for_file: type=lint
/// The translations for English (`en`).
/// Newly generated English documentation.
class AppLocalizationsEn {}
''',
        ),
        throwsFormatException,
      );
    });
  });

  group('compareLocalizationOutputs', () {
    test('接受逐字节一致的固定清单', () {
      final Map<String, List<int>> expected = <String, List<int>>{
        'app_localizations.dart': utf8.encode('same'),
      };

      expect(
        compareLocalizationOutputs(
          expected: expected,
          actual: <String, List<int>>{
            'app_localizations.dart': List<int>.of(
              expected['app_localizations.dart']!,
            ),
          },
        ),
        isEmpty,
      );
    });

    test('稳定报告缺失、过期和额外文件', () {
      final List<String> violations = compareLocalizationOutputs(
        expected: <String, List<int>>{
          'app_localizations.dart': utf8.encode('new'),
          'app_localizations_en.dart': utf8.encode('english'),
        },
        actual: <String, List<int>>{
          'app_localizations.dart': utf8.encode('old'),
          'unexpected.dart': utf8.encode('extra'),
        },
      );

      expect(
        violations.map((String violation) => violation.split(' ').first),
        <String>[
          '[L10N_OUTPUT_STALE]',
          '[L10N_OUTPUT_MISSING]',
          '[L10N_OUTPUT_UNEXPECTED]',
        ],
      );
    });
  });
}

void _createMinimumLocalizationLayout(Directory projectRoot) {
  File(
    _pathIn(projectRoot, localizationConfigurationPath),
  ).createSync(recursive: true);
  Directory(
    _pathIn(projectRoot, 'lib/app/localization/arb'),
  ).createSync(recursive: true);
}

String _pathIn(Directory projectRoot, String relativePath) {
  final String platformPath = relativePath.replaceAll(
    '/',
    Platform.pathSeparator,
  );
  return '${projectRoot.path}${Platform.pathSeparator}$platformPath';
}
