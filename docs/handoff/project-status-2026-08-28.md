# Migration Companion 当前工程状态

**日期：** 2026-08-28
**仓库：** `https://github.com/Longao5k/migration-companion`
**范围：** 第一阶段南澳 SA 190/491；不提前扩到全澳洲或其他国家。

## 当前结论

项目已有可重复启动、可构建、可自动验收的第一阶段本地开发版。用户可在不注册时管理本机材料、提醒、附件和
加密完整备份；账号项目具备明确云同步、逐文件上传、安全分享、协作、离线修改队列、幂等重试、字段级冲突选择
和换机元数据恢复。官方内容已从真实 API 获取并离线缓存，运营后台已完成来源、新闻、变更、更正与采集健康闭环。

“第一阶段产品代码的本地可完成部分”已经进入绿色基线，但不得标记为可上架。生产身份、商店、通知、扫描基础设施、
商业文档能力/自研 SDK 替换、双平台真机矩阵和澳洲法律/隐私复核需要产品所有者提供账号、授权、样本或专业签核。

## 2026-08-28 新完成

1. 内容生产闭环：8 个南澳/联邦来源种子；草稿与发布隔离；重要变更人工摘要门；更正留痕；采集健康与证据快照登记。
2. App 内容闭环：动态新闻/变更、离线缓存、刷新/失败/空状态，不再让本地演示内容冒充线上事实。
3. 数据恢复：v2 完整备份在新仓库恢复项目、状态、提醒和附件字节；旧云引用不会随备份导入。
4. 云空间与扫描：已存 + 预留统一计费，超额仍可读/导出/删除；待扫描状态自动轮询。
5. 可靠同步：本机先保存、持久化队列、重启后重试、服务端操作幂等、云端拉取与新设备恢复。
6. 冲突处理：409 后列出字段级差异，备注正文不进入摘要；用户可选择使用云端或保留本机修改重放。
7. 内容后台五个模块连接真实 API，未同步时明确为空，不再展示伪造 demo 数据。
8. 移动端主上传路径改为预签名直传；只持久化会话 ID，不保存短时 URL；完成响应丢失后不会重复上传字节。
9. 账号删除具备 7 天撤回、到期 worker、先清对象再删记录和不含邮箱/文件名的最小 HMAC ledger。
10. 政策通知关注规则已跨设备保存；人工核实与通知 Outbox 同事务提交，去重、超时重领和有限重试已完成。
11. 过期未完成上传会话会同时删除隔离对象和数据库记录，真实 MinIO 删除已纳入端到端验收。

## 当前绿色证据

```text
Flutter analyze              0 issue
Flutter tests                21 passed
Flutter Web release          built
Android Release APK          built, 243.2 MB
API unit tests               4 passed
API end-to-end               29 passed
Admin build/lint             passed
Next.js web build/lint       passed
Crawler tests                7 passed
pnpm production audit        0 known vulnerabilities
Fresh DB migrate deploy      7 migrations applied
Local endpoints              53001/53002/53003/53004 all HTTP 200
```

可视化验收：内容后台五个导航模块均成功加载；Flutter Web release 在 390×844 容器正常首帧；Android 模拟器
完成安装、启动和动态内容加载，App 进程无崩溃。首次冷启动约 25 秒，主要来自当前 389 MB 评估 PDF SDK。

## 下一位执行者不要重做

- 不要替换 Flutter 或改全局 Flutter。版本固定 **Flutter 3.47.1 / Dart 3.13.1**，只用 `fvm flutter` / `fvm dart`。
- 不要把 `DEV_AUTH`、`DEV_AUTO_SCAN`、`LOCAL_SANDBOX` 或本地后台密钥当作生产实现。
- 不要绕过内容人工审核、附件显式同意、对象级权限或 409 用户选择。
- 不要把社区版/评估版文档组件带入公开测试或商店构建；业务层只依赖既有 document engine interface。
- 不要提前扩地域。第一阶段仍是 SA 190/491 与必要联邦上游。

## 剩余工作分组

### 可继续在本仓库推进

- 自研文档 SDK 就绪后经现有适配器接入并重跑文档矩阵。
- 生产资源到位后补 IaC、运行手册、SBOM、性能/渗透测试与真实设备证据。

### 外部依赖，不能伪造通过

- Cognito/AWS Sydney dev/staging/prod 资源与生产域名。
- Apple Developer、Google Play Console、商品、税务/收款资料和两端沙盒。
- APNs/FCM 实际投递、设备 token 生命周期、App Store Server API/Notifications V2、Google Play Developer API/RTDN。
- 自研 SDK 完成，或 Apryse/ONLYOFFICE 明确商业分发授权；DOCX/PDF 各 30 个代表性样本。
- 独立病毒扫描 Worker、WAF/rate limit、备份恢复与事件响应演练。
- iPhone/iPad 和主流 Android 真机矩阵。
- 澳洲合资格专业人士对移民协助边界、Privacy Act/APP/NDB、抓取版权、隐私/条款/订阅与商店披露的签核。

## 本地运行

```powershell
.\scripts\start-local.ps1
```

- App Web：`http://127.0.0.1:53004`
- 安全分享：`http://127.0.0.1:53003`
- 内容后台：`http://127.0.0.1:53002`，本地开发密钥 `local-admin`
- API：`http://127.0.0.1:53001/v1`

停止：

```powershell
.\scripts\stop-local.ps1
```

完整验收入口与产品经理/技术总监签核见 [`../review/stage-gate-log.md`](../review/stage-gate-log.md)。
