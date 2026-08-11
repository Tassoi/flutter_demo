# ADR 0004：稳定应用错误与结构化日志

- 状态：Accepted
- 决策日期：2026-08-09
- 适用范围：第一阶段通用错误边界、日志级别、结构化记录、脱敏与启动异常报告

## 背景与范围

UI、状态层和后续 Feature 需要依据稳定语义处理失败，但配置解析、Flutter runtime 和第三方插件会抛出不同类型的异常。直接把这些异常向上传递，会让插件替换变成破坏性变更，也可能把 Token、密码、个人数据或本机构建路径带入 Widget、测试快照和生产日志。

本决策建立项目自有错误模型和唯一日志门面，并把 Task 4 的启动异常接入结构化日志。Task 6 已在同一 sealed 模型中加入经过真实 adapter 规则验证的网络错误，精确映射与隐私边界见 ADR 0005；Task 7 进一步加入不保存键、值或平台异常的五类存储错误，具体契约见 ADR 0006。远程日志、崩溃上报、认证和业务错误规则仍不在本决策范围。

## 稳定错误模型

`AppError` 是状态层和 UI 可以依赖的 sealed 项目类型，只保存：

1. 稳定 `code`，供程序分支、日志关联和测试断言使用。
2. 固定且非敏感的 `displayMessage`，供尚未接入国际化的通用失败 UI 使用。

错误对象不保存原始 `cause`、stack trace、插件对象、响应体或任意 details。`toString()` 也只输出项目类型和稳定 code，因此上层即使误打印整个错误对象，也不会泄漏底层异常正文。第二阶段接入国际化时应使用 `code` 映射文案，不能把异常文本直接作为用户文案。

`AppErrorMapper` 当前只执行已经有明确证据的映射：

| 捕获边界 | 原始值 | 稳定结果 |
| --- | --- | --- |
| 配置 | 已有 `AppError` | 保持原实例 |
| 配置 | `FormatException` | `configuration.invalid` |
| 配置 | 其他异常 | `configuration.unavailable` |
| 无专用语义 | 已有 `AppError` | 保持原实例 |
| 无专用语义 | 其他异常 | `unexpected` |

网络、存储和 Feature adapter 必须在自己的基础设施边界执行精确转换；只有无法证明更具体语义时才使用 `fromUnexpected`。网络 adapter 进一步禁止把可能含 URL 或响应正文的原始异常交给 logger，只记录稳定 `AppError`；其他边界即使需要诊断原始异常，也不能让它进入返回给 UI 的错误。

存储边界只依据正在执行的操作映射，不检查可能含平台路径或密钥用途的异常文本：

| 存储阶段 | 稳定结果 |
| --- | --- |
| adapter/插件同步构造 | `storage.initialization` |
| 普通值读取、类型检查或敏感值解密 | `storage.read` |
| 普通值写入或敏感值加密 | `storage.write` |
| 删除单个键 | `storage.delete` |
| 清理 adapter 自有 namespace/service | `storage.clear` |

缺失普通偏好返回调用方显式默认值，缺失安全值返回 `null`，两者都不是错误。安全写入失败不得降级到普通偏好，存储 adapter 也不记录逻辑键、物理键或敏感值。

## 日志契约与第三方隔离

项目代码只依赖 `AppLogger`、`AppLogLevel`、`AppLogRecord` 和 `AppLogSink`。`package:logging` 的 `Logger`、`Level` 与 `LogRecord` 仅存在于 `PackageLoggingAppLogger` adapter 文件，不进入配置、Feature 或 sink 契约。

调用方必须提供稳定的小写点分 `category` 和 `event`，例如 `app` 与 `startup.unhandled_error`。动态值不得拼接进这些字段；固定事件说明写入 `message`，动态值放入结构化 `context`。非法名称会在写入前被拒绝，异常消息不会回显被拒绝的原始名称。

一条进入 sink 的 `AppLogRecord` 包含 UTC 时间、级别、category、event、已脱敏 message、已递归冻结的 context，以及按环境策略保留的 error type、异常正文和堆栈。默认 `ConsoleLogSink` 每条输出一个 JSON 对象，不接收原始异常，也不自行执行第二套脱敏。

adapter 使用 detached logger，不读取或修改 `Logger.root`。这样多个测试、多个嵌入式 engine 或未来独立工具不会共享全局 level 和 listener。项目级别映射固定为：

| 项目级别 | `package:logging` 级别 |
| --- | --- |
| `debug` | `FINE` |
| `info` | `INFO` |
| `warning` | `WARNING` |
| `error` | `SEVERE` |

低于环境阈值的事件在遍历 context、格式化异常或读取堆栈前直接丢弃，减少敏感数据暴露面和无用开销。

## 环境策略

环境策略完全来自已经验证的 `AppConfig`，不通过散落的 `kDebugMode` 改变日志行为：

| 环境 | 最低级别 | 异常正文 | 堆栈 |
| --- | --- | --- | --- |
| `dev` | `debug` | 脱敏并限制长度后保留 | 脱敏并限制长度后保留 |
| `staging` | `info` | 脱敏并限制长度后保留 | 脱敏并限制长度后保留 |
| `prod` | `warning` | 不保留 | 不保留 |

生产记录仍可以保留不含实例数据的 runtime type 和结构化稳定 error code，便于聚合类别；原始异常正文和 stack trace 不会构造进 `AppLogRecord`。启动完成的 `info` 事件在生产阈值下被过滤是预期行为。

## 统一脱敏与资源上限

所有输入必须先经过 `LogRedactor`，再进入 `package:logging` 和 sink。脱敏采用 fail-closed 规则：

1. 结构化字段名经过大小写和分隔符归一化。Authorization、Cookie、Token、API key、密码、secret、credential、session，以及常见邮箱、电话、姓名、地址、用户/设备/IP、出生日期、证件和卡号字段会整值替换。
2. message、异常和堆栈再次扫描常见 header、Bearer/Basic、标记值、带引号的赋值、Cookie、JSON 字段、邮箱和电话号码形式。
3. URI 整体移除 user info、query 和 fragment，不依赖参数是否命中正则；path 仍应由调用方保证不含个人数据。
4. 未知 context 对象不会调用其 `toString()`，只保留 runtime type。异常正文是唯一允许安全调用 `toString()` 的入口，调用失败时返回固定不可用标记。
5. Map 与 Iterable 递归检测循环引用，并限制深度和每个集合的元素数；文本在正则扫描前先应用长度上限，非有限浮点数转换为 JSON-safe 字符串。自定义集合或 stack trace 在遍历/格式化时抛错，会丢弃未完成结果并输出固定不可用标记。
6. 时钟、脱敏、第三方分发或 sink 发生任何故障时，logger 只通过固定 fallback 文案报告，不传播原始输入，也不让诊断旁路改变业务结果。logger 与启动安全 reporter 的最终 writer 再次失败都会被吞掉，避免越过或递归触发进程级异常处理器。

正则脱敏不是任意自然语言个人数据识别器。调用方仍必须使用固定 message，把动态数据放入命名准确的 context，并且不得记录响应体、完整请求头、认证凭据或不必要的个人数据。新增敏感字段时应先扩充统一 redactor 与回归测试，不能在单个 sink 中建立分叉规则。

## 启动流程接入

Flutter 全局异常处理器必须在读取配置前安装，而日志阈值和生产详情策略依赖配置。`bootstrapApplication()` 因此使用一次性 `DeferredStartupErrorReporter`：

1. 初始 reporter 为不格式化异常或堆栈、只输出捕获边界和稳定 error code 的 `SafeStartupErrorReporter`。
2. `AppConfig` 校验成功后创建环境化 `PackageLoggingAppLogger`。
3. 在初始化任何后续依赖前，把 deferred reporter 一次性绑定到 `LoggingStartupErrorReporter`。
4. 配置读取使用独立捕获来源；后续初始化、Flutter framework、platform dispatcher 与 root Zone 错误都映射为稳定 code，再由统一 logger 脱敏。只有精确的配置来源允许生成配置错误，组装阶段的 `FormatException` 仍为 `unexpected`。

代理不缓存或重放绑定前的原始异常，避免敏感对象滞留内存。日志构造或写入失败时，结构化 reporter 回到同一个安全 fallback。进程级 logger 由 reporter 持有并与进程同生命周期；测试和短生命周期工具必须调用幂等的 `close()`，取消 detached logger listener。

## 测试与验证边界

直接测试覆盖：配置与未知错误映射、不保留原始异常；结构化字段、带引号凭据、Cookie 与自由文本脱敏；URI、循环、深度、数量和长度边界；会抛异常的对象/集合/堆栈；环境阈值在求值前过滤；生产详情关闭；sink、fallback、最终 writer 和记录构造失败隔离；logger 关闭；启动 reporter 映射和一次性切换。

测试使用内存 sink、可替换时钟和人工异常，不访问真实网络、平台日志服务或真实凭据。常规检查为：

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build apk --debug --flavor dev \
  --dart-define-from-file=config/dev.example.json
```

## 取舍、限制与回滚

1. 当前 sink 只写 Flutter 控制台，不持久化、上传或缓冲日志；远程观测和崩溃上报明确不在第一阶段范围。
2. 生产关闭异常正文和堆栈会降低单条日志诊断精度，换取更小的隐私与本地路径泄漏风险；稳定事件、error code 和 type 仍支持聚合。
3. logger 不支持运行时动态改级别。环境是构建配置，进程内保持不变能让行为更容易测试和审计。
4. 网络错误和请求日志已按 ADR 0005 复用此门面与 redactor；后续扩展不得创建第二套日志、扩大记录字段或把 Dio 类型暴露给上层。

回滚本决策时，应精确移除 `lib/core/error/`、`lib/core/logging/`、对应测试和本 ADR；把 `AppLogLevel` 恢复到配置边界，并把启动流程恢复为全程使用 `SafeStartupErrorReporter`。同时移除 `LoggingStartupErrorReporter`、deferred 绑定和 production logger 组装，不得回退 Task 1-4、平台工程、配置校验或用户文件。
