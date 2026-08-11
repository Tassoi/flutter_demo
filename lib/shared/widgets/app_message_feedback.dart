import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_template/shared/design/app_layout_tokens.dart';
import 'package:flutter_template/shared/layout/app_screen_adaptation.dart';

/// 短时消息反馈使用的视觉语义。
///
/// 该枚举只选择现有 [ColorScheme] 角色和熟悉图标，不代表日志级别、业务错误类型或
/// 持久状态。调用方应依据用户需要采取的动作选择种类，而不是暴露后端实现细节。
enum AppMessageKind {
  /// 一般说明或非阻塞提示。
  information,

  /// 已成功完成的操作。
  success,

  /// 需要注意但尚可继续的状态。
  warning,

  /// 未完成或失败的操作。
  error,
}

/// 通过最近的 [ScaffoldMessenger] 展示短时消息反馈。
///
/// [message] 必须是非空且适合展示给用户的安全文案，不得包含原始异常、响应正文、
/// Token 或个人数据。[actionLabel] 与 [onAction] 必须同时提供或同时省略；包装器最多
/// 转发一次动作。[actionIcon] 只负责可见动作图标，不改变回调语义。本函数不记录、缓存
/// 或重试消息，也不改变业务状态。
///
/// [replaceCurrent] 默认为 `true`，会清除当前及排队中的旧消息，再展示最新状态，避免
/// 快速状态变化产生过期提示；设为 `false` 时沿用 ScaffoldMessenger 的排队语义。
/// 返回的控制器可用于观察关闭原因或由调用方主动关闭。调用必须发生在已有 Scaffold
/// 的事件回调或帧结束后，不能在 Widget `build` 期间执行。
///
/// 消息正文和可选操作共享一个有界滚动区域。高度计算同时考虑调用处的 MediaQuery 和所属
/// FlutterView 的原始安全区/键盘 Insets，因此调用处即使位于已经消费 padding 的 SafeArea
/// 下方，也不会让浮动 SnackBar 超出 Scaffold 可见区域；这些平台值不会经过 `du` 换算。
ScaffoldFeatureController<SnackBar, SnackBarClosedReason>
showAppMessageFeedback(
  BuildContext context, {
  required String message,
  AppMessageKind kind = AppMessageKind.information,
  Duration duration = const Duration(seconds: 4),
  String? actionLabel,
  VoidCallback? onAction,
  IconData actionIcon = Icons.arrow_forward,
  bool replaceCurrent = true,
}) {
  if (message.trim().isEmpty) {
    throw ArgumentError('message must contain readable text.');
  }
  if (duration <= Duration.zero) {
    throw ArgumentError('duration must be greater than zero.');
  }
  if ((actionLabel == null) != (onAction == null)) {
    throw ArgumentError('actionLabel and onAction must be provided together.');
  }
  if (actionLabel != null && actionLabel.trim().isEmpty) {
    throw ArgumentError('actionLabel must contain readable text.');
  }

  final messenger = ScaffoldMessenger.of(context);
  final visual = _feedbackVisual(kind, Theme.of(context).colorScheme);
  final hasAction = actionLabel != null;
  final mediaQuery = MediaQuery.of(context);
  final flutterView = View.of(context);
  final platformPadding = EdgeInsets.fromViewPadding(
    flutterView.padding,
    flutterView.devicePixelRatio,
  );
  final platformViewInsets = EdgeInsets.fromViewPadding(
    flutterView.viewInsets,
    flutterView.devicePixelRatio,
  );
  final effectivePadding = _maxInsets(mediaQuery.padding, platformPadding);
  final effectiveViewInsets = _maxInsets(
    mediaQuery.viewInsets,
    platformViewInsets,
  );
  final margin = EdgeInsets.all(context.du(AppSpacing.md));
  final contentPadding = EdgeInsets.symmetric(
    horizontal: context.du(AppSpacing.md),
    vertical: context.du(AppSpacing.sm),
  );
  final maximumContentHeight = math.max(
    0.0,
    mediaQuery.size.height -
        effectivePadding.vertical -
        effectiveViewInsets.vertical -
        margin.vertical,
  );
  var actionInvoked = false;

  void handleAction() {
    if (actionInvoked) {
      return;
    }
    actionInvoked = true;
    try {
      onAction!();
    } finally {
      messenger.hideCurrentSnackBar(reason: SnackBarClosedReason.action);
    }
  }

  if (replaceCurrent) {
    // 清理发生在新消息入队前，保证快速连续反馈最终只保留调用方最新状态。
    messenger.clearSnackBars();
  }

  return messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      margin: margin,
      padding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.du(AppRadii.medium)),
      ),
      backgroundColor: visual.background,
      duration: duration,
      showCloseIcon: !hasAction,
      closeIconColor: visual.foreground,
      content: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maximumContentHeight),
        child: SingleChildScrollView(
          primary: false,
          child: Padding(
            padding: contentPadding,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Semantics(
                  container: true,
                  liveRegion: true,
                  label: message,
                  child: ExcludeSemantics(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Icon(
                          visual.icon,
                          size: context.du(AppSpacing.lg),
                          color: visual.foreground,
                        ),
                        SizedBox(width: context.du(AppSpacing.sm)),
                        Expanded(
                          child: Text(
                            message,
                            softWrap: true,
                            style: TextStyle(color: visual.foreground),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (hasAction) ...<Widget>[
                  SizedBox(height: context.du(AppSpacing.xs)),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: AppDimensions.minimumTouchTarget(context),
                        maxWidth: context.du(320),
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: visual.foreground,
                          ),
                          onPressed: handleAction,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              Icon(actionIcon, size: context.du(AppSpacing.lg)),
                              SizedBox(width: context.du(AppSpacing.xs)),
                              Flexible(
                                child: Text(
                                  actionLabel,
                                  textAlign: TextAlign.center,
                                  softWrap: true,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

({IconData icon, Color background, Color foreground}) _feedbackVisual(
  AppMessageKind kind,
  ColorScheme colorScheme,
) {
  return switch (kind) {
    AppMessageKind.information => (
      icon: Icons.info_outline,
      background: colorScheme.tertiaryContainer,
      foreground: colorScheme.onTertiaryContainer,
    ),
    AppMessageKind.success => (
      icon: Icons.check_circle_outline,
      background: colorScheme.primaryContainer,
      foreground: colorScheme.onPrimaryContainer,
    ),
    AppMessageKind.warning => (
      icon: Icons.warning_amber_rounded,
      background: colorScheme.secondaryContainer,
      foreground: colorScheme.onSecondaryContainer,
    ),
    AppMessageKind.error => (
      icon: Icons.error_outline,
      background: colorScheme.errorContainer,
      foreground: colorScheme.onErrorContainer,
    ),
  };
}

EdgeInsets _maxInsets(EdgeInsets ambient, EdgeInsets platform) {
  // 调用方经常位于 SafeArea 下方，此时局部 MediaQuery 已把消费过的 padding 清零，
  // 但拥有 Scaffold 的上级仍按原始平台值摆放浮动 SnackBar。逐边保留两者较大值，既兼容
  // 未消费的局部 Insets，也避免错误地认为整个物理 View 都可用于消息内容。
  return EdgeInsets.fromLTRB(
    math.max(ambient.left, platform.left),
    math.max(ambient.top, platform.top),
    math.max(ambient.right, platform.right),
    math.max(ambient.bottom, platform.bottom),
  );
}
