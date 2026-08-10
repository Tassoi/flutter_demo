# 测试基础设施

本目录验证脚手架第一阶段的稳定工程边界。测试必须通过项目接口替换网络、存储和状态依赖，
不得访问真实服务、真实密钥、文件系统、系统时钟或不稳定的平台状态。

## 目录与职责

测试文件使用 `*_test.dart` 命名，并尽量镜像 `lib/` 的边界：

```text
test/
├── app/                         # 配置、启动、路由、状态和主题
├── core/                        # 错误、日志、网络和存储
├── features/                    # Feature 的领域、数据、状态、页面与路由契约
├── shared/                      # 类型安全资源和无业务组件
├── tool/                        # 架构与生成产物质量门禁
└── support/                     # 被多个测试文件复用的测试专用能力
```

`test/support/` 只接收已经出现多个使用方的测试代码：

1. `features/example/controlled_example_repository.dart` 使用 `Completer` 显式结算请求，
   用于验证加载、取消、竞态和迟到结果，不使用延时等待。
2. `features/example/example_item_fixture.dart` 提供通过领域校验的默认对象。领域模型自身的
   无效输入测试仍直接调用构造函数，不能让 Fixture 隐藏边界。
3. `state/create_test_provider_container.dart` 为每个测试创建并自动释放 Riverpod 容器。
4. `storage/` 下的内存实现只替换项目存储接口，不提供真实加密，也不得进入生产组装。
5. `widgets/test_widget_environment.dart` 统一窄屏尺寸、放大文字和首帧挂载行为，并在测试
   结束时恢复表面尺寸。

只被一个 adapter 测试使用的第三方插件 Fake 保留在对应测试文件内。不要为了目录整齐把
Dio、SharedPreferences 或 FlutterSecureStorage 类型扩散到通用测试支持层。

## 覆盖矩阵

下表中的每一项都具有直接、可独立运行的正常、边界和失败证据。文件名是该能力的主要
证据入口，不表示其他测试不能提供跨层验证。

| 能力 | 正常路径 | 关键边界 | 主要失败路径 |
| --- | --- | --- | --- |
| 环境与配置 | `app/config/app_environment_test.dart` 验证全部环境；`app_config_test.dart` 验证三套配置 | 缺失和未知环境、Base URI 规范化、只使用不可路由默认地址 | 拒绝生产 HTTP、user info、query、fragment 与不安全地址，异常不回显原值 |
| 应用启动 | `app/bootstrap/app_bootstrap_test.dart` 验证初始化顺序和应用装配；`app_bootstrap_runtime_test.dart` 验证运行时桥接 | 同步与异步失败、Reporter 切换、重复错误处理 | 配置或装配失败进入安全回退；Reporter 自身失败被隔离；失败页不泄漏底层异常 |
| 统一错误 | `core/error/app_error_test.dart` 验证稳定代码、文案和既有错误透传 | HTTP 状态码上下界与配置错误分类边界 | 未知异常折叠为稳定错误，原始配置、传输、键和值不进入结果 |
| 日志 | `core/logging/package_logging_app_logger_test.dart` 验证级别、结构化记录和 JSON Sink；`log_redactor_test.dart` 验证脱敏 | 深度、集合、文本长度、循环引用、动态事件名和关闭生命周期 | Sink、fallback writer、脱敏器及恶意集合失败均被隔离；生产策略不输出原始错误和堆栈 |
| 网络 | `core/network/network_contract_test.dart` 验证请求、凭据、取消和超时契约；`dio_network_client_test.dart` 验证完整 adapter pipeline | 路径、header、query、body、Base URI、重复取消、并发请求和异步 decoder | HTTP、连接、全部超时、解析、凭据和取消失败映射稳定；正文、凭据与日志均不泄漏 |
| 存储 | `core/storage/storage_contract_test.dart` 验证普通与安全存储接口；两个插件 adapter 测试验证平台选项和命名空间 | 缺失值、列表防御复制、类型、有限 double、单键删除与 scoped clear | 初始化和读写删清失败稳定映射；凭据类名称不能进入普通存储 |
| 路由 | `app/router/app_router_test.dart` 验证 Shell 内首页、详情和返回；`features/example/routing/example_route_contract_test.dart` 验证 URI 契约 | 正整数参数、规范 URI、重复返回、窄屏与放大文字 | 未知页、非法参数、不安全重定向和策略异常都显示安全状态且不回显 URI |
| 状态 | `app/state/app_state_scope_test.dart` 与两个异步生命周期测试验证 override、加载、数据和主题状态 | 成功空值、非正 family 参数、重复重试、auto-dispose、依赖重建和迟到完成 | Repository、重试与缺少组装失败均映射为稳定错误；取消后旧结果不能复活状态 |
| 组件与页面 | `shared/widgets/`、`shared/assets/app_assets_test.dart` 和 `features/example/presentation/example_detail_page_test.dart` 验证展示与交互 | 窄屏、放大文字、滚动、语义、触控尺寸、空状态和可选动作 | 错误文案脱敏；无效参数提前拒绝；重复弹窗动作与过期消息不会产生二次副作用 |
| 工程门禁 | `tool/ci/check_architecture_test.dart` 验证允许的分层与 adapter；`check_generated_files_test.dart` 验证锁文件和项目创建/迁移 metadata；`check_platform_environments_test.dart` 验证三环境对齐 | export、跨 Feature、编码路径、相对导入、旧创建 SDK、缺失元数据、无效 JSON、缺少 scheme、环境值漂移和 configuration 专属 Pods include | 反向依赖、adapter 越界、锁文件漂移、metadata 结构/平台/保护项漂移、主 Manifest 缺少 release 联网权限或禁用备份策略、Keychain entitlement 漂移、通用 Android APK/AAB、晚于 flavor 依赖触发的保护、iOS fallback、错误 Pods include 和 release debug 签名均返回稳定规则编号 |

## Widget 帧与布局

`pumpTestWidget` 只挂载 Widget 并推进首帧。调用方必须根据行为显式选择后续的 `pump` 或
`pumpAndSettle`，不能在通用辅助方法中隐藏动画和异步状态时序。需要小屏验证时传入
`narrowPhoneSurfaceSize`；需要无障碍文字验证时通过 `createTestMediaQueryBuilder` 使用
`largeTestTextScaler`。

持续进度动画不应使用无上限的 `pumpAndSettle`。状态测试优先用 `Completer`、项目取消令牌
和 Riverpod 的 `container.pump()` 推进明确事件，不使用无依据的 `Future.delayed`。

## 独立性与确定性

1. 每个测试负责创建并释放自己的 Router、ProviderContainer、客户端和语义句柄。
2. 测试替身不得持有跨测试静态可变状态，也不得依赖测试文件或用例的执行顺序。
3. 网络 adapter 通过注入 transport 验证，不打开 Socket；存储 adapter 通过注入插件接口
   验证，不访问设备数据。
4. 修复缺陷时先增加能复现该行为的最小测试，再修复实现；至少保留正常、关键边界和主要
   失败路径中与缺陷有关的证据。
5. 随机顺序失败时必须记录 seed，修复共享状态或资源释放问题，不能固定顺序掩盖问题。

常用验证命令：

```bash
# 单文件独立验证
flutter test test/core/network/network_contract_test.dart

# 工程门禁的正常、边界和失败测试
flutter test test/tool/ci

# 使用固定 seed 的可复现随机顺序
flutter test --test-randomize-ordering-seed=20260809

# 生成本地覆盖率诊断，产物位于已忽略的 coverage/
flutter test --coverage
```

覆盖率用于发现未执行分支，不设置脱离风险的百分比目标。`bootstrapApplication` 的编译期
环境读取和全局 `runApp`、默认 `debugPrint` writer、真实插件通道属于生产装配或平台边界：
其可替换契约由单元测试覆盖，默认集成由实际平台构建与后续设备验证覆盖。不得仅为提高行
覆盖率，把私有装配函数、平台对象或第三方类型暴露为公开 API。
