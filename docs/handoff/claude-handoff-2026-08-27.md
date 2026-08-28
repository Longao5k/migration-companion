# Migration Companion 工程交接（给 Claude）

> 本文是 2026-08-27 历史交接快照。2026-08-28 的续建结果、当前绿色证据和剩余外部门槛已迁移到
> [`project-status-2026-08-28.md`](project-status-2026-08-28.md)，后续以新文件为准。

**交接日期：** 2026-08-27  
**最近更新：** 2026-08-27（续建：P0-A 完成、P0-D 部分完成）  
**项目目录：** `C:\Users\longa\Dev\migration-companion`  
**当前结论：** 已形成可本地运行的端到端开发版和 Android Debug APK，但**尚未达到产品经理定义的“第一阶段完成”或应用商店可发布状态**。请从本文的未完成清单继续，不要重新做已经验证的底座。

## 0. 本次续建的变化（先读这一节）

每个交付门的产品经理与技术总监评审记录在 [`docs/review/stage-gate-log.md`](../review/stage-gate-log.md)。

已完成：

- **P0-A 全部完成。** 手工 API 验收已固化为 21 条自动化端到端验收（`.\scripts\test-local-e2e.ps1`）；
  `test:e2e` 配置补齐；Web release 在真实 Chrome 的 390x844 视口复测通过，未复现 loader 停滞。
- **P0-D 的管理界面完成。** App 内新增“云端与协作管理”（云文件 / 安全分享 / 协作三个页签）；
  安全分享创建可选择已扫描云文件；“直接发送副本”会把选中的本机文件交给系统分享面板。

同期修复的真实缺陷（都有回归测试或验收覆盖）：

1. `GET /v1/projects/:projectId` 在项目含文件时返回 500（BigInt 无法序列化）。
2. 分享面板弹出的后续流程使用了已被 `Navigator.pop` 卸载的 `BuildContext`，
   导致“创建安全分享入口”静默失败：既不创建入口，也不报错。
3. PowerShell 脚本缺 UTF-8 BOM，在 Windows PowerShell 5.1 下直接语法报错。
4. `scripts\start-local.ps1` 硬依赖 `pwsh`；未安装 PowerShell 7 的机器无法启动本地环境。
5. `APP_ORIGIN` 缺少 Flutter Web 预览来源，网页版所有 API 调用被 CORS 拒绝。
6. `FileRecord` 没有上传者字段，无法执行“可协作成员不能删除他人文件”的冻结权限规则。

## 1. 最高优先级约束

1. Flutter 固定为 **3.47.1 / Dart 3.13.1**，配置在根目录 `.fvmrc`。只允许使用 `fvm flutter ...`、`fvm dart ...`。禁止运行 `flutter upgrade`、`flutter channel`、`fvm global`，禁止修改用户全局 Flutter 或 PATH。
2. 第一阶段只做南澳（SA）190/491 及必要的联邦上游信息。第二阶段才扩全澳洲，之后才是热门移民国家。不要提前扩范围。
3. 产品是高敏感材料工具：注册不等于允许上传；云同步按项目明确开启；附件按文件明确上传；日志、通知和分析不得出现文件名、正文、证件号、访问码或材料细节。
4. 不提供个案资格判断、签证路径推荐、政府表格答案建议、代填或代递交。所有政策内容必须可回到官方来源。
5. 当前免费/试用文档组件只用于本地开发和内部验收。公开测试或商店发布前必须用自研 SDK 替换，或另行获得明确商业授权。
6. 不要把 Debug 本地邮箱模拟、开发扫描模拟、演示内容或未连接的 DOCX 适配器描述为生产完成。

必读文件：

- `docs/product/product-manager-review.md`：冻结的 P0 与验收口径。
- `docs/architecture/technical-director-review.md`：整体架构与安全边界。
- `docs/architecture/commercial-release-gates.md`：不可绕过的商业/法律/商店门槛。
- `docs/architecture/adr-011-document-engine-transition.md`：文档引擎替换路线。
- `docs/architecture/self-built-document-sdk-agent-brief.md`：另一个 Agent 开发自研 SDK 的任务书。

## 2. 本地运行

从项目根目录执行：

```powershell
.\scripts\start-local.ps1
```

启动后：

- App 网页预览：`http://127.0.0.1:53004`
- 无 App 安全分享网页：`http://127.0.0.1:53003`
- 内容运营后台：`http://127.0.0.1:53002`
- API：`http://127.0.0.1:53001/v1`
- API 健康检查：`http://127.0.0.1:53001/v1/health`
- 本地后台密钥：`local-admin`
- App Debug 登录示例：`owner@example.com`（只在 `DEV_AUTH=true` 下生效）

停止：

```powershell
.\scripts\stop-local.ps1
```

停止脚本只停止本项目记录的进程并执行 Docker `stop`，不会删除 PostgreSQL/MinIO 数据卷。

运行 API 端到端验收（会自行启动容器、同步结构、准备文件桶）：

```powershell
.\scripts\test-local-e2e.ps1
```

构建并预览 Web release，附带固定 390x844 手机视口检查页：

```powershell
.\scripts\preview-web-release.ps1
```

环境要求补充：

- 脚本不再假设本机装有全局 `pnpm`，会退回 Node 自带的 corepack；如果本机 corepack 过旧而无法验证 npm
  签名密钥，脚本会明确报错并列出三种修复方式，其中“跳过签名校验”必须由操作者显式选择，脚本不会默认关闭。
- 脚本不再硬依赖 `pwsh`，未安装 PowerShell 7 时退回 Windows PowerShell 5.1。
- 所有 `.ps1` 必须保持 **UTF-8 with BOM**：无 BOM 时 Windows PowerShell 5.1 按 ANSI 读取，中文字符串会破坏解析。

只启动后端/网页而跳过 Flutter Web：

```powershell
.\scripts\start-local.ps1 -SkipMobileWeb
```

Android 模拟器：先启动本地服务，再执行：

```powershell
cd apps\mobile
fvm flutter run
```

Android 默认访问 `10.0.2.2:53001`；真机需用 `--dart-define=API_BASE_URL=...` 和 `--dart-define=WEB_BASE_URL=...` 指向电脑局域网地址。

## 3. 已完成并验证的部分

### 3.1 产品、架构与 UI

- 原始 PRD 已移动到 `docs/product/澳洲移民申请管理App_第一阶段产品需求文档.docx`。
- 产品经理与技术总监分别完成独立评审、范围冻结和签核文件。
- 已完成 Flutter 主界面：资讯、Change Log、材料项目、文档工具、个人/订阅。
- 设计预览位于 `docs/design/previews/`。
- Next.js 提供隐私、条款、账号删除说明、安全分享接收页与协作邀请页。
- Vite/React 内容后台具备审核队列界面和 API 连接入口。

### 3.2 Flutter 本地工作区

- 访客无需账号可创建 SA 190、SA 491 或空白项目。
- 项目、清单、五段状态、备注、目标日期、系统提醒、附件、搜索/状态筛选、本地操作记录已经接入。
- 本地结构化数据使用 SQLCipher；密钥由 `flutter_secure_storage` 保存；不支持原生插件的测试/Web 环境才退回 SharedPreferences。
- 附件复制进 App 私有目录，记录 MIME、大小和 SHA-256；同一材料项可关联多个附件。
- 网页预览明确禁用敏感附件持久保存，不能把 Web 当成正式移动文件库。
- 加密备份采用 PBKDF2-HMAC-SHA256（210,000 次）+ AES-256-GCM；v2 备份包含附件字节和校验，恢复时逐个验证。仍兼容旧 v1 纯项目备份。
- 资讯搜索、标签/来源文本检索、收藏本机持久化和系统分享已接入。
- 系统提醒使用 `flutter_local_notifications 22.3.0` + `timezone 0.11.1`，只在用户主动设置时请求权限；Android 使用非精确提醒，避免申请高风险 exact-alarm 权限；锁屏文案不含材料名称。
- 账号登录后仍不会自动上传本机文件；云同步按项目确认，附件逐个再次确认。

### 3.3 文档能力

- 已建立可替换接口：`apps/mobile/lib/core/documents/`。
- PDF 接入 `pdftron_flutter 1.0.1-57` 的 Apryse 免费评估适配器；打开前校验 `%PDF-` 文件头，创建 App 自有工作副本后再交给编辑器，避免覆盖原件。
- PDF Android 原生构建已经通过。
- DOC/DOCX 已有元数据预检、大小边界和兼容等级文案；旧 DOC 只读。
- **DOCX 真正编辑会话尚未接入**，当前工具页会明确显示“正在接入服务器端保存副本流程”。不得把它改成虚假成功提示。

### 3.4 API、权限与文件安全

- NestJS 模块化单体 + Prisma/PostgreSQL；本地 MinIO 模拟 S3。
- 项目拥有者/仅查看/可协作三种角色；邮箱定向邀请、7 天 fragment secret、接受、降权、移除、撤销邀请、评论和审计已实现。
- 项目采用乐观版本号；冲突返回 409，不静默覆盖。
- 安全分享默认无选择、7 天、访问码、禁止下载；支持 1/7/14/30 天、撤销、尝试锁定、最近访问时间、60 秒下载 URL。
- 上传支持预签名流程和移动端 multipart 直传流程；最大 50 MB。
- 服务端不只相信扩展名/MIME：会校验 PDF、DOCX ZIP、DOC OLE、JPEG、PNG、HEIC 的 magic bytes。
- 文件先进入 quarantine；只有 `CLEAN` 才能下载/分享。`DEV_AUTO_SCAN=true` 仅在非生产环境模拟 CLEAN，生产必须替换成独立病毒扫描 Worker。
- 免费/试用/Premium 云容量为 1 GB/10 GB；创建上传时计入已存文件与未完成上传，防止超额。
- 下载检查项目成员身份、扫描状态和项目级 viewer 下载开关；仅查看者默认不能下载，所有者明确开启后才允许。

### 3.5 订阅

- Flutter 使用官方 `in_app_purchase 3.3.0`。
- 有 7 天一次性高级试用，明确不会自动转付费。
- 月付/年付商品 ID：`migration_companion_premium_monthly`、`migration_companion_premium_yearly`。
- App 有购买、恢复购买、管理/取消订阅入口；显示当前权益和云存储用量。
- 服务端保存 subscription/entitlement，客户端购买结果不能直接授权；只有服务端 verified event 能变更生产权益。
- Debug 环境有 `LOCAL_SANDBOX` 月/年订阅模拟，用于本地验收，不产生真实扣款。
- 已实现 ACTIVE、GRACE、EXPIRED、REVOKED、REFUNDED 状态写入逻辑。

### 3.6 爬虫与内容审核

- Python 3.13 白名单抓取器位于 `services/crawler`。
- 已有 SSRF 防护、私网/metadata IP 拒绝、官方域名白名单、robots 检查、条件请求、页面规范化、噪声过滤、指纹与差异分类。
- 重大/重要变化只进入人工审核；一般变化可标记“待核实”，不能自动给个案影响判断。
- 当前白名单在 `services/crawler/sources.json`，覆盖南澳和必要联邦 190/491 上游来源。

## 4. 已完成的验收证据

最近一次结果：

- `fvm flutter analyze`：通过，0 issue。
- `fvm flutter test`：12 个测试通过（含云文件状态映射、下载校验、删除保留本机原件、安全分享流程回归）。
- `fvm flutter build apk --debug`：通过。
- Debug APK：`apps/mobile/build/app/outputs/flutter-apk/app-debug.apk`，约 389 MB（评估版 PDF SDK 导致体积很大）。
- `pnpm --filter @migration-companion/api build`：通过。
- API ESLint：通过。
- API Jest：2 suites / 4 tests 通过。
- API 端到端验收（`.\scripts\test-local-e2e.ps1`）：1 suite / **21 tests 通过**。
- Next.js 生产构建与 ESLint：通过；路由包含 `/privacy`、`/terms`、`/account-deletion`、`/s/[shareId]`、`/invite/[invitationId]`。
- Admin TypeScript/Vite build 与 lint：通过。
- Crawler `python -m unittest discover -s tests -v`：7 tests 通过。
- 一键启动脚本实测后，53001、53002、53003、53004 四个入口均返回 HTTP 200。

手工端到端 API 验收已真实跑过：

1. Debug 邮箱账号创建 SA 491 项目。
2. 明确开启项目云文件。
3. 开启 7 天试用，返回 `TRIAL`。
4. 上传真实 PDF，开发扫描返回 `CLEAN`。
5. 登录用户获得短时下载 URL。
6. 创建含清单和文件的安全分享；无账号访问码交换返回 1 个清单项和 1 个文件。
7. 仅查看成员默认下载返回 403；所有者开启项目级下载后成功。
8. 用 PDF 内容冒充 `image/png` 上传返回 400。
9. 协作者可修改清单和发表评论；降级为 VIEWER 后评论返回 403。
10. Debug 月订阅模拟后权益为 `PREMIUM`，恢复购买仍为 `PREMIUM`。

## 5. 尚未完成：按接手顺序推进

### P0-A：先恢复绿色构建并自动化现有手工验收 — **已完成**

1. ~~重新执行所有第 4 节命令~~：已全部通过，Flutter Web release build 也已完成。
2. ~~把手工 API 验收固化~~：已实现为 `services/api/test/acceptance.e2e-spec.ts`（21 条），
   一键入口 `.\scripts\test-local-e2e.ps1`。
3. ~~修复 `test:e2e`~~：已补齐 `services/api/test/jest-e2e.json`，未使用 `--passWithNoTests`。
4. ~~390×844 loader 复测~~：release 产物在真实 Chrome 的 390x844 视口首帧与刷新均正常，
   未复现 loader 停滞；结论是 debug `flutter run -d web-server` 的调试连接问题。
   **仍待办：Android 模拟器复测一次**（Windows 上可做，本次未执行）。

### P0-B：完成真实文档编辑闭环

1. 接入经许可的 ONLYOFFICE Developer 试用服务器：服务端创建短时 editor session/JWT，移动端 WebView 打开，回调保存不可变副本，再关联原材料项。
2. PDF 需要按产品矩阵验证查看、搜索、表单、批注、签名、页面旋转/重排/删除/提取/合并、相机生成、保存副本和重新关联。不能只验证“能打开”。
3. DOCX/PDF 各准备至少 30 个代表性样本；支持矩阵内 100% 通过，矩阵外必须明确只读/失败且保留原件。
4. 自研 SDK 由另一 Agent 完成后，只通过现有 document engine interface 替换，不让 vendor API 泄漏到业务 UI。

### P0-C：生产身份、同步与恢复

1. 当前正式构建没有邮箱验证码/魔术链接页面；后端 Cognito JWT guard 已有，但移动端仍只有 Debug 邮箱模拟。接入 Cognito 邮箱 OTP/OIDC PKCE、安全 token storage 和刷新。
2. 当前云同步主要是“本机创建项目后首次上传 + 单项修改”，没有完整离线队列、断网重试、幂等 operation、服务器拉取、换机恢复和冲突解决 UI。
3. 409 目前只抛错误，没有“拉取新版本 → 展示差异 → 用户选择合并/重试”。
4. 登录账号在新设备上还不能完整列出并恢复云项目/附件。
5. 收藏、关注和提醒尚未跨设备同步。

### P0-D：完成文件、分享与协作 UI — **管理界面已完成，其余待办**

已完成（入口：项目页右上角菜单 →“云端与协作管理”，代码在 `apps/mobile/lib/features/projects/project_cloud_screen.dart`）：

1. ~~“直接发送副本”~~：现在会把选中的本机附件作为 `XFile` 交给系统分享面板，并对发出文件做二次风险提示。
2. ~~安全分享创建选择云文件~~：创建对话框会列出已通过扫描的云文件供逐项选择；读取失败时明确显示原因，
   仍允许只分享清单项。
3. ~~安全分享列表~~：有效/已过期/已撤销状态、到期时间、最近访问时间、内容项数与一键撤销均已接入。
4. ~~协作管理~~：成员列表、角色调整、移除成员、待接受邀请与撤销邀请、讨论列表与发表讨论均已接入。
5. ~~云文件删除、下载到私有目录、扫描状态刷新~~：已接入，删除只删云端副本、保留本机原件；
   下载会校验 SHA-256，不一致时丢弃且不覆盖本机原件。
   **仍待办：原件/编辑副本版本链 UI**（`FileRecord.isOriginal` / `parentFileId` 目前没有写入方，
   需要等 P0-B 的真实编辑闭环）；**扫描状态目前是手动刷新，没有自动轮询**。
6. **仍待办：** multipart 直传会在 API 内存中承载最多 50 MB；生产应优先使用现有预签名直传，
   并解决模拟器/真机可达域名与签名 host 问题。
7. **仍待办：** 云文件与协作界面尚未在 Android 真机/模拟器上验证（本次只在 Chrome Web release 上验证）。

### P0-E：内容与通知生产闭环

1. Flutter 当前使用本地 `SeedData`，尚未从 `/content/news`、`/content/changes` 拉取并做离线缓存/刷新/错误状态。
2. API 缺新闻/来源/标签完整 CRUD 和种子流程；后台只有审核队列，侧边栏其他模块是视觉入口。
3. 爬虫证据目前本地文件化；生产需独立 evidence bucket、不可变快照、抓取健康状态、故障事件和人工审核 SLA。
4. 还没有 APNs/FCM、设备 token、关注规则、Outbox/SQS 和远程政策通知；现在只有用户主动设置的本地材料提醒。
5. 重大/重要变更未经人工确认不得推送；页面故障、验证码、空白响应不能成为政策变更。

### P0-F：真实商店订阅

1. 需要 Apple Developer 和 Google Play Console 的真实应用与商品。
2. 接 App Store Server API / App Store Server Notifications V2，以及 Google Play Developer API / RTDN；验证签名、幂等、账号绑定和重放防护。
3. 在 Apple/Google 沙盒分别验证购买、恢复、续订、billing retry/grace、退款、撤销、过期、换机恢复。
4. 当前 `store-events/verified` 受 Worker key 保护，但它只是内部可信事件入口，不是商店签名验证器。
5. 月/年价格 UI 有 A$ fallback；生产必须以商店返回的本地化价格为准，不把 fallback 当成最终报价。

### P0-G：删除、安全与生产基础设施

1. App 内删除当前只写 `deletionRequestedAt`；缺 7 天主数据清除 Worker、取消/撤回窗口、备份轮换删除证据和最小法律留存 ledger。
2. 公开删除页在未配置正式身份链接时会明确显示上线阻塞；接入 Cognito 身份确认和支持联系方式。
3. 开发扫描模拟必须替换为独立隔离的 ClamAV/等价扫描 Worker；拒绝文件及时删除，错误状态可重试。
4. 分享访问锁定当前依赖数据库字段；生产还需 WAF/分布式 rate limit、告警和滥用监控。
5. 完成 threat model、PIA/数据流图、依赖/秘密扫描、独立渗透测试、备份恢复演练、泄露响应演练。
6. AWS Sydney 基础设施需要 IaC 落地：独立 dev/staging/prod、RDS Multi-AZ、S3/KMS keyspace、ECS、WAF/ALB、SQS/DLQ、Cognito、Secrets Manager、监控和独立备份权限。

### P0-H：商店与法律门槛

发布前必须由用户/运营方提供：法定主体名称、联系邮箱、支持渠道、域名、数据负责人、保留期、Apple/Google 开发者账号、AWS 账号和文档 SDK 授权/自研替换结果。

必须由澳洲合资格专业人士复核：

- 移民协助/法律意见边界及所有产品文案。
- Privacy Act / APP、跨境披露、NDB 数据泄露响应和实际小企业豁免适用性。
- 南澳/联邦页面抓取、证据留存、引用和版权。
- 隐私政策、条款、订阅/退款说明、Apple App Privacy 和 Google Data safety。

未经上述复核，不得标记为可上架。

## 6. 关键代码位置

| 领域 | 路径 |
| --- | --- |
| Flutter 状态/业务 | `apps/mobile/lib/core/state/app_store.dart` |
| 本地模型 | `apps/mobile/lib/core/models/models.dart` |
| SQLCipher KV | `apps/mobile/lib/core/storage/local_repository_native.dart` |
| 私有附件 | `apps/mobile/lib/core/storage/attachment_storage_native.dart` |
| 加密备份 | `apps/mobile/lib/core/backup/backup_codec.dart` |
| 系统提醒 | `apps/mobile/lib/core/notifications/` |
| 材料/分享 UI | `apps/mobile/lib/features/projects/projects_screen.dart` |
| 订阅 UI | `apps/mobile/lib/features/subscription/subscription_screen.dart` |
| 文档适配器 | `apps/mobile/lib/core/documents/` |
| API 项目/锁 | `services/api/src/projects/` |
| API 文件 | `services/api/src/files/` |
| API 安全分享 | `services/api/src/shares/` |
| API 协作 | `services/api/src/collaboration/` |
| API 订阅 | `services/api/src/entitlements/` |
| Prisma 模型/初始迁移 | `services/api/prisma/` |
| App 云端/协作管理 UI | `apps/mobile/lib/features/projects/project_cloud_screen.dart` |
| API 端到端验收 | `services/api/test/acceptance.e2e-spec.ts` |
| 评审门记录 | `docs/review/stage-gate-log.md` |
| 无 App 分享/邀请 | `apps/web/src/app/s/`、`apps/web/src/app/invite/` |
| 内容后台 | `apps/admin/src/App.tsx` |
| 抓取器 | `services/crawler/migration_crawler/` |
| 一键启动/停止 | `scripts/start-local.ps1`、`scripts/stop-local.ps1` |

## 7. 当前工作树注意事项

- 仓库目前没有已提交基线；`git status` 中项目文件全部为 untracked。接手后先检查文件，再建立第一次有意义的提交，不要使用 `git reset --hard` 或清理未跟踪文件。
- `.local/` 已加入 `.gitignore`；其中是本地进程状态和日志，不要提交。
- Docker 数据卷保留此前的手工 E2E 测试账号、项目和文件；这些都是合成测试数据。
- Android release 仍使用 debug signing；正式 package/bundle ID 已初步设为 `com.migrationcompanion.migration_companion`，但最终所有权与商店可用性必须由产品所有者确认。
- Windows 无法完成 iOS build/真机测试；必须在 macOS/Xcode 上补齐。

## 8. 建议接手执行顺序

1. 停止当前服务（如仍运行），阅读第 1 节文件，执行全套构建与测试。
2. 修复/自动化 E2E，并解决 390×844 Flutter Web loader 复测问题。
3. 完成云端拉取、离线队列、冲突 UI、分享/协作管理和文件版本链。
4. 接入 ONLYOFFICE 试用闭环并完成 PDF/DOCX 样本矩阵；随后准备自研 SDK 替换。
5. 完成动态内容/API/后台/通知流水线。
6. 有真实账号与凭据后接 Cognito、Apple/Google 沙盒、AWS Sydney IaC。
7. 最后做安全、法律、隐私和双商店验收；所有门槛过后，产品经理与技术总监再次签署“第一阶段完成”。

不要用“页面存在”“本地沙盒成功”或“代码路径已预留”替代 P0 验收。当前工程的价值是已经把本地优先、权限、上传、分享、订阅和未来 SDK 替换的边界搭好；接下来的核心工作是把外部依赖和剩余操作闭环变成真实、可重复的验收结果。
