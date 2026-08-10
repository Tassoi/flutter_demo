# core

`core/` 保存网络、存储、错误和日志等稳定基础设施。它不得导入 `features/` 或包含具体业务规则。

插件适配器可以在此目录内部使用第三方类型，但对外接口必须使用项目自有类型，以便测试替换和依赖升级。

- `error/` 只暴露不携带底层 cause、堆栈或插件对象的稳定 `AppError`。基础设施必须在自己的边界完成精确映射；网络错误只额外保留安全 HTTP 状态码。
- `logging/` 提供唯一的 `AppLogger` 门面、结构化记录、环境级别、统一脱敏和 sink。任何数据必须先脱敏再进入 `package:logging` 或控制台。
- `network/` 对 Feature 暴露项目自有请求、响应、取消、凭据与超时契约；Dio 类型只存在于唯一 adapter 及其测试。网络日志禁止读取 URL、header、body、响应 data 或凭据。
- `storage/` 分离可恢复的普通偏好与敏感字符串。Feature 只依赖 `PreferenceStore` 或 `SecureValueStore`；shared_preferences 与 flutter_secure_storage 类型只存在于各自 adapter 和 adapter 测试。
- Feature 不得直接导入 `package:logging`，也不得直接调用 sink 绕过阈值和脱敏。
- Feature 不得导入 `package:dio` 或 `dio_network_client.dart`；网络 Repository 只依赖 `NetworkClient`，由 `app/` 在启用真实网络数据源时创建、注入并释放具体实现。
- Feature 不得导入 `package:shared_preferences`、`package:flutter_secure_storage` 或两个具体存储 adapter。Token、密码、Cookie、私钥和认证会话只能进入 `SecureValueStore`，不得以模糊键名写入普通偏好。
- 日志 message 与 event 必须稳定，动态值放入命名准确的 context；即使有脱敏器，也不得主动记录凭据、响应体或不必要的个人数据。

错误映射、环境策略、脱敏边界、启动接入和回滚方式见 `docs/architecture/0004-application-errors-and-structured-logging.md`；网络契约、取消、凭据和错误矩阵见 `docs/architecture/0005-network-infrastructure.md`；普通/安全存储契约、平台配置、清理与迁移边界见 `docs/architecture/0006-local-storage.md`。
