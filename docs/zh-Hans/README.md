# negaflow 文档

按内容分开，方便直接打开需要的那一份。

[English](../README.md) · [한국어](../ko/README.md) · [日本語](../ja/README.md) · 简体中文 · [Français](../fr/README.md) · [Deutsch](../de/README.md)

> [!NOTE]
> negaflow 1.2.6 可在 macOS 和 Windows 上运行。两个应用分别开发，同一个文件在两边得到同样的画面。

## 平台

| 文档 | 什么时候看 |
|---|---|
| [macOS 版和 Windows 版的差异](platform/PLATFORM_DIFFERENCES.md) | 想知道两边哪些一样、哪些不一样 |
| [macOS 文档](../../negaflow-mac/docs/README_zh-Hans.md) | 在 macOS 上安装、构建或使用 CLI |
| [Windows 文档](../../negaflow-windows/docs/README_zh-Hans.md) | 在 Windows 上安装、构建或检查引擎 |

## 产品

| 文档 | 什么时候看 |
|---|---|
| [从图库到印相](product/WORKFLOW.md) | 需要了解导入、文件夹显影、复制粘贴和印相的行为 |
| [Chroma Engine](product/CHROMA_ENGINE.md) | 想了解胶片反相和显影顺序 |
| [GrainMend](product/GRAINMEND.md) | 想看灰尘与划痕修复如何工作 |
| [胶片配置文件](product/FILM_PROFILES.md) | 想知道内置配置文件的来源与局限 |

## 结构

| 文档 | 什么时候用 |
|---|---|
| [产品结构](architecture/PRODUCT_ARCHITECTURE.md) | 应用、引擎、存储与导出之间的数据流 |
| [目录存储结构](architecture/CATALOG_STORAGE.md) | SQLite 目录、旧 JSON 目录的导入、实测 |
| [扫描仪插件结构](architecture/SCANNER_PLUGINS.md) | 外部进程、批准、扫描文件发布 |
| [图库保存归档](architecture/LIBRARY_ARCHIVE.md) | 原始文件与编辑记录的合并保存 |

## 规格

| 文档 | 内容 |
|---|---|
| [扫描仪 CLI JSON](reference/CLI_JSON.md) | `detect --json` 与 `capabilities --json` 的输出 |
| [渲染记录](reference/RENDER_MANIFEST.md) | 连接源文件、编辑值和输出文件的 SHA-256 |
| [印相布局与 C-print 预览](reference/C_PRINT.md) | 八种布局、成品页导出、仅校样 ICC、精度局限 |
| [负片反转响应](reference/PRINT_RESPONSE.md) | `shoulder-print-response-v4` 的公式与锚点 |
| [扫描仪配置文件质量判定](reference/PROFILE_QUALITY_GATE.md) | REAL/TARGET 配对资料的发布标准 |
| [扫描仪噪声配置文件](reference/SCANNER_NOISE_PROFILES.md) | 重复扫描测量与适用条件 |
| [GrainMend IR 要避开的胶片](reference/INFRARED_LIMITS.md) | 黑白、Kodachrome、RGB/IR 对位局限 |
| [平板自动画幅检测如何找到胶片](reference/FRAME_DETECTION.md) | 胶片与空片夹的区分、画幅边界 |
| [IT8 色彩检验](reference/IT8_COLOR_VALIDATION.md) | 色块测量、证据等级、合成回归 |

## 来源与分发

| 文档 | 内容 |
|---|---|
| [代码与资源的来源](legal/PROVENANCE.md) | 核对 Apache/GPL 边界和内置资源哈希 |
| [`TRADEMARKS.md`](../../TRADEMARKS.md) | 核对胶片、扫描仪和产品名称的使用方式 |

## 写法

- 产品文档只写用户现在看到的内容。
- 结构文档写职责和数据流向。
- 参考文档里的代码值、字段名和哈希保持原样。
- 验证文档把通过的和未检查的分开。
- 某种语言里有的章节，六种语言里都有。
