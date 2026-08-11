# SVG 图标字体指南

本能力只处理适合单色 `IconData` 语义的应用图标。原始 SVG 是唯一人工维护的图形源；OTF 与
Dart 映射是可删除、可重复生成的产物。多色插图、品牌图、动画或需要运行时修改内部元素的
SVG 继续使用 `flutter_svg`，不得为了统一入口而丢失颜色、细节或可访问性信息。

## 文件所有权

```text
assets/icons/svg/                     # 人工维护：单色 SVG 图形源
assets/icons/icon_font_manifest.json  # 人工维护：稳定身份、状态和许可证
assets/icons/LICENSE.md               # 人工维护：字形来源与再分发许可
assets/fonts/template_icons.otf       # 生成产物：禁止手改
lib/shared/assets/generated/
└── template_icons.g.dart             # 生成产物：禁止手改
tool/generate_icon_font.dart          # 本能力唯一生成与检查工具
```

字体工具的 MIT 许可证不等于字形许可证。加入 SVG 前，维护者必须确认项目拥有该图形或已获得
允许修改和再分发的授权，并在清单和 `LICENSE.md` 中登记同一个 license ID、SPDX 标识和来源。
无法确认权利的文件不得加入；不得从搜索结果或客户产品中直接复制图标。

## SVG 输入约束

生成器有意接受很小的 SVG 子集，避免不同解析器忽略样式或 transform 后生成错误字形：

1. 文件名必须由 glyph 的 `lower_snake_case` 名称精确推导，例如 `language.svg`。
2. 根元素必须是标准 SVG namespace，`viewBox` 精确为 `0 0 24 24`。
3. 根元素只能包含一个或多个直接 `path`；path 只能有非空 `d` 属性。
4. 不接受 `g`、`rect`、`circle`、`use`、`defs`、文字、位图、style、fill、stroke、
   `fill-rule` 或 transform。需要这些能力时先在设计工具中转换为最终 path，并人工核对。
5. 轮廓必须在画布内具有正宽和正高；完全相同的两个活动轮廓会被拒绝。
6. 图标本身不携带可访问性文案。按钮、菜单或页面在消费 `TemplateIcons` 时负责提供当前 locale
   的 tooltip/semantics；纯装饰图标保持从语义树排除。

## 稳定清单

清单 schema v1 固定 family 和两个输出路径。`glyphs` 数组顺序没有语义，工具始终按 codepoint
排序。当前核心形状如下：

```json
{
  "schemaVersion": 1,
  "fontFamily": "TemplateIcons",
  "fontAsset": "assets/fonts/template_icons.otf",
  "dartOutput": "lib/shared/assets/generated/template_icons.g.dart",
  "licenseFile": "assets/icons/LICENSE.md",
  "nextCodepoint": "0xE002",
  "licenses": {},
  "glyphs": []
}
```

codepoint 从 Unicode Private Use Area 的 `0xE000` 开始。每个历史槽必须连续存在，
`nextCodepoint` 等于下一个从未使用的编号并且只能前移。工具无法替代版本控制判断一次故意的
清单重写，因此 Review 必须把已有名称/codepoint 和 `nextCodepoint` 的变化当作公开 API 迁移；
正常添加、退休和数组重排由专项测试自动锁定。

### 添加图标

1. 确认来源授权，把规范 SVG 放入 `assets/icons/svg/<name>.svg`。
2. 在 `licenses` 和 `LICENSE.md` 登记许可证；已有同来源条目可以复用。
3. 在 `glyphs` 追加活动项，codepoint 使用当前 `nextCodepoint`，路径必须是
   `svg/<name>.svg`，中文 `description` 会成为生成字段的文档注释。
4. 把 `nextCodepoint` 加一。不要为插入到视觉列表中而重排已有 codepoint。
5. 运行生成、聚焦测试、完整门禁和适用平台构建。

### 退休图标

删除 SVG，把原清单项的 `status` 改为 `retired`，移除 `svg`，增加中文
`retiredReason`。名称、codepoint、license ID、说明和 `nextCodepoint` 不得改变。退休项不再
生成公共 `IconData`，但 OTF 中保留零面积占位，因此之后的 glyph ID/codepoint 不会移动。

不得从数组物理删除条目，即使它位于末尾；否则未改变的 `nextCodepoint` 会触发
`ICON_FONT_NEXT_CODEPOINT`。不得通过让 `nextCodepoint` 后退来绕过该错误。

### 重命名图标

重命名是显式破坏性 API 迁移。保留原 codepoint，同时重命名清单 `name`、SVG 文件和 `svg`
路径；在同一变更中更新所有 `TemplateIcons` 调用方和测试。不要先退休旧项再以新 codepoint
复制同一轮廓，除非产品确实要求两个并存身份。迁移说明必须记录旧字段、新字段和回滚方式。

## 生成与只读检查

依赖解析后执行：

```bash
dart run tool/generate_icon_font.dart
dart run tool/generate_icon_font.dart --check
```

普通生成在任何目标写入前完成清单、SVG、许可证、依赖和 `pubspec.yaml` 字体注册预检。工具
按 codepoint 构造 glyph，调用精确锁定的 `icon_font_generator 4.0.0` 结构化 OTF API，再把
`head` 创建/修改时间固定为 2000-01-01，把工具版权年份固定为 2000，并重算每张表和全字体
校验和。Dart emitter 由项目维护，生成标记与公开注释均为中文。

两个输出先写入同文件系统的 `.dart_tool/icon_font_*` 暂存目录并回读验证。安装前旧输出移动
到备份区；任一步失败会删除本轮新文件并恢复两个旧文件。若外部进程同时抢占目标导致回滚也
失败，工具返回 `ICON_FONT_ROLLBACK_FAILED` 并保留暂存目录。此时停止再次生成，核对两个固定
目标，并从该目录的 `backups/` 人工恢复；确认恢复后才删除故障目录。

`--check` 不创建项目内暂存目录。它在系统临时目录生成和回读期望字节，再只读比较两个项目
目标；缺失和过期分别返回 `ICON_FONT_OUTPUT_MISSING`、`ICON_FONT_OUTPUT_STALE`。生成后手改
OTF 或 Dart 会在 CI 失败，应修改人工输入后重新生成。

## 测试与平台验证

聚焦验证命令：

```bash
flutter test test/tool/generate_icon_font_test.dart
flutter test test/shared/assets/template_icons_test.dart
flutter test test/app/router/app_router_test.dart
dart tool/ci/check_architecture.dart
dart tool/ci/check_platform_environments.dart
```

生成器测试覆盖实际 OTF 元数据/校验和/cmap、重复生成、清单重排、追加、退休、尾部删除、
非法 SVG、重复身份、许可证缺失、只读漂移检查、第二目标失败回滚和灾难恢复备份。Widget 测试
从 AssetBundle 加载真实 OTF，并通过像素断言证明两枚活动字形非空且不同。

字体或注册变化还必须实际构建 Android，例如：

```bash
flutter build apk --debug --flavor dev \
  --dart-define-from-file=config/dev.example.json
```

Flutter 的 `pubspec.yaml` 字体注册同时适用于 Android/iOS，平台门禁会静态核对 family 和 OTF
路径。iOS 最终仍须在 macOS/Xcode 执行三个 scheme 的无签名构建，并在模拟器或真机检查字形；
非 macOS 的静态检查和 Android 构建不能冒充 iOS 编译证据。

## 工具升级

`icon_font_generator` 必须保持精确版本，因为项目依赖其从 `E000` 按输入顺序分配、默认 glyph
数量、CFF 表、`head/name` 元数据和校验和行为。升级时同时审查 `xml`、`yaml` 直接解析版本：

1. 阅读版本间 changelog、SDK 下限和包内许可证。
2. 在独立分支更新精确版本和锁文件，不放宽为 `any` 或未审查范围。
3. 重新核对包的 codepoint、退休占位、SVG 解析、字体表和时间字段；未知结构应安全失败。
4. 连续生成两次并比较 OTF/Dart SHA-256，运行全部专项测试和格式/分析/全量测试。
5. 实际构建 Android，并在 macOS 补 iOS 构建与字形检查；记录 APK/IPA 包体变化。

若新工具无法满足确定性，可替换 `tool/generate_icon_font.dart` 内部 adapter，但必须保持
`TemplateIcons` family、现有 codepoint、输入清单与应用调用接口。

## 删除与回滚

完整移除图标字体时，先把所有 `TemplateIcons` 调用方替换为普通 SVG、Material 图标或具体
项目资源，再删除：

1. `assets/icons/`、生成 OTF 和生成 Dart 文件。
2. `tool/generate_icon_font.dart` 及两个专项测试。
3. `pubspec.yaml` 的 TemplateIcons 注册和三个 dev 依赖，并重新生成锁文件。
4. CI 字体 `--check`、架构工具依赖规则、平台字体注册规则和相关文档。

随后执行完整格式、分析、测试和 Android/iOS 构建。普通 `AppAssets`、`flutter_svg`、主题、
路由、国际化和示例 Feature 不依赖字体生成器内部实现，不应随删除一同移除。

若只回滚一次错误图标变更，应整体恢复 SVG、清单、许可证、OTF、Dart 映射和所有调用方，
然后运行 `--check`。不得只恢复生成文件而保留不同人工输入，也不得通过复用已发布 codepoint
制造表面上的干净检查结果。
