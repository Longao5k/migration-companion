# 自研 PDF/DOCX SDK：AI Agent 实施工件

## 目标

建立一个独立、可公开发布并可被 Flutter/iOS/Android 引入的文档 SDK。核心引擎不引入 PDFium、qpdf、LibreOffice、ONLYOFFICE、Apryse、MuPDF 或其他文档引擎源码；按照 PDF 与 ECMA-376/OOXML 公开格式，自行实现第一阶段所需子集。

目标是复刻本产品需要的行为，不承诺复制任一商业产品的商标、UI、私有 API、未公开实现或完整功能集合。

## AI Agent 时间模型

以下估算假设：

- 6–10 个 Agent 可并行、持续运行；
- 每个 Agent 有独立任务边界、共享规范、可执行测试和合并负责人；
- Android 模拟器可自动运行；iOS 编译和真机测试有可用 Mac；
- 第一版只支持冻结的 PDF P0 与“简单 DOCX”兼容档位；
- 未支持结构必须只读或拒绝保存，不允许静默损坏。

| 里程碑 | 并行 Agent 工时 | 预计墙钟时间 | 完成定义 |
|---|---:|---:|---|
| 可演示原型 | 40–80 | 6–12 小时 | 打开简单 PDF/DOCX，修改文字或批注，保存副本 |
| SDK Alpha | 180–320 | 36–72 小时 | PDF 基础闭环、DOCX 段落/样式/列表/简单表格、Flutter 接口 |
| 产品 Beta | 420–750 | 7–14 天 | iOS/Android、崩溃恢复、版本验证、代表性语料、性能基线 |
| 上架候选版 | 900–1,600 | 3–6 周 | 真机矩阵、格式模糊测试、安全审计、500+ 语料、签名发布 |

如果只要求当前移民材料 App 中常见的 PDF 和简单 DOCX，且明确降级复杂文件，上架候选版可争取压缩到 **10–21 天**。完整覆盖任意现实世界 PDF/DOCX 不设为第一版完成条件，而通过兼容档位持续扩大。

代码生成本身通常不是关键路径。墙钟时间主要花在生成失败样本、交叉打开验证、定位只在某个字体/输入法/设备出现的问题，以及确认保存后没有静默丢失未知结构。

## 无第三方文档引擎架构

### 共享核心

- 语言：Rust，核心仅依赖标准库和项目内代码；通过稳定 C ABI 暴露能力。
- `container`：自行实现 ZIP central directory、Deflate、CRC32、流式大小限制。
- `xml`：自行实现受限 XML tokenizer、namespace、关系解析和安全实体策略。
- `document_model`：段落、run、样式、列表、表格、图片、评论、选择、事务、撤销/重做。
- `layout`：输出平台无关 display list；字体选择、字形测量和最终绘制委托系统文字/图形 API。
- `validation`：打开前预检、资源限制、保存后重新解析、结构 hash 与降级原因。

### PDF 核心

- tokenizer、间接对象、xref table/xref stream、object stream、page tree；
- content stream 操作符、图形状态、路径、裁剪、图片、文本和 ToUnicode；
- Flate、ASCIIHex、ASCII85、RunLength 第一批；LZW、JPX、JBIG2 分级加入；
- display list 分别映射到 Core Graphics 与 Android Canvas；
- annotations、AcroForm、搜索、选择、填写、普通手写签名；
- 页面旋转、排序、删除、提取、合并、图片生成 PDF；
- incremental save 与 full rewrite 两种模式；原件不可覆盖；
- 数字签名检测与修改失效警告，不在第一版生成认证数字签名。

### DOCX 核心

- OPC package、content types、relationships；
- `document.xml`、styles、numbering、settings、comments、media；
- 段落、run、基础字符/段落样式、列表、超链接、图片和简单表格；
- native IME composition、光标、选择、复制粘贴、查找替换和撤销/重做；
- 未理解的 XML part 和节点原样保留；触及无法安全 round-trip 的区域时转为只读；
- 保存新 DOCX 包并重新解析验证；通过共享 display list 导出 PDF。

### 平台层

- Apple：Swift Package，Swift/Objective-C wrapper，Core Graphics/Core Text，UIDocumentPicker；
- Android：AAR，Kotlin/JNI wrapper，Canvas/Text shaping，Storage Access Framework；
- Flutter：FFI 处理批量模型与字节，Pigeon/MethodChannel 处理文件选择、输入法和生命周期；
- 所有 API 首先在独立 SDK 仓库定义，产品 App 只依赖版本，不复制引擎源码。

## Agent 并行任务图

1. Agent A：公共 API、C ABI、错误码、兼容档位和版本策略。
2. Agent B：PDF tokenizer/xref/object/page tree。
3. Agent C：PDF content stream/display list/render backend。
4. Agent D：PDF annotation/form/page operations/writer。
5. Agent E：ZIP/Deflate/XML/OPC。
6. Agent F：DOCX model/import/export/unknown-node preservation。
7. Agent G：layout/editor/IME/selection/undo。
8. Agent H：Apple/Android/Flutter bindings。
9. Agent I：corpus generator、differential tests、fuzzing、安全限制。
10. Agent J：集成、性能、发布、文档与示例应用。

每个任务必须先提交 fixture 和失败测试，再提交实现。合并负责人只接受具备 round-trip、资源限制和错误降级测试的变更。

## 第一版验收

- 100 份合成 PDF、100 份合成 DOCX、300 份变异/损坏/边界样本；
- 支持档位内打开、编辑、保存、重新打开成功率 100%；
- 不支持档位不得崩溃、越界读取、无限循环、解压炸弹或静默覆盖；
- 中文输入、英文输入、emoji、组合字符、RTL 基础样本；
- Android/iOS 前后台切换、低内存、旋转、大文件和中断恢复；
- 同一输出分别由 SDK、系统预览与至少一个外部 Office/PDF 阅读器交叉打开；
- 原件 hash 永远不因编辑改变，所有输出创建新版本。

## 发布规则

- GitHub 仓库公开源代码；项目本身可选 Apache-2.0 或 MIT 双许可；
- 不复制第三方产品 UI、图标、商标、测试文件或反编译实现；
- 每次发布生成 SBOM、来源归属、签名 tag、校验和、变更日志和安全公告；
- `SECURITY.md` 提供私密漏洞报告渠道；高风险解析漏洞修复前不公开利用样本；
- 采用 SemVer；产品 App 锁定精确版本并保留快速回滚能力。

## 给执行 Agent 的首轮命令目标

在独立仓库中先完成 72 小时 Alpha：建立 Rust workspace、C ABI、Flutter example；实现无压缩/Deflate ZIP、受限 XML、简单 DOCX 段落 round-trip；实现 PDF tokenizer/xref/page tree、基础文字和路径 display list、文本批注保存；生成不少于 50 个自动化 fixtures。不得引入第三方文档引擎或复制其代码。

