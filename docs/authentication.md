# 认证模块指南

认证模块提供登录、退出、启动恢复、安全持久化、访问凭据注入、单飞刷新、会话失效和路由
重定向的项目边界。模板不规定服务端 URL、字段名、账号规则或第三方登录方式，也不内置可用
测试账号。默认 `UnconfiguredAuthGateway` 明确失败且不访问网络，因此公开首页和示例 Feature
始终可以直接运行；只有项目接入自己的 `AuthGateway` 后，登录才可能成功。

## 文件与所有权

```text
lib/features/auth/
├── domain/                         # 纯 Dart 凭据、失败、gateway、时钟和会话协作契约
├── data/                           # 安全 envelope、网络装饰器和凭据注入 adapter
├── presentation/                   # Riverpod 会话所有者与无 Router 依赖的页面
└── routing/                        # 纯 Dart 路径、保护范围和 returnTo 白名单
lib/app/
├── bootstrap/app_bootstrap.dart    # production 安全存储、logger 与默认 gateway 组装
├── router/app_router.dart          # 唯一路由注册和本地化文案注入
├── router/auth_app_route_redirect_policy.dart
└── template_app.dart               # Riverpod 状态到 go_router 刷新通知的无状态桥接
```

`features/auth` 不创建 Router，不导入 go_router，不读取 Dart define，也不直接依赖
`flutter_secure_storage` 或 Dio。`app/` 只负责组装和导航；`core/` 继续保持无认证业务规则，认证
通过第一阶段公开的 `NetworkClient`、`NetworkCredentialProvider`、`SecureValueStore`、
`AppLogger` 和 `AppRouteRedirectPolicy` 协作。

## 会话状态与生命周期

Riverpod 的 `authSessionProvider` 是唯一会话状态所有者。公开 `AuthSessionState` 只保存稳定阶段
和安全失败分类，不保存账号、密码、用户对象或任何凭据：

| 阶段 | 含义 | 受保护路由行为 |
| --- | --- | --- |
| `restoring` | 正在读取并验证安全 envelope | 进入固定 loading route |
| `signedOut` | 没有可用会话 | 进入登录页 |
| `signingIn` | 登录提交进行中，重复提交被拒绝 | 保持登录页 |
| `authenticated` | 私有内存中存在可用或可刷新的凭据 | 放行白名单受保护路由 |
| `failure` | 最近操作失败，当前按未认证处理 | 进入登录页并显示稳定文案 |

Controller 构建后立即开始一次恢复。缺失 envelope 正常进入 `signedOut`；损坏或读取失败进入
`AuthPersistenceFailure` 并尽力删除坏数据；access 已过期但 refresh 仍有效时执行一次共享刷新；
refresh 也失效时清空会话。所有时间都转换为 UTC，到达失效时刻即视为不可用，不存在隐藏宽限期。

每次登录替换、退出或会话失效都会先递增 session generation、清空内存凭据并取消认证模块
拥有的登录/刷新令牌，再等待 I/O。任何迟到结果在保存或发布前都必须重新核对 generation；
Provider 销毁后也不会更新状态。安全存储读写由同一串行队列编排，使旧 refresh 的保存一定早于
随后退出的删除，避免旧凭据在退出后重新落盘。

## 安全 envelope

`SecureAuthCredentialPersistence` 只使用 `SecureValueStore` 的单个物理键
`auth.session`。schema 1 是一个完整 JSON envelope：

| 字段 | 类型 | 约束 |
| --- | --- | --- |
| `schemaVersion` | integer | 必须精确为 `1` |
| `accessCredential` | string | 非空、无首尾空白和控制字符 |
| `refreshCredential` | string | 与 access 使用同一安全校验 |
| `accessExpiresAtMs` | integer | UTC Unix 毫秒 |
| `refreshExpiresAtMs` | integer | 不得早于 access 失效时间 |

读取拒绝未知、缺失、多余或错误类型字段，且错误对象不回显 JSON、键或插件异常。写入采用一次
单键覆盖，不把 access 与 refresh 分成两个可能部分成功的值。任何保存失败都会失败关闭，不能
建立“只在内存有效”的伪会话；任何情况下都不得回退到 `PreferenceStore`、Dart define、源码
常量或可提交配置。

修改字段、时间精度或键名属于数据迁移。应新增 schema 版本和向前兼容读取测试，并先证明旧
版本能够安全清理或迁移；不得直接就地改变 schema 1 的含义。

## 接入项目服务端

接入真实服务时按以下顺序实施：

1. 在项目边界实现 `AuthGateway`，把登录和刷新协议映射为完整 `AuthCredentials`。只有经过
   证明的认证拒绝才映射为 `AuthSignInRejectedFailure` 或
   `AuthSessionExpiredFailure`；响应正文、账号和底层异常不得进入失败对象。
2. Gateway 使用不带 `AuthenticatedNetworkClient` 的基础 `NetworkClient`，避免登录或刷新
   自己收到 401 后递归触发刷新。模板建议让认证 gateway 与普通业务请求使用职责独立且由
   composition root 明确释放的客户端。
3. 在 production `AppStateScope` 中 override `authGatewayProvider`。保留现有
   `SecureAuthCredentialPersistence(FlutterSecureValueStore())` 和 `authLoggerProvider`；
   不要在 Feature 内创建插件实例或全局 ProviderContainer。
4. 普通受保护 API 客户端使用 `SessionCredentialProvider(authSessionController)` 注入最新
   access credential，再由 `AuthenticatedNetworkClient` 包装该基础客户端。两者必须指向
   同一个 controller，包装器拥有其基础客户端的关闭职责。
5. 所有需要认证的请求显式设置 `requiresCredential: true`。公开请求保持默认 `false`，这样
   未登录状态不会无意义读取凭据。
6. 使用项目测试替身覆盖登录拒绝、响应解析、刷新拒绝、取消、并发 401 和安全存储故障；不要
   在测试中访问真实服务、系统 Keychain/Keystore 或真实账号。

项目后端地址仍由已有环境配置提供。示例必须使用明显不可路由的占位地址；任何 API key、
长期凭据、证书或签名数据都不能通过 Dart define 注入。

## 凭据注入与 401 重放

`SessionCredentialProvider` 每次发送受保护请求时从唯一 controller 读取当前 access credential，
不缓存安全存储值。凭据在运行时已过期时，controller 会先执行或等待当前 generation 唯一的
refresh，再返回新 header；未认证或刷新失败时，基础网络层返回稳定凭据不可用错误。

受保护请求第一次收到 401 后，`AuthenticatedNetworkClient` 等待同一共享 refresh：

1. 同一 generation 的所有调用方只触发一次 gateway refresh。
2. 某个调用方取消，只结束该调用方的等待，不取消仍服务其他请求的共享 refresh。
3. 每个受保护请求绑定开始时的非敏感 generation。请求完成、触发 refresh、重放或使会话失效
   前都会重新核对；期间发生退出、失效或新登录时，旧请求的成功、失败和 401 均按
   `NetworkCancelledError` 处理，不能把旧账号请求重放到新会话，也不能用迟到 401 失效新会话。
4. refresh 失败会使会话失效并尽力删除 envelope；调用方继续收到首次稳定 401，refresh 的
   服务端详情不会穿过网络契约。
5. refresh 成功后，每个原请求最多重放一次。默认只重放无 body GET；POST、PUT、PATCH 和
   DELETE 必须在服务端已提供幂等键或等价保证后，显式选择
   `NetworkRequestReplayPolicy.explicitlyIdempotent`。
6. 重放仍返回 401 时立即使会话失效并返回第二次 401，不递归刷新。

基础 `DioNetworkClient` 仍然不会因超时、连接失败或普通服务端错误自动重试。认证装饰器只扩展
上述凭据刷新路径；显式幂等不代表取消能够回滚服务端已经执行的副作用。

## 路由与界面

当前纯 Dart 契约注册三个位置：`/sign-in`、`/session-loading` 和受保护示例 `/account`。
认证策略同步读取已经发布的会话快照，不在 redirect 中启动 I/O。`TemplateApp` 的私有
`Listenable` 只通知 go_router 重新求值，不保存第二份认证状态。

`returnTo` 只接受 `AuthRouteContract` 明确白名单中的规范站内路径。scheme、authority、
userinfo、query、fragment、未知深链和外站地址一律丢弃；当前唯一允许值是 `/account`。
增加受保护页面时必须同时扩展保护判断、returnTo 白名单和正常/非法/循环重定向测试，不能直接
信任外部 URI。

登录页和受保护示例页通过应用层文案模型接收 `en/zh` 文案，不反向依赖
`app/localization`。密码在提交结束和 Widget 销毁时清空；失败界面只显示稳定本地化分类。默认
gateway 无真实服务，因此用户可以查看登录表单和安全失败状态，但模板不会接受任何本地账号。

## 安全检查清单

1. `AuthCredentials`、`AuthSignInRequest`、`NetworkCredential` 和会话状态的 `toString()` 必须
   保持脱敏；禁止把敏感模型加入 logger context、Provider observer 或测试快照。
2. 会话 controller 日志只能使用固定事件名和固定消息，不传账号、密码、凭据、URI、响应正文、
   原始异常或堆栈。启动 adapter 构造异常仍经过第一阶段统一脱敏 logger，但该路径不能接收
   envelope 或登录输入。
3. 普通偏好、Dart define、源码、配置样例和 bundled 数据中不得出现认证凭据。
4. 登录/刷新请求必须使用 HTTPS；第一阶段网络 adapter 已禁止向 HTTP 注入凭据。
5. 退出先使内存会话失效，再删除安全 envelope。删除失败也不得恢复内存会话或伪装成功。
6. 测试只使用明显虚构、不可用于任何服务的短暂值，并验证诊断字符串和日志不包含这些值；不
   保存截图、Golden 或快照形式的登录输入。

## 测试与验证

认证变更至少运行：

```bash
flutter test test/features/auth
flutter test test/app/router/auth_app_route_redirect_policy_test.dart
flutter test test/app/router/app_router_test.dart test/app/template_app_test.dart
flutter test test/core/network/network_contract_test.dart
flutter test test/app/mobile_ui_layout_matrix_test.dart
```

专项测试覆盖 envelope 严格 schema、默认失败边界、登录/退出、恢复、过期刷新、存储和网络
失败、重复提交、并发单飞、调用方取消、跨 generation 迟到响应/401、非幂等请求不重放、第二次
401、持久化顺序、Provider 销毁、路由 returnTo 和窄屏 200% 文字。交付前还必须执行完整生成
检查、格式、严格分析、全量测试和 Android 实际构建；iOS Keychain 与构建只能在 macOS/Xcode
补证。

## 删除与回滚

认证属于可裁剪增强能力。已经向真实用户写入过 envelope 的项目，先发布一个仍包含认证模块的
迁移版本：使会话失效并精确删除 `auth.session`，确认不会影响同一安全存储中的其他值；下一版
再删除代码。不得使用全量 secure storage clear，也不得先删除清理能力而永久遗留 refresh
credential。

完整删除时成组处理：

1. 从 Router 移除登录、loading、受保护示例、首页入口、认证重定向策略和状态刷新桥接，恢复
   项目确认的公开路由策略。
2. 从 bootstrap/ProviderScope 移除 gateway、认证持久化和 logger override；删除
   `lib/features/auth/`、应用认证策略、本地化文案与对应测试。
3. 若没有其他消费者，再移除 `NetworkRequestReplayPolicy` 增量；不要改变基础
   `NetworkClient` 的默认不重试语义。
4. 删除本文档和测试说明中的认证入口，运行格式、分析、全量测试、架构/平台门禁与 Android/iOS
   构建，确认公开首页、示例 Feature、普通/安全存储和网络底座仍可独立工作。

只回滚项目 gateway 时保留默认 `UnconfiguredAuthGateway`，公开应用仍可运行且登录失败关闭。
安全存储 schema 或路由 URI 已经发布后，回滚必须保留兼容读取/清理和旧链接终止路径，不能只
恢复 Dart 源码版本。
