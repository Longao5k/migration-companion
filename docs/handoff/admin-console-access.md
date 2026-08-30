# 管理后台怎么登录

## 一次性设置：建你的后台账号

后台签名密钥已在服务器上生成（`ADMIN_JWT_SECRET`，与内测密钥独立）。还差你的账号：

**第一步**，在本机生成密码哈希——密码明文不出你的机器，服务器上只存哈希：

```bash
pnpm --filter @migration-companion/api admin:hash-password -- 你的邮箱 你的密码
```

密码至少 12 位。这个账号能向所有用户发布政策内容，别用你在别处用过的密码。

**第二步**，把输出（形如 `you@example.com=<salt>:<hash>`）写进服务器 `.env`：

```bash
ssh tencent-light "cd ~/migration-companion/infra/server && printf 'ADMIN_LOGIN_CREDENTIALS=%s
' '粘贴上一步的输出' >> ./.env && docker compose up -d api"
```

连错 5 次会锁 15 分钟。这个计数和 App 的内测登录是分开的——在 App 上输错密码不会
把后台锁死。

## 每次要用后台时

**第一步，开隧道。** 开着别关，用完 Ctrl+C：

```bash
ssh -N -L 53202:127.0.0.1:53102 tencent-light
```

本地端口特意用 **53202** 而不是 53102。踩过一次坑：本机 Docker Desktop 上跑着同一套
服务的旧容器，占了 5310x 段的端口，隧道看起来通了，其实浏览器连的是本机那份旧数据——
排查了很久才发现。本地端口和服务器端口错开，就不会有这种误判。

**第二步**，浏览器打开 `http://127.0.0.1:53202`，用上面建的邮箱和密码登录。

会话 8 小时后过期，token 只存在页面内存里，刷新要重新登录。后台能发布政策内容，
不该因为忘了关标签页就一直是登录态。

## 还没做，上公网前必须补

后台现在**仍然只监听回环**。要放到 `admin.migration-companion.…` 子域名上，
还差两件事：

1. **TOTP 二次验证**。单管理员加强随机密码加锁定，在隧道后面够用；挂到公网上，
   密码是唯一凭据就太薄了。
2. **审计**。`AuditEvent` 模型有，但后台的发布/撤下操作还没写进去。
   守卫已经把管理员邮箱放进了请求上下文（`request.adminEmail`），差的是写入。

## 后台能做什么

| 页签 | 用途 |
| --- | --- |
| 待审核 | 采集器发现的页面变化。重大/重要**不会自动发布**，必须在这里写中文摘要再「核实并发布」 |
| 已发布内容 | 新闻列表。草稿会标「草稿」，点「发布」才进 App；点「撤下」可以收回 |
| 编辑新闻草稿 | 手写一条新闻，可选「保存后立即发布」 |
| 来源健康 | 每个官方来源上次成功/失败时间——App 里那句「有部分页面监控不到」就是从这里来的 |

## 封闭测试期间每天要做的一件事

进「待审核」看有没有新的变化，有就写摘要发布。**这条链路没有自动化**：
重要政策变更在人工核实前不会出现在 App 里，没人核就永远不出现。

顺带看一眼「已发布内容」里的草稿——采集器抓到新闻会自动建草稿，但同样要人点发布。

## 排查

| 现象 | 原因 |
| --- | --- |
| 浏览器打不开 | 隧道没开，或本地端口被占。换一个本地端口重开 |
| 「后台身份验证失败」 | 密钥输错，或服务器上 `ADMIN_API_KEY` 变了 |
| 页面出来但列表空 | 密钥还没输——顶部输入框留空时不会发请求 |
| 隧道连不上 | `ssh tencent-light` 单独能不能通；不通是 SSH 配置或密钥问题，与后台无关 |

---

## 2026-08-29：历史政策回填后要做的一次性工作

采集器补进了南澳官网 **2024-07 至今的 31 条**新闻，其中 26 条是草稿。
我已经为其中 **18 条政策类**写好中文标题和摘要（存档在
`docs/content/sa-news-backfill-editorial-2026-08-29.json`），但**没有发布**——
发布是人工闸门，该由你按一遍。

进「已发布内容」页签，草稿会标「草稿」。逐条看一眼中文摘要对不对得上官方原文，
对了点「发布」。

**剩下 8 条我故意没写文案**，都是已经过期的一次性活动，现在发出去只是噪音：

- Skilled Migrants: Bridging the ICT Skills Gap（2024 年 8 月的活动）
- Skilled and Business Migration Office holiday closure（2024 年圣诞闭馆）
- Move to South Australia Roadshow in the UK（2025 年 10 月已结束）
- Careers: Made in SA November 2025
- Career Compass ×3（2025 年 10/11/12 月场次）
- Event: Welcome to South Australia - November 2025

要发的话自己写中文摘要即可；不发就留着，它们不会出现在 App 里。

### 以后还要不要再跑回填

不用。回填是一次性的，日常发现会接着往前走。只有在**南澳官网改版**导致列表页结构
变化时才需要重跑，命令是：

```bash
docker exec -w /worker -e PYTHONPATH=/worker migration-companion-crawler-1 \
  python -m migration_crawler --source sa-news --state-dir /data/evidence --backfill --dry-run
```

先 `--dry-run` 看会补哪些，确认无误再去掉这个参数。重复跑是安全的：按 `sourceUrl`
去重，已有的条目只更新发布时间，不会产生重复，也不会覆盖你写好的中文文案。
