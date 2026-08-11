import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/generate_agents.dart';

void main() {
  group('基础 AGENTS.md 生成器', () {
    test('首次生成 UTF-8 LF 中文指南并完整拼接 Goal Mode', () {
      final Directory projectRoot = _createTemporaryProject();
      final StringBuffer output = StringBuffer();
      final StringBuffer errorOutput = StringBuffer();

      final int result = runAgentsGenerator(
        const <String>[],
        projectRoot: projectRoot,
        output: output,
        errorOutput: errorOutput,
      );

      expect(result, 0);
      expect(errorOutput.toString(), isEmpty);
      expect(output.toString(), contains('已创建 AGENTS.md'));

      final File generated = File(_pathIn(projectRoot, agentsOutputPath));
      final List<int> bytes = generated.readAsBytesSync();
      final String document = utf8.decode(bytes, allowMalformed: false);
      final String goalMode = File(
        _pathIn(projectRoot, agentsGoalModeTemplatePath),
      ).readAsStringSync(encoding: utf8);

      expect(bytes.take(3), isNot(<int>[0xEF, 0xBB, 0xBF]));
      expect(document, isNot(contains('\r')));
      expect(document, endsWith('\n'));
      expect(document, contains('# Flutter 项目 Agent 指南'));
      expect(document, contains('## 注释与文档规范'));
      expect(document, contains('生成到项目中的代码注释使用中文'));
      expect(document, contains('## 测试规范'));
      expect(document, contains('## 密钥与安全'));
      expect(document, contains('## Git 与外部操作'));
      expect(document, contains('dart run tool/generate_agents.dart --check'));
      expect(document, contains('dart tool/ci/check_documentation.dart'));
      expect(document, contains('375 x 812'));
      expect(document, contains('`du`/`dsp`'));
      expect(document, contains('`320x568`'));
      expect(document, contains('`800x360`'));
      expect(document, contains('GOAL_INIT_DONE'));
      expect(document, contains('每轮只执行一个任务'));
      expect(document, contains('每完成三个实现任务'));
      expect(document, contains('### 阻塞与无人值守约束'));
      expect(document, contains('最终全面 Review'));
      expect(
        document.substring(document.indexOf('## Goal Mode 工作流')),
        goalMode,
      );
      expect(document, isNot(contains(agentsGoalModePlaceholder)));
      expect(document, isNot(contains('/mnt/')));
      expect(document, isNot(contains('/Users/')));
      expect(document, isNot(contains('http://')));
      expect(document, isNot(contains('https://')));
    });

    test('相同模板始终产生完全一致的字符串和 UTF-8 字节', () {
      final Directory projectRoot = _createTemporaryProject();
      final String baseTemplate = File(
        _pathIn(projectRoot, agentsBaseTemplatePath),
      ).readAsStringSync(encoding: utf8);
      final String goalModeTemplate = File(
        _pathIn(projectRoot, agentsGoalModeTemplatePath),
      ).readAsStringSync(encoding: utf8);

      final String first = buildAgentsDocument(
        baseTemplate: baseTemplate,
        goalModeTemplate: goalModeTemplate,
      );
      final String second = buildAgentsDocument(
        baseTemplate: baseTemplate,
        goalModeTemplate: goalModeTemplate,
      );

      expect(second, first);
      expect(utf8.encode(second), orderedEquals(utf8.encode(first)));
    });

    test('重复运行接受相同目标且不改变内容或 mtime', () {
      final Directory projectRoot = _createTemporaryProject();
      expect(
        generateAgentsGuide(projectRoot: projectRoot),
        AgentsGenerationStatus.created,
      );
      final File target = File(_pathIn(projectRoot, agentsOutputPath));
      final List<int> originalBytes = target.readAsBytesSync();
      target.setLastModifiedSync(DateTime.utc(2001, 2, 3, 4, 5, 6));
      final DateTime originalModified = target.lastModifiedSync();

      final AgentsGenerationStatus result = generateAgentsGuide(
        projectRoot: projectRoot,
      );

      expect(result, AgentsGenerationStatus.unchanged);
      expect(target.readAsBytesSync(), orderedEquals(originalBytes));
      expect(target.lastModifiedSync(), originalModified);
    });

    test('--check 匹配时成功且连续检查零写入、输出确定', () {
      final Directory projectRoot = _createTemporaryProject();
      expect(
        generateAgentsGuide(projectRoot: projectRoot),
        AgentsGenerationStatus.created,
      );
      final File target = File(_pathIn(projectRoot, agentsOutputPath));
      target.setLastModifiedSync(DateTime.utc(2003, 4, 5, 6, 7, 8));
      final _ProjectSnapshot before = _snapshotProject(projectRoot);
      bool writeHookCalled = false;
      final StringBuffer firstOutput = StringBuffer();

      final int firstResult = runAgentsGenerator(
        const <String>['--check'],
        projectRoot: projectRoot,
        output: firstOutput,
        errorOutput: StringBuffer(),
        beforeWrite: (_) => writeHookCalled = true,
      );
      final StringBuffer secondOutput = StringBuffer();
      final int secondResult = runAgentsGenerator(
        const <String>['--check'],
        projectRoot: projectRoot,
        output: secondOutput,
        errorOutput: StringBuffer(),
        beforeWrite: (_) => writeHookCalled = true,
      );

      expect(firstResult, 0);
      expect(secondResult, 0);
      expect(firstOutput.toString(), contains('检查通过'));
      expect(secondOutput.toString(), firstOutput.toString());
      expect(writeHookCalled, isFalse);
      _expectProjectUnchanged(projectRoot, before);
    });

    test('--check 区分缺失目标且不执行初始化', () {
      final Directory projectRoot = _createTemporaryProject();
      final _ProjectSnapshot before = _snapshotProject(projectRoot);
      final StringBuffer errorOutput = StringBuffer();

      final int result = runAgentsGenerator(
        const <String>['--check'],
        projectRoot: projectRoot,
        output: StringBuffer(),
        errorOutput: errorOutput,
      );

      expect(result, 1);
      expect(errorOutput.toString(), contains('[AGENTS_CHECK_MISSING]'));
      _expectProjectUnchanged(projectRoot, before);
    });

    test('--check 区分用户修改导致的过期目标且不覆盖', () {
      final Directory projectRoot = _createTemporaryProject();
      expect(
        generateAgentsGuide(projectRoot: projectRoot),
        AgentsGenerationStatus.created,
      );
      final File target = File(_pathIn(projectRoot, agentsOutputPath));
      target.writeAsStringSync(
        '\n<!-- 用户项目补充规则 -->\n',
        mode: FileMode.append,
        flush: true,
      );
      target.setLastModifiedSync(DateTime.utc(2004, 5, 6, 7, 8, 9));
      final _ProjectSnapshot before = _snapshotProject(projectRoot);
      final StringBuffer errorOutput = StringBuffer();

      final int result = runAgentsGenerator(
        const <String>['--check'],
        projectRoot: projectRoot,
        output: StringBuffer(),
        errorOutput: errorOutput,
      );

      expect(result, 1);
      expect(errorOutput.toString(), contains('[AGENTS_CHECK_STALE]'));
      _expectProjectUnchanged(projectRoot, before);
    });

    test('--check 区分无法读取目标且不回退为过期或覆盖', () {
      final Directory projectRoot = _createTemporaryProject();
      expect(
        generateAgentsGuide(projectRoot: projectRoot),
        AgentsGenerationStatus.created,
      );
      final _ProjectSnapshot before = _snapshotProject(projectRoot);
      final StringBuffer errorOutput = StringBuffer();

      final int result = runAgentsGenerator(
        const <String>['--check'],
        projectRoot: projectRoot,
        output: StringBuffer(),
        errorOutput: errorOutput,
        readTargetBytes: (_) {
          throw const FileSystemException('injected unreadable target');
        },
      );

      expect(result, 1);
      expect(errorOutput.toString(), contains('[AGENTS_CHECK_UNREADABLE]'));
      expect(errorOutput.toString(), isNot(contains('[AGENTS_CHECK_STALE]')));
      _expectProjectUnchanged(projectRoot, before);
    });

    test('--check 区分非法目标类型且不删除调用方目录', () {
      final Directory projectRoot = _createTemporaryProject();
      Directory(_pathIn(projectRoot, agentsOutputPath)).createSync();
      final _ProjectSnapshot before = _snapshotProject(projectRoot);
      final StringBuffer errorOutput = StringBuffer();

      final int result = runAgentsGenerator(
        const <String>['--check'],
        projectRoot: projectRoot,
        output: StringBuffer(),
        errorOutput: errorOutput,
      );

      expect(result, 1);
      expect(errorOutput.toString(), contains('[AGENTS_CHECK_INVALID]'));
      _expectProjectUnchanged(projectRoot, before);
    });

    test('已有用户目标不一致时失败且不改变字节或 mtime', () {
      final Directory projectRoot = _createTemporaryProject();
      final File target = File(_pathIn(projectRoot, agentsOutputPath));
      final List<int> userBytes = utf8.encode('# 用户维护的项目规则\n');
      target.writeAsBytesSync(userBytes, flush: true);
      target.setLastModifiedSync(DateTime.utc(2002, 3, 4, 5, 6, 7));
      final DateTime originalModified = target.lastModifiedSync();
      final StringBuffer errorOutput = StringBuffer();

      final int result = runAgentsGenerator(
        const <String>[],
        projectRoot: projectRoot,
        output: StringBuffer(),
        errorOutput: errorOutput,
      );

      expect(result, 1);
      expect(errorOutput.toString(), contains('[AGENTS_TARGET_EXISTS]'));
      expect(target.readAsBytesSync(), orderedEquals(userBytes));
      expect(target.lastModifiedSync(), originalModified);
    });

    test('拒绝 force、root 和组合参数且不创建目标', () {
      for (final List<String> arguments in <List<String>>[
        <String>['--force'],
        <String>['--root', 'temporary-project'],
        <String>['--check', '--check'],
        <String>['--check', '--force'],
      ]) {
        final Directory projectRoot = _createTemporaryProject();
        final StringBuffer errorOutput = StringBuffer();

        final int result = runAgentsGenerator(
          arguments,
          projectRoot: projectRoot,
          output: StringBuffer(),
          errorOutput: errorOutput,
        );

        expect(result, 64, reason: arguments.join(' '));
        expect(errorOutput.toString(), contains('无参数初始化或单一 --check'));
        expect(
          File(_pathIn(projectRoot, agentsOutputPath)).existsSync(),
          isFalse,
        );
      }
    });

    test('Goal Mode 局部模板缺失时稳定失败且不创建目标', () {
      final Directory projectRoot = _createTemporaryProject();
      File(_pathIn(projectRoot, agentsGoalModeTemplatePath)).deleteSync();
      final StringBuffer errorOutput = StringBuffer();

      final int result = runAgentsGenerator(
        const <String>[],
        projectRoot: projectRoot,
        output: StringBuffer(),
        errorOutput: errorOutput,
      );

      expect(result, 1);
      expect(errorOutput.toString(), contains('[AGENTS_TEMPLATE_MISSING]'));
      expect(
        File(_pathIn(projectRoot, agentsOutputPath)).existsSync(),
        isFalse,
      );
    });

    test('非法目标类型失败且不会删除调用方目录', () {
      final Directory projectRoot = _createTemporaryProject();
      final Directory targetDirectory = Directory(
        _pathIn(projectRoot, agentsOutputPath),
      )..createSync();
      final StringBuffer errorOutput = StringBuffer();

      final int result = runAgentsGenerator(
        const <String>[],
        projectRoot: projectRoot,
        output: StringBuffer(),
        errorOutput: errorOutput,
      );

      expect(result, 1);
      expect(errorOutput.toString(), contains('[AGENTS_TARGET_INVALID]'));
      expect(targetDirectory.existsSync(), isTrue);
    });

    test('注入写入失败后清理本轮目标且不残留部分内容', () {
      final Directory projectRoot = _createTemporaryProject();
      final StringBuffer errorOutput = StringBuffer();

      final int result = runAgentsGenerator(
        const <String>[],
        projectRoot: projectRoot,
        output: StringBuffer(),
        errorOutput: errorOutput,
        beforeWrite: (String relativePath) {
          expect(relativePath, agentsOutputPath);
          throw const FileSystemException('injected write failure');
        },
      );

      expect(result, 1);
      expect(errorOutput.toString(), contains('[AGENTS_WRITE_FAILED]'));
      expect(
        FileSystemEntity.typeSync(
          _pathIn(projectRoot, agentsOutputPath),
          followLinks: false,
        ),
        FileSystemEntityType.notFound,
      );
    });

    test('拒绝重复占位符和 CRLF 模板', () {
      final Directory projectRoot = _createTemporaryProject();
      final String baseTemplate = File(
        _pathIn(projectRoot, agentsBaseTemplatePath),
      ).readAsStringSync(encoding: utf8);
      final String goalModeTemplate = File(
        _pathIn(projectRoot, agentsGoalModeTemplatePath),
      ).readAsStringSync(encoding: utf8);

      expect(
        () => buildAgentsDocument(
          baseTemplate: '$agentsGoalModePlaceholder\n$baseTemplate',
          goalModeTemplate: goalModeTemplate.replaceFirst('\n', '\r\n'),
        ),
        throwsA(
          isA<AgentsGenerationException>().having(
            (AgentsGenerationException error) => error.violations.join('\n'),
            'violations',
            allOf(
              contains('[AGENTS_TEMPLATE_MARKER]'),
              contains('[AGENTS_TEMPLATE_LINE_ENDING]'),
            ),
          ),
        ),
      );
    });
  });

  group('Agent 模板仓库漂移契约', () {
    test('根规范、两份模板和临时初始化样例保持同步', () {
      final Directory repositoryRoot = _createTemporaryProject(
        includeRootGuide: true,
      );
      final Directory sampleRoot = _createTemporaryProject();
      expect(
        generateAgentsGuide(projectRoot: sampleRoot),
        AgentsGenerationStatus.created,
      );

      final List<String> violations = validateAgentsRepositoryContract(
        rootGuide: _readFixture(repositoryRoot, agentsOutputPath),
        baseTemplate: _readFixture(repositoryRoot, agentsBaseTemplatePath),
        goalModeTemplate: _readFixture(
          repositoryRoot,
          agentsGoalModeTemplatePath,
        ),
        generatedSample: _readFixture(sampleRoot, agentsOutputPath),
      );

      expect(violations, isEmpty);
    });

    test('删除根规范 Goal Mode 条款会触发逐字漂移', () {
      final _AgentsContractFixture fixture = _createContractFixture();
      final String changedRoot = fixture.rootGuide.replaceFirst(
        '每轮只执行一个任务',
        '每轮执行当前任务',
      );

      final List<String> violations = validateAgentsRepositoryContract(
        rootGuide: changedRoot,
        baseTemplate: fixture.baseTemplate,
        goalModeTemplate: fixture.goalModeTemplate,
        generatedSample: fixture.generatedSample,
      );

      expect(
        violations,
        contains(
          '[AGENTS_REPOSITORY_GOAL_MODE_DRIFT] AGENTS.md 的完整 Goal Mode 与局部模板不一致。',
        ),
      );
    });

    test('删除局部模板关键 Goal Mode 条款会同时触发完整性与漂移检查', () {
      final _AgentsContractFixture fixture = _createContractFixture();
      final String changedPartial = fixture.goalModeTemplate.replaceFirst(
        '每轮只执行一个任务',
        '每轮执行当前任务',
      );

      final List<String> violations = validateAgentsRepositoryContract(
        rootGuide: fixture.rootGuide,
        baseTemplate: fixture.baseTemplate,
        goalModeTemplate: changedPartial,
        generatedSample: fixture.generatedSample,
      );

      expect(
        violations.map((String violation) => violation.split(' ').first),
        containsAll(<String>{
          '[AGENTS_OUTPUT_GOAL_RULE]',
          '[AGENTS_REPOSITORY_GOAL_MODE_DRIFT]',
          '[AGENTS_REPOSITORY_SAMPLE_GOAL_MODE]',
          '[AGENTS_REPOSITORY_SAMPLE_STALE]',
        }),
      );
    });

    test('基础模板遗漏参考尺寸规则会触发屏幕契约检查', () {
      final _AgentsContractFixture fixture = _createContractFixture();
      final String changedBase = fixture.baseTemplate.replaceFirst(
        '唯一参考设计尺寸为 `375 x 812`',
        '默认参考设计尺寸由项目自行说明',
      );

      final List<String> violations = validateAgentsRepositoryContract(
        rootGuide: fixture.rootGuide,
        baseTemplate: changedBase,
        goalModeTemplate: fixture.goalModeTemplate,
        generatedSample: fixture.generatedSample,
      );

      expect(
        violations.map((String violation) => violation.split(' ').first),
        containsAll(<String>{
          '[AGENTS_OUTPUT_SCREEN_RULE]',
          '[AGENTS_REPOSITORY_SAMPLE_STALE]',
        }),
      );
    });

    test('临时样例遗漏 Insets 规则会触发样例与屏幕漂移检查', () {
      final _AgentsContractFixture fixture = _createContractFixture();
      final String changedSample = fixture.generatedSample.replaceFirst(
        '键盘 `viewInsets` 使用平台实测逻辑值',
        '键盘区域按页面自行处理',
      );

      final List<String> violations = validateAgentsRepositoryContract(
        rootGuide: fixture.rootGuide,
        baseTemplate: fixture.baseTemplate,
        goalModeTemplate: fixture.goalModeTemplate,
        generatedSample: changedSample,
      );

      expect(
        violations.map((String violation) => violation.split(' ').first),
        containsAll(<String>{
          '[AGENTS_OUTPUT_SCREEN_RULE]',
          '[AGENTS_REPOSITORY_SAMPLE_STALE]',
        }),
      );
    });
  });
}

Directory _createTemporaryProject({bool includeRootGuide = false}) {
  final Directory projectRoot = Directory.systemTemp.createTempSync(
    'flutter-template-agents-',
  );
  addTearDown(() {
    if (projectRoot.existsSync()) {
      projectRoot.deleteSync(recursive: true);
    }
  });
  for (final String relativePath in <String>[
    agentsBaseTemplatePath,
    agentsGoalModeTemplatePath,
    if (includeRootGuide) agentsOutputPath,
  ]) {
    final File source = File(relativePath);
    final File target = File(_pathIn(projectRoot, relativePath));
    target.createSync(recursive: true);
    target.writeAsBytesSync(source.readAsBytesSync(), flush: true);
  }
  return projectRoot;
}

_AgentsContractFixture _createContractFixture() {
  final Directory repositoryRoot = _createTemporaryProject(
    includeRootGuide: true,
  );
  final Directory sampleRoot = _createTemporaryProject();
  expect(
    generateAgentsGuide(projectRoot: sampleRoot),
    AgentsGenerationStatus.created,
  );
  return _AgentsContractFixture(
    rootGuide: _readFixture(repositoryRoot, agentsOutputPath),
    baseTemplate: _readFixture(repositoryRoot, agentsBaseTemplatePath),
    goalModeTemplate: _readFixture(repositoryRoot, agentsGoalModeTemplatePath),
    generatedSample: _readFixture(sampleRoot, agentsOutputPath),
  );
}

String _readFixture(Directory projectRoot, String relativePath) {
  return File(
    _pathIn(projectRoot, relativePath),
  ).readAsStringSync(encoding: utf8);
}

_ProjectSnapshot _snapshotProject(Directory projectRoot) {
  final List<FileSystemEntity> entities = projectRoot.listSync(
    recursive: true,
    followLinks: false,
  )..sort((FileSystemEntity left, FileSystemEntity right) {
    return left.path.compareTo(right.path);
  });
  final Map<String, _SnapshotEntry> entries = <String, _SnapshotEntry>{};
  for (final FileSystemEntity entity in entities) {
    final String relativePath = entity.path
        .substring(projectRoot.path.length + 1)
        .replaceAll(Platform.pathSeparator, '/');
    final FileSystemEntityType type = FileSystemEntity.typeSync(
      entity.path,
      followLinks: false,
    );
    entries[relativePath] = _SnapshotEntry(
      type: type,
      modified: entity.statSync().modified,
      bytes:
          type == FileSystemEntityType.file
              ? File(entity.path).readAsBytesSync()
              : null,
    );
  }
  return _ProjectSnapshot(entries);
}

void _expectProjectUnchanged(Directory projectRoot, _ProjectSnapshot before) {
  final _ProjectSnapshot after = _snapshotProject(projectRoot);
  expect(after.entries.keys, orderedEquals(before.entries.keys));
  for (final String path in before.entries.keys) {
    final _SnapshotEntry beforeEntry = before.entries[path]!;
    final _SnapshotEntry afterEntry = after.entries[path]!;
    expect(afterEntry.type, beforeEntry.type, reason: path);
    expect(afterEntry.modified, beforeEntry.modified, reason: path);
    if (beforeEntry.bytes != null) {
      expect(afterEntry.bytes, orderedEquals(beforeEntry.bytes!), reason: path);
    }
  }
}

String _pathIn(Directory projectRoot, String relativePath) {
  return '${projectRoot.path}${Platform.pathSeparator}'
      '${relativePath.replaceAll('/', Platform.pathSeparator)}';
}

final class _AgentsContractFixture {
  const _AgentsContractFixture({
    required this.rootGuide,
    required this.baseTemplate,
    required this.goalModeTemplate,
    required this.generatedSample,
  });

  final String rootGuide;
  final String baseTemplate;
  final String goalModeTemplate;
  final String generatedSample;
}

final class _ProjectSnapshot {
  const _ProjectSnapshot(this.entries);

  final Map<String, _SnapshotEntry> entries;
}

final class _SnapshotEntry {
  const _SnapshotEntry({
    required this.type,
    required this.modified,
    required this.bytes,
  });

  final FileSystemEntityType type;
  final DateTime modified;
  final List<int>? bytes;
}
