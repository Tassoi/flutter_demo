# ADR 0007：主题与类型安全资源

- 状态：Accepted
- 决策日期：2026-08-09
- 适用范围：第一阶段 Material 3 亮暗主题、布局 token、本地静态资源与普通 SVG，以及第二阶段手机设计单位接入

## 背景与范围

模板需要让新增页面共享颜色、排版、间距和圆角，同时避免 Feature 到处复制十六进制颜色、字号和资源路径。直接调用 `SvgPicture.asset('...')` 还会让 flutter_svg 类型、语义规则和路径维护扩散到业务代码，资源移动后难以一次修正。

本决策提供唯一 `AppTheme`、一套布局 token 和一个类型安全的本地资源目录。第二阶段 Task 4
只把现有主题、组件和页面接入已经由 ADR 0014 建立的项目 `du/dsp` 边界，不改变资源 catalog
职责。它不实现国际化、SVG 转字体、品牌图标/启动资源生成、远程图片、资源下载缓存或通用
代码生成平台。

## 主题决策

### Material 3 与主题模式

正常应用使用 `AppTheme.light(context)` 和 `AppTheme.dark(context)` 两个唯一入口；传入的 context
必须位于 `AppScreenAdaptation` 下方，使主题圆角、边框、留白、图标、按钮尺寸和排版共享同一
宽度比例。两者仍是无 I/O、无缓存、无全局可变状态的本地组装函数，不读取环境、存储或网络。

安全启动失败页不能把适配插件初始化当作前置条件，因此使用明确命名的 `fallbackLight()` /
`fallbackDark()`，仅把参考稿值按 1:1 解释。正常页面不得使用 fallback 绕过设计单位。Task 11
的 `appThemeModeProvider` 默认使用 `ThemeMode.system`，`TemplateApp` 只监听该应用级状态。
Controller 不访问存储；后续真实偏好必须通过项目存储接口和明确失败策略接入。

Feature 必须通过 `Theme.of(context).colorScheme`、`textTheme` 和组件主题读取语义值，不导入或复制私有色板。模板色板同时使用青绿色 primary、暖红色 secondary 和蓝色 tertiary，并为亮暗模式显式提供表面、轮廓、错误及反色角色，避免界面退化为单一色相。关键前景/背景组合的测试要求对比度高于 4.5:1；这不是对所有任意叠色的自动保证，新增颜色组合仍需针对实际 Widget 验证。

### 排版

`AppTypography` 定义完整 Material 3 文本刻度，集中固定参考稿字号、行高、字重和零 letter
spacing。正常主题先用 `dsp` 应用“当前逻辑宽度 / 375”的设计比例，随后 Flutter 再应用当前
系统 `TextScaler`；两次换算职责不同，不能预乘、抵消或全局固定文字倍率。启动失败 fallback
只跳过设计宽度换算，仍保留 Flutter 系统文字缩放。

模板正文排版当前使用 Android/iOS 系统字体和 Flutter fallback，不捆绑来源、许可证和字符覆盖尚未确认的文本字体。第二阶段生成的 `TemplateIcons` 是仅含获授权单色语义 glyph 的图标 OTF，遵守独立清单、许可证和确定性生成规则，不改变 `AppTypography` 或正文 fallback。未来加入文本字体时仍必须取得可分发源文件和许可证，在 `pubspec.yaml` 明确登记 family/weight，并更新 `AppTypography`、许可证文档和亮暗/大字体测试。仅为了展示“字体能力”放入任意第三方文本字体不符合本模板的安全默认值。

### 间距与圆角

`AppSpacing` 提供 4、8、12、16、24、32、48、64 的单调参考稿刻度；`AppRadii` 只提供 4 和
8 的参考稿半径。它们是设计源值，不是普通调用方可直接使用的最终逻辑像素。正常主题、组件
和页面必须在使用点通过 `context.du(...)` 解析；卡片、输入框和弹窗因此在参考宽度保持 8
逻辑像素圆角，并随其他手机宽度统一换算。

token 位于 `lib/shared/design/app_layout_tokens.dart`，使 `app/` 的主题和跨 Feature 组件依赖
同一稳定来源，同时避免 `shared/` 反向依赖 composition root。SafeArea、状态栏、系统手势区、
键盘 Insets 和其他平台值已经是实际逻辑像素，禁止交给 `du`。可点击控件使用
`AppDimensions.minimumTouchTarget(context)`，取 `du(48)` 与原始 48 逻辑像素的较大值，
避免窄屏设计比例把无障碍触控下限缩小。

业务 UI 应优先组合 token，但它们不是禁止所有局部数值的万能规则。固定画布比例、协议尺寸或确有语义的局部值可以留在所属 Widget，并需要说明为何不属于全局设计刻度。

## 类型安全资源决策

### Catalog 与插件边界

`AppAssets` 是随应用打包资源的命名目录；真实路径是 `AppSvgAsset` 的私有状态，调用方无法从任意字符串创建资源句柄。`AppSvgAsset.image()` 返回 Flutter `Widget`，业务代码不导入 flutter_svg，也不接触 `SvgPicture`。生产代码中 flutter_svg 只允许出现在 `lib/shared/assets/app_assets.dart` 这一渲染边界，对应测试可以导入插件类型检查适配结果。

当前目录只登记一个实际使用的无品牌 `templateLayers` SVG。没有真实消费者的 raster、动画和字体 wrapper 暂不创建，避免把资源目录扩展成万能抽象；对应资源出现后再增加职责窄、可测试的类型。

### SVG 约束

普通 SVG 必须随应用打包，不允许网络 URL、运行时路径或外部引用。`AppSvgAsset.image()` 强制调用方提供有限正数宽高，避免解析前后布局跳动；可选颜色通过 `srcIn` 过滤器支持主题化单色图形。语义标签为 `null` 明确表示装饰并从语义树排除，非空标签不得只有空白。

源 SVG 必须具有稳定 `viewBox`，不得包含脚本、远程资源、嵌入凭据、用户数据或未确认可分发的字体/图片。`assets/svg/template_layers.svg` 只包含本地路径与透明度，是展示普通 SVG 管线的中立示例，不是 Logo、应用图标或品牌设计。

flutter_svg 负责 AssetBundle 读取、解析和内部缓存；项目 wrapper 不持有 listener，也没有需要释放的生命周期。资源缺失、未登记或解析失败属于构建输入缺陷，Widget 测试应直接失败，而不是在生产中静默替换成可能掩盖发布错误的占位图。

### 新增资源流程

当前只有一个 SVG，手写 catalog 比引入 build_runner 或独立资源生成器更简单且更易审查。新增静态资源必须完成以下步骤：

1. 核对来源、许可证、隐私与格式安全，并把源文件放入对应 `assets/` 子目录。
2. 在 `pubspec.yaml` 逐项登记文件，避免目录级声明意外打包临时或敏感文件。
3. 在 `AppAssets` 增加命名且类型明确的私有路径入口，业务代码不得手写路径。
4. 增加能够从 AssetBundle 实际加载资源的 Widget 测试，并覆盖尺寸、语义和必要的主题行为。
5. 运行格式、分析、全量测试与平台构建，检查最终包中没有陈旧或意外资源。

只有资源数量增长到人工 catalog 已产生可证明的漂移问题时，才可以在资源边界内增加专用、可复现的生成步骤和陈旧产物检查；不得借此建设通用代码生成或脚手架 CLI。

## 测试与验证

主题测试直接验证：

1. 亮暗主题均启用 Material 3，brightness、surface 与主题模式正确。
2. primary、secondary、tertiary、surface、error 及消息反馈实际使用的四组 container/on-container 语义色组合达到 4.5:1。
3. 完整 TextTheme 非空且 letter spacing 全部为零。
4. 卡片、弹窗、输入框、按钮、图标与排版在六档宽度按同一比例换算，原始 token 保持固定单调刻度。
5. 启动失败 fallback 保持 1:1 且不依赖适配根，正常主题缺少适配 context 时不能静默降级。

资源测试从真实 AssetBundle 加载 catalog 中的 SVG，验证稳定宽高、可访问语义、装饰排除和
非法参数。首页、详情和安全路由错误页在 `320x568`、`360x800`、`375x812`、`390x844`、
`430x932`、`800x360` 分别覆盖正常和 200% 系统文字，并断言关键操作矩形与语义。参考尺寸
的首页和示例详情另有 Flutter 原生 Golden；Golden 测试主题显式使用 Ahem 固定字形与度量，并为
Windows/Linux 字形边缘栅格化维护分离的零容差基线。生产主题仍使用平台系统字体。启动失败页
不加载资源或适配插件，避免次生缺陷破坏最小 fallback。

常规验证命令：

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build apk --debug --flavor dev \
  --dart-define-from-file=config/dev.example.json
```

## 已知限制、迁移与回滚

当前没有动态取色、高对比主题、运行时主题编辑器或生产自定义字体。Golden 固定的是 Flutter
测试字体和参考视口，不代表 Android/iOS 系统字体像素一致，也不能替代真机大字体、TalkBack、
VoiceOver 或 GPU SVG 验证。颜色对比测试只覆盖明确的语义对，复杂叠加、disabled opacity 和
未来组件仍需在对应任务中验证；当前非 macOS 主机也不能提供 iOS 构建证据。

更改公开 spacing/radius 数值、色彩角色、文字刻度或资源常量名称可能影响所有页面，应作为设计迁移处理并运行全量 Widget 测试。移动或重命名资源必须在同一变更中更新 `pubspec.yaml`、catalog 和测试；不得保留两个路径作为无期限兼容层。

Task 9 的共享组件已经成为布局 token 的第二个消费者。回滚本决策前必须先回滚这些组件，或者保留等价的 `shared/design` token 契约；只要 `shared/widgets` 仍然存在，就不得把 token 移回 `app/theme` 并制造反向依赖。完整回滚本决策时，移除 `lib/app/theme/`、`lib/shared/design/`、`lib/shared/assets/`、示例 SVG、pubspec 资源登记、相关测试和本 ADR，并把正常/失败壳层恢复为 Task 7 状态。不得移除已锁定的 flutter_svg 依赖决策、回退 Task 1-7、覆盖用户的 `AGENTS.md` 或修改 Goal 原文。
