# Waymark

> 曾用名 Migration Companion。2026-08-29 改名，历史文档（ADR、交接、门记录）保留原名不动。

面向个人申请人的本地优先移民信息与材料工作空间。第一阶段的**资讯范围是全澳洲、全部移民类型**；南澳是首发市场和材料模板起点，不是资讯过滤边界。后续再按独立法律与内容评审扩展到其他热门移民国家。

## 当前范围

- 中文优先的新闻与官方来源核对
- 政策 Change Log（变更日志）：来源、时间、前后差异、核实与更正
- 访客可直接使用的本机材料项目、五段状态、备份与提醒
- 无 App 直接分享、安全链接，以及 App 内协作的分层设计
- PDF 与受支持简单 DOCX 的安全编辑流程和兼容等级
- 账号、云同步、试用、订阅、删除与商店合规边界

产品不提供个人签证资格判断、路径推荐、政府表格答案建议或代为递交。

## 2026-09-01 可运行基线

当前本地开发版已完成并验证：全澳洲、全移民类型的动态官方内容与离线缓存、来源/新闻/变更/更正/采集健康后台、
访客完整备份恢复、云容量预留计费、扫描状态自动轮询、离线修改队列、幂等重试、409 字段级冲突处理、
账号云项目拉取和换机元数据恢复、预签名直传与失败恢复、政策通知规则与事务 Outbox、7 天账号删除撤回及
过期隔离文件清理。低风险资讯经过证据锁定、独立模型多轮复核与服务端确定性规则后可自动发布；法规、
资格、费用、日期、模型冲突与证据异常自动进入人工队列。最新自动化证据为 Flutter **38 tests**、API 单元
**50 tests**、API 端到端 **37 tests**、爬虫 **65 tests**，并通过后台与 API 生产构建。PDF 编辑器已在
Android 模拟器上使用真实 PDF 完成标注、导出和重新解析验证。

这仍是开发验收基线，不是“已可上架”：生产身份系统、商店服务端核验与沙盒、APNs/FCM 实际投递、独立扫描 Worker、
自研文档 SDK 的双平台真实设备验收、真实 iOS 设备，以及法律/隐私专业复核仍是外部门槛。历史交接见
[`docs/handoff/project-status-2026-08-28.md`](docs/handoff/project-status-2026-08-28.md)。

内容范围和自动审核的当前决策见
[`docs/product/scope-decision-2026-09-01.md`](docs/product/scope-decision-2026-09-01.md)。抓取器只使用登记的官方来源，
遵守 robots 与访问限制；无法透明访问的来源会在来源健康页明确显示，不会伪装浏览器绕过。

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

发布到 App Store 或 Google Play 前，仍必须完成自研文档 SDK 的真实设备语料测试、商店沙盒订阅测试、独立渗透测试，以及澳洲移民法律与隐私专项审查。

PDF 引擎已切换到自研 `document_sdk` `v0.1.0-alpha.4`；评估组件不得进入发布构建，见 [`docs/architecture/adr-011-document-engine-transition.md`](docs/architecture/adr-011-document-engine-transition.md)。剩余发布门槛记录在 [`docs/architecture/commercial-release-gates.md`](docs/architecture/commercial-release-gates.md)。在这些门槛通过前，项目不得标记为可上架。
