# 依赖与 SDK 升级指南

本指南用于升级 Flutter/Dart 基线、直接依赖和 `flutter_lints`。升级的目标不是让版本号始终
追平 pub.dev，而是在保留架构边界、平台数据兼容性和可回滚证据的前提下得到一套重新验证的
基线。

## 必须保持的工程不变量

1. 状态、路由、网络、普通存储、安全存储、日志和普通 SVG 各自只有一套默认实现。
2. 第三方类型继续留在 ADR 0001 规定的组装或 adapter 边界，Feature domain 不直接依赖插件。
3. `pubspec.yaml`、`pubspec.lock`、SDK 支持范围和 CI pin 必须描述同一套已验证输入。
4. Android 的三个 flavor 与 iOS 的三个 scheme 必须继续和 `APP_ENV` 一一对应。
5. 升级不得引入真实密钥、发布签名、当前任务范围外能力或通用代码生成框架；已经启用的
   第二阶段依赖仍必须维持 ADR 0014 规定的适配边界。
6. 存储格式、物理键、Keychain service、Android namespace 或路由 URI 的变化必须被当作迁移，
   不能只按“依赖版本变化”处理。

## 当前已验证基线

| 输入 | 当前值 | 主要验证边界 |
| --- | --- | --- |
| Flutter | 3.29.0 stable，revision `35c388afb57ef061d06a39b537336c87e0e3d1b1` | 三个 CI job、格式、分析、测试及 Android/iOS 三环境实际构建 |
| Dart | 3.7.0 | `pubspec.yaml` 支持范围与 Flutter SDK 携带版本 |
| flutter_riverpod | 2.6.1 | 根作用域、异步状态、取消和销毁 |
| go_router | 17.0.0 | 参数、Shell、未知页和同步重定向 |
| dio | 5.11.0 | 请求、取消、凭据、日志和错误映射 |
| shared_preferences | 2.5.3 | `SharedPreferencesAsync`、namespace 和普通存储契约 |
| flutter_secure_storage | 10.3.1 | Android/iOS 选项、安全存储契约和持久化兼容性 |
| logging | 1.3.0 | 结构化上下文、级别、脱敏和 sink 生命周期 |
| flutter_svg | 2.2.2 | 类型安全资源、语义、主题和真实 AssetBundle |
| flutter_screenutil | 5.9.3 | 根初始化、统一宽度比例、系统文字缩放和插件隔离边界 |
| flutter_localizations / intl | Flutter SDK / 0.19.0 | `gen-l10n`、en/zh 格式化、中文生成注释、确定性检查和 iOS 语言声明 |
| icon_font_generator / xml / yaml | 4.0.0 / 6.5.0 / 3.1.3 | 仅仓库工具使用；稳定 PUA、严格 SVG/许可证预检、确定性 OTF/Dart 和平台字体注册 |
| flutter_launcher_icons / flutter_native_splash / image | 0.14.4 / 2.4.6 / 4.8.0 | 仅品牌工具使用；PNG 预检、隔离上游生成、73 文件白名单、事务恢复和平台引用 |
| flutter_lints | 5.0.0 | strict analyzer 配置与零 warning/info 门禁 |

### 2026-08-10 依赖审计快照

以下结果来自 Flutter 3.29.0 下的 `flutter pub outdated`，只代表该日期和该 SDK。`dio` 与
`logging` 因已经是 Latest，没有出现在命令的过期直接依赖列表中。

| 包 | Current | Upgradable | Resolvable | Latest | 当前结论 |
| --- | --- | --- | --- | --- | --- |
| flutter_riverpod | 2.6.1 | 2.6.1 | 3.3.2 | 3.4.2 | 3.3.2 可解析，但跨 major，必须单独迁移和验证 |
| flutter_secure_storage | 10.3.1 | 10.3.1 | 10.3.1 | 11.0.0 | 当前 SDK 不能解析 11.x |
| flutter_svg | 2.2.2 | 2.2.2 | 2.2.2 | 2.3.0 | 当前 SDK 不能解析最新版 |
| go_router | 17.0.0 | 17.0.0 | 17.0.0 | 17.4.0 | 当前 SDK 不能解析最新版 |
| shared_preferences | 2.5.3 | 2.5.3 | 2.5.3 | 2.5.5 | 当前 SDK 不能解析最新版 |
| icon_font_generator | 4.0.0 | 4.0.0 | 4.0.0 | 4.1.0 | 4.1.0 的传递分析/格式依赖要求 Dart >=3.9；工具行为还需专项迁移 |
| flutter_native_splash | 2.4.6 | 2.4.6 | 2.4.6 | 2.4.8 | 2.4.7 要求 Dart >=3.8，2.4.8 与当前 Flutter 固定 meta 冲突 |
| image | 4.8.0 | 4.8.0 | 4.8.0 | 4.9.1 | 与品牌工具精确成组锁定，升级可能改变 PNG 编码字节 |
| flutter_lints | 5.0.0 | 5.0.0 | 5.0.0 | 6.0.0 | 随 SDK 基线和 lint 迁移一起评估 |

四列含义不同：

1. **Current** 是锁文件当前选择的版本。
2. **Upgradable** 是不修改现有 `pubspec.yaml` 约束时可以升级到的版本。
3. **Resolvable** 是允许修改约束后，当前 SDK 和整张依赖图能够共同解析的最高版本。
4. **Latest** 是 pub.dev 最新版本，不保证与当前 SDK、其他依赖或项目代码兼容。

因此，“Resolvable 高于 Current”只是一条候选迁移信号，不是自动升级授权。命令语义以
[Dart `pub outdated` 文档](https://dart.dev/tools/pub/cmd/pub-outdated)和
[`pub upgrade` 文档](https://dart.dev/tools/pub/cmd/pub-upgrade)为准。

## 升级节奏与触发条件

1. 每月或每个发布周期运行一次只读 `flutter pub outdated`，不因发现新版本立即改锁文件。
2. 安全公告、平台商店要求、停止维护、编译失败或明确缺陷可以触发计划外升级。
3. patch/minor 仍需按受影响能力验证；major、SDK、原生插件和 lint 基线必须独立变更。
4. 不把多个无关直接依赖混入一次升级。只有同一 SDK 迁移导致的不可分割约束变化可以成组，
   并需逐项记录原因。
5. 升级前阅读所选版本之间的 changelog、migration guide、平台要求和包内 `LICENSE`；不能只看
   pub 求解成功。

## 升级前审计

在独立分支或其他可恢复工作区中记录基线。先保留当前失败/通过证据，不要用清理命令抹掉问题：

```bash
git status --short
flutter --version --machine
flutter doctor -v
flutter pub outdated
flutter pub deps --style=compact
flutter pub upgrade --major-versions --dry-run
```

检查 `pubspec.yaml`、`pubspec.lock`、`.github/workflows/quality.yml`、Android Gradle 输入和 iOS
工程输入是否已有未提交修改。`--major-versions --dry-run` 只用于预览当前 SDK 下的候选约束，
不能代替 changelog 和迁移评审。

同时回答以下问题并写入变更记录：

1. 新版本的 Dart、Flutter、Android min/compile SDK、iOS deployment target、JDK、Gradle、Xcode
   和 CocoaPods 下限是什么？
2. 许可证、发布者或维护状态是否变化，是否新增必须保留的 notice？
3. 是否改变本地持久化格式、加密实现、备份行为、路由 URI、取消语义、日志内容或网络默认值？
4. 是否新增传递依赖、代码生成、平台权限、隐私声明、包体或启动成本？
5. 旧版本写入的数据能否被新版本读取；回退后二进制能否读取升级期间写入的数据？

## 升级单个依赖

一次只选择一个直接依赖：

1. 在 `pubspec.yaml` 中把约束改为明确、经过审查的版本范围，不使用 `any` 或
   `dependency_overrides` 绕过 SDK 下限。
2. 预览该包及必要传递依赖的变化：

```bash
flutter pub upgrade <package-name> --dry-run
```

3. 确认预览只包含预期变化后生成锁文件：

```bash
flutter pub upgrade <package-name>
flutter pub get --enforce-lockfile
flutter pub deps --style=compact
```

4. 同时审查 `pubspec.yaml` 和 `pubspec.lock` diff。不要手工编辑锁文件，也不要顺手接受无关
   直接依赖升级。
5. 完成下方对应能力的聚焦测试，再执行完整质量门禁和需要的平台构建。

### 依赖聚焦验证矩阵

| 输入 | 首要验证 |
| --- | --- |
| flutter_riverpod | `test/app/state/`、示例 Controller、`test/features/auth/presentation/`、根 `ProviderScope` override、加载/空/失败/重试、认证恢复/单飞刷新、auto-dispose、取消与迟到结果 |
| go_router | `test/app/router/`、两个 Feature 的纯 Dart 路由契约、Shell 栈、参数、未知页、认证 loading/登录/受保护重定向、安全 `returnTo` 及 Widget 返回行为 |
| dio | `test/core/network/`、示例网络 Repository、`test/features/auth/data/authenticated_network_client_test.dart`、请求取消、timeout、错误映射、凭据注入、401 单飞/单次重放和敏感日志过滤 |
| shared_preferences | 普通存储契约与 adapter 测试、namespace、默认值、scoped clear，并在 Android/iOS 构建中验证插件注册 |
| flutter_secure_storage | 安全存储契约与 adapter 测试、`secure_auth_credential_persistence_test.dart` 的单 envelope/schema/损坏数据、Android/iOS 实际构建、已有数据读取、Keychain/加密/备份迁移与回退兼容性 |
| logging | `test/core/logging/`、启动 Reporter、环境阈值、脱敏、循环/恶意上下文和 sink 关闭 |
| flutter_svg | `test/shared/assets/`、主题/资源 Widget 测试、语义、固定尺寸、真实 AssetBundle 和 Android/iOS 包资源 |
| flutter_screenutil | `test/shared/layout/`、`TemplateApp` 根初始化、主题与共享组件、示例流程、六档视口各自正常/200% 文字、运行时指标变化、原始 SafeArea/键盘 Insets、短屏/横屏滚动可达性、固定画布矩形、Ahem 参考 Golden，以及 Feature 插件导入架构门禁 |
| flutter_localizations / intl | `dart run tool/generate_localizations.dart --check`、`test/app/localization/`、locale Controller 持久化竞态、en/zh 复数/日期/数字、双语六尺寸页面矩阵、iOS `CFBundleLocalizations` 和 Android/iOS 构建 |
| icon_font_generator / xml / yaml | `dart run tool/generate_icon_font.dart --check`、`test/tool/generate_icon_font_test.dart`、`test/shared/assets/template_icons_test.dart`、重排/追加/退休/回滚、OTF 时间/版权/校验和/cmap、工具依赖架构门禁、pubspec 字体注册和 Android/iOS 构建 |
| flutter_launcher_icons / flutter_native_splash / image | `dart run tool/generate_branding.dart --check`、`test/tool/generate_branding_test.dart`、PNG/Alpha/安全区/权利预检、连续两次 73 文件哈希、第二目标失败恢复、平台门禁、Android 构建及 macOS iOS 构建 |
| flutter_lints | 全量格式和严格分析；逐条处理新增 lint，不使用仓库级 ignore 消音 |

插件升级即使没有 Dart API 编译错误，也必须核对 Android/iOS 的注册、最低系统版本和数据迁移。

SVG 字体工具三项依赖视为一个不可分割的生成输入。`icon_font_generator` 升级前必须重新审查
顺序分配、默认 glyph、退休占位、CFF 表、`head/name` 时间字段和校验和；`xml`/`yaml` 升级
必须重跑非法结构与固定配置测试。连续生成两次的 OTF/Dart SHA-256 必须一致，不能用更新
生成文件掩盖 codepoint 或元数据漂移。完整流程见 [SVG 图标字体指南](svg-icon-font.md)。

认证模块没有新增第三方依赖，但会同时消费 Riverpod、go_router、网络、安全存储和日志的
项目接口。升级其中任一项时都要重跑 `test/features/auth/` 与认证路由策略测试，并复核 session
generation、单飞 Future、调用方取消、单 envelope schema、日志脱敏和 Provider/Router 释放；
只通过各包原有单元测试不能证明跨边界会话仍然安全。完整不变量见
[认证模块指南](authentication.md)。

品牌三项依赖同样视为不可分割的生成输入。升级前必须重新记录许可证、Dart/Flutter 下限和
上游写入清单，尤其复核 launcher 对 Xcode Asset Symbols、splash 对 `Info.plist` 及新建 v31
styles 行尾空白的行为。
连续两次生成的 73 个文件必须逐字节一致，`--check` 必须保持只读，注入安装失败后旧文件必须
整组恢复；随后核对 Android/iOS 原生引用和实际构建。完整契约见[品牌资源生成指南](branding.md)。

## 第二阶段协调升级顺序与生成产物迁移

一次升级仍只处理一个直接依赖或一个不可分割的生成器组合。若 SDK 升级同时解锁多个候选，
也应按以下顺序逐组验证，不能把整张依赖图和所有生成产物一次性刷新后再猜测差异来源：

1. 先固定新的 Flutter/Dart 与三个 CI job revision，恢复锁文件可解析状态；这一变更不同时接受
   无关 major 依赖。
2. 分别升级运行时 adapter。`flutter_screenutil` 只允许改变
   `app_screen_adaptation.dart` 内部并保持 `du/dsp` 契约；`intl`/Flutter 本地化模板变化必须先
   通过中文注释与缺失翻译检查。Riverpod、路由、网络、安全存储或日志变化还要重跑认证组合
   测试，即使认证模块本身没有新增依赖。
3. 把 `icon_font_generator/xml/yaml` 作为一组，再把
   `flutter_launcher_icons/flutter_native_splash/image` 作为另一组。两组之间不得共享临时
   白名单或回滚目录。
4. Agent 生成器只依赖 Dart 标准库，但 SDK/格式器变化仍需重跑 19 项临时项目契约；已有下游
   `AGENTS.md` 不因工具升级自动覆盖。
5. 最后按“国际化 -> SVG 字体 -> 品牌”的固定顺序迁移提交产物，再运行全部只读检查和文档
   契约门禁。该顺序与[阶段二统一操作指南](phase-2-operations.md)及 Quality workflow 一致。

生成器升级前记录人工输入、旧工具版本、锁文件、全部目标路径和 SHA-256。在独立临时副本使用
新工具连续生成两次，先验证字节确定性，再审查语义不变量：本地化键/占位符和语言声明不丢失；
字体 family、既有 codepoint、退休槽与 `nextCodepoint` 不变化；品牌只写固定公共白名单且三环境
继续共用资源。确认后才在主工作区生成并执行所有 `--check`。

若新版本有意改变产物格式，应附迁移说明，明确旧二进制/旧工具是否还能读取或清理新数据、
产物是否需要一次性重建、平台包体和视觉如何复核。失败时成组恢复依赖约束、锁文件、wrapper、
人工输入、全部生成产物、CI 与文档；不得只恢复输出文件，也不得让旧工具读取未声明兼容的新
schema。手机适配替换和 1:1 固定逻辑像素回退见
[移动端屏幕适配指南](mobile-screen-adaptation.md)。

## 升级 Flutter/Dart SDK

SDK 升级会同时影响求解器、Flutter 模板、分析器、测试运行时和两个原生工程，必须单独完成：

1. 从 Flutter stable 的明确版本选择一个完整 framework revision，阅读
   [Flutter 升级说明](https://docs.flutter.dev/install/upgrade)和
   [破坏性变更索引](https://docs.flutter.dev/release/breaking-changes)。不要在主工作区依赖一个
   随后继续移动的 channel HEAD。
2. 安装或切换到该精确 SDK，记录 `flutter --version --machine` 与 `flutter doctor -v`。
3. 更新 `pubspec.yaml` 的 Dart/Flutter 支持范围，并把 `.github/workflows/quality.yml` 中
   `quality`、`android`、`ios` 三个 job 的 `FLUTTER_VERSION` 和 `FLUTTER_REVISION` 全部改为
   同一值。CI 中完整 revision 才是当前 SDK 的可复现权威。
4. 只有新 SDK 或插件明确要求时才调整 compile/min SDK、NDK、Gradle、JDK、iOS target、Xcode
   或 CocoaPods；每一项都要记录来源和平台构建证据。
5. 在系统临时目录复制工程并检查新 SDK 的平台模板差异。不要在已定制的主工作区盲目执行
   `flutter create .`，它可能重新引入通用 `Runner` scheme 或覆盖环境配置。只把确认需要的
   平台迁移逐项应用并审查 diff。
6. 重新运行 `flutter pub outdated`，按单依赖流程处理因 SDK 解锁的 major；SDK 可解析不等于
   项目已兼容。

### `.metadata` 的正确语义

`.metadata` 顶层 `version.revision` 是项目**创建时**的 Flutter framework，migration 中的
`create_revision`/`base_revision` 用于 Flutter 模板迁移。它不是“当前使用 SDK”的 pin，不能
为了升级而手工改成 `flutter --version` 的输出。

`tool/ci/check_generated_files.dart` 因此只验证以下稳定不变量：创建 revision 合法、创建频道为
stable、项目类型为 app、平台集合恰好为 root/Android/iOS、迁移 revision 合法，以及
`lib/main.dart` 和定制 PBX 工程仍受 unmanaged 保护。若 Flutter 工具在经过审查的平台迁移中
合法更新 `.metadata`，应提交工具产生且能够解释的 diff；否则保持原值。

## 完整验证

所有依赖或 SDK 升级都执行本地 CI 等价门禁：

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
flutter test
flutter test test/goldens/mobile_ui_golden_test.dart
```

SDK 或渲染相关依赖升级后，Golden 默认只做比较。若 Flutter 引擎、SVG 或 Material 图标的像素
确有预期变化，必须先通过六尺寸矩形/语义矩阵，再使用 `--update-goldens` 生成候选，并逐张审查；
Ahem 只固定测试字形，不能把宿主渲染差异或真实平台字体验证省略。

SDK、原生插件、字体、资源或平台配置升级还要在 Android 构建全部环境：

```bash
for environment in dev staging prod; do
  flutter build apk --debug --flavor "$environment" \
    --dart-define-from-file="config/$environment.example.json"
  flutter build appbundle --debug --flavor "$environment" \
    --dart-define-from-file="config/$environment.example.json"
done
```

并在 macOS 上构建全部 iOS scheme：

```bash
for environment in dev staging prod; do
  flutter build ios --debug --no-codesign --flavor "$environment" \
    --dart-define-from-file="config/$environment.example.json"
done
```

存储、路由、触摸、语义或平台通道行为发生变化时，还应在代表性 Android/iOS 设备上验证。
无法执行的环境必须明确记录，不能用静态检查或另一平台构建代替。

## 回滚

1. 保留升级前的 SDK revision、依赖图、锁文件、测试结果和平台构建日志，确保能定位最后一套
   已知可用输入。
2. 回滚单依赖时一起恢复 `pubspec.yaml`、`pubspec.lock` 及对应代码/平台迁移；回滚 SDK 时还要
   一起恢复三个 CI job 的版本与 revision、SDK 支持范围和受影响平台工具链。
3. 不使用 dependency override、放宽 SDK 范围、删除失败测试或关闭门禁来伪装回滚成功。
4. 安全存储或普通存储升级写入了新格式后，先确认旧版本能够读取；否则需要向前兼容读取器或
   显式数据迁移，不能直接下发旧二进制造成数据丢失。
5. 路由 URI、公开接口或序列化发生变化时，回滚必须同时恢复调用方和兼容入口，避免已保存链接
   或数据失效。
6. 回滚后重新执行与升级相同的聚焦测试、完整门禁和平台构建，记录仍然存在的外部网络、设备或
   macOS 验证缺口。
7. SVG 字体工具回滚必须同时恢复三个精确 dev 依赖、锁文件、生成器、清单、OTF 和 Dart 映射；
   不得让旧工具读取新 schema，也不得复用已退休 codepoint。
8. Riverpod、路由、网络或安全存储回滚不得让认证状态出现第二所有者、复用已失效 generation、
   绕过 `returnTo` 白名单或遗留不可读取的 `auth.session`；必要时先发布兼容读取与精确清理迁移。
9. 品牌工具回滚必须同时恢复三个精确 dev 依赖、锁文件、两份配置、源图/权利声明、wrapper、
   Android/iOS 全部白名单产物和 CI 接线；不得只换源图或只恢复单个平台。
10. Agent 工具回滚不得覆盖下游已经维护的 `AGENTS.md`；文档门禁回滚必须同步恢复 README、
    阶段二操作指南、workflow 与 ADR 的同一质量顺序，不能只删除失败的检查步骤。

第一阶段依赖的升级结果和最终版本判断应同步回
[ADR 0001](architecture/0001-technology-baseline.md)，第二阶段依赖同步回
[ADR 0014](architecture/0014-phase-2-technology-baseline.md)，CI/生成产物规则变化同步回
[ADR 0012](architecture/0012-code-quality-and-ci.md)。
