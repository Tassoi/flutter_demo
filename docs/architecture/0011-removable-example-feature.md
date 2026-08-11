# ADR 0011：可删除的中立示例 Feature

- 状态：Accepted
- 决策日期：2026-08-09
- 适用范围：第一阶段示例业务模块、应用组装和删除边界

## 背景与范围

脚手架需要用一条真实纵向切片证明路由、状态、Repository、网络契约、稳定错误和基础组件能够
协作。示例又不能假定模板使用者已有服务、凭据或具体业务，因此默认项目必须在 `.invalid`
API 配置下直接运行，模块也必须能完整删除。

本决策实现一个只读取单条中立记录的 `example` Feature。它不实现认证、缓存、数据库、离线
同步、通用 Mock 服务、代码生成或环境驱动的数据源切换，也不把示例规则提升为万能基类。

## 模块边界

| 目录 | 职责 | 禁止内容 |
| --- | --- | --- |
| `domain/` | 校验并保存 `ExampleItem`；声明 `ExampleRepository` | Riverpod、Flutter、插件、路由 |
| `data/` | bundled 与网络两种窄 Repository 实现 | UI、Provider、客户端所有权、缓存 |
| `presentation/` | family Controller、异步生命周期和详情页面 | go_router、Dio、具体存储插件 |
| `routing/` | 稳定路径、参数名及 ID 编解码 | Router 实例、BuildContext、Navigator |

`ExampleItem` 在构造时裁剪首尾空白，并限制正整数 ID、80 字符标题和 600 字符描述。校验错误与
`toString()` 不回显标题或描述，避免外部响应内容进入诊断文本。`ExampleRepository` 返回
`ExampleItem?`：对象表示成功数据，`null` 表示成功但没有匹配项，失败必须抛稳定 `AppError`
或由 Controller 在最后边界稳定化。

## 默认数据源与网络替换

production composition root 默认创建 `BundledExampleRepository`，通过
`exampleRepositoryProvider` override 注入根 `AppStateScope`。bundled 集合不可变，只含一条
确定性记录，不读取网络、存储、文件、时钟或平台通道，也没有需要释放的资源。它不是缓存或
Mock 服务，而是脚手架在没有真实后端时的安全演示数据源。

`NetworkExampleRepository` 展示真实项目的替换边界。它只接收项目自有 `NetworkClient`，发送
公开 GET 请求 `examples/{itemId}`，不要求凭据；decoder 只接受 `null` 或 ID 匹配、字段完整的
JSON object。响应形状、领域校验或 ID 不匹配都转换为 `NetworkResponseParseError`，原始 payload
不进入错误文本。Repository 不关闭客户端，因为客户端可能被多个 Repository 共享，生命周期
必须由创建它的 `app/` 组装边界拥有。

要启用真实服务，项目必须显式完成以下操作：

1. 在配置与 logger 已成功初始化后，由 `app/` 创建 `NetworkClient`。
2. 使用该客户端构造 `NetworkExampleRepository`，替换 bundled override。
3. 在 `app/` 增加与根应用生命周期绑定的资源所有者，在释放时关闭客户端，并为具体 API
   协议补充契约测试；当前模板不会为了未启用的客户端预建通用资源托管器。
4. 保持 Feature 不导入 Dio；需要认证时等待第二阶段会话模型，不在示例中添加临时 Token。

模板不根据环境、URL 或网络可达性隐式切换两个实现。隐式 fallback 会混淆真实空数据与连接
失败，也会形成未定义的缓存语义。

## 状态、错误与页面行为

`exampleDetailProvider(itemId)` 为每个已验证 ID 创建独立的 autoDispose
`ExampleDetailController`。首次进入发布 loading 并读取一次 Repository；成功对象进入 data，
成功 `null` 进入 empty，稳定错误进入 error。页面使用共享的加载、空和错误组件，成功内容保持
有界且可滚动。

同一时刻只允许一个读取。重试在调用 Repository 前同步发布 loading，连续点击不会创建并行
请求。每轮读取都有项目取消令牌和 generation；页面销毁或 provider 重建会取消旧令牌，迟到
结果不能覆盖替代状态。Repository 的 `AppError` 保留语义，其他对象统一转换为
`UnexpectedAppError`，页面只渲染安全 `displayMessage`。

应用路由层先解析并验证 ID，再构造 `ExampleDetailPage`。页面不读取 go_router，只通过
`onBack` 把用户命令交还应用；应用优先弹出当前栈，直接深链没有历史时回到 `/`。因此 Feature
页面既可独立测试，也不会接管全局导航。

第二阶段 Task 4 后，详情页拥有自身唯一 `Scaffold`/`SafeArea`，固定顶部返回与标题区域，
loading/empty/error 和成功正文各自在剩余空间内滚动。页面只导入项目 `du/dsp` 扩展并从主题
读取排版，不直接依赖 `flutter_screenutil`；根初始化、安全滚动壳层、触控下限和适配器仍位于
`shared/`/`app/`。因此删除本 Feature 不会删除或破坏手机适配底座。

## 组装点与完整删除

Feature 之外只有两个 production 注册点：

1. `lib/app/bootstrap/app_bootstrap.dart` 创建 bundled Repository 并 override
   `exampleRepositoryProvider`。
2. `lib/app/router/app_router.dart` 注册详情路径、首页入口和应用拥有的返回包装页。

完整删除示例时按以下顺序操作：

1. 从 `app_router.dart` 删除三个 Feature import、详情子路由、首页按钮及
   `_ExampleDetailRoute`（包括应用层向详情页注入的 `ExampleDetailCopy`）；保留
   `AppRouter`、ShellRoute、未知页和重定向基础设施。
2. 从 `app_bootstrap.dart` 删除两个 Feature import、`BundledExampleRepository` 实例和对应
   provider override；保留 `AppStateScope` 及其他应用状态。
3. 删除 `lib/features/example/`、`test/features/example/` 和
   `test/support/features/example/`。
4. 删除或改写 `test/app/router/app_router_test.dart` 与 `test/app/template_app_test.dart` 中的
   示例 import、override 和详情断言。
5. 运行格式、分析和全量测试；删除不需要修改 `core/`、`shared/` 或启动 runtime。

Task 17 已在临时副本实际执行该清单并验证基础工程；当前工作区继续保留示例，供新项目先阅读
纵向切片再自行裁剪。

## Task 17 物理裁剪证据

2026-08-10 使用 `rsync` 把当前工作树复制到独立 Windows 临时目录，明确排除 `.git`、
`.dart_tool` 与 `build`。验收副本执行了以下真实改动：

1. 从 bootstrap 删除 bundled Repository、provider override 和两个 Feature import。
2. 从 Router 删除详情路径、参数错误分支、首页入口、返回包装页和两个 Feature import；保留
   ShellRoute、基础首页、安全未知页和可替换重定向策略。
3. 物理删除 `lib/features/example/`、`test/features/example/` 和
   `test/support/features/example/`。
4. 重写应用路由与根应用测试，只验证基础首页、主题、Router 替换、未知位置、重定向安全、
   错误脱敏和窄屏大字布局。

删除后，`lib/` 和应用测试中不再存在 `package:flutter_template/features/example`、
`exampleRepositoryProvider`、`ExampleRouteContract`、`open-example-detail` 或
`template-detail-route` 引用。架构检查器测试中保留的 `template_app/features/example`
字符串是用于证明违规依赖会被拒绝的内存夹具，不是运行时或测试依赖。

临时副本的验证结果为：

1. 锁定依赖解析、生成产物新鲜度、40 个 Dart 文件架构检查和 3 环境/24 文件平台检查通过。
2. 格式检查 74 个文件且 0 改写；严格分析为 `No issues found`。
3. bootstrap、Router 与根应用 17 项聚焦测试通过；固定 seed `20260809` 的 167 项剩余
   全量测试通过。
4. `flutter build apk --debug --flavor dev` 使用 `config/dev.example.json` 实际成功；
   APK 为 198603508 bytes，SHA-256 为
   `7a01dd5bb4a6390a877bd1ee7b49ca53217f99d135ac7cb1f8c45176dde43052`。

验收只操作临时副本，没有删除或改写主工作区的示例源码。证据记录后，初始化探针移入系统
回收站；1.1 GB 裁剪副本因 Windows 挂载目录不支持 `gio trash`，在确认精确路径、无符号链接
且无持有该路径的进程后永久删除。两处临时根都已确认不存在。

## Task 4 适配后物理裁剪复验

2026-08-10 在主题、共享组件、路由页和示例详情全部接入 `du/dsp` 后，再次创建隔离 Windows
临时副本并执行完整裁剪。副本明确排除 `.git`、`.dart_tool`、`build` 和 `coverage`；主工作区
始终保留 Feature。除按本 ADR 删除 bootstrap/Router 注册点及三个示例目录外，本次还移除了
依赖示例流程的 Golden，并把副本内的 Router、根应用和六档页面矩阵测试收敛为基础首页、
未知路由与安全返回，不通过保留死测试掩盖 Feature 依赖。

物理删除后，副本的可执行 Dart 文件不再引用
`package:flutter_template/features/example`、`exampleRepositoryProvider`、
`ExampleRouteContract`、`open-example-detail`、`template-detail-route` 或
`BundledExampleRepository`。手机设计单位、正常/安全 fallback 主题、安全滚动壳层、共享状态
与反馈组件都继续位于 `shared/`/`app/`，删除 Feature 不要求修改这些基础设施实现。

复验结果如下：

1. 锁定依赖解析、生成产物检查、43 个 Dart 文件架构门禁和 3 环境/25 文件平台门禁通过。
2. 格式检查覆盖 82 个文件且 0 改写；严格分析为 `No issues found`。
3. 固定 seed `20260809` 和默认顺序的剩余全量测试均为 206 项通过。
4. dev Debug Android APK 实际构建成功，大小为 198672527 bytes，SHA-256 为
   `faf47585731aa529e825f77a1748d1148be7badab46f3cd530d4498740c01e26`。

验证完成后先尝试系统回收站；Windows 挂载副本不支持该能力，因此只在校验精确 realpath、
目录大小和测试/构建均已结束后，按该唯一临时根自底向上清理。两个临时目录随后均确认不存在，
没有触碰主工作区源码、用户原生平台改动或其他目录。

## 测试证据

Feature 测试使用确定性 Repository/NetworkClient 替身，不访问 Socket、真实存储、时钟、文件
或平台通道，覆盖：

1. 领域值归一化、长度边界、非法 ID 和诊断脱敏。
2. bundled 正常/缺失/取消，以及网络请求契约、正常/空/畸形响应和稳定传输错误。
3. Controller 的 loading、data、empty、未知错误映射、稳定 `AppError` 保留、重试去重、
   autoDispose、依赖重建，以及迟到 data/error 隔离。
4. 页面返回交互、错误后重试，以及六档手机视口各自正常/200% 文字下的真实路由流程；页面
   专项测试继续覆盖 320×568 下的 loading/data/empty/error 和 80/600 字符无空格边界值。
5. 路由参数解析、真实详情接入、未知位置、重复返回和安全返回行为。

常规验证命令：

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build apk --debug --flavor dev \
  --dart-define-from-file=config/dev.example.json
```

## 取舍、风险与回滚

bundled 默认值让模板离线可运行，但不能证明真实服务协议或设备网络行为；项目启用真实 endpoint
时仍需针对 API、TLS、服务端错误码和生命周期补集成测试。当前页面界面文案已由应用层通过
`ExampleDetailCopy` 注入国际化资源；bundled 标题和描述仍是中立英文领域示例数据，不属于界面
文案资源，具体项目需要本地化领域内容时必须先定义稳定的产品数据协议。

回滚 Task 12 等同于按“完整删除”清单移除示例。不得因此删除 Riverpod、go_router、网络错误、
共享状态组件或其他第一阶段基础设施；这些能力有独立消费者、测试或后续第一阶段用途。不得
修改根 `AGENTS.md`、Goal 原文或用户已有文件。
