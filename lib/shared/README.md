# shared

`shared/` 只保存第一阶段明确要求，或者已经确认被多个 Feature 复用的无业务设计值、组件、资源入口和工具，不作为临时代码目录。

它不得依赖 `app/` 或具体 Feature。除脚手架基线明确要求的内容外，只有出现真实的跨 Feature 消费者后，通用实现才应移动到这里。

- `design/` 保存应用主题与共享组件共同消费的参考稿间距和圆角源值。它自身不读取视口、SafeArea、文字缩放或平台状态；正常调用方必须在使用点通过 `context.du(...)` 解析，只有启动失败 fallback 明确保持 1:1。`AppDimensions.minimumTouchTarget` 在设计比例之外保留 48 逻辑像素的触控下限。
- `layout/` 保存项目自有的手机布局边界。`AppScreenAdaptation` 在应用根节点按 `375 x 812` 初始化底层适配器；调用方只使用 `context.du(...)` 和 `context.dsp(...)`，不得直接导入 `flutter_screenutil`。宽度、高度、间距、圆角和图标统一按宽度比例换算；系统 Insets 不换算，系统文字缩放由 Flutter 在 `dsp` 之后应用一次。`AppSafeScrollableScaffold` 为普通页面消费一次真实 SafeArea 和键盘 Insets，并在短屏提供唯一主滚动；`AppFixedVisualCanvas` 只允许明确视觉画布选择 `contain` 留白或 `cover` 裁切，不用于表单、列表或普通页面。
- `assets/` 是类型安全资源边界。`AppAssets` 隐藏普通 SVG 的真实路径，`AppSvgAsset` 把 flutter_svg 限制在唯一运行时渲染文件并只向调用方返回 Flutter `Widget`。单色语义图标由 `assets/icons/` 的 SVG 清单生成到 `generated/template_icons.g.dart`，调用方只使用 `TemplateIcons`；生成工具包不得进入 `lib/`。普通 SVG 与图标字体保持独立，不为尚不存在的 raster 或动画消费者预建通用 wrapper。
- `widgets/` 提供加载、空、错误状态、确认弹窗和短时消息反馈。它们通过项目 `du/dsp` 和当前主题适配设计值，在短屏、横屏和大字体下保持可滚动；浮动消息会同时考虑局部 MediaQuery 与所属 FlutterView 的原始安全区/键盘 Insets。组件只呈现调用方给出的安全文案并转发操作，不访问网络、存储、日志、路由状态或具体业务模型，也不直接导入底层适配插件。

主题、token 与普通资源规则见 `docs/architecture/0007-theme-and-type-safe-assets.md`；图标字体的添加、退休、检查和删除流程见 `docs/svg-icon-font.md`；基础状态和反馈组件契约见 `docs/architecture/0008-basic-state-and-feedback-widgets.md`。
