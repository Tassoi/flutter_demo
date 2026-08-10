# features

`features/` 按业务能力纵向组织模块。Feature 可以依赖 `core/` 和 `shared/` 的公开接口，但不得直接访问其他 Feature 的内部实现。

示例 Feature 必须保持可整体删除，基础设施不能反向依赖它的内部类型。当前 `example/` 是一条
中立、可运行的纵向切片：

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
