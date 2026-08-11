# 国际化指南

本项目使用 Flutter SDK 自带的 `gen-l10n`，当前只真实维护通用英语 `en` 与通用中文 `zh`。
默认语言策略为跟随系统；设备语言均不受支持时固定回退英语。两种语言均为 LTR，当前实现不
声明 RTL 能力，也不以未维护的地区变体冒充独立翻译。

## 文件与所有权

```text
lib/app/localization/
├── app_locale.dart                            # locale 选择与回退规则
├── app_locale_persistence.dart                # 普通偏好边界
├── app_localizations.dart                     # BuildContext 与 AppError 映射
├── l10n.yaml                                  # 专项工具读取的固定 Flutter 配置
├── arb/
│   ├── app_en.arb                             # 唯一模板资源
│   ├── app_zh.arb                             # 中文资源
│   └── generated_header.txt                   # 中文生成标记
└── generated/                                 # 必须提交、禁止手改
    ├── app_localizations.dart
    ├── app_localizations_en.dart
    ├── app_localizations_zh.dart
    └── untranslated_messages.json
tool/generate_localizations.dart                # 专项生成与只读检查
```

ARB 是唯一人工维护的用户界面文案源。英语文件是 `gen-l10n` 模板；每个文案键及占位符都要
提供中文 `description` 元数据。日志事件、协议值、稳定错误 code、路由 URI、存储键和测试用
技术标识不翻译。Repository 返回的标题、描述等领域或服务端数据也不伪装为界面资源；具体项目
需要本地内容时，应在有明确产品协议的领域边界处理。

生成目录由工具整体替换。Flutter 3.29 官方模板自带英文说明，专项工具只在系统临时目录识别
并转换已知片段；出现未知英文生成注释、模板变化、缺失翻译、额外输出或无效 ARB 时，在触碰
已验证产物前失败。脚手架生成出来的 Dart 文档注释因此保持中文，Flutter 的固定 lint 指令除外。

配置有意位于 `lib/app/localization/l10n.yaml`，而不是仓库根目录。Flutter 3.29 的普通编译目标
只要发现根目录 `l10n.yaml`，就会在 `flutter run`、`flutter test` 和平台构建时直接重新生成
源码，绕过中文注释转换与写入前验证。专项工具会把受控配置复制到系统临时项目根目录后调用
官方命令；自身也会拒绝仓库根目录出现同名文件。不要把配置移回根目录。

若从曾经使用根配置的版本迁移，旧 `.dart_tool/flutter_build/**/gen_localizations.d` 仍可能把
提交源码登记为可删除构建输出。先执行一次 `flutter clean`，再依次执行锁定依赖解析、专项
生成和检查。工具会以 `L10N_LEGACY_BUILD_CACHE` 拒绝这类缓存，避免把随后的编译失败误判为
源码缺失；全新检出不需要额外清理。

## 生成与检查

修改任意 ARB 或 `lib/app/localization/l10n.yaml` 后，在仓库根目录执行：

```bash
dart run tool/generate_localizations.dart
dart run tool/generate_localizations.dart --check
```

第一条命令先在系统临时目录调用官方 `flutter gen-l10n`，完成资源、缺失翻译、清单和中文注释
验证，再原子替换固定输出目录。失败时保留最后一次已验证产物。第二条命令执行相同临时生成，
但只逐字节比较仓库输出，不写项目目录；缺失、过期或额外文件都会返回非零退出码。

不要直接在仓库根运行 `flutter gen-l10n`，也不要新增根目录 `l10n.yaml`。这两种做法都会
绕过中文注释归一化和写入前验证。也不要手工修改 `generated/` 或
`untranslated_messages.json`；修复 ARB 后重新运行专项命令。

CI 在锁定依赖解析后执行 `--check`。本地完整顺序至少包括：

```bash
dart tool/ci/check_generated_files.dart
flutter pub get --enforce-lockfile
dart run tool/generate_localizations.dart --check
dart tool/ci/check_architecture.dart
dart tool/ci/check_platform_environments.dart
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos --fatal-warnings
flutter test
```

## 使用文案与格式化

`TemplateApp` 和安全启动失败应用都注册生成代理、支持语言与统一回退函数。普通 Widget 在该
树下通过类型安全 getter 读取文案：

```dart
final copy = context.localizations;

Text(copy.exampleItemCount(count: itemCount));
Text(copy.exampleUpdatedOn(date: updatedAt));
Text(copy.exampleItemIdentifier(itemId: itemId));
```

生成方法会把实例自身的 locale 显式传给复数、日期和数字格式化。禁止设置
`Intl.defaultLocale`；全局值会让并行 Widget 树、测试和未来嵌入式场景互相污染。

Feature 不得导入 `app/localization`。应用层应把当前文案或职责具体的格式化函数注入 Feature
自有模型；示例采用 `ExampleDetailCopy`。应用错误继续用稳定 `AppError.code` 做程序判断，应用
本地化映射器负责转换用户文案，不能直接展示底层异常或把翻译文本当日志/协议标识。

## 语言选择与持久化

首页语言菜单提供“跟随系统 / English / 中文”。选择后 Riverpod 立即更新 `MaterialApp.locale`，
无需重启且不会重建 Router。显式英语或中文通过现有 `PreferenceStore` 写入
`appearance.locale`；跟随系统会删除该键，而不是保存设备当前语言。

并发选择按调用顺序串行写入。只有最新一次写入失败才把界面回滚到最后成功值，并展示当前
语言的安全反馈；较早失败不能覆盖新选择。读取失败或旧版本未知值不阻止启动，应用跟随系统；
若普通存储实例仍可用，后续选择可以修复值。语言偏好不含凭据，不得转存到安全存储。

## 新增语言

新增语言必须是团队能够持续维护和测试的真实资源，不能只复制英语占位。按以下顺序操作：

1. 新增完整 `app_<locale>.arb`，设置正确 `@@locale`，保持与 `app_en.arb` 完全相同的文案键、
   占位符类型和中文元数据。
2. 更新 `lib/app/localization/l10n.yaml` 的支持顺序、`tool/generate_localizations.dart` 的
   输入/输出白名单、已知官方生成类说明转换，以及 `AppLocalePreference`、存储值、菜单和
   回退测试。
3. iOS 同步更新 `CFBundleLocalizations`；Android 不需要静态语言列表。若新增 RTL 语言，必须
   增加文本方向、方向性图标、边距镜像、导航和全尺寸布局测试，不能沿用当前 LTR 结论。
4. 运行生成命令，确认 `untranslated_messages.json` 仍为 `{}`，连续生成哈希一致，`--check`
   严格通过。
5. 为复数类别、日期、数字、错误映射、运行时切换、系统回退、窄屏和 200% 文字补充该语言
   测试，并执行 Android 构建；iOS 在 macOS 补充实际构建和设备验证。

Flutter SDK 升级可能改变官方生成模板。此时工具应先因未知注释失败；审查新模板后明确更新
转换规则和测试，不能放宽为“允许任意英文注释”或关闭陈旧检查。

## 删除与回滚

国际化是应用组装层增强能力，不改变 `core/` 的存储或错误接口。完整删除时应在一个聚焦变更中：

1. 把 `TemplateApp`、安全启动页和错误 Widget 恢复为项目确认的单语言安全文案，移除代理、
   locale 解析、Controller override 和首页语言菜单。
2. 把示例页的 `ExampleDetailCopy` 注入替换为单语言 Feature 文案边界，或随示例 Feature 一并
   删除；不要让 Feature 为删除国际化而反向依赖 `app/`。
3. 删除 `lib/app/localization/`、`app_locale_controller.dart`、专项工具和对应测试，移除 CI
   检查、`flutter_localizations` 与 `intl`，重新生成 `pubspec.lock`。
4. 从 iOS `CFBundleLocalizations` 移除已删除声明，并同步平台门禁。遗留的普通偏好键不含敏感
   数据，可由一次明确迁移删除；不要用全量 preferences clear。
5. 运行格式、分析、全量测试、生成/平台门禁和 Android 构建，确认启动失败路径仍不暴露异常。

生成失败时不需要删除当前产物：先保留最后已验证版本，修复输入后再次生成。需要整体回滚
Task 5 时，应成组恢复源码、ARB、生成工具与产物、依赖/锁文件、CI、iOS 声明、测试和文档；
只删除生成文件或只降级 `intl` 都会留下不可编译或不可复现状态。
