import 'package:flutter_template/app/bootstrap/app_bootstrap.dart';

/// 进入带全局异常边界和环境配置的应用启动流程。
///
/// 平台入口不负责构造依赖，确保所有启动方式都遵循 [bootstrapApplication]
/// 定义的初始化顺序、失败策略和异常边界。
void main() {
  bootstrapApplication();
}
