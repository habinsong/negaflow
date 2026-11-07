<p align="center">
  <img src="../Sources/negaflowApp/Resources/AppIcon-1024.png" width="128" alt="negaflow">
</p>

<h1 align="center">negaflow for macOS</h1>

<p align="center">用 macOS 原生方式做的 negaflow。</p>

<p align="center">
  <a href="#"><img src="https://img.shields.io/badge/version-1.2.6-EF8B26" alt="版本 1.2.6"></a>
  <a href="#"><img src="https://img.shields.io/badge/macOS-14.0+-000000?logo=apple&logoColor=white" alt="macOS 14 及以上"></a>
  <a href="../../LICENSE"><img src="https://img.shields.io/badge/license-Apache--2.0-6E7781" alt="Apache 2.0"></a>
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
  <a href="../../README_zh-Hans.md">共同文档</a> ·
  <a href="../../negaflow-windows/docs/README_zh-Hans.md">Windows</a>
</p>

---

## 运行环境

运行需要：

- macOS 14.0 及以上（支持 macOS 14、26、27）
- Apple Silicon 或 Intel
- 8 GB 内存，中画幅建议 16 GB

构建需要：

- 应用：Xcode 26 及以上
- 引擎和 CLI：Swift 5.9 及以上

## 安装

从 [Releases](https://github.com/habinsong/negaflow/releases) 下载。

| 文件 | 支持的 Mac |
|---|---|
| `negaflow-1.2.6-mac-universal.pkg` | Apple Silicon、Intel |
| `negaflow-1.2.6-mac-arm64.pkg` | 仅 Apple Silicon |

大多数 Mac 用 Universal PKG，会装进 `/Applications`。想自己摆放应用，可以用同一页面上的 DMG 或 ZIP。

应用是 ad hoc 签名，没有经过公证，所以 macOS 会拦截第一次启动。在系统设置的隐私与安全性里点「仍要打开」。

图库和设置在 `~/Library/Application Support/negaflow`。

应用在启动时向 GitHub 查询一次最新发布。有新版本时，右上角 ⋯ 菜单最下方会出现“更新到 X.Y.Z 版”。点击后会打开发布页面，并按发布附带的 `SHA256SUMS.txt` 校验适合这台 Mac 的 PKG，再保存到“下载”文件夹。安装需要你自己完成。已是最新时，该项显示“当前已是最新版本。”，点击会打开项目页面。离线等原因导致查询失败时，该项不出现。

## 构建

```bash
git clone https://github.com/habinsong/negaflow.git
cd negaflow/negaflow-mac

# 构建 Release 应用并启动
bash scripts/run-app.sh

# 只构建，不启动
bash scripts/run-app.sh build
```

`run-app.sh` 调用 `xcodebuild`，组装应用包并在本机签名。只处理引擎或 CLI 时，`swift build` 就够了。

发布文件：

```bash
bash negaflow-mac/scripts/build-release.sh
bash negaflow-mac/scripts/create-release-artifacts.sh
```

## 检查

```bash
# Swift 测试
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test

# 应用的 Release 构建
bash scripts/run-app.sh build

# 仓库的全部检查
bash scripts/ci-gate.sh
```

## Custom 色彩目标

目标胶囊按 MAIN、HS、SP、F135、HR 的顺序排列，CS 在最后。选中 CS 后，左下角的选择器会展开 18 个 Custom 目标的两列列表，风格选择器仍在右侧。进入 CS 时选中 Emulsion，已经在用 Custom 目标的照片保持原目标。

列表分三组：Emulsion 到 Dichroic 共 11 个，Wetzlar 到 Rochester 共 4 个，Slide Show 到 Point & Shoot 共 3 个。Custom 目标应用 custom-3 的影调、密度和色度响应。保存、预览、缩略图和导出都使用所选目标的 ID。其他目标不变。

CLI 接受同样的 ID：`--target classic`、`--target dye-transfer`、`--target point-and-shoot`。

## 命令行

macOS 版自带 CLI。

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

# 配置文件与引擎自检
.build/debug/negaflow list-scanner-profiles
.build/debug/negaflow selftest
```

不带参数运行 `negaflow` 可以看到全部选项。

## 扫描仪

安装插件之前，扫描仪控件不会显示。SANE 设备由单独安装的 [`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane) 负责。

## 模块

| 模块 | 作用 |
|---|---|
| `Chromabase` | Chroma Engine、GrainMend、配置文件、导出 |
| `ScannerKit` | 扫描仪能力检查与插件连接 |
| `negaflowApp` | 图库、显影、扫描、导出界面 |
| `negaflowCLI` | 显影、扫描、基准测试、自检命令 |

## 基准图像

`docs/verification/macos-golden` 存放这个构建渲染出的图像。Git 忽略这个文件夹，所以图像只存在于渲染它们的那台电脑上。Windows 引擎测试会与副本逐像素比较。只有在有意改变 macOS 输出时才重新生成。

## 相关文档

- [两个版本的差异](../../docs/zh-Hans/platform/PLATFORM_DIFFERENCES.md)
- [Chroma Engine](../../docs/zh-Hans/product/CHROMA_ENGINE.md)
- [GrainMend](../../docs/zh-Hans/product/GRAINMEND.md)
- [产品结构](../../docs/zh-Hans/architecture/PRODUCT_ARCHITECTURE.md)
