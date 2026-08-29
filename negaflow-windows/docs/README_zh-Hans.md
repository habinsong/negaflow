<p align="center">
  <img src="../../negaflow-mac/Sources/negaflowApp/Resources/AppIcon-1024.png" width="128" alt="negaflow">
</p>

<h1 align="center">negaflow for Windows</h1>

<p align="center">为 Windows 原生开发的 negaflow。</p>

<p align="center">
  <a href="#"><img src="https://img.shields.io/badge/version-1.1.0-EF8B26" alt="版本 1.1.0"></a>
  <a href="#"><img src="https://img.shields.io/badge/Windows-11-0078D4?logo=windows&logoColor=white" alt="Windows 11"></a>
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
  <a href="../../negaflow-mac/docs/README_zh-Hans.md">macOS</a>
</p>

---

## 需要什么

运行：

- Windows 11（版本 26100 或更高），64 位
- 处理 35mm 需要 8GB 内存，中画幅有 16GB 会舒服些

构建：

- Visual Studio 2022，带使用 C++ 的桌面开发工作负载
- Windows 11 SDK（10.0.26100 或更高）
- .NET 10 SDK
- CMake 3.28 或更高
- Python 3.11 或更高，用于图标和资源脚本

Arm64 机器也能跑，只是 Arm64 的发布版没有 x64 验证得充分。

## 安装

在 [Releases](https://github.com/habinsong/negaflow/releases) 下载
`negaflow-1.1.0-x64-setup.exe` 并运行。

不需要管理员权限。第一次运行时 SmartScreen 会提示一次，点更多信息，再点仍要运行。

卸载走开始菜单的`卸载 negaflow`，或者设置里的应用列表。图库和照片不动。

## 构建

```powershell
git clone https://github.com/habinsong/negaflow.git
cd negaflow\negaflow-windows

# 构建 C++ 引擎
.\scripts\build.ps1 -Preset x64-release

# 构建应用并启动
.\scripts\run-app.ps1 -Architecture x64 -Configuration Release
```

`build.ps1` 接受 `x64-debug`、`x64-release`、`arm64-debug`、`arm64-release`。

开发时启动应用只有 `run-app.ps1` 这一条路。应用打包成 MSIX，所以构建目录里的 exe 直接双击
是起不来的。这个脚本会打包、为当前用户注册，然后按应用 ID 启动。和安装程序做的事一样，
只是少了安装那一步。

制作安装程序：

```powershell
.\scripts\build-release.ps1 -Architecture x64
```

结果在 `out\release\win-x64`。

## 检查

```powershell
# C++ 引擎测试
ctest --preset x64-release --output-on-failure

# 应用与图库测试
.\scripts\test-managed.ps1

# 引擎与应用边界测试
.\scripts\test-interop.ps1

# 上面几项一起跑
.\scripts\local-ci.ps1
```

引擎测试里包含基准图比对。它读取 macOS 版导出的参照文件，检查 Windows 引擎是否给出相同像素。

## 用命令行检查引擎

`negaflow-cli.exe` 是个小工具，用来看引擎怎么处理某一个文件。它是为核对行为准备的，
不是日常用的，所以接受参数标志而不是子命令。

```powershell
$cli = "out\build\native\x64-release\Release\negaflow-cli.exe"

# 这个构建是什么
& $cli --build-info

# 读一张扫描并报告文件内容
& $cli --probe-tiff scan.tif

# 冲洗并写出 16 位 TIFF
& $cli --export-developed-tiff16 scan.tif out.tif

# 一次冲洗的时间花在哪里
& $cli --develop-timing scan.tif

# 自动找片基并报告选了什么
& $cli --auto-base-probe scan.tif
```

不带参数运行会列出全部。

## 扫描仪

装插件之前，扫描仪相关的操作不会出现。SANE 设备由
[`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane) 负责，
需要单独安装。

插件走 Windows 本身提供的扫描仪驱动通路，所以同一台机器上 VueScan 和 SilverFast 照常可用。

## 出问题的时候

应用会把纯文本日志写到 `%LOCALAPPDATA%\Negaflow\Logs`。

| 文件 | 记录内容 |
|---|---|
| `export-trace.txt` | 每次导出和快速导出，包括失败的 |
| `termination.txt` | 应用关闭过程中发生的事 |
| `settings-change.txt` | 变动的设置以及是什么改的 |

这三个一直开着。反馈问题时，对应的那一份通常就能说明原因。

还有两个默认关闭，只在追查特定问题时开：

- `preview-trace.txt`，在同一目录建一个名为 `preview-trace.on` 的空文件即可开启
- `stage-trace.txt`，启动前设置环境变量 `NEGAFLOW_STAGE_TRACE=1` 开启。它记录冲洗过程每一步
  之后的像素统计，用来找出预览和导出是从哪一步开始不一致的

## 目录结构

```
negaflow-windows/
├── src/
│   ├── Native/        Chroma Engine、GrainMend、解码与导出 (C++)
│   ├── Interop/       引擎与应用之间的桥接 (C#)
│   ├── Catalog.Core/  图库存储 (C#)
│   ├── Shell.Core/    冲洗、打印与导出逻辑 (C#)
│   ├── Shell/         图库、冲洗与打印界面 (WinUI 3)
│   └── Cli/           引擎检查工具 (C++)
├── scripts/           构建、测试与打包脚本
├── tests/             引擎、应用与边界测试
└── Installer/windows/ NSIS 安装程序
```

## 相关文档

- [两个版本的差异](../../docs/zh-Hans/platform/PLATFORM_DIFFERENCES.md)
- [Chroma Engine](../../docs/zh-Hans/product/CHROMA_ENGINE.md)
- [GrainMend](../../docs/zh-Hans/product/GRAINMEND.md)
- [产品结构](../../docs/zh-Hans/architecture/PRODUCT_ARCHITECTURE.md)
