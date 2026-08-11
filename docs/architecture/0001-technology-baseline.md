# ADR 0001：Flutter 工具链与基础依赖基线

- 状态：Accepted
- 决策日期：2026-08-09
- 适用范围：第一阶段基础能力
- 决策依据：Flutter 3.29.0、Dart 3.7.0、Android、iOS

## 背景

脚手架需要为状态管理、声明式路由、网络、普通存储、安全存储、日志和普通 SVG 各选择一套默认实现。选择必须同时满足以下约束：

1. 能在本机已安装的 Flutter 3.29.0 / Dart 3.7.0 上完成依赖求解。
2. 支持 Android 和 iOS，且平台最低版本要求可以明确配置。
3. 覆盖 Goal 中实际要求的异步状态、路由重定向、请求取消、日志脱敏和可测试替换能力。
4. 许可证允许在商业和开源模板中再分发。
5. 第三方类型可以被限制在应用组装层或基础设施实现内部。
6. 不依赖通用代码生成框架，也不引入独立依赖注入容器。

本 ADR 记录的是经过测试和当前可用平台证据验证的固定组合，而不是无条件追逐 pub.dev 最新
版本，也不把求解器能够解析等同于项目已经兼容。更高版本即使能在当前 SDK 下解析，仍需完成
迁移、架构审查和风险相称的回归验证后，才能替换该基线；iOS 真实编译缺口仍按下文单独记录。

## 工具链基线

### 已验证版本

```text
Flutter 3.29.0 • stable • framework 35c388afb5
Dart 3.7.0 • windows_x64
Android SDK tools 35.0.1 • platform android-36 • build-tools 35.0.1
Android NDK 27.0.12077973
Java 21.0.4 • Android Studio bundled JBR
```

`pubspec.yaml` 将支持范围固定为 Dart `>=3.7.0 <3.8.0` 与 Flutter
`>=3.29.0 <3.30.0`，允许同一已验证 minor 内的兼容补丁，不把尚未验证的下一
minor 或 major 宣称为受支持版本。CI 使用精确 Flutter 3.29.0 framework revision
`35c388afb57ef061d06a39b537336c87e0e3d1b1`；完整质量门禁见 ADR 0012。

初始依赖审计时本机只有 platform android-35 和 NDK 26.3。项目生成后的首次 Android 构建根据已锁定插件的明确要求安装了 platform android-36 与 NDK 27.0.12077973，并把版本固定在 `android/app/build.gradle.kts`。这是项目当前可复现的构建基线，不是对 Flutter 全局默认值的修改。

Flutter SDK 位于 Windows 文件系统。其无扩展名 Bash 启动脚本使用 CRLF，在 WSL 中直接执行 `flutter` 或 `dart` 会因 `bash\r` shebang 失败。不得为了本项目修改或重新换行用户的全局 SDK。

从 WSL 运行仓库命令时，使用 Windows 原生批处理入口：

```bash
/mnt/c/Windows/System32/cmd.exe /d /c flutter --version
/mnt/c/Windows/System32/cmd.exe /d /c dart --version
/mnt/c/Windows/System32/cmd.exe /d /c flutter pub get
```

以上入口已实际运行成功。Windows Terminal、PowerShell、CMD 和 CI runner 仍使用常规 `flutter` / `dart` 命令；这个调用差异只属于当前 WSL 工作站，不进入应用运行时设计。

### 已知工具链状态与限制

1. Android licenses 已全部接受；`flutter doctor -v` 的 Android toolchain 检查通过，实际 Debug APK 构建也已通过。
2. 当前主机不是 macOS，无法本地运行 Xcode；iOS 工程由本地静态门禁核对，并由远端 macOS CI
   对三环境执行真实无签名编译。签名和设备行为仍需业务项目在 Apple 设备上验证。
3. `flutter doctor` 对 Maven 的网络探测仍会超时，但锁文件离线解析和实际 Gradle 构建均成功。全新机器首次下载依赖仍受外部网络可用性影响，不能用本机缓存证据替代 CI 冷启动验证。

## 决策

### 最终依赖

| 能力 | 依赖约束 | 实际解析版本 | 许可证 | 当前 SDK 兼容下限 | 使用边界 |
| --- | --- | --- | --- | --- | --- |
| 状态管理 | `flutter_riverpod: ^2.6.1` | 2.6.1 | MIT | Dart >=2.17、Flutter >=3.0 | Provider 声明和容器组装位于 `app/` 或 Feature presentation；领域接口不依赖 Riverpod 类型 |
| 声明式路由 | `go_router: ^17.0.0` | 17.0.0 | BSD-3-Clause | Dart ^3.7、Flutter >=3.29 | `app/` 持有全局 Router；Feature 只公开路径和页面契约 |
| 网络 | `dio: ^5.11.0` | 5.11.0 | MIT | Dart >=2.18 | Dio、Interceptor、CancelToken 和 DioException 只存在于 `core/network` 实现内部 |
| 普通存储 | `shared_preferences: ^2.5.3` | 2.5.3 | BSD-3-Clause | Dart ^3.5、Flutter >=3.24 | 使用 `SharedPreferencesAsync` 适配器；Feature 依赖项目自有存储接口 |
| 安全存储 | `flutter_secure_storage: ^10.3.1` | 10.3.1 | BSD-3-Clause | Dart >=3.3、Flutter >=3.19 | 插件选项和平台异常只存在于 `core/storage` 适配器 |
| 日志 | `logging: ^1.3.0` | 1.3.0 | BSD-3-Clause | Dart ^3.4 | 项目自有 logger/redactor/sink 包装 `LogRecord`，调用方不配置全局 Logger |
| 普通 SVG | `flutter_svg: ^2.2.2` | 2.2.2 | MIT | Dart ^3.7、Flutter >=3.29 | 由 `shared/` 的类型安全资源入口渲染本地 SVG，不开放网络 SVG 作为默认路径 |

所有许可证均从实际下载版本随包附带的 `LICENSE` 文件核对。MIT 与 BSD-3-Clause 均为宽松许可证，但再分发应用或模板时仍需保留相应版权和许可文本。

### 版本解析证据

在临时、未提交的 probe 中使用 Flutter 3.29.0/Dart 3.7.0 对上述约束执行了 `flutter pub get`。解析成功，直接依赖图为：

```text
dio 5.11.0
flutter_riverpod 2.6.1
flutter_secure_storage 10.3.1
flutter_svg 2.2.2
go_router 17.0.0
logging 1.3.0
shared_preferences 2.5.3
```

`flutter pub deps --style=compact` 证明候选的 `flutter_bloc` 与 `provider` 未留在最终依赖图中。`http` 和 `vector_graphics` 会由 `flutter_svg` 间接引入，但应用网络层不得借此建立第二套 HTTP 实现。

### 为什么不是全部使用 2026-08-09 的最新版

| 包 | 当前最新版 | 当前 SDK 可解析版本 | 最新版环境约束 | 结论 |
| --- | --- | --- | --- | --- |
| flutter_riverpod | 3.4.2 | 3.3.2 | Dart ^3.12（最新版） | 3.3.2 在当前 SDK 可解析，但跨 major，必须按迁移指南独立验证 |
| go_router | 17.4.0 | 17.0.0 | Dart ^3.10、Flutter >=3.38 | 保持 17.0.0，避免伪造兼容性 |
| dio | 5.11.0 | 5.11.0 | Dart >=2.18 | 使用最新版 |
| shared_preferences | 2.5.5 | 2.5.3 | Dart ^3.9、Flutter >=3.35 | 当前使用 2.5.3 的新异步 API |
| flutter_secure_storage | 11.0.0 | 10.3.1 | Dart >=3.8 | 保持 10.3.1，升级时审查 major migration |
| flutter_svg | 2.3.0 | 2.2.2 | Dart ^3.9、Flutter >=3.35 | 保持 2.2.2；不降低 SDK 校验 |
| logging | 1.3.0 | 1.3.0 | Dart ^3.4 | 使用最新版 |

初始版本、最新版下限和许可证数据来自 pub.dev Package API 与本机求解器，验证日期为
2026-08-09。2026-08-10 再次执行 `flutter pub outdated` 后，只有 Riverpod 出现高于当前约束的
可解析直接依赖：Current/Upgradable 为 2.6.1、Resolvable 为 3.3.2、Latest 为 3.4.2。该结果
修正了“2.6.1 是当前 SDK 最高可解析版本”的旧判断，但不改变已验证基线；3.x 仍需显式 major
迁移。其他直接依赖与 `flutter_lints` 的 Resolvable 仍等于锁定版本。完整时间点快照和操作步骤
见[依赖与 SDK 升级指南](../dependency-upgrades.md)。模板提交 `pubspec.lock` 后以锁文件保证应用
构建可复现；不得使用 `any` 依赖约束。

### 维护状态证据

| 包 | pub.dev 发布者 | 所选版本发布日期 | 最新版发布日期 | 判断 |
| --- | --- | --- | --- | --- |
| flutter_riverpod | dash-overflow.net | 2.6.1：2024-10-22 | 3.4.2：2026-07-28 | 项目活跃；3.3.2 已可解析，但采用 3.x 前必须完成显式 major migration |
| go_router | flutter.dev | 17.0.0：2025-11-06 | 17.4.0：2026-08-04 | Flutter 团队持续维护；功能稳定且有近期修复 |
| dio | flutter.cn | 5.11.0：2026-07-25 | 5.11.0：2026-07-25 | 当前最新版，近期仍在发布 |
| shared_preferences | flutter.dev | 2.5.3：2025-03-27 | 2.5.5：2026-03-25 | Flutter 官方插件持续维护；新版受 SDK 下限约束 |
| flutter_secure_storage | steenbakker.dev | 10.3.1：2026-05-27 | 11.0.0：2026-08-06 | 活跃维护；当前 major 需要随 SDK 升级 |
| flutter_svg | flutter.dev | 2.2.2：2025-11-04 | 2.3.0：2026-05-08 | 持续维护；兼容版本覆盖当前需求 |
| logging | dart.dev | 1.3.0：2024-10-17 | 1.3.0：2024-10-17 | Dart 团队稳定基础包，低变更频率与成熟 API 相符 |

发布日期由 pub.dev Package API 返回的 UTC 时间归并为日期。维护判断同时考虑发布者、近期版本和功能成熟度；它不保证未来维护，因此依赖升级流程仍需定期重新审查。

## 各能力选择理由

### 状态管理：Riverpod

选择 Riverpod 2.6.1，且第一阶段不启用 Riverpod 代码生成。

1. `AsyncValue` 能表达加载、数据、空数据和失败，符合示例 Feature 的异步状态要求。
2. Provider override 允许测试替换网络、存储、时钟和 Repository，无需再引入 DI 容器。
3. `autoDispose` 与 `ref.onDispose` 可以把请求取消和页面生命周期建立明确关系。
4. 业务实体和 Repository 接口保持普通 Dart 类型，Riverpod 仅参与组装与 presentation 状态。

Task 11 已用 `AppStateScope` 建立唯一根 ProviderScope，并由具体的
`AppThemeModeController` 验证全局同步状态；Task 12 的 `ExampleDetailController` 使用 Feature
专属 `AutoDisposeAsyncNotifier`/`AsyncValue`，通过 provider override 替换项目 Repository。
空数据、稳定错误、重试去重、依赖重建、取消和销毁规则见 ADR 0010；模板刻意不提供万能状态
基类。

代价是 2.6.1 落后于当前 3.x major。无论是否同时升级 Flutter/Dart 基线，Riverpod 3 迁移都
必须作为显式破坏性升级处理，不能在普通补丁升级中顺带完成。

### 路由：go_router

选择 Flutter 团队发布的 go_router。它直接覆盖路径参数、嵌套路由、未知页面、重定向和声明式 Router API。第一阶段使用手写路由表，不引入 `go_router_builder`，避免为有限路由增加生成链。

Task 10 已由 `app/` 中唯一的 `AppRouter` 接入 GoRouter，并通过独立 ShellRoute Navigator
隔离页面栈。示例 Feature 公开不依赖 go_router 的路径参数契约和只接收返回回调的页面；顶层
重定向使用项目自有同步策略接口，默认放行且不实现认证。参数校验、未知页安全呈现、生命周期
和测试规则见 ADR 0009。

### 网络：Dio

选择 Dio，因为 Goal 明确要求公共配置、拦截器、超时、请求取消和错误分类，这些都是 Dio 的直接能力。项目必须在适配器内把 `DioException`、`Response` 和 `CancelToken` 转换为项目自有类型；Repository 和 UI 不得导入 Dio。

默认日志拦截器不记录请求/响应正文，也不直接使用 Dio 的原始 `LogInterceptor` 输出敏感头。凭据注入和日志脱敏由项目自有拦截器负责。

Task 12 的 `NetworkExampleRepository` 已验证 Feature 只依赖项目 `NetworkClient` 的替换边界；
默认演示仍注入 bundled Repository，不访问真实网络或创建闲置 Dio 客户端。具体项目契约、请求
约束、超时、错误矩阵、取消生命周期与凭据安全规则见 ADR 0005，示例替换规则见 ADR 0011。


### 普通存储：SharedPreferencesAsync

选择 Flutter 团队维护的 shared_preferences，但只使用较新的 `SharedPreferencesAsync` API。其无进程内缓存，避免多 isolate 或多 engine 场景读取陈旧缓存。该插件明确不保证关键数据持久化，因此只保存主题、开关等可恢复偏好，绝不保存凭据或关键业务数据。

所选 2.5.3 文档支持 Android SDK 16+、iOS 12+；安全存储将项目有效 Android 最低版本提高到 API 23。

Task 7 已用项目自有 `PreferenceStore` 封装五种受支持类型和显式默认值。物理键使用固定 `app.preferences.` namespace，清理只把该 namespace 的键交给插件 allow-list；明显描述 Token、密码、Cookie、API key 等凭据的逻辑键会在接触插件前被拒绝。完整契约、并发限制和迁移规则见 `docs/architecture/0006-local-storage.md`。

### 安全存储：flutter_secure_storage

选择 flutter_secure_storage 10.3.1，通过 Android 加密实现和 iOS Keychain 保存敏感值。其 Android 最低版本为 API 23，因此模板原生配置必须使用 `minSdk 23` 或更高。iOS Keychain Sharing entitlement、Android backup 行为和插件异常映射在存储任务及原生配置任务中验证。

第一阶段只提供安全存储能力，不以此实现认证、Token 刷新或登录状态机。

Task 7 已固定 Android `app_secure_storage` namespace、RSA-OAEP/AES-GCM、关闭遇错自动清空并启用迁移备份保护；iOS 使用 `app.secure_storage` Keychain service、`unlocked_this_device` accessibility 且不启用 iCloud 同步。Android manifest 默认禁用系统备份，iOS Debug/Profile/Release 共用 Keychain entitlement。更改这些持久化身份或重新启用 Android 备份都属于需要迁移与平台验证的破坏性配置，详见 ADR 0006。

### 日志：package:logging + 项目门面

选择 Dart 团队维护的 package:logging 作为日志记录机制，因为它提供稳定级别、命名 logger 和可监听的 `LogRecord`。项目仍需提供自己的日志门面和 sink，以实现结构化上下文、按环境阈值和统一脱敏，并使测试能够捕获输出。

直接使用 `print`、`debugPrint` 或到处调用 `dart:developer.log` 无法集中保证脱敏与生产策略，因此不作为默认方案。

### SVG：flutter_svg

选择 flutter_svg 渲染随应用打包的普通 SVG。它覆盖当前阶段的本地矢量资源需求，同时保留语义标签和颜色过滤能力。默认不从网络加载 SVG，以免增加缓存、安全与不确定网络状态。

直接使用 vector_graphics 预编译可以优化复杂资源，但会增加生成流程；只有性能测量证明运行时解析是瓶颈时才考虑，当前不提前实现。SVG 转字体明确属于第二阶段。

Task 8 已通过 `AppAssets` 和不可由外部字符串构造的 `AppSvgAsset` 隐藏资源路径；调用方必须提供稳定宽高，并显式选择可访问标签或装饰排除。flutter_svg 只存在于 shared 资源渲染边界，不向 Feature 暴露 `SvgPicture`。当前使用逐文件 pubspec 登记和真实 AssetBundle Widget 测试，不增加无必要的资源生成链；完整主题、字体和资源规则见 ADR 0007。

### 基础组件：Flutter Material

加载、空、错误状态、确认弹窗和短时消息反馈直接组合 Flutter Material Widget，不引入另一套组件库、Toast 插件或屏幕适配依赖。Task 9 的共享包装器只统一布局、参数校验、语义和操作转发；状态生命周期、业务文案与副作用仍由 Feature 拥有。完整行为、大文字测试和回滚契约见 ADR 0008。

## 未选择的替代方案

| 能力 | 替代方案 | 未选择原因 |
| --- | --- | --- |
| 状态管理 | provider 6.1.5+1 | 依赖最少，但异步状态、取消和失败模型需要自行建立较多约定；无法像 Riverpod override 一样同时承担测试组装职责 |
| 状态管理 | flutter_bloc 9.1.1 | 状态转换明确且成熟，但对本模板的中等复杂度示例增加事件/Cubit 与 provider 组装层；异步依赖替换仍需额外约定 |
| 路由 | 原生 Router/Navigator 2 | 无第三方依赖，但参数、嵌套、重定向和错误页需要维护大量基础样板，违背脚手架减少重复工作的目标 |
| 路由 | auto_route | 功能充分，但默认依赖代码生成；本阶段路由规模不足以证明这条生成链的成本合理 |
| 网络 | package:http 1.6.0 | API 小且由 Dart 团队维护，但要满足统一拦截、细分超时和取消需要额外实现；Dio 与需求更直接匹配 |
| 普通存储 | Hive/数据库 | 超出简单偏好范围，且数据库明确不在第一阶段范围内 |
| 日志 | 仅 dart:developer | 无额外依赖，但需要自行补齐层级配置与记录分发；package:logging 已作为 go_router 的传递依赖，直接声明不会新增另一套机制 |
| SVG | 直接 vector_graphics 编译 | 性能潜力更高，但会引入资源编译和生成产物管理；当前没有性能证据支持这项复杂度 |

## 架构后果

1. `app/` 使用 Riverpod ProviderScope 组装依赖，但 `core/` 接口和 Feature domain 不导入 Riverpod。
2. `app/` 是唯一创建 GoRouter 的位置；Feature 不直接持有全局导航器。
3. Dio、shared_preferences、flutter_secure_storage、logging 和 flutter_svg 的第三方类型各自限制在对应 adapter/widget 边界。
4. 示例 Feature 的 Repository 接口必须能够由内存实现替换，默认测试和演示不访问真实网络。
5. Android 最低 API 由安全存储约束为 23，compile SDK 为 36，NDK 为 27.0.12077973；iOS 目标最低版本不得低于 12，并需要验证 Keychain 配置。
6. Riverpod 与路由均使用手写声明，不新增 build_runner 或通用生成框架。
7. `pubspec.lock` 属于应用模板的可复现构建证据，应提交版本控制。
8. SDK 支持范围与 CI 精确版本必须一起升级，不得只放宽 `pubspec.yaml` 而省略兼容性验证。

## 升级策略

1. Flutter 与 Dart SDK 作为一个基线整体升级，先在独立分支验证，再升级因 SDK 约束被锁住的依赖。
2. 每次升级运行 `flutter pub outdated`，区分“有新版本”和“当前 SDK 可解析版本”，不得用 dependency override 绕过 SDK 下限。
3. Riverpod、flutter_secure_storage 等 major 升级必须阅读官方 migration/changelog，并为状态生命周期、密钥读取和数据迁移补回归测试。
4. go_router、shared_preferences 和 flutter_svg 即使只提高 minor/patch，也要重新执行路由、平台存储和 SVG Widget 测试，因为这些包会随 Flutter 最低版本调整约束。
5. 发生解析或行为回归时，同时恢复 `pubspec.yaml` 与 `pubspec.lock`；不得只编辑锁文件。

逐依赖验证矩阵、SDK/CI pin、`.metadata` 语义、三环境平台构建和数据兼容回滚流程见
[依赖与 SDK 升级指南](../dependency-upgrades.md)。

## 验证命令与结果

以下命令已在临时 probe 中执行，不依赖当前仓库存在 Flutter 工程：

```bash
/mnt/c/Windows/System32/cmd.exe /d /c flutter --version
/mnt/c/Windows/System32/cmd.exe /d /c dart --version
/mnt/c/Windows/System32/cmd.exe /d /c flutter doctor -v
/mnt/c/Windows/System32/cmd.exe /d /c flutter pub get
/mnt/c/Windows/System32/cmd.exe /d /c flutter pub deps --style=compact
/mnt/c/Windows/System32/cmd.exe /d /c flutter pub outdated
```

结果：版本探测成功；最终七个直接依赖解析成功；依赖图中不存在第二套状态管理。该段记录
Task 1 当时的选择证据；2026-08-10 的复核已按上文修正 Riverpod Resolvable 结论，后续版本与
平台状态以锁文件、升级指南和工程门禁为准。

工程生成后，Task 2 与 Checkpoint A 又在仓库根目录执行了 `flutter pub get --offline`、`flutter pub deps --style=compact`、`flutter doctor -v` 和 Android Debug APK 构建。结果确认锁文件可离线解析、直接依赖版本与本 ADR 一致、Android licenses 全部接受，platform 36/NDK 27 配置能够实际编译。仍保留的工具链缺口只有非 macOS 主机无法编译 iOS，以及 `flutter doctor` 的 Maven 网络探测超时。

## 官方来源

1. [Flutter SDK archive](https://docs.flutter.dev/install/archive)
2. [flutter_riverpod on pub.dev](https://pub.dev/packages/flutter_riverpod)
3. [go_router on pub.dev](https://pub.dev/packages/go_router)
4. [dio on pub.dev](https://pub.dev/packages/dio)
5. [shared_preferences on pub.dev](https://pub.dev/packages/shared_preferences)
6. [flutter_secure_storage on pub.dev](https://pub.dev/packages/flutter_secure_storage)
7. [logging on pub.dev](https://pub.dev/packages/logging)
8. [flutter_svg on pub.dev](https://pub.dev/packages/flutter_svg)
9. [pub.dev Package API](https://pub.dev/help/api)
10. [Dart pub outdated](https://dart.dev/tools/pub/cmd/pub-outdated)
11. [Dart pub upgrade](https://dart.dev/tools/pub/cmd/pub-upgrade)
12. [Flutter SDK 升级](https://docs.flutter.dev/install/upgrade)
