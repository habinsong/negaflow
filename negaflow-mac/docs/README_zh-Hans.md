<p align="center">
  <img src="../Sources/negaflowApp/Resources/AppIcon-1024.png" width="128" alt="negaflow">
</p>

<h1 align="center">negaflow for macOS</h1>

<p align="center">为 macOS 原生开发的 negaflow。</p>

<p align="center">
  <a href="#"><img src="https://img.shields.io/badge/version-1.1.0-EF8B26" alt="版本 1.1.0"></a>
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
  <a href="../../README_zh-Hans.md">共用文档</a> ·
  <a href="../../negaflow-windows/docs/README_zh-Hans.md">Windows</a>
</p>

---

## 需要什么

运行：

- macOS 14.0 或更高
- Apple Silicon 或 Intel
- 处理 35mm 需要 8GB 内存，中画幅有 16GB 会舒服些

构建：

- 应用需要 Xcode 26
- 引擎和 CLI 需要 Swift 5.9 或更高

## 安装

在 [Releases](https://github.com/habinsong/negaflow/releases) 下载。

| 下载 | 适用的 Mac |
|---|---|
| `negaflow-1.1.0-mac-universal.pkg` | Apple Silicon 和 Intel |
| `negaflow-1.1.0-mac-arm64.pkg` | 仅 Apple Silicon |

多数人用 Universal PKG 就行。打开后按提示操作，应用会进到 `/Applications`。
同一页也有 DMG 和 ZIP，想自己拖放安装可以用它们。

应用没有经过 Apple 公证，第一次启动会被系统拦下。到系统设置的隐私与安全性里
点仍要打开即可。

图库和设置存在 `~/Library/Application Support/negaflow`。

## 构建

```bash
git clone https://github.com/habinsong/negaflow.git
cd negaflow

# 构建 Release 并启动
bash scripts/run-app.sh

# 只构建不启动
bash scripts/run-app.sh build
```

`run-app.sh` 会调用 `xcodebuild`，组装应用包并做本地签名。只改引擎或 CLI 的话，
`swift build` 就够，不需要 Xcode。

制作发布文件：

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

macOS 版随应用带一个可用的 CLI。

```bash
swift build

# 查找扫描仪
.build/debug/negaflow detect
.build/debug/negaflow capabilities <scannerID>

# 冲洗
.build/debug/negaflow develop in.tiff out.jpg --look rich-neutral --target main

# GrainMend
.build/debug/negaflow develop scan.tif out.jpg --defects 1
.build/debug/negaflow defect-bench ./scans --out ./report

# 配置文件列表与引擎自检
.build/debug/negaflow list-scanner-profiles
.build/debug/negaflow selftest
```

不带参数运行会列出全部选项。

## 扫描仪

装插件之前，扫描仪相关的操作不会出现。SANE 设备由
[`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane) 负责，
需要单独安装。

## 模块结构

| 模块 | 职责 |
|---|---|
| `Chromabase` | Chroma Engine、GrainMend、配置文件与导出 |
| `ScannerKit` | 扫描仪能力检查与外部插件连接 |
| `negaflowApp` | 图库、冲洗、扫描与导出界面 |
| `negaflowCLI` | 冲洗、扫描、基准测试与自检命令 |

## 基准图

仓库根目录的 `docs/verification/macos-golden` 放着这个版本渲染出来的图。
Windows 的引擎测试会读它们逐像素比对，两个版本就是这样保持一致的。
只有在 macOS 输出确实要变的时候才重新生成。

## 相关文档

- [macOS 与 Windows 的差异](../../docs/zh-Hans/platform/PLATFORM_DIFFERENCES.md)
- [Chroma Engine](../../docs/zh-Hans/product/CHROMA_ENGINE.md)
- [GrainMend](../../docs/zh-Hans/product/GRAINMEND.md)
- [产品结构](../../docs/zh-Hans/architecture/PRODUCT_ARCHITECTURE.md)
