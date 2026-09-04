<p align="center">
  <img src="../Sources/negaflowApp/Resources/AppIcon-1024.png" width="128" alt="negaflow">
</p>

<h1 align="center">negaflow for macOS</h1>

<p align="center">用 macOS 原生方式做的 negaflow。</p>

<p align="center">
  <a href="#"><img src="https://img.shields.io/badge/version-1.1.4-EF8B26" alt="版本 1.1.4"></a>
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

## 需要什么

运行时：

- macOS 14.0 及以上
- Apple Silicon 或 Intel
- 处理 35mm 需要 8GB 内存，中画幅有 16GB 会舒服些

构建时：

- 应用需要 Xcode 26
- 引擎和 CLI 需要 Swift 5.9 及以上

## 安装

在 [Releases](https://github.com/habinsong/negaflow/releases) 下载。

| 安装文件 | 支持的 Mac |
|---|---|
| `negaflow-1.1.4-mac-universal.pkg` | Apple Silicon、Intel |
| `negaflow-1.1.4-mac-arm64.pkg` | 仅 Apple Silicon |

多数情况用 Universal PKG 就行，它会装进 `/Applications`。想自己搬就用同一页面上的 DMG 或 ZIP。

没有经过 Apple 公证，第一次运行时 macOS 会拦住。在系统设置的隐私与安全性里点「仍要打开」。

图库和设置保存在 `~/Library/Application Support/negaflow`。

## 构建

```bash
git clone https://github.com/habinsong/negaflow.git
cd negaflow/negaflow-mac

# Release 构建后运行
bash scripts/run-app.sh

# 只构建不运行
bash scripts/run-app.sh build
```

`run-app.sh` 会调用 `xcodebuild`，组装应用包，再做本地签名。只改引擎或 CLI 的时候 `swift build` 就够了。

做发布文件时：

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

# 仓库整体检查
bash scripts/ci-gate.sh
```

## 命令行

macOS 版里带了 CLI。

```bash
swift build

# 找扫描仪
.build/debug/negaflow detect
.build/debug/negaflow capabilities <scannerID>

# 显影
.build/debug/negaflow develop in.tiff out.jpg --look rich-neutral --target main

# GrainMend
.build/debug/negaflow develop scan.tif out.jpg --defects 1
.build/debug/negaflow defect-bench ./scans --out ./report

# 配置文件列表与引擎自检
.build/debug/negaflow list-scanner-profiles
.build/debug/negaflow selftest
```

不带参数运行 `negaflow` 会列出全部选项。

## 扫描仪

装插件之前不会出现扫描仪的操作项。SANE 设备由 [`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane) 负责，要另外安装。

## 模块构成

| 模块 | 职责 |
|---|---|
| `Chromabase` | Chroma Engine、GrainMend、配置文件与导出 |
| `ScannerKit` | 扫描仪能力确认与外部插件连接 |
| `negaflowApp` | 图库、显影、扫描与导出界面 |
| `negaflowCLI` | 显影、扫描、基准测试与自检命令 |

## 基准图像

仓库最上层的 `docs/verification/macos-golden` 里放着这个构建产出的图像。Windows 的引擎测试会读这些文件，逐像素比对。只有 macOS 输出该变的时候才重新生成。

## 相关文档

- [macOS 和 Windows 的差异](../../docs/zh-Hans/platform/PLATFORM_DIFFERENCES.md)
- [Chroma Engine](../../docs/zh-Hans/product/CHROMA_ENGINE.md)
- [GrainMend](../../docs/zh-Hans/product/GRAINMEND.md)
- [产品结构](../../docs/zh-Hans/architecture/PRODUCT_ARCHITECTURE.md)
