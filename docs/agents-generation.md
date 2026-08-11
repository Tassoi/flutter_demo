# 基础 Agent 指南生成

## 目的与边界

`tool/generate_agents.dart` 只负责在一个尚未拥有根 `AGENTS.md` 的项目中初始化基础 Agent
指南。它不是通用脚手架 CLI，不生成业务代码、依赖、平台工程、发布配置或任意模板，也不会在
应用运行、Flutter 构建或测试后台改写文件。

生成器只使用 Dart 标准库，不增加运行时或开发依赖。当前仓库根 `AGENTS.md` 是用户维护的
权威规范，不能用本工具覆盖；初始化行为及所有写入测试均在独立临时项目中验证。

## 固定输入与输出

人工维护输入固定为：

```text
tool/templates/AGENTS.base.md
tool/templates/partials/goal_mode.md
```

基础模板只能包含一行 `{{GOAL_MODE}}`。生成器用完整局部模板原文替换该行，最终只创建项目根
`AGENTS.md`。模板和输出都必须是无 BOM 的 UTF-8、只使用 LF 且以换行结尾；相同输入不会读取
时间、环境变量、用户名或机器路径，因此输出字节完全一致。

`goal_mode.md` 必须保留根规范中完整的 Goal Mode 工作流，包括触发条件、初始化、原始输入
留存、第一轮 `GOAL_INIT_DONE`、逐轮单任务、每三个实现任务后的全面检查、无人值守阻塞边界、
禁止操作和最终全面 Review。不能用摘要、外部链接或几条关键字替代正文。

基础模板同时固定以下内容：

1. 单 App 项目定位、Android/iOS 手机范围和 `app/core/features/shared` 依赖方向。
2. 当前实际启用的环境、国际化、SVG 图标字体、认证、品牌资源和手机适配边界。
3. 运行、生成/文档检查、格式、严格分析、测试和 Android 构建命令。
4. 公开 API 与复杂逻辑的详细中文注释要求。
5. 正常、边界、失败、Widget、网络、存储、环境和生成器测试要求。
6. 密钥、日志脱敏、普通/安全存储、Git 与外部系统操作约束。
7. `375 x 812`、`du/dsp`、统一宽度比例、真实 Insets、短屏滚动、固定画布和六档视口验收规则。

输出校验还拒绝未展开占位符、机器绝对路径、URL 和疑似已赋值凭据。错误信息只包含固定规则
编号、项目相对路径和安全中文说明，不回显模板正文或用户已有规范。

## 初始化

在已经复制完整模板、但根目录还没有 `AGENTS.md` 的新项目中执行：

```bash
dart run tool/generate_agents.dart
```

CLI 只接受无参数初始化或唯一参数 `--check`，目标固定为当前目录。项目目录注入只作为 Dart
API 提供给临时测试，不暴露 `--root`；也不存在 `--force`、隐式覆盖或任意输出路径。

初始化结果只有两种成功状态：

| 状态 | 行为 |
| --- | --- |
| 目标不存在 | 独占创建 `AGENTS.md`，写入后逐字节回读验证 |
| 目标已存在且字节一致 | 返回成功，不重写内容，不改变 mtime |

以下情况稳定失败：

| 规则 | 含义与处理 |
| --- | --- |
| `AGENTS_TEMPLATE_MISSING` | 固定基础模板或 Goal Mode 局部模板缺失；恢复模板后重试 |
| `AGENTS_TEMPLATE_*` | 模板编码、换行、占位符、路径或结构不符合固定契约；先修正人工输入 |
| `AGENTS_OUTPUT_*` | 拼接结果缺少必需章节或包含不安全内容；不得绕过校验直接写目标 |
| `AGENTS_TARGET_EXISTS` | 用户文件与模板不同；保留用户内容，使用普通 diff 人工合并需要的规则 |
| `AGENTS_TARGET_UNREADABLE` | 已有目标无法读取；初始化拒绝猜测或覆盖其内容 |
| `AGENTS_TARGET_INVALID` | 目标是目录或其他非普通文件；先确认调用方真实意图，不自动删除 |
| `AGENTS_TARGET_SYMLINK` | 目标为符号链接；工具拒绝跟随，避免越过项目边界 |
| `AGENTS_WRITE_FAILED` | 本轮创建或写入失败；工具会清理自己创建的不完整目标 |
| `AGENTS_WRITE_RECOVERY_FAILED` | 写入失败且自动清理也失败；停止重试并人工检查根目标 |

如果目标已由团队修改，生成器不会把它恢复成模板版本。维护者应比较基础模板、Goal Mode
局部模板和项目实际规范，明确决定哪些变更需要人工合并；不得删除用户规则后重新生成来规避
冲突。

## 严格只读检查

已初始化的下游项目在 CI 或本地执行：

```bash
dart run tool/generate_agents.dart --check
```

检查会读取固定模板，在内存构建期望 UTF-8 字节，再读取根目标比较。它不会创建、删除、覆盖、
修复文件或更新 mtime，也不会在目标缺失时退回初始化。退出语义固定为：匹配返回 `0`，参数
错误返回 `64`，模板/目标/漂移错误返回 `1`；非零结果再通过稳定规则编号区分原因。

| 规则 | 含义与处理 |
| --- | --- |
| `AGENTS_CHECK_MISSING` | 根目标不存在；显式执行无参数初始化后重新检查 |
| `AGENTS_CHECK_STALE` | 根目标与当前模板字节不同；保留用户内容并人工审查差异 |
| `AGENTS_CHECK_UNREADABLE` | 目标无法读取；修正本地权限或文件系统问题 |
| `AGENTS_CHECK_SYMLINK` | 目标是符号链接；检查拒绝越过项目边界 |
| `AGENTS_CHECK_INVALID` | 目标是目录或其他非普通文件；先确认调用方真实意图 |

当前模板仓库根 `AGENTS.md` 是服务于脚手架开发的用户维护规范，职责和内容都多于下游基础
指南，因此不得在仓库根直接运行初始化或用 `--check` 要求它等于生成结果。Quality workflow
显式运行 `test/tool/generate_agents_test.dart`：测试把根规范、base、partial 和一次真实初始化
样例复制/生成到系统临时目录，再执行四方只读契约校验。该门禁要求根规范末尾的完整 Goal Mode
与 partial 逐字一致，并验证样例逐字等于模板拼接结果，能发现 Goal 条款删减、参考尺寸、
`du/dsp`、Insets、短屏滚动、固定画布和布局矩阵规则遗漏。

## 模板维护

修改基础模板时必须保持内容自包含，只描述当前项目实际启用的能力，不加入尚未实现的可选
模块、真实包名、内部/生产地址、密钥、个人数据、机器路径或模板仓库的 Goal 执行记录。生成到
项目中的代码注释要求必须保持中文；工具源码本身可以保留必要的英文上游术语。

修改 Goal Mode 时先更新权威根规范，再把完整章节同步到 `goal_mode.md`，逐字审查标题、列表、
禁止项和完成流程。随后运行专项测试；根规范与 partial 的任意单边变化都会以
`AGENTS_REPOSITORY_GOAL_MODE_DRIFT` 失败。修改 base 或屏幕规则后，临时样例必须重新由初始化
路径产生；校验会同时报告规则缺失和 `AGENTS_REPOSITORY_SAMPLE_STALE`，不能靠手改样例绕过。

## 测试与验证

聚焦验证：

```bash
flutter test test/tool/generate_agents_test.dart
dart format --output=none --set-exit-if-changed tool/generate_agents.dart \
  test/tool/generate_agents_test.dart
flutter analyze --fatal-infos --fatal-warnings
```

生成后的下游项目另行在自己的根目录执行 `dart run tool/generate_agents.dart --check`；不要在
当前模板仓库根运行该命令。

专项 19 项测试的所有写入均位于独立系统临时目录，从不改写仓库根 `AGENTS.md`。它覆盖首次
初始化、完整 Goal Mode 拼接、UTF-8/LF、重复构建字节稳定、相同目标 mtime、用户修改保护、
非法参数、局部模板缺失、非法目标类型、CRLF/重复占位符和注入写入失败后的清理；同时覆盖
`--check` 的匹配、缺失、过期、不可读、非法目标和连续零写入，以及根/base/partial/临时样例
四方漂移。不可读分支通过受限测试回调注入，不依赖宿主权限模型。

修改模板或生成器后还要执行全量测试，确认专用工具没有影响 Flutter 应用、其他生成器或平台
构建。该能力不修改原生平台、依赖或运行时代码，单独变化时不要求用一次无关 Android 构建
替代专项文件系统证据；最终阶段集成仍会执行统一 Android 构建。

基础模板同时列出 `dart tool/ci/check_documentation.dart`，使下游 Agent 在调整 README、专题
指南或 Quality 顺序后执行本地链接、命令目标和安全示例检查。该命令不替代生成器自己的
`--check`；前者验证工程文档，后者只比较下游根 `AGENTS.md` 与固定模板。

## 删除与回滚

尚未初始化任何下游文件时，可以整体删除以下内容而不影响应用运行：

```text
tool/generate_agents.dart
tool/templates/AGENTS.base.md
tool/templates/partials/goal_mode.md
test/tool/generate_agents_test.dart
docs/agents-generation.md
```

已经生成的下游 `AGENTS.md` 属于该项目的维护资产。移除生成器时默认保留它；只有项目负责人
明确确认不再需要规范时才单独删除。回滚生成器实现不应回退用户后来写入的规则，也不涉及
依赖、原生资源、签名、凭据或生产配置。
