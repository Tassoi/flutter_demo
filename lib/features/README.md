# features

`features/` 按业务能力纵向组织模块。Feature 可以依赖 `core/` 和 `shared/` 的公开接口，但不得直接访问其他 Feature 的内部实现。

示例 Feature 必须保持可整体删除，基础设施不能反向依赖它的内部类型。当前 `features/` 包含
中立示例与可裁剪认证能力；两者之间没有依赖。

`example/` 是一条中立、可运行的纵向切片：

- `domain/` 保存不可变 `ExampleItem` 和纯 Dart `ExampleRepository` 接口。
- `data/` 提供默认无 I/O 的 `BundledExampleRepository`，以及只依赖项目 `NetworkClient` 的
  可替换 `NetworkExampleRepository`。默认运行不会访问 `.invalid` 地址或真实服务。
- `presentation/` 保存 family autoDispose Controller 和 loading/data/empty/error 页面；页面只
  接收应用传入的返回回调，不读取 Router 或插件。
- `routing/` 只公开路径、参数名和 ID 编解码契约，不导入 go_router、BuildContext、Navigator
  或 `app/`；唯一 Router 和路由注册仍由应用组装层拥有。

Feature 的 Riverpod provider 只放在自身 presentation 边界，domain、Repository 和数据实现
保持普通 Dart 类型。成功 `null` 表达空状态，失败只向 UI 暴露稳定 `AppError`；重试、取消、
依赖重建和迟到结果规则见 `docs/architecture/0010-state-management-and-async-lifecycle.md`。在出现
两个已证明相同的真实 Controller 前，不把状态逻辑抽到 `shared/` 或万能基类。

删除 `example/` 时，只需同时清理 `lib/app/router/app_router.dart` 中的详情注册、首页按钮和
包装页，以及 `lib/app/bootstrap/app_bootstrap.dart` 中的 bundled Repository override；随后
删除对应 Feature 测试和应用测试中的示例断言。`core/`、`shared/`、路由基础设施与启动编排
不需要修改。逐文件清单、替换网络实现的所有权和回滚方式见
`docs/architecture/0011-removable-example-feature.md`。

`auth/` 是第二阶段最小认证纵向切片：

- `domain/` 保存敏感凭据模型、稳定失败、可替换 `AuthGateway`、时钟和网络协作接口；不规定
  后端 URL、传输字段、社交登录或具体账号规则。
- `data/` 使用项目 `SecureValueStore` 保存单一版本化 envelope，并提供凭据注入和 401
  单飞刷新装饰器；不直接依赖 Dio 或安全存储插件。
- `presentation/` 的 Riverpod controller 是唯一会话所有者，私有保存凭据并以 generation、
  取消令牌和串行持久化阻止退出后的迟到结果；页面不导入 Router。
- `routing/` 只公开登录、恢复 loading、受保护位置和严格 `returnTo` 白名单；唯一 Router
  仍由 `app/` 注册。

默认 gateway 不访问网络且明确失败，因而模板不包含真实服务或本地测试账号。删除认证前，已
上线项目必须先用仍包含该模块的迁移版本精确清除 `auth.session`，再移除 Feature、应用路由/
组装、本地化文案和测试；不得全量清空安全存储。接入、测试与完整回滚见
`docs/authentication.md`。
