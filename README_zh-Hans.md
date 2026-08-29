<p align="center">
  <img src="negaflow-mac/Sources/negaflowApp/Resources/AppIcon-1024.png" width="128" alt="negaflow 应用图标">
</p>

<h1 align="center">negaflow</h1>

<p align="center">从扫描胶片到冲洗和打印的完整流程。macOS 和 Windows 各有一套原生应用。</p>

<p align="center">
  <a href="https://habinsong.github.io/negaflow-site/zh/"><img src="https://img.shields.io/badge/website-negaflow-1F6FEB" alt="网站"></a>
  <a href="#install"><img src="https://img.shields.io/badge/version-1.1.0-EF8B26" alt="版本 1.1.0"></a>
  <a href="negaflow-mac/docs/README_zh-Hans.md"><img src="https://img.shields.io/badge/macOS-14.0+-000000?logo=apple&logoColor=white" alt="macOS 14 及以上"></a>
  <a href="negaflow-windows/docs/README_zh-Hans.md"><img src="https://img.shields.io/badge/Windows-11-0078D4?logo=windows&logoColor=white" alt="Windows 11"></a>
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

<p align="center">
  <a href="https://habinsong.github.io/negaflow-site/zh/">网站</a> ·
  <a href="https://habinsong.github.io/negaflow-site/zh/camera-scanning/">相机翻拍指南</a> ·
  <a href="https://habinsong.github.io/negaflow-site/zh/faq/">常见问题</a>
</p>

---

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/zh-Hans/develop-dark.webp">
    <img src="docs/images/zh-Hans/develop-light.webp" alt="negaflow 显影界面">
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

## 两套分开做

negaflow 在 macOS 和 Windows 上都能运行。两个应用不共用代码。

| | macOS | Windows |
|---|---|---|
| 界面 | SwiftUI | WinUI 3 |
| 引擎 | Swift 和 Core Image | C++ 和 Direct3D |
| 色彩管理 | ColorSync | Windows ICM |

同一张照片交给两边，出来的结果是一样的。macOS 版渲染出的基准图存在仓库里，
Windows 的测试会读回来逐像素比对。

每一边都按各自平台的方式写，不是移植过去再打补丁。代价是整套东西做了两遍，
好处是两个版本在各自系统上都不显得别扭。

- [macOS 文档](negaflow-mac/docs/README_zh-Hans.md)
- [Windows 文档](negaflow-windows/docs/README_zh-Hans.md)
- [两个版本的差异](docs/zh-Hans/platform/PLATFORM_DIFFERENCES.md)

---

## 安装

在 [GitHub Releases](https://github.com/habinsong/negaflow/releases) 下载当前版本。

### macOS

| 下载 | 适用的 Mac |
|---|---|
| `negaflow-1.1.0-1-macOS-universal.pkg` | Apple Silicon 和 Intel |
| `negaflow-1.1.0-1-macOS-arm64.pkg` | 仅 Apple Silicon |

多数 Mac 用 Universal PKG 就可以。

1. 下载与你的 Mac 匹配的 PKG。
2. 打开后按安装程序提示操作。
3. 从 `/Applications` 启动 **negaflow**。

同一个发布页也提供 DMG 和 ZIP，可以自己手动安装。
应用没有经过 Apple 公证，第一次启动需要在系统设置的隐私与安全性里点仍要打开。

### Windows

| 下载 | 适用的电脑 |
|---|---|
| `negaflow-1.1.0-x64-setup.exe` | Windows 11 (x64) |

1. 下载安装程序并运行。
2. 选择语言，按提示操作。
3. 从开始菜单启动 **negaflow**。

只安装到用户目录，不需要管理员权限。
卸载走开始菜单里的`卸载 negaflow`，或者设置里的应用列表。
安装程序没有签名，SmartScreen 会提示一次。点更多信息，再点仍要运行。

> 要连接实际的扫描仪，需要单独的插件。<br>
> SANE 扫描仪由 [`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane) 负责，macOS 和 Windows 都支持。

---

## 功能

- 测量片基并反相彩色或黑白胶片
- 曝光、对比度、曲线、HSL、色彩分级和黑白调色
- 锐化、降噪、颗粒、暗角和光晕
- 使用 GrainMend 修复灰尘和划痕，包含由扫描仪红外通道驱动的 GrainMend IR
- 胶卷、文件夹、收藏、星级、堆叠和虚拟副本
- 缩放、裁剪、旋转、对比视图、直方图和剪切提示
- 将相机、镜头、胶片与曝光记录写入导出文件的 EXIF
- 按胶卷记录拍摄信息，并可按相机、镜头、胶片检索图库
- 导出 JPEG 和 16-bit TIFF，支持 ICC 配置文件和打印版式
- 各布局独立的黑、灰、白纸张，共用哑光、光面、绒面、丝绸纹预览，照片/ISO 纸张与可选 in/cm 标尺
- C-print 冲印店与相纸设置，以及冲印店 ICC 软打样预览
- 导入进度、按文件夹批量设置显影流程与目标，以及处理进度
- 记住折叠状态的文件夹列表、照片拖放和 Finder 变更自动同步
- 包含流程、目标、调整、裁剪和方向的预设及复制粘贴
- 七种印相布局：单张图像、接触印相表、照片套版、自定义套版、蓝晒、玻璃干版和明胶银盐
- 按成品页计数的印相导出与快速导出：39 张照片的 6 × 7 接触印相表输出为一个合成文件，
  单张式布局则作为受限并发的 39 文件批处理，并显示线性进度与百分比


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
    <img src="docs/images/zh-Hans/library-light.webp" alt="negaflow 图库界面">
  </picture>
</p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/zh-Hans/print-dark.webp">
    <img src="docs/images/zh-Hans/print-light.webp" alt="negaflow 打印界面">
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

两个平台需要的工具和命令不同，详细内容在各自的文档里。

**macOS**

```bash
git clone https://github.com/habinsong/negaflow.git
cd negaflow

# 构建 Release 版本并启动
bash scripts/run-app.sh

# 只构建不启动
bash scripts/run-app.sh build
```

需要 macOS 14 及以上和 Xcode 26。只构建引擎和 CLI 用 `swift build` 就够。
更多内容见 [macOS 文档](negaflow-mac/docs/README_zh-Hans.md)。

**Windows**

```powershell
git clone https://github.com/habinsong/negaflow.git
cd negaflow\negaflow-windows

# 构建引擎
.\scripts\build.ps1 -Preset x64-release

# 构建应用并启动
.\scripts\run-app.ps1 -Architecture x64 -Configuration Release
```

需要 Windows 11、Visual Studio 2022 和 .NET 10 SDK。
更多内容见 [Windows 文档](negaflow-windows/docs/README_zh-Hans.md)。

## 扫描仪

negaflow 不会根据扫描仪型号猜测功能。<br>
它只使用插件报告的分辨率、位深、扫描区域、曝光和 IR 功能。

SANE 设备由单独的 GPL 项目 [`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane)负责。<br>
插件在独立进程中运行，并通过 JSON 与主应用通信。<br>
negaflow 主应用不包含或链接 SANE 代码。

## 仓库结构

```
negaflow/
├── negaflow-mac/       macOS 应用与引擎 (Swift)
├── negaflow-windows/   Windows 应用与引擎 (C#, C++)
└── docs/               共用文档
```

**macOS**

| 模块 | 职责 |
|---|---|
| `Chromabase` | Chroma Engine、GrainMend、配置文件与导出 |
| `ScannerKit` | 扫描仪能力检查与外部插件连接 |
| `negaflowApp` | 图库、冲洗、扫描与导出界面 |
| `negaflowCLI` | 冲洗、扫描、基准测试与自检命令 |

**Windows**

| 模块 | 职责 |
|---|---|
| `Native` | Chroma Engine、GrainMend、导出 (C++) |
| `Interop` | 引擎与应用之间的桥接 |
| `Catalog.Core` | 图库存储 |
| `Shell.Core` | 冲洗、打印与导出逻辑 |
| `Shell` | 图库、冲洗与打印界面 (WinUI 3) |

模块之间的数据流向见[产品结构文档](docs/zh-Hans/architecture/PRODUCT_ARCHITECTURE.md)。

## 文档

| 文档 | 内容 |
|---|---|
| [Chroma Engine](docs/zh-Hans/product/CHROMA_ENGINE.md) | 片基、反转、色彩处理与冲洗顺序 |
| [GrainMend](docs/zh-Hans/product/GRAINMEND.md) | 缺陷检测与修复、IR、编辑记录、质量与性能标准 |
| [胶片配置文件](docs/zh-Hans/product/FILM_PROFILES.md) | 素材分析与配置文件生成 |
| [从图库到打印](docs/zh-Hans/product/WORKFLOW.md) | 导入、文件夹同步、批量冲洗、设置复制与打印配置 |
| [产品结构](docs/zh-Hans/architecture/PRODUCT_ARCHITECTURE.md) | 应用、引擎、扫描仪、存储与导出结构 |
| [两个版本的差异](docs/zh-Hans/platform/PLATFORM_DIFFERENCES.md) | macOS 与 Windows 相同和不同的地方 |
| [macOS 文档](negaflow-mac/docs/README_zh-Hans.md) | macOS 安装、构建与 CLI |
| [Windows 文档](negaflow-windows/docs/README_zh-Hans.md) | Windows 安装、构建与引擎检查 |

## 许可证

negaflow 主项目采用 [Apache License 2.0](LICENSE) 发布。

negaflow 与 Kodak、Fujifilm、Noritsu、LaserSoft Imaging 或其他商标权利人没有合作或赞助关系。<br>
产品名称只用于标识测量对象或兼容目标。<br>
详情见[商标声明](TRADEMARKS.md)。
