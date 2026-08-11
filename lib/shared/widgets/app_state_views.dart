import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_template/shared/design/app_layout_tokens.dart';
import 'package:flutter_template/shared/layout/app_screen_adaptation.dart';

const _statusContentMaxWidth = 480.0;
const _statusActionMaxWidth = 320.0;
const _statusIconSize = 48.0;

/// 展示正在进行且尚无可交互结果的加载状态。
///
/// [message] 同时作为可见文案和实时语义播报，不得为空，也不应包含底层异常、凭据或
/// 其他仅供诊断的信息。本组件不启动异步任务、不管理超时，也不会决定何时切换状态；
/// 调用方仍负责请求生命周期和状态转换。
///
/// 内容在有界高度中垂直居中，短屏或较大系统文字导致空间不足时可以滚动。[padding]
/// 只控制组件内部留白，页面级 SafeArea 仍由调用方负责。
final class AppLoadingState extends StatelessWidget {
  /// 创建具有稳定进度指示器尺寸的加载状态。
  AppLoadingState({required this.message, this.padding, super.key}) {
    _requireNonBlank(message, 'message');
  }

  /// 面向用户且可供辅助技术播报的加载说明。
  final String message;

  /// 状态内容与可用边界之间的可选实际逻辑留白。
  ///
  /// 省略时使用按当前宽度换算的 `AppSpacing.lg`；调用方提供时应先通过 `du` 构造，且解析后
  /// 每条边都必须有限且非负。系统 SafeArea 或键盘 Insets 不得放入本参数。
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      container: true,
      liveRegion: true,
      label: message,
      child: ExcludeSemantics(
        child: _AppStateViewport(
          padding: padding ?? EdgeInsets.all(context.du(AppSpacing.lg)),
          child: _AppStateContent(
            visual: SizedBox.square(
              dimension: context.du(AppSpacing.xxxl),
              child: Center(
                child: SizedBox.square(
                  dimension: context.du(AppSpacing.xl),
                  child: CircularProgressIndicator(
                    strokeWidth: context.du(3),
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ),
            message: message,
          ),
        ),
      ),
    );
  }
}

/// 展示一次查询或集合没有可呈现内容的空状态。
///
/// [title] 描述状态，[message] 可以补充用户下一步，但两者都不应包含业务实体实现细节。
/// [action] 允许调用方组合与当前页面有关的按钮；本组件不推断刷新、创建或清除筛选等
/// 业务行为。[decoration] 仅承担视觉装饰并从语义树排除，状态含义必须由文字表达。
final class AppEmptyState extends StatelessWidget {
  /// 创建可选说明、装饰和操作的空状态。
  AppEmptyState({
    required this.title,
    this.message,
    this.action,
    this.decoration,
    this.padding,
    super.key,
  }) {
    _requireNonBlank(title, 'title');
    if (message != null) {
      _requireNonBlank(message!, 'message');
    }
  }

  /// 空状态的简短标题。
  final String title;

  /// 可选的补充说明。
  final String? message;

  /// 可选的调用方操作 Widget，其回调和业务语义由调用方拥有。
  final Widget? action;

  /// 可选的纯装饰 Widget；省略时使用中立的收件箱图标。
  final Widget? decoration;

  /// 状态内容与可用边界之间的可选实际逻辑留白。
  ///
  /// 省略时使用按当前宽度换算的 `AppSpacing.lg`；调用方提供时应先通过 `du` 构造，且不得
  /// 混入系统 Insets。
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      container: true,
      explicitChildNodes: true,
      liveRegion: true,
      child: _AppStateViewport(
        padding: padding ?? EdgeInsets.all(context.du(AppSpacing.lg)),
        child: _AppStateContent(
          visual: _StateDecoration(
            color: theme.colorScheme.onSurfaceVariant,
            fallbackIcon: Icons.inbox_outlined,
            decoration: decoration,
          ),
          title: title,
          message: message,
          action: action,
        ),
      ),
    );
  }
}

/// 展示已经失败且可选择重试的错误状态。
///
/// [title] 和 [message] 必须是适合向用户展示的稳定文案，禁止直接传入异常 `toString()`、
/// 响应正文、路径或凭据。[retryLabel] 与 [onRetry] 必须同时提供或同时省略；组件只转发
/// 点击，不实现重试次数、去重、退避、取消或并发控制，这些行为仍由状态管理单元负责。
/// [decoration] 仅用于视觉呈现并从语义树排除。
final class AppErrorState extends StatelessWidget {
  /// 创建错误状态，并可选择提供重试命令。
  AppErrorState({
    required this.title,
    required this.message,
    this.retryLabel,
    this.onRetry,
    this.decoration,
    this.padding,
    super.key,
  }) {
    _requireNonBlank(title, 'title');
    _requireNonBlank(message, 'message');
    if ((retryLabel == null) != (onRetry == null)) {
      throw ArgumentError('retryLabel and onRetry must be provided together.');
    }
    if (retryLabel != null) {
      _requireNonBlank(retryLabel!, 'retryLabel');
    }
  }

  /// 错误状态的简短标题。
  final String title;

  /// 不包含内部诊断信息的用户说明。
  final String message;

  /// 可选重试按钮的可见标签。
  final String? retryLabel;

  /// 可选重试回调；请求并发和取消仍由调用方处理。
  final VoidCallback? onRetry;

  /// 可选的纯装饰 Widget；省略时使用中立错误图标。
  final Widget? decoration;

  /// 状态内容与可用边界之间的可选实际逻辑留白。
  ///
  /// 省略时使用按当前宽度换算的 `AppSpacing.lg`；调用方提供时应先通过 `du` 构造，且不得
  /// 混入系统 Insets。
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final retry = onRetry;

    return Semantics(
      container: true,
      explicitChildNodes: true,
      liveRegion: true,
      child: _AppStateViewport(
        padding: padding ?? EdgeInsets.all(context.du(AppSpacing.lg)),
        child: _AppStateContent(
          visual: _StateDecoration(
            color: theme.colorScheme.error,
            fallbackIcon: Icons.error_outline,
            decoration: decoration,
          ),
          title: title,
          message: message,
          action:
              retry == null
                  ? null
                  : FilledButton.icon(
                    onPressed: retry,
                    icon: const Icon(Icons.refresh),
                    label: Text(
                      retryLabel!,
                      textAlign: TextAlign.center,
                      softWrap: true,
                    ),
                  ),
        ),
      ),
    );
  }
}

final class _AppStateViewport extends StatelessWidget {
  const _AppStateViewport({required this.padding, required this.child});

  final EdgeInsetsGeometry padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final resolvedPadding = padding.resolve(Directionality.of(context));
        if (!_isFiniteNonNegative(resolvedPadding)) {
          throw ArgumentError.value(
            padding,
            'padding',
            'State padding must resolve to finite non-negative values.',
          );
        }
        final content = Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: context.du(_statusContentMaxWidth),
            ),
            child: child,
          ),
        );

        if (!constraints.hasBoundedHeight) {
          return Padding(padding: resolvedPadding, child: content);
        }

        final minimumContentHeight =
            math
                .max(0, constraints.maxHeight - resolvedPadding.vertical)
                .toDouble();

        // 有足够空间时用最小高度把状态居中；文字放大或短屏时仍保留同一滚动容器，
        // 让内容自然增长而不是压缩系统文字、图标或点击目标。
        return SingleChildScrollView(
          padding: resolvedPadding,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minimumContentHeight),
            child: content,
          ),
        );
      },
    );
  }
}

final class _AppStateContent extends StatelessWidget {
  const _AppStateContent({
    required this.visual,
    required this.message,
    this.title,
    this.action,
  });

  final Widget visual;
  final String? title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        visual,
        SizedBox(height: context.du(AppSpacing.md)),
        if (title != null)
          Text(
            title!,
            textAlign: TextAlign.center,
            softWrap: true,
            style: textTheme.titleLarge,
          ),
        if (title != null && message != null)
          SizedBox(height: context.du(AppSpacing.xs)),
        if (message != null)
          Text(
            message!,
            textAlign: TextAlign.center,
            softWrap: true,
            style: title == null ? textTheme.bodyLarge : textTheme.bodyMedium,
          ),
        if (action != null) ...<Widget>[
          SizedBox(height: context.du(AppSpacing.lg)),
          ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: AppDimensions.minimumTouchTarget(context),
              maxWidth: context.du(_statusActionMaxWidth),
            ),
            child: action,
          ),
        ],
      ],
    );
  }
}

final class _StateDecoration extends StatelessWidget {
  const _StateDecoration({
    required this.color,
    required this.fallbackIcon,
    required this.decoration,
  });

  final Color color;
  final IconData fallbackIcon;
  final Widget? decoration;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: context.du(AppSpacing.xxxl),
        child: Center(
          child:
              decoration ??
              Icon(
                fallbackIcon,
                size: context.du(_statusIconSize),
                color: color,
              ),
        ),
      ),
    );
  }
}

void _requireNonBlank(String value, String argumentName) {
  if (value.trim().isEmpty) {
    throw ArgumentError('$argumentName must contain readable text.');
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
