// 此文件由 `dart run tool/generate_icon_font.dart` 基于 SVG 清单生成。
// 请勿手工修改；更新 `assets/icons/` 后重新运行生成命令。

import 'package:flutter/widgets.dart';

/// 应用内单色语义图标的类型安全入口。
///
/// 字形来自 `assets/icons/svg/`，稳定 codepoint 由清单维护。此类只暴露活动
/// 图标；退休槽仍保留在字体中，避免后续图标映射发生位移。
abstract final class TemplateIcons {
  /// Flutter 资源注册使用的固定字体 family。
  static const String fontFamily = 'TemplateIcons';

  /// 表示语言选择或本地化设置的图标。
  static const IconData language = IconData(0xe000, fontFamily: fontFamily);

  /// 表示操作成功或选项已确认的图标。
  static const IconData check = IconData(0xe001, fontFamily: fontFamily);
}
