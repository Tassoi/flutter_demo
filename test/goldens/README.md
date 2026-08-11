# 手机页面 Golden 基线

本目录保存关键手机页面的 Flutter 原生 Golden。基线固定在 `375x812` 逻辑尺寸、顶部
`44` 与底部 `34` 的原始安全区、1.0 设备像素比和正常系统文字倍率；它用于发现主题、
间距、圆角、图标、页面层级和资源渲染的意外变化。

Golden 测试只在测试主题中显式应用 Flutter SDK 随 `flutter test` 提供的 `Ahem` 字体，
从而避免 Windows、Linux 与 macOS 系统 fallback 字体的字形和度量差异。生产代码没有
固定字体，也没有禁用 `TextScaler`。真实字体放大、六档手机尺寸、横屏、安全区、关键
矩形、滚动可达性和语义由布局矩阵测试负责，因此不能用更新 Golden 代替这些断言。

校验基线：

```bash
flutter test test/goldens/mobile_ui_golden_test.dart
```

仅在已经人工核对视觉变更、布局矩阵通过并确认 Flutter SDK 版本仍符合 `pubspec.yaml`
约束后更新：

```bash
flutter test --update-goldens test/goldens/mobile_ui_golden_test.dart
```

Flutter 引擎升级可能改变 SVG、Material 图标或像素抗锯齿结果。升级时应在 CI 使用的
Ubuntu runner 上再次校验，并逐张审查差异；不得因平台差异直接批量接受新基线。
