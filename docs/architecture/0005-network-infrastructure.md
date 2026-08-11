# ADR 0005：项目自有网络契约与 Dio 适配器

- 状态：Accepted
- 决策日期：2026-08-09
- 适用范围：第一阶段 Base URL、公共 header、超时、JSON 请求/响应、取消、错误映射、安全日志与凭据注入边界

## 背景与范围

Feature 需要发起 HTTP 请求，但不能直接依赖 Dio 的 `Response`、`Options`、`CancelToken` 或 `DioException`。否则插件升级会穿透 Repository 和状态层，底层异常、完整 URL、响应 header 或正文也容易进入 UI 与日志。

本决策使用 Task 1 已选定的 Dio 5.11.0 作为唯一传输实现，同时建立项目自有契约。它只服务 JSON API，不实现登录、Token 刷新、Cookie 会话、自动重试、缓存、离线同步、上传下载、流式响应或通用 Mock 服务。完整认证仍属于第二阶段。

## 公开契约与依赖边界

Repository 只使用以下项目类型：

| 类型 | 职责 | 明确不包含 |
| --- | --- | --- |
| `NetworkClient` | 发送请求、调用 decoder、关闭资源 | Dio 参数、全局 service locator |
| `NetworkRequest` | 描述稳定 operation、方法、相对 path、query、header、JSON body 与凭据需求 | 绝对 URL、原始凭据、插件对象 |
| `NetworkResponse<T>` | 返回状态码和已解析数据 | 响应 header、Cookie、原始正文、Dio Response |
| `NetworkCancellationToken` | 在状态生命周期与传输取消之间建立项目边界 | Dio CancelToken、任意取消 reason |
| `NetworkCredentialProvider` | 为明确受保护的请求按次读取凭据 | 登录、刷新、失效、退出状态机 |
| `NetworkTimeouts` | 提供四个有界超时 | 自动重试、业务 deadline |

`DioNetworkClient` 是唯一生产 adapter。`package:dio` 只允许出现在 `lib/core/network/dio_network_client.dart` 和它的基础设施测试中。`withHttpClientAdapter` 构造函数仅用于注入内存 fake transport；应用组装与 Feature 不得使用这个测试入口。

Task 12 的 `NetworkExampleRepository` 已证明 Feature 可以只依赖本节项目契约完成请求和解析，但它不是默认数据源。production assembler 注入无 I/O 的 `BundledExampleRepository`，因此 `.invalid` 示例地址不会被访问，也不会创建无人持有的 Dio 客户端。真实项目启用网络实现时，必须由 `app/` 使用已验证的 `AppConfig.apiBaseUri`、进程 logger 和明确凭据提供者构造客户端，通过 `ExampleRepository` override 注入，并由同一组装边界负责 `close()`。这不是新增 DI 容器，也不改变本 ADR 的公开契约。

## 请求约束

`NetworkRequest` 在接触 Dio 前执行以下验证并深冻结集合：

1. `operation` 必须是稳定小写点分名称，例如 `catalog.load_items`；不得包含用户 ID、搜索词或 URL。
2. path 只能是相对 endpoint。绝对 URL、前导 `/`、query、fragment、反斜杠、`.`/`..` 路径段及编码/双重编码的分隔符会被拒绝。
3. query 只接受 `null`、字符串、布尔、有限数字或这些标量的单层列表。已知 Authorization、Token、密码、API key、secret、credential 与 session 参数名被拒绝。
4. 普通和公共 header 必须是有效 HTTP token，值不能包含控制字符。Authorization、Cookie、API key、Host、Content-Length、Transfer-Encoding、Connection 与 Content-Type 等凭据或传输控制 header 不允许由请求直接设置。
5. body 只能是无循环、最大嵌套 64 层、可 JSON 编码的 object 或 array。GET 不允许 body；其他方法有 body 时统一使用 `application/json`。
6. 所有校验异常只返回固定 `ArgumentError`，不回显被拒 path、header、query、body 或凭据。

这些规则不能识别任意自定义字段中的 secret。调用方仍必须遵守“URL 与普通 header 不承载凭据”的契约；网络日志从类型边界上完全不读取这些字段。

## Base URL、公共 header 与重定向

客户端只接受绝对 HTTP(S) Base URI，要求 host 非空，禁止 user info、query、fragment 和路径穿越，并统一补齐末尾 `/`。这与 `AppConfig.apiBaseUri` 的环境校验形成双重边界：配置负责生产环境必须 HTTPS，网络 adapter 负责任何构造来源都不能绕过固定 host 与相对 path。

默认公共 header 为 `Accept: application/json`，应用可以注入非敏感版本号等公共 header。请求级同名 header 覆盖公共值。Dio 自动重定向被关闭，3xx 按非成功响应处理，避免凭据被转发到未验证 host 或降级连接。

## 超时与重试

模板默认值为：

| 阶段 | 默认值 | Dio 语义 |
| --- | --- | --- |
| connect | 10 秒 | 建立连接上限 |
| send | 15 秒 | 发送请求数据上限 |
| receive | 20 秒 | 相邻响应数据事件等待上限，不是总时长 |
| transform | 5 秒 | 大响应在后台 isolate 转换时的上限 |

所有值必须大于零，不能用 `null` 或零静默关闭。四种 Dio timeout 都转换为同一个 `NetworkTimeoutError`。客户端没有隐式重试，因为 timeout 或取消发生时服务端可能已经执行写操作；重试必须由知道 endpoint 幂等语义的上层显式决定。

## 响应解析与错误矩阵

Dio 先根据 JSON Content-Type 完成基础转换，再由每次请求必填的 `NetworkResponseDecoder<T>` 做数据形状校验和 DTO 构造。decoder 可以同步或异步；它不应包含业务规则。非 2xx 响应关闭并丢弃正文，不尝试解析服务端错误 payload。

| Dio/decoder 结果 | 项目错误 | 稳定 code | 保留数据 |
| --- | --- | --- | --- |
| DNS、Socket、TLS 证书或连接失败 | `NetworkConnectionError` | `network.connection` | 无 |
| connect/send/receive/transform timeout | `NetworkTimeoutError` | `network.timeout` | 无 |
| 主动取消或关闭客户端 | `NetworkCancelledError` | `network.cancelled` | 无取消 reason |
| 非 2xx HTTP | `NetworkResponseError` | `network.response` | 仅 100-599 状态码 |
| JSON 或请求 decoder 失败 | `NetworkResponseParseError` | `network.parse` | 无正文或解析异常 |
| 凭据缺失、provider 失败或非 HTTPS | `NetworkCredentialsUnavailableError` | `network.credentials_unavailable` | 无凭据原因 |
| 无法证明语义的未知失败 | `UnexpectedAppError` | `unexpected` | 无底层异常 |

上层收到的错误不保存 Dio 对象、响应 header、正文、cause 或 stack。原始传输与 decoder 异常也不会作为日志 error 参数传递；日志只接收已经稳定化的 `AppError`。

## 凭据安全边界

公开请求不会调用凭据提供者。受保护请求每次重新调用 `loadCredential()`，使轮换后的值立即生效，网络层不缓存凭据。provider 返回 `null` 或抛错都会在进入 transport 前稳定失败；原始异常会被丢弃，因为安全存储错误文本也可能含敏感详情。

`NetworkCredential` 只保存一个经过验证的 header 名称和值，`toString()` 永远显示 `[REDACTED]`。日志拦截器先于凭据拦截器运行且只读取稳定 extra，随后才注入 headerValue，因此日志代码从执行顺序上也接触不到凭据。受保护请求必须使用 HTTPS；开发环境也没有 insecure override。

Dio 无法强制取消 provider 自身已经开始的任意异步 I/O。项目取消仍会立即结束请求 Future；provider 之后完成时 adapter 会再次检查 Dio CancelToken，不再注入凭据或访问 transport。provider 实现仍应保证读取有界且并发安全。

## 取消与生命周期

项目令牌可以同时取消多个请求。每次 `send` 创建独立 Dio CancelToken，并注册一个同步监听；令牌已取消时会立即转发。异步 decoder 与同一 Dio 取消信号竞速，因此页面销毁或 `close()` 不必等待 decoder Future 才能收到 `network.cancelled`。监听在整个 `send` 生命周期结束后于 `finally` 注销，避免长期持有 RequestOptions、header 或 body。

Dart 不能强制终止已经开始的同步计算或任意 Future。取消胜出后，decoder 可能在后台继续到自身完成，但其迟到值/错误会被已安装处理器接收并丢弃，不会改变请求结果或形成未捕获异常；decoder 仍应保持有界且不执行业务副作用。

取消只终止客户端等待，不能撤销服务端已经执行的操作。`close()` 幂等：先取消所有活跃 Dio token，再以 `force: true` 关闭 adapter。关闭后 `send` 抛固定 `StateError`，因为这是依赖所有者的生命周期错误，不是可重试网络状态。

## 日志与隐私

网络层复用唯一 `AppLogger`，固定事件为：

| 事件 | 级别 | context |
| --- | --- | --- |
| `network.request_started` | debug | operation、method |
| `network.request_succeeded` | info | operation、method、statusCode |
| `network.request_failed` | cancel 为 info、未知为 error、其他为 warning | operation、method、errorCode；非成功响应再加 statusCode |

日志不读取 Base URL、path、query、request/response header、body、响应 data 或 credential。即使 logger 实现关闭或抛错，网络真实结果也不受影响。生产环境仍由 ADR 0004 的阈值与详情策略决定最终输出。

## 测试与验证边界

adapter 测试全部注入自定义 `HttpClientAdapter`，只返回内存 `ResponseBody` 或人工 `DioException`，不会打开 Socket。直接覆盖正常 JSON、Base URL、公共 header、四类超时、连接失败、非成功状态、取消、关闭、JSON/decoder 失败、凭据注入/缺失/provider 失败、provider 保持挂起时取消仍立即完成、迟到凭据不触达 transport、HTTP 凭据拒绝、日志故障和端到端敏感数据不出现在结构化记录。

示例网络 Repository 的测试只注入 `NetworkClient` 替身，验证 operation、相对 path、取消令牌、无凭据请求、成功/空响应、数据形状校验和稳定错误透传。它不会导入 Dio 或重复 adapter 测试，也不会访问真实服务。

常规验证命令为：

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build apk --debug --flavor dev \
  --dart-define-from-file=config/dev.example.json
```

Android 主 Manifest 声明 `INTERNET`，使该网络能力在 release 变体中同样可用；平台门禁会阻止
权限被 Flutter 平台文件更新静默移除。该权限不放宽 HTTP 明文传输、TLS 或系统网络安全策略。
Android 实际构建验证 Dio adapter 可随应用编译；iOS 在当前非 macOS 主机仍只能由后续 macOS CI
或开发机验证。

## 限制与回滚

1. 当前只有 JSON object/array 请求与内存响应，不支持 multipart、文件、进度、stream 或 response header 消费；出现真实用例后应新增窄接口，而不是暴露 Dio。
2. 非 2xx 正文被丢弃，因此尚不能解析项目特定服务端业务错误码。应由具有明确协议和测试的 Repository adapter 扩展，不能把任意 payload 放进通用错误。
3. receive timeout 不是端到端 deadline；本阶段不增加另一套计时器。
4. 自动重定向和自动重试均关闭，这是凭据安全和副作用一致性的保守默认值。

回滚本决策时，应精确移除 `lib/core/network/`、本 ADR、对应测试以及 `AppError` 中六个网络子类型，并恢复 ADR 0004/core README 对网络任务的旧说明。不得回退配置、启动、通用错误/日志、依赖锁定、平台骨架或用户文件；Dio 依赖是否移除应结合 Task 1 的完整依赖基线单独决定。
