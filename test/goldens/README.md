# 手机页面 Golden 基线

本目录保存关键手机页面的 Flutter 原生 Golden。基线固定在 `375x812` 逻辑尺寸、顶部
`44` 与底部 `34` 的原始安全区、1.0 设备像素比和正常系统文字倍率；它用于发现主题、
间距、圆角、图标、页面层级和资源渲染的意外变化。

Golden 测试只在测试主题中显式应用 Flutter SDK 随 `flutter test` 提供的 `Ahem` 字体，
从而避免系统 fallback 字体改变字形和度量。Flutter tester 在 Windows 与 Linux 上仍会让
Ahem、Material 图标和项目 OTF 的边缘栅格化产生一像素差异，因此两个宿主分别使用
`baselines/windows/` 与 `baselines/linux/` 中经过审查的精确 PNG；比较保持零容差，不使用
百分比阈值。当前没有独立基线的宿主会跳过两项像素测试，不能静默复用其他平台截图。

生产代码没有固定字体，也没有禁用 `TextScaler`。真实字体放大、六档手机尺寸、横屏、安全区、
关键矩形、滚动可达性和语义由布局矩阵测试负责，因此不能用更新 Golden 代替这些断言。

校验基线：

```bash
flutter test test/goldens/mobile_ui_golden_test.dart
```

仅在 Windows 或 Linux 上已经人工核对视觉变更、布局矩阵通过并确认 Flutter SDK 版本仍符合
`pubspec.yaml` 约束后更新当前宿主的目录：

```bash
flutter test --update-goldens test/goldens/mobile_ui_golden_test.dart
```

Flutter 引擎升级可能改变 SVG、Material 图标或像素抗锯齿结果。升级时应在 CI 使用的 Ubuntu
runner 上再次校验 Linux 基线，并在 Windows 上复核对应目录，逐张审查差异。新增 macOS 等宿主
时，先在固定 SDK/runner 上生成独立目录并完成审查，再把平台加入测试选择；不得批量接受截图、
复用其他宿主基线或增加模糊容差。
