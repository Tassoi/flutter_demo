# ADR 0013：移动端三环境原生构建

- 状态：Accepted
- 决策日期：2026-08-09
- 适用范围：第一阶段 Android/iOS 原生环境配置与构建验证

## 背景

Dart 配置已经严格要求 `APP_ENV` 为 `dev`、`staging` 或 `prod`，但只有 Dart define 无法改变
安装包标识、桌面展示名或 Xcode 构建配置。若原生环境与 Dart 环境可以独立选择，开发包可能
携带生产后端配置，或者多个环境互相覆盖安装；若模板默认使用 debug key 签名 release，又会把
占位配置误解为可发布配置。

本决策只完成第一阶段原生构建基线，不生成环境图标、启动资源、证书、Provisioning Profile、
Keystore 或发布流水线。品牌资源仍属于第二阶段，真实签名必须由具体项目在版本控制外配置。

## 唯一环境表

| 环境 | Flutter flavor | Android application ID | iOS bundle identifier | 展示名 |
| --- | --- | --- | --- | --- |
| 开发 | `dev` | `com.example.flutter_template.dev` | `com.example.flutterTemplate.dev` | Flutter Template Dev |
| 预发布 | `staging` | `com.example.flutter_template.staging` | `com.example.flutterTemplate.staging` | Flutter Template Staging |
| 生产 | `prod` | `com.example.flutter_template` | `com.example.flutterTemplate` | Flutter Template |

基础标识仍是明显的模板占位值，真实项目必须在初始化时整体替换。后缀与 ADR 0002 的
`AppConfig.packageNameSuffix` 完全相同；`prod` 不追加后缀。三个环境复用当前占位图标和启动资源，
不得在第一阶段提前生成品牌或环境专属资源。

## Android 决策

`android/app/build.gradle.kts` 只定义一个 `environment` flavor dimension：

1. 每个 flavor 固定 application ID 后缀、`app_name` 和 `app_environment` 字符串资源。
2. Manifest 从资源读取展示名，并把环境作为只读 metadata 打包，便于直接审计 APK；应用业务
   仍只读取已经校验的 Dart `APP_ENV`，不建立第二套运行时配置源。
3. 主 Manifest 声明 `INTERNET`，保证 Dio 网络适配器不只在 Flutter 默认的 debug/profile
   Manifest 中可用；平台门禁会阻止 release 联网权限被静默移除。
4. 不设置 `defaultFlavor`。缺少 `--flavor` 的 APK 与 App Bundle 命令必须在 Gradle 配置阶段
   检查 `startParameter.taskNames` 并立即失败，不能先执行聚合 `assemble*`/`bundle*` 的 flavor
   依赖再报错。聚合任务自身的 `doFirst` 动作触发过晚，会先用同一份 Dart define 覆盖三套
   环境产物，因此不属于有效保护。
5. release 不再复用 debug signing config，也不包含仓库 Keystore。具体项目只能通过本机安全
   配置或受控 CI secret 注入签名，不得把密码、证书或私钥加入源码。
6. 当前保留 Flutter 默认 ABI 集合。官方不建议在单个 flavor 设置 `abiFilters`；未来 stable
   移除 x86 时应随 Flutter/Gradle 升级统一评估，而不是让三个环境产生不同 ABI。

## iOS 决策

Xcode 工程只保留以下 9 个 build configurations：

```text
Debug-dev       Profile-dev       Release-dev
Debug-staging   Profile-staging   Release-staging
Debug-prod      Profile-prod      Release-prod
```

Project、Runner 和 RunnerTests 都具有同名配置。三个共享 scheme 使用小写名称 `dev`、
`staging`、`prod`，并按以下规则绑定：

| Scheme action | Build configuration |
| --- | --- |
| Run、Test、Analyze | `Debug-<environment>` |
| Profile | `Profile-<environment>` |
| Archive | `Release-<environment>` |

通用 `Runner` scheme 被移除，避免绕过环境选择。Runner 配置提供 `APP_ENV`、
`APP_DISPLAY_NAME` 和占位 bundle identifier；Info.plist 只引用这些 build settings。Podfile 明确
把 9 个配置映射到 CocoaPods 的 debug/release 模式。CocoaPods 会把完整 configuration 名小写后
生成 `Pods-Runner.debug-dev.xcconfig` 等文件，因此每个 Runner configuration 都使用自己的
`<Mode>-<environment>.xcconfig` 包装层：先 include 完全同名的 Pods 配置，再 include 公共
`Debug.xcconfig` 或 `Release.xcconfig` 以取得 Flutter 生成设置和 entitlement。不能让 9 个配置
共用不存在的 `Pods-Runner.debug.xcconfig`/`release.xcconfig`。workspace 继续登记 Pods project；
工程不包含开发团队、Profile、证书或真实 App ID 注册信息。

## Dart 对齐与构建入口

Flutter CLI 会把 `--flavor` 编译为 `appFlavor`。`AppConfig.fromDartDefines()` 在该值存在时要求它
与 `APP_ENV` 精确一致；大小写、空格或跨环境错配会在依赖初始化前抛出固定 `FormatException`，
再由既有启动失败边界安全呈现。纯 Dart 测试或直接由 Xcode 发起的构建可能没有 `appFlavor`，
因此 `APP_ENV` 仍严格必填，但无法执行这项跨边界比对。

推荐始终通过 Flutter CLI 成对传入参数：

```bash
flutter run --flavor dev --dart-define-from-file=config/dev.example.json
flutter build apk --debug --flavor staging \
  --dart-define-from-file=config/staging.example.json
flutter build ios --debug --no-codesign --flavor prod \
  --dart-define-from-file=config/prod.example.json
```

`config/*.example.json` 只含 `.invalid` 地址。真实 API 地址即使通过本地 define 文件注入也会进入
编译产物，因此其中仍禁止 API key、Token、密码、证书、签名数据或长期凭据。

## 一致性门禁与 CI

`dart tool/ci/check_platform_environments.dart` 使用 Dart 标准库静态核对：

1. Dart 展示名、后缀、示例 JSON 和 flavor 错配保护。
2. Android flavor 维度、后缀、资源、主 Manifest 联网/备份策略、配置阶段聚合入口保护及
   release 签名边界。
3. Xcode 27 个配置对象与 configuration list、三套 scheme action、Runner/RunnerTests bundle ID。
4. Info.plist build settings、Keychain entitlement、Podfile 9 项映射、9 个 configuration 专属
   Pods xcconfig 包装层和 workspace 接线。

检查器是针对当前工程形状的门禁，不解析任意 Gradle/PBX，也不生成配置。结构发生有意变化时，
必须同时更新实现、正反测试和本 ADR，不能只放宽规则。

CI 继续固定 Flutter 3.29.0 与完整 revision。质量任务通过后：

1. `ubuntu-24.04` 顺序构建 dev、staging、prod 三个 debug APK。
2. `macos-15` 固定 `/Applications/Xcode_16.4.app` 和 CocoaPods 1.16.2，顺序执行三个
   `--no-codesign` iOS debug 构建。任务只验证编译和 CocoaPods 接线，不签名、不上传、不发布。

当前开发主机不是 macOS，因此本地只能静态核对 iOS 工程；GitHub-hosted macOS job 的实际日志
是三环境编译证据，不能把 workflow 文件本身当作通过证据。真实签名和设备行为仍需业务项目补证。

## 回滚

若原生环境配置导致构建回归，应整体回滚本决策涉及的 Gradle flavors、Manifest 环境资源、
Xcode configurations/schemes、Podfile/9 个专属 xcconfig 包装层/workspace、Dart flavor 比对、平台检查器、对应测试
和 CI 平台任务。回滚后必须恢复此前可构建的单环境平台文件，并同步撤销 README/ADR 中的
三环境承诺；不得删除 Dart 基础设施、用户 `AGENTS.md`、Goal 原文或无关功能。

## 官方来源

1. [Flutter Android flavors](https://docs.flutter.dev/deployment/flavors)
2. [Flutter iOS schemes and configurations](https://docs.flutter.dev/deployment/flavors-ios)
3. [GitHub-hosted runner images](https://github.com/actions/runner-images)
4. [CocoaPods 1.16.2 xcconfig path implementation](https://github.com/CocoaPods/CocoaPods/blob/861039444193ac218160ae5486a12016ac9f485d/lib/cocoapods/target.rb#L244-L249)
