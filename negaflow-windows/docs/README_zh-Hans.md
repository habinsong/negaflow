<p align="center">
  <img src="../../negaflow-mac/Sources/negaflowApp/Resources/AppIcon-1024.png" width="128" alt="negaflow">
</p>

<h1 align="center">negaflow for Windows</h1>

<p align="center">用 Windows 原生方式做的 negaflow。</p>

<p align="center">
  <a href="#"><img src="https://img.shields.io/badge/version-1.1.0-EF8B26" alt="版本 1.1.0"></a>
  <a href="#"><img src="https://img.shields.io/badge/Windows-11%2024H2+-0078D4?logo=windows&logoColor=white" alt="Windows 11 24H2 或更高"></a>
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
  <a href="../../negaflow-mac/docs/README_zh-Hans.md">macOS</a>
</p>

---

## 需要什么

运行时：

- Windows 11 24H2（版本 26100）或更高，64 位
- 处理 35mm 需要 8GB 内存，中画幅有 16GB 会舒服些

构建时：

- Visual Studio 2022，含 C++ 桌面开发工作负载
- Windows 11 SDK（10.0.26100 或更高）
- .NET 10 SDK
- CMake 3.28 或更高
- 图标和资源脚本用的 Python 3.11 或更高

Arm64 机器上也能跑。只是 Arm64 的发布版没像 x64 那样确认过。

## 安装

在 [Releases](https://github.com/habinsong/negaflow/releases) 下载 `negaflow-1.1.0-win-x64.exe` 并运行。

不需要管理员权限。第一次运行时 SmartScreen 会提示一次，点更多信息再运行就行。

卸载走开始菜单的 `卸载 negaflow`，或者设置里的应用列表。图库和照片保持原样。

## 构建

```powershell
git clone https://github.com/habinsong/negaflow.git
cd negaflow\negaflow-windows

# 构建 C++ 引擎
.\scripts\build.ps1 -Preset x64-release

# 构建应用后运行
.\scripts\run-app.ps1 -Architecture x64 -Configuration Release
```

`build.ps1` 可以传 `x64-debug`、`x64-release`、`arm64-debug`、`arm64-release`。

开发时启动应用只有 `run-app.ps1` 一条路。应用会打包成 MSIX，所以直接跑构建目录里的 exe 起不来。这个脚本会做好包，注册给当前用户，再按应用 ID 启动。

做安装程序时：

```powershell
.\scripts\build-release.ps1 -Architecture x64
```

产物在 `out\release\win-x64`。

## 检查

```powershell
# C++ 引擎测试
ctest --preset x64-release --output-on-failure

# 应用与编目测试
.\scripts\test-managed.ps1

# 引擎与应用的边界测试
.\scripts\test-interop.ps1

# 以上一次跑完
.\scripts\local-ci.ps1
```

引擎测试里含有基准图像比对。它读 macOS 版导出的基准文件，确认 Windows 引擎给出同样的像素。

## 用命令行确认引擎

`negaflow-cli.exe` 用来看引擎怎么处理一个文件。它用标志而不是子命令。

```powershell
$cli = "out\build\native\x64-release\Release\negaflow-cli.exe"

# 确认这是什么构建
& $cli --build-info

# 看扫描文件里有什么
& $cli --probe-tiff scan.tif

# 显影后存成 16 位 TIFF
& $cli --export-developed-tiff16 scan.tif out.tif

# 看一次显影的时间花在哪
& $cli --develop-timing scan.tif

# 自动找片基，看它选了什么
& $cli --auto-base-probe scan.tif
```

不带参数运行会列出全部。

## 扫描仪

装插件之前不会出现扫描仪的操作项。SANE 设备由 [`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane) 负责，要另外安装。

插件通过 Windows 本来就提供的驱动路径和扫描仪通信。同一台机器上照样可以继续用 VueScan 或 SilverFast。

## 出问题的时候

应用会往 `%LOCALAPPDATA%\Negaflow\Logs` 写文本记录。

| 文件 | 记录内容 |
|---|---|
| `export-trace.txt` | 导出与快速导出，包含失败的情况 |
| `termination.txt` | 关闭应用期间发生的事 |
| `settings-change.txt` | 改动的设置和改动方 |

这三个一直开着。另外还有两个，只在追查特定问题时才打开。

- `preview-trace.txt`。在同一个文件夹里建一个名为 `preview-trace.on` 的空文件就会打开。
- `stage-trace.txt`。启动应用前设置环境变量 `NEGAFLOW_STAGE_TRACE=1` 就会打开。它记录显影每个阶段的像素统计。

## 文件夹构成

```
negaflow-windows/
├── src/
│   ├── Native/        Chroma Engine、GrainMend、解码与导出 (C++)
│   ├── Interop/       连接引擎和应用的层 (C#)
│   ├── Catalog.Core/  图库存储 (C#)
│   ├── Shell.Core/    显影、印相、导出逻辑 (C#)
│   ├── Shell/         图库、显影、印相界面 (WinUI 3)
│   └── Cli/           引擎检查工具 (C++)
├── scripts/           构建、测试、打包脚本
├── tests/             引擎、应用、边界测试
└── Installer/windows/ NSIS 安装程序
```

## 相关文档

- [macOS 和 Windows 的差异](../../docs/zh-Hans/platform/PLATFORM_DIFFERENCES.md)
- [Chroma Engine](../../docs/zh-Hans/product/CHROMA_ENGINE.md)
- [GrainMend](../../docs/zh-Hans/product/GRAINMEND.md)
- [产品结构](../../docs/zh-Hans/architecture/PRODUCT_ARCHITECTURE.md)
