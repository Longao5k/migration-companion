# 单环境服务器部署

第一阶段使用一套公网运行环境，不另建 dev/prod 数据库。`NODE_ENV=production` 只负责关闭开发身份伪造、自动扫描和沙盒购买等危险开关，并不代表维护第二套环境。

对外**只需要一个 DNS 记录**：产品域名同时承载公开网页（隐私政策、条款、安全分享接收页、协作邀请页）与 `/v1` API。
后台控制台只监听服务器回环地址，通过 SSH 隧道访问，不暴露公网。

> 原设计还需要第二个「文件域名」承载 MinIO 的签名上传/下载。由于用户文件将来放到**澳洲区域的 AWS S3**，
> 预签名地址由 AWS 域名签发，因此不需要自建文件域名；迁移到 S3 时可以把 MinIO 一并从部署中移除。

## 首次部署

1. 在服务器上运行 `bash infra/server/bootstrap-env.sh <访问码条目文件>` 生成 `.env`：所有密钥用本机 `openssl` 生成，
   文件权限 600，已存在时不会覆盖（避免重跑换掉数据库密码导致既有数据卷打不开）。

   内测访问码**逐邮箱绑定**：每个内测用户在本机运行一次
   `pnpm --filter @migration-companion/api pilot:hash-code -- <邮箱> <访问码>`，
   把输出（形如 `alice@example.com=<salt>:<hash>`）用逗号或换行拼接后写入 `PILOT_ACCESS_CODES`；
   访问码明文另行分渠道发给本人，不要写进服务器。

   > 不要退回到单一共享访问码。共享码等于任何持码人都能登录成其他内测用户的邮箱，读取对方的护照、
   > 银行和健康材料。服务端已拒绝旧的 `PILOT_ACCESS_CODE_SCRYPT` 配置并返回明确错误。
   > 内测身份是过渡方案，最终形态仍是冻结决策里的邮箱一次性验证码/登录链接。
2. 域名：在 DNS 服务商添加一条 A 记录指向服务器公网 IP。用 Cloudflare 时先保持 **DNS only（灰云）**，
   否则 Certbot 的 HTTP-01 验证会被代理拦下；证书签发后再决定是否开启代理。
   然后把 `migration-companion.nginx.example` 里的示例域名替换为真实域名，保留服务器现有站点，再启用该配置。
3. 在 `infra/server` 运行 `docker compose build --no-cache`，然后 `docker compose up -d`。API 会先执行已提交的 Prisma migrations 和幂等内容来源初始化。
4. DNS 生效后用 Certbot 申请 HTTPS；App 只使用 HTTPS 地址。
   证书就绪后把 `.env` 里的 `PUBLIC_WEB_URL`、`PUBLIC_API_URL`、`APP_ORIGIN`、`SHARE_ORIGIN` 从回环地址改成正式域名
   （`bash infra/server/set-env-var.sh <KEY> <VALUE>`），再 `docker compose up -d api web`。

## 常用脚本

| 脚本 | 用途 |
| --- | --- |
| `bootstrap-env.sh <条目文件>` | 首次生成 `.env`，密钥在服务器本机用 `openssl` 生成；已存在时不覆盖。 |
| `set-pilot-codes.sh <条目文件>` | 写入/替换逐邮箱绑定的内测访问码，只接受哈希条目。 |
| `set-env-var.sh <KEY> <VALUE>` | 安全地设置单个变量（会清理被 shell 转义弄坏的残留行）。 |
| `maintenance.sh` | 容器内循环：清理过期上传会话、执行到期账号删除。 |

## 云文件开关

`CLOUD_FILES_ENABLED=false` 时服务端**不接收新的云文件上传**（预签名、完成、multipart 三个入口都返回 503），
`/v1/entitlements/me` 会下发 `cloudFileUploads.enabled=false` 和原因，App 据此提前说明“文件只保存在本机”。

关闭只挡新增上传：**既有文件的下载、删除和分享保持可用**——冻结规则要求任何情况下用户都能取回和删除自己的文件。

开放云存储时需要同时具备：澳洲区域的 AWS S3、独立病毒扫描 Worker（否则文件会永远停在 `PENDING`，
既不能下载也不会出现在分享里），以及跨境/数据驻留评审结论。

## 自动资讯编辑

`editorial` 服务从 API 领取已保存官方原文的待处理资讯，先生成中英文稿，再用不同模型家族进行 3–5 轮独立复核。
服务器而不是模型决定是否发布：只有低风险、证据一致且无阻断项的内容会自动发布；法规、资格、材料、费用、
日期、模型冲突及其它高风险内容进入后台人工队列。所有判断保留在审计记录中。

服务器 `.env` 至少需要 `SUMMARIZER_BASE_URL` 与 `SUMMARIZER_API_KEY`。Key 只能放在服务器环境文件，不得进入
仓库、App 或浏览器。缺少配置时 worker 会持续安全暂停，不会绕过审核发布。透明抓取身份由
`CRAWLER_USER_AGENT` 和 `CRAWLER_CONTACT_URL` 分开配置，避免把网址塞进 User-Agent 后被官方站点拒绝。

## 内测 App 构建

App 的 API/网页地址是**构建期注入**的，默认值是本地开发地址。给内测用户的包必须显式指定正式域名，
否则装上去连的是 `127.0.0.1`，直接连不上。`PILOT_AUTH=true` 才会在登录框里显示内测访问码输入。

```powershell
cd apps\mobile
fvm flutter build apk --release `
  --dart-define=API_BASE_URL=https://migration-companion-api.infinite-innovation.com/v1 `
  --dart-define=WEB_BASE_URL=https://migration-companion.infinite-innovation.com `
  --dart-define=PILOT_AUTH=true
```

当前内测构建尚未完成正式签名、自研 PDF SDK 的 iOS/Android 真机语料矩阵和商店沙盒验证——只能用于
**封闭内测**，不能上架，也不能公开分发。

后台访问示例：`ssh -L 53102:127.0.0.1:53102 tencent-light`，然后在本机打开 `http://127.0.0.1:53102`。后台密钥只保留在当前浏览器会话内。

数据库、文件和爬虫证据分别存放在命名 Docker volume。社区版 MinIO 使用服务级 `MINIO_API_CORS_ALLOW_ORIGIN` 限定产品域名，不依赖其付费版的逐桶 CORS 功能。部署前后运行 `docker compose ps`、`docker compose logs --tail 100 api crawler`，并验证 `/v1/health`、新闻、登录、上传、分享和删除闭环。
