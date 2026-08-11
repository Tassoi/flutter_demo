import 'package:flutter/material.dart';
import 'package:flutter_template/app/localization/app_locale.dart';
import 'package:flutter_template/app/localization/app_localizations.dart';
import 'package:flutter_template/app/theme/app_theme.dart';
import 'package:flutter_template/shared/design/app_layout_tokens.dart';

/// 配置解析或依赖组装失败时展示的最小应用。
///
/// 构造函数刻意不接收异常或诊断文本，从类型边界上避免配置值、堆栈、凭据和内部实现
/// 细节意外进入 Widget 树。当前页面不提供交互，因为可靠的重试语义取决于后续基础设施
/// 引入的真实资源及其释放规则。
final class StartupFailureApp extends StatelessWidget {
  /// 创建不依赖任何初始化结果的启动 fallback。
  const StartupFailureApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      onGenerateTitle:
          (context) => context.localizations.applicationUnavailableTitle,
      theme: AppTheme.fallbackLight(),
      darkTheme: AppTheme.fallbackDark(),
      themeMode: ThemeMode.system,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      localeListResolutionCallback: resolveAppLocale,
      home: const _StartupFailureView(),
    );
  }
}

final class _StartupFailureView extends StatelessWidget {
  const _StartupFailureView();

  @override
  Widget build(BuildContext context) {
    final localizations = context.localizations;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            // 正常适配根可能正是启动失败原因，fallback 有意使用设计稿 1:1 留白，不能
            // 调用 du/dsp 或加载其他初始化结果。
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Semantics(
              container: true,
              liveRegion: true,
              label: localizations.applicationStartupFailedSemantics,
              child: ExcludeSemantics(
                child: Text(
                  localizations.applicationStartupFailedMessage,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
