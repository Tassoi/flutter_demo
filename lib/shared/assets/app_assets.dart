import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// 随应用打包的类型安全资源目录。
///
/// 调用方只引用这里的命名资源，不手写文件路径。[AppAssets] 当前只登记已有消费者的
/// 普通 SVG；图片、字体或其他资源应在真实需求出现时增加对应的窄类型，而不是预先建立
/// 通用资源框架。资源路径同时必须在 `pubspec.yaml` 中逐项登记，由 Widget 测试验证可加载。
abstract final class AppAssets {
  /// 用于模板壳层的无品牌叠层示例图形。
  static const AppSvgAsset templateLayers = AppSvgAsset._(
    'assets/svg/template_layers.svg',
  );
}

/// 一个只能从 [AppAssets] 取得的本地 SVG 资源句柄。
///
/// 该类型把 flutter_svg 和真实资源路径限制在 shared 资源边界，对 Feature 只返回 Flutter
/// [Widget]。资源从应用 AssetBundle 加载，不支持网络 URL、运行时路径或外部 SVG，因而
/// 不引入下载、缓存失效和远端内容安全问题。底层解析缓存由 flutter_svg 管理，本类型不
/// 持有 listener 或需要释放的生命周期资源。
final class AppSvgAsset {
  const AppSvgAsset._(this._assetName);

  final String _assetName;

  /// 创建具有稳定 [width] 和 [height] 的 SVG Widget。
  ///
  /// 两个尺寸必须为有限正数，避免资源解析前后改变布局。[color] 非空时使用 `srcIn`
  /// 统一着色，适合跟随主题的单色图形；省略时保留源文件颜色。[semanticsLabel] 为 `null`
  /// 表示纯装饰并从语义树排除，非空时必须包含可读字符。无效参数在访问 AssetBundle 前
  /// 抛固定 [ArgumentError]，不会产生平台 I/O 或部分渲染状态。
  Widget image({
    Key? key,
    required double width,
    required double height,
    Color? color,
    BoxFit fit = BoxFit.contain,
    AlignmentGeometry alignment = Alignment.center,
    String? semanticsLabel,
  }) {
    if (!width.isFinite || width <= 0 || !height.isFinite || height <= 0) {
      throw ArgumentError('SVG dimensions must be finite and positive.');
    }
    if (semanticsLabel != null && semanticsLabel.trim().isEmpty) {
      throw ArgumentError('SVG semantics label must contain readable text.');
    }

    return SvgPicture.asset(
      _assetName,
      key: key,
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      colorFilter:
          color == null ? null : ColorFilter.mode(color, BlendMode.srcIn),
      semanticsLabel: semanticsLabel,
      excludeFromSemantics: semanticsLabel == null,
    );
  }
}
