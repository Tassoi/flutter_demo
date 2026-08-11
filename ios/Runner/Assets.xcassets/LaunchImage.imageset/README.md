# 启动图片生成产物

本目录由 `dart run tool/generate_branding.dart` 根据 `assets/branding/splash_logo.png`
生成。不要直接替换 PNG，也不要在 Xcode 中向本目录拖入文件；手工改动会被
`dart run tool/generate_branding.dart --check` 识别为过期或未知产物。

替换正式品牌时，请先更新经过授权的源图和 `assets/branding/LICENSE.md`，再按
`docs/branding.md` 的步骤重新生成、检查并执行平台构建。
