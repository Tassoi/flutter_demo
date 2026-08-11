# 第二阶段采用、运维与裁剪指南

本文是六项第二阶段能力的统一操作入口，负责说明准备、启用顺序、生成/过期检查、验证、升级
和裁剪。每项能力的输入契约与失败恢复仍以对应专题指南为准：

1. [移动端屏幕适配](mobile-screen-adaptation.md)
2. [国际化](internationalization.md)
3. [SVG 图标字体](svg-icon-font.md)
4. [认证模块](authentication.md)
5. [品牌资源生成](branding.md)
6. [基础 Agent 指南生成](agents-generation.md)

这些能力不会扩大为桌面/平板框架、真实认证服务、品牌设计服务或通用脚手架 CLI。阶段范围与
验收依据见[第二阶段实施计划](phase-2-plan.md)，依赖版本与迁移细节见
[依赖与 SDK 升级指南](dependency-upgrades.md)。

## 环境准备

1. 使用仓库固定的 Flutter 3.29.0 / Dart 3.7.0。Android 准备 platform 36、build-tools
   35.0.1、NDK 27.0.12077973、JDK 21 并接受 licenses；iOS 只在 macOS 使用 Xcode 16.4 和
   CocoaPods 1.16.2。
2. 在仓库根执行 `flutter --version`、`dart --version` 和 `flutter doctor -v`，先处理目标平台
   工具链错误。WSL 使用 README 记录的 Windows 批处理入口，不改写全局 SDK。
3. 三个环境始终成对使用 flavor 和示例配置。示例地址只允许 `.invalid`；真实密钥、账号、
   品牌、证书、签名和生产地址不得写入文档、Dart define 或版本库。
4. 所有生成器都依赖已经锁定的依赖图，先执行：

```bash
flutter pub get --enforce-lockfile
```

## 当前启用点与专项操作

| 能力 | 当前启用点 | 生成与过期检查 | 聚焦测试 | 平台证据 |
| --- | --- | --- | --- | --- |
| 手机适配 | `TemplateApp` 下唯一 `AppScreenAdaptation`；调用方使用 `du/dsp` | 无生成产物；架构门禁防止插件泄漏，布局矩阵防行为漂移 | `flutter test test/shared/layout` 与两套布局矩阵/Golden | Android/iOS 构建；代表设备验证旋转、Insets、键盘和大字体 |
| 国际化 | `app/localization`、locale Controller、应用代理与 iOS 语言声明 | `dart run tool/generate_localizations.dart`；随后同命令加 `--check` | 生成器、本地化、locale 状态与双语布局测试 | Android 构建；macOS iOS 构建并核对系统语言切换 |
| SVG 图标字体 | `assets/icons` 清单/SVG/许可证、生成 OTF 与 `TemplateIcons` | `dart run tool/generate_icon_font.dart`；随后同命令加 `--check` | 字体生成器、真实 OTF 像素和消费页面测试 | Android/iOS 构建并核对字体打包和实际字形 |
| 认证 | `features/auth`，应用层组装 gateway、会话、路由策略与安全存储 | 无生成产物；默认 gateway 失败关闭，测试/架构门禁防契约漂移 | `flutter test test/features/auth`、认证路由与网络契约 | Android Keystore、iOS Keychain、进程恢复和真实服务协议需项目设备验证 |
| 品牌 | `assets/branding`、两份根配置与公共 Android/iOS 原生产物 | `dart run tool/generate_branding.dart`；随后同命令加 `--check` | 品牌生成器与平台门禁 | Android/iOS 构建；设备核对图标蒙版及明暗启动画面 |
| Agent 指南 | 固定 base/Goal Mode 模板；下游根目标 `AGENTS.md` | 下游先运行无参数初始化，再运行 `--check`；模板仓库改跑专项临时项目测试 | `flutter test test/tool/generate_agents_test.dart` | 不涉及应用平台；检查 UTF-8/LF、非覆盖、完整 Goal Mode 和零写入 |

“无生成产物”不是省略验证。手机适配依赖尺寸/语义测试，认证依赖状态、并发、安全存储、网络和
路由测试；二者都必须继续通过架构门禁及适用平台构建。

## 新项目采用顺序

完整模板已经启用六项能力。将模板复制为新项目或恢复缺失产物时，按固定顺序操作：

1. 完成项目名、包名、展示名和三环境配置，确认示例文件只含不可用占位值。
2. 解析锁定依赖，核对 `TemplateApp` 根适配与三环境启动；不要先改 Feature 页面绕过根初始化。
3. 先生成国际化，再生成 SVG 字体，最后生成品牌原生产物。后一步可能触发 Flutter 编译或读取
   前一步的注册信息，固定顺序更容易定位漂移。
4. 新的下游项目仅在根 `AGENTS.md` 不存在时执行 Agent 初始化；模板仓库根规范或已有用户文件
   不得覆盖。认证默认保持未配置，只有明确实现真实 `AuthGateway` 和协议测试后才接服务端。
5. 执行全部只读检查、格式、分析和测试，再构建平台。生成失败时保留最后一套已验证产物，不
   手改生成文件制造暂时通过。

资源生成顺序：

```bash
dart run tool/generate_localizations.dart
dart run tool/generate_icon_font.dart
dart run tool/generate_branding.dart
```

下游根目标不存在时才执行：

```bash
dart run tool/generate_agents.dart
dart run tool/generate_agents.dart --check
```

当前模板仓库不执行上面两条 Agent 根目标命令；它通过临时项目专项测试验证相同契约。

## 运行与完整质量顺序

使用一个不依赖真实服务的 dev 配置运行：

```bash
flutter run --flavor dev --dart-define-from-file=config/dev.example.json
```

本地 CI 等价质量顺序必须与 `.github/workflows/quality.yml` 保持一致：

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

随后再执行默认顺序 `flutter test`。文档门禁只读取 Markdown、项目路径和 workflow：它检查本地
链接/锚点、命令引用目标、六份专题入口、安全示例，以及上面质量命令与 CI 的顺序，不访问外网
也不修改文档。

## 平台构建

Android 至少构建一个受影响环境；SDK、插件、字体、品牌或平台配置变化时构建全部环境。dev
示例命令是：

```bash
flutter build apk --debug --flavor dev \
  --dart-define-from-file=config/dev.example.json
flutter build appbundle --debug --flavor dev \
  --dart-define-from-file=config/dev.example.json
```

iOS 只在 macOS 执行：

```bash
flutter build ios --debug --no-codesign --flavor dev \
  --dart-define-from-file=config/dev.example.json
```

把命令中的两个 `dev` 成对替换为 `staging` 或 `prod`。平台构建证明编译和资源接线，不证明
键盘、SafeArea、文字缩放、Keystore/Keychain、图标蒙版、启动画面或真实认证协议；这些行为仍
需要代表性模拟器/真机证据。release 签名有意不在模板中提供。

## 升级与生成产物迁移

版本升级遵守“一次一个直接依赖，生成器按不可分割组合处理”：

1. SDK/CI pin 单独升级并先稳定依赖求解；随后分别处理运行时 adapter。认证没有新增包，但
   Riverpod、路由、网络、安全存储或日志任一升级都要重跑认证跨边界测试。
2. `icon_font_generator/xml/yaml` 是一组字体生成输入；
   `flutter_launcher_icons/flutter_native_splash/image` 是一组品牌生成输入。组内版本、wrapper、
   锁文件和产物必须共同验证与回滚。
3. 在可恢复工作区记录旧输入、产物哈希、测试和平台构建。先在临时副本用新工具连续生成两次，
   检查字节确定性、白名单、codepoint/schema、平台引用和包体，再安装到主工作区。
4. 迁移生成物时固定使用“国际化 -> SVG 字体 -> 品牌”的顺序。生成后执行所有 `--check`；Agent
   模板随 Dart SDK 变化时运行专项测试，不覆盖已有下游规范。
5. 失败时恢复依赖约束、锁文件、wrapper、人工输入、全部生成输出、CI 与文档。已发布的 locale
   偏好、字体 codepoint、认证 envelope 或路由不能因工具回滚而失去兼容读取/清理路径。

完整版本判断、聚焦测试矩阵和 SDK 回滚步骤见[依赖与 SDK 升级指南](dependency-upgrades.md)。

## 安全替换与裁剪顺序

裁剪前先保存完整门禁和至少一个目标平台构建基线。每项能力都先解除消费者和迁移持久化数据，
再删除实现、依赖、生成物与 CI；禁止反向删除第一阶段 `core/` 契约来消除编译错误。

| 能力 | 安全替换或删除顺序 | 必须保留的第一阶段边界 |
| --- | --- | --- |
| 手机适配 | 替换时只改 `app_screen_adaptation.dart` 内部并保留 `du/dsp`；回退固定逻辑像素时先让比例变为 1:1，再迁移调用方，最后删除插件/根包装 | SafeArea、键盘避让、短屏滚动、触控目标、主题和普通页面仍可独立工作 |
| 国际化 | 新方案先在应用层提供等价类型安全文案/格式化与 locale 持久化迁移，迁完调用方再删 ARB、生成器、依赖和 iOS 声明 | Feature 不反向依赖 `app/`；错误仍按稳定 code 映射，普通偏好只精确清理 locale 键 |
| SVG 字体 | 替换生成器时保持 family、已有 codepoint、清单与 `TemplateIcons` 契约；完全删除前先迁移所有图标调用方，再删 OTF、工具和注册 | 普通 `AppAssets`/SVG、主题、路由与 Feature 不依赖生成器内部；已发布 PUA 不复用 |
| 认证 | 优先只替换应用层 `AuthGateway`；改用另一认证方案时先迁移/精确清理 `auth.session`、网络凭据和受保护路由，再删除当前 Feature | `NetworkClient` 默认不重试，普通/安全存储接口、公开路由和日志脱敏继续成立 |
| 品牌 | 新工具先在临时副本生成并证明公共平台引用等价；删除生成能力前选定并保留一套有效 AppIcon/LaunchScreen，再删源、wrapper 和 CI | 包名、环境、签名和其他用户资源不随品牌工具删除；三个环境继续使用明确资源 |
| Agent 指南 | 替换工具必须维持固定目标、非覆盖、只读检查、中文规范和完整 Goal Mode；删除生成器默认保留已生成的下游 `AGENTS.md` | 应用运行、依赖、原生工程和用户已维护规范都不由工具拥有 |

裁剪完成后至少运行本文完整质量顺序和适用平台构建。最终检查：`app/core/features/shared` 依赖
方向不变；公开首页可启动；路由、网络、普通/安全存储、错误与日志底座仍通过；示例 Feature
仍能按 ADR 0011 单独删除；文档与 CI 不再声称已删除能力存在。

## 常见故障入口

| 现象 | 首要动作 |
| --- | --- |
| `L10N_*` | 保留已验证生成目录，核对 ARB、固定配置和遗留构建缓存，按[国际化指南](internationalization.md)恢复 |
| `ICON_FONT_*` | 停止手改产物，核对清单、许可证和退休槽；回滚失败时从工具保留备份恢复 |
| `BRANDING_*` | 先修复源图/权利/白名单；事务回滚失败时停止生成并按错误路径恢复整组文件 |
| `AGENTS_*` | 保留用户根规范；缺失时显式初始化，过期时人工合并，不使用 force |
| 适配溢出或 Insets 翻倍 | 检查裸设计值、重复 SafeArea/键盘消费和主滚动所有权，不关闭文字缩放 |
| 登录不可用或重复 401 | 默认 gateway 本来就失败关闭；真实实现核对基础客户端、同一 session generation、幂等和安全存储 |
| `DOC_*` | 运行文档门禁，按项目相对路径修复链接/命令；质量顺序变化时同步 README、本文、workflow 和 ADR |

更完整的环境、构建和第一阶段故障诊断见[常见问题与诊断](troubleshooting.md)。
