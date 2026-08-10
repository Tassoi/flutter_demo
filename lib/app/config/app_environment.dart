/// 应用模板支持的环境。
///
/// 取值有意限制为 Android/iOS 原生 variant 已提供的三个环境，因此增加枚举值是跨平台
/// 变更，必须同步修改 Gradle、Xcode、Podfile、CI 和环境一致性检查。
enum AppEnvironment {
  /// 使用详细诊断和独立标识的开发构建。
  dev,

  /// 用于候选版本验证的预发布构建。
  staging,

  /// 使用最严格诊断默认值的生产构建。
  prod;

  /// 解析 `APP_ENV` Dart define 提供的精确值。
  ///
  /// 只接受 `dev`、`staging` 和 `prod`。解析器刻意不移除空格或统一大小写，因为静默
  /// 修复构建配置拼写错误可能选择错误的后端或原生 variant。
  ///
  /// [value] 为空或不受支持时抛出 [FormatException]。异常由应用启动边界捕获，且不会
  /// 复制进启动失败 UI；解析过程不触发网络或磁盘 I/O。
  static AppEnvironment parse(String value) {
    return switch (value) {
      'dev' => AppEnvironment.dev,
      'staging' => AppEnvironment.staging,
      'prod' => AppEnvironment.prod,
      _ =>
        throw FormatException(
          'APP_ENV must be exactly one of: dev, staging, prod.',
        ),
    };
  }
}
