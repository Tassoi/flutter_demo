# ADR 0002：项目边界与 Dart 环境配置

- 状态：Accepted
- 决策日期：2026-08-09
- 适用范围：第一阶段目录结构与 Dart 配置

## 背景

脚手架需要在业务代码出现前固定目录职责，并提供 `dev`、`staging`、`prod` 三套可测试配置。环境选择必须显式，默认地址不得连接真实服务，配置错误必须在网络和存储初始化前暴露。

本决策定义 Dart 配置模型。集中启动流程由 `ADR 0003` 接入，Android flavor、iOS scheme、跨平台一致性门禁和平台构建路径现由 `ADR 0013` 实施；两份决策共同组成环境契约。

## 目录与依赖方向

```text
lib/
├── main.dart
├── app/       # composition root、配置、启动、路由、主题
├── core/      # 网络、存储、错误、日志等无业务基础设施
├── features/  # 按业务能力纵向组织的模块
└── shared/    # 已确认跨 Feature 复用的无业务代码
```

依赖规则如下：

1. `app/` 可以组装 `core/`、`features/` 和 `shared/`。
2. `features/` 可以依赖 `core/`、`shared/` 的公开接口，但不得导入其他 Feature 的内部实现。
3. `core/` 不得依赖 `features/`，也不得包含具体业务规则。
4. `shared/` 不得依赖具体 Feature；没有至少两个真实消费者的代码不提前放入此目录。
5. 第三方插件类型只允许出现在 `app/` 的组装边界或 `core/`/`shared/` 的适配实现内，不进入 Feature domain 契约。

各目录保留局部 `README.md`，因此即使尚无实现文件，边界也能进入版本控制并靠近调用者。`tool/ci/check_architecture.dart` 现在按实际 `import`/`export` 规则检查反向依赖、跨 Feature 访问、最小入口和第三方适配器位置；规则、局限和本地命令见 ADR 0012。

## 环境配置契约

| 环境 | APP_ENV | 安全默认 API | 最低日志级别 | 应用名称 | 包名后缀 |
| --- | --- | --- | --- | --- | --- |
| 开发 | `dev` | `https://api.dev.example.invalid/` | debug | Flutter Template Dev | `.dev` |
| 预发布 | `staging` | `https://api.staging.example.invalid/` | info | Flutter Template Staging | `.staging` |
| 生产 | `prod` | `https://api.example.invalid/` | warning | Flutter Template | 空 |

`APP_ENV` 没有默认值。缺失、未知值、大小写错误或前后空格都会抛出 `FormatException`，因为静默修正可能让 Dart 后端配置与原生 flavor 不一致。启动层会在依赖组装前捕获该异常，通过启动报告边界记录事件，并展示不接收异常对象的安全失败界面；稳定应用错误类型留给独立错误模型任务。

`API_BASE_URL` 为空时使用表中的 `.invalid` 地址。覆盖值必须满足：

1. 是具有非空 host 的绝对 HTTP(S) URI。
2. 不含 user info、query 或 fragment，避免凭据泄漏和端点拼接歧义。
3. 生产环境必须使用 HTTPS；开发和预发布的 Dart 模型允许描述 HTTP URI，但模板不会全局关闭
   Android Network Security 或 iOS App Transport Security。移动端默认仍使用 HTTPS；具体项目
   若需要明文调试，只能为明确开发环境和目标主机增加最小平台例外及测试。
4. 配置模型统一补齐 path 末尾 `/`，确保相对端点不会替换 base path 的最后一段。

应用名称和包名后缀是 Dart 与原生配置之间的契约。Android/iOS 已使用同一表生成各自的 build variant；启动时还会在 Flutter CLI 提供 flavor 时检查它与 `APP_ENV` 精确一致。环境不会根据 `kDebugMode` 隐式切换。

## 可提交配置与敏感信息

`config/*.example.json` 只包含环境名和 `.invalid` 地址，可以提交。`config/*.json` 默认被忽略，再通过否定规则只放行示例文件，降低误提交本机地址的风险。

Dart define 会进入编译产物，因此即使本地 JSON 被忽略，也不得放入 API key、Token、密码、证书、私钥、签名数据或长期凭据。真实凭据必须由后端短期签发并进入后续安全存储边界；构建签名由平台安全机制或 CI secret 管理，不进入 Dart 配置模型。

## 使用方式

```bash
flutter run --flavor dev --dart-define-from-file=config/dev.example.json
flutter test
```

也可以逐项传入：

```bash
flutter run \
  --flavor dev \
  --dart-define=APP_ENV=dev \
  --dart-define=API_BASE_URL=https://api.dev.example.invalid/
```

`main.dart` 现在只进入 `bootstrapApplication()`。启动层在 Flutter Binding 和全局异常处理器就绪后调用 `AppConfig.fromDartDefines()`；配置模型仍保持纯解析，不会自行读取网络、磁盘或插件状态。完整顺序与失败矩阵见 `docs/architecture/0003-application-bootstrap.md`。

## 验证与回滚

环境单元测试覆盖三套默认值、缺失值、未知值、原生 flavor 错配、安全 URL 规则、生产 HTTPS 和 base path 规范化。启动层另有配置失败到安全 UI 的边界测试；`dart tool/ci/check_platform_environments.dart` 负责跨 Dart/Android/iOS 漂移检查。原生配置的验证与回滚见 ADR 0013；回滚本 Dart 决策时不得误删其他平台工程或用户文件。
