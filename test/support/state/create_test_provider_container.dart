import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 创建由当前测试自动释放的 Riverpod 容器。
///
/// [overrides] 用于替换 Repository、数据源或其他外部依赖；调用方仍应通过项目接口提供
/// 替身，不能把插件对象直接注入 Feature。容器会注册到 `addTearDown`，即使断言提前失败
/// 也会释放 provider、监听器和 `ref.onDispose` 资源，避免测试顺序污染。
ProviderContainer createTestProviderContainer({
  List<Override> overrides = const <Override>[],
}) {
  final container = ProviderContainer(overrides: overrides);
  addTearDown(container.dispose);
  return container;
}
