import 'package:flutter/material.dart';
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

  /// 所有启动失败统一展示的稳定用户文案。
  static const message = 'The application could not start.';

  /// fallback 替换正常应用时供辅助技术播报的状态。
  static const semanticsLabel = 'Application startup failed';

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Application unavailable',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Semantics(
                container: true,
                liveRegion: true,
                label: semanticsLabel,
                child: const ExcludeSemantics(
                  child: Text(message, textAlign: TextAlign.center),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
