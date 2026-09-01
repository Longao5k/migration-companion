# ADR-011：免费评估组件与自研文档 SDK 过渡

**状态：已执行（PDF 自研替换完成，DOCX 路线待后续决定）**
**日期：2026-08-27**

## 决策

当前 Migration Companion 第一阶段继续使用 Apryse 免费评估能力开发 PDF 适配器，并以 ONLYOFFICE Developer 试用环境开发 DOCX 会话适配器。开发期间不购买商业授权，也不将评估许可提供给正式终端用户。

所有文档能力必须通过项目自有接口调用，不允许业务页面直接依赖供应商 API：

- `PdfDocumentEngine`
- `DocxDocumentEngine`
- `DocumentPreflight`
- `DocumentVersionStore`
- `DocumentCapabilityMatrix`

后续独立自研 SDK 实现相同接口，通过 contract test 后替换评估适配器。发布构建不得包含过期、仅限评估或不允许终端用户使用的组件。

## 原因

- 当前产品可以继续验证 UI、文件生命周期、保存副本、订阅权益和失败状态；
- 自研 SDK 可以独立并行，不阻塞 Migration Companion 其余功能；
- 通过稳定接口和 contract test 控制替换成本；
- 正式发布前可以在“购买生产许可”与“完成自研替换”之间作最终选择。

## 发布门槛

免费或试用组件只用于开发、自动化验证和内部演示。App Store、Google Play、公开 TestFlight、公开 Play testing 或向外部用户提供编辑能力前，必须完成以下之一：

1. 自研 SDK 已通过当前 P0 corpus 和双平台验收并完成替换；或
2. 产品所有者购买允许生产和终端用户使用的商业许可。

## 2026-09-01 执行结果

- PDF 宿主固定依赖 `docu-sdk` 的 `v0.1.0-alpha.4`，不再把 Apryse 评估组件带入 App。`alpha.4` 只修复真实接入时发现的 Gradle 9 Android 构建问题，C ABI 仍为 15。
- App 继续通过自有 `PdfDocumentEngine` 边界先做逐文件兼容性检查，再打开 App 私有工作副本。
- 保存使用 SDK 的 validated copy，作为新附件或用户选择的新文件落地；不原地覆盖来源文件。
- 页面预览必须保留兼容性提示。字体替代只说明内容是否完整，不得把 `complete` 当作 `exact`。
- 版本仍是 Alpha；Android/iOS 代表性语料、性能、崩溃与商店构建验证仍是发布门，不因代码接入自动签核。

