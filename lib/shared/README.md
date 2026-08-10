# shared

`shared/` 只保存第一阶段明确要求，或者已经确认被多个 Feature 复用的无业务设计值、组件、资源入口和工具，不作为临时代码目录。

它不得依赖 `app/` 或具体 Feature。除脚手架基线明确要求的内容外，只有出现真实的跨 Feature 消费者后，通用实现才应移动到这里。

- `design/` 保存应用主题与共享组件共同消费的固定间距和圆角 token。它不读取视口、SafeArea、文字缩放或平台状态。
- `assets/` 是类型安全资源边界。`AppAssets` 隐藏真实路径，`AppSvgAsset` 把 flutter_svg 限制在唯一渲染文件并只向调用方返回 Flutter `Widget`。当前只登记应用壳层实际使用的无品牌 SVG，不为尚不存在的 raster、字体或动画消费者预建通用 wrapper。
- `widgets/` 提供加载、空、错误状态、确认弹窗和短时消息反馈。它们只呈现调用方给出的安全文案并转发操作，不访问网络、存储、日志、路由状态或具体业务模型。

主题、token 与资源规则见 `docs/architecture/0007-theme-and-type-safe-assets.md`；基础状态和反馈组件契约见 `docs/architecture/0008-basic-state-and-feedback-widgets.md`。
