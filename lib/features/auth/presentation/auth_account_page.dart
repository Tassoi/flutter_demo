import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_template/features/auth/domain/auth_session_state.dart';
import 'package:flutter_template/features/auth/presentation/auth_session_controller.dart';
import 'package:flutter_template/shared/design/app_layout_tokens.dart';
import 'package:flutter_template/shared/layout/app_safe_scrollable_scaffold.dart';
import 'package:flutter_template/shared/layout/app_screen_adaptation.dart';

/// 应用层传给受保护认证示例页的本地化文案。
final class AuthAccountCopy {
  /// 创建页面标题、状态说明和操作标签。
  const AuthAccountCopy({
    required this.pageTitle,
    required this.sessionActiveMessage,
    required this.signOutLabel,
    required this.returnHomeLabel,
  });

  /// 页面标题。
  final String pageTitle;

  /// 已建立会话时的稳定说明，不得包含用户对象或 credential。
  final String sessionActiveMessage;

  /// 退出操作标签。
  final String signOutLabel;

  /// 返回公开首页的操作标签。
  final String returnHomeLabel;
}

/// 展示认证状态并提供退出命令的最小受保护页面。
///
/// 页面不读取用户资料或 credential。Router 保证只有已认证快照能够进入；退出会先同步
/// 清空内存状态，随后由路由策略返回登录页。本页面不自行调用 Navigator 或 go_router。
final class AuthAccountPage extends ConsumerWidget {
  /// 创建受保护页面。
  const AuthAccountPage({
    required this.copy,
    required this.onReturnHome,
    super.key,
  });

  /// 当前 locale 下的页面文案。
  final AuthAccountCopy copy;

  /// 用户明确返回公开首页时调用的导航命令。
  final VoidCallback onReturnHome;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authSessionProvider);
    final canSignOut = session.phase == AuthSessionPhase.authenticated;
    final theme = Theme.of(context);

    return AppSafeScrollableScaffold(
      key: const Key('auth-account-route'),
      contentPadding: EdgeInsets.all(context.du(AppSpacing.lg)),
      content: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: context.du(480)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ExcludeSemantics(
                child: Icon(
                  Icons.verified_user_outlined,
                  size: context.du(AppSpacing.xxl),
                  color: theme.colorScheme.tertiary,
                ),
              ),
              SizedBox(height: context.du(AppSpacing.md)),
              Semantics(
                header: true,
                child: Text(
                  copy.pageTitle,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall,
                ),
              ),
              SizedBox(height: context.du(AppSpacing.xs)),
              Text(
                copy.sessionActiveMessage,
                key: const Key('auth-session-active'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
            ],
          ),
        ),
      ),
      bottomAction: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: context.du(480)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SizedBox(
                height: AppDimensions.minimumTouchTarget(context),
                child: FilledButton.icon(
                  key: const Key('auth-sign-out'),
                  onPressed:
                      canSignOut
                          ? () {
                            unawaited(
                              ref.read(authSessionProvider.notifier).signOut(),
                            );
                          }
                          : null,
                  icon: const Icon(Icons.logout),
                  label: Text(copy.signOutLabel),
                ),
              ),
              SizedBox(height: context.du(AppSpacing.xs)),
              TextButton.icon(
                key: const Key('auth-account-return-home'),
                onPressed: onReturnHome,
                icon: const Icon(Icons.home_outlined),
                label: Text(copy.returnHomeLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
