# negaflow 文档

按内容分开，方便直接打开需要的那一份。

[English](../README.md) · [한국어](../ko/README.md) · [日本語](../ja/README.md) · 简体中文 · [Français](../fr/README.md) · [Deutsch](../de/README.md)

```mermaid
flowchart LR
    A["想先了解产品"] --> P["product"]
    B["想看代码和数据流"] --> R["architecture"]
    C["想确认格式和数值"] --> S["reference"]
```

> [!NOTE]
> negaflow 1.1.0 在 macOS 和 Windows 上都能运行。两个应用按各自平台分开编写， 同一个文件在两边出来的结果一致。

## 平台

| 文档 | 什么时候看 |
|---|---|
| [macOS 与 Windows 的差异](platform/PLATFORM_DIFFERENCES.md) | 想知道两边哪些一样、哪些不一样 |
| [macOS 文档](../../negaflow-mac/docs/README_zh-Hans.md) | 在 macOS 上安装、构建或使用 CLI |
| [Windows 文档](../../negaflow-windows/docs/README_zh-Hans.md) | 在 Windows 上安装、构建或检查引擎 |

## 产品

| 文档 | 什么时候看 |
|---|---|
| [从图库到打印](product/WORKFLOW.md) | 需要了解导入、按文件夹显影、复制粘贴和打印流程时 |
| [色彩引擎](product/CHROMA_ENGINE.md) | 想了解胶片反转和显影顺序时 |
| [GrainMend](product/GRAINMEND.md) | 想看灰尘和划痕怎么修复时 |
| [胶片配置文件](product/FILM_PROFILES.md) | 想确认内置配置文件的来源和限制时 |

## 结构

| 文档 | 内容 |
|---|---|
| [产品结构](architecture/PRODUCT_ARCHITECTURE.md) | 应用、引擎、存储、导出之间的数据流 |
| [目录存储结构](architecture/CATALOG_STORAGE.md) | 为什么用 SQLite、旧格式、实测数值 |
| [扫描仪插件结构](architecture/SCANNER_PLUGINS.md) | 外部进程、批准、扫描文件的公开 |
| [图库保存归档](architecture/LIBRARY_ARCHIVE.md) | 原件和编辑记录如何一起保存 |

## 规格

| 文档 | 内容 |
|---|---|
| [扫描仪 CLI JSON](reference/CLI_JSON.md) | `detect --json` 和 `capabilities --json` 的输出形式 |
| [渲染记录](reference/RENDER_MANIFEST.md) | 原件、编辑值、输出文件之间的 SHA-256 关系 |
| [印相布局与 C-print 预览](reference/C_PRINT.md) | 7 种布局、成品页导出、渲染优化、仅软打样 ICC 的行为和精度限制 |
| [固定印相响应](reference/PRINT_RESPONSE.md) | `shoulder-print-response-v4` 的公式和基准点 |
| [扫描仪配置文件质量判定](reference/PROFILE_QUALITY_GATE.md) | REAL/TARGET 配对素材的发布判定 |
| [扫描仪噪声配置文件](reference/SCANNER_NOISE_PROFILES.md) | 重复扫描测量与自动应用的条件 |
| [GrainMend IR 要避开的胶片](reference/INFRARED_LIMITS.md) | 黑白、Kodachrome、RGB/IR 对齐的限制 |
| [平板自动画幅检测](reference/FRAME_DETECTION.md) | 如何把胶片与空片夹区分开，如何测量画幅边界 |
| [IT8 色彩检验](reference/IT8_COLOR_VALIDATION.md) | 色块测量、证据等级、合成回归 |

## 来源与分发

| 文档 | 什么时候用 |
|---|---|
| [代码与资源来源](legal/PROVENANCE.md) | 确认 Apache/GPL 边界和内置资源哈希时 |
| [`TRADEMARKS.md`](../../TRADEMARKS.md) | 确认胶片、扫描仪和产品名称的用法时 |

## 写法

- 产品说明只写用户现在看得到的行为。
- 结构文档写职责范围和数据流向。
- 规格文档里的代码值、字段名和哈希保持原样。
- 验证文档把通过的和还没确认的分开写。
- 用平实的句子。不写宣传形容词，不写结尾总结段，不写否定对句。
- 一种语言里有的小节，六种语言里都要有。规则写在 [`AGENTS.md`](../../AGENTS.md)。
