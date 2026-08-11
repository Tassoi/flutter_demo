import 'dart:io';

const String _operationsGuidePath = 'docs/phase-2-operations.md';
const String _qualityWorkflowPath = '.github/workflows/quality.yml';

const Set<String> _requiredDocumentationPaths = <String>{
  'README.md',
  'docs/agents-generation.md',
  'docs/authentication.md',
  'docs/branding.md',
  'docs/dependency-upgrades.md',
  'docs/internationalization.md',
  'docs/mobile-screen-adaptation.md',
  'docs/phase-2-operations.md',
  'docs/svg-icon-font.md',
  'docs/troubleshooting.md',
};

const Set<String> _requiredOperationsGuideTargets = <String>{
  'docs/agents-generation.md',
  'docs/authentication.md',
  'docs/branding.md',
  'docs/internationalization.md',
  'docs/mobile-screen-adaptation.md',
  'docs/svg-icon-font.md',
};

const List<String> _qualityCommands = <String>[
  'dart tool/ci/check_generated_files.dart',
  'flutter pub get --enforce-lockfile',
  'dart run tool/generate_localizations.dart --check',
  'dart run tool/generate_icon_font.dart --check',
  'dart run tool/generate_branding.dart --check',
  'flutter test test/tool/generate_agents_test.dart',
  'dart tool/ci/check_documentation.dart',
  'dart tool/ci/check_architecture.dart',
  'dart tool/ci/check_platform_environments.dart',
  'dart format --output=none --set-exit-if-changed .',
  'flutter analyze --fatal-infos --fatal-warnings',
  'flutter test --test-randomize-ordering-seed=20260809',
];

const List<String> _requiredOperationsCommands = <String>[
  'flutter run --flavor dev --dart-define-from-file=config/dev.example.json',
  'flutter build apk --debug --flavor dev',
  'flutter build appbundle --debug --flavor dev',
  'flutter build ios --debug --no-codesign --flavor dev',
];

final RegExp _markdownLinkPattern = RegExp(
  r'''!?\[[^\]]*\]\(\s*(?:<([^>]+)>|([^\s)]+))(?:\s+["'][^)]*["'])?\s*\)''',
);
final RegExp _headingPattern = RegExp(
  r'^(#{1,6})\s+(.+?)\s*#*\s*$',
  multiLine: true,
);
final RegExp _fencedBlockPattern = RegExp(
  r'^```([^\n]*)\n(.*?)^```\s*$',
  multiLine: true,
  dotAll: true,
);
final RegExp _toolCommandTargetPattern = RegExp(
  r'\bdart\s+(?:run\s+)?(tool/[A-Za-z0-9_./-]+\.dart)\b',
);
final RegExp _testCommandTargetPattern = RegExp(
  r'(?:^|\s)(test/[A-Za-z0-9_./-]+)',
);
final RegExp _explicitConfigTargetPattern = RegExp(
  r'''--dart-define-from-file=["']?(config/[A-Za-z0-9_./-]+)''',
);
final RegExp _copiedLocalConfigPattern = RegExp(
  r'\bcp\s+config/[A-Za-z0-9_./-]+\.example\.json\s+'
  r'(config/[A-Za-z0-9_./-]+\.local\.json)\b',
);
final RegExp _personalPathPattern = RegExp(
  r'(?:[A-Za-z]:\\Users\\[^\\\s]+|/Users/[^/\s]+|/home/[^/\s]+|/mnt/[A-Za-z]/Users/[^/\s]+)',
);
final RegExp _privateKeyPattern = RegExp(
  r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
);
final RegExp _exampleUrlPattern = RegExp(r'''https?://[^\s"')>]+''');

/// 校验工程文档的本地链接、命令目标、安全示例和 CI 顺序契约。
///
/// [documents] 的键是使用 `/` 的项目相对 Markdown 路径，值是对应正文；
/// [projectPaths] 同时包含当前项目中允许被文档引用的普通文件和目录。
/// [qualityWorkflow] 是 Quality workflow 的原文，用于证明 README、阶段二操作指南与
/// 自动化执行的命令和顺序一致。
///
/// 检查只分析调用方提供的内存数据，不访问网络或文件系统。外部 HTTP(S) 链接仅被视为
/// 来源引用，不在 CI 中探测可用性；本地链接、锚点以及 Bash 命令中的 `tool/`、`test/`
/// 和显式 `config/` 输入必须真实存在。返回值经过排序，且不会回显代码块正文、URL 查询或
/// 可能包含凭据的值。
List<String> validateDocumentation({
  required Map<String, String> documents,
  required Set<String> projectPaths,
  required String qualityWorkflow,
}) {
  final normalizedDocuments = <String, String>{
    for (final entry in documents.entries)
      _normalizePath(entry.key): entry.value,
  };
  final normalizedProjectPaths = <String>{
    for (final path in projectPaths) _normalizePath(path),
  };
  final violations = <String>[];

  for (final requiredPath in _requiredDocumentationPaths) {
    if (!normalizedDocuments.containsKey(requiredPath)) {
      violations.add('[DOC_REQUIRED_GUIDE] 缺少阶段二工程文档：$requiredPath。');
    }
  }

  final resolvedTargetsByDocument = <String, Set<String>>{};
  final sortedDocumentPaths = normalizedDocuments.keys.toList()..sort();
  for (final documentPath in sortedDocumentPaths) {
    final content = normalizedDocuments[documentPath]!;
    resolvedTargetsByDocument[documentPath] = _validateLinks(
      documentPath: documentPath,
      content: content,
      documents: normalizedDocuments,
      projectPaths: normalizedProjectPaths,
      violations: violations,
    );
    _validateCommandTargets(
      documentPath: documentPath,
      content: content,
      projectPaths: normalizedProjectPaths,
      violations: violations,
    );
    _validateSafeExamples(
      documentPath: documentPath,
      content: content,
      violations: violations,
    );
  }

  final operationsTargets =
      resolvedTargetsByDocument[_operationsGuidePath] ?? const <String>{};
  for (final requiredTarget in _requiredOperationsGuideTargets) {
    if (!operationsTargets.contains(requiredTarget)) {
      violations.add(
        '[DOC_PHASE2_GUIDE_LINK] $_operationsGuidePath 必须链接到 $requiredTarget。',
      );
    }
  }

  final readme = normalizedDocuments['README.md'];
  final operations = normalizedDocuments[_operationsGuidePath];
  if (readme != null) {
    _validateOrderedCommands(
      ownerPath: 'README.md',
      content: readme,
      violations: violations,
    );
  }
  if (operations != null) {
    _validateOrderedCommands(
      ownerPath: _operationsGuidePath,
      content: operations,
      violations: violations,
    );
    for (final command in _requiredOperationsCommands) {
      if (!operations.contains(command)) {
        violations.add(
          '[DOC_PHASE2_COMMAND] $_operationsGuidePath 缺少当前运行或平台命令：$command。',
        );
      }
    }
  }
  _validateOrderedCommands(
    ownerPath: _qualityWorkflowPath,
    content: qualityWorkflow,
    violations: violations,
  );

  violations.sort();
  return violations;
}

/// 从项目根目录执行严格只读的文档契约检查。
///
/// 可选 `--root <path>` 只改变读取根目录，便于 CI 和临时项目测试。CLI 排除 `.git`、
/// 构建缓存、IDE 状态及 `goal-*` 审计目录，避免本地临时产物让不存在的文档目标误通过。
/// 参数错误返回 64；缺失、读取失败或契约漂移返回 1；成功返回 0。
void main(List<String> arguments) {
  late final Directory projectRoot;
  try {
    projectRoot = _resolveProjectRoot(arguments);
  } on FormatException catch (error) {
    stderr.writeln('文档契约检查参数错误：${error.message}');
    stderr.writeln('用法：dart tool/ci/check_documentation.dart [--root <path>]');
    exitCode = 64;
    return;
  }

  if (!_isDirectory(projectRoot)) {
    stderr.writeln('文档契约检查失败：项目根目录不存在或不是普通目录。');
    exitCode = 1;
    return;
  }

  try {
    final projectPaths = _readStableProjectPaths(projectRoot);
    final documents = _readDocumentationFiles(
      projectRoot: projectRoot,
      projectPaths: projectPaths,
    );
    final workflow = File(
      '${projectRoot.path}${Platform.pathSeparator}${_platformPath(_qualityWorkflowPath)}',
    );
    if (!_isRegularFile(workflow)) {
      stderr.writeln('文档契约检查失败：缺少 $_qualityWorkflowPath。');
      exitCode = 1;
      return;
    }

    final violations = validateDocumentation(
      documents: documents,
      projectPaths: projectPaths,
      qualityWorkflow: workflow.readAsStringSync(),
    );
    if (violations.isNotEmpty) {
      stderr.writeln('文档契约检查失败，共 ${violations.length} 项：');
      for (final violation in violations) {
        stderr.writeln('- $violation');
      }
      exitCode = 1;
      return;
    }

    stdout.writeln('文档契约检查通过，共检查 ${documents.length} 份工程文档。');
  } on FileSystemException catch (error) {
    stderr.writeln('文档契约检查失败：无法安全读取项目文件（${error.message}）。');
    exitCode = 1;
  }
}

Set<String> _validateLinks({
  required String documentPath,
  required String content,
  required Map<String, String> documents,
  required Set<String> projectPaths,
  required List<String> violations,
}) {
  final resolvedTargets = <String>{};
  for (final match in _markdownLinkPattern.allMatches(content)) {
    final rawTarget = match.group(1) ?? match.group(2)!;
    final uri = Uri.tryParse(rawTarget);
    if (uri != null && uri.scheme.isNotEmpty) {
      if (uri.scheme != 'http' &&
          uri.scheme != 'https' &&
          uri.scheme != 'mailto') {
        violations.add(
          '[DOC_LINK_SCHEME] $documentPath:${_lineNumber(content, match.start)} '
          '不支持本地文档链接协议。',
        );
      }
      continue;
    }

    final fragmentIndex = rawTarget.indexOf('#');
    final rawPath =
        fragmentIndex == -1 ? rawTarget : rawTarget.substring(0, fragmentIndex);
    final rawFragment =
        fragmentIndex == -1 ? '' : rawTarget.substring(fragmentIndex + 1);
    late final String decodedPath;
    late final String decodedFragment;
    try {
      decodedPath = _decodeLinkComponent(rawPath);
      decodedFragment = _decodeLinkComponent(rawFragment);
    } on ArgumentError {
      violations.add(
        '[DOC_LINK_ENCODING] $documentPath:${_lineNumber(content, match.start)} '
        '本地链接包含无效的百分号编码。',
      );
      continue;
    }

    final resolvedPath = _resolveProjectPath(
      sourcePath: documentPath,
      targetPath: decodedPath,
    );
    if (resolvedPath == null) {
      violations.add(
        '[DOC_LINK_OUTSIDE_ROOT] $documentPath:${_lineNumber(content, match.start)} '
        '本地链接越过项目根目录。',
      );
      continue;
    }
    if (!projectPaths.contains(resolvedPath)) {
      violations.add(
        '[DOC_LINK_MISSING] $documentPath:${_lineNumber(content, match.start)} '
        '本地链接目标不存在：$resolvedPath。',
      );
      continue;
    }
    resolvedTargets.add(resolvedPath);

    if (decodedFragment.isEmpty) {
      continue;
    }
    final targetContent = documents[resolvedPath];
    if (targetContent == null ||
        !_headingAnchors(targetContent).contains(decodedFragment)) {
      violations.add(
        '[DOC_LINK_ANCHOR] $documentPath:${_lineNumber(content, match.start)} '
        '本地链接锚点不存在：$resolvedPath#$decodedFragment。',
      );
    }
  }
  return resolvedTargets;
}

void _validateCommandTargets({
  required String documentPath,
  required String content,
  required Set<String> projectPaths,
  required List<String> violations,
}) {
  for (final block in _fencedBlockPattern.allMatches(content)) {
    final language = block.group(1)!.trim().toLowerCase();
    if (language != 'bash' && language != 'sh' && language != 'shell') {
      continue;
    }
    final body = block.group(2)!;
    final logicalLines = _logicalShellLines(body);
    final copiedLocalConfigs = <String>{
      for (final match in _copiedLocalConfigPattern.allMatches(body))
        match.group(1)!,
    };
    for (final logicalLine in logicalLines) {
      final command = logicalLine.text.trim();
      if (command.isEmpty || command.startsWith('#')) {
        continue;
      }
      final targets = <String>{};
      for (final match in _toolCommandTargetPattern.allMatches(command)) {
        targets.add(match.group(1)!);
      }
      if (command.contains(RegExp(r'\bflutter\s+test\b'))) {
        for (final match in _testCommandTargetPattern.allMatches(command)) {
          targets.add(match.group(1)!);
        }
      }
      for (final match in _explicitConfigTargetPattern.allMatches(command)) {
        targets.add(match.group(1)!);
      }

      for (final target in targets) {
        if (!projectPaths.contains(target) &&
            !copiedLocalConfigs.contains(target)) {
          final line = _lineNumber(content, block.start) + logicalLine.line - 1;
          violations.add(
            '[DOC_COMMAND_TARGET_MISSING] $documentPath:$line '
            '命令引用的项目路径不存在：$target。',
          );
        }
      }
    }
  }
}

void _validateSafeExamples({
  required String documentPath,
  required String content,
  required List<String> violations,
}) {
  for (final block in _fencedBlockPattern.allMatches(content)) {
    final body = block.group(2)!;
    final line = _lineNumber(content, block.start);
    if (_personalPathPattern.hasMatch(body)) {
      violations.add('[DOC_PERSONAL_PATH] $documentPath:$line 示例不得包含个人主目录路径。');
    }
    if (_privateKeyPattern.hasMatch(body)) {
      violations.add('[DOC_PRIVATE_KEY] $documentPath:$line 示例不得包含私钥材料。');
    }
    for (final match in _exampleUrlPattern.allMatches(body)) {
      final uri = Uri.tryParse(match.group(0)!);
      final host = uri?.host.toLowerCase() ?? '';
      if (host != 'localhost' &&
          host != '127.0.0.1' &&
          host != '::1' &&
          host != 'example.invalid' &&
          !host.endsWith('.example.invalid') &&
          !host.endsWith('.invalid')) {
        violations.add(
          '[DOC_UNSAFE_EXAMPLE_URL] $documentPath:$line '
          '代码示例中的服务地址必须使用 `.invalid` 或本机占位主机。',
        );
      }
    }
  }
}

void _validateOrderedCommands({
  required String ownerPath,
  required String content,
  required List<String> violations,
}) {
  var searchStart = 0;
  for (final command in _qualityCommands) {
    final index = content.indexOf(command, searchStart);
    if (index == -1) {
      violations.add(
        '[DOC_QUALITY_COMMAND_DRIFT] $ownerPath 缺少或打乱质量命令：$command。',
      );
      continue;
    }
    searchStart = index + command.length;
  }
}

Set<String> _headingAnchors(String content) {
  final anchors = <String>{};
  final counts = <String, int>{};
  for (final match in _headingPattern.allMatches(content)) {
    final base = _headingSlug(match.group(2)!);
    if (base.isEmpty) {
      continue;
    }
    final count = counts[base] ?? 0;
    counts[base] = count + 1;
    anchors.add(count == 0 ? base : '$base-$count');
  }
  return anchors;
}

String _headingSlug(String heading) {
  var value =
      heading
          .replaceAllMapped(
            RegExp(r'!\[([^\]]*)\]\([^)]*\)'),
            (match) => match.group(1)!,
          )
          .replaceAllMapped(
            RegExp(r'\[([^\]]+)\]\([^)]*\)'),
            (match) => match.group(1)!,
          )
          .replaceAll('`', '')
          .toLowerCase();
  final buffer = StringBuffer();
  var pendingHyphen = false;
  for (final rune in value.runes) {
    final isAsciiLetter = rune >= 0x61 && rune <= 0x7A;
    final isDigit = rune >= 0x30 && rune <= 0x39;
    final isCjk = rune >= 0x3400 && rune <= 0x9FFF;
    if (isAsciiLetter || isDigit || isCjk || rune == 0x5F) {
      if (pendingHyphen && buffer.isNotEmpty) {
        buffer.write('-');
      }
      pendingHyphen = false;
      buffer.writeCharCode(rune);
    } else if (rune == 0x2D || rune == 0x20 || rune == 0x09) {
      pendingHyphen = buffer.isNotEmpty;
    }
  }
  value = buffer.toString();
  return value;
}

List<_LogicalShellLine> _logicalShellLines(String body) {
  final lines = body.split('\n');
  final result = <_LogicalShellLine>[];
  var buffer = StringBuffer();
  var startLine = 1;
  for (var index = 0; index < lines.length; index += 1) {
    final line = lines[index];
    if (buffer.isEmpty) {
      startLine = index + 1;
    }
    final trimmedRight = line.replaceFirst(RegExp(r'\s+$'), '');
    final continues = trimmedRight.endsWith('\\');
    buffer.write(
      continues ? trimmedRight.substring(0, trimmedRight.length - 1) : line,
    );
    if (continues) {
      buffer.write(' ');
      continue;
    }
    result.add(_LogicalShellLine(text: buffer.toString(), line: startLine));
    buffer = StringBuffer();
  }
  if (buffer.isNotEmpty) {
    result.add(_LogicalShellLine(text: buffer.toString(), line: startLine));
  }
  return result;
}

String? _resolveProjectPath({
  required String sourcePath,
  required String targetPath,
}) {
  final normalizedTarget = _normalizePath(targetPath);
  if (normalizedTarget.isEmpty) {
    return sourcePath;
  }
  if (normalizedTarget.startsWith('/')) {
    return null;
  }
  final segments = sourcePath.split('/')..removeLast();
  for (final segment in normalizedTarget.split('/')) {
    if (segment.isEmpty || segment == '.') {
      continue;
    }
    if (segment == '..') {
      if (segments.isEmpty) {
        return null;
      }
      segments.removeLast();
      continue;
    }
    segments.add(segment);
  }
  return segments.join('/');
}

String _decodeLinkComponent(String value) =>
    value.contains('%') ? Uri.decodeComponent(value) : value;

Set<String> _readStableProjectPaths(Directory root) {
  final paths = <String>{'.'};
  void visit(Directory directory, String relativeDirectory) {
    final entities = directory.listSync(followLinks: false)
      ..sort((left, right) => left.path.compareTo(right.path));
    for (final entity in entities) {
      final name =
          entity.uri.pathSegments.where((segment) => segment.isNotEmpty).last;
      final relativePath =
          relativeDirectory.isEmpty ? name : '$relativeDirectory/$name';
      final type = FileSystemEntity.typeSync(entity.path, followLinks: false);
      if (type == FileSystemEntityType.directory) {
        if (_isExcludedDirectory(relativePath)) {
          continue;
        }
        paths.add(relativePath);
        visit(Directory(entity.path), relativePath);
      } else if (type == FileSystemEntityType.file) {
        paths.add(relativePath);
      }
    }
  }

  visit(root, '');
  return paths;
}

Map<String, String> _readDocumentationFiles({
  required Directory projectRoot,
  required Set<String> projectPaths,
}) {
  final documentPaths =
      projectPaths.where(_isDocumentationPath).toList()..sort();
  return <String, String>{
    for (final path in documentPaths)
      path:
          File(
            '${projectRoot.path}${Platform.pathSeparator}${_platformPath(path)}',
          ).readAsStringSync(),
  };
}

bool _isDocumentationPath(String path) {
  if (path == 'README.md') {
    return true;
  }
  if (path.startsWith('docs/') && path.endsWith('.md')) {
    return true;
  }
  if (path == 'config/README.md') {
    return true;
  }
  if ((path.startsWith('lib/') || path.startsWith('test/')) &&
      path.endsWith('/README.md')) {
    return true;
  }
  return path.startsWith('assets/') && path.endsWith('/LICENSE.md');
}

bool _isExcludedDirectory(String path) {
  const excluded = <String>{
    '.dart_tool',
    '.git',
    '.idea',
    'build',
    'coverage',
    'android/.gradle',
    'android/app/.cxx',
    'ios/Pods',
  };
  if (excluded.contains(path)) {
    return true;
  }
  return !path.contains('/') && RegExp(r'^goal-\d+$').hasMatch(path);
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

String _platformPath(String path) =>
    path.replaceAll('/', Platform.pathSeparator);

String _normalizePath(String path) => path.replaceAll('\\', '/');

bool _isRegularFile(File file) =>
    FileSystemEntity.typeSync(file.path, followLinks: false) ==
    FileSystemEntityType.file;

bool _isDirectory(Directory directory) =>
    FileSystemEntity.typeSync(directory.path, followLinks: false) ==
    FileSystemEntityType.directory;

int _lineNumber(String source, int offset) =>
    RegExp(r'\n').allMatches(source.substring(0, offset)).length + 1;

final class _LogicalShellLine {
  const _LogicalShellLine({required this.text, required this.line});

  final String text;
  final int line;
}
