# 常见问题与诊断

先保留第一条失败日志，再做最小诊断。不要先删除锁文件、修改全局 Flutter SDK、关闭门禁或
运行无目标的清理命令；这些操作会抹掉根因并产生新的漂移。

## WSL 报 `bash\r` 或 shebang 错误

**原因**：当前工作站的 Flutter SDK 位于 Windows 文件系统，无扩展名 Bash 入口使用 CRLF。
WSL 会把回车识别为解释器路径的一部分。

**处理**：不要改写用户的全局 SDK，改用 Windows 批处理入口：

```bash
/mnt/c/Windows/System32/cmd.exe /d /c flutter --version
/mnt/c/Windows/System32/cmd.exe /d /c flutter pub get --enforce-lockfile
/mnt/c/Windows/System32/cmd.exe /d /c flutter test
```

原生 Windows 终端、macOS、Linux 和 CI 继续使用普通 `flutter`/`dart` 命令。

## Android 报 `An environment flavor is required`

**原因**：项目故意拒绝 Gradle 的通用 `assemble*`/`bundle*` 聚合任务。未指定 flavor 会尝试把
同一份 Dart define 构建到多个原生环境，可能生成错配产物。保护必须在 Gradle 配置阶段触发；
若先执行 flavor 依赖再报错，已有产物仍会被错误配置覆盖。

**处理**：显式选择 flavor，并让配置文件使用相同环境：

```bash
flutter run --flavor dev \
  --dart-define-from-file=config/dev.example.json
flutter build apk --debug --flavor dev \
  --dart-define-from-file=config/dev.example.json
```

不要删除 `android/app/build.gradle.kts` 中基于显式请求任务的早期保护，也不要改回聚合任务的
`doFirst` 动作。staging/prod 也必须成对替换两个环境名。修改这段配置后，应运行平台门禁测试，
并比较一次失败命令前后的环境产物哈希或修改时间，确认失败没有触碰产物。

## 应用只显示安全启动失败页

**原因**：`APP_ENV` 缺失、不是精确小写的 `dev`/`staging`/`prod`、含空格，或与 Android
flavor/iOS scheme 不一致。无效 `API_BASE_URL` 也会在依赖组装前失败。

**处理**：检查 JSON 是合法对象，并使用匹配命令：

```bash
flutter run --flavor staging \
  --dart-define-from-file=config/staging.example.json
```

失败页有意不显示原始值、URL、异常或堆栈。不要为排查把真实配置打印到日志；配置契约见
[`config/README.md`](../config/README.md)。

## `GENERATED_LOCK_STALE` 或锁文件变化

**原因**：`pubspec.yaml` 与 `pubspec.lock` 不属于同一次依赖求解，或 SDK 支持范围变化后没有
重新审查锁文件。

**处理**：如果没有计划升级，恢复两者到同一已知基线；如果正在升级，按
[依赖升级指南](dependency-upgrades.md)生成并审查锁文件：

```bash
flutter pub get --enforce-lockfile
dart tool/ci/check_generated_files.dart
```

不要手工编辑 `pubspec.lock`，也不要删除它后接受整张依赖图的无审查升级。

## `.metadata` 检查失败

检查器可能返回 `GENERATED_METADATA_REVISION`、`CHANNEL`、`PROJECT_TYPE`、`PLATFORMS`、
`PLATFORM_REVISION` 或 `UNMANAGED`。这些规则验证创建信息格式、app 类型、仅 root/Android/iOS
平台、合法迁移 revision，以及定制入口/PBX 工程的保护项。

`.metadata` 顶层 revision 是项目创建时的 Flutter framework，不要求等于当前 SDK。当前 SDK
由 `.github/workflows/quality.yml` 三个 job 的完整 `FLUTTER_REVISION` 固定。处理时先查看实际
diff 和失败规则：

```bash
dart tool/ci/check_generated_files.dart
git diff -- .metadata .github/workflows/quality.yml
```

不要手工把 `.metadata` revision 改成当前 SDK，也不要在主工作区盲目执行 `flutter create .`；
后者可能覆盖定制平台输入或重新生成通用 `Runner` scheme。

## `DOC_*` 文档契约检查失败

`DOC_LINK_MISSING`/`ANCHOR` 表示本地 Markdown 目标或标题已经移动；
`DOC_COMMAND_TARGET_MISSING` 表示 Bash 示例引用了不存在的项目工具、测试或显式配置；
`DOC_QUALITY_COMMAND_DRIFT` 表示 README、阶段二操作指南与 Quality workflow 的命令或顺序不同。

```bash
dart tool/ci/check_documentation.dart
flutter test test/tool/ci/check_documentation_test.dart
```

修复项目相对链接或同步真实命令后重跑。检查有意不访问外网，也不把 `.dart_tool`、`build/`、
IDE 状态或 `goal-*` 审计目录当作有效目标，因此不能创建同名缓存文件掩盖缺失文档。若质量顺序
确实变化，必须在同一变更中更新 README、`docs/phase-2-operations.md`、workflow、ADR 0012
和测试；不要删除检查步骤或放宽为任意命令。

## Android SDK、NDK、JDK 或 licenses 失败

当前基线是 platform 36、build-tools 35.0.1、NDK 27.0.12077973、min SDK 23；已验证工作站使用
JDK 21，项目 Java/Kotlin bytecode 目标为 11。

先检查实际环境：

```bash
flutter doctor -v
flutter doctor --android-licenses
flutter build apk --debug --flavor dev \
  --dart-define-from-file=config/dev.example.json --verbose
```

安装日志明确指出的缺失 SDK/NDK，并保留项目固定版本。不要通过降低 compile SDK、NDK 或 min
SDK 来绕过插件要求，也不要提交个人 `local.properties`。

## Maven 网络探测超时

`flutter doctor -v` 的 Maven 探测超时可能只是外部网络问题；已有缓存下构建成功不代表全新
runner 能冷启动。先执行带 `--verbose` 的上方 Android 构建，区分“探测失败”和“Gradle 无法
解析依赖”。

如果冷缓存确实无法下载，检查 DNS、代理、防火墙和官方仓库连通性。不要提交个人代理、内部
镜像凭据、禁用 TLS 或用来源不明的二进制替换依赖。CI 首次冷启动仍需留下真实证据。

## `flutter run` 找不到设备

检查设备列表：

```bash
flutter devices
flutter emulators
```

启动模拟器或连接已授权设备后重试带 flavor 的运行命令。没有设备时可以用 Android APK 构建
验证编译，但构建不能证明安装、插件通道、触摸、TalkBack、Keychain 或 VoiceOver 行为。

## iOS Xcode、CocoaPods 或 xcconfig 失败

iOS 必须在 macOS 上使用 Xcode 16.2 与 CocoaPods 1.16.2 验证。项目只有 `dev`、`staging`、
`prod` 三个共享 scheme，每个 Debug/Profile/Release configuration 都有专属 wrapper xcconfig
和对应 Pods include。

```bash
xcodebuild -version
pod --version
dart tool/ci/check_platform_environments.dart
flutter build ios --debug --no-codesign --flavor dev \
  --dart-define-from-file=config/dev.example.json
```

出现 Pods include、configuration 或 scheme 错误时，先检查 `ios/Podfile`、`ios/Flutter/*.xcconfig`、
PBX configuration 与三个 `.xcscheme` 是否同步。不要改回通用 Debug/Release fallback，也不要新增
`Runner.xcscheme`；通用 scheme 会绕过环境对齐约束。非 macOS 主机的静态检查不能替代 Xcode
真实编译。

## release 构建提示缺少签名

这是模板的安全默认。仓库不包含 Android Keystore、密码、iOS Team/Profile 或可发布配置。
真实项目必须在版本控制外建立签名注入和受保护的发布流程；不要把 release signing 指向 debug
key，也不要把证书或密码写进 Gradle、xcconfig、JSON 或 CI 日志。

无签名 iOS 编译验证使用：

```bash
flutter build ios --debug --no-codesign --flavor prod \
  --dart-define-from-file=config/prod.example.json
```

## 启用网络示例后 `.invalid` 地址失败

三个 example JSON 默认使用不可路由的 `.invalid` 地址，bundled Repository 不会访问它。只有
显式把示例组装切换为 `NetworkExampleRepository` 后，才需要提供本机配置：

```bash
cp config/dev.example.json config/dev.local.json
flutter run --flavor dev \
  --dart-define-from-file=config/dev.local.json
```

修改 `dev.local.json` 的 `API_BASE_URL`；prod 必须使用 HTTPS。Dart define 会进入应用二进制，
所以 local 文件也不能存 API key、Token、密码、证书或长期凭据。

dev/staging 的配置模型接受 HTTP 不代表移动平台默认放行明文传输。模板不会全局关闭 Android
Network Security 或 iOS App Transport Security；优先让本地服务提供 HTTPS。若具体项目必须
调试明文服务，应只对明确开发环境和目标主机配置最小原生例外，补充平台门禁与实际设备测试，
不得通过全局 `usesCleartextTraffic` 或 `NSAllowsArbitraryLoads` 放宽所有连接。

## 何时使用 `flutter clean`

只有证据指向过期的 `build/`、`.dart_tool/` 或 Flutter/CocoaPods 临时生成状态时才使用：

```bash
flutter clean
flutter pub get --enforce-lockfile
```

清理前保留原始错误和 `git status --short`，清理后重新运行生成产物检查、聚焦测试和对应平台
构建。`flutter clean` 不会修复错误的 flavor、SDK 约束、锁文件、PBX 配置或业务逻辑，也不能作为
删除 `pubspec.lock`、Pods 配置或用户数据的理由。

若问题仍无法定位，在报告中附上失败命令、首个错误、`flutter --version --machine`、
`flutter doctor -v`、目标环境和已执行的最小复现步骤，并先移除路径、用户名、Token、证书和
真实服务地址。
