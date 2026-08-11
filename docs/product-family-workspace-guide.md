# 下游产品族 Workspace 参考指南

## 文档定位

- 状态：Reference
- 记录日期：2026-08-10
- 适用对象：从本脚手架派生并已经完成第一个 App 的下游产品仓库
- 不适用对象：当前 `flutter_template` 仓库、默认单 App 输出或尚无第二个真实产品的项目

本文件只保存产品族演进时可复用的架构约束，不是本仓库的第三阶段计划，也不授权
在本仓库实现 Workspace、产品初始化工具、签名管理或发布平台。

当第一个 App 已经发布，并且第二个相关产品的需求足以识别真实差异时，应在第一个
App 所在仓库中创建新的 Goal。该 Goal 必须重新读取当时的代码、SDK、接口、设计稿、
账号归属和公司安全要求；不能把本指南直接当成已经确认的实施计划。

## 推荐演进顺序

```text
flutter_template 稳定版本
    ↓ 独立裁剪
company_mobile_base
    ↓ 创建产品仓库
App A 开发、跨电脑归档并发布
    ↓ 保留发布 Tag，在同一 Git 历史中演进
产品族 Workspace + App B
    ↓ 依据两个真实消费者提取公共 Package
App C 及后续产品按需加入
```

当前脚手架完成第二阶段 Final Review 后即告一段落。`company_mobile_base` 和产品族
Workspace 应使用独立仓库维护；它们不是本脚手架的运行时依赖，也不自动继承上游
修改。通用修复只能经过评估后选择性迁移。

## 启动条件

只有同时满足以下条件，才应启动产品仓库的 Workspace Goal：

1. App A 已经形成可重建的发布 Tag，并能在归档电脑独立构建。
2. App B 的功能、接口、设计、品牌、包名和发布账号边界已经基本明确。
3. 公司允许相关产品代码共仓；合同、知识产权或客户隔离规则没有禁止共享源码。
4. 团队接受 App A、App B 共享一份依赖解析和公共 Package 变更验证。

如果第三项不成立，必须使用独立产品仓库和公司批准的私有包分发方式，不得为了
技术便利擅自建立 Monorepo。

## Git 与目录关系

模板、公司基础模板和产品 Workspace 使用三个独立 Git 仓库：

```text
flutter_template                # 通用脚手架
company_mobile_base             # 公司级单 App 基础模板
company_product_workspace       # 实际产品代码
├── apps/
│   ├── app_a/
│   └── app_b/
├── packages/
├── tool/
├── pubspec.yaml
└── pubspec.lock
```

App A 发布后应先创建不可变 Tag，再在同一个产品仓库中迁移目录并添加 Workspace
根配置，以保留完整历史。各产品不使用长期产品分支；日常开发合入共同主线，发布
使用产品独立 Tag，例如 `app-a-v1.0.0-build1` 和 `app-b-v1.0.0-build1`。

归档电脑只需要克隆产品 Workspace，不需要克隆两个模板仓库。模板更新不会自动
传播到产品仓库；只有确认适用的修复才人工迁移。

## Workspace 结构

每个产品必须是完整且可独立构建的 Flutter App，拥有自己的 Dart 包、Android/iOS
原生工程、应用标识、品牌资源、设计系统、版本和发布配置。

```text
company_product_workspace/
├── pubspec.yaml                 # 显式 Workspace 成员
├── pubspec.lock                 # 唯一锁文件
├── apps/
│   ├── app_a/
│   │   ├── pubspec.yaml
│   │   ├── android/
│   │   ├── ios/
│   │   ├── assets/
│   │   ├── lib/
│   │   └── test/
│   └── app_b/
│       └── ...
└── packages/
    ├── foundation/
    ├── app_network/
    └── auth_core/
```

当前模板 Dart 3.7 基线可以使用 Dart Pub Workspace，但成员必须显式列出；若未来
升级到支持通配符的 SDK，也必须在产品仓库 ADR 中单独评估。所有成员使用根锁文件，
不得保留遮蔽根解析的子级锁文件或 `.dart_tool` 配置。

依赖方向必须保持：

```text
apps/<product> → packages/*
packages/*     ↛ apps/<product>
app_a          ↛ app_b
app_b          ↛ app_a
```

每个 App 只声明实际使用的 Package。不得创建依赖所有 Feature、插件和资源的
`company_common` 万能包，也不得通过运行时布尔开关注册全部产品功能。

## 公共模块判定

“两个产品里都有相似代码”不是充分条件。代码进入共享 Package 前必须满足：

1. 至少存在 App A、App B 两个真实消费者。
2. 业务语义、错误规则和生命周期一致。
3. 未来变化方向和发布节奏基本一致。
4. 抽取后不需要产品名判断、大量可选参数或不断增长的功能开关。
5. Package 可以独立测试，删除任一产品后仍保持清晰职责。

默认处理方式：

| 实际情况 | 处理方式 |
| --- | --- |
| 业务、交互和视觉都相同 | 可以共享完整 Feature |
| 业务和状态相同，视觉不同 | 共享领域、数据和状态；页面留在各 App |
| 请求响应相同，只有路径不同 | 共享客户端和 Repository，注入产品路由表 |
| 服务端结构不同，领域语义相同 | 各产品提供 Adapter，输出共同领域模型 |
| 业务规则或用户流程不同 | 保留产品专属 Feature |

适度重复优于错误抽象。只有一个消费者的代码继续留在对应产品 App。

## 产品、环境与发布账号

以下三个维度必须独立：

| 维度 | 负责内容 |
| --- | --- |
| 产品 | 功能组合、设计、资源、接口路径、应用标识 |
| 环境 | `dev`、`staging`、`prod` 的 Base URL、日志和后缀 |
| 发布账号 | Apple/Android 证书、Profile、权限和 Secret |

产品不得实现为环境 Flavor。每个产品内部继续拥有自己的三个环境，但同一产品的
三个环境复用该产品的一套 Logo。不同产品不得互相读取品牌资源、原生配置或签名。

相同接口语义但路径不同的情况由产品 App 提供语义路由映射。Base URL 属于环境，
相对路径属于产品；共享 Repository 不得包含具体产品名或混淆路径。客户端路径
始终可以被逆向分析，不能作为认证或授权边界。

## 跨电脑归档的最小方案

第一版不开发自动发布平台、源码导出器或私有 Package 服务。开发电脑和归档电脑
通过私有 Git 仓库及产品发布 Tag 交付完整 Workspace：

```text
开发电脑提交并推送产品 Tag
    ↓
归档电脑检出准确 Tag
    ↓
安装根依赖并执行产品测试
    ↓
进入 apps/<product> 构建 IPA/AAB
    ↓
使用归档电脑本地签名材料上传
```

Tag 固定整个 Workspace 快照，因此同时固定产品 App、公共 Package 和根锁文件。
归档电脑不得从开发者未提交的工作区构建，也不得复制 `.dart_tool/`、`build/` 等
机器缓存。

证书、私钥、Provisioning Profile、API Key 和生产凭据只保存在归档电脑或公司批准
的 Secret 系统中，不进入 Git。各产品发布命令、Bundle ID、版本和签名账号必须
明确分开。

只有公司明确要求归档电脑不能看到其他产品源码时，才单独设计“产品源码依赖闭包
导出工具”。该工具属于新的安全与发布需求，不能在没有隔离要求时提前实现。

## 验证要求

下游 Workspace Goal 至少验证：

1. App A 迁移前的发布 Tag 仍可在归档电脑重建。
2. App A、App B 可以从同一 Workspace 分别运行、测试和构建。
3. Dart 包名、Android Application ID、iOS Bundle ID 和品牌资源互不冲突。
4. 每个产品只依赖实际需要的内部 Package、原生插件和资源。
5. 公共 Package 变化会验证所有消费者，产品专属变化不会污染其他 App。
6. 产品路由映射覆盖全部业务语义和主要错误路径。
7. 根锁文件、生成产物和发布 Tag 能在干净克隆中复现。
8. 归档日志、测试和仓库中没有真实签名材料或生产凭据。

自动化应在人工流程至少稳定执行两次后再增加。优先自动化重复检查和构建参数，
不自动管理开发者账号、创建或撤销证书、修改商店状态或上传未经确认的产物。

## 下游 Goal 初始化建议

启动产品 Workspace 时，用户应在 App A 产品仓库中明确输入 `/goal`，并让该仓库
自己的 `AGENTS.md` 保存本指南仍适用的边界。Goal 第一项只盘点两个真实产品和发布
流程并输出 ADR；在共享范围、源码共仓权限和回滚方式确认前，不移动 App A 源码。

本指南可以复制为决策输入，但不能替代产品仓库的 `input.md`、`plan.md`、
`tasks.md`、实际构建证据和最终 Review。
