# 管理后台怎么登录

## 一次性设置：建你的后台账号

**在服务器上跑一次，没有额外脚本。** 把 `你的邮箱` 换成真实邮箱，密码会提示输入（不回显）：

```bash
cd ~/migration-companion/infra/server && read -rsp "密码: " P && echo && docker compose exec -T -e A_EMAIL="你的邮箱" -e A_PASS="$P" api node -e '
const{PrismaClient}=require("@prisma/client");const{randomBytes,scryptSync}=require("crypto");
const s=randomBytes(16),h=s.toString("hex")+":"+scryptSync(process.env.A_PASS,s,32).toString("hex");
new PrismaClient().adminUser.upsert({where:{email:process.env.A_EMAIL},create:{email:process.env.A_EMAIL,passwordHash:h},update:{passwordHash:h,disabled:false}})
.then(()=>console.log("已写入",process.env.A_EMAIL)).catch(e=>{console.error(e.message);process.exit(1)});
' && unset P
```

密码至少 12 位（服务端的 DTO 会拒绝更短的）。改密码就把同一条再跑一遍。

**停用账号**（保留审计指向，不删）：

```bash
cd ~/migration-companion/infra/server && docker compose exec -T api node -e 'new (require("@prisma/client").PrismaClient)().adminUser.update({where:{email:"你的邮箱"},data:{disabled:true}}).then(()=>console.log("已停用"))'
```

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
| 资讯审核 | 低风险稿由自动编辑器发布；高影响或持续冲突的稿件在这里人工核对。历史新闻和法规原始记录单列为「历史/参考」，不占人工待办 |
| 编辑新闻草稿 | 手写一条新闻，可选「保存后立即发布」 |
| 来源健康 | 每个官方来源上次成功/失败时间——App 里那句「有部分页面监控不到」就是从这里来的 |

## 封闭测试期间每天要做的一件事

进「待审核」看有没有新的重要页面变化，再到「资讯审核」只处理标为「需人工复核」的稿件。
自动编辑器会对普通官方资讯完成中英起草与三轮独立复核；纯模型冲突还会带反馈自动重写一次。
涉及资格、期限、费用、项目开关等高影响主题，或重写后仍冲突的内容，才会留给人工。

「历史/参考」不属于待办：超过 15 个月的旧闻和法规原始记录保留用于检索与变化监控，
默认不进入当前资讯流。若确实要发布其中某条，必须打开编辑、人工核对并保存后再发布。

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
