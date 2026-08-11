# 品牌资源生成指南

本指南描述如何从一组经过授权的 PNG 源文件，确定地生成 Android/iOS 应用图标和启动资源。
品牌工具只做预检、格式转换、平台接线与漂移检查，不设计、绘制或下载 Logo，也不修改项目名、
包名、Bundle Identifier、签名、证书或发布配置。

## 权利与占位资源

品牌源必须由项目方拥有，或已经获得覆盖目标应用、平台、地区和分发渠道的明确授权。工具包的
MIT 许可证只覆盖生成工具，不覆盖输入图片。正式资源的来源、权利持有人、授权范围、署名和
限制必须记录在 `assets/branding/LICENSE.md`；缺失权利声明时生成会在平台写入前失败。

仓库当前源图是为流水线验证创建的中性几何占位，不包含客户或第三方 Logo。它可以随模板使用，
但不得被描述为下游项目的正式品牌；发布真实项目之前必须替换。

## 固定输入契约

`assets/branding/` 只允许以下文件：

| 文件 | 要求 | 用途 |
| --- | --- | --- |
| `app_icon.png` | 1024 x 1024、单帧 PNG、完全不透明 | Android 传统图标与 iOS AppIcon |
| `app_icon_foreground.png` | 1024 x 1024、透明画布、存在可见图形 | Android Adaptive Icon 前景 |
| `app_icon_background.png` | 1024 x 1024、完全不透明 | Android Adaptive Icon 背景 |
| `app_icon_monochrome.png` | 可选；1024 x 1024、透明画布、灰度可见图形 | Android 13+ 主题图标 Alpha 蒙版 |
| `splash_logo.png` | 1024 x 1024、透明画布、存在可见图形 | 旧 Android、Android 12+ 与 iOS 启动 Logo |
| `LICENSE.md` | 登记每个实际输入及其权利范围 | 阻止未登记素材进入生成流程 |

Adaptive 前景、单色图和启动 Logo 的所有非透明像素必须位于 `108 x 108` 图层坐标的中心
`66 x 66` 安全区。源图换算到 1024 画布后，可见边界不得越过工具计算出的安全范围。这样系统
应用圆形、圆角矩形等蒙版时不会裁掉核心图形。完整图标和背景不得依赖透明像素；iOS 输出还会
再次核对所有 AppIcon 像素不透明。

单色图确实不可提供时，应同时删除 `app_icon_monochrome.png` 和
`flutter_launcher_icons.yaml` 中的 `adaptive_icon_monochrome` 字段。只删一处会被视为配置
漂移。不要在目录中保留草稿、导出备份、`.DS_Store` 或未登记子目录。

## 唯一配置

应用图标只读取根目录 `flutter_launcher_icons.yaml`，启动资源只读取
`flutter_native_splash.yaml`。不得把同一配置复制进 `pubspec.yaml`，也不得新增
`-dev`、`-staging`、`-prod` 配置。两份配置只启用 Android/iOS；Web、Windows 和 macOS 不在
当前脚手架范围内。

背景色使用不带 Alpha 的 `#RRGGBB`。Android 12 配置必须复用同一个 `splash_logo.png` 和背景
色。品牌源只供仓库工具读取，没有注册到 Flutter runtime assets，因此不会在原生资源之外再
打包一份 1024 源图。

## 生成与检查

修改图片、权利声明或任一配置后执行：

```bash
flutter pub get --enforce-lockfile
dart run tool/generate_branding.dart
dart run tool/generate_branding.dart --check
```

工具依次执行以下步骤：

1. 用 `image 4.8.0` 校验真实 PNG、尺寸、Alpha、灰度和安全区，并结构化校验 YAML、依赖与
   权利声明。
2. 复制上游所需的最小 Android/iOS 骨架到系统临时项目。
3. 在临时项目调用精确锁定的 `flutter_launcher_icons 0.14.4` 和
   `flutter_native_splash 2.4.6`。
4. 拒绝所有非白名单平台修改，核对图片尺寸、Asset Catalog、Manifest、Adaptive Icon、
   Android 12 style 和 iOS LaunchScreen 引用。
5. 默认生成在读取现有产物前先逐级拒绝符号链接、目录占位和特殊文件，再把候选写入项目
   `.dart_tool` 的同文件系统暂存区；回读后才逐文件备份并 rename，任一失败会逆序恢复整组
   旧目标，相同字节不会重写。
6. `--check` 使用同一输出路径类型约束，只在系统临时目录重建期望结果并逐字节比较，不跟随
   受管路径中的符号链接，不创建项目暂存目录，也不改变目标内容或 mtime。

当前启用单色图时，白名单包含 73 个文件：Android 五档传统图标、五档 Adaptive 三图层、
Adaptive XML、旧版/Android 12 明暗启动图片与 styles；iOS 完整 AppIcon、LaunchImage、
LaunchBackground Catalog 和 LaunchScreen。关闭单色图后只移除对应五个 PNG，并同步更新
Adaptive XML。手写文件不得放入受管 AppIcon、LaunchImage 或 LaunchBackground Catalog；工具
遇到未知文件会失败，不会静默删除。

上游 launcher 0.14.4 会把当前 Xcode 工程中的 Swift Asset Symbols 设置过宽替换为 `AppIcon`；
splash 工具在 `fullscreen: false` 时会重排 `Info.plist` 并加入等价的显式 false。wrapper 只在
临时项目接受并验证这两个已知行为，然后恢复原 PBX/plist 字节，不让品牌生成覆盖环境、国际化
或其他用户配置。splash 2.4.6 新建的两份 v31 styles 还会在注释空行保留缩进空格；wrapper 只对
这两个本来不存在的新产物统一 LF 并移除行尾空白，不归一化既有 XML。升级工具版本时必须重新
验证这些兼容处理，不能直接删除或放宽白名单。

## 三环境与平台验证

`dev`、`staging`、`prod` 共用完全相同的源图和产物：

- Android flavor 都继承 `android/app/src/main/res`，各 flavor 的 `res/` 不得出现
  `ic_launcher`、`splash`、`background` 或 `launch_background` 的任何资源格式，也不得用
  符号链接或特殊文件绕过公共资源边界。
- Android 主 Manifest 唯一引用 `@mipmap/ic_launcher`。
- iOS 九个 Runner 构建配置都引用同一个 `AppIcon`，三个 scheme 共用同一 LaunchScreen。
- 不生成环境角标、环境专属 Logo 或三份重复输入。

聚焦验证命令：

```bash
flutter test test/tool/generate_branding_test.dart
dart run tool/generate_branding.dart --check
dart tool/ci/check_platform_environments.dart
flutter build apk --debug --flavor dev \
  --dart-define-from-file=config/dev.example.json
```

生成器测试覆盖非法格式、Alpha、安全区、单色边界、权利/平台配置、连续两次完整生成、73 文件
清单、只读漂移、输出链接拒绝和第二目标失败后的整组恢复。修改品牌工具版本、配置或原生输出
规则时，还必须执行格式、严格分析、全量测试和 Android 实际构建。iOS 的 Catalog/XML 静态
检查不能替代 macOS 上的 Xcode 构建、模拟器/真机启动画面和图标蒙版验证。

## 替换正式品牌

1. 从设计/品牌负责人取得原始授权证明和符合固定画布的 PNG 导出，不从搜索引擎或未知素材站
   下载图片。
2. 在可恢复分支中替换五个源文件；不提供单色图时按上文成组删除文件和配置字段。
3. 更新 `LICENSE.md`，逐项记录来源、权利持有人、授权范围与限制。
4. 运行生成命令，审查所有源图和平台二进制 diff；确认 iOS 图标无 Alpha、Adaptive 图形位于
   多种系统蒙版安全区、启动 Logo 在浅色背景可识别。
5. 连续运行两次生成并执行 `--check`，确认第二次没有内容 diff。
6. 执行专项测试、平台静态门禁、全量测试、Android 构建，并在 macOS/Xcode 与代表设备上补齐
   iOS 和真实启动视觉证据。

## 故障、回滚与删除

- `BRANDING_PNG_*`、`BRANDING_IMAGE_*` 或 `BRANDING_ADAPTIVE_SAFE_ZONE`：修正源图，不要跳过
  预检或手改缩放后的平台 PNG。
- `BRANDING_OUTPUT_STALE`：重新运行默认生成并审查 diff；不要把 `--check` 改成写模式。
- `BRANDING_UPSTREAM_WHITELIST`：上游版本或平台模板产生了未知写入，先审查工具/模板变化，
  不能扩大白名单来掩盖问题。
- `BRANDING_INSTALL_FAILED`：正常回滚已经恢复旧产物，可以修正原因后重试。
- `BRANDING_ROLLBACK_FAILED`：立即停止生成，保留错误中点名的
  `.dart_tool/branding_install_*`，从其 `backup/` 按相对路径人工恢复后再执行 `--check`。

回滚本任务时，应成组恢复三个精确 dev 依赖和锁文件、两份配置、
`tool/generate_branding.dart`、CI/平台门禁、品牌源、测试、文档及全部白名单原生产物。不得只删除
源图而留下旧品牌平台文件，也不得触碰包名、环境配置、签名或其他用户资源。

完全移除此能力时，先决定项目仍需保留哪一套已经验证的手工原生图标/启动资源，再删除生成器
与输入；随后从 CI 移除专项 `--check`，调整平台门禁，重新构建 Android/iOS。移除生成能力不
等于移除应用必需的 AppIcon/LaunchScreen。
