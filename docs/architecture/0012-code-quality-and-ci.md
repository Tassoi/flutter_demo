# ADR 0012：代码质量门禁与 CI

- 状态：Accepted
- 决策日期：2026-08-09
- 适用范围：第一阶段代码规范与自动化检查

## 背景

脚手架需要把“本地能运行”提升为可重复验证的工程基线。格式、类型、依赖边界、测试和已提交
生成产物如果只依赖人工约定，会在模板复制和依赖升级后逐渐漂移；CI 如果使用宽泛权限、移动
版本或隐式工具链，又无法作为可复现证据。

本决策只建立质量门禁，不实现自动发布、签名、品牌资源生成、通用代码生成或第二阶段能力。
Task 15 后续在同一 workflow 增加了三环境一致性检查和 Android/iOS 构建任务，具体平台决策见
ADR 0013；它们仍不构成发布或签名流水线。

第二阶段 Task 8 又在同一只读质量链中加入品牌资源漂移检查。品牌能力本身仍由 ADR 0014 与
专项指南定义；本 ADR 只记录它作为已提交原生产物的 CI 门禁，不把该扩展改写成第一阶段交付。
第二阶段 Task 11 继续加入只读文档契约检查，校验本地链接、命令目标、安全示例、六份专题入口
以及 README/统一操作指南/workflow 的质量顺序；它不访问外网，也不修改文档。

## SDK 与依赖基线

1. `pubspec.yaml` 支持 Dart `>=3.7.0 <3.8.0`、Flutter
   `>=3.29.0 <3.30.0`，允许同一已验证 minor 的补丁版本，不承诺未经验证的下一 minor。
2. CI 固定 Flutter 3.29.0 和完整 framework revision
   `35c388afb57ef061d06a39b537336c87e0e3d1b1`。安装后再次读取 Git HEAD，缓存命中也必须验证。
3. `pubspec.lock` 必须提交。CI 使用 `flutter pub get --enforce-lockfile`，输入不能由流水线静默
   重新求解；依赖升级必须同时审查 `pubspec.yaml` 与锁文件 diff。
4. SDK 与核心依赖升级在独立分支完成，先调整受支持范围和 CI 精确 revision，再执行格式、
   分析、全量测试及受影响的平台构建。失败时两者一起回滚。

## 静态规则

`analysis_options.yaml` 继续基于 Flutter 官方 `flutter_lints`，并启用 strict casts、strict
inference、strict raw types。额外规则聚焦可维护性和运行时风险：显式返回类型、lib 内 package
导入、禁止隐式 dynamic 调用、异步结果处理、订阅与 sink 释放、指令顺序、结尾换行、仅抛出
Error/Exception、局部不可变性、公开 API 文档注释和稳定格式。公开注释必须遵守仓库的中文、
职责边界、错误、副作用和生命周期要求；这条 lint 只防止缺失，不能替代内容审查。

CI 将 info 与 warning 都视为失败。规则升级可能产生大范围迁移，必须在独立变更中说明新增规则、
修复证据和回滚方式，不得用全局 ignore 隐藏问题。确有第三方兼容原因时，只允许最小范围 ignore，
并在同一位置用中文注释说明原因和移除条件。

## 架构边界检查

`tool/ci/check_architecture.dart` 使用 Dart 标准库扫描 `lib/**/*.dart` 的 `import` 与 `export`：

1. `lib/` 内只允许 package 导入，不允许相对导入。
2. `main.dart` 只能进入 `app/` 组装层。
3. `core/`、`shared/` 不得反向依赖 `app/` 或 `features/`。
4. Feature 不得依赖 `app/`，也不得导入其他 Feature 的内部实现。
5. Dio、go_router、shared_preferences、flutter_secure_storage、logging 和 flutter_svg 只能在
   ADR 0001 指定的单一适配文件使用；Riverpod 只能位于 `app/` 或 Feature presentation。
6. Android 主 Manifest 必须保留 `INTERNET` 权限和禁用系统备份的安全存储策略；iOS 必须保留
   当前 Keychain entitlement，避免平台更新让 release 网络或持久化安全边界静默漂移。

检查器不引入 analyzer/build_runner，也不尝试建立通用代码生成平台。它检查当前项目使用的标准
URI 指令；若未来引入 part、宏或新的第三方 adapter，必须先扩充规则及其正常、边界、失败测试，
不能仅修改代码绕过现有检查。

## 生成产物新鲜度

当前需要提交并检查的 Flutter/仓库生成产物包括：

1. `pubspec.lock`：检查器把 pubspec 与锁文件复制到隔离临时目录，执行
   `flutter pub get --enforce-lockfile`，重算结果必须与仓库版本逐字节一致，并保留 pub
   生成标记。不能只依赖命令退出码，因为依赖仍可满足时 pub 可能更新 SDK 区间并成功退出。
2. `.metadata`：顶层 `version.revision` 记录项目创建时的 Flutter framework，不是当前 SDK
   pin。检查器验证创建 revision 格式、stable 频道、app 类型、仅 root/Android/iOS 的平台集合、
   合法 migration revision，以及 `lib/main.dart` 和定制 PBX 工程仍在 unmanaged 保护列表中。
3. `lib/app/localization/generated/`：专项本地化工具在系统临时项目调用固定 Flutter
   `gen-l10n`，归一化中文注释后逐字节检查提交产物和零缺失翻译报告。
4. `assets/fonts/template_icons.otf` 与
   `lib/shared/assets/generated/template_icons.g.dart`：专项 SVG 字体工具校验人工清单、
   SVG 和许可证，归一化 OTF 元数据并执行只读字节比较。
5. Android/iOS 应用图标和启动资源：品牌专项工具预检授权 PNG，在系统临时项目调用锁定的
   launcher/splash 工具，以 73 文件白名单逐字节比较，并核对三环境公共原生引用。

三类专项生成保持独立，不抽象为通用代码生成框架。

当前 SDK 的权威固定点是 workflow 三个 job 完全一致的 `FLUTTER_VERSION` 和完整
`FLUTTER_REVISION`。不得为了让 `.metadata` 等于本机 SDK 而手工改写创建信息；Flutter 工具在
经过审查的平台迁移中产生的 metadata diff 才能随迁移提交。

iOS PluginRegistrant、Generated.xcconfig、`.dart_tool/` 和构建目录是被忽略的本地输出，不作为
提交产物。普通 SVG 的类型安全 catalog 继续按 ADR 0007 手工维护；图标字体只生成上面固定的
两个输出，不扩展到其他资源类型。

## CI 安全与可复现性

`.github/workflows/quality.yml` 在 push、pull request 和手动触发时先运行质量任务，再运行平台构建任务：

1. workflow 只授予 `contents: read`，checkout 关闭凭据持久化，不使用 secret、
   `pull_request_target`、发布权限或外部写入。
2. GitHub Actions 固定到完整 commit SHA，并在旁边记录可审查版本；不依赖移动 tag。
3. runner 固定 `ubuntu-24.04`，任务总超时 30 分钟，同一 ref 的旧任务可被取消。
4. Flutter SDK 缓存以完整 framework revision 为键；pub 缓存以锁文件哈希为键，并保留受约束
   的 restore prefix。缓存只优化下载，不替代 revision、checksum 和锁文件验证。Flutter 3.29.0
   在 detached checkout 启动时仍读取 `origin/master`，且缺少版本 Tag 时会报告 unknown 版本；
   因此三个 job 每次恢复缓存后都把仅限本地的兼容引用和 `FLUTTER_VERSION` Tag 重建到已校验的
   `FLUTTER_REVISION`，不得为此拉取会移动的远程引用。
5. 质量门禁顺序固定为隔离锁文件/metadata 检查、锁定依赖、本地化、SVG 字体与品牌资源只读
   生成检查、Agent 指南临时项目契约、文档契约、架构检查、原生环境一致性、格式、严格分析和
   固定 seed 全量测试。质量任务通过后，Android/iOS 任务才构建三套环境；本阶段没有发布流程。
6. iOS 任务除固定 Xcode 16.2 外，还把 CocoaPods 1.16.2 安装到独立的 `GEM_HOME/GEM_PATH`，
   并在构建前核对 PATH 中的版本。runner 的预装 gem 会随镜像更新，不得让它静默改写 Pods
   集成结果；固定版本升级仍需经过显式兼容性验证。

## 本地等价命令

```bash
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
```

当前 WSL 工作站仍按 ADR 0001 通过 Windows `cmd.exe /d /c` 调用 Flutter/Dart；命令语义与 CI
相同。锁文件/metadata 检查在依赖解析前运行；需要 Flutter 或 YAML/XML 包的专项检查只在
`flutter pub get --enforce-lockfile` 后运行。通用工程检查器及资源生成器按各自文档支持
`--root <path>`；Agent 工具有意不暴露任意根参数，只在 Dart 测试 API 注入系统临时目录。
各 `--check` 路径不得修改业务源码或项目生成目标。

## Task 14 验证结果

1. 收窄 SDK 输入后，Flutter 3.29 的 `--enforce-lockfile` 成功退出但实际更新了锁文件 SDK
   区间，证明不能只检查退出码。改为隔离重算后，当前 `pubspec.lock` 与结果逐字节一致。当时
   `.metadata` 创建 revision 恰好与工具链一致，但 Task 16 已确认这不是应当持续强制的不变量。
2. 架构检查扫描 47 个 `lib/` Dart 文件并通过；新增门禁测试覆盖允许路径、反向依赖、跨
   Feature、相对/编码 URI、adapter 越界、锁文件漂移和缺失/无效 metadata。
3. `dart format --output=none --set-exit-if-changed .` 检查 86 个文件且无改写；严格
   `flutter analyze --fatal-infos --fatal-warnings` 为零问题。
4. 默认顺序和固定 seed `20260809` 的全量测试均为 185 项通过；dev 配置的 Android Debug APK
   实际构建通过。
5. actionlint 1.7.12 的 Linux amd64 发布包经官方 SHA-256 校验后检查 workflow，结果为零问题；
   `actions/checkout` v6.0.2 与 `actions/cache` v5.0.5 的 tag 也分别解析到 workflow 中固定的完整
   commit SHA。校验工具只在系统临时目录运行，随后移入回收站，未成为项目依赖。
6. 高置信度密钥模式、写权限、secret 上下文和 `pull_request_target` 扫描无实现命中；
   `git diff --check` 通过。根 `AGENTS.md` 与 Goal 原文哈希保持不变。

## Checkpoint E 补强

跨任务审查确认，Android 还存在 `bundleDebug/Profile/Release` 聚合入口，原门禁只拒绝
`assemble*`。未指定 flavor 的真实 App Bundle 命令曾构建 dev、staging、prod 三套 AAB 后才因
缺少通用输出失败；Checkpoint E 因此同时覆盖了 `assemble*` 与 `bundle*`，并增加失败测试。
Task 18 的产物时间戳审计进一步发现，当时使用的聚合任务 `doFirst` 仍会在 flavor 依赖完成后才
抛错，能够污染已有正确产物。当前实现改为在 Gradle 配置阶段检查显式请求任务并立即失败；
平台门禁新增晚触发保护反例，真实无 flavor APK/AAB 命令也已证明不会改变既有产物。

审查同时依据 CocoaPods 1.16.2 的官方实现确认，其 aggregate xcconfig 文件名使用完整 Xcode
configuration。iOS 现在为 9 个 configuration 使用一一对应的包装 xcconfig，平台门禁会拒绝
错误或缺失的 Pods include；workflow 会隔离安装并显式核对 CocoaPods 1.16.2。真实 iOS 编译
由 GitHub Actions macOS runner 对三套环境提供证据，静态修复不能替代该平台验证。

## Task 16 生成检查语义修正

工程文档审计发现，旧检查器把 `.metadata` 的创建 revision 错当成当前 SDK pin。Flutter tool
源码将该字段用于项目创建/模板迁移；SDK 升级后要求它始终等于当前 framework 会产生误报，也
会诱导维护者手工修改本应由 Flutter 工具管理的文件。

本次先增加“旧创建 revision 仍应通过”的回归测试，确认旧实现以
`GENERATED_SDK_MISMATCH` 失败，再移除运行时 `flutter --version` 比较，改为上文的结构和保护
项校验。`check_generated_files_test.dart` 现有 5 项测试覆盖有效 metadata、旧创建 SDK、畸形
输入、锁文件/迁移 revision 漂移，以及平台集合/unmanaged 保护漂移；修复后全部通过。workflow
三个 job 的完整 revision pin 继续独立保证当前 SDK 可复现性。

依赖与 SDK 的完整升级、平台验证和回滚步骤见
[依赖与 SDK 升级指南](../dependency-upgrades.md)。

## 第二阶段 Agent 指南契约门禁

模板仓库根 `AGENTS.md` 是用户维护的开发规范，并不等于下游基础指南，因此 workflow 不会在
仓库根直接执行 `generate_agents.dart --check`。它在依赖解析和其他生成检查后显式运行
`test/tool/generate_agents_test.dart`：所有初始化写入、目标修改和故障注入只发生在系统临时
目录，根规范只被复制读取。

专项 19 项测试覆盖下游 `--check` 的匹配、缺失、过期、不可读和非法目标，并用完整目录快照
证明检查零写入；同时要求根规范末尾 Goal Mode 与 partial 逐字一致，临时初始化样例与
base + partial 逐字一致，并对 Goal 条款、参考尺寸和 Insets 规则提供失败反例。下游生成项目
可直接把 `dart run tool/generate_agents.dart --check` 放入自己的 CI；匹配返回 `0`，参数错误
返回 `64`，其余检查失败返回 `1` 并携带稳定规则编号。

## 第二阶段文档契约门禁

`tool/ci/check_documentation.dart` 使用 Dart 标准库只读扫描 README、`docs/`、目录 README 和
资源许可证，不读取 `goal-*`、构建缓存或 IDE 状态。它解析本地 Markdown 链接和标题锚点，
核对 Bash 示例中的 `tool/`、`test/` 与显式 `config/` 目标，并要求阶段二统一操作指南链接六份
专题指南。外部 HTTP(S) 链接不在 CI 中联网探测，避免网络状态成为文档正确性的随机输入。

检查器还要求 README、`docs/phase-2-operations.md` 与 Quality workflow 按同一顺序列出完整
质量命令，并拒绝代码示例中的个人主目录、私钥标记和非 `.invalid` 服务地址。对应测试覆盖
完整通过、本地链接缺失/越界/锚点错误、命令目标与 CI 漂移，以及不安全示例；CLI 支持只读
`--root <path>`，参数错误返回 `64`，契约失败返回 `1`。

## 已知限制与回滚

本地验证不能证明 GitHub-hosted runner 的冷缓存网络一定可用，workflow 必须在远端首次运行后
补充真实 CI 证据。当前非 macOS 主机不能提供 iOS 编译证据，因此 Task 15 固定的 macOS 无签名
构建仍属于待远端执行的验证路径，不能在本地报告为已通过。

回滚时可以独立移除 workflow、三个 `tool/ci` 检查器及其测试，并恢复 analysis options；若恢复
宽 SDK 范围，必须同时明确撤销“受支持版本”承诺。不得只删除失败门禁而保留文档中的通过声明，
也不得回退用户的 `AGENTS.md`、Goal 原文或无关实现。

常见本地与平台故障的诊断顺序见[常见问题与诊断](../troubleshooting.md)。

## 官方来源

1. [GitHub Actions 安全使用参考](https://docs.github.com/en/actions/reference/security/secure-use)
2. [actions/checkout](https://github.com/actions/checkout)
3. [actions/cache](https://github.com/actions/cache)
4. [Flutter 持续交付文档](https://docs.flutter.dev/deployment/cd)
