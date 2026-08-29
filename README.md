# Waymark

> 曾用名 Migration Companion。2026-08-29 改名，历史文档（ADR、交接、门记录）保留原名不动。

面向个人申请人的本地优先移民信息与材料工作空间。第一阶段只运营南澳大利亚州（SA）190/491 的官方信息、政策变更证据和基础材料模板；产品底座为后续全澳洲与其他司法辖区扩展而设计。

## 当前范围

- 中文优先的新闻与官方来源核对
- 政策 Change Log（变更日志）：来源、时间、前后差异、核实与更正
- 访客可直接使用的本机材料项目、五段状态、备份与提醒
- 无 App 直接分享、安全链接，以及 App 内协作的分层设计
- PDF 与受支持简单 DOCX 的安全编辑流程和兼容等级
- 账号、云同步、试用、订阅、删除与商店合规边界

产品不提供个人签证资格判断、路径推荐、政府表格答案建议或代为递交。

## 2026-08-28 可运行基线

当前本地开发版已完成并验证：动态官方内容与离线缓存、来源/新闻/变更/更正/采集健康后台、
访客完整备份恢复、云容量预留计费、扫描状态自动轮询、离线修改队列、幂等重试、409 字段级冲突处理、
账号云项目拉取和换机元数据恢复、预签名直传与失败恢复、政策通知规则与事务 Outbox、7 天账号删除撤回及
过期隔离文件清理。最新自动化证据为 Flutter **21 tests**、API 单元 **4 tests**、API 端到端 **29 tests**、
爬虫 **7 tests**，并通过后台/公开网页生产构建、Flutter Web release 和 243.2 MB Android release APK 构建；
此前也已完成 Pixel Fold API 35 模拟器安装启动检查。

这仍是开发验收基线，不是“已可上架”：生产 Cognito、商店服务端核验与沙盒、APNs/FCM 实际投递、独立扫描 Worker、
文档引擎授权/自研替换、真实 iOS 设备，以及法律/隐私专业复核仍是外部门槛。最新状态见
[`docs/handoff/project-status-2026-08-28.md`](docs/handoff/project-status-2026-08-28.md)。

## Flutter 版本隔离

项目固定 Flutter 3.47.1。所有 Flutter 命令必须通过 FVM 运行，禁止使用 `flutter upgrade`、`flutter channel` 或任何会修改本机全局 Flutter 的操作。

```powershell
fvm install
cd apps\mobile
fvm flutter pub get
fvm flutter run
```

## 项目结构

- `apps/mobile`：Flutter iOS/Android 客户端与 Web 预览
- `docs/product`：原始 PRD 与产品经理签核
- `docs/architecture`：技术总监 ADR 与安全边界
- `docs/review`：每个交付门的产品经理与技术总监评审记录
- `services/api`：账号、同步、分享、协作、订阅和内容 API
- `services/crawler`：官方白名单抓取、证据快照、差异与审核队列
- `apps/admin`：内容与 Change Log 人工审核后台
- `infra`：AWS Sydney 部署定义

## 开发检查

```powershell
cd apps\mobile
fvm flutter analyze
fvm flutter test
fvm flutter build web
```

API 端到端验收（自动启动本地 PostgreSQL 与 MinIO）：

```powershell
.\scripts\test-local-e2e.ps1
```

构建并预览 Web release，附带固定 390x844 手机视口检查页：

```powershell
.\scripts\preview-web-release.ps1
```

所有 `.ps1` 必须保存为 UTF-8 with BOM，否则 Windows PowerShell 5.1 会把中文字符串按 ANSI 解析并报语法错误。

发布到 App Store 或 Google Play 前，仍必须完成真实设备测试、商业文档 SDK 授权验证、商店沙盒订阅测试、独立渗透测试，以及澳洲移民法律与隐私专项审查。

文档引擎采用“免费评估适配器开发、自研 SDK 发布前替换”的路线，见 [`docs/architecture/adr-011-document-engine-transition.md`](docs/architecture/adr-011-document-engine-transition.md)。剩余发布门槛记录在 [`docs/architecture/commercial-release-gates.md`](docs/architecture/commercial-release-gates.md)。在这些门槛通过前，项目不得标记为可上架。
