# ADR 0010：状态管理边界与异步生命周期

- 状态：Accepted
- 决策日期：2026-08-09
- 适用范围：第一阶段 Riverpod 根容器、同步应用状态、异步状态约定和测试替换

## 背景与范围

模板已经锁定 Riverpod 2.6.1，但仅声明依赖并不能证明状态所有权、异步竞态和销毁行为。
Feature 如果各自随意选择 `ChangeNotifier`、裸 `setState`、全局容器或不同的重试规则，会重新
产生多套状态方案；反过来提前创建万能 AsyncNotifier 基类，又会把尚未出现的业务差异压进
不稳定抽象。

本决策落地唯一应用根容器、一个真实的应用级主题状态单元和可执行的异步生命周期契约。
Task 12 已按该契约实现 `ExampleDetailController`、Repository override 和详情页，作为真实
Feature 证据；测试专用夹具仍不进入 production。第一阶段不启用 Riverpod 代码生成，也不
增加 service locator、第二套状态包、全局 ProviderContainer、持久状态缓存或通用 ViewModel
基类。

## 容器与依赖边界

`AppStateScope` 是 production 唯一的应用级 ProviderScope 包装器。它只在 Flutter Binding、
异常处理和配置校验成功后由 application assembler 创建；根 Widget 销毁时，ProviderScope
释放 ProviderContainer，并触发所有 provider 的 `ref.onDispose`。启动失败页不依赖该容器，
因此状态初始化故障不会破坏最小 fallback。

`AppStateScope.overrides` 会复制为不可变快照，职责仅有两类：

1. `app/` composition root 把项目接口绑定到具体实现。
2. 测试把 Repository、数据源、时钟或存储接口替换为确定性替身。

Override 可以使用 Riverpod 类型，因为它位于 `app/`/测试组装边界；被注入的对象仍必须是
项目自有接口。Feature domain/data、`core/` 和 `shared/` 不得接收 Ref、ProviderContainer
或插件对象。模板不安装通用 ProviderObserver，因为任意状态值可能包含个人数据或凭据；
诊断必须在已有结构化日志边界使用稳定事件和脱敏上下文。

## Provider 位置与状态边界

Provider 按所有权放置，而不是集中到全局注册表：

1. 真正影响整个应用的状态位于 `app/state/`。
2. Feature 的依赖 provider 和 Controller 位于对应 Feature presentation/assembly 边界。
3. 业务实体、Repository 接口和数据源接口保持普通 Dart 类型，不导入 Riverpod。
4. `shared/widgets` 只接收状态和回调，不读取 Feature provider。

`appThemeModeProvider` 是当前唯一真实全局状态。`AppThemeModeController` 使用手写
Notifier，默认返回 `ThemeMode.system`，只更新内存且忽略重复值。它不读取普通存储、不组装
ThemeData，也不控制路由；因此 ThemeMode 更新只重建 `MaterialApp` 的消费部分，不会重建
或释放 `AppRouter`。后续持久化必须在明确的应用组装/偏好契约下设计失败策略，不能让该
Controller 直接导入 shared_preferences。

`exampleDetailProvider(itemId)` 是 Feature 自有的真实页面状态。它通过 family 隔离不同已验证
ID，通过 autoDispose 在页面离开时取消读取，不保留隐式缓存。`exampleRepositoryProvider`
只声明项目接口注入点；production 与测试都必须在 ProviderScope 组装边界提供实现，缺失
override 会被 Controller 转换为稳定 `UnexpectedAppError`，不会回显组装异常。

## 异步状态约定

页面级异步状态使用 Feature 专属的 `AutoDisposeAsyncNotifier<T>` 和 `AsyncValue<T>`。没有
额外的 `AppAsyncState` 包装层；这避免 loading/error 语义与 Riverpod 重复并保持调试工具
兼容。状态含义固定为：

| 状态 | 含义 | UI 处理 |
| --- | --- | --- |
| `AsyncLoading<T>` | 首次加载、依赖重载或显式重试正在进行 | 优先显示加载状态，不能触发第二次相同请求 |
| `AsyncData<T>` | 数据读取成功 | `null` 或集合为空时可显示空状态，空数据不是失败 |
| `AsyncError<T>` | 当前操作失败 | `error` 必须是稳定 `AppError`，UI 只使用安全 code/displayMessage |

AsyncValue 在刷新时可能同时保留 previous data/error 和 `isLoading=true`。页面必须明确决定
是否展示旧数据；需要完整加载状态时，应优先判断 `isLoading`，或调用 `when` 时显式设置
loading 跳过策略，不能因 previous value 存在而误报成功。

Repository 或基础设施应先把已知失败映射为具体 AppError；Controller 的最后边界仍要把未知
Object 折叠为 `UnexpectedAppError`。AsyncValue 可以保存诊断 stack trace 供框架处理，但 UI
和测试快照不得渲染 stack/error.toString，也不得把底层异常正文放回状态。页面销毁导致的
协作取消不展示错误状态。

## 重试、并发与释放

默认页面 Controller 每次只允许一个活动读取：

1. `build` 发布首次 loading，并创建一次项目自有取消令牌。
2. `retry` 在进入数据源前同步设置 loading；loading 期间的重复操作直接忽略，避免同一事件
   循环产生并行请求。
3. `ref.onDispose` 立即取消当前令牌并标记本轮失效；异步结果返回后必须再次检查本轮仍有效，
   迟到 data/error 不得修改已销毁或已重建的状态。
4. 依赖变化可能保留 AsyncNotifier 实例并重新执行 `build`。每轮 build 必须重置本轮标记、
   重新登记资源清理，并让上一轮 onDispose 先取消旧工作。
5. 页面 provider 默认使用 autoDispose，不调用 keepAlive。只有经过测量且有失效、内存和隐私
   策略的真实缓存需求才能例外。

该默认策略是单次读取的 single-flight，不是对所有业务的万能并发模型。搜索建议可能需要
latest-wins，支付/写入可能需要服务端幂等和禁止自动重试；这些规则必须留在拥有业务语义的
Feature Controller，并用专门测试证明，不能通过通用基类猜测。

## 测试契约

`createTestProviderContainer` 为每个测试创建独立 ProviderContainer，并通过 `addTearDown`
保证断言失败时仍释放容器。测试使用 override 注入项目接口替身，不访问真实网络、存储、
时钟或平台通道。根 Widget 测试另行证明已挂载 `AppStateScope` 可以应用同一 provider 的替代
override，并在卸载时释放容器。

Task 11 的测试专用 AsyncNotifier 夹具是上述规则的可执行规范，不进入 `lib/`。它覆盖：

1. 首次 loading 到非空 data。
2. 空集合仍为成功 data。
3. 原始异常转换为不泄漏详情的 AppError，失败后重试成功。
4. loading 期间重复 retry 不创建额外请求。
5. autoDispose 取消活动工作，迟到完成不复活旧状态。
6. 依赖重建取消旧操作、忽略旧结果，并允许保留的 Notifier 实例继续重试。

Task 12 的真实 `ExampleDetailController` 已独立覆盖 loading、成功、空、未知错误稳定化、既有
`AppError` 原实例保留、retry 去重、autoDispose、依赖重建、请求取消和迟到 data/error 隔离，
未继承测试夹具或万能基类。契约夹具继续留在 test，用于约束后续 Feature；只有出现两个已
证明相同的 production 实现时才评估抽取。

## 验证、迁移与回滚

常规验证命令：

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build apk --debug --flavor dev \
  --dart-define-from-file=config/dev.example.json
```

升级 Riverpod major 时必须重新验证 ProviderScope override 更新、Notifier build 重执行、
AsyncValue previous-state 标记、autoDispose 调度、ProviderContainer 测试释放和 Router 保留。
不得同时迁移状态包、生成方式和业务 Controller；这些变化必须拆分并保留回滚路径。

仅回滚 Task 11 前必须先按 ADR 0011 移除依赖 ProviderScope 的 Task 12 示例。随后把
`TemplateApp` 恢复为 StatefulWidget 与显式 ThemeMode 参数，移除 `lib/app/state/`、状态测试
与测试容器 helper，从 production assembler 移除 AppStateScope，并撤销 ADR 0001、0003、
0007、0009 和模块 README 中仅与 Task 11 有关的补充。不得移除已锁定的 Riverpod 依赖决策、
回退 Task 1-10、修改根 `AGENTS.md` 或 Goal 原文。
