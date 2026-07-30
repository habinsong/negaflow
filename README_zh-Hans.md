<p align="center">
  <img src="Sources/negaflowApp/Resources/AppIcon-1024.png" width="128" alt="negaflow 应用图标">
</p>

<h1 align="center">negaflow</h1>

<p align="center">支持胶片翻拍、扫描和完整显影流程的 macOS 应用</p>

<p align="center">
  <a href="docs/zh-Hans/product/PROJECT_STATUS.md"><img src="https://img.shields.io/badge/status-1.0.4%20release-EF8B26" alt="发布状态"></a>
  <a href="#系统要求"><img src="https://img.shields.io/badge/macOS-14.0+-000000?logo=apple&logoColor=white" alt="macOS 14 或更高版本"></a>
  <a href="Package.swift"><img src="https://img.shields.io/badge/Swift-5.9+-F05138?logo=swift&logoColor=white" alt="Swift 5.9 或更高版本"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache--2.0-6E7781" alt="Apache 2.0 许可证"></a>
</p>

<p align="center">
  <a href="README.md">English</a> ·
  <a href="README_ko.md">한국어</a> ·
  <a href="README_ja.md">日本語</a> ·
  <strong>简体中文</strong> ·
  <a href="README_fr.md">Français</a> ·
  <a href="README_de.md">Deutsch</a>
</p>

---

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/zh-Hans/develop-dark.webp">
    <img src="docs/images/zh-Hans/develop-light.webp" alt="negaflow — 显影界面">
  </picture>
</p>

negaflow 是一款 macOS 应用，用于导入、反相和显影扫描胶片或数码相机翻拍的胶片。<br>
它支持彩色和黑白、负片和正片，所有调整都会与原始文件分开保存。<br>
从图库管理到显影和打印，它覆盖了胶片数字化处理的完整流程。

显影引擎名为 **Chroma Engine**，灰尘和划痕修复功能名为 **GrainMend**。<br>
只导入图像文件也能完成显影和导出。<br>
只有安装单独的插件后，扫描仪连接才会启用。

> 技术一直在进步，但与胶片重新流行的势头相反，模拟摄影周边的工作流程却停滞了。<br>
> 除非坚持暗房放大，否则胶片必须先转成数字图像，才能被大多数人看见和分享。<br>
> 可随着胶片实验室和冲洗店逐渐消失，这一环节能得到的支持也越来越少。
> <br>
> 这个项目始于我在不同工作流程里遇到的不便，也始于那些“要是有这个功能就好了”的念头。<br>
> 我以使用 35mm 和中画幅胶片积累的经验为基础，从头到尾都由自己开发。<br>
> 它最初只是一个给自己用的小项目，如今的 **negaflow** 已经不止于此。<br>
> 归根到底，工具最重要的是好用、顺手、够快，并能把琐碎的事情正确处理好。<br>
> **negaflow** 是独立开发的原生 macOS 应用，把胶片实验室和个人使用者的工作方式都融了进来。
>
> **谨以此夏，纪念尼埃普斯拍下人类第一张照片二百周年。**

---

## 安装

请从 [GitHub Releases](https://github.com/habinsong/negaflow/releases) 下载当前版本。<br>
大多数 Mac 请使用 Universal PKG。

| 下载文件 | 支持的 Mac |
|---|---|
| `negaflow-1.0.4-1-macOS-universal.pkg` | Apple Silicon 和 Intel |
| `negaflow-1.0.4-1-macOS-arm64.pkg` | 仅 Apple Silicon |

1. 下载适合当前 Mac 的 PKG。
2. 打开 PKG，并按安装器提示操作。
3. 从 `/Applications` 启动 **negaflow**。

PKG 会把 `negaflow.app` 直接安装到 `/Applications`。<br>
同一发布页面还提供用于手动安装的 DMG 和 ZIP。<br>
目前在 GitHub 上发布的文件为 ad-hoc 签名，并未通过 Apple 公证。<br>
因此 macOS 可能会拦下首次启动。请先尝试打开 negaflow，然后在
**系统设置 → 隐私与安全性**中查看该提示，并仅在下载文件的 SHA-256 校验和
与发布页公布的一致时，选择**仍要打开**。

> 使用实体扫描仪还需要单独安装扫描仪插件。<br>
> SANE 扫描仪使用 [`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane)。

## 功能

- 测量片基并反相彩色或黑白胶片
- 曝光、对比度、曲线、HSL、色彩分级和黑白调色
- 锐化、降噪、颗粒、暗角和光晕
- 使用 GrainMend 修复灰尘和划痕
- 胶卷、文件夹、收藏、星级、堆叠和虚拟副本
- 缩放、裁剪、旋转、对比视图、直方图和剪切提示
- 将相机、镜头、胶片与曝光记录写入导出文件的 EXIF
- 按胶卷记录拍摄信息，并可按相机、镜头、胶片检索图库
- 导出 JPEG 和 16-bit TIFF，支持 ICC 配置文件和打印版式
- 黑白接触印相表、毫米网格、自由说明文字和当前布局印相导出
- C-print 冲印店、相纸与表面设置，以及冲印店 ICC 软打样预览
- 导入进度、按文件夹批量设置显影流程与目标，以及处理进度
- 记住折叠状态的文件夹列表、照片拖放和 Finder 变更自动同步
- 包含流程、目标、调整、裁剪和方向的预设及复制粘贴
- 七种印相布局：单张图像、接触印相表、照片套版、自定义套版、蓝晒、玻璃干版和明胶银盐
- 按成品页计数的印相导出与快速导出：39 张照片的 6 × 7 接触印相表输出为一个合成文件，
  单张式布局则作为受限并发的 39 文件批处理
- 在应用名称与版本之间显示尼埃普斯二百周年纪念句的多语言“关于 negaflow”窗口

> 已完成的检查记录在[项目状态](docs/zh-Hans/product/PROJECT_STATUS.md)中。 <br>

## Chroma Engine

Chroma Engine 是 `Chromabase` 模块中的胶片反相和显影引擎。<br>
反相负片前，它会从未曝光区域测量片基。<br>
自动测量不准确时，可以用吸管选择区域，也可以直接输入 RGB 数值。

默认状态是 `MAIN` 和手动调整。<br>
自动色调、自动白平衡、自动色阶和自动颜色只会在你主动运行时应用。

显影目标包括：

- `MAIN`：常规显影
- `PRINT`：使用打印机 ICC 的输出
- `HS`、`SP`：迷你冲印设备风格
- `F135`、`HR`：对应设备系列的显影风格
- `EXPIRED`：老胶片修复

输出可使用 sRGB、Display P3、Adobe RGB 或自定义 RGB ICC。<br>
反相和色彩处理顺序见 [Chroma Engine](docs/zh-Hans/product/CHROMA_ENGINE.md)。

## GrainMend

**GrainMend 用于修复胶片上的灰尘、针孔、划痕和乳剂损伤等缺陷。** <br>


| GrainMend RGB | 使用方式 |
|---|---|
| 自动 | 在整张照片中查找并修复缺陷。 |
| 引导 | 在你标出的区域内查找缺陷。 |
| 画笔 | 直接涂出需要修复的位置。 |
| 仿制图章 | 把指定位置的像素复制到另一处。 |


**GrainMend RGB** 的自动和引导会参考周围纹理填补缺陷， <br>
同时检查方向与附近结构，避免把画面中的线条或网格当成划痕抹掉。 <br>
修复结果会保留为 GrainMend 图层。 <br><br>
> 自动用于清除照片上常见的缺陷。当候选过于密集、无法安全应用时，它会在不修改图像的情况下停止，并提示改用引导。 <br>
> 引导针对扫描过程中产生的各种灰尘。画笔用于补上自动没能发现的缺陷，仿制图章则复制你选定的来源像素。 <br>
每个 **GrainMend RGB** 图层都可以调整强度、查看蒙版，也可以单独关闭或删除。



如果扫描仪插件提供红外通道，**GrainMend IR** 的检测结果也会加入同一份编辑记录。<br><br>

**GrainMend RGB** 是有别于硬件红外除尘的独立软件方案， <br>
**GrainMend IR** 使用扫描仪的红外通道，并非 Digital ICE、iSRD 或 SRDx 的实现或兼容模式。

实现方式以及画质、性能标准见 [GrainMend](docs/zh-Hans/product/GRAINMEND.md)。

## 胶片配置文件

应用内置 15 个扫描仪配置文件，数据来自项目作者实际拍摄的胶片。<br>
配置文件共记录 928 个图像观测值，目前全部标为 `realOnly`。<br>
`realOnly` 表示它们来自真实扫描，但尚未通过独立成对参考图像的精度验证。

配置文件不会只根据扫描仪名称自动套用，必须由用户手动选择。<br>
应用也会检查每个文件和清单的 SHA-256。

`928` 是各配置文件组观测数的总和，不代表 928 张互不相同的照片。<br>
同一卷胶片可能在多个扫描仪组中重复统计。<br>
我逐一检查了作为来源的 928 份扫描，并在测量前排除了存在误检或漏检的文件。<br>
数据构成和生成过程见[胶片配置文件](docs/zh-Hans/product/FILM_PROFILES.md)。

## 基本使用顺序

1. 导入图像文件，或使用已安装的插件进行扫描。
2. 选择胶片类型并测量片基。
3. 在 Chroma Engine 中调整颜色和色调。
4. 对需要的照片使用 GrainMend。
5. 用对比视图和直方图检查结果，然后打印或导出。

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/zh-Hans/library-dark.webp">
    <img src="docs/images/zh-Hans/library-light.webp" alt="negaflow — 图库界面">
  </picture>
</p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/zh-Hans/print-dark.webp">
    <img src="docs/images/zh-Hans/print-light.webp" alt="negaflow — 打印界面">
  </picture>
</p>

界面是为真正处理照片的人做的，不是泛泛的 AI 生成样稿。<br>
只要把摄影当作爱好，就应该能很快找到熟悉的操作方式。

## 从图库到打印

默认情况下，仅导入图片不会开始显影。negaflow 先建立原始缩略图和文件夹；在文件夹中选择流程
与目标并点击应用，或进入显影页面时才开始处理。需要自动显影时，可在设置的工作流程中开启，
默认值为关闭。

文件夹的折叠状态会在重新打开应用后保留。照片可以拖到其他文件夹；目标位置已有同名文件时，
应用会添加编号而不是覆盖原文件。在 Finder 中移动或重命名原图或文件夹后，图库只重新读取
发生变化的文件夹并更新位置。

显影设置复制粘贴和用户预设包含流程、目标、胶片片基、色调、颜色、细节、裁剪、旋转、翻转和
拉直。选择多张照片后，会应用到全部所选照片。

打印页面中的打印机输出配置文件会应用到排版完成后的整页。无论照片套装重复使用同一张照片，
还是混合多张照片，所有位置都会得到相同的输出转换。它不会改变显影页面的预览。

具体行为见[从图库到打印](docs/zh-Hans/product/WORKFLOW.md)。

## 从源码构建

### 系统要求

- macOS 14.0 或更高版本
- GUI 应用：Xcode 26
- 引擎和 CLI：Swift 5.9 或更高版本
- 硬件扫描：单独安装扫描仪插件

```bash
git clone https://github.com/habinsong/negaflow.git
cd negaflow

# 构建 Release 版本并启动
bash scripts/run-app.sh

# 只构建，不启动
bash scripts/run-app.sh build
```

GUI 应用使用 `xcodebuild` 构建。<br>
`scripts/run-app.sh` 会完成构建、应用包组装和本地签名。<br>
只构建引擎和 CLI 时，请使用 `swift build`。

## CLI

```bash
swift build

# 查找扫描仪
.build/debug/negaflow detect
.build/debug/negaflow capabilities <scannerID>

# 显影
.build/debug/negaflow develop in.tiff out.jpg --look rich-neutral --target main

# GrainMend
.build/debug/negaflow develop scan.tif out.jpg --defects 1
.build/debug/negaflow defect-bench ./scans --out ./report

# 列出配置文件并检查引擎
.build/debug/negaflow list-scanner-profiles
.build/debug/negaflow selftest
```

不带参数运行 `negaflow` 可以查看全部选项。

## 扫描仪

negaflow 不会根据扫描仪型号猜测功能。<br>
它只使用插件报告的分辨率、位深、扫描区域、曝光和 IR 功能。

SANE 设备由单独的 GPL 项目 [`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane)负责。<br>
插件在独立进程中运行，并通过 JSON 与主应用通信。<br>
negaflow 主应用不包含或链接 SANE 代码。

## 仓库结构

| 模块 | 用途 |
|---|---|
| `Chromabase` | Chroma Engine、GrainMend、配置文件和导出 |
| `ScannerKit` | 扫描仪功能检查和外部插件连接 |
| `negaflowApp` | 图库、显影、扫描和导出界面 |
| `negaflowCLI` | 显影、扫描、基准测试和自检命令 |

模块之间的数据流见[产品结构](docs/zh-Hans/architecture/PRODUCT_ARCHITECTURE.md)。

## 开发检查

```bash
# Swift 测试
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test

# GUI Release 构建
bash scripts/run-app.sh build

# 仓库完整检查
bash scripts/ci-gate.sh
```

自动测试用于检查代码行为和回归。<br>
扫描仪特有行为、最终画质、签名和公证需要单独检查。

## 文档

| 文档 | 内容 |
|---|---|
| [Chroma Engine](docs/zh-Hans/product/CHROMA_ENGINE.md) | 片基、反相、色彩处理和显影顺序 |
| [GrainMend](docs/zh-Hans/product/GRAINMEND.md) | 缺陷检测与修复、IR、编辑记录、性能和画质标准 |
| [胶片配置文件](docs/zh-Hans/product/FILM_PROFILES.md) | 拍摄资料分析和配置文件生成 |
| [从图库到打印](docs/zh-Hans/product/WORKFLOW.md) | 导入、文件夹同步、批量显影、设置复制和打印配置文件 |
| [产品结构](docs/zh-Hans/architecture/PRODUCT_ARCHITECTURE.md) | 应用、引擎、扫描仪、存储和导出 |
| [项目状态](docs/zh-Hans/product/PROJECT_STATUS.md) | 实现状态、测量结果和待验证内容 |
| [真机与画质检查表](docs/zh-Hans/validation/REAL_QA_CHECKLIST.md) | 需要真机或人工查看的项目 |

## 许可证

negaflow 主项目采用 [Apache License 2.0](LICENSE) 发布。

negaflow 与 Kodak、Fujifilm、Noritsu、LaserSoft Imaging 或其他商标权利人没有合作或赞助关系。<br>
产品名称只用于标识测量对象或兼容目标。<br>
详情见[商标声明](TRADEMARKS.md)。
