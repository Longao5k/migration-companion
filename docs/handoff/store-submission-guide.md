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

### 2.1 本机已验证到哪一步（2026-08-28）

| 检查 | 结果 |
| --- | --- |
| `fvm flutter build apk --release` | 成功，70 MB |
| `fvm flutter build appbundle --release` | **AAB 已生成**（61 MB），但命令以退出码 1 结束，见下 |
| 合并清单权限 | `INTERNET` / `RECEIVE_BOOT_COMPLETED` / `POST_NOTIFICATIONS` / `VIBRATE` / `ACCESS_NETWORK_STATE` / `com.android.vending.BILLING` |
| 合并清单是否含计费 | 是（有意保留，第一版要卖订阅） |
| AAB 调试符号是否已剥离 | 是，`BUNDLE-METADATA/com.android.tools.build.debugsymbols/` 下三种 ABI 齐全 |

**关于那个退出码 1**：报错文本是「Release app bundle failed to strip debug symbols」，
但真正的原因不是没剥离——AAB 里的 `.sym` 文件是齐的。Flutter 在打完包之后会用
`apkanalyzer` 再核对一遍，而 `apkanalyzer` 属于 **Android SDK Command-line Tools**，
这台机器上没装（`fvm flutter doctor` 里的 `cmdline-tools component is missing`），
核对跑不起来就当成失败了。

修法：Android Studio → Settings → Languages & Frameworks → Android SDK → **SDK Tools**
页签 → 勾选 **Android SDK Command-line Tools (latest)** → Apply。装完再跑一次，
命令会正常以 0 退出。装之前生成的那个 AAB 本身是可用的。

顺带把 `flutter doctor --android-licenses` 也跑一遍。

> **签名**：现在 `android/key.properties` 还不存在，所以 release 包回落到了 **debug 签名**。
> **debug 签名的包 Play 不收**。按下一节生成 keystore 并写好 `key.properties` 之后，
> 必须**重新打一次包**再上传。

---

## 3. Data safety 表单（按实际代码填，别猜）

Google 下架的常见原因就是这张表跟实际行为对不上。以下是**核实过的现状**：

**没有的东西**（可以放心勾"否"）：

- 没有任何分析 SDK、崩溃上报 SDK、广告 SDK（依赖清单里 Firebase / Crashlytics / Sentry / 友盟等全部为零）
- 不收集位置、通讯录、短信、通话记录、设备标识符
- **不上传用户的材料文件**（`CLOUD_FILES_ENABLED=false`，服务端直接拒绝新增上传）

**Android 权限**（这是**合并后清单**的实际结果，不是源码里写了几行）：

| 权限 | 来自 | 用途 |
| --- | --- | --- |
| `INTERNET` | 我们 | 拉取官方资讯与政策变更 |
| `RECEIVE_BOOT_COMPLETED` | 我们 | 重启后恢复用户自己设的提醒 |
| `POST_NOTIFICATIONS` | `flutter_local_notifications` | Android 13+，只在用户主动设提醒时请求 |
| `VIBRATE` | `flutter_local_notifications` | 提醒震动 |
| `ACCESS_NETWORK_STATE` | `in_app_purchase` | 计费库自带 |
| `com.android.vending.BILLING` | `in_app_purchase` | 订阅（第一版出售 PDF / Word 编辑） |

（合并清单里还有一条 `…DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`，是 Flutter 引擎
自定义的签名级权限，不面向用户，表单里不用填。）

> `open_filex` 原本会塞进 `READ_EXTERNAL_STORAGE` 和三个 `READ_MEDIA_*`。我们不读媒体库，
> 已用 `tools:node="remove"` 移除，核对过合并清单确认没了。
> `in_app_purchase` 会塞进 `com.android.vending.BILLING` 和两个 `ProxyBillingActivity`。
> 这是有意保留的（第一版要卖订阅），所以表单的「应用内购买」必须填「是」。
>
> 换依赖或升级后，**上传前用 `aapt2 dump permissions` 重新核对一次**。

清单里还声明了 `<queries>`（打开 https、Custom Tabs、PDF/Word 查看、文本分享）。
Android 11 起没有这几行，「读官方原文」和「打开查看」会解析不到应用而**静默失败**。
这些是定向声明，不需要受限的 `QUERY_ALL_PACKAGES`。

**确实收集的**：

| 数据 | 是否收集 | 是否传输 | 用途 | 能否删除 |
| --- | --- | --- | --- | --- |
| 邮箱地址 | 是（登录时） | 是 | 账号功能 | 是，App 内与网页均可发起删除 |
| 申请项目与清单（名称、状态、备注） | 仅在用户为该项目开启云同步后 | 是 | 账号功能、跨设备恢复 | 是 |
| 材料文件 | **否** | **否** | — | 只在设备上，用户自行删除 |
| 项目讨论留言 | 仅在用户为该项目开启云同步后 | 是 | 账号功能、协作 | 是，随项目删除 |

**材料文件那一行有个必须说清楚的例外**：文件本身不上传，但用户点「打开查看」时，
App 会复制一份工作副本交给设备上的其他应用（系统 PDF/Word 阅读器）。Data safety 里
这属于**用户主动发起的、向其他应用的分享**，不是我们的数据收集，但你在描述里要写出来，
不要留下「文件绝不离开本 App」这种更强的印象。App 内在打开前也会明说一次。

**必须提供的链接**（已经上线）：

- 隐私政策：`https://migration-companion.infinite-innovation.com/privacy`
- 使用条款：`https://migration-companion.infinite-innovation.com/terms`
- 网页版删除账号：`https://migration-companion.infinite-innovation.com/account-deletion`

Google 要求提供账号删除的**应用内入口和网页入口**，两个都有。

---

## 4. 商店素材清单

| 项 | 要求 |
| --- | --- |
| 应用图标 | 512×512 PNG，32 位，无透明 —— **已生成**：`apps/mobile/store/play-icon-512.png` |
| 功能图（Feature graphic） | 1024×500 PNG/JPG |
| 手机截图 | 至少 2 张，建议 4–6 张（资讯、追踪、申请、文档） |
| 简短描述 | ≤ 80 字符 |
| 完整描述 | ≤ 4000 字符 |
| 分类 | 工具 或 教育 |
| 内容分级问卷 | 如实填写；无 UGC 时分级很低 |

### 名称与图标（已落地）

产品名是 **Waymark**。

### 三个「一次性」标识（首次上传后永久锁定）

这三个在商店里一经创建就改不了——`applicationId` 要改只能建新应用，
商品 ID 删不掉也不能改名。都已经趁未上传定成产品名：

| 标识 | 值 |
| --- | --- |
| Android `applicationId` | `com.waymark.app` |
| iOS bundle id | `com.waymark.app`（RunnerTests 为 `com.waymark.app.RunnerTests`） |
| 月付商品 ID | `waymark_premium_monthly` |
| 年付商品 ID | `waymark_premium_yearly` |

商品 ID 两端必须一致：App 侧在 `subscription_screen.dart`，服务端在
`entitlements.service.ts`（可用 `STORE_MONTHLY_PRODUCT_ID` / `STORE_YEARLY_PRODUCT_ID`
覆盖，服务器 `.env` 目前没有设，走的就是这两个默认值）。对不上的话，
用户买回来的收据校验不过，权益发不出去。

在 Play Console 建订阅商品时，ID 必须逐字符照抄上面这两个。

| 位置 | 内容 |
| --- | --- |
| 桌面/主屏图标名 | `Waymark`（Android `res/values/strings.xml`，iOS `Info.plist` 的 `CFBundleDisplayName`） |
| 商店名称 | `Waymark`，副标题里再补「南澳技术移民信息与材料整理」之类的说明 |
| App 内标题 | `Waymark` |

图标源文件是 **`apps/mobile/assets/brand/app-icon.svg`**（设计稿本身）。
要改图形就改 SVG，然后重跑 `python tool/generate_app_icon.py` 重新出图，
**不要手改 PNG**。

光栅化用 `npx sharp-cli`（sharp 内置 librsvg）。这台机器上没有别的可用渲染器：
cairosvg 装得上但加载不了 cairo DLL，`convert` 是 Windows 自带的磁盘工具而不是
ImageMagick。第一次跑会下载 sharp 的预编译二进制，之后走 npx 缓存。

脚本按平台切分三个变体，不能混用：

| 输出 | 变体 | 为什么 |
| --- | --- | --- |
| Android 旧版位图 `ic_launcher.png` | 满幅 + SVG 自带的 `rx=220` 圆角 | API 24-25 没有自适应图标，用位图本身的圆角 |
| Android 自适应背景层 `ic_launcher_background.png` | 满幅 **方角** | 圆角由系统遮罩决定，自带圆角会被切两次 |
| Android 自适应前景层 `ic_launcher_foreground.png` | 去掉背景矩形，缩进安全区 | 保证可视区是 108dp 画布上直径 66dp 的圆 |
| iOS `AppIcon.appiconset`（19 张） | 满幅 **方角**，压平 alpha | iOS 自己加圆角遮罩；带 alpha 的图标 App Store Connect 直接拒收 |
| Play `store/play-icon-512.png` | 满幅圆角，压平 alpha | 商店要求 32 位无透明 |

前景层的缩放不是拍脑袋定的：脚本量出所有不透明像素到图形中心的**最大距离**，
按它缩到安全半径。用外接矩形的对角线算会白白缩掉一圈。

**没有 `monochrome` 层。** Android 13 的主题图标只取 alpha 通道再上色，而这张图的
信息（地球、对勾、清单行）全画在不透明的白色文档**里面**，取完 alpha 只剩一块实心板
加两道弧线。缺省时系统回落到普通图标，比给一个认不出的好。

**已知取舍：** 这张图的信息密度对启动图标偏高，在 mdpi（48×48）下清单行会糊成噪点。
mdpi 只用于很老的低密度设备，现代机走 xxhdpi/xxxhdpi（144-192px），那个尺寸下是清楚的。

---

**文案红线**（冻结规则，写商店描述时必须遵守）：

- 不能出现「官方」「政府认证」「与移民局合作」或任何暗示官方身份的表述
- 不能承诺签证结果、成功率、获批时间
- 不能描述成提供移民建议或代办服务
- 图标和截图里不能出现政府徽章

建议的定位句式：**整理澳洲南澳技术移民的官方信息与你自己的材料清单**——
说清楚是信息整理工具，不是中介。

**截图与描述里不能出现的东西**（都是这个构建做不到的，出现即为虚假宣称）：

- 订阅、Premium、7 天试用、价格——入口尚未开启（等 PDF / Word 编辑上线），现在不能宣传
- PDF/Word 的编辑、批注、签名、表单填写、页面整理——这一版只能查看
- 云端上传、云端备份——`CLOUD_FILES_ENABLED=false`，上传入口是关的

截图只截真机上跑出来的界面。用设计稿或早期版本的截图，等于用做不到的功能拉安装。

---

## 4.1 审核访问权限（Play Console「应用访问权限」必填）

App 的资讯、政策变更、文档工具和本机材料清单**不需要登录**，但协作和分享需要。
表单里要按这个填：

- 选择「部分功能受限」
- 说明：主要内容无需登录即可访问；协作与分享功能需要内测访问码
- 提供一组**专供审核使用**的邮箱 + 访问码（用 `set-pilot-codes.sh` 单独生成一条，
  不要复用真实测试者的），并写明有效期

**应用内购买：按你上传的那个包填，不要按计划填。**

第一版的定位是靠订阅出售 PDF / Word 编辑，所以计费依赖留在代码里，合并清单会带上
`com.android.vending.BILLING`。但**订阅入口目前是关的**（`subscriptionsEnabled` 默认 false），
因为编辑能力还没接进来——权益不存在就开卖，既违反商店计费政策，也踩澳洲消费者法。

于是有两种包，填法不同：

| 你上传的包 | 「应用内购买」 | 商店描述与截图 |
| --- | --- | --- |
| 现在这种（不带 `--dart-define=SUBSCRIPTIONS=true`） | **是** | 不能出现订阅、试用、价格、编辑 |
| 编辑上线后（带 `SUBSCRIPTIONS=true`） | **是** | 可以，且必须与实际权益一致 |

两种都填「是」：清单里有 `BILLING` 权限，声明「无内购」会对不上。区别在于**描述和截图**——
在编辑能力真正可用之前，商店页面不能宣传订阅或编辑，否则就是卖一个买不到也用不了的东西。

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
4. **PDF 和 Word 只能查看，不能编辑**。评估版 SDK 已按 ADR-011 从发布构建中移除。
   打开文件的方式是：复制一份工作副本 → 交给系统里能打开它的应用。这意味着
   **文件会离开本 App，进入第三方阅读器**，那个应用可能有自己的云同步。App 内在
   打开前会明说这一点，Data safety 表单也要按「由用户主动分享给其他应用」如实描述。
   工作副本 24 小时后自动清理。
5. **iOS 完全未验证**，没有真机矩阵。
6. **联邦内政部的三个页面抓不到**（边缘 403，非 robots 限制）。我们不做 UA 伪装、
   无头浏览器或 IP 轮换绕过。替代做法：监控 Migration Act 1958 与 Migration
   Regulations 1994（法条本身），并在 App 里如实显示「联邦有部分页面监控不到」。
7. **政策变更需要两轮抓取才会出现**。首轮只建立基线，没有可比对的旧版本。
   新加来源上线后至少要等一个抓取周期，变更列表才可能有内容。
8. **重要变更在人工核实前不发布**。App 的空列表会显示「有 N 条改动正在核对」，
   但这条链路依赖有人真的去后台核。封闭测试期间这件事需要你自己每天做一次。
