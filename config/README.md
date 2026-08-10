# Dart 编译期配置

`*.example.json` 是可以提交的非敏感示例，可通过以下方式运行：

```bash
flutter run --flavor dev --dart-define-from-file=config/dev.example.json
```

需要使用本机地址时，创建例如 `config/dev.local.json` 的文件；根目录 `.gitignore` 会忽略除 `*.example.json` 外的 JSON 配置。不要把 API key、Token、密码、证书或签名信息放进任何 Dart define 文件。忽略文件只能避免误提交，不能阻止值被编译进应用后二进制提取。

`APP_ENV` 必须精确为 `dev`、`staging` 或 `prod`。`API_BASE_URL` 可以省略，此时配置模型使用对应的 `.invalid` 安全默认值；生产环境覆盖地址必须使用 HTTPS。dev/staging 的配置模型虽接受 HTTP，模板也不会全局放宽 Android Network Security 或 iOS App Transport Security，因此移动端默认仍应使用 HTTPS。具体项目确需明文调试时，只能为明确开发环境和目标主机增加最小平台例外及测试，不能提交全局放行。`main.dart` 会通过集中启动流程读取这些值：配置无效时不会继续组装依赖，而是显示不含异常、地址或堆栈的固定失败界面。Android flavor 与 iOS scheme 已使用同一环境名；Flutter CLI 提供的 flavor 与 `APP_ENV` 不一致时也会在依赖初始化前失败。完整平台命令和签名边界见 [`docs/architecture/0013-mobile-environment-builds.md`](../docs/architecture/0013-mobile-environment-builds.md)，启动或网络配置失败的诊断见[常见问题与诊断](../docs/troubleshooting.md)。
