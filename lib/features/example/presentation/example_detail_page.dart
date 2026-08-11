import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_template/core/error/app_error.dart';
import 'package:flutter_template/features/example/domain/example_item.dart';
import 'package:flutter_template/features/example/presentation/example_detail_controller.dart';
import 'package:flutter_template/features/example/presentation/example_detail_copy.dart';
import 'package:flutter_template/shared/design/app_layout_tokens.dart';
import 'package:flutter_template/shared/layout/app_screen_adaptation.dart';
import 'package:flutter_template/shared/widgets/app_state_views.dart';

/// 展示一个已经由应用路由层验证 ID 的示例详情页。
///
/// 页面读取 [exampleDetailProvider] 并明确呈现 loading、data、empty 与 error。它不创建
/// Repository、不读取 Router 或插件，也不格式化底层异常。[onBack] 由 `app/` 传入，
/// 因此删除 Feature 或替换路由方案不会让 go_router 类型进入 presentation。
///
/// 页面拥有自身 Scaffold 与 SafeArea。状态正文和成功内容都可在短屏或放大文字下纵向滚动；
/// 标题、ID、间距和图标从应用主题或项目 `du/dsp` 取得，不直接依赖底层适配插件。
final class ExampleDetailPage extends ConsumerWidget {
  /// 创建 [itemId] 对应的详情页。
  ///
  /// [itemId] 必须为正整数，否则在构建状态前抛出固定 [ArgumentError]。[onBack] 只在用户
  /// 点击顶部返回或空状态返回操作时调用。页面不猜测导航栈，也不限制回调的重复执行；
  /// 是否接受连续导航命令由应用路由层决定。
  ExampleDetailPage({
    required this.itemId,
    required this.copy,
    required this.onBack,
    super.key,
  }) {
    if (itemId <= 0) {
      throw ArgumentError('Example item ID must be positive.');
    }
  }

  /// 应用路由层传入的已验证正整数 ID。
  final int itemId;

  /// 由应用组装层按当前 locale 注入的页面文案与格式化能力。
  final ExampleDetailCopy copy;

  /// 离开当前详情的应用级导航命令。
  final VoidCallback onBack;

  /// 根据当前示例详情状态构建固定边界的页面。
  ///
  /// 构建过程只订阅当前 [itemId] 的 provider，没有 I/O 或导航副作用。Repository 完成会由
  /// Riverpod 触发重建；页面销毁后的取消和迟到结果隔离由 Controller 负责。
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailState = ref.watch(exampleDetailProvider(itemId));

    return Scaffold(
      body: SafeArea(
        key: const Key('template-detail-route'),
        child: Column(
          children: <Widget>[
            _ExampleDetailHeader(itemId: itemId, copy: copy, onBack: onBack),
            Divider(height: context.du(1), thickness: context.du(1)),
            Expanded(child: _buildStateBody(ref, detailState)),
          ],
        ),
      ),
    );
  }

  Widget _buildStateBody(WidgetRef ref, AsyncValue<ExampleItem?> detailState) {
    // AsyncValue 刷新时可能同时保留旧 data/error；本页面选择完整加载反馈，因此 loading
    // 优先于 previous value，避免用户误以为重试已经完成。
    if (detailState.isLoading) {
      return AppLoadingState(
        key: const Key('example-detail-loading'),
        message: copy.loadingMessage,
      );
    }
    if (detailState.hasError) {
      final rawError = detailState.error;
      final error =
          rawError is AppError ? rawError : const UnexpectedAppError();
      return AppErrorState(
        key: const Key('example-detail-error'),
        title: copy.errorTitle,
        message: copy.errorMessage(error),
        retryLabel: copy.retryLabel,
        onRetry: () {
          unawaited(ref.read(exampleDetailProvider(itemId).notifier).retry());
        },
      );
    }

    final item = detailState.valueOrNull;
    if (item == null) {
      return AppEmptyState(
        key: const Key('example-detail-empty'),
        title: copy.emptyTitle,
        message: copy.emptyMessage,
        action: OutlinedButton.icon(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back),
          label: Text(copy.backToHomeLabel),
        ),
      );
    }
    return _ExampleItemDataView(item: item);
  }
}

final class _ExampleDetailHeader extends StatelessWidget {
  const _ExampleDetailHeader({
    required this.itemId,
    required this.copy,
    required this.onBack,
  });

  final int itemId;
  final ExampleDetailCopy copy;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: context.du(AppSpacing.sm),
        vertical: context.du(AppSpacing.xs),
      ),
      child: Row(
        children: <Widget>[
          IconButton(
            key: const Key('example-detail-back'),
            tooltip: copy.backTooltip,
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back),
          ),
          SizedBox(width: context.du(AppSpacing.xs)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  copy.pageTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleMedium,
                ),
                Text(
                  copy.itemIdentifier(itemId),
                  key: const Key('example-item-id'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final class _ExampleItemDataView extends StatelessWidget {
  const _ExampleItemDataView({required this.item});

  final ExampleItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      key: const Key('example-detail-data'),
      padding: EdgeInsets.all(context.du(AppSpacing.lg)),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: context.du(480)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ExcludeSemantics(
                child: Icon(
                  Icons.description_outlined,
                  size: context.du(AppSpacing.xxl),
                  color: theme.colorScheme.primary,
                ),
              ),
              SizedBox(height: context.du(AppSpacing.md)),
              Semantics(
                header: true,
                child: Text(item.title, style: theme.textTheme.headlineSmall),
              ),
              SizedBox(height: context.du(AppSpacing.sm)),
              Text(item.description, style: theme.textTheme.bodyLarge),
            ],
          ),
        ),
      ),
    );
  }
}
