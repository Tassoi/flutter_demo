# 移动端屏幕适配指南

本能力只服务 Android/iOS 手机。项目使用唯一 `375 x 812` 参考设计尺寸，把普通几何值按当前
逻辑宽度等比换算；它不是平板、桌面或通用断点框架。系统安全区、系统手势区、键盘 Insets 和
无障碍文字缩放始终使用 Flutter 提供的真实值，不属于设计稿缩放。

## 设计交付契约

设计与开发开始前应确认一份可版本化的交付说明，至少包含：

1. 唯一参考画布，默认是 `375 x 812` 逻辑像素。标注必须使用逻辑设计单位，不使用某台设备的
   物理像素、截图像素或 DPR 反推布局。
2. 页面内容是否位于系统安全区域内。状态栏、刘海、Home Indicator、系统手势区和键盘高度不
   写进普通间距标注，也不作为画布上下留白重复交付。
3. 每个容器的固定、内容自适应和弹性规则。短屏必须明确滚动范围与主要操作顺序；长屏只标记
   哪一段留白可以扩展，不能要求整页按高度拉伸。
4. 文案的最大行数、允许换行位置、截断策略，以及英语、中文和 200% 系统文字下的代表长文案。
   设计稿不得以关闭系统字体缩放作为成立条件。
5. 触控目标、焦点顺序和语义名称。视觉图标可以按设计比例缩放，但可点击区域最终不得小于
   `48 x 48` Flutter 逻辑像素。
6. 位图的导出倍率、裁切方式和 `BoxFit`；普通 SVG 与图标字体继续走项目资源入口。海报等固定
   画布必须明确使用 `contain` 留白还是 `cover` 裁切，并给出关键内容安全区。
7. 横屏的最低行为要求。当前默认只要求无布局异常、可滚动且主要操作可用，不额外维护一套横屏
   视觉稿。

修改参考尺寸时只能调整
`lib/shared/layout/app_screen_adaptation.dart` 中的 `appDesignSize`，并在同一变更中更新设计
交付说明、矩形断言和 Golden。不得按页面、环境或设备定义不同基准。

## 文件与所有权

```text
lib/app/template_app.dart
lib/shared/layout/
├── app_screen_adaptation.dart
├── app_safe_scrollable_scaffold.dart
└── app_fixed_visual_canvas.dart
lib/shared/design/app_layout_tokens.dart
test/shared/layout/
test/app/mobile_ui_layout_matrix_test.dart
test/shared/widgets/app_widget_layout_matrix_test.dart
test/goldens/mobile_ui_golden_test.dart
```

`AppScreenAdaptation` 是 `flutter_screenutil` 的唯一运行时适配边界，应用根节点先建立设计单位，
再创建主题和 `MaterialApp`。Feature、主题和共享组件只能使用项目公开的 `context.du(...)` 与
`context.dsp(...)`；架构门禁会拒绝其他运行时代码直接导入底层插件。

`AppSafeScrollableScaffold` 拥有普通页面唯一的主滚动、`Scaffold`、SafeArea 和键盘避让。
调用方传入非滚动正文及可选底部操作，不再外包 `SafeArea`，也不手工追加 `viewInsets`。
`AppFixedVisualCanvas` 只用于海报、活动视觉等有界固定画布，不得包裹表单、列表、导航或普通
详情页。

## 启用与使用

完整模板已经启用该能力。把相关边界移植到其他项目时，应按以下顺序组装：

1. 固定并解析 `flutter_screenutil 5.9.3`，只允许
   `lib/shared/layout/app_screen_adaptation.dart` 导入它。
2. 在应用唯一根节点挂载 `AppScreenAdaptation`，并在其 `builder` context 中创建亮暗主题和
   `MaterialApp`。启动失败 fallback 保持 1:1，不依赖适配插件初始化。
3. 让主题、共享组件和 Feature 在使用点解析设计源值；不要把已经换算的逻辑像素缓存为全局
   常量，也不要散布 `.w`、`.h` 或 `.sp`。
4. 普通几何值统一使用宽度比例：

```dart
final padding = EdgeInsets.all(context.du(16));
final iconSize = context.du(24);
final titleStyle = TextStyle(fontSize: context.dsp(20));
```

5. 系统值直接使用，不传给 `du`：

```dart
final viewInsets = MediaQuery.viewInsetsOf(context);
final systemPadding = MediaQuery.paddingOf(context);
```

`dsp` 只应用设计宽度比例。Flutter 随后通过当前 `TextScaler` 再应用用户文字设置；不得覆盖
`MediaQuery` 或使用 `TextScaler.noScaling` 追求截图一致。高度、纵向间距、圆角和图标同样走
`du`，项目有意不提供独立高度比例。

## 运行、测试与平台验证

先使用真实环境对齐的 flavor 运行应用：

```bash
flutter pub get --enforce-lockfile
flutter run --flavor dev --dart-define-from-file=config/dev.example.json
```

适配变更至少执行：

```bash
flutter test test/shared/layout
flutter test test/app/mobile_ui_layout_matrix_test.dart
flutter test test/shared/widgets/app_widget_layout_matrix_test.dart
flutter test test/goldens/mobile_ui_golden_test.dart
dart tool/ci/check_architecture.dart
flutter analyze --fatal-infos --fatal-warnings
```

布局矩阵必须覆盖 `320x568`、`360x800`、`375x812`、`390x844`、`430x932` 和
`800x360`，每个核心页面同时覆盖正常与 200% 系统文字。表单还要测试动态键盘 Insets，代表
设备要测试四边安全区、滚动到达、主要操作、语义和至少 48 逻辑像素触控目标。Golden 只比较
参考尺寸像素，不能替代矩形、滚动和语义断言。

涉及根初始化、插件版本或页面布局时，还要实际构建 Android：

```bash
flutter build apk --debug --flavor dev \
  --dart-define-from-file=config/dev.example.json
```

iOS 必须在 macOS 使用当前固定的 Xcode/CocoaPods 环境执行对应 scheme 的无签名构建，并在
模拟器或真机核对旋转、Dynamic Type、刘海/Home Indicator 和键盘。其他平台的静态检查不能
替代这项证据。

## 常见故障

| 现象 | 原因与处理 |
| --- | --- |
| `AppScreenAdaptation must be mounted` | 在根适配 builder 之外读取了 `du/dsp`；移动主题或 Widget 创建时机，不要增加全局 fallback |
| 参考宽度正确，其他宽度比例错误 | 页面混入了裸设计值、独立高度比例或插件 `.w/.h/.sp`；搜索调用点并恢复项目 API |
| 键盘出现后底部留白翻倍 | `Scaffold` 自动 resize、外层 `SafeArea` 或手写 `viewInsets` 与安全滚动壳层重复消费；只保留一个所有者 |
| 200% 文字溢出 | 页面限制了高度、禁止换行或关闭了 `TextScaler`；恢复可增长内容和主滚动，并补长文案测试 |
| 横屏或短屏操作不可达 | 普通页面没有唯一主滚动，或在滚动内容中使用了 `Expanded/Spacer`；按壳层契约重组内容 |
| Golden 变化但矩形测试通过 | 先核对 SDK、测试字体、SVG 和抗锯齿；只有确认视觉变更后才更新基线 |

## 升级或替换底层适配器

`flutter_screenutil` 只是私有实现。升级或替换时应保留 `AppScreenAdaptation`、`appDesignSize`、
`context.du/dsp` 和调用方语义：

1. 记录当前依赖/锁文件、六档矩形、Golden 和 Android 构建基线；阅读新实现的 SDK 下限、
   许可证、指标更新、文字缩放和多 View 行为。
2. 只替换 `app_screen_adaptation.dart` 内部。新实现仍必须按“当前逻辑宽度 / 参考宽度”计算
   唯一有限正比例，并在 View 尺寸变化时重建；不得把插件类型泄漏到 Feature。
3. 先运行适配器单元测试，再执行六档双语布局、Golden、架构门禁、全量测试和 Android/iOS
   构建。旋转后比例、测试隔离和系统 Insets 必须重新验证。
4. 最后更新依赖与锁文件。若验证失败，成组恢复 adapter、依赖/锁文件、测试和文档，而不是
   在调用方临时混用两套单位。

## 固定逻辑像素回退与完整删除

不再需要设计稿缩放时，优先先回退为 1:1 适配器，再决定是否删除公开 API。这样可以把行为
迁移和大范围调用点重写拆成可验证步骤：

1. 在 `app_screen_adaptation.dart` 内保留同名根 Widget 与 `du/dsp`，把项目作用域比例固定为
   `1.0`，移除底层插件读取；系统文字缩放仍交给 Flutter。更新测试，证明所有设计输入按固定
   Flutter 逻辑像素返回。
2. 重跑六档矩阵。1:1 回退不保证窄屏自动成立，必须保留短屏滚动、真实 SafeArea/键盘 Insets
   和最小触控目标；需要的页面使用约束、换行和滚动解决，而不是再次引入隐式缩放。
3. 移除 `flutter_screenutil`、重新解析锁文件，并从架构门禁删除该插件的单 adapter 规则。
   `AppSafeScrollableScaffold` 与 `AppFixedVisualCanvas` 不依赖该插件，可以按产品需要继续保留。
4. 若还要完整删除设计单位，再逐个把主题、共享组件、路由页和 Feature 的 `du/dsp` 调用替换为
   明确的固定逻辑值或约束布局；全部调用方迁移和测试通过后，才删除根适配器与包装节点。
5. 执行格式、严格分析、全量测试、架构/平台门禁及 Android/iOS 构建。确认第一阶段路由、
   网络、存储、错误、日志和可删除示例 Feature 没有依赖适配器内部实现。

不要先删除依赖再批量把无法编译的调用点改成任意数字。回滚整个适配能力时应成组恢复根初始化、
公开单位、主题、组件、页面、依赖/锁文件、矩阵和 Golden；只恢复其中一部分会留下不可比较的
混合单位。
