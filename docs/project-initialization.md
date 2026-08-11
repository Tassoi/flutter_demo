# 项目初始化与产品标识配置

本文说明如何把本脚手架用于一个新项目，并精确配置 Dart 项目名、描述、组织名、应用展示名、
Android application ID、iOS bundle identifier 和目标平台。当前仓库不提供脚手架 CLI；
初始化依赖 Flutter 官方命令，成品模板的三环境标识则按本文清单一次性修改。

## 两种操作不要混用

Flutter 官方初始化与采用本模板是两个不同动作：

1. `flutter create` 用于在空目录生成官方平台骨架，适合验证项目名、组织名、描述和平台参数。
2. 当前仓库已经包含定制的 Android flavors、iOS schemes、测试、CI 和基础设施。创建业务项目时，
   应复制或从模板仓库创建一个新仓库，然后按本文重命名。

不得在成品模板根目录直接执行 `flutter create .`。Flutter 只保证维护官方模板文件，不理解本项目
的三环境契约；重新生成可能添加通用 `Runner.xcscheme` 或改写平台配置，从而绕过环境选择门禁。
需要比较 Flutter 新模板时，只能在独立临时目录生成，再逐项审查差异。

## 先确定产品标识

开始修改前，先记录一份不可含真实密钥的产品标识表。下表给出当前占位值和约束：

| 输入 | 当前占位值 | 约束 |
| --- | --- | --- |
| Dart 项目名 | `flutter_template` | 使用 `lowercase_with_underscores`；同时决定 `package:` import 前缀 |
| 项目描述 | `A reusable, testable Flutter application scaffold.` | 写入 `pubspec.yaml`，不放内部地址或凭据 |
| 组织名 | `com.example` | 只在官方初始化时作为派生标识输入；成品工程没有可单独修改的全局 org 字段 |
| Android production ID/namespace | `com.example.flutter_template` | 反向域名；dev/staging 继续追加 `.dev`/`.staging` |
| iOS production bundle ID | `com.example.flutterTemplate` | 反向域名；dev/staging 继续追加 `.dev`/`.staging` |
| production 展示名 | `Flutter Template` | 面向用户，可含空格 |
| dev/staging 展示名 | `Flutter Template Dev` / `Flutter Template Staging` | 应能从桌面名称直接区分环境 |
| 目标平台 | `android,ios` | 第一阶段只维护 Android/iOS，不包含 Web 或桌面平台 |

Android 与 iOS 标识可以采用不同的最后一段格式，但一旦发布就不应随意变更。生产标识不得继续
使用 `com.example`；也不要把客户名、邮箱、环境密钥或其他敏感数据写入标识。

## 用官方命令验证空工程输入

下面的命令必须指向一个不存在或为空的目录，不能指向本模板工作区：

```bash
flutter create \
  --project-name acme_portal \
  --org com.acme \
  --description "Acme portal mobile application." \
  --platforms android,ios \
  --empty ../acme_portal_flutter_baseline
```

在本项目固定的 Flutter 3.29.0 中，该命令产生以下映射：

| 参数 | 官方生成结果 |
| --- | --- |
| `--project-name acme_portal` | `pubspec.yaml` 的 `name: acme_portal` 和 Dart 包名 |
| `--description ...` | `pubspec.yaml` 的 `description` |
| `--org com.acme` + 项目名 | Android `com.acme.acme_portal` 与 iOS `com.acme.acmePortal` |
| `--platforms android,ios` | 只登记 root、Android 和 iOS，不生成 Web/desktop 平台 |
| `--empty` | 最小 `main.dart`，不生成计数器示例 |

`flutter create` 没有为本模板配置三套展示名、flavor 或 scheme；这些属于下一节的成品模板配置。
初始化完成后至少在空工程目录执行一次：

```bash
flutter analyze --fatal-infos --fatal-warnings
```

2026-08-10 的 Task 17 验收使用上面的参数形状创建了独立探针，核对了 Dart、Android、Kotlin
路径、iOS 与 `.metadata`，严格分析为零问题。探针验证后已移入系统回收站，没有写入主工作区。

## 重命名成品模板

以下修改必须作为同一个变更完成。只改 `pubspec.yaml` 或只改平台包名会让 Dart import、原生
入口、环境门禁或测试互相漂移。

### 1. Dart 项目名、描述和展示名

1. 修改 `pubspec.yaml` 的 `name` 与 `description`。
2. 把 `lib/` 和 `test/` 中所有 `package:flutter_template/` import 改为新的 Dart 包名前缀。
3. 修改 `lib/app/config/app_config.dart` 中 dev、staging、prod 的 `appName`；保留
   `packageNameSuffix` 的 `.dev`、`.staging` 和空字符串语义，除非产品明确选择另一套环境标识。
4. 同步修改 `test/app/config/`、`test/app/router/` 和 `test/app/template_app_test.dart`
   的展示名断言。

可以先用只读搜索确定影响面：

```bash
rg -n "package:flutter_template/|Flutter Template" lib test pubspec.yaml
```

不要用未经审查的全仓库字符串替换。历史 ADR、Goal 证据和本指南可能有意记录旧占位值，平台
标识的大小写规则也不同。

### 2. Android 标识

按以下顺序更新：

1. 在 `android/app/build.gradle.kts` 同时修改 `namespace` 与 production `applicationId`，
   并修改三个 flavor 的 `app_name`。
2. 把 `android/app/src/main/kotlin/com/example/flutter_template/MainActivity.kt` 移到与新
   namespace 对应的目录，并修改文件首行 `package`。目录与 package 必须一致。
3. 修改 `android/app/src/main/AndroidManifest.xml` 的环境 metadata 名称：
   `com.example.flutter_template.APP_ENV` 应变为新 namespace 加 `.APP_ENV`。
4. 保留 dev/staging 的 `applicationIdSuffix`，使三个环境可以并存安装；production 不加后缀。
5. release 签名继续保持未配置，直到项目在版本控制外接入真实签名材料。

例如 production ID 选择 `com.acme.acme_portal` 时，三个 application ID 应为：

| 环境 | Android application ID |
| --- | --- |
| dev | `com.acme.acme_portal.dev` |
| staging | `com.acme.acme_portal.staging` |
| prod | `com.acme.acme_portal` |

### 3. iOS 标识

应在 macOS/Xcode 中审查修改；文本修改后仍必须用 Xcode 构建确认：

1. 在 `ios/Runner.xcodeproj/project.pbxproj` 修改 9 个应用 configuration 的
   `PRODUCT_BUNDLE_IDENTIFIER` 和 `APP_DISPLAY_NAME`。
2. 同步修改 9 个 RunnerTests configuration 的 bundle identifier；测试标识保持在对应应用
   标识后追加 `.RunnerTests`。
3. 保留 dev、staging、prod scheme 与 Debug/Profile/Release configuration 的对应关系。
4. `ios/Runner/Info.plist` 已通过 `$(APP_DISPLAY_NAME)` 和
   `$(PRODUCT_BUNDLE_IDENTIFIER)` 读取配置，不应再写一套硬编码值。

例如 production bundle ID 选择 `com.acme.acmePortal` 时：

| 环境 | 应用 bundle identifier | 测试 bundle identifier |
| --- | --- | --- |
| dev | `com.acme.acmePortal.dev` | `com.acme.acmePortal.dev.RunnerTests` |
| staging | `com.acme.acmePortal.staging` | `com.acme.acmePortal.staging.RunnerTests` |
| prod | `com.acme.acmePortal` | `com.acme.acmePortal.RunnerTests` |

### 4. 同步工程门禁与文档

平台检查器故意保存当前标识的精确契约，因此重命名时还必须同步：

1. `tool/ci/check_platform_environments.dart` 的三套展示名、Android metadata 名称和 iOS
   production bundle ID。
2. `test/tool/ci/check_platform_environments_test.dart` 的内存夹具与漂移断言。
3. `README.md`、`docs/architecture/0002-project-boundaries-and-environments.md` 和
   `docs/architecture/0013-mobile-environment-builds.md` 的环境表。
4. 其他仍面向当前产品显示旧名称或旧标识的测试与文档。

检查器不是通用品牌生成器，也不应为了省去这些显式修改而放宽为“任意字符串”。它的职责是
在一次重命名完成后，继续阻止 Dart、Android 与 iOS 发生静默漂移。

## 目标平台选择

Flutter 官方 `--platforms` 参数负责新空工程的平台选择。本脚手架第一阶段实际维护且已验证的
交付组合是 `android,ios`；不要把 `web`、`windows`、`linux` 或 `macos` 加入命令后宣称它们
继承了当前平台配置、存储安全或 CI 证据。

如果具体产品只保留 Android 或只保留 iOS，必须把它作为独立的平台裁剪变更处理，而不是仅删除
一个目录：

1. 删除不选平台的工程目录。
2. 删除 `.github/workflows/quality.yml` 中对应构建 job。
3. 调整 `tool/ci/check_generated_files.dart`、`tool/ci/check_platform_environments.dart`
   及其测试，使必需平台集合与新选择一致。
4. 更新 README、ADR、构建命令和平台风险说明。
5. 对保留平台执行实际构建；没有构建证据时不得把裁剪标记完成。

`.metadata` 是 Flutter tool 的迁移输入，不是品牌配置文件，禁止手工修改。平台集合发生变化时
应先在独立副本验证 Flutter tool 行为，并把 metadata、平台门禁和实际构建作为一个整体审查。
当前 Task 17 只验证了 Android+iOS 组合，没有把单平台裁剪标记为已完成。

## 重命名后的验收

先确认运行时与测试源码不再引用旧 Dart 包名或平台标识：

```bash
rg -n "package:flutter_template/" lib test
rg -n "com\.example\.flutter_template|com\.example\.flutterTemplate" \
  lib test tool android ios pubspec.yaml
```

两条命令在完整重命名后都应无匹配；如果保留匹配，必须逐项证明它只是有意的历史测试输入。
然后执行完整质量顺序：

```bash
dart tool/ci/check_generated_files.dart
flutter pub get --enforce-lockfile
dart tool/ci/check_architecture.dart
dart tool/ci/check_platform_environments.dart
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos --fatal-warnings
flutter test --test-randomize-ordering-seed=20260809
```

Android 至少构建一个显式环境：

```bash
flutter build apk --debug --flavor dev \
  --dart-define-from-file=config/dev.example.json
```

iOS 必须在 macOS 执行：

```bash
flutter build ios --debug --no-codesign --flavor dev \
  --dart-define-from-file=config/dev.example.json
```

有设备或模拟器时再执行 `flutter run`，核对桌面展示名、包标识、环境和首屏。重命名后的回滚
必须成组恢复 Dart 名称/import、Android、iOS、检查器、测试和文档；不得只恢复其中一层而留下
能够通过局部编译、却在另一平台或 CI 中失败的半完成状态。
