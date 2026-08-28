# 上架试水指南（Google Play 优先）

**日期：** 2026-08-28
**结论：** Google Play 可达，App Store 本机不可达（需要 macOS）。
**范围：** 第一版按「本机优先 + 只查看文档」的收窄范围试水，不包含 PDF 编辑与云文件上传。

---

## 0. 先做这一件事：Google Play 的 14 天封闭测试

**这是整条路上最长的日历时间，其它都能并行，只有它不能压缩。**

Google 对 2023 年 11 月之后创建的**个人开发者账号**要求：申请正式发布权限之前，
必须先跑一轮封闭测试——**至少 12 名测试者持续加入满 14 天**。人数掉下去会重新计时。

所以顺序是：注册账号 → 建应用 → 传一个能装的包 → 拉满 12 个测试者 → **等 14 天** →
才能申请 production。你在等的这两周里，我们继续把功能补完。

先去做：

1. 注册 [Google Play Console](https://play.google.com/console)，**US$25 一次性**。
2. 完成**个人开发者身份验证**（证件 + 地址）。这一步 Google 可能要几天。
3. 现在就开始凑 12 个测试者的 Google 账号邮箱——朋友、同事、备用账号都行，
   但必须是真实 Google 账号且要保持加入状态。

---

## 1. 签名密钥（你自己生成并保管）

代码侧已经接好：`android/key.properties` 存在时用它签名，不存在时回落 debug。
该文件与 `*.jks` 已加入 `.gitignore`，不会进版本库。

在 `apps/mobile/android/` 目录下执行：

```bash
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

然后新建 `apps/mobile/android/key.properties`：

```properties
storePassword=你设置的口令
keyPassword=你设置的口令
keyAlias=upload
storeFile=upload-keystore.jks
```

> **丢了这个密钥，就再也无法向 Google Play 更新同一个应用**（除非启用 Play App Signing
> 并走密钥重置流程）。请备份到密码管理器或离线介质，不要只留在这台电脑上。
> 建议在 Play Console 打开 **Play App Signing**，这样即使 upload key 丢失也能重置。

## 2. 构建上传包

Google Play 只收 **App Bundle（.aab）**，不收 APK：

```bash
cd apps/mobile && fvm flutter build appbundle --release --dart-define=API_BASE_URL=https://migration-companion-api.infinite-innovation.com/v1 --dart-define=WEB_BASE_URL=https://migration-companion.infinite-innovation.com --dart-define=PILOT_AUTH=true
```

产物在 `build/app/outputs/bundle/release/app-release.aab`。

---

## 3. Data safety 表单（按实际代码填，别猜）

Google 下架的常见原因就是这张表跟实际行为对不上。以下是**核实过的现状**：

**没有的东西**（可以放心勾"否"）：

- 没有任何分析 SDK、崩溃上报 SDK、广告 SDK（依赖清单里 Firebase / Crashlytics / Sentry / 友盟等全部为零）
- 不收集位置、通讯录、短信、通话记录、设备标识符
- **不上传用户的材料文件**（`CLOUD_FILES_ENABLED=false`，服务端直接拒绝新增上传）

**Android 权限只有两个**：`INTERNET`、`RECEIVE_BOOT_COMPLETED`（重启后恢复用户自己设的提醒）。
通知权限由 `flutter_local_notifications` 在 Android 13+ 合并进清单，只在用户主动设置提醒时请求。

**确实收集的**：

| 数据 | 是否收集 | 是否传输 | 用途 | 能否删除 |
| --- | --- | --- | --- | --- |
| 邮箱地址 | 是（登录时） | 是 | 账号功能 | 是，App 内与网页均可发起删除 |
| 申请项目与清单（名称、状态、备注） | 仅在用户为该项目开启云同步后 | 是 | 账号功能、跨设备恢复 | 是 |
| 材料文件 | **否** | **否** | — | 只在设备上，用户自行删除 |

**必须提供的链接**（已经上线）：

- 隐私政策：`https://migration-companion.infinite-innovation.com/privacy`
- 使用条款：`https://migration-companion.infinite-innovation.com/terms`
- 网页版删除账号：`https://migration-companion.infinite-innovation.com/account-deletion`

Google 要求提供账号删除的**应用内入口和网页入口**，两个都有。

---

## 4. 商店素材清单

| 项 | 要求 |
| --- | --- |
| 应用图标 | 512×512 PNG，32 位，无透明 |
| 功能图（Feature graphic） | 1024×500 PNG/JPG |
| 手机截图 | 至少 2 张，建议 4–6 张（资讯、追踪、申请、文档） |
| 简短描述 | ≤ 80 字符 |
| 完整描述 | ≤ 4000 字符 |
| 分类 | 工具 或 教育 |
| 内容分级问卷 | 如实填写；无 UGC 时分级很低 |

**文案红线**（冻结规则，写商店描述时必须遵守）：

- 不能出现「官方」「政府认证」「与移民局合作」或任何暗示官方身份的表述
- 不能承诺签证结果、成功率、获批时间
- 不能描述成提供移民建议或代办服务
- 图标和截图里不能出现政府徽章

建议的定位句式：**整理澳洲南澳技术移民的官方信息与你自己的材料清单**——
说清楚是信息整理工具，不是中介。

---

## 5. App Store（本机做不了）

- Apple Developer Program **US$99/年**
- **必须在 macOS + Xcode 上构建和上传**，Windows 无法完成
- 需要一台 Mac，或租用 Mac 云构建服务

建议先把 Google Play 跑通，iOS 等有 Mac 环境时再做。

---

## 6. 上架前仍未解决的事（如实列出）

这些不是"做完了"，是"知道没做"：

1. **没有澳洲合资格专业人士的复核**。冻结文档要求上线前由注册移民代理或移民法律专业人士
   复核产品边界与文案，并由隐私专业人士确认 Privacy Act 适用性。试水发布是你的商业决定，
   但这项没有完成。
2. **服务器在新加坡**，而冻结的数据边界要求澳洲区域。当前不上传材料文件，风险大幅降低，
   但账号邮箱与项目元数据仍在新加坡，属于跨境披露。
3. **身份是内测访问码，不是正式账号体系**。逐邮箱绑定、有失败锁定，但不是邮箱验证码/OIDC。
4. **PDF 只能查看，不能编辑**。评估版 SDK 已按 ADR-011 从发布构建中移除。
5. **iOS 完全未验证**，没有真机矩阵。
