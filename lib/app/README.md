# app

`app/` 是 composition root，负责读取已验证配置并组装启动、路由、主题、全局 Provider 与 Feature 入口。

- 可以依赖 `core/`、`features/` 和 `shared/` 的公开契约。
- 不承载具体业务规则，也不把插件类型暴露给 Feature。
- `bootstrap/` 固定执行 Binding、异常处理器、配置、异步应用组装和 `runApp` 的顺序；所有 Flutter 全局调用隔离在可替换 runtime 中。
- 启动异常处理器在配置可用前使用固定安全 fallback，配置成功后一次性切换到按环境分级、统一脱敏的结构化 logger；原始错误不会进入 UI。
- `config/` 只解析非敏感 Dart 编译期值；缺失或非法环境由启动层捕获并显示不含内部细节的失败界面。
- `localization/` 维护 `en/zh` ARB、locale 回退、普通偏好边界和稳定错误 code 的用户文案映射；Flutter/intl 类型只存在于生成目录或应用门面，Feature 通过自有文案模型接收当前语言内容。
- `router/` 创建全局唯一的声明式 Router，集中持有根/嵌套 Navigator、参数验证、未知页和同步重定向入口；认证策略只读取 Riverpod 已发布快照，并用白名单 `returnTo` 处理登录、恢复 loading 与受保护位置。只有该目录可以依赖 go_router，Feature 只公开纯 Dart 路由契约。
- `state/` 提供唯一根 `AppStateScope` 和职责具体的应用级 Controller。production override 只绑定项目接口；不创建全局 ProviderContainer、万能状态基类或可能记录任意状态值的 observer。
- `theme/` 提供唯一 Material 3 亮暗主题和完整排版刻度，并消费 `shared/design/` 中由应用与跨 Feature 组件共用的参考稿间距/圆角 token。正常主题必须在 `AppScreenAdaptation` 下方用 context 创建，使组件外观和字号分别经过 `du/dsp`；Feature 通过 `Theme.of` 读取语义颜色和文字样式，不复制私有色板。
- `template_app.dart` 只接收已经验证的 `AppConfig` 和可替换重定向策略，不自行读取环境或存储；它先通过 `AppScreenAdaptation` 建立唯一 `375 x 812` 参考设计单位，再创建 `MaterialApp`、主题和 Router。它监听主题、语言和认证 provider 并拥有 Router 生命周期；认证监听只转成 go_router 刷新通知，不保存第二份会话，三类更新都不会重置无关导航状态。
- 启动组装在 ProviderScope 创建前读取语言普通偏好；失败时记录脱敏事件并跟随系统，不把可恢复偏好升级为启动失败。显式写入由 locale Controller 串行化，最新失败才回滚。
- 安全启动失败页使用明确的 1:1 fallback 主题和布局 token，不加载适配插件、静态资源或其他初始化结果；该入口不能被正常页面用来绕过设计单位。
- `router/` 中的首页和安全路由错误页使用统一安全滚动壳层；示例详情自行拥有一个 Scaffold/SafeArea，避免 Shell 嵌套 Scaffold 或重复消费系统 Insets。短屏、横屏和系统大字体下的主要操作均可滚动到达。
- production assembler 在配置与 logger 就绪后为示例 Feature 注入无 I/O 的 bundled Repository，并为认证注入安全 envelope adapter、明确未配置 gateway 和同一 logger。安全存储不可用时公开应用仍启动，但认证保存失败关闭且绝不降级到普通偏好。默认不创建 Dio；真实项目接入服务时，必须由该组装边界创建并释放 gateway 使用的基础客户端和业务请求使用的认证装饰器，再通过项目接口 override，不能让 Feature 持有插件或客户端生命周期。

完整启动时序见 `docs/architecture/0003-application-bootstrap.md`；错误与日志策略见 `docs/architecture/0004-application-errors-and-structured-logging.md`；存储初始化与平台边界见 `docs/architecture/0006-local-storage.md`；主题与资源规则见 `docs/architecture/0007-theme-and-type-safe-assets.md`；跨 Feature 状态与反馈组件见 `docs/architecture/0008-basic-state-and-feedback-widgets.md`；路由契约与生命周期见 `docs/architecture/0009-declarative-routing.md`；状态管理和异步生命周期见 `docs/architecture/0010-state-management-and-async-lifecycle.md`；示例组装、替换和删除边界见 `docs/architecture/0011-removable-example-feature.md`；认证接入、安全与回滚见 `docs/authentication.md`。
