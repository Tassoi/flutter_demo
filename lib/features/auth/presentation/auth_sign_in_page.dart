import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_template/features/auth/domain/auth_failure.dart';
import 'package:flutter_template/features/auth/domain/auth_session_state.dart';
import 'package:flutter_template/features/auth/presentation/auth_session_controller.dart';
import 'package:flutter_template/shared/design/app_layout_tokens.dart';
import 'package:flutter_template/shared/layout/app_safe_scrollable_scaffold.dart';
import 'package:flutter_template/shared/layout/app_screen_adaptation.dart';

/// 应用层传给登录页的完整本地化文案集合。
///
/// Feature 不依赖 `app/localization`；所有用户文案和失败映射由唯一 Router 在当前 locale 下
/// 组装。[failureMessage] 只能返回稳定用户文案，禁止回显异常、账号标识或服务端正文。
final class AuthSignInCopy {
  /// 创建登录页所需的固定文案与失败映射。
  const AuthSignInCopy({
    required this.pageTitle,
    required this.identifierLabel,
    required this.passwordLabel,
    required this.identifierRequired,
    required this.passwordRequired,
    required this.showPasswordTooltip,
    required this.hidePasswordTooltip,
    required this.submitLabel,
    required this.returnHomeLabel,
    required this.failureMessage,
  });

  /// 页面标题。
  final String pageTitle;

  /// 登录标识符输入标签。
  final String identifierLabel;

  /// 密码输入标签。
  final String passwordLabel;

  /// 标识符为空时的校验文案。
  final String identifierRequired;

  /// 密码为空时的校验文案。
  final String passwordRequired;

  /// 显示密码按钮提示。
  final String showPasswordTooltip;

  /// 隐藏密码按钮提示。
  final String hidePasswordTooltip;

  /// 登录提交按钮标签。
  final String submitLabel;

  /// 返回公开首页的操作标签。
  final String returnHomeLabel;

  /// 把稳定认证失败映射为当前语言文案。
  final String Function(AuthFailure failure) failureMessage;
}

/// 最小、可替换后端且不持有 Router 的认证登录页。
///
/// 页面只收集登录标识符和密码，并调用唯一 [authSessionProvider]。输入不会写入 Provider
/// 状态、普通存储或日志；密码在每次提交完成和 Widget 销毁时清空。认证成功后的返回位置
/// 由应用同步重定向策略处理，本页面只通过 [onReturnHome] 暴露公开导航命令。
final class AuthSignInPage extends ConsumerStatefulWidget {
  /// 创建具有 [copy] 和公开首页回调的登录页。
  const AuthSignInPage({
    required this.copy,
    required this.onReturnHome,
    super.key,
  });

  /// 当前 locale 下的完整页面文案。
  final AuthSignInCopy copy;

  /// 用户明确选择离开认证流程时调用的导航命令。
  final VoidCallback onReturnHome;

  @override
  ConsumerState<AuthSignInPage> createState() => _AuthSignInPageState();
}

final class _AuthSignInPageState extends ConsumerState<AuthSignInPage> {
  final _formKey = GlobalKey<FormState>();
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  var _isPasswordVisible = false;

  @override
  void dispose() {
    _identifierController.clear();
    _passwordController.clear();
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authSessionProvider);
    final isSubmitting = session.phase == AuthSessionPhase.signingIn;
    final failure = session.failure;
    final theme = Theme.of(context);

    return AppSafeScrollableScaffold(
      key: const Key('auth-sign-in-route'),
      contentPadding: EdgeInsets.all(context.du(AppSpacing.lg)),
      content: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: context.du(480)),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                ExcludeSemantics(
                  child: Icon(
                    Icons.lock_outline,
                    size: context.du(AppSpacing.xxl),
                    color: theme.colorScheme.primary,
                  ),
                ),
                SizedBox(height: context.du(AppSpacing.md)),
                Semantics(
                  header: true,
                  child: Text(
                    widget.copy.pageTitle,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall,
                  ),
                ),
                SizedBox(height: context.du(AppSpacing.lg)),
                TextFormField(
                  key: const Key('auth-identifier-field'),
                  controller: _identifierController,
                  enabled: !isSubmitting,
                  autofillHints: const <String>[AutofillHints.username],
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: widget.copy.identifierLabel,
                    prefixIcon: const Icon(Icons.person_outline),
                  ),
                  validator:
                      (value) =>
                          value == null || value.trim().isEmpty
                              ? widget.copy.identifierRequired
                              : null,
                ),
                SizedBox(height: context.du(AppSpacing.md)),
                TextFormField(
                  key: const Key('auth-password-field'),
                  controller: _passwordController,
                  enabled: !isSubmitting,
                  obscureText: !_isPasswordVisible,
                  autofillHints: const <String>[AutofillHints.password],
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted:
                      isSubmitting ? null : (_) => unawaited(_submit()),
                  decoration: InputDecoration(
                    labelText: widget.copy.passwordLabel,
                    prefixIcon: const Icon(Icons.password_outlined),
                    suffixIcon: IconButton(
                      key: const Key('auth-password-visibility'),
                      tooltip:
                          _isPasswordVisible
                              ? widget.copy.hidePasswordTooltip
                              : widget.copy.showPasswordTooltip,
                      onPressed:
                          isSubmitting
                              ? null
                              : () {
                                setState(() {
                                  _isPasswordVisible = !_isPasswordVisible;
                                });
                              },
                      icon: Icon(
                        _isPasswordVisible
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                    ),
                  ),
                  validator:
                      (value) =>
                          value == null || value.isEmpty
                              ? widget.copy.passwordRequired
                              : null,
                ),
                if (failure != null) ...<Widget>[
                  SizedBox(height: context.du(AppSpacing.md)),
                  Semantics(
                    key: const Key('auth-sign-in-failure'),
                    liveRegion: true,
                    child: Text(
                      widget.copy.failureMessage(failure),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ],
            ),
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
                  key: const Key('auth-submit'),
                  onPressed: isSubmitting ? null : () => unawaited(_submit()),
                  icon:
                      isSubmitting
                          ? SizedBox.square(
                            dimension: context.du(AppSpacing.md),
                            child: const CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                          : const Icon(Icons.login),
                  label: Text(widget.copy.submitLabel),
                ),
              ),
              SizedBox(height: context.du(AppSpacing.xs)),
              TextButton.icon(
                key: const Key('auth-return-home'),
                onPressed: isSubmitting ? null : widget.onReturnHome,
                icon: const Icon(Icons.home_outlined),
                label: Text(widget.copy.returnHomeLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final identifier = _identifierController.text;
    final password = _passwordController.text;
    try {
      await ref
          .read(authSessionProvider.notifier)
          .signIn(identifier: identifier, password: password);
    } finally {
      // TextEditingController 已在 dispose 后失效；只在页面仍挂载时清除并重置可见状态。
      if (mounted) {
        _passwordController.clear();
        setState(() {
          _isPasswordVisible = false;
        });
      }
    }
  }
}
