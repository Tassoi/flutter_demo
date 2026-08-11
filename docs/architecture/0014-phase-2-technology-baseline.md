# ADR 0014：第二阶段技术基线与依赖决策

- 状态：Accepted
- 决策日期：2026-08-10
- 适用范围：第二阶段 Task 1，六项增强能力的实施前基线
- 前置决策：ADR 0001、0005、0006、0009、0010、0012、0013

## 背景与范围

第二阶段只实施国际化、SVG 转字体、认证、品牌资源生成、Android/iOS 手机屏幕
适配和基础 `AGENTS.md` 生成。第一阶段已经为状态管理、路由、网络、安全存储、
错误和日志建立项目自有边界，第二阶段必须复用这些边界，不能借增强能力引入第二套
架构或通用代码生成平台。

本 ADR 固定后续任务共同使用的 SDK、依赖版本、输入/输出契约和替换边界。它只记录
Task 1 的验证与决策，不表示依赖已经加入 `pubspec.yaml`，也不表示任一第二阶段功能
已经实现。功能、配置、生成产物和专项测试必须在 `goal-2/tasks.md` 对应后续任务中
逐项交付并重新验证。

## 当前工程基线

### 工具链与平台

2026-08-10 在当前工作区重新核对的基线为：

```text
Flutter 3.29.0 stable，framework revision 35c388afb5
Dart 3.7.0
Android SDK tools 35.0.1，platform android-36，build-tools 35.0.1
Android Studio bundled JBR 21.0.4
```

`pubspec.yaml` 继续只支持 Dart `>=3.7.0 <3.8.0` 与 Flutter
`>=3.29.0 <3.30.0`。Android licenses 已全部接受，dev Debug APK 可以实际构建。
Task 1 复核时没有 Android 设备或模拟器，因此当时没有设备启动、触摸、系统安全区或插件
通道证据。Checkpoint A 后续检测到一个 Android 15 模拟器，但尚未执行对应设备自动化，
不能用“设备已连接”替代行为证据；当前主机不是 macOS，因此不能声称 iOS 已实际构建。

当前 WSL 会话仍须通过 Windows 批处理入口调用 Flutter/Dart，因为全局 SDK 的 Bash
入口使用 CRLF。该工作站差异不进入项目实现：

```bash
cmd.exe /d /c flutter <arguments>
cmd.exe /d /c dart <arguments>
```

### 已锁定依赖与架构不变量

Task 1 开始时的直接运行时依赖仍为：

| 能力 | 已锁定版本 | 第二阶段必须维持的边界 |
| --- | --- | --- |
| 状态管理 | `flutter_riverpod 2.6.1` | Riverpod 仍是唯一状态所有者，不增加第二套状态方案 |
| 路由 | `go_router 17.0.0` | go_router 只由 `app/router` 使用，Feature 不导入插件类型 |
| 网络 | `dio 5.11.0` | Dio 只留在 `core/network` adapter，认证复用 `NetworkClient` |
| 安全存储 | `flutter_secure_storage 10.3.1` | 认证只依赖 `SecureValueStore`，不得直接使用插件 |
| 普通存储 | `shared_preferences 2.5.3` | 仅保存 locale 等非敏感偏好，不保存任何凭据 |
| 日志 | `logging 1.3.0` | Token、密码、深链参数和完整个人数据不得进入日志 |
| 普通 SVG | `flutter_svg 2.2.2` | 普通插图继续运行时渲染；图标字体是独立、可裁剪能力 |

`app/` 继续负责组装，`features/` 只依赖公开的 `core/`、`shared/` 契约，
`core/`/`shared/` 不反向依赖 Feature。认证状态属于 `features/auth`，屏幕换算属于
`shared/layout`，国际化 delegate 与 locale 组装属于 `app/localization`；生成工具只位于
`tool/`，不得让工具包类型泄漏到运行时代码。

### 重新执行的质量基线

以下结果来自当前工作区，而不是沿用 Goal 1 报告：

| 命令 | 结果 |
| --- | --- |
| `flutter pub get --enforce-lockfile` | 通过，锁文件可按当前 SDK 解析 |
| `flutter pub deps --style=compact` | 通过，直接依赖与上表一致 |
| `flutter pub outdated` | 通过；可解析新版本不自动改变已验证基线 |
| `dart tool/ci/check_generated_files.dart` | 通过，锁文件与 `.metadata` 有效 |
| `dart tool/ci/check_architecture.dart` | 通过，检查 47 个 Dart 文件 |
| `dart tool/ci/check_platform_environments.dart` | 通过，检查 3 个环境、25 个平台文件 |
| `dart format --output=none --set-exit-if-changed .` | 通过，88 个文件、0 个改动 |
| `flutter analyze --fatal-infos --fatal-warnings` | 通过，零问题 |
| `flutter test --test-randomize-ordering-seed=20260809` | 199 项通过 |
| `flutter test` | 默认顺序 199 项通过 |
| `flutter build apk --debug --flavor dev --dart-define-from-file=config/dev.example.json` | 通过，生成 `app-dev-debug.apk` |

`flutter doctor -v` 的 Android toolchain 通过，但 Maven 网络探测超时；实际 Gradle 构建
成功只证明当前缓存和网络条件可用，不能替代 CI 冷缓存验证。Android 构建还报告 Flutter
未来将移除 Android x86 的提示，它不是当前构建错误，不在本任务修改 ABI。

Task 1 前后 `pubspec.yaml` 与 `pubspec.lock` 的 SHA-256 分别保持为
`42b71210341c8197986b273cbb8193ecb11e7a7205f0356e6b550d7591a80b79` 和
`be93e74923d626dd0e5a6cfb8e70ed361aff62f4b1145191e0f979bd8f6fb3b7`，证明依赖
探针没有改写工程依赖。

## 依赖决策总表

后续任务必须按下表声明依赖；运行时约束仍由提交的 `pubspec.lock` 固定实际版本，生成器
额外使用精确约束，避免同一输入因工具升级产生不同字节。

| 能力 | 后续采用的依赖 | 许可证 | 平台与包体影响 | 替换边界与成本 |
| --- | --- | --- | --- | --- |
| 手机屏幕适配 | `flutter_screenutil: ^5.9.3` | Apache-2.0 | 纯 Flutter 运行时依赖，无原生插件；增加少量 AOT 代码 | 只允许 `app/` 与 `shared/layout` 接触，替换成本中等 |
| 国际化 | `flutter_localizations`（Flutter SDK）、`intl: 0.19.0` | BSD-3-Clause | 官方运行时能力；只提交 `en`、`zh` 文案，包体随文案和格式数据增长 | 业务只使用项目类型安全入口，替换成本中等 |
| SVG 转字体 | `icon_font_generator: 4.0.0`（dev） | MIT | 工具不进入应用；生成的 OTF 会进入资源包，大小按实际字形测量 | 固定在一个工具 adapter 内，因确定性兼容层而为中等成本 |
| 应用图标 | `flutter_launcher_icons: 0.14.4`（dev） | MIT | 工具不进入应用；替换 Android/iOS 原生图标资源 | 配置与调用只在品牌工具中，替换成本低 |
| 启动资源 | `flutter_native_splash: 2.4.6`（dev） | MIT | 工具不进入应用；修改 Android/iOS 启动资源和引用 | 通过暂存目录与白名单隔离，替换成本低到中等 |
| 品牌输入预检 | `image: 4.8.0`（dev） | MIT | 工具不进入应用；只解析、检查 PNG | 项目预检器直接依赖，替换成本低 |
| 认证 | 不增加依赖 | 继承现有依赖许可证 | 只增加项目 Dart 代码；凭据仍由既有安全存储插件承载 | `AuthGateway`、会话和网络装饰器均为项目接口 |
| `AGENTS.md` 生成 | Dart 标准库 | Dart SDK 许可证 | 不进入应用，不增加 Flutter 包体 | 单一专用工具，替换成本低 |

dev 工具依赖本身不会被打入应用，但字体、图标和启动资源是运行时产物。Task 6 和 Task 8
必须记录生成文件字节数、APK 前后差异和 Android 实际构建；iOS 包体只能在后续 macOS
环境补测。包缓存目录大小不是应用包体证据，不能用来宣称最终影响。

### 当前版本与维护判断

1. `flutter_screenutil 5.9.3` 是复核时的最新稳定版，但已较长时间未发布新稳定版且
   pub.dev 发布者未认证。它的 API 成熟、依赖面小，但必须由项目 wrapper 降低维护风险。
2. `flutter_localizations` 随 Flutter SDK 共同维护；当前 Flutter 3.29.0 将 `intl`
   固定为 0.19.0，因此不得单独升级到与 SDK 冲突的版本。
3. `icon_font_generator` 仍有 4.1.0 新版，说明项目有近期维护；但 4.1.0 的传递依赖
   `dart_style >=3.1.3` 需要 Dart 3.9，当前 SDK 只能采用 4.0.0。
4. `flutter_launcher_icons 0.14.4` 是复核时的当前稳定版，由 Flutter Community
   验证发布者维护，覆盖 Android/iOS、Adaptive Icon、单色图标和 iOS Alpha 处理。
5. `flutter_native_splash` 的当前稳定版是 2.4.8，但当前 SDK 不能解析；2.4.6 是本
   基线可解析且覆盖 Android/iOS 的最新可用选择。
6. `image` 当前有高于 4.8.0 的版本，但品牌工具组合在 Dart 3.7 下解析为 4.8.0。
   项目预检器会直接导入它，因此显式声明精确 dev 依赖，不能依赖偶然的传递依赖。

MIT、BSD-3-Clause 和 Apache-2.0 都允许模板使用和再分发，但后续任务仍须保留所选版本
附带的许可证文本。输入 SVG、字体字形和品牌图片的权利独立于工具许可证，不能由依赖许可证
替代。

### 依赖解析证据

在 Flutter 3.29.0 / Dart 3.7.0 下执行的只读 `flutter pub add --dry-run` 探针得到：

| 探针 | 结果与决策 |
| --- | --- |
| `flutter_screenutil:5.9.3` | 解析通过，只增加该 Flutter 包 |
| `flutter_localizations --sdk=flutter` + `intl:0.19.0` | 解析通过，与 Flutter SDK pin 一致 |
| `icon_font_generator:4.0.0` | 解析通过；固定 4.0.0 |
| `icon_font_generator:4.1.0` | 失败，`dart_style` 要求 Dart >=3.9 |
| `flutter_launcher_icons:0.14.4` + `flutter_native_splash:2.4.6` + `image:4.8.0` | 组合解析通过 |
| `flutter_native_splash:2.4.7` | 失败，`xml >=6.6.0` 要求 Dart >=3.8 |
| `flutter_native_splash:2.4.8` | 失败，`meta ^1.18.0` 与 Flutter SDK 固定的 1.16.0 冲突 |
| `flutter_screenutil_plus:1.5.0` | 失败，要求 Dart >=3.10.1 |

探针结束后依赖文件哈希未变。正式添加依赖仍分别属于 Task 2、Task 5、Task 6 和 Task 8；
每次必须审查真实 lock diff，不能把本表当作已经完成 `pub get` 的证据。

## 手机屏幕适配决策

### 唯一换算边界

1. 参考设计尺寸固定为 `375 x 812`，只面向 Android/iOS 手机。
2. `app/` 在应用根初始化 `ScreenUtilInit`；Feature 和普通共享 Widget 不得导入
   `flutter_screenutil`，也不得直接使用 `.w`、`.h`、`.sp`。
3. `shared/layout` 提供项目自有 `du` 与 `dsp`。`du` 只使用
   `logicalScreenWidth / 375`，宽、高、间距、圆角和图标都使用同一宽度比例；不提供
   独立高度单位。
4. `dsp` 先按同一宽度比例换算设计字号，再由 Flutter `TextScaler` 应用一次系统文字
   缩放。不得把系统倍率乘入 `dsp` 后再由 Flutter 重复缩放，也不得全局关闭文字缩放。
5. 根初始化不使用 `minTextAdapt` 绕过上述公式，不启用平板/桌面断点或 split-screen
   语义。屏幕指标变化必须触发根部正确重建，不能缓存跨测试或跨旋转的旧比例。

`SafeArea`、`MediaQuery.padding/viewPadding/viewInsets`、状态栏、底部手势区和键盘高度
始终使用 Flutter 报告的实际逻辑值，不经过 `du`。短屏用滚动保证操作可达，横屏只要求
可用且无溢出；固定画布只用于明确视觉场景并局部说明 `contain`/`cover` 策略。

### 选择与替换理由

`flutter_screenutil` 已处理根初始化和屏幕指标更新，能减少自建全局可变缩放器的状态泄漏；
项目 wrapper 又能阻止插件 API 扩散。若未来包停止兼容，只需保持 `du/dsp` 语义并替换
`app/`、`shared/layout` 两处实现，不要求 Feature 迁移插件扩展。

Task 2 至 Task 4 必须覆盖 `320x568`、`360x800`、`375x812`、`390x844`、
`430x932`、`800x360`，同时覆盖大字体、安全区、键盘 Insets、滚动可达性、Golden 与
关键矩形。没有这些证据时，依赖可以解析不等于适配完成。

## 国际化决策

### 初始 locale 与运行时状态

初始语言只维护通用 `en` 与 `zh`：

1. `en` 是当前界面原始文案语言，也是 ARB 模板和不支持语言的最终回退。
2. `zh` 满足脚手架维护者的中文使用需求；现阶段不伪造未实际维护的 `zh_CN`、
   `zh_TW` 等地区变体。
3. 两种语言都是 LTR，因此本阶段不声称支持 RTL。未来加入 RTL locale 时，必须同时
   增加文本方向、镜像布局、图标方向和 Golden 测试。
4. 用户选择包含“跟随系统”、`en`、`zh`。未保存偏好时跟随系统，不支持的系统语言回退
   `en`；显式选择通过现有 `PreferenceStore` 保存，不需要重启应用。

locale 状态由 Riverpod 的项目 controller 持有，`MaterialApp.router` 只消费稳定 locale；
不得使用全局可变 `Intl.defaultLocale` 作为业务状态。日期、数字和复数调用显式 locale，
避免并行测试或多个 View 因全局值互相污染。

### 生成与检查

采用 Flutter 官方 `gen-l10n`，不引入 easy_localization、slang 或另一套生成框架。
项目专用 `tool/generate_localizations.dart` 只编排该官方命令、中文注释规范化和只读
过期检查，不扩展为通用生成器。固定配置维护在
`lib/app/localization/l10n.yaml`，由专项工具复制到系统临时项目根目录后交给官方命令：

1. `synthetic-package: false`，生成源码进入项目明确目录并提交版本库。
2. `app_en.arb` 为模板；所有 key 都要求带中文用途描述，启用
   `required-resource-attributes` 和非空 getter。
3. 使用中文 `header-file` 标记生成来源、禁止手改和重新生成命令；ARB description 也全部
   使用中文。
4. Flutter 3.29 的固定生成模板仍包含英文 class/delegate 注释。wrapper 必须在 staging
   中识别已知模板注释并转换为经过测试的中文文档注释；遇到未知英文注释或模板结构变化时
   立即失败，不能静默提交混合语言产物，也不能在目标文件上手工修改。
5. 写出 untranslated JSON；CI 要求该文件表示零缺失，并同时执行生成产物字节比较。
6. ARB 覆盖普通文案、复数、日期和数字；业务 UI 不继续新增散落的用户可见硬编码。
7. 仓库根目录不得存在 `l10n.yaml`。Flutter 3.29 的普通测试、运行和平台构建会自动消费根配置
   并直接覆写输出，绕过专项工具的中文注释与原子写入；生成器和测试必须显式阻止该配置回归。

项目自有 localization 扩展与 controller 的公开 API 必须使用详细中文文档注释。Flutter
工具生成的内部结构不手工修改；若升级 Flutter 改变生成格式，必须用固定命令重新生成并审查
全量 diff。

## SVG 转字体决策

### 人工维护输入与稳定身份

原始 SVG 是唯一人工维护的图形源，计划使用独立目录与清单：

```text
assets/icons/svg/                    # 人工维护的原始 SVG
assets/icons/icon_font_manifest.json # 名称、codepoint、状态和来源许可证
assets/icons/LICENSE.md              # 字形来源与再分发许可
assets/fonts/template_icons.otf      # 生成产物
lib/shared/assets/generated/template_icons.g.dart
```

清单不是第二份图形源，只保存稳定身份。首个 codepoint 从 Unicode Private Use Area
`0xE000` 开始；新增图标只能追加新 codepoint，重命名必须显式迁移，已删除 codepoint 永不
复用。schema v1 使用只能前移的 `nextCodepoint` 记录下一个从未使用的槽位；删除任何条目，
包括最后一项，都必须保留 `retired` 墓碑。清单顺序、文件系统枚举顺序和文件名排序都不得
重新分配已有图标。

`icon_font_generator 4.0.0` 会按传入 glyph 顺序从 `0xE000` 连续分配 codepoint，默认
CLI 还会枚举目录；因此后续不得直接把包 CLI 当作仓库生成命令。项目专用
`tool/generate_icon_font.dart` 必须：

1. 在任何写入前解析、规范化并验证全部 SVG、名称、清单、重复项、Private Use Area
   范围和许可证；不支持的 shape/transform/fill 规则必须明确失败。
2. 按清单 codepoint 构造有序 glyph 列表，为已退休位置生成不渲染但保留槽位的占位
   glyph，使新增、删除和重排不会移动后续 codepoint；退休项不再生成公共 `IconData`。
3. 只在一个工具 adapter 中调用包的结构化 OTF API。4.0.0 的 head/name table 含当前
   时间或年份，adapter 必须固定或结构化重写这些元数据并重算校验和，不能用脆弱的全文
   字符串替换。
4. 不使用包自带的英文 Dart emitter；项目自行输出带中文生成标记、中文公开文档注释和
   稳定排序的 `IconData` 类。
5. 先写临时目录，所有产物验证通过后再替换字体和 Dart 文件；失败保留最后一次有效产物。
6. `--check` 在临时目录生成期望字节并只读比较目标；相同输入连续运行时 OTF、Dart 和
   清单哈希必须完全一致。

Task 6 的专项工具直接导入结构化 XML 与 YAML API，因此除精确
`icon_font_generator 4.0.0` 外，还须把解析到的 `xml 6.5.0`、`yaml 3.1.3` 声明为精确
dev 依赖，不能依赖偶然传递关系。三者只能由 `tool/` 使用，架构门禁拒绝进入 `lib/`。

该方案对 4.0.0 的字体表行为有明确耦合，因此使用精确版本，并把兼容逻辑限制在工具
adapter。升级前必须重新审查 codepoint 分配、时间字段、SVG 支持和二进制哈希；若耦合成本
失控，可替换工具而不改变应用侧 `TemplateIcons` 和字体 family 契约。

普通彩色 SVG、插图和动态 SVG 继续使用 `flutter_svg`。只有适合单色 `IconData` 语义、
尺寸一致且获得授权的图标进入字体，不能为追求统一而丢失多色或可访问性语义。

## 认证模块决策

### 模块与依赖边界

认证不增加 SDK 或第三方依赖。`features/auth` 拥有纯 Dart 会话实体、`AuthGateway`、
凭据序列化/恢复、session controller 和认证 UI；`app/` 只组装 provider、注册登录/受保护
路由并把同步重定向策略交给唯一 Router。`core/` 不依赖认证 Feature，也不增加业务规则。

默认模板不假设服务端 URL、JSON 字段、OAuth provider 或第三方 SDK。生产组装使用明确的
“未配置” gateway，不伪造可用账号或本地生产凭据；项目接入真实后端时替换 `AuthGateway`
adapter。正常、失败和并发路径通过确定测试替身完整验证。现有公共首页与示例流程保持可直接
运行，认证不会把整个模板锁在无法成功的登录页。

### 会话和凭据

1. Riverpod 是唯一会话状态所有者。稳定状态至少区分恢复中、未认证、已认证和失败；
   Token、密码与完整用户对象不放入可打印的状态或 `toString()`。
2. 登录结果包含项目自有 access/refresh credential 和必要过期元数据。两项凭据序列化为
   一个带 schema version 的安全存储 envelope，减少跨两个键的半更新；绝不写入
   `PreferenceStore`、Dart define、日志或错误详情。
3. 启动恢复先读取并严格校验 envelope。有效 access credential 进入内存；已过期时通过
   `AuthGateway` 刷新。损坏、缺失或刷新拒绝都不会被当作已登录。
4. `SessionCredentialProvider` 实现既有 `NetworkCredentialProvider`，只向明确
   `requiresCredential` 的 HTTPS 请求提供当前内存 access credential。
5. 退出先递增 session generation、清空内存凭据并使状态不可认证，再取消认证模块拥有的
   工作并删除安全 envelope。安全存储删除失败必须返回稳定错误并记录重启后可能读到旧值的
   风险，不能谎报持久化退出成功，也不能降级到普通存储。

### 401、并发和取消

认证提供一个包装现有 `NetworkClient` 的项目装饰器，而不修改 Dio adapter 或引入第二个
HTTP 客户端：

1. 只有 `requiresCredential` 请求抛出 `NetworkResponseError(statusCode: 401)` 时才尝试
   刷新；登录和刷新请求直接使用基础 `NetworkClient`，避免递归拦截。
2. 同一 session generation 内所有 401 等待同一个 refresh Future；成功后每个请求最多
   重试一次，防止刷新风暴和无限循环。自动重放默认只允许无请求体的 GET；POST、PUT、
   PATCH、DELETE 只有调用方通过项目自有 replay policy 显式声明服务端幂等保证后才可重放，
   否则刷新会话后仍返回原 401，避免重复业务副作用。
3. replay policy 只表达一次请求是否可以安全重放，不暴露 Dio 类型，也不改变网络层“默认
   不自动重试”的第一阶段规则；认证装饰器是唯一消费者。
4. refresh 完成前后都核对 generation。退出、替换账号或会话失效后，旧 refresh 的迟到
   结果不得写回状态或安全存储。
5. 单个调用方取消只取消其等待和重试，不取消其他请求共享的 refresh；退出/销毁则使整个
   generation 失效并取消认证模块拥有且可取消的工作。
6. refresh 失败会清除内存凭据，尽力删除安全 envelope，并进入未认证/会话失效状态；原始
   response、Token 和服务端正文不进入 UI、日志或稳定错误。

### 路由重定向

认证策略实现现有同步 `AppRouteRedirectPolicy`，只读取已经稳定的 session snapshot。
异步恢复/刷新在 controller 中完成，Router 不能在 `redirect` 内发网络请求。一个私有
`Listenable` bridge 只通知 go_router 重新求值，不拥有第二份认证状态。

受保护位置在恢复期进入不泄漏原 URI 的 loading route，未认证时进入登录 route；登录后
只恢复经过校验的站内 `returnTo`。带 scheme、authority、userinfo、双斜杠或形成循环的目标
一律拒绝，query/fragment 不写日志。已认证访问登录页、未认证访问登录页和重复重定向都有
明确终止条件。

## 品牌资源生成决策

### 输入、权利与平台范围

输入继续采用 `docs/phase-2-plan.md` 的固定目录：

```text
assets/branding/
├── app_icon.png
├── app_icon_foreground.png
├── app_icon_background.png
├── app_icon_monochrome.png       # 可选
├── splash_logo.png
└── LICENSE.md                    # 来源、权利范围与替换责任
```

只生成 Android/iOS 资源，且 dev、staging、prod 共用同一输入和 `src/main`/同一 iOS
Asset Catalog，不生成环境角标。当前没有用户提供的正式品牌资产；Task 8 只能以仓库权属
明确、视觉上清楚是占位的中立资源验证流水线，并文档化正式替换方式，不能自行声称占位资源是
客户品牌。

项目预检器直接使用固定 `image 4.8.0` 读取 PNG，在调用上游工具前验证文件存在、真实
格式、像素尺寸、正方形要求、Alpha、iOS 不透明输出、Android Adaptive Icon 安全区和可选
单色图。Android Adaptive Icon 使用 108x108 图层坐标与中心 66x66 安全区规则；iOS 完整图标
源至少为 1024x1024。输入不合法时不得触碰原生目录。

### 工具隔离与原子性

1. 根目录只维护一份 `flutter_launcher_icons.yaml` 和一份
   `flutter_native_splash.yaml`；后者关闭 Web 和其他非目标平台。
2. 项目专用品牌工具先复制允许的最小 Android/iOS 输入到临时 staging project，再调用
   `flutter_launcher_icons 0.14.4` 与 `flutter_native_splash 2.4.6`。上游工具不得直接
   在真实工作区进行探索式写入。
3. staging 输出通过目标白名单、配置引用、图片格式和环境一致性检查后，才同步到明确的
   Android/iOS 目标；替换前保留可恢复快照，任一写入失败就恢复整组目标。
4. `--check` 只生成 staging 期望值并逐字节比较，不改变源文件、配置、原生产物或时间戳。
   连续两次生成必须无 diff。
5. 图标和启动页是两个独立工具职责；不得把 launcher icon 命令描述为 splash 生成。

Android 12+ 使用平台 SplashScreen 语义，旧 Android 与 iOS 继续由生成的原生资源承载。
Task 8 必须实际构建 dev Android APK、检查 Manifest/资源引用与三环境公共来源；iOS 只可在
当前主机静态核对，真实 LaunchScreen 和 AppIcon 仍需 macOS 构建及设备验证。

## 基础 AGENTS.md 生成决策

`tool/generate_agents.dart` 只使用 Dart 标准库，并且只接受无参数初始化或 `--check`。
不增加通用参数解析器、模板插件、业务代码生成或脚手架 CLI。CLI 以当前目录为目标；测试通过
可注入的项目目录 API 在临时目录执行，不提供隐式输出到任意路径的命令行参数。

模板固定为 `tool/templates/AGENTS.base.md` 与
`tool/templates/partials/goal_mode.md`。工具必须：

1. 以 UTF-8、LF 和稳定拼接顺序生成中文内容，不读取系统时间、用户名、机器路径或环境变量
   作为输出。
2. 目标不存在时创建；内容一致时不写入；内容不一致时失败。不存在 `--force`，根
   `AGENTS.md` 始终视为用户资产。
3. `--check` 严格只读，区分目标缺失、陈旧、不可读和匹配，并返回稳定退出码。
4. 完整包含项目边界、命令、详细中文注释、测试、安全、Git、屏幕适配与根级 Goal Mode，
   不用摘要或外部链接替代 Goal Mode 正文。
5. 对根规范、base 模板、Goal Mode partial 和临时生成结果做结构与字节漂移检查；所有写入
   测试只触碰系统临时目录。

当前仓库已经存在用户维护的根 `AGENTS.md`。后续不得用生成器覆盖它；模板同步只能通过
显式文档 diff 与只读门禁证明。生成器自身是脚手架工具，可以保留合适的英文实现注释，但其
生成到下游项目的规范和项目代码注释必须为中文。

## 不采用的主要方案

| 方案 | 不采用原因 |
| --- | --- |
| `flutter_screenutil_plus` | 当前 1.5.0 要求 Dart >=3.10.1，且断点/Size Class 能力超出手机固定设计稿范围 |
| Feature 直接使用 `.w/.h/.sp` | 插件扩散、独立高度缩放和替换成本违背统一 `du/dsp` 边界 |
| 自建全局 MediaQuery 缩放单例 | 需要自行处理指标变化、测试隔离和根生命周期；当前无收益 |
| easy_localization、slang 或手写 Map | 重复 Flutter 官方生成链，增加运行时/生成器和迁移成本 |
| 只保留 `flutter_svg` 而不生成字体 | 无法满足稳定 `IconData`、字体产物和 codepoint 门禁要求 |
| `icon_font_generator 4.1.0` | 当前 Dart 3.7 无法解析其 `dart_style` 依赖 |
| `fontify` | 工具陈旧，不能在当前 Dart 3 基线可靠解析 |
| `icon_font_gen` / Fantasticon | 需要额外 Node 工具链，增加跨平台安装与可复现风险 |
| `mrx_icon_font_gen` | 依赖外部网络服务，违反离线、确定和隐私边界 |
| Firebase Auth、Supabase Auth、Amplify Auth | 预设具体后端、平台配置与凭据体系；模板没有该产品决策 |
| 在 Dio interceptor 内直接刷新 | 会把认证业务和并发状态塞入基础设施插件层，难以隔离递归与退出竞态 |
| 手工维护平台图标/启动资源 | 容易遗漏尺寸、环境引用和过期产物，不能建立确定性检查 |
| 让一个工具同时伪装 icon 与 splash | 两类平台资源和配置职责不同，错误回滚范围不清晰 |
| Mason、通用模板引擎或新脚手架 CLI | 根规范明确排除通用代码生成和 CLI；基础 Agent 文件不需要该复杂度 |

## 升级、验证与回滚

### 升级规则

1. Flutter/Dart 升级后先重新求解官方 `flutter_localizations`/`intl` 组合，再评估其他包；
   不为使用最新版反向放宽本项目 SDK 承诺。
2. 每次只升级一个运行时依赖或一组不可分割的生成工具。生成工具即使是 patch 版本也必须
   视为可能改变产物，重新生成并审查完整二进制/文本 diff。
3. `icon_font_generator`、launcher、splash 和 `image` 保持精确 pubspec 约束，且继续提交
   `pubspec.lock`。升级时重新核对许可证、SDK 下限、平台写入白名单和时间字段。
4. 每个实现任务先运行聚焦测试，再运行生成检查、严格分析、全量测试和适用 Android 构建。
   字体/品牌升级必须比较生成前后 APK/资源大小，不能只看 `pub get` 成功。
5. iOS 原生资源、Keychain 和字体注册的真实验证必须来自 macOS/Xcode；静态文件存在不是
   编译或设备行为证据。

### 回滚边界

1. 屏幕适配整体恢复根初始化、`du/dsp`、主题/页面使用点、依赖和锁文件，不能只删包。
2. 国际化整体恢复 locale controller、delegate、ARB/生成物、文案调用点和依赖；不得留下
   混合硬编码/类型安全访问状态。
3. SVG 字体保留最后一次验证产物；失败或回滚时恢复清单、SVG、字体、Dart 映射和 pubspec
   字体声明这一完整集合，不复用已退休 codepoint。
4. 认证回滚先使会话失效并删除安全 envelope，再移除路由、组装、Feature 与测试；不得在
   普通存储或日志留下凭据。
5. 品牌回滚按白名单整体恢复 Android/iOS 图标、启动资源、两份配置和输入，不改包名、签名
   或环境配置。
6. Agent 生成器回滚只删除工具、模板、测试和 CI 接线，不删除或覆盖任何已经属于用户的
   `AGENTS.md`。

## 结果与后续实施顺序

本决策接受上述组合，并授权 Goal 2 后续任务按 `Task 2 -> Task 3 -> Checkpoint A -> ...`
顺序实施。Task 1 没有修改业务源码、工程配置、平台资源或依赖声明。若后续实现发现某项
已接受假设无法通过专项测试，应先更新本 ADR 并记录迁移影响，不能静默采用另一套方案或扩大
阶段范围。

## 官方与一手来源

1. [Flutter 国际化指南](https://docs.flutter.dev/ui/internationalization)
2. [Flutter `MediaQuery.textScalerOf`](https://api.flutter.dev/flutter/widgets/MediaQuery/textScalerOf.html)
3. [Flutter `SafeArea`](https://api.flutter.dev/flutter/widgets/SafeArea-class.html)
4. [`flutter_screenutil` versions](https://pub.dev/packages/flutter_screenutil/versions)
5. [`flutter_screenutil_plus` versions](https://pub.dev/packages/flutter_screenutil_plus/versions)
6. [`icon_font_generator` versions](https://pub.dev/packages/icon_font_generator/versions)
7. [`flutter_launcher_icons` versions](https://pub.dev/packages/flutter_launcher_icons/versions)
8. [`flutter_native_splash` versions](https://pub.dev/packages/flutter_native_splash/versions)
9. [`image` versions](https://pub.dev/packages/image/versions)
10. [Android Adaptive Icon 设计规范](https://developer.android.com/develop/ui/compose/system/icon_design_adaptive)
11. [Android SplashScreen](https://developer.android.com/develop/ui/views/launch/splash-screen)
12. [Apple App Icon 指南](https://developer.apple.com/design/human-interface-guidelines/app-icons/)
13. [Apple Launch Screen 配置](https://developer.apple.com/documentation/xcode/specifying-your-apps-launch-screen/)
