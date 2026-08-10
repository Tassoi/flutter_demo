# Flutter Template

一个面向 Android 和 iOS 的 Flutter 工程脚手架。它提供可直接运行、测试和继续开发的工程底座，
不预先假定具体业务，也不需要任何第二阶段可选能力才能启动。

默认应用使用内置的中立示例数据，不会访问 `config/` 中的 `.invalid` 地址。示例 Feature
可以整体删除，网络、存储、路由、日志和错误等基础设施仍可独立使用。

## 当前基线

| 项目 | 已验证值 | 说明 |
| --- | --- | --- |
| Flutter | 3.29.0 stable，revision `35c388afb57ef061d06a39b537336c87e0e3d1b1` | CI 精确固定；`pubspec.yaml` 只承诺 `>=3.29.0 <3.30.0` |
| Dart | 3.7.0 | 由上述 Flutter SDK 携带；支持范围 `>=3.7.0 <3.8.0` |
| Android | platform 36、build-tools 35.0.1、NDK 27.0.12077973、min SDK 23 | JDK 21 已用于实际构建；项目 Java/Kotlin bytecode 目标为 11 |
| iOS | iOS 12.0、Xcode 16.2、CocoaPods 1.16.2 | 只能在 macOS 构建；当前主机尚无真实 iOS 编译证据 |
| 环境 | `dev`、`staging`、`prod` | Flutter flavor 和 `APP_ENV` 必须成对且完全一致 |

完整选型证据、许可证、替代方案和主要权衡见
[ADR 0001](docs/architecture/0001-technology-baseline.md)。

## 创建业务项目与重命名

本仓库已经是成品模板，不应在其根目录重新执行 `flutter create .`。Flutter 官方
`--project-name`、`--org`、`--description`、`--platforms` 和 `--empty` 参数用于在独立空目录
验证项目初始化；采用本模板时，应先创建新的仓库副本，再同步修改 Dart 包名、三环境展示名、
Android namespace/application ID、MainActivity package、iOS bundle identifier、平台门禁、
测试和文档。

当前第一阶段只维护并验证 Android+iOS 组合。项目名/组织名的官方派生规则、完整逐文件重命名
清单、目标平台裁剪边界、验收命令和成组回滚方式见
[项目初始化与产品标识配置](docs/project-initialization.md)。

## 环境准备

### 通用工具

1. 安装 Git 和 Flutter 3.29.0 stable，并确保 `flutter` 与 `dart` 可在终端中执行。
2. 安装 Android Studio 或等价 Android SDK 工具链，准备 platform 36、build-tools
   35.0.1 和 NDK 27.0.12077973，并接受 Android licenses。
3. 构建 iOS 时使用 macOS，安装 Xcode 16.2 和 CocoaPods 1.16.2。Linux 或 Windows
   不能代替这一平台验证。
4. 在仓库根目录核对实际环境：

```bash
flutter --version
dart --version
flutter doctor -v
```

`flutter doctor -v` 中与本项目无关的 Web/desktop 提示不影响 Android/iOS 基线，但
Android toolchain 错误必须先修复。

### 当前 WSL 工作站

本机 Flutter SDK 位于 Windows 文件系统，其 Bash 入口使用 CRLF。在 WSL 直接执行
`flutter` 可能出现 `bash\r` shebang 错误；不要为本项目改写全局 SDK，使用 Windows
批处理入口：

```bash
/mnt/c/Windows/System32/cmd.exe /d /c flutter --version
/mnt/c/Windows/System32/cmd.exe /d /c flutter pub get --enforce-lockfile
/mnt/c/Windows/System32/cmd.exe /d /c flutter test
```

其他 Windows 终端、macOS、Linux 和 CI 使用普通 `flutter` / `dart` 命令。

## 首次运行

本仓库已经是完整 Flutter 应用，不需要在工作区重新执行 `flutter create`。获取代码后：

```bash
flutter pub get --enforce-lockfile
flutter run --flavor dev --dart-define-from-file=config/dev.example.json
```

第二条命令需要已连接的 Android/iOS 设备或已启动的模拟器。没有设备时可先执行
Android Debug 构建，确认工具链和工程可用：

```bash
flutter build apk --debug --flavor dev \
  --dart-define-from-file=config/dev.example.json
```

首屏展示一个中立示例入口。进入详情后，bundled Repository 返回本地确定性数据，
不要求真实 API、凭据或存储插件初始化。

## 三环境配置

| 环境 | flavor | 示例文件 | Android application ID | iOS bundle identifier | 展示名 |
| --- | --- | --- | --- | --- | --- |
| 开发 | `dev` | `config/dev.example.json` | `com.example.flutter_template.dev` | `com.example.flutterTemplate.dev` | Flutter Template Dev |
| 预发布 | `staging` | `config/staging.example.json` | `com.example.flutter_template.staging` | `com.example.flutterTemplate.staging` | Flutter Template Staging |
| 生产 | `prod` | `config/prod.example.json` | `com.example.flutter_template` | `com.example.flutterTemplate` | Flutter Template |

运行其他环境时，flavor 与 define 文件必须使用同一行：

```bash
flutter run --flavor staging \
  --dart-define-from-file=config/staging.example.json
flutter run --flavor prod \
  --dart-define-from-file=config/prod.example.json
```

需要本机 API 地址时，复制而不要直接修改示例文件：

```bash
cp config/dev.example.json config/dev.local.json
```

PowerShell 使用 `Copy-Item config/dev.example.json config/dev.local.json`。根 `.gitignore` 忽略
`config/*.json` 并只放行 `*.example.json`。本地文件可修改 `API_BASE_URL`，但仍不得放入 API
key、Token、密码、证书、私钥、签名数据或长期凭据，因为 Dart define 会进入应用二进制。

dev/staging 的 Dart 配置模型可以描述 HTTP 地址，但模板不会全局关闭 Android Network Security
或 iOS App Transport Security。移动端本地服务默认也应提供 HTTPS；具体项目确需明文调试时，
只能为明确开发环境和目标主机增加最小平台例外，并同步增加原生配置测试，不能提交全局放行。

`APP_ENV` 仅接受精确小写的三个值。缺失、未知、大小写错误、前后空格或与 flavor
不一致都会在依赖组装前失败，并进入不显示原始值的安全启动页。详细规则见
[Dart 配置说明](config/README.md) 和 [ADR 0013](docs/architecture/0013-mobile-environment-builds.md)。

## 工程结构与依赖方向

```text
lib/
├── main.dart                     # 最小平台入口
├── app/                          # 配置、启动、路由、主题和全局组装
├── core/                         # 错误、日志、网络和存储基础设施
├── features/                     # 按业务能力纵向组织的 Feature
└── shared/                       # 无业务语义的跨 Feature 资源、设计值和组件
assets/                          # 已登记的本地静态资源
config/                          # 可提交示例和已忽略本机配置
test/                            # 镜像 lib 边界的单元/Widget 测试与测试替身
tool/ci/                         # 当前工程专用的质量门禁
docs/architecture/              # 已接受的架构决策记录
```

依赖方向为：

1. `app/` 可组装 `core/`、`features/` 和 `shared/`。
2. Feature 只依赖项目自有的 `core/`/`shared/` 公开契约，不引用 `app/` 或其他
   Feature 内部实现。
3. `core/` 与 `shared/` 不得反向依赖 `app/` 或具体 Feature。
4. Dio、go_router、shared_preferences、flutter_secure_storage、logging 和 flutter_svg 类型
   限制在各自适配边界；业务层使用项目类型。

`dart tool/ci/check_architecture.dart` 会自动检查这些规则。目录内更细的所有权说明见
[`app`](lib/app/README.md)、[`core`](lib/core/README.md)、[`features`](lib/features/README.md) 和
[`shared`](lib/shared/README.md)。

## 默认技术选择

| 能力 | 唯一默认实现 | 锁定版本 | 实现边界 |
| --- | --- | --- | --- |
| 状态管理 | Riverpod | 2.6.1 | 根 ProviderScope 属于 `app/`，Feature provider 仅位于 presentation |
| 声明式路由 | go_router | 17.0.0 | 唯一 Router 位于 `app/router/` |
| 网络 | Dio | 5.11.0 | Dio 只存在于 `core/network` adapter |
| 普通存储 | shared_preferences | 2.5.3 | 只使用 `SharedPreferencesAsync` adapter |
| 安全存储 | flutter_secure_storage | 10.3.1 | 平台选项和异常只存在于 `core/storage` adapter |
| 日志 | package:logging | 1.3.0 | 项目 logger/redactor/sink 位于 `core/logging` |
| 普通 SVG | flutter_svg | 2.2.2 | 类型安全入口位于 `shared/assets` |

每类能力仅保留一套默认方案，不启用 Riverpod/go_router 代码生成，也不引入独立
DI 容器。具体决策见 [架构决策索引](#架构决策索引)。

## 测试与质量门禁

常规开发中至少执行受影响的单文件测试，交付前执行完整 CI 等价顺序：

```bash
dart tool/ci/check_generated_files.dart
flutter pub get --enforce-lockfile
dart tool/ci/check_architecture.dart
dart tool/ci/check_platform_environments.dart
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos --fatal-warnings
flutter test --test-randomize-ordering-seed=20260809
```

还应执行默认顺序全量测试，确保常用入口同样通过：

```bash
flutter test
```

针对性示例：

```bash
flutter test test/core/network/network_contract_test.dart
flutter test test/features/example/presentation/example_detail_controller_test.dart
flutter test test/tool/ci
```

测试不使用真实网络、真实密钥、文件系统、系统时钟或无依据延时。覆盖矩阵、Fixture、
Widget 帧策略和覆盖率使用边界见 [测试基础设施](test/README.md)。CI 的权限、缓存、固定版本
和生成产物规则见 [ADR 0012](docs/architecture/0012-code-quality-and-ci.md)。

## 平台构建

### Android

构建命令始终显式选择环境。以 dev 为例：

```bash
flutter build apk --debug --flavor dev \
  --dart-define-from-file=config/dev.example.json
flutter build appbundle --debug --flavor dev \
  --dart-define-from-file=config/dev.example.json
```

把命令中的两个 `dev` 同时替换为 `staging` 或 `prod` 即可构建其他环境。不传
`--flavor` 会在 Gradle 配置阶段、任何 flavor 依赖执行前明确失败，防止一份 Dart define
错配多个原生环境，也不会改写已有的正确环境产物。

模板的 release signing 有意留空，不包含 Keystore、密码或可发布配置。未先在版本控制外
配置真实签名时，不得把该模板产物当作可发布包。

### iOS

仅在 macOS 执行：

```bash
flutter build ios --debug --no-codesign --flavor dev \
  --dart-define-from-file=config/dev.example.json
```

同样将两个 `dev` 成对替换为 `staging` 或 `prod`。三个 scheme 分别绑定定制的
Debug/Profile/Release configuration；不存在通用 Runner scheme。当前仓库已通过静态门禁和
XML/PBX 审计，但当前非 macOS 开发主机无法提供 CocoaPods/Xcode 真实编译证据，这一缺口
必须由首次 macOS CI 或 macOS 开发机补证。

## 示例 Feature 与裁剪

`lib/features/example/` 是一条中立纵向切片，展示领域模型、bundled/网络 Repository、Riverpod
异步状态、取消、错误映射、路由参数和共享状态组件的协作方式。

完整删除时需要同步清理两个 production 注册点：

1. `lib/app/bootstrap/app_bootstrap.dart` 中的 bundled Repository override。
2. `lib/app/router/app_router.dart` 中的详情路由、首页入口和包装页。

然后删除 Feature 源码、测试和对应应用断言，重新执行格式、分析与全量测试。逐文件清单和
网络实现替换的资源所有权见 [ADR 0011](docs/architecture/0011-removable-example-feature.md)。

Task 17 已在隔离临时副本实际执行上述删除：裁剪后的生成/架构/平台门禁、格式、严格分析和
167 项剩余全量测试通过，并成功构建 dev Debug APK。该验收没有删除主工作区中的示例，因此
新项目仍可先阅读纵向切片，再按清单完整移除。

## 依赖升级与回滚

不要直接执行无审查的全量 major 升级。本项目的基本规则是：

1. Flutter/Dart、CI 完整 revision 和平台工具链作为一个 SDK 基线升级。
2. 每次只升级一个直接依赖或一组不可分割的 SDK 输入，先读 changelog/migration 并审查
   许可证、平台下限和锁文件 diff。
3. `pub outdated` 的 Current、Upgradable、Resolvable 和 Latest 含义不同；Latest 不等于当前
   SDK 或现有代码可安全使用。
4. 先执行影响能力的聚焦测试，再执行全部门禁和三环境平台构建。
5. 失败时同时恢复 `pubspec.yaml`、`pubspec.lock`、SDK/CI pin 和受影响平台输入，
   不得只手工改锁文件。

完整步骤、每个依赖的验证矩阵、`.metadata` 语义、存储迁移及可恢复回滚见
[依赖与 SDK 升级指南](docs/dependency-upgrades.md)。

## 常见问题

| 现象 | 首先检查 |
| --- | --- |
| `An environment flavor is required` | 命令是否包含 `--flavor dev/staging/prod` |
| 应用只显示安全启动失败页 | flavor 与 JSON 中 `APP_ENV` 是否精确一致 |
| `GENERATED_LOCK_STALE` | `pubspec.yaml` 与 `pubspec.lock` 是否在同一次升级中生成 |
| WSL 报 `bash\r` | 是否按上文使用 Windows `cmd.exe` 入口 |
| Android SDK/NDK 构建失败 | `flutter doctor -v` 和基线版本是否齐备，licenses 是否接受 |
| iOS Pods/xcconfig 失败 | 是否使用 macOS、Xcode 16.2、CocoaPods 1.16.2 及对应 scheme |
| release 构建缺少签名 | 这是安全默认；必须在版本控制外配置真实项目签名 |

完整症状、原因、命令和不应采取的规避方式见 [常见问题与诊断](docs/troubleshooting.md)。

## 架构决策索引

| ADR | 主题 |
| --- | --- |
| [0001](docs/architecture/0001-technology-baseline.md) | Flutter 工具链、依赖选型、许可证和替代方案 |
| [0002](docs/architecture/0002-project-boundaries-and-environments.md) | 目录边界与 Dart 环境配置 |
| [0003](docs/architecture/0003-application-bootstrap.md) | 集中启动顺序与失败策略 |
| [0004](docs/architecture/0004-application-errors-and-structured-logging.md) | 稳定错误、结构化日志与脱敏 |
| [0005](docs/architecture/0005-network-infrastructure.md) | 项目网络契约、Dio adapter、取消与凭据边界 |
| [0006](docs/architecture/0006-local-storage.md) | 普通/安全存储、命名空间、平台安全与迁移 |
| [0007](docs/architecture/0007-theme-and-type-safe-assets.md) | 主题、排版、设计值与类型安全资源 |
| [0008](docs/architecture/0008-basic-state-and-feedback-widgets.md) | 加载/空/错误状态、确认对话框与消息反馈 |
| [0009](docs/architecture/0009-declarative-routing.md) | 声明式路由、嵌套导航、参数和重定向 |
| [0010](docs/architecture/0010-state-management-and-async-lifecycle.md) | Riverpod 状态边界、重试、取消与迟到结果 |
| [0011](docs/architecture/0011-removable-example-feature.md) | 可删除示例、网络替换和完整裁剪清单 |
| [0012](docs/architecture/0012-code-quality-and-ci.md) | 严格 lint、架构/生成门禁和最小权限 CI |
| [0013](docs/architecture/0013-mobile-environment-builds.md) | Android/iOS 三环境、签名边界与平台构建 |

## 验证状态与明确缺口

- 当前工作站已通过格式、严格分析、全量测试、生成产物、架构和三环境静态门禁。
- Flutter 官方 Android/iOS 空工程初始化参数已在隔离目录验证；成品模板的重命名映射已有
  可执行文档。
- 示例 Feature 已在隔离副本物理删除，剩余底座严格分析、167 项测试和 dev Android 构建通过。
- dev、staging、prod 的 Android Debug APK 和 AAB 均已实际构建。
- 当前没有 Android 设备或模拟器，因此尚无并存安装、真机启动、插件通道、触摸或
  TalkBack 证据。
- 当前主机不是 macOS，GitHub Actions 也尚未触发；CocoaPods 集成、Xcode 编译、
  Keychain 与 VoiceOver 仍是明确的 iOS 平台验证缺口。
- release 签名有意缺省，模板当前不能直接发布。

可选第二阶段见 [phase-2 plan](docs/phase-2-plan.md)；可选多产品 Workspace 见
[phase-3 plan](docs/phase-3-plan.md)。两者都不是当前默认脚手架的运行前置。
