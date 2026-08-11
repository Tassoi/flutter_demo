import 'dart:convert';
import 'dart:io';

/// 基础 Agent 指南模板在项目内的固定相对路径。
const String agentsBaseTemplatePath = 'tool/templates/AGENTS.base.md';

/// 完整 Goal Mode 局部模板在项目内的固定相对路径。
const String agentsGoalModeTemplatePath =
    'tool/templates/partials/goal_mode.md';

/// 初始化生成的唯一目标路径。
const String agentsOutputPath = 'AGENTS.md';

/// 基础模板中用于插入完整 Goal Mode 正文的唯一占位符。
const String agentsGoalModePlaceholder = '{{GOAL_MODE}}';

const String _goalModeHeading = '## Goal Mode 工作流';

const List<String> _requiredDocumentSnippets = <String>[
  '# Flutter 项目 Agent 指南',
  '## 项目定位与范围',
  '## 目录与依赖边界',
  '## 已启用能力与边界',
  '## 常用命令',
  '## 注释与文档规范',
  '## 测试规范',
  '## 移动端屏幕适配',
  '## 密钥与安全',
  '## Git 与外部操作',
  '## Goal Mode 工作流',
  '初始维护 `en`、`zh`',
  'OTF 与 Dart `IconData`',
  '认证通过项目自有会话',
  '三个环境共用一套 Android/iOS',
  '生成到项目中的代码注释使用中文',
  '不创建 commit、不暂存、不推送、不发布',
  'dart run tool/generate_agents.dart --check',
  'dart tool/ci/check_documentation.dart',
];

const List<String> _requiredScreenRuleSnippets = <String>[
  '唯一参考设计尺寸为 `375 x 812`',
  '`flutter_screenutil` 只能由应用根部和项目自有适配层使用',
  '项目 `du`/`dsp` 表达设计稿尺寸',
  '宽、高、间距、圆角和图标统一按宽度比例换算',
  '不得全局使用 `TextScaler.noScaling`',
  '键盘 `viewInsets` 使用平台实测逻辑值',
  '正文和主要操作必须可以滚动到达',
  '`contain`/`cover` 不得用于表单',
  '`320x568`',
  '`360x800`',
  '`375x812`',
  '`390x844`',
  '`430x932`',
  '`800x360`',
  'FlutterView 和 MediaQuery 注入一致的真实平台值',
];

const List<String> _requiredGoalModeRuleSnippets = <String>[
  '只有用户明确输入 `/goal`',
  '`input.md` 必须逐字保存用户触发 Goal 的原始输入',
  'Goal 初始化完成前不得修改业务源码、工程配置或依赖',
  '只输出 `GOAL_INIT_DONE`',
  '完整读取当前 Goal 的 `input.md`、`plan.md` 和 `tasks.md`',
  '只选择 `tasks.md` 中第一个未完成任务',
  '每轮只执行一个任务',
  '每完成三个实现任务',
  'Goal Mode 默认按无人值守方式推进',
  '### 阻塞与无人值守约束',
  'Goal Mode 中禁止：',
  '### Goal 完成',
  '所有任务完成后必须执行最终全面 Review',
];

const List<String> _requiredRepositoryRootSnippets = <String>[
  '35. **移动端屏幕适配**',
  '使用 `flutter_screenutil` 和项目自有设计单位实现宽度等比缩放',
  '系统安全区、键盘 Insets 和无障碍文字缩放必须使用平台真实值',
  '短屏内容必须可以滚动',
  '不得通过独立高度比例拉伸 UI',
  '36. **基础 Agent 规范生成**',
  '本文件完整的 Goal Mode 工作流',
  '不得静默覆盖调用方已有或已修改的 `AGENTS.md`',
  '屏幕适配至少覆盖 `320`、`360`、`375`、`390`、`430`',
  '测试只能写入临时目录',
];

final RegExp _hanCharacterPattern = RegExp(r'[\u3400-\u9fff]');
final RegExp _windowsAbsolutePathPattern = RegExp(r'[A-Za-z]:[\\/]');
final RegExp _unixPersonalPathPattern = RegExp(
  r'/(?:Users|home|mnt|private/var/folders)/',
  caseSensitive: false,
);
final RegExp _uncPathPattern = RegExp(r'\\\\[^\\\s]+\\');
final RegExp _urlPattern = RegExp(r'https?://', caseSensitive: false);
final RegExp _assignedSecretPattern = RegExp(
  r'''\b(?:api[_ -]?key|token|password|secret)\s*[:=]\s*["']?[A-Za-z0-9_./+=-]{8,}''',
  caseSensitive: false,
);

/// Agent 指南初始化、模板校验或安全写入失败时使用的稳定错误。
///
/// [violations] 只包含规则编号、固定相对路径和安全中文说明，不回显模板正文、用户已有
/// `AGENTS.md` 内容或底层文件系统路径。CLI 会逐项输出并返回非零退出码。
final class AgentsGenerationException implements Exception {
  /// 创建一个至少包含一项违规信息的生成错误。
  AgentsGenerationException(Iterable<String> violations)
    : violations = List<String>.unmodifiable(violations) {
    if (this.violations.isEmpty) {
      throw ArgumentError.value(violations, 'violations', '不得为空。');
    }
  }

  /// 已按稳定顺序记录的违规信息。
  final List<String> violations;

  @override
  String toString() => violations.join('\n');
}

/// 一次 Agent 指南初始化的可观察结果。
enum AgentsGenerationStatus {
  /// 目标原本不存在，本轮已经创建并回读验证。
  created,

  /// 目标已存在且字节完全一致，本轮没有执行写入。
  unchanged,
}

/// 把基础模板与完整 Goal Mode 局部模板确定性拼接为最终指南。
///
/// 两份输入都必须是已解码的 UTF-8 文本、仅使用 LF 且以换行结尾。基础模板必须把
/// [agentsGoalModePlaceholder] 作为单独一行且只出现一次；局部模板必须包含完整 Goal Mode
/// 正文。函数不读取时间、环境变量、用户名或文件系统，因此相同输入始终返回相同字符串。
/// 任一结构、安全或内容契约不满足时抛出 [AgentsGenerationException]。
String buildAgentsDocument({
  required String baseTemplate,
  required String goalModeTemplate,
}) {
  final List<String> violations = <String>[
    ..._validateTemplateText(
      source: baseTemplate,
      relativePath: agentsBaseTemplatePath,
    ),
    ..._validateTemplateText(
      source: goalModeTemplate,
      relativePath: agentsGoalModeTemplatePath,
    ),
  ];

  final String placeholderLine = '$agentsGoalModePlaceholder\n';
  final int placeholderIndex = baseTemplate.indexOf(placeholderLine);
  if (placeholderIndex < 0 ||
      placeholderIndex != baseTemplate.lastIndexOf(placeholderLine) ||
      baseTemplate.contains(agentsGoalModePlaceholder) &&
          _countOccurrences(baseTemplate, agentsGoalModePlaceholder) != 1) {
    violations.add(
      '[AGENTS_TEMPLATE_MARKER] $agentsBaseTemplatePath 必须且只能包含一行 '
      '$agentsGoalModePlaceholder。',
    );
  }
  if (goalModeTemplate.contains(agentsGoalModePlaceholder)) {
    violations.add(
      '[AGENTS_TEMPLATE_MARKER] $agentsGoalModeTemplatePath 不得包含基础模板占位符。',
    );
  }
  if (!goalModeTemplate.startsWith('## Goal Mode 工作流\n')) {
    violations.add(
      '[AGENTS_GOAL_MODE_ROOT] $agentsGoalModeTemplatePath 必须从根级 Goal Mode 标题开始。',
    );
  }
  if (violations.isNotEmpty) {
    violations.sort();
    throw AgentsGenerationException(violations);
  }

  final String document = baseTemplate.replaceFirst(
    placeholderLine,
    goalModeTemplate,
  );
  final List<String> outputViolations = _validateGeneratedDocument(document);
  if (outputViolations.isNotEmpty) {
    throw AgentsGenerationException(outputViolations);
  }
  return document;
}

/// 校验模板仓库根规范、两份模板和临时样例输出之间的同步契约。
///
/// [rootGuide] 是用户维护的仓库根规范，[baseTemplate] 与 [goalModeTemplate] 是生成器的
/// 两份人工输入，[generatedSample] 必须来自临时项目中的一次真实初始化。函数只处理调用方
/// 已读取的字符串，不访问文件系统，也不会尝试修复任何漂移。
///
/// 根规范中的 Goal Mode 必须从唯一根级标题一直到文件末尾，并与局部模板逐字一致。临时样例
/// 必须逐字等于当前两份模板的确定性拼接，同时满足完整屏幕适配、Goal Mode、安全和编码规则。
/// 返回值使用稳定规则编号并按字典序排列；空列表表示四方契约一致。
List<String> validateAgentsRepositoryContract({
  required String rootGuide,
  required String baseTemplate,
  required String goalModeTemplate,
  required String generatedSample,
}) {
  final List<String> violations = <String>[];

  if (rootGuide.isEmpty ||
      rootGuide.startsWith('\uFEFF') ||
      rootGuide.contains('\r') ||
      rootGuide.contains('\u0000') ||
      !rootGuide.endsWith('\n')) {
    violations.add(
      '[AGENTS_REPOSITORY_ROOT_ENCODING] AGENTS.md 必须是无 BOM/NUL 的 UTF-8、仅使用 LF 且以换行结尾。',
    );
  }
  for (final String snippet in _requiredRepositoryRootSnippets) {
    if (!rootGuide.contains(snippet)) {
      violations.add(
        '[AGENTS_REPOSITORY_ROOT_REQUIRED] AGENTS.md 缺少阶段二 Agent 契约：$snippet。',
      );
    }
  }

  final String headingLine = '$_goalModeHeading\n';
  final int rootHeadingIndex = rootGuide.indexOf(headingLine);
  if (rootHeadingIndex < 0 ||
      rootHeadingIndex != rootGuide.lastIndexOf(headingLine)) {
    violations.add(
      '[AGENTS_REPOSITORY_ROOT_GOAL_MODE] AGENTS.md 必须且只能包含一份根级 Goal Mode，并以其作为末尾章节。',
    );
  } else if (rootGuide.substring(rootHeadingIndex) != goalModeTemplate) {
    violations.add(
      '[AGENTS_REPOSITORY_GOAL_MODE_DRIFT] AGENTS.md 的完整 Goal Mode 与局部模板不一致。',
    );
  }

  final String placeholderLine = '$agentsGoalModePlaceholder\n';
  String? expectedDocument;
  if (_countOccurrences(baseTemplate, agentsGoalModePlaceholder) == 1 &&
      baseTemplate.contains(placeholderLine) &&
      !goalModeTemplate.contains(agentsGoalModePlaceholder)) {
    // 即使完整性校验随后失败，结构仍唯一时也能比较原始拼接，避免遗漏模板与样例的独立漂移。
    expectedDocument = baseTemplate.replaceFirst(
      placeholderLine,
      goalModeTemplate,
    );
  }
  try {
    expectedDocument = buildAgentsDocument(
      baseTemplate: baseTemplate,
      goalModeTemplate: goalModeTemplate,
    );
  } on AgentsGenerationException catch (error) {
    violations.addAll(error.violations);
  }

  violations.addAll(_validateGeneratedDocument(generatedSample));
  if (expectedDocument != null &&
      !_bytesEqual(
        utf8.encode(expectedDocument),
        utf8.encode(generatedSample),
      )) {
    violations.add('[AGENTS_REPOSITORY_SAMPLE_STALE] 临时样例输出与当前模板拼接结果不一致。');
  }
  if (_countOccurrences(generatedSample, _goalModeHeading) != 1 ||
      !generatedSample.endsWith(goalModeTemplate)) {
    violations.add(
      '[AGENTS_REPOSITORY_SAMPLE_GOAL_MODE] 临时样例没有逐字包含完整 Goal Mode 局部模板。',
    );
  }

  final List<String> stableViolations = violations.toSet().toList()..sort();
  return stableViolations;
}

/// 从固定模板读取内容，并在目标不存在时初始化根 `AGENTS.md`。
///
/// [projectRoot] 必须是普通目录；模板路径、局部模板和目标路径均不可为符号链接。目标已存在
/// 且字节一致时返回 [AgentsGenerationStatus.unchanged] 并保持 mtime；目标内容不同、不可读
/// 或不是普通文件时立即失败，绝不覆盖。目标不存在时先以独占方式创建，再写入并回读验证；
/// 失败会删除本轮创建的目标。[beforeWrite] 只用于临时目录测试注入确定的写入故障，生产 CLI
/// 必须省略。
AgentsGenerationStatus generateAgentsGuide({
  required Directory projectRoot,
  void Function(String relativePath)? beforeWrite,
}) {
  _validateProjectRoot(projectRoot);
  final String baseTemplate = _readUtf8Template(
    projectRoot,
    agentsBaseTemplatePath,
  );
  final String goalModeTemplate = _readUtf8Template(
    projectRoot,
    agentsGoalModeTemplatePath,
  );
  final String document = buildAgentsDocument(
    baseTemplate: baseTemplate,
    goalModeTemplate: goalModeTemplate,
  );
  final List<int> expectedBytes = utf8.encode(document);
  final File target = File(_pathIn(projectRoot, agentsOutputPath));

  final AgentsGenerationStatus? existing = _inspectExistingTargetForGeneration(
    target,
    expectedBytes,
  );
  if (existing != null) {
    return existing;
  }

  bool createdTarget = false;
  try {
    try {
      // 独占创建把并发出现的用户文件也纳入非覆盖边界，避免“先检查、后写入”的竞态。
      target.createSync(exclusive: true);
      createdTarget = true;
    } on FileSystemException {
      final AgentsGenerationStatus? racedTarget =
          _inspectExistingTargetForGeneration(target, expectedBytes);
      if (racedTarget != null) {
        return racedTarget;
      }
      rethrow;
    }

    beforeWrite?.call(agentsOutputPath);
    target.writeAsBytesSync(
      expectedBytes,
      mode: FileMode.writeOnly,
      flush: true,
    );
    if (!_bytesEqual(target.readAsBytesSync(), expectedBytes)) {
      throw const FileSystemException('generated file verification failed');
    }
    return AgentsGenerationStatus.created;
  } on AgentsGenerationException {
    rethrow;
  } on Object {
    if (createdTarget) {
      try {
        final FileSystemEntityType type = FileSystemEntity.typeSync(
          target.path,
          followLinks: false,
        );
        if (type == FileSystemEntityType.file) {
          target.deleteSync();
        } else if (type != FileSystemEntityType.notFound) {
          throw const FileSystemException('generated target changed type');
        }
      } on Object {
        throw AgentsGenerationException(const <String>[
          '[AGENTS_WRITE_RECOVERY_FAILED] 初始化写入失败且无法清理本轮创建的 AGENTS.md。',
        ]);
      }
    }
    throw AgentsGenerationException(const <String>[
      '[AGENTS_WRITE_FAILED] 无法安全创建 AGENTS.md；未确认写入任何有效内容。',
    ]);
  }
}

/// 严格只读检查根 `AGENTS.md` 是否与当前固定模板逐字节一致。
///
/// 函数只读取 [projectRoot]、两份模板和固定目标，不创建目录、不修改内容或 mtime，也不自动
/// 修复缺失、过期或非法目标。返回空列表表示目标匹配；缺失、过期、不可读、符号链接和非法
/// 文件类型分别使用稳定规则编号。[readTargetBytes] 仅供系统临时目录测试注入不可读故障，
/// 生产 CLI 必须省略。
List<String> findAgentsGuideDrift({
  required Directory projectRoot,
  List<int> Function(File target)? readTargetBytes,
}) {
  _validateProjectRoot(projectRoot);
  final String baseTemplate = _readUtf8Template(
    projectRoot,
    agentsBaseTemplatePath,
  );
  final String goalModeTemplate = _readUtf8Template(
    projectRoot,
    agentsGoalModeTemplatePath,
  );
  final List<int> expectedBytes = utf8.encode(
    buildAgentsDocument(
      baseTemplate: baseTemplate,
      goalModeTemplate: goalModeTemplate,
    ),
  );
  final File target = File(_pathIn(projectRoot, agentsOutputPath));
  final _AgentsTargetState state = _inspectAgentsTarget(
    target,
    expectedBytes,
    readTargetBytes: readTargetBytes,
  );

  return switch (state) {
    _AgentsTargetState.matching => const <String>[],
    _AgentsTargetState.missing => const <String>[
      '[AGENTS_CHECK_MISSING] AGENTS.md 尚未初始化。',
    ],
    _AgentsTargetState.stale => const <String>[
      '[AGENTS_CHECK_STALE] AGENTS.md 与当前固定模板不同。',
    ],
    _AgentsTargetState.unreadable => const <String>[
      '[AGENTS_CHECK_UNREADABLE] AGENTS.md 无法读取。',
    ],
    _AgentsTargetState.symlink => const <String>[
      '[AGENTS_CHECK_SYMLINK] AGENTS.md 不得是符号链接。',
    ],
    _AgentsTargetState.invalid => const <String>[
      '[AGENTS_CHECK_INVALID] AGENTS.md 必须是普通文件。',
    ],
  };
}

/// 执行基础 Agent 指南初始化或严格只读检查，并返回适合进程和测试断言的退出码。
///
/// CLI 只接受无参数初始化或唯一参数 `--check`，目标固定为当前目录。测试可通过
/// [projectRoot] 注入系统临时目录，但该能力不会暴露成 `--root` 参数。参数错误返回 64，模板、
/// 目标、漂移或写入失败返回 1，成功返回 0。初始化与检查都不提供强制覆盖；[beforeWrite] 和
/// [readTargetBytes] 只用于临时目录故障注入，生产 CLI 必须省略。
int runAgentsGenerator(
  List<String> arguments, {
  Directory? projectRoot,
  StringSink? output,
  StringSink? errorOutput,
  void Function(String relativePath)? beforeWrite,
  List<int> Function(File target)? readTargetBytes,
}) {
  final StringSink stdoutSink = output ?? stdout;
  final StringSink stderrSink = errorOutput ?? stderr;
  final bool checkOnly;
  if (arguments.isEmpty) {
    checkOnly = false;
  } else if (arguments.length == 1 && arguments.single == '--check') {
    checkOnly = true;
  } else {
    stderrSink.writeln('Agent 指南生成参数错误：只支持无参数初始化或单一 --check。');
    stderrSink.writeln('用法：dart run tool/generate_agents.dart [--check]');
    return 64;
  }

  try {
    if (checkOnly) {
      final List<String> violations = findAgentsGuideDrift(
        projectRoot: projectRoot ?? Directory.current,
        readTargetBytes: readTargetBytes,
      );
      if (violations.isNotEmpty) {
        throw AgentsGenerationException(violations);
      }
      stdoutSink.writeln('Agent 指南检查通过：$agentsOutputPath 与模板逐字节一致。');
      return 0;
    }

    final AgentsGenerationStatus result = generateAgentsGuide(
      projectRoot: projectRoot ?? Directory.current,
      beforeWrite: beforeWrite,
    );
    switch (result) {
      case AgentsGenerationStatus.created:
        stdoutSink.writeln('Agent 指南初始化完成：已创建 $agentsOutputPath。');
      case AgentsGenerationStatus.unchanged:
        stdoutSink.writeln('Agent 指南无需更新：现有 $agentsOutputPath 与模板一致。');
    }
    return 0;
  } on AgentsGenerationException catch (error) {
    final String action = checkOnly ? '检查' : '初始化';
    stderrSink.writeln('Agent 指南$action失败，共 ${error.violations.length} 项：');
    for (final String violation in error.violations) {
      stderrSink.writeln('- $violation');
    }
    return 1;
  } on Object {
    final String action = checkOnly ? '检查' : '初始化';
    stderrSink.writeln('Agent 指南$action失败：发生未分类的本地工具错误。');
    return 1;
  }
}

/// 以当前目录为唯一目标执行初始化或只读检查，并把稳定结果映射到进程退出码。
void main(List<String> arguments) {
  exitCode = runAgentsGenerator(arguments);
}

void _validateProjectRoot(Directory projectRoot) {
  final FileSystemEntityType type = FileSystemEntity.typeSync(
    projectRoot.path,
    followLinks: false,
  );
  if (type != FileSystemEntityType.directory) {
    throw AgentsGenerationException(const <String>[
      '[AGENTS_PROJECT_ROOT_INVALID] 项目根必须是已存在的普通目录。',
    ]);
  }
}

String _readUtf8Template(Directory projectRoot, String relativePath) {
  final List<String> segments = relativePath.split('/');
  String currentPath = projectRoot.path;
  for (int index = 0; index < segments.length; index += 1) {
    currentPath = '$currentPath${Platform.pathSeparator}${segments[index]}';
    final FileSystemEntityType type = FileSystemEntity.typeSync(
      currentPath,
      followLinks: false,
    );
    if (type == FileSystemEntityType.link) {
      throw AgentsGenerationException(<String>[
        '[AGENTS_TEMPLATE_SYMLINK] $relativePath 的路径组件不得是符号链接。',
      ]);
    }
    final bool isFile = index == segments.length - 1;
    if (isFile && type == FileSystemEntityType.notFound) {
      throw AgentsGenerationException(<String>[
        '[AGENTS_TEMPLATE_MISSING] 缺少固定模板 $relativePath。',
      ]);
    }
    if (isFile && type != FileSystemEntityType.file) {
      throw AgentsGenerationException(<String>[
        '[AGENTS_TEMPLATE_INVALID] $relativePath 必须是普通文件。',
      ]);
    }
    if (!isFile && type != FileSystemEntityType.directory) {
      throw AgentsGenerationException(<String>[
        '[AGENTS_TEMPLATE_PATH_INVALID] $relativePath 的父路径必须是普通目录。',
      ]);
    }
  }

  try {
    final List<int> bytes = File(currentPath).readAsBytesSync();
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      throw AgentsGenerationException(<String>[
        '[AGENTS_TEMPLATE_BOM] $relativePath 不得包含 UTF-8 BOM。',
      ]);
    }
    return utf8.decode(bytes, allowMalformed: false);
  } on AgentsGenerationException {
    rethrow;
  } on FormatException {
    throw AgentsGenerationException(<String>[
      '[AGENTS_TEMPLATE_UTF8] $relativePath 不是有效 UTF-8。',
    ]);
  } on FileSystemException {
    throw AgentsGenerationException(<String>[
      '[AGENTS_TEMPLATE_UNREADABLE] $relativePath 无法读取。',
    ]);
  }
}

List<String> _validateTemplateText({
  required String source,
  required String relativePath,
}) {
  final List<String> violations = <String>[];
  if (source.isEmpty) {
    violations.add('[AGENTS_TEMPLATE_EMPTY] $relativePath 不得为空。');
  }
  if (source.startsWith('\uFEFF')) {
    violations.add('[AGENTS_TEMPLATE_BOM] $relativePath 不得包含 UTF-8 BOM。');
  }
  if (source.contains('\r')) {
    violations.add('[AGENTS_TEMPLATE_LINE_ENDING] $relativePath 只能使用 LF 换行。');
  }
  if (!source.endsWith('\n')) {
    violations.add('[AGENTS_TEMPLATE_FINAL_NEWLINE] $relativePath 必须以 LF 结尾。');
  }
  if (source.contains('\u0000')) {
    violations.add('[AGENTS_TEMPLATE_NUL] $relativePath 不得包含 NUL 字符。');
  }
  if (!_hanCharacterPattern.hasMatch(source)) {
    violations.add('[AGENTS_TEMPLATE_CHINESE] $relativePath 必须包含中文规范正文。');
  }
  return violations;
}

List<String> _validateGeneratedDocument(String document) {
  final List<String> violations = <String>[];
  if (document.contains('\r') || !document.endsWith('\n')) {
    violations.add('[AGENTS_OUTPUT_ENCODING] 生成结果必须使用 LF 且以换行结尾。');
  }
  if (document.startsWith('\uFEFF') || document.contains('\u0000')) {
    violations.add('[AGENTS_OUTPUT_ENCODING] 生成结果不得包含 BOM 或 NUL。');
  }
  if (document.contains(agentsGoalModePlaceholder) ||
      RegExp(r'\{\{[A-Z0-9_]+\}\}').hasMatch(document)) {
    violations.add('[AGENTS_OUTPUT_MARKER] 生成结果包含未展开的模板占位符。');
  }
  for (final String snippet in _requiredDocumentSnippets) {
    if (!document.contains(snippet)) {
      violations.add('[AGENTS_OUTPUT_REQUIRED] 生成结果缺少必需规范：$snippet。');
    }
  }
  for (final String snippet in _requiredScreenRuleSnippets) {
    if (!document.contains(snippet)) {
      violations.add('[AGENTS_OUTPUT_SCREEN_RULE] 生成结果缺少屏幕适配规则：$snippet。');
    }
  }
  for (final String snippet in _requiredGoalModeRuleSnippets) {
    if (!document.contains(snippet)) {
      violations.add('[AGENTS_OUTPUT_GOAL_RULE] 生成结果缺少 Goal Mode 规则：$snippet。');
    }
  }
  if (_countOccurrences(document, _goalModeHeading) != 1) {
    violations.add('[AGENTS_OUTPUT_GOAL_MODE] 生成结果必须且只能包含一份根级 Goal Mode。');
  }
  if (_windowsAbsolutePathPattern.hasMatch(document) ||
      _unixPersonalPathPattern.hasMatch(document) ||
      _uncPathPattern.hasMatch(document)) {
    violations.add('[AGENTS_OUTPUT_ABSOLUTE_PATH] 生成结果不得包含机器绝对路径。');
  }
  if (_urlPattern.hasMatch(document)) {
    violations.add('[AGENTS_OUTPUT_URL] 生成结果不得包含内部或生产 URL。');
  }
  if (_assignedSecretPattern.hasMatch(document)) {
    violations.add('[AGENTS_OUTPUT_SECRET] 生成结果不得包含疑似密钥或凭据值。');
  }
  violations.sort();
  return violations;
}

AgentsGenerationStatus? _inspectExistingTargetForGeneration(
  File target,
  List<int> expectedBytes,
) {
  return switch (_inspectAgentsTarget(target, expectedBytes)) {
    _AgentsTargetState.missing => null,
    _AgentsTargetState.matching => AgentsGenerationStatus.unchanged,
    _AgentsTargetState.stale =>
      throw AgentsGenerationException(const <String>[
        '[AGENTS_TARGET_EXISTS] 现有 AGENTS.md 与模板不同，工具不会覆盖用户内容。',
      ]),
    _AgentsTargetState.unreadable =>
      throw AgentsGenerationException(const <String>[
        '[AGENTS_TARGET_UNREADABLE] 现有 AGENTS.md 无法读取，工具不会覆盖。',
      ]),
    _AgentsTargetState.symlink =>
      throw AgentsGenerationException(const <String>[
        '[AGENTS_TARGET_SYMLINK] AGENTS.md 不得是符号链接。',
      ]),
    _AgentsTargetState.invalid =>
      throw AgentsGenerationException(const <String>[
        '[AGENTS_TARGET_INVALID] AGENTS.md 目标必须是普通文件。',
      ]),
  };
}

_AgentsTargetState _inspectAgentsTarget(
  File target,
  List<int> expectedBytes, {
  List<int> Function(File target)? readTargetBytes,
}) {
  late final FileSystemEntityType type;
  try {
    type = FileSystemEntity.typeSync(target.path, followLinks: false);
  } on FileSystemException {
    return _AgentsTargetState.unreadable;
  }
  switch (type) {
    case FileSystemEntityType.notFound:
      return _AgentsTargetState.missing;
    case FileSystemEntityType.link:
      return _AgentsTargetState.symlink;
    case FileSystemEntityType.file:
      try {
        final List<int> actualBytes =
            readTargetBytes?.call(target) ?? target.readAsBytesSync();
        return _bytesEqual(actualBytes, expectedBytes)
            ? _AgentsTargetState.matching
            : _AgentsTargetState.stale;
      } on FileSystemException {
        return _AgentsTargetState.unreadable;
      }
    case FileSystemEntityType.directory:
    case FileSystemEntityType.unixDomainSock:
    case FileSystemEntityType.pipe:
      return _AgentsTargetState.invalid;
    default:
      return _AgentsTargetState.invalid;
  }
}

enum _AgentsTargetState {
  missing,
  matching,
  stale,
  unreadable,
  symlink,
  invalid,
}

int _countOccurrences(String source, String pattern) {
  int count = 0;
  int offset = 0;
  while (true) {
    final int index = source.indexOf(pattern, offset);
    if (index < 0) {
      return count;
    }
    count += 1;
    offset = index + pattern.length;
  }
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

String _pathIn(Directory projectRoot, String relativePath) {
  final String platformPath = relativePath.replaceAll(
    '/',
    Platform.pathSeparator,
  );
  return '${projectRoot.path}${Platform.pathSeparator}$platformPath';
}
