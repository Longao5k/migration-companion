# ADR-011：免费评估组件与自研文档 SDK 过渡

**状态：已接受**  
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

