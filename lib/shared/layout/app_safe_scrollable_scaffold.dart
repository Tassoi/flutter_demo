import 'package:flutter/material.dart';

/// 为普通手机页面提供安全区域、键盘避让和单一主滚动容器。
///
/// 本组件拥有自己的 [Scaffold]，并固定使用 `resizeToAvoidBottomInset: false`，随后按以下顺序
/// 处理平台空间：先由 [SafeArea] 消费状态栏、刘海、横屏侧边和底部手势区，再直接使用
/// [MediaQueryData.viewInsets] 缩小滚动视口。两类系统值都是 Flutter 已换算好的逻辑像素，
/// 不会经过项目 `du` 比例，因此不会在宽屏设备上被二次放大。
///
/// [content] 与可选 [bottomAction] 必须是非滚动内容；页面唯一的纵向主滚动由本组件持有。
/// 短屏、大字体或键盘令内容超过可见高度时，二者会作为一个整体滚动。内容较短时，
/// [bottomAction] 位于可见区域底部；内容增长时，它自然排在正文之后并保持可滚动到达。
/// 调用方不得在这两个直接插槽中放入 `ListView`、`CustomScrollView`、`Expanded` 或
/// `Spacer`，需要长列表或复杂 Sliver 的页面应建立经过专项测试的页面实现。
///
/// [contentPadding] 只表达设计稿留白。调用方应在已初始化的适配上下文中用 `du` 构造它，
/// 不得把 SafeArea、状态栏、手势区或键盘 Insets 填入该参数，也不得在外层再次包裹
/// `SafeArea` 或手工追加 `viewInsets`。本组件不定义页面业务语义、表单校验、焦点顺序、
/// AppBar、底部导航或提交行为。
final class AppSafeScrollableScaffold extends StatelessWidget {
  /// 创建一个消费一次系统 Insets 的普通手机页面壳层。
  const AppSafeScrollableScaffold({
    required this.content,
    this.bottomAction,
    this.contentPadding = EdgeInsets.zero,
    this.scrollController,
    this.keyboardDismissBehavior = ScrollViewKeyboardDismissBehavior.onDrag,
    this.backgroundColor,
    super.key,
  });

  /// 页面主要内容。
  ///
  /// 内容本身应为非滚动 Widget，并允许在纵向约束增长时按自身固有高度布局。
  final Widget content;

  /// 可选的页面底部主要操作。
  ///
  /// 本组件不会在正文与操作之间隐式插入设计间距；调用方需要的间距应包含在
  /// [contentPadding]、正文末尾或操作自身外层中。
  final Widget? bottomAction;

  /// 正文与安全可见视口之间的设计稿留白。
  ///
  /// 该值必须在解析文字方向后保持有限且非负。系统 Insets 不属于设计稿留白，禁止传入。
  final EdgeInsetsGeometry contentPadding;

  /// 可选的页面主滚动控制器。
  ///
  /// 控制器生命周期仍由调用方拥有；本组件不会释放外部传入的实例。
  final ScrollController? scrollController;

  /// 用户拖动主滚动视口时采用的键盘收起策略。
  final ScrollViewKeyboardDismissBehavior keyboardDismissBehavior;

  /// 可选 Scaffold 背景色；省略时使用当前主题的默认背景。
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final resolvedContentPadding = contentPadding.resolve(
      Directionality.of(context),
    );
    if (!_isFiniteNonNegative(resolvedContentPadding)) {
      throw ArgumentError.value(
        contentPadding,
        'contentPadding',
        'Content padding must resolve to finite non-negative values.',
      );
    }

    // Scaffold 不自动缩小 body，避免“父级 resize + 子级 viewInsets”导致键盘高度消费两次。
    // 这里捕获的 Insets 来自当前 MediaQuery，并作为平台逻辑像素直接作用于滚动视口。
    final systemViewInsets = MediaQuery.viewInsetsOf(context);

    return Scaffold(
      backgroundColor: backgroundColor,
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        maintainBottomViewPadding: false,
        child: Padding(
          padding: systemViewInsets,
          child: CustomScrollView(
            controller: scrollController,
            primary: scrollController == null,
            keyboardDismissBehavior: keyboardDismissBehavior,
            slivers: <Widget>[
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: resolvedContentPadding,
                  child: _SafeScrollablePageContent(
                    content: content,
                    bottomAction: bottomAction,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _SafeScrollablePageContent extends StatelessWidget {
  const _SafeScrollablePageContent({
    required this.content,
    required this.bottomAction,
  });

  final Widget content;
  final Widget? bottomAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment:
          bottomAction == null
              ? MainAxisAlignment.start
              : MainAxisAlignment.spaceBetween,
      children: <Widget>[content, if (bottomAction != null) bottomAction!],
    );
  }
}

bool _isFiniteNonNegative(EdgeInsets value) {
  return value.left.isFinite &&
      value.top.isFinite &&
      value.right.isFinite &&
      value.bottom.isFinite &&
      value.left >= 0 &&
      value.top >= 0 &&
      value.right >= 0 &&
      value.bottom >= 0;
}
