# ADR 0009：声明式路由与应用导航边界

- 状态：Accepted
- 决策日期：2026-08-09
- 适用范围：第一阶段路由、参数解析、嵌套导航、未知页和可替换重定向入口

## 背景与范围

模板需要提供可直接运行的声明式路由基线，并让后续 Feature 能注册页面而不接管全局
Navigator。路径参数还可能来自外部深链；如果页面自行解析参数，非法值、原始 URI 或底层
路由异常容易进入业务状态和用户界面。

本决策使用已经锁定的 go_router 17.0.0，但把依赖限制在 `lib/app/router/`。它不实现登录、
会话刷新、认证页面、状态驱动的重定向刷新、系统级深链配置或通用路由代码生成；认证仍是
第二阶段能力。Task 12 已把详情位置接到示例 Feature 的真实页面和异步状态，Feature 仍不
导入 go_router，也不拥有全局导航生命周期。

## 路由表与导航层级

应用只有一个由 `AppRouter` 创建和释放的 GoRouter。当前公共位置为：

| 位置 | Navigator | 行为 |
| --- | --- | --- |
| `/` | ShellRoute 的嵌套 Navigator | 显示模板首页和进入示例详情的操作 |
| `/example/:itemId` | ShellRoute 的嵌套 Navigator | 只把已经验证的正整数 ID 交给 `ExampleDetailPage` |
| 其他 URI 或路由异常 | 根 Navigator | 显示不包含请求详情的固定未知页 |

根 Navigator 负责应用级错误边界；ShellRoute 使用独立 Navigator 保留应用壳层并隔离后续
Feature 页面栈。当前壳层只提供 Scaffold，不提前制造底部导航或标签页。详情页返回时优先
弹出嵌套栈；直接深链没有可弹历史时回到 `/`，避免留下无响应的返回操作。

`TemplateApp` 使用 `MaterialApp.router`，并在 ConsumerState 生命周期内持有 `AppRouter`。
`appThemeModeProvider` 更新时只重建消费主题的 Widget，保留 Router 和当前位置；应用名称或
重定向策略实例变化时，先成功创建替代 Router，再释放旧实例。根 Widget 销毁时幂等释放
Router；外部策略及其依赖仍由组装层拥有。

## Feature 路由契约

`ExampleRouteContract` 是示例 Feature 对 `app/` 公开的纯 Dart 契约。它只包含相对路径、
参数名、稳定路由名以及 ID 编解码，不导入 go_router、BuildContext 或 Navigator。应用层
拥有路由注册和全局导航生命周期，Feature 不得创建第二个全局 Router。

示例 ID 使用 1 到 999999999 的规范十进制形式。缺失值、零、符号、前导零、非数字和超过
九位上限的输入都被拒绝；非法参数不会抛给页面，也不会回显原始路径。程序内部构造位置时
同样验证范围，避免先生成无效链接再依赖错误页兜底。该上限是公共 URL 契约，改变有效集合
需要迁移说明和回归测试。

`ExampleDetailPage` 只接收已解析 ID 和应用层提供的 `onBack` 命令，不读取 Router 或
BuildContext 导航扩展。完整删除示例 Feature 时，从应用路由表移除详情注册、首页入口和
Feature import，再从应用组装入口移除 Repository override；不需要修改 `core/`、`shared/`
或启动编排实现。完整删除清单见 ADR 0011。

## 重定向策略

`AppRouteRedirectPolicy` 是项目自有的同步接口，只接收已解析 `Uri`，不暴露 go_router
State、BuildContext 或 Navigator。返回 `null` 或当前 URI 表示放行；返回其他 URI 表示请求
重定向。策略必须确定、允许重复调用、没有导航副作用，也不得记录可能来自深链的 query 或
fragment。

Router 只接受没有 scheme、authority、userinfo 且以单个 `/` 开头的站内绝对路径。非法外部
目标和策略抛错都进入固定安全错误页，不显示 URI 或异常正文。默认
`AllowAllAppRouteRedirectPolicy` 完全放行，它不代表用户已经登录。认证状态、异步刷新和
`refreshListenable` 等重新求值机制只有第二阶段认证模型确定后才能加入。

## 错误、安全与可访问性

go_router 的默认错误页可能展示异常文本和请求位置，因此 production 必须覆盖
`errorBuilder`。未知 URI、重定向目标校验失败和策略异常统一显示固定“页面不可用”状态；
非法示例参数显示另一种固定状态。两者均不把 URI、query、fragment、异常或堆栈传给 Widget。

首页、详情和错误状态都使用 SafeArea、可滚动内容和有界宽度，支持窄屏及放大文字。恢复操作
具有至少 48 逻辑像素高度；图标按钮提供 tooltip，错误标题使用 live-region 语义。新增路由
必须维持同等的参数验证、敏感信息隔离和无障碍基线。

## 测试与验证

聚焦测试覆盖以下行为：

1. 规范位置构造、参数上限及各类非法输入。
2. 首页和真实示例详情位于嵌套 Navigator，返回恢复首页，根 Navigator 与嵌套 Navigator
   相互独立。
3. 非法参数、未知 URI、非法外部重定向和策略异常都不泄漏原始数据。
4. 默认放行、替代策略重定向和“返回当前 URI”不会形成循环。
5. Router 重复释放安全，释放后不能继续取得配置；主题更新不丢失当前位置，应用名称或
   重定向策略变化时可以安全替换 Router；快速重复返回不会越过首页。
6. 320×568 视口和 2 倍文字缩放下，首页、详情 loading/data/empty/error 及路由错误状态没有
   布局溢出。

常规验证命令：

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build apk --debug --flavor dev \
  --dart-define-from-file=config/dev.example.json
```

当前 Widget 测试、Android APK 与远端 iOS 无签名构建验证 Dart 路由组装和编译边界，但实际
系统返回键、地址栏深链、进程恢复和 iOS Universal Links 仍需对应设备验证；编译通过不替代
这些平台集成测试。

## 取舍、迁移与回滚

手写有限路由表比引入 `go_router_builder` 更容易审查，也不会增加通用生成链。同步重定向接口
有意缩小第一阶段能力：策略不能在导航过程中发起网络请求或等待凭据刷新；未来认证模块应先
形成稳定会话状态，再让 Router 对该状态重新求值。

新增或变更公共路径、参数格式和路由名都可能破坏既有深链，应附迁移说明并同时更新 Feature
契约、应用注册和测试。若回滚本决策，先按 ADR 0011 删除依赖路由的示例 Feature，再把
`TemplateApp` 恢复为不使用 Router 的根 Widget，移除 `lib/app/router/`、对应测试和本 ADR；
不得顺带移除已锁定的 go_router 依赖决策、回退 Task 1-9 或修改用户文件。
