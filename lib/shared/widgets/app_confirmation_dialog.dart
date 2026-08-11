import 'package:flutter/material.dart';
import 'package:flutter_template/shared/design/app_layout_tokens.dart';
import 'package:flutter_template/shared/layout/app_screen_adaptation.dart';

/// 展示需要用户明确确认或取消的 Material 对话框。
///
/// [title]、[message]、[cancelLabel] 和 [confirmLabel] 都必须是非空、适合展示给用户的
/// 文案；不得直接传入底层异常、响应正文或凭据。函数会向根 Navigator 推入一个路由，
/// 因而只能在事件回调或帧结束后调用，不能在 Widget `build` 期间调用。
///
/// 点击取消返回 `false`，点击确认返回 `true`，系统返回键等其他路由关闭方式也折叠为
/// `false`。同一弹窗只接受第一次明确操作；路由开始关闭后也会忽略退出动画期间到达的
/// 按钮事件，避免继续弹出底层路由。遮罩点击不会关闭弹窗，避免把一次误触解释成已完成
/// 决策。[isDestructive] 只改变确认操作的视觉语义，不执行删除、写入或任何业务副作用。
Future<bool> showAppConfirmationDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String cancelLabel,
  required String confirmLabel,
  bool isDestructive = false,
}) async {
  _requireDialogText(title, 'title');
  _requireDialogText(message, 'message');
  _requireDialogText(cancelLabel, 'cancelLabel');
  _requireDialogText(confirmLabel, 'confirmLabel');

  var decisionSubmitted = false;

  void submitDecision(BuildContext dialogContext, bool decision) {
    final dialogRoute = ModalRoute.of(dialogContext);
    if (decisionSubmitted || dialogRoute?.isCurrent != true) {
      return;
    }
    // 两个按钮可能连续收到事件，系统返回后退出动画期间也可能残留旧按钮回调。先确认
    // 弹窗仍是当前路由并锁定结果，避免后续 pop 作用到下方页面；业务副作用仍由等待
    // Future 的调用方在唯一结果后执行。
    decisionSubmitted = true;
    Navigator.of(dialogContext).pop(decision);
  }

  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    useSafeArea: true,
    builder: (dialogContext) {
      final colorScheme = Theme.of(dialogContext).colorScheme;
      final confirmStyle =
          isDestructive
              ? FilledButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor: colorScheme.onError,
              )
              : null;

      return AlertDialog(
        semanticLabel: title,
        scrollable: true,
        insetPadding: EdgeInsets.symmetric(
          horizontal: dialogContext.du(AppSpacing.xl),
          vertical: dialogContext.du(AppSpacing.lg),
        ),
        icon: Icon(
          isDestructive ? Icons.warning_amber_rounded : Icons.help_outline,
          size: dialogContext.du(AppSpacing.lg),
        ),
        iconColor:
            isDestructive ? colorScheme.error : colorScheme.onSurfaceVariant,
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(message),
            SizedBox(height: dialogContext.du(AppSpacing.lg)),
            // AlertDialog 的独立 actions 区不会随标题和正文滚动，较大系统文字可能把
            // 两个长标签挤出短屏。把动作放入同一个可滚动区域，并让每个按钮获得
            // 有界宽度，既保留完整文案，也不通过缩小文字规避布局问题。
            OverflowBar(
              spacing: dialogContext.du(AppSpacing.xs),
              overflowSpacing: dialogContext.du(AppSpacing.xs),
              overflowAlignment: OverflowBarAlignment.end,
              overflowDirection: VerticalDirection.down,
              children: <Widget>[
                _DialogActionButton(
                  label: cancelLabel,
                  icon: Icons.close,
                  onPressed: () => submitDecision(dialogContext, false),
                ),
                _DialogActionButton(
                  label: confirmLabel,
                  icon: isDestructive ? Icons.delete_outline : Icons.check,
                  onPressed: () => submitDecision(dialogContext, true),
                  style: confirmStyle,
                  filled: true,
                ),
              ],
            ),
          ],
        ),
      );
    },
  );

  return result ?? false;
}

final class _DialogActionButton extends StatelessWidget {
  const _DialogActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.style,
    this.filled = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final ButtonStyle? style;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final content = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Icon(icon, size: context.du(AppSpacing.lg)),
        SizedBox(width: context.du(AppSpacing.xs)),
        Flexible(
          child: Text(label, textAlign: TextAlign.center, softWrap: true),
        ),
      ],
    );

    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: AppDimensions.minimumTouchTarget(context),
      ),
      child: SizedBox(
        width: double.infinity,
        child:
            filled
                ? FilledButton(
                  style: style,
                  onPressed: onPressed,
                  child: content,
                )
                : TextButton(onPressed: onPressed, child: content),
      ),
    );
  }
}

void _requireDialogText(String value, String argumentName) {
  if (value.trim().isEmpty) {
    throw ArgumentError('$argumentName must contain readable text.');
  }
}
