# Flutter Template

一个面向 Android 和 iOS 的 Flutter 工程脚手架。它提供可直接运行、测试和继续开发的工程底座，
不预先假定具体业务。第二阶段的手机适配、国际化、SVG 图标字体、认证边界、品牌资源生成与
基础 Agent 指南初始化/只读检查已经启用；认证默认不连接真实服务，这些增强能力不会成为
应用启动对外部服务的依赖。

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
├── app/                          # 配置、启动、国际化、路由、主题和全局组装
├── core/                         # 错误、日志、网络和存储基础设施
├── features/                     # 按业务能力纵向组织的 Feature
└── shared/                       # 无业务语义的跨 Feature 资源、设计值和组件
assets/                          # 普通资源、图标/品牌源、许可证与生成字体
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
4. Dio、go_router、shared_preferences、flutter_secure_storage、logging、flutter_svg、
   flutter_screenutil 与国际化工具类型限制在各自适配/生成边界；`icon_font_generator`、
   `xml`、`yaml`、`flutter_launcher_icons`、`flutter_native_splash`、`image` 只能存在于仓库
   工具，业务层只使用生成的项目类型或平台资源。

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
| 手机设计单位 | flutter_screenutil | 5.9.3 | 插件仅位于 `shared/layout` adapter，调用方使用项目 `du/dsp` |
| 国际化 | Flutter gen-l10n + intl | SDK + 0.19.0 | ARB 位于 `app/localization`，生成产物提交并由专项工具检查 |
| SVG 图标字体 | icon_font_generator + xml/yaml | 4.0.0 + 6.5.0/3.1.3 | 仅 `tool/generate_icon_font.dart` 使用；应用只打包生成 OTF |
| 认证 | 项目接口 + 现有 Riverpod/路由/网络/安全存储 | 不增加依赖 | `features/auth` 拥有会话，`app` 组装安全存储、重定向与默认未配置 gateway |
| 品牌资源 | flutter_launcher_icons + flutter_native_splash + image | 0.14.4 + 2.4.6 + 4.8.0 | 仅专项工具使用；源图不注册为 runtime assets，三环境共用原生产物 |
| 基础 Agent 指南 | Dart 标准库 + 固定 Markdown 模板 | 不增加依赖 | 初始化和 `--check` 只操作固定根目标；已有不同内容时拒绝覆盖 |

每类能力仅保留一套默认方案，不启用 Riverpod/go_router 代码生成，也不引入独立
DI 容器。具体决策见 [架构决策索引](#架构决策索引)。

## 移动端设计单位

应用根节点使用唯一 `375 x 812` 参考设计尺寸。位于 `TemplateApp` 下方的 Widget 通过项目
扩展读取单位，不直接使用 `flutter_screenutil`：

```dart
final horizontalPadding = context.du(16);
final titleSize = context.dsp(20);
```

`du` 对宽度、高度、间距、圆角和图标统一应用“当前逻辑宽度 / 375”的比例；`dsp` 应用相同
设计比例后，仍由 Flutter 按用户的系统文字设置继续缩放。`SafeArea`、状态栏、系统手势区和
键盘 `viewInsets` 已经是系统逻辑像素，不得再次传入 `du`。

`AppSpacing` 与 `AppRadii` 保存的是参考稿源值，不是可以直接交给普通页面的最终逻辑像素；
主题、共享组件和 Feature 使用时都通过 `context.du(...)` 换算。正常亮暗主题必须在
`AppScreenAdaptation` 的 builder context 中调用 `AppTheme.light(context)` / `dark(context)`；
只有不依赖任何正常初始化结果的启动失败页使用明确的 1:1 fallback 主题。触控目标在缩放后
仍以 Flutter 逻辑 `48` 像素为下限，不会在窄屏缩小到无障碍建议值以下。

普通表单或详情页可以使用项目的安全滚动壳层。它拥有 `Scaffold` 和页面主滚动，调用方不要
再包一层 `SafeArea`，也不要手工追加键盘高度：

```dart
return AppSafeScrollableScaffold(
  contentPadding: EdgeInsets.all(context.du(16)),
  content: const ExampleContent(),
  bottomAction: const ExamplePrimaryAction(),
);
```

短屏、大字体或键盘出现时，正文和主要操作保持可滚动到达；状态栏、横屏侧边、底部手势区和
键盘 Insets 始终使用 Flutter 报告的原始逻辑值。海报或活动视觉确实需要固定坐标画布时，才
使用 `AppFixedVisualCanvas` 并明确选择 `contain` 留白或 `cover` 裁切；它不会处理 SafeArea，
也不能替代表单、列表和普通页面布局。根适配与可复用布局基线已经启用，现有主题 token、
共享组件、路由页面和示例详情已经统一接入该边界，不存在直接导入插件的 Feature 实现。
设计交付、单位边界、六档验收、底层替换和固定逻辑像素回退见
[移动端屏幕适配指南](docs/mobile-screen-adaptation.md)。

## 国际化

当前真实维护 `en` 与 `zh`，默认跟随系统，无法匹配时回退英语。首页可在不重启和不重置导航的
情况下切换语言；显式选择通过普通偏好保存，选择跟随系统会删除显式值。复数、日期和数字由
生成实例按自身 locale 格式化，不使用全局 `Intl.defaultLocale`。

固定配置位于 `lib/app/localization/l10n.yaml`；根目录不得新增同名文件，否则 Flutter 3.29
会在普通测试或构建时绕过中文注释归一化并覆写产物。修改配置或
`lib/app/localization/arb/` 后必须通过专项工具生成并检查：

```bash
dart run tool/generate_localizations.dart
dart run tool/generate_localizations.dart --check
```

生成器在临时目录调用官方工具，拒绝缺失翻译、输出漂移与未知英文生成注释，再整体更新必须
提交的产物。Feature 不导入应用生成类，应用层通过职责具体的文案模型注入。新增语言、iOS
声明、失败策略、测试、完整删除和回滚步骤见[国际化指南](docs/internationalization.md)。

## SVG 图标字体

适合单色语义图标且许可证明确的 SVG 维护在 `assets/icons/svg/`。人工清单
`assets/icons/icon_font_manifest.json` 保存名称、状态、许可证和稳定 PUA codepoint；
`nextCodepoint` 只能前移，删除图标必须保留 `retired` 槽，避免以后复用历史编号。普通插图、
多色或动态 SVG 仍由 `AppAssets`/`flutter_svg` 处理，不进入字体。

修改 SVG、清单或许可证后运行：

```bash
dart run tool/generate_icon_font.dart
dart run tool/generate_icon_font.dart --check
```

工具先验证固定 24x24 `path` 结构、清单、重复项、许可证、依赖和字体注册，再生成
`assets/fonts/template_icons.otf` 与中文
`lib/shared/assets/generated/template_icons.g.dart`。OTF 时间和年份被结构化归一化并重算校验和；
两个输出通过带备份的事务替换，`--check` 只在系统临时目录构建期望字节。应用通过
`TemplateIcons` 使用活动图标，不手改任一生成文件。添加、退休、重命名、工具升级、异常恢复、
平台验证和完整删除见 [SVG 图标字体指南](docs/svg-icon-font.md)。

## 认证

认证模块提供登录、退出、安全 envelope、启动恢复、访问凭据注入、单飞刷新、会话失效和同步
路由重定向。默认 `UnconfiguredAuthGateway` 不访问 `.invalid` 地址、不接受本地账号，也不生成
伪凭据；公开首页和原有示例仍可直接运行。首页的受保护区域入口用于展示恢复、登录和重定向
协作，真实项目必须在应用组装层替换自己的 gateway 后才可能登录成功。

敏感 access/refresh credential 只在 gateway、认证 data/controller 和单次网络发送的受控边界
中流转，持久化只使用 `SecureValueStore` 的单一 `auth.session` envelope；它们不进入普通偏好、
公开 Riverpod 状态、日志、错误或可提交配置。
同一会话代次的并发 401 只触发一次 refresh；默认只自动重放 GET，其他方法必须显式证明幂等，
且每个请求最多重放一次。退出、失效和 Provider 销毁会取消旧工作，迟到结果不能恢复会话。

接入真实后端时，登录/刷新 gateway 必须使用未包装的基础 `NetworkClient`，普通受保护业务请求
再通过 `SessionCredentialProvider` 和 `AuthenticatedNetworkClient` 注入/刷新凭据，避免 401
递归。完整组装、安全、schema、路由白名单、测试、删除与迁移见
[认证模块指南](docs/authentication.md)。

## 品牌资源

`assets/branding/` 当前包含一组权属明确的中性几何占位 PNG，只用于验证流程，不是下游项目的
正式品牌。完整图标、Adaptive 前景/背景、可选单色图和启动 Logo 使用固定 1024 方形契约；
透明图形还必须位于 Android 中心安全区。正式替换必须同步更新目录内 `LICENSE.md`。

修改源图、权利声明或两份根配置后运行：

```bash
dart run tool/generate_branding.dart
dart run tool/generate_branding.dart --check
```

工具在系统临时项目调用锁定的 launcher/splash 依赖，验证 73 个 Android/iOS 白名单输出后才
事务安装；`--check` 严格只读。`dev`、`staging`、`prod` 始终继承同一套 `src/main` 和 iOS
Catalog，不生成环境角标。输入尺寸、授权、正式替换、失败恢复、平台验证和完整删除见
[品牌资源生成指南](docs/branding.md)。

## 基础 Agent 指南生成

新项目可以从固定的 `tool/templates/AGENTS.base.md` 与
`tool/templates/partials/goal_mode.md` 初始化根 `AGENTS.md`：

```bash
dart run tool/generate_agents.dart
dart run tool/generate_agents.dart --check
```

生成内容使用 UTF-8/LF 中文正文，包含当前架构、命令、详细中文注释、测试、安全、Git、
手机适配和完整 Goal Mode。目标不存在时才创建；内容一致时不改 mtime；用户已修改或目标
类型异常时直接失败，不存在 `--force` 或命令行输出路径。当前仓库根规范是用户维护资产，
不得在这里运行初始化或把它当作下游生成结果检查；所有写入测试只使用系统临时目录。
`--check` 对下游目标严格只读，稳定区分缺失、过期、不可读和非法类型。仓库 Quality workflow
通过临时样例测试检查根规范、base、Goal Mode partial 和生成结果，防止屏幕/Goal 规则漂移。
完整契约、错误编号、模板维护和删除方式见[基础 Agent 指南生成](docs/agents-generation.md)。

## 第二阶段采用与裁剪

六项增强能力的环境准备、启用顺序、运行、生成、只读检查、测试、平台构建和常见故障统一见
[第二阶段采用、运维与裁剪指南](docs/phase-2-operations.md)。该指南也记录了每项能力的安全
替换/删除顺序和第一阶段不变量；裁剪时应先迁移消费者与持久化数据，再移除实现、依赖、生成物
和 CI，不能通过删除 `core/` 底座或关闭门禁消除编译错误。

## 测试与质量门禁

常规开发中至少执行受影响的单文件测试，交付前执行完整 CI 等价顺序：

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

还应执行默认顺序全量测试，确保常用入口同样通过：

```bash
flutter test
```

针对性示例：

```bash
flutter test test/core/network/network_contract_test.dart
flutter test test/features/example/presentation/example_detail_controller_test.dart
flutter test test/features/auth test/app/router/auth_app_route_redirect_policy_test.dart
flutter test test/shared/layout
flutter test test/tool/generate_icon_font_test.dart test/shared/assets/template_icons_test.dart
flutter test test/tool/generate_branding_test.dart
flutter test test/tool/generate_agents_test.dart
flutter test test/tool/ci/check_documentation_test.dart
flutter test test/app/mobile_ui_layout_matrix_test.dart
flutter test test/shared/widgets/app_widget_layout_matrix_test.dart
flutter test test/goldens/mobile_ui_golden_test.dart
flutter test test/tool/ci
```

测试不使用真实网络、真实密钥、文件系统、系统时钟或无依据延时。覆盖矩阵、Fixture、
Widget 帧策略和覆盖率使用边界见 [测试基础设施](test/README.md)。CI 的权限、缓存、固定版本
和生成产物规则见 [ADR 0012](docs/architecture/0012-code-quality-and-ci.md)。

手机布局矩阵对 `en/zh`、6 个视口分别执行正常与 200% 系统文字场景，并验证关键矩形、滚动
可达性、操作、语义和 LTR 方向。参考尺寸的 Flutter 原生 Golden 只在测试主题内使用 `Ahem`
固定字形度量，并对 Windows/Linux 采用分离的零容差像素基线；生产仍使用平台字体并保留系统
`TextScaler`。更新规则见
[Golden 基线说明](test/goldens/README.md)。

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

Task 17 已在隔离临时副本实际执行上述删除；Task 4 在主题、组件和页面完成手机适配后又重新
执行了一次物理裁剪。最新副本的生成/架构/平台门禁、格式、严格分析、固定随机种子和默认顺序
206 项剩余测试均通过，并成功构建 dev Debug APK。两次验收都没有删除主工作区中的示例，
因此新项目仍可先阅读纵向切片，再按清单完整移除。

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
| `L10N_OUTPUT_STALE` | 是否修改 ARB 后遗漏专项生成命令，或手改了生成文件 |
| `L10N_ROOT_CONFIG_FORBIDDEN` | 是否误把本地化配置放回仓库根目录；应使用 `lib/app/localization/l10n.yaml` |
| `L10N_LEGACY_BUILD_CACHE` | 从旧根配置迁移后先执行一次 `flutter clean`，再解析依赖并重新生成本地化产物 |
| 本地化生成报告模板漂移 | Flutter SDK 是否变化；审查模板后更新已知中文注释转换，不能关闭检查 |
| `ICON_FONT_OUTPUT_STALE` | 是否修改 SVG/清单/许可证后遗漏生成命令，或手改了 OTF/Dart 产物 |
| `ICON_FONT_NEXT_CODEPOINT` | 是否删除了历史条目或让 `nextCodepoint` 后退；应把原条目改为 `retired` |
| `ICON_FONT_ROLLBACK_FAILED` | 暂停生成，检查两个固定输出，并从 `.dart_tool/icon_font_*` 恢复保留备份 |
| `BRANDING_OUTPUT_STALE` | 是否修改品牌源/配置后遗漏生成命令，或手改了原生图标/启动资源 |
| `BRANDING_ROLLBACK_FAILED` | 停止生成，从错误点名的 `.dart_tool/branding_install_*` 备份按相对路径恢复 |
| `AGENTS_TARGET_EXISTS` | 根规范已存在且与模板不同；保留用户文件，通过普通 diff 人工合并，不得强制覆盖 |
| `AGENTS_TEMPLATE_MISSING` | 固定基础模板或完整 Goal Mode 局部模板是否缺失；恢复输入后再初始化 |
| `AGENTS_WRITE_FAILED` | 检查目录权限与目标类型；工具已清理本轮不完整目标，不要改用覆盖写入绕过 |
| `AGENTS_CHECK_MISSING` | 下游根指南尚未初始化；明确执行一次无参数命令，不要让检查隐式创建文件 |
| `AGENTS_CHECK_STALE` | 下游根指南与模板不同；保留项目规则并人工审查差异，不要强制重新生成 |
| `AGENTS_CHECK_UNREADABLE` | 修正目标权限或文件系统问题；检查不会把读取失败误当作可覆盖的陈旧文件 |
| `DOC_LINK_*` 或 `DOC_COMMAND_TARGET_MISSING` | 修复项目相对链接、锚点或命令目标；不要用构建缓存中的同名文件掩盖缺失路径 |
| `DOC_QUALITY_COMMAND_DRIFT` | 同步 README、阶段二操作指南、Quality workflow 和 ADR 中的执行顺序 |
| 登录始终显示服务不可用 | 模板默认 gateway 有意未配置；应在 composition root 注入项目 `AuthGateway`，不要加入本地账号 |
| 启动恢复显示认证存储失败 | 检查设备安全存储能力、schema 与插件配置；不得改用普通偏好或忽略损坏 envelope |
| 受保护请求反复 401 | 确认 gateway 未使用认证装饰器、客户端与 controller 属于同一会话、非 GET 是否确实声明幂等 |
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
| [0014](docs/architecture/0014-phase-2-technology-baseline.md) | 第二阶段 SDK 复核、依赖版本和六项增强能力边界 |

## 验证状态与明确缺口

- 当前工作站已通过 149 个 Dart 文件的格式检查、严格分析、固定随机种子与默认顺序各
  385 项全量测试，以及本地化、SVG 字体、品牌资源、锁文件、36 份工程文档、架构和三环境
  静态门禁；六档手机视口的正常/200% 文字矩阵和两张参考页面 Golden 同时通过。
- SVG 字体连续生成两次保持完全相同的 2280-byte OTF 与中文 Dart 映射；dev Debug APK 已
  确认打包同一份 OTF，字体测试和首页 Golden 均渲染真实字形而不是缺字方框。
- Flutter 官方 Android/iOS 空工程初始化参数已在隔离目录验证；成品模板的重命名映射已有
  可执行文档。
- 示例 Feature 已在适配后的隔离副本物理删除，剩余底座严格分析、206 项测试和 dev Android
  构建通过。Checkpoint B 又复核了国际化和字体增量：外部 production 引用仍只位于
  `app_bootstrap.dart` 与 `app_router.dart`，当前裁剪清单已包含 Router 新增的文案注入 import。
- 认证专项 70 项聚焦测试覆盖安全 envelope、登录/退出、启动恢复、单飞刷新、401 重放、
  调用方取消、跨账号 generation 竞态、路由白名单和窄屏大字体；默认 gateway 无网络且失败关闭。
  Checkpoint C 的 dev Debug APK 已实际构建，构建后全部生成产物检查保持通过。
- 品牌专项 10 项测试覆盖权利与 PNG/Alpha/安全区预检、可选单色图、两次真实上游生成的 73 文件
  字节一致性、未知 Catalog、输出父目录链接、只读漂移和注入安装失败后的整组恢复。Checkpoint C
  的 dev Debug APK 为 221,193,891 bytes，SHA-256 为
  `ca420d3609e09c72a662b3e11e29e9330a514f0987e2f19203fbb6a47b9e2ecb`；
  `aapt2` 已确认 Manifest、Adaptive/单色图层、旧版 splash 和 Android 12 明暗启动资源引用。
- Agent 指南专项 19 项测试全部在系统临时目录执行，覆盖完整 Goal Mode、UTF-8/LF、确定性、
  初始化非覆盖、`--check` 的匹配/缺失/过期/不可读/非法目标零写入，以及根规范、base、partial
  和临时样例四方漂移；根规范未被改写。
- dev、staging、prod 的 Android Debug APK 和 AAB 均已实际构建；`aapt2` 已核对三套包名、
  展示名和图标入口，APK/AAB 均包含同一份 SVG 字体及 Adaptive/单色图标、旧版和 Android 12
  启动资源，构建后全部生成检查继续通过。
- Android 15/API 35 x86_64 模拟器已实际验证冷启动品牌画面、launcher 图标、英文/中文切换与
  冷启动持久化、受保护路由、真实 IME、密码掩码和失败清理、横屏安全滚动、示例详情及日志
  脱敏；截图、UI 树和哈希清单保存在忽略目录 `build/device-evidence/`，测试包与数据随后已清理。
- 当前主机不是 macOS，GitHub Actions 也尚未触发；iOS 三套 scheme、九套构建配置、Bundle ID、
  `en/zh` 声明、25 个 AppIcon 槽位和 LaunchScreen 已通过静态门禁，但 CocoaPods/Xcode 编译、
  真实图标蒙版、启动画面、Keychain 与 VoiceOver 仍是明确的 iOS 平台验证缺口。
- release 签名有意缺省，模板当前不能直接发布。

第二阶段已完成基线决策、手机适配、国际化、SVG 图标字体、认证模块、品牌资源生成、基础
`AGENTS.md` 模板/检查、统一运维文档，以及 Task 12 的组合路径、设备和平台构建收敛；
Checkpoint A、Checkpoint B、Checkpoint C 与 Checkpoint D 均已通过，见
[phase-2 plan](docs/phase-2-plan.md)。Checkpoint D 重新执行完整质量顺序、三环境 Android Debug
APK 构建，并复核范围、架构、安全、设备、iOS 静态、文档、裁剪和回滚证据。Final Review
再次完成六项需求矩阵、最终 diff、两种顺序全量测试、三环境 Android 构建和设备/iOS 证据审查，
未发现待解决的已知高风险问题。第二阶段与当前通用单 App 脚手架已经完成阶段性交付；下一步
应从该稳定版本裁剪独立的公司基础模板。

多产品 Workspace 不在本仓库继续实施。完成第一个产品并开始第二个相关产品时，应在产品仓库
中单独规划 Workspace、公共模块和跨电脑归档，参考
[product family workspace guide](docs/product-family-workspace-guide.md)。
