import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 应用级 Riverpod 容器的唯一生命周期边界。
///
/// [AppStateScope] 在挂载时创建一个 [ProviderContainer]，使 `app/` 和 Feature presentation
/// 中声明的 provider 可以通过 `ref.watch`/`ref.read` 使用；根 Widget 被替换或销毁时，
/// Riverpod 会同步释放容器，并触发其中每个 provider 的 `ref.onDispose` 清理。
///
/// [overrides] 只供应用组装层绑定项目接口实现，以及测试替换 Repository 或数据源。Feature
/// 不得创建新的全局作用域，也不得把插件对象作为 override 向业务层泄漏。本类型不持有全局
/// 单例容器、不提供 service locator，也不安装可能记录状态值的通用 observer。
final class AppStateScope extends StatelessWidget {
  /// 创建包含 [child] 的应用状态作用域。
  ///
  /// [overrides] 会被复制为不可变快照，调用方后续修改原列表不会改变已挂载容器。需要调整
  /// override 时应重建本 Widget；Riverpod 负责更新对应 provider，调用方不得直接操作内部
  /// [ProviderContainer] 的生命周期。
  AppStateScope({
    required this.child,
    List<Override> overrides = const <Override>[],
    super.key,
  }) : overrides = List<Override>.unmodifiable(overrides);

  /// 允许读取应用状态的 Widget 子树。
  final Widget child;

  /// 应用组装层提供的依赖替换快照。
  ///
  /// 该列表包含 Riverpod 类型，因此只能在 `app/` composition root 或测试中构造；Feature
  /// domain/data 接口必须保持普通 Dart 类型。
  final List<Override> overrides;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(overrides: overrides, child: child);
  }
}
