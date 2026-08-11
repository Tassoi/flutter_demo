# 测试基础设施

本目录验证脚手架第一阶段的稳定工程边界，以及已经启用的第二阶段能力。测试必须通过项目接口
替换网络、存储和状态依赖，不得访问真实服务、真实密钥、系统时钟或不稳定的平台状态。确需
验证生成事务的文件系统测试只能使用独立系统临时目录，并在结束时完整清理。

## 目录与职责

测试文件使用 `*_test.dart` 命名，并尽量镜像 `lib/` 的边界：

```text
test/
├── app/                         # 配置、启动、路由、状态和主题
├── core/                        # 错误、日志、网络和存储
├── features/                    # Feature 的领域、数据、状态、页面与路由契约
├── goldens/                     # 固定字体与参考手机尺寸的关键页面像素基线
├── shared/                      # 类型安全资源和无业务组件
├── tool/                        # 架构与生成产物质量门禁
└── support/                     # 被多个测试文件复用的测试专用能力
```

`test/support/` 只接收已经出现多个使用方的测试代码：

1. `features/example/controlled_example_repository.dart` 使用 `Completer` 显式结算请求，
   用于验证加载、取消、竞态和迟到结果，不使用延时等待。
2. `features/example/example_item_fixture.dart` 提供通过领域校验的默认对象。领域模型自身的
   无效输入测试仍直接调用构造函数，不能让 Fixture 隐藏边界。
3. `state/create_test_provider_container.dart` 为每个测试创建并自动释放 Riverpod 容器。
4. `storage/` 下的内存实现只替换项目存储接口，不提供真实加密，也不得进入生产组装。
5. `widgets/test_widget_environment.dart` 统一六档手机视口、放大文字、原始 FlutterView
   Insets 和首帧挂载行为，并在测试结束时恢复所有 View 指标。
6. `features/auth/` 下的凭据 fixture 使用明显虚构值；可控 gateway 不保存登录输入或 refresh
   credential，只记录调用次数、取消令牌和脱敏描述；可控持久化与时钟用于验证 I/O 顺序、
   generation 竞态和有效期，不访问平台安全存储或系统时钟。

只被一个 adapter 测试使用的第三方插件 Fake 保留在对应测试文件内。不要为了目录整齐把
Dio、SharedPreferences 或 FlutterSecureStorage 类型扩散到通用测试支持层。

## 覆盖矩阵

下表中的每一项都具有直接、可独立运行的正常、边界和失败证据。文件名是该能力的主要
证据入口，不表示其他测试不能提供跨层验证。

| 能力 | 正常路径 | 关键边界 | 主要失败路径 |
| --- | --- | --- | --- |
| 环境与配置 | `app/config/app_environment_test.dart` 验证全部环境；`app_config_test.dart` 验证三套配置 | 缺失和未知环境、Base URI 规范化、只使用不可路由默认地址 | 拒绝生产 HTTP、user info、query、fragment 与不安全地址，异常不回显原值 |
| 应用启动 | `app/bootstrap/app_bootstrap_test.dart` 验证初始化顺序和应用装配；`app_bootstrap_runtime_test.dart` 验证运行时桥接 | 同步与异步失败、Reporter 切换、重复错误处理 | 配置或装配失败进入安全回退；Reporter 自身失败被隔离；失败页不泄漏底层异常 |
| 统一错误 | `core/error/app_error_test.dart` 验证稳定代码、文案和既有错误透传 | HTTP 状态码上下界与配置错误分类边界 | 未知异常折叠为稳定错误，原始配置、传输、键和值不进入结果 |
| 日志 | `core/logging/package_logging_app_logger_test.dart` 验证级别、结构化记录和 JSON Sink；`log_redactor_test.dart` 验证脱敏 | 深度、集合、文本长度、循环引用、动态事件名和关闭生命周期 | Sink、fallback writer、脱敏器及恶意集合失败均被隔离；生产策略不输出原始错误和堆栈 |
| 网络 | `core/network/network_contract_test.dart` 验证请求、凭据、取消和超时契约；`dio_network_client_test.dart` 验证完整 adapter pipeline | 路径、header、query、body、Base URI、重复取消、并发请求和异步 decoder | HTTP、连接、全部超时、解析、凭据和取消失败映射稳定；正文、凭据与日志均不泄漏 |
| 存储 | `core/storage/storage_contract_test.dart` 验证普通与安全存储接口；两个插件 adapter 测试验证平台选项和命名空间 | 缺失值、列表防御复制、类型、有限 double、单键删除与 scoped clear | 初始化和读写删清失败稳定映射；凭据类名称不能进入普通存储 |
| 路由 | `app/router/app_router_test.dart` 验证 Shell 内首页、详情和返回；`features/example/routing/example_route_contract_test.dart` 验证 URI 契约 | 正整数参数、规范 URI、重复返回、窄屏与放大文字 | 未知页、非法参数、不安全重定向和策略异常都显示安全状态且不回显 URI |
| 状态 | `app/state/app_state_scope_test.dart` 与两个异步生命周期测试验证 override、加载、数据和主题状态 | 成功空值、非正 family 参数、重复重试、auto-dispose、依赖重建和迟到完成 | Repository、重试与缺少组装失败均映射为稳定错误；取消后旧结果不能复活状态 |
| 设计单位 | `shared/layout/app_screen_adaptation_test.dart` 验证参考宽度和应用根初始化 | `320`/`375`/`430` 宽度、运行时屏幕指标变化、两倍系统文字缩放、零值 | 根作用域缺失以及负数、NaN、无穷大设计值会立即失败，Feature 直接导入底层插件由架构门禁拒绝 |
| 页面适配基线 | `shared/layout/app_safe_scrollable_scaffold_test.dart` 验证安全区、短屏、横屏、键盘和操作可达性；`app_fixed_visual_canvas_test.dart` 验证固定视觉画布 | `320x568`、`375x812`、`430x932`、`800x360`、两倍文字、侧边/底部安全区、动态键盘 Insets、外部滚动控制器所有权及 `contain/cover` 关键矩形 | 非法设计留白、非法固定画布尺寸和无界画布目标立即失败；普通页面不得使用固定画布掩盖溢出 |
| 组件与页面 | `app/mobile_ui_layout_matrix_test.dart`、`shared/widgets/app_widget_layout_matrix_test.dart`、`shared/assets/app_assets_test.dart` 和示例页面测试验证展示与交互 | 六档视口各自覆盖正常/200% 系统文字、四边安全区、超高操作的上下滚动可达性、语义、触控尺寸、空状态和可选动作 | 错误文案脱敏；非法自定义留白和无效参数提前拒绝；重复弹窗动作与过期消息不会产生二次副作用 |
| SVG 图标字体 | `tool/generate_icon_font_test.dart` 验证真实输入、OTF 表和确定性；`shared/assets/template_icons_test.dart` 验证 AssetBundle、映射和实际像素 | 清单重排、尾部追加、退休槽、尾部删除墓碑、固定时间/版权、PUA `cmap` 与两个不同非空字形 | 非法/不支持 SVG、重复名称/codepoint、许可证缺失、产物过期、第二文件写入失败及回滚失败备份保留均返回稳定证据 |
| 品牌资源 | `tool/generate_branding_test.dart` 验证 PNG 预检、隔离上游生成、完整 Android/iOS 清单和只读漂移 | 可选单色成组省略、连续两次 73 文件逐字节一致、三环境公共路径、Catalog 复用文件与目标 mtime | 伪 PNG、Alpha/安全区/灰度、权利/平台配置、未知 Catalog 文件、单文件过期和第二目标安装失败均稳定失败并恢复旧字节 |
| Agent 指南 | `tool/generate_agents_test.dart` 在系统临时项目验证初始化、严格只读检查和根/base/partial/样例四方契约 | 相同输入 UTF-8 字节稳定；匹配检查连续输出确定且整个临时目录零写入；根 Goal Mode 与 partial 逐字一致 | 缺失、过期、不可读、非法目标、用户修改、Goal 条款删减、屏幕规则遗漏和注入写入失败均返回稳定编号，不覆盖根规范或留下部分目标 |
| 认证 | `features/auth/` 验证登录、退出、安全 envelope、启动恢复、凭据注入和受保护页面；`app/router/auth_app_route_redirect_policy_test.dart` 验证应用重定向 | 重复登录、运行时过期、并发 401 单飞、GET/显式幂等重放、调用方取消、串行持久化、generation/销毁后迟到结果、严格 `returnTo` 和 200% 窄屏 | 默认 gateway/持久化失败关闭，损坏 schema、存储/网络/刷新/第二次 401 失败映射稳定，日志、状态、诊断字符串和 Widget 不包含登录输入或凭据 |
| Golden | `goldens/mobile_ui_golden_test.dart` 验证首页与示例详情参考像素 | `375x812`、1.0 DPR、固定安全区、正常文字、显式 Ahem 测试字体，以及 Windows/Linux 分离的精确基线 | 受支持宿主的基线缺失或任意像素漂移直接失败；不得用容差或更新截图掩盖布局矩阵失败 |
| 阶段二运行时组合 | `app/phase_two_runtime_integration_test.dart` 在同一 `TemplateApp` 中串联适配、生成图标、语言切换、认证重定向/登录/退出和示例路由 | `390x844` 原始安全区、英语切换中文、受控安全凭据写入与精确清理、退出后 locale/路由保持 | fixture 输入不得进入页面或状态；品牌与 Agent 属于平台/工具门禁，不以 Widget 断言替代 |
| 工程门禁 | `tool/ci/check_architecture_test.dart` 验证允许的分层与 adapter；`check_generated_files_test.dart` 验证锁文件和项目创建/迁移 metadata；`check_platform_environments_test.dart` 验证三环境、语言与字体注册；`check_documentation_test.dart` 验证工程文档契约 | export、跨 Feature、编码路径、相对导入、工具依赖泄漏、旧创建 SDK、缺失元数据、无效 JSON、缺少 scheme、环境值漂移、configuration 专属 Pods include，以及本地文档链接/锚点/命令目标/质量顺序 | 反向依赖、adapter/工具越界、生成/平台漂移、缺失或越界文档链接、不存在命令目标、不安全示例和 README/操作指南/CI 顺序差异均返回稳定规则编号 |

## 文档契约测试

`tool/ci/check_documentation_test.dart` 只向内存 validator 提供文档、项目路径和 workflow fixture，
不访问网络或改写仓库。正常用例验证六份阶段二指南、中文锚点、现有命令目标与固定质量顺序；
边界/失败用例覆盖缺失和越界链接、未知锚点、不存在工具/测试、workflow 漂移、个人目录、私钥
标记与非 `.invalid` 示例服务地址。

实际 CLI 递归读取稳定项目树时会排除 `.git`、`.dart_tool`、`build/`、IDE 状态和 `goal-*`，
避免本地缓存让错误链接偶然通过。文档或 Quality 顺序变化至少运行：

```bash
dart tool/ci/check_documentation.dart
flutter test test/tool/ci/check_documentation_test.dart
```

## Widget 帧与布局

`pumpTestWidget` 只挂载 Widget 并推进首帧。调用方必须根据行为显式选择后续的 `pump` 或
`pumpAndSettle`，不能在通用辅助方法中隐藏动画和异步状态时序。需要小屏验证时传入
`narrowPhoneSurfaceSize`；需要无障碍文字验证时通过 `createTestMediaQueryBuilder` 使用
`largeTestTextScaler`。完整手机验收使用 `supportedPhoneViewports`，并把同一安全值同时写入
测试 FlutterView 和 MediaQuery；这保证从 SafeArea 内部调用的代码仍能看到未消费的平台原值。

设计单位适配器直接读取 `FlutterView` 指标，因此它的测试不能只调用 `setSurfaceSize`。相关
测试应设置 `tester.view.devicePixelRatio` 与 `tester.view.physicalSize`，并在 teardown 中调用
对应的 reset 方法；否则底层适配器可能继续使用默认测试视口，或把尺寸状态泄漏到其他用例。

系统 Insets 测试应同时设置相互一致的 `viewPadding`、`padding` 和 `viewInsets`，并用
`tester.getRect` 断言安全滚动视口与关键操作的实际边界。键盘出现时，通常保留原始
`viewPadding`、将被键盘覆盖一侧的 `padding` 设为零，再提供真实 `viewInsets`；不得只断言
“没有抛异常”，也不得把系统值乘以设计比例后作为期望。

持续进度动画不应使用无上限的 `pumpAndSettle`。状态测试优先用 `Completer`、项目取消令牌
和 Riverpod 的 `container.pump()` 推进明确事件，不使用无依据的 `Future.delayed`。

## Golden 与字体确定性

关键页面 Golden 固定 `375x812`、1.0 DPR、顶部 44/底部 34 安全区，并只在测试主题中显式
使用 Flutter 测试字体 `Ahem`。Ahem 消除系统 fallback 字体的字形和度量差异，但 Flutter tester
在 Windows 与 Linux 上仍会产生一像素字形边缘差异。因此 `baselines/windows/` 与
`baselines/linux/` 分别保存经过审查的精确 PNG，比较保持零容差；当前没有审查基线的宿主只
跳过这两项像素测试，六档布局、200% TextScaler、语义和交互测试仍照常执行。生产主题不得因此
指定 Ahem 或禁用系统缩放。

常规检查只比较基线：

```bash
flutter test test/goldens/mobile_ui_golden_test.dart
```

只有在 Windows 或 Linux 上确认视觉变化符合需求、布局矩阵与全部门禁通过后，才使用
`--update-goldens` 更新当前宿主目录，并逐张审查 PNG。Flutter SDK/引擎升级可能改变 SVG、
Material 图标或抗锯齿结果，必须在 CI 的 Ubuntu runner 重新验证 Linux 基线；新增 macOS 等
宿主时先建立并审查独立目录，不能复用其他宿主截图或放宽全局阈值。详细规则见
`goldens/README.md`。

## 国际化测试

本地化资源测试分别验证 `en/zh` 的类型安全访问、系统回退、复数、日期、数字和全部稳定
`AppError.code` 映射。语言 Controller 使用可控完成器验证立即更新、最新写入失败回滚及旧失败
不能覆盖新选择，不使用延时等待。Widget 测试通过真实语言菜单验证无需重启、偏好写入、失败
反馈和 Router 位置保持。

页面布局矩阵对两种语言各执行 6 个视口和正常/200% 文字，共 24 条完整流程；当前两种语言均
明确断言 LTR。新增 RTL locale 时必须补方向性图标、边距镜像和导航测试，不能用当前断言代替。
资源或生成工具变更至少运行：

```bash
dart run tool/generate_localizations.dart --check
flutter test test/tool/generate_localizations_test.dart
flutter test test/app/localization test/app/state/app_locale_controller_test.dart
flutter test test/app/template_app_test.dart test/app/mobile_ui_layout_matrix_test.dart
```

## SVG 图标字体测试

生成器测试同时解析实际 OTF 表和校验和，不以文件存在代替有效字体。清单重排必须产生相同
字节；新增只能使用 `nextCodepoint`，退休保留槽位且移除公共 Dart 字段；直接删除历史条目会
失败。事务测试在临时项目中把故障注入到第二个输出，证明旧 OTF/Dart 同时恢复；若模拟外部
抢占导致回滚也失败，测试还要求 `.dart_tool/icon_font_*` 的旧文件备份不得被清理。

Widget 测试从真实 AssetBundle 加载 OTF，渲染 `language` 与 `check` 并检查两者像素非空且不同。
资源或工具变更至少运行：

```bash
dart run tool/generate_icon_font.dart --check
flutter test test/tool/generate_icon_font_test.dart
flutter test test/shared/assets/template_icons_test.dart
flutter test test/app/router/app_router_test.dart
```

普通彩色 SVG 的测试仍属于 `app_assets_test.dart`，不能用图标字体测试替代；Android/iOS 的最终
打包证据来自实际平台构建，当前非 macOS 主机只能静态核对 iOS 的 Flutter 字体注册。

## 品牌资源测试

品牌测试直接读取 `assets/branding/` 的真实 PNG、权利声明与两份根配置。输入预检覆盖真实
格式、1024 方形、不透明完整图/背景、透明图层、`108/66` 安全区、单色灰度以及 Android/iOS
平台范围；可选单色只能和配置字段成组省略。

`setUpAll` 在两个独立系统临时项目分别调用锁定 launcher/splash 工具，比较 73 个白名单文件
全部字节。事务测试先准备完整旧目标，再把失败注入第二个变化文件，要求前一个已安装目标和
本轮全部旧字节恢复，且不残留 `.dart_tool/branding_install_*`。漂移测试同时保存 mtime，证明
匹配检查零写入，并确保未知 Catalog 文件只报错而不自动删除。

品牌源、配置、工具版本或平台资源变化至少运行：

```bash
dart run tool/generate_branding.dart --check
flutter test test/tool/generate_branding_test.dart
flutter test test/tool/ci/check_architecture_test.dart
flutter test test/tool/ci/check_platform_environments_test.dart
```

完整平台证据还需要 Android 实际构建；iOS Catalog/Storyboard 静态检查不能替代 macOS/Xcode
构建和模拟器/真机的应用图标、系统蒙版及启动画面验证。

## Agent 指南生成测试

专项测试只读取固定的根规范与 base/Goal Mode 模板，并把副本写入每个用例独立创建的系统
临时项目；它不会改写仓库根 `AGENTS.md`。首次生成会断言 UTF-8 无 BOM、LF、中文注释规范、
六档手机视口规则和 Goal Mode 局部模板全文；重复初始化则先固定 mtime，再证明字节一致时
完全不写入。

`--check` 用目录清单、文件字节和 mtime 快照证明匹配、缺失、过期、不可读与非法目标都不会
写入；检查不调用初始化写钩子，连续成功输出也必须一致。不可读目标由受限回调注入，不依赖
Windows/Unix 权限差异。用户目标保护、缺失模板、非法参数、重复占位符、CRLF 和写入失败同样
只在临时目录验证；初始化写入故障发生在独占创建后，测试要求本轮空目标被清理。

仓库契约用一次临时初始化产物作为样例，逐字比较根规范末尾 Goal Mode 与 partial，并把样例
与 base + partial 的确定性拼接结果比较。反例分别删除根/partial 的 Goal 条款、base 的参考尺寸
和样例的键盘 Insets 规则，必须同时得到对应完整性或过期编号。Quality workflow 在全量测试前
显式运行这 19 项测试，保证模板维护错误尽早失败。

模板或生成器变化至少运行：

```bash
flutter test test/tool/generate_agents_test.dart
```

## 认证测试

认证测试必须通过项目接口替换 gateway、时钟和安全持久化，不打开 Socket、不访问设备
Keychain/Keystore，也不使用无依据延时。会话状态断言只读取阶段和稳定失败；需要证明凭据注入
时仅在局部检查 fake header，并同步断言 `toString()`、日志和公开状态没有包含该值。

Controller 用例显式控制登录、refresh 和安全写入完成顺序，覆盖并发单飞、退出先清内存、旧
save 后排删除、同步/异步失败、Provider 销毁及迟到成功。网络装饰器用例区分共享 refresh 令牌
和各调用方取消令牌，并验证非幂等请求默认不重放、显式幂等最多重放一次、第二次 401 使会话
失效。路由 Widget 用例从 restoring 分别结算到未登录和已认证，不能通过预设最终状态跳过恢复
时序。

聚焦命令：

```bash
flutter test test/features/auth
flutter test test/app/router/auth_app_route_redirect_policy_test.dart
flutter test test/app/router/app_router_test.dart test/app/template_app_test.dart
flutter test test/core/network/network_contract_test.dart
```

认证页面使用同一安全滚动壳层；页面或文案变化还要运行双语六视口矩阵和 Golden。Golden 不得
输入账号或密码，当前首页基线只展示进入受保护区域的公开命令。

## 独立性与确定性

1. 每个测试负责创建并释放自己的 Router、ProviderContainer、客户端和语义句柄。
2. 测试替身不得持有跨测试静态可变状态，也不得依赖测试文件或用例的执行顺序。
3. 网络 adapter 通过注入 transport 验证，不打开 Socket；存储 adapter 通过注入插件接口
   验证，不访问设备数据。
4. 修复缺陷时先增加能复现该行为的最小测试，再修复实现；至少保留正常、关键边界和主要
   失败路径中与缺陷有关的证据。
5. 随机顺序失败时必须记录 seed，修复共享状态或资源释放问题，不能固定顺序掩盖问题。

常用验证命令：

```bash
# 单文件独立验证
flutter test test/core/network/network_contract_test.dart

# 工程门禁的正常、边界和失败测试
flutter test test/tool/ci

# SVG 字体输入、事务、OTF 映射和实际字形像素
flutter test test/tool/generate_icon_font_test.dart test/shared/assets/template_icons_test.dart

# 品牌 PNG 预检、隔离生成、清单、漂移与事务恢复
flutter test test/tool/generate_branding_test.dart

# 基础 Agent 指南、只读检查、四方漂移、非覆盖和失败清理
flutter test test/tool/generate_agents_test.dart

# 认证会话、安全 envelope、401 重放与重定向
flutter test test/features/auth test/app/router/auth_app_route_redirect_policy_test.dart

# 六尺寸、正常/200% 文字和关键页面 Golden
flutter test test/app/mobile_ui_layout_matrix_test.dart
flutter test test/shared/widgets/app_widget_layout_matrix_test.dart
flutter test test/goldens/mobile_ui_golden_test.dart

# 使用固定 seed 的可复现随机顺序
flutter test --test-randomize-ordering-seed=20260809

# 生成本地覆盖率诊断，产物位于已忽略的 coverage/
flutter test --coverage
```

覆盖率用于发现未执行分支，不设置脱离风险的百分比目标。`bootstrapApplication` 的编译期
环境读取和全局 `runApp`、默认 `debugPrint` writer、真实插件通道属于生产装配或平台边界：
其可替换契约由单元测试覆盖，默认集成由实际平台构建与后续设备验证覆盖。不得仅为提高行
覆盖率，把私有装配函数、平台对象或第三方类型暴露为公开 API。
