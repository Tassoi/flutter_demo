import 'package:flutter_test/flutter_test.dart';

import '../../../tool/ci/check_documentation.dart';

const String _flutterSdkCompatibilityRefCommand =
    'git -C "\$FLUTTER_ROOT" update-ref refs/remotes/origin/master '
    '"\$FLUTTER_REVISION"';

void main() {
  group('validateDocumentation', () {
    test(
      'accepts complete guides, local anchors, command targets, and CI order',
      () {
        final fixture = _validFixture();

        final violations = validateDocumentation(
          documents: fixture.documents,
          projectPaths: fixture.projectPaths,
          qualityWorkflow: fixture.qualityWorkflow,
        );

        expect(violations, isEmpty);
      },
    );

    test('reports missing, escaped, and unknown local link anchors', () {
      final fixture = _validFixture();
      fixture.documents['docs/internationalization.md'] = '''
# 国际化

[缺失](missing.md)
[越界](../../outside.md)
[锚点](../README.md#不存在)
''';

      final violations = validateDocumentation(
        documents: fixture.documents,
        projectPaths: fixture.projectPaths,
        qualityWorkflow: fixture.qualityWorkflow,
      );

      expect(
        violations.map((violation) => violation.split(' ').first),
        containsAll(<String>{
          '[DOC_LINK_ANCHOR]',
          '[DOC_LINK_MISSING]',
          '[DOC_LINK_OUTSIDE_ROOT]',
        }),
      );
    });

    test('reports missing command paths and quality workflow drift', () {
      final fixture = _validFixture();
      fixture.documents['README.md'] = fixture.documents['README.md']!
          .replaceFirst(
            'flutter test test/tool/generate_agents_test.dart',
            'flutter test test/tool/missing_test.dart',
          );
      fixture.qualityWorkflow = fixture.qualityWorkflow.replaceFirst(
        'dart tool/ci/check_documentation.dart',
        'dart tool/ci/check_architecture.dart',
      );

      final violations = validateDocumentation(
        documents: fixture.documents,
        projectPaths: fixture.projectPaths,
        qualityWorkflow: fixture.qualityWorkflow,
      );

      expect(
        violations.map((violation) => violation.split(' ').first),
        containsAll(<String>{
          '[DOC_COMMAND_TARGET_MISSING]',
          '[DOC_QUALITY_COMMAND_DRIFT]',
        }),
      );
    });

    test('reports a missing pinned Flutter SDK compatibility ref', () {
      final fixture = _validFixture();
      fixture.qualityWorkflow = fixture.qualityWorkflow.replaceFirst(
        _flutterSdkCompatibilityRefCommand,
        '',
      );

      final violations = validateDocumentation(
        documents: fixture.documents,
        projectPaths: fixture.projectPaths,
        qualityWorkflow: fixture.qualityWorkflow,
      );

      expect(
        violations.map((violation) => violation.split(' ').first),
        contains('[DOC_QUALITY_FLUTTER_BOOTSTRAP]'),
      );
    });

    test('rejects unsafe code examples and a missing phase-two guide link', () {
      final fixture = _validFixture();
      fixture.documents['docs/phase-2-operations.md'] = fixture
          .documents['docs/phase-2-operations.md']!
          .replaceFirst('[认证](authentication.md)', '认证说明已省略')
          .replaceFirst(
            '```bash\nflutter run',
            '```bash\n/home/alice/private/tool\n'
                'curl https://service.example.com/session\n'
                '-----BEGIN PRIVATE KEY-----\nflutter run',
          );

      final violations = validateDocumentation(
        documents: fixture.documents,
        projectPaths: fixture.projectPaths,
        qualityWorkflow: fixture.qualityWorkflow,
      );

      expect(
        violations.map((violation) => violation.split(' ').first),
        containsAll(<String>{
          '[DOC_PERSONAL_PATH]',
          '[DOC_PHASE2_GUIDE_LINK]',
          '[DOC_PRIVATE_KEY]',
          '[DOC_UNSAFE_EXAMPLE_URL]',
        }),
      );
    });
  });
}

_DocumentationFixture _validFixture() {
  const qualityCommands = '''
dart tool/ci/check_generated_files.dart
flutter pub get --enforce-lockfile
dart run tool/generate_localizations.dart --check
dart run tool/generate_icon_font.dart --check
dart run tool/generate_branding.dart --check
flutter test test/tool/generate_agents_test.dart
dart tool/ci/check_documentation.dart
dart tool/ci/check_architecture.dart
dart tool/ci/check_platform_environments.dart
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos --fatal-warnings
flutter test --test-randomize-ordering-seed=20260809
''';
  final documents = <String, String>{
    'README.md': '''
# 首页

[本地锚点](#质量命令)

## 质量命令

```bash
$qualityCommands```
''',
    'docs/phase-2-operations.md': '''
# 第二阶段操作

[适配](mobile-screen-adaptation.md)
[国际化](internationalization.md)
[字体](svg-icon-font.md)
[认证](authentication.md)
[品牌](branding.md)
[Agent](agents-generation.md)

```bash
$qualityCommands```

```bash
flutter run --flavor dev --dart-define-from-file=config/dev.example.json
flutter build apk --debug --flavor dev \\
  --dart-define-from-file=config/dev.example.json
flutter build appbundle --debug --flavor dev \\
  --dart-define-from-file=config/dev.example.json
flutter build ios --debug --no-codesign --flavor dev \\
  --dart-define-from-file=config/dev.example.json
```
''',
    'docs/agents-generation.md': '# Agent\n',
    'docs/authentication.md': '# 认证\n',
    'docs/branding.md': '# 品牌\n',
    'docs/dependency-upgrades.md': '# 升级\n',
    'docs/internationalization.md': '# 国际化\n',
    'docs/mobile-screen-adaptation.md': '# 适配\n',
    'docs/svg-icon-font.md': '# 字体\n',
    'docs/troubleshooting.md': '# 故障\n',
  };
  final projectPaths = <String>{
    ...documents.keys,
    'config/dev.example.json',
    'test/tool/generate_agents_test.dart',
    'tool/ci/check_architecture.dart',
    'tool/ci/check_documentation.dart',
    'tool/ci/check_generated_files.dart',
    'tool/ci/check_platform_environments.dart',
    'tool/generate_branding.dart',
    'tool/generate_icon_font.dart',
    'tool/generate_localizations.dart',
  };
  final qualityWorkflow = '''
$_flutterSdkCompatibilityRefCommand
run: flutter config --no-analytics
$qualityCommands
$_flutterSdkCompatibilityRefCommand
run: flutter config --no-analytics
$_flutterSdkCompatibilityRefCommand
run: flutter config --no-analytics
''';
  return _DocumentationFixture(
    documents: documents,
    projectPaths: projectPaths,
    qualityWorkflow: qualityWorkflow,
  );
}

final class _DocumentationFixture {
  _DocumentationFixture({
    required this.documents,
    required this.projectPaths,
    required this.qualityWorkflow,
  });

  final Map<String, String> documents;
  final Set<String> projectPaths;
  String qualityWorkflow;
}
