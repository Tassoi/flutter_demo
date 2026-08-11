# ADR 0006：普通偏好与安全存储边界

- 状态：Accepted
- 决策日期：2026-08-09
- 适用范围：第一阶段普通键值偏好、安全字符串存储、插件隔离与平台安全配置

## 背景与范围

应用需要保存主题、开关等可恢复偏好，也需要为后续受保护网络请求提供安全保存运行时凭据的能力。把两类数据放进同一个通用 Map 或直接向 Feature 暴露插件，会让敏感值误入未加密偏好、让插件异常泄漏到 UI，并使测试依赖 MethodChannel。

本决策提供两个窄契约：`PreferenceStore` 只保存非敏感、可恢复的简单值，`SecureValueStore` 只保存敏感字符串。它不实现数据库、对象查询、缓存、认证状态机、登录、Token 刷新或跨设备同步；安全存储只是第二阶段认证模块未来可以依赖的基础设施。

## 项目契约

### 普通偏好

`PreferenceStore` 支持与 shared_preferences 稳定对应的五种类型：

| 类型 | 缺失行为 | 写入约束 |
| --- | --- | --- |
| `bool` | 返回调用方显式默认值 | 无隐式字符串转换 |
| `int` | 返回调用方显式默认值 | 保持整数语义 |
| `double` | 返回调用方显式默认值；平台遗留非有限值按 `storage.read` 失败 | 默认值与写入值都必须有限 |
| `String` | 返回调用方显式默认值 | 不承担敏感值加密 |
| `List<String>` | 返回默认列表的不可修改副本 | 输入、存储结果和输出均防御性复制 |

缺失与失败必须区分：缺失返回默认值，平台失败或历史值类型不匹配抛 `storage.read`。写入 Future 只说明插件平台调用完成，不把普通偏好提升为关键业务数据或事务存储。

`PreferenceKey` 只接受最长 120 字符的小写点分稳定名称。键不得包含用户 ID、邮箱或其他动态值；明显描述 Token、密码、Cookie、API key、secret、bearer、JWT、私钥和会话的名称会在接触插件前被拒绝。该校验不是任意秘密识别器，调用方仍有责任不把敏感或不可恢复数据写入普通偏好。

### 安全值

`SecureValueStore` 只提供 `read`、`write`、`delete` 和 `clear`。缺失键返回 `null`，解密或平台失败抛 `storage.read`，不会把错误伪装成退出登录。`SecureStorageKey` 采用同样的稳定格式但允许描述凭据用途，其 `toString()` 始终隐藏名称。

接口不提供 `readAll`、查询或任意对象序列化，减少敏感值批量进入内存的路径。写入失败时调用方不得退回 `PreferenceStore`；认证恢复策略必须由未来明确的认证模块处理。

## 唯一插件实现

### SharedPreferencesAsync

`SharedPreferencesPreferenceStore` 是唯一普通存储 adapter，只在该文件和对应 adapter 测试中导入 shared_preferences。选择 `SharedPreferencesAsync` 而不是 legacy/cache API，避免多 isolate、多个 Flutter engine 或原生写入导致进程缓存陈旧。

所有逻辑键都映射到固定 `app.preferences.` 前缀。`clear()` 先读取平台键快照，只筛选该前缀，再将非空集合作为插件 allow-list；它永远不会调用无范围清理，避免删除原生代码和其他插件的数据。快照与删除不是跨进程事务，多个 adapter 实例或原生写入可能并发变化；调用方必须等待同一业务流程中的冲突操作，不能把 `clear()` 当成数据库事务。

### flutter_secure_storage

`FlutterSecureValueStore` 是唯一安全存储 adapter，只在该文件和 adapter 测试中导入 flutter_secure_storage。持久化身份固定为：

| 平台/层级 | 固定值与策略 |
| --- | --- |
| 逻辑键前缀 | `app.secure.` |
| Android namespace | `app_secure_storage`，隔离密文、配置标记和 Keystore alias |
| Android 加密 | 显式固定 RSA-OAEP 包装 + AES-GCM 数据加密，不要求生物识别 |
| Android 故障 | `resetOnError: false`，避免插件在解密错误时静默清空 |
| Android 迁移 | 算法迁移开启，`migrateWithBackup: true` 提供加密备份恢复 |
| Apple service | `app.secure_storage` |
| iOS accessibility | `unlocked_this_device`，仅设备解锁时可用且不迁移到新设备 |
| iCloud Keychain | `synchronizable: false` |

Android 系统备份无法同时恢复设备 Keystore 私钥，恢复密文可能产生无法解包错误。因此模板在主 Manifest 设置 `android:allowBackup="false"`。项目若未来确实需要普通数据备份，必须改用明确的 data-extraction/backup 规则排除安全存储文件，并在真实备份恢复流程中验证，不能只删除该属性。

iOS 按插件要求提供 `Runner/Runner.entitlements`，声明空 `keychain-access-groups`；Debug xcconfig 直接引用它，Profile 与 Release 通过 Release xcconfig 引用同一文件。未来配置 App Group 时必须使用实际受控 group、同步签名能力并在 macOS/Xcode 验证，不能写入占位生产标识。

项目平台门禁把主 Manifest 的备份策略和 entitlement 文件本身都作为必需输入；升级 Flutter、
存储插件或原生工程时，静默移除或放宽任一边界都会让 CI 失败。具体项目有意改变持久化身份时，
必须同步更新迁移方案、正反测试和实际平台恢复证据，不能只放宽检查字符串。

## 初始化、错误与生命周期

两个 adapter 的工厂会把同步插件构造失败映射为 `storage.initialization`。所有读、写、删除和清理操作分别映射为 `storage.read`、`storage.write`、`storage.delete`、`storage.clear`，稳定对象不保存插件异常、平台路径、键或值。测试注入参数以 `@visibleForTesting` 标记，Feature 不得借此取得插件实例。

插件不需要显式 `close()`，adapter 不持有 listener、缓存或长连接。当前没有 Repository/Feature 消费者，因此 production assembler 不创建存储实例；首次实际组装必须发生在 Flutter Binding、异常处理和配置校验完成后，并通过 `PreferenceStore`/`SecureValueStore` 注入真实消费者。这样初始化失败才有明确启动边界，也不会创建无人持有的服务。

测试使用 `InMemoryPreferenceStore` 与 `InMemorySecureValueStore`，不访问 MethodChannel、磁盘或真实密钥。内存安全存储没有加密保证，只能位于测试代码，禁止进入 production assembler。

## 验证与已知限制

直接测试覆盖：键格式与敏感普通键拒绝、五种普通类型、显式默认值、写入及平台遗留非有限浮点、列表复制、类型不匹配、单键删除、命名空间清理、空 namespace 不触发全量清理、安全值缺失/写入/删除/清空，以及初始化、读、写、删除、清理的稳定错误转换。

常规验证命令：

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build apk --debug --flavor dev \
  --dart-define-from-file=config/dev.example.json
```

当前主机没有 Android 设备或模拟器，因此不能验证真实 Keystore 的写后重启、备份恢复和清理；Android 编译只能证明插件与配置可打包。当前主机不是 macOS，无法执行签名、Keychain 读写或 iOS 构建；entitlement 与 Xcode 配置只能静态核对，真实行为必须由后续 macOS CI/开发机验证。

shared_preferences 不保证关键写入永久落盘，安全存储也不提供跨多个键的事务。若未来改变普通前缀、Android namespace、Apple service、加密算法或 Keychain accessibility，旧值可能不可见或无法解密；必须先提供版本化迁移、失败恢复和回滚测试，不能原地替换常量。

## 回滚

回滚本决策时，只移除 `lib/core/storage/`、对应测试替身与测试、`AppError` 的五个存储子类型、本 ADR 和相关文档引用；同时精确移除 Android `allowBackup="false"`、iOS `Runner.entitlements` 及两个 xcconfig 的引用。不得回退网络、日志、启动、配置、平台骨架、用户的 `AGENTS.md` 或其他 Goal 任务。
