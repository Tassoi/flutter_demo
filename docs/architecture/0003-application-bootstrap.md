# ADR 0003：集中且可测试的应用启动流程

- 状态：Accepted
- 决策日期：2026-08-09
- 适用范围：第一阶段应用启动、初始化失败和进程级异常入口

## 背景

应用需要在任何插件或业务代码运行前完成 Flutter Binding、环境校验和异常监听，并且只有全部必要依赖组装成功后才调用 `runApp`。如果这些职责散落在 `main.dart`、Widget 构造函数或 Feature 中，初始化顺序难以证明，测试会触碰 Flutter 全局状态，配置失败也容易把异常文本或内部地址暴露给用户。

本决策最初只建立启动编排和最后一道进程级捕获边界。Task 5 现已按 `ADR 0004` 接入稳定应用错误、结构化日志和统一脱敏。Task 6/7 提供网络和存储 adapter；Task 12 的默认示例只在 production assembler 创建无 I/O、无需释放的 `BundledExampleRepository`，并通过项目接口 override 注入。可替换的网络 Repository 不会让默认启动创建闲置 Dio 客户端，存储目前也没有消费者。Task 10 由 `TemplateApp` 在 Widget 生命周期内创建唯一 Router；Task 11 在配置及异常边界就绪后用 `AppStateScope` 创建唯一 Provider 容器。这些对象都在配置成功后组装，不改变“先完成必要异步初始化，再挂载应用”的顺序，也不构成 service locator 或独立 DI 容器。

## 决策

### 最小平台入口

`lib/main.dart` 只调用 `bootstrapApplication()`。Android 与 iOS 平台入口不自行读取配置、构造服务或调用 `runApp`，确保所有启动方式共享同一时序和失败策略。

`bootstrapApplication()` 先创建不依赖其他服务的 `SafeStartupErrorReporter` 和一次性 `DeferredStartupErrorReporter`，再在 guarded root Zone 内创建并运行 production `AppBootstrap`。配置校验成功后，assembler 创建环境化 logger 并把代理绑定到结构化 reporter；绑定前不缓存或重放原始错误。Binding 初始化、错误处理器安装以及最终 `runApp` 都发生在同一个 Zone；这点很重要，因为 `PlatformDispatcher` 会记住设置 `onError` 时的 `Zone.current`。

### 固定初始化顺序

`AppBootstrap.run()` 每个进程只能调用一次，顺序固定为：

1. `WidgetsFlutterBinding.ensureInitialized()`。
2. 安装 `FlutterError.onError`、`PlatformDispatcher.instance.onError` 和安全 `ErrorWidget.builder`。
3. 调用 `AppConfig.fromDartDefines()`，严格校验 `APP_ENV` 和公开 API 配置。
4. `await` application assembler，等待依赖初始化并得到完整根 Widget。
5. 调用 runtime 的 `runApplication()`，由 production adapter 委托给 Flutter `runApp`。

第 4 步使用聚焦的 `Future<Widget> Function(AppConfig)` 依赖组装契约。测试可以用未完成的 `Completer` 证明第 5 步不会提前发生；后续服务必须在 assembler 内按明确顺序初始化，并在自身失败时释放已经取得的资源。应用代码通过显式构造或 `AppStateScope` 的项目接口 override 接收依赖，不通过 `AppBootstrap`、全局 ProviderContainer 或 service locator 查找服务。

### Flutter 全局 API 隔离

`AppBootstrapRuntime` 只封装三个进程级副作用：Binding、异常/失败呈现回调和 `runApp`。production 使用 `FlutterAppBootstrapRuntime`，编排测试使用记录型替身，因此常规测试不会改写 `FlutterError.onError`、`PlatformDispatcher.instance.onError` 或 `ErrorWidget.builder`。

只有 runtime adapter 的针对性测试会安装真实回调，并在测试结束时恢复原值，避免执行顺序或全局污染。Flutter 默认 debug `ErrorWidget` 会显示 `exception.toString()`；production runtime 将其替换为固定的 “Unable to render this content.”，原始详情仍只进入 reporter。runtime 不读取配置、不组装依赖，也不包含业务规则。

## 失败与异常策略

| 失败位置 | 捕获入口 | 行为 | UI 是否接收原始错误 |
| --- | --- | --- | --- |
| Binding 初始化 | guarded root Zone | 安全报告；Flutter 尚不可依赖，因此不尝试渲染 | 否 |
| 全局处理器安装 | guarded root Zone | 安全报告；处理器不完整时停止继续启动 | 否 |
| 配置解析 | `AppBootstrap` 初始化边界 | 报告后挂载 `StartupFailureApp` | 否 |
| 异步依赖/应用组装 | `AppBootstrap` 初始化边界 | 报告后挂载 `StartupFailureApp` | 否 |
| 首次 `runApp` 同步失败 | `AppBootstrap` 初始化边界 | 报告后尝试挂载 dependency-free fallback | 否 |
| Flutter framework 回调 | `FlutterError.onError` + 安全 `ErrorWidget.builder` | 报告；需要替换损坏子树时只显示固定文本 | 否 |
| engine/platform 异步回调 | `PlatformDispatcher.onError` | 报告并返回 `true`，避免重复的非结构化输出 | 否 |
| guarded Zone 内其他同步或未处理异步错误 | `runZonedGuarded` | 最后兜底报告，不猜测恢复方式 | 否 |

`StartupFailureApp` 的构造函数不接收 exception、stack trace 或自定义诊断文本，只显示固定状态并提供 live-region 无障碍语义。这样即使配置文本错误地包含凭据，原始对象也没有进入 Widget 树的通道。页面复用仅由 Flutter API 和本地常量构成的 Material 3 亮暗主题，但不加载 SVG 或依赖配置、存储和插件初始化；主题规则见 ADR 0007。页面不提供重试按钮，因为当前尚无可证明安全的资源回收和重试协议。

`StartupErrorReporter` 会收到原始错误与堆栈，供隐私安全的实现分类和诊断；实现必须同步且不得抛异常。配置读取具有独立 source，避免把依赖组装中的解析异常误判成配置错误。`SafeStartupErrorReporter` 只写入错误发生的边界和稳定 error code，不调用 `error.toString()`、不格式化 stack trace，因此在配置或日志初始化失败时不会输出 Token、密码、内部地址或个人数据。logger 可用后，`LoggingStartupErrorReporter` 把错误转换为稳定 code，并把原始详情只交给统一脱敏边界；logger 或 sink 失败时仍回到安全 fallback。完整策略见 `ADR 0004`。

安全 fallback 还会隔离最终控制台 writer 的异常。writer 已位于 guarded root Zone 的最后诊断边界，继续抛出既无法恢复业务，也可能越过或递归触发同一个异常处理器，因此失败时只放弃该条诊断，不再格式化或转发原始对象。

## 可测试性与验收证据

`AppBootstrap` 显式注入 runtime、配置读取器、异步 assembler、失败 Widget factory 和 reporter。测试因此可以确定性验证：

1. Binding、处理器、配置、组装和 `runApp` 的精确顺序。
2. 未完成的异步组装不会提前挂载 Widget。
3. 配置同步失败和组装异步失败都会报告并运行同一个 fallback。
4. guarded Zone 能捕获同步异常和通过 microtask 逃逸的异步异常，不使用延时等待。
5. Flutter 与 platform 回调保留原始 error/stack/source，且 platform 回调返回已处理。
6. debug `ErrorWidget` 与安全 reporter 都不输出原始异常或堆栈内容。
7. 失败页面在 320×568 视口无溢出，具有明确语义且不显示内部异常文本。
8. 安全 reporter 的最终 writer 抛错时仍保持非抛出语义，不让诊断故障逃出 root Zone。

常规验证命令：

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build apk --debug --flavor dev \
  --dart-define-from-file=config/dev.example.json
```

当前主机不是 macOS；Dart 启动代码由 Android 构建、分析和测试验证，远端 macOS CI 也已完成
iOS 三环境无签名编译。真实签名和设备启动失败行为仍需业务项目补证。

## 取舍与后续边界

1. production reporter 已使用结构化事件、稳定 error code 和 runtime type，但按环境策略不保留异常正文或堆栈；这是隐私优先的明确取舍。
2. Binding 或错误处理器安装失败时不显示 Flutter fallback，因为此时继续依赖 Flutter 渲染可能掩盖或递归触发故障。
3. 启动重试、部分资源回收和超时需要结合后续真实依赖逐项定义，本任务不预留通用生命周期框架。
4. 本决策本身没有引入第三方依赖、第二套日志方案或认证重定向；后续 Task 10-12 按 ADR 0009-0011 在根 Widget 内接入 Router、ProviderScope 和示例 Repository override，但导航、状态与数据规则仍留在各自所有权边界。

## 回滚

回滚本决策时，只恢复 `lib/main.dart` 的直接最小入口，移除 `lib/app/bootstrap/`、`lib/app/template_app.dart`、对应测试与本 ADR，并把配置文档恢复为“尚未接入启动”。不得改动 `AppConfig` 的既有解析规则、Android/iOS 工程、其他 Goal 任务或用户文件。
