<p align="center">
  <img src="../../negaflow-mac/Sources/negaflowApp/Resources/AppIcon-1024.png" width="128" alt="negaflow">
</p>

<h1 align="center">negaflow for Windows</h1>

<p align="center">用 Windows 原生方式做的 negaflow。</p>

<p align="center">
  <a href="#"><img src="https://img.shields.io/badge/version-1.2.6-EF8B26" alt="版本 1.2.6"></a>
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

## 运行环境

运行需要：

- Windows 11 24H2（版本 26100）及以上，64 位
- 8 GB 内存，中画幅建议 16 GB

构建需要：

- Visual Studio 2026，含 C++ 桌面开发工作负载（组件见 `.vsconfig`）
- Windows 11 SDK 10.0.26100 及以上
- .NET 10 SDK（`global.json` 固定为 10.0.302）
- CMake 4.2 及以上（`Visual Studio 18 2026` 生成器需要）
- Python 3（用于图标和资源脚本）

构建也有 Arm64 预设。发布文件只提供 x64。

## 安装

从 [Releases](https://github.com/habinsong/negaflow/releases) 下载 `negaflow-1.2.6-win-x64.exe` 并运行。默认安装到 `%LOCALAPPDATA%\Negaflow\App`，不要求管理员权限。

[negaflow-1.2.6-win-x64-setup.zip](https://github.com/habinsong/negaflow/releases/download/v1.2.6/negaflow-1.2.6-win-x64-setup.zip) 内含同一个安装程序 EXE，以及安装说明、许可证声明和 SHA-256 校验和。请先解压全部文件再运行安装程序。它是安装程序压缩包，不是便携应用。

安装程序没有签名。第一次运行时 SmartScreen 会警告一次，点「更多信息」后再运行。

卸载使用开始菜单里的 `Uninstall negaflow`，或设置中的应用列表。图库和照片不受影响。

应用在启动时向 GitHub 查询一次最新发布。有新版本时，右上角 ⋯ 菜单最下方会出现“更新到 X.Y.Z 版”。点击后会打开发布页面，并按发布附带的 `SHA256SUMS.txt` 校验`win-x64.exe` 安装程序，再保存到“下载”文件夹。安装需要你自己完成。已是最新时，该项显示“当前已是最新版本。”，点击会打开项目页面。离线等原因导致查询失败时，该项不出现。

## 构建

```powershell
git clone https://github.com/habinsong/negaflow.git
cd negaflow\negaflow-windows

# 构建 C++ 引擎
.\scripts\build.ps1 -Preset x64-release

# 构建应用并启动
.\scripts\run-app.ps1 -Architecture x64 -Configuration Release
```

`build.ps1` 接受 `x64-debug`、`x64-release`、`arm64-debug` 和 `arm64-release`。

开发时只用 `run-app.ps1` 启动应用。应用以 MSIX 包的形式构建，直接运行构建目录里的 exe 不会有任何反应。脚本会构建包、为当前用户注册，再按应用 ID 启动。

构建安装程序：

```powershell
.\scripts\build-release.ps1 -Architecture x64
```

输出在 `out\release\win-x64`。

## 检查

```powershell
# C++ 引擎测试
ctest --preset x64-release --output-on-failure

# 应用和目录测试
.\scripts\test-managed.ps1

# 引擎与应用的边界测试
.\scripts\test-interop.ps1

# 以上全部一次运行
.\scripts\local-ci.ps1
```

`scripts\verify-installer.ps1`（`local-ci.ps1` 也会调用）要在已登录的桌面会话里运行。在 SSH 会话中，AppX 注册可能以 `0x80070005` 失败，脚本会在碰到现有安装之前停止。

CI 只运行自成一体的引擎测试。macOS 参考文件放在 Git 之外。要运行这些对比，在配置 CMake 时把 `NEGAFLOW_MACOS_GOLDEN_ROOT` 设为参考目录。目录里必须有 `task6-metadata-policy`、`task9-bw-slide`、`task7-coreimage-filters`、`task8-digital-film-look` 和 `vibrance`。文件缺失或无法读取时，所选对比会失败。`ctest --preset x64-release -L external-golden` 运行这些对比，普通单元测试保持开启。

## Custom 色彩目标

目标胶囊按 MAIN、HS、SP、F135、HR 的顺序排列，CS 在最后。选中 CS 后，左下角会展开 18 个 Custom 目标的两列列表，分为 11、4、3 个三组；风格选择器仍在右侧。进入 CS 时选中 Emulsion，已经在用 Custom 目标的照片保持原目标。

Custom 使用与 macOS 相同的 custom-3 系数和字符串 ID。所选目标保存在照片设置和目录里，预览和导出运行同一个阶段。文件夹标题处用现有的应用按钮，把所选目标应用到整个文件夹。

## 用命令行检查引擎

`negaflow-cli.exe` 对单个文件运行引擎。它接受参数标志，而不是子命令。

```powershell
$cli = "out\build\native\x64-release\Release\negaflow-cli.exe"

# 构建信息
& $cli --build-info

# 扫描文件里有什么
& $cli --probe-tiff scan.tif

# 显影并存为 16 位 TIFF
& $cli --export-developed-tiff16 scan.tif out.tif

# 一次显影的耗时分布
& $cli --develop-timing scan.tif

# 自动测量片基及其选择结果
& $cli --auto-base-probe scan.tif
```

不带参数运行可以看到完整列表。

## 扫描仪

安装插件之前，扫描仪控件不会显示。SANE 设备由单独安装的 [`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane) 负责。

插件通过 Windows 自带的驱动路径访问扫描仪，所以同一台电脑上可以继续保留 VueScan 或 SilverFast。

## 出问题时

应用把文本日志写到 `%LOCALAPPDATA%\Negaflow\Logs`。

| 文件 | 记录的内容 |
|---|---|
| `export-trace.txt` | 导出和快速导出，包括失败 |
| `termination.txt` | 应用关闭期间发生的事 |
| `settings-change.txt` | 改动的设置，以及改动来源 |

这三个始终开启。另外两个默认关闭：

- `preview-trace.txt`：在同一文件夹里新建空文件 `preview-trace.on` 即可开启。
- `stage-trace.txt`：启动应用之前设置环境变量 `NEGAFLOW_STAGE_TRACE=1`。它记录显影每个阶段的像素统计。

## 目录结构

```
negaflow-windows/
├── src/
│   ├── Native/        Chroma Engine、GrainMend、解码与导出 (C++)
│   ├── Interop/       引擎与应用之间的层 (C#)
│   ├── Catalog.Core/  图库存储 (C#)
│   ├── Shell.Core/    显影、印相、导出逻辑 (C#)
│   ├── Shell/         图库、显影、印相界面 (WinUI 3)
│   └── Cli/           引擎检查工具 (C++)
├── scripts/           构建、测试、打包脚本
├── tests/             引擎、应用、边界测试
└── Installer/windows/ NSIS 安装程序
```

## 相关文档

- [两个版本的差异](../../docs/zh-Hans/platform/PLATFORM_DIFFERENCES.md)
- [Chroma Engine](../../docs/zh-Hans/product/CHROMA_ENGINE.md)
- [GrainMend](../../docs/zh-Hans/product/GRAINMEND.md)
- [产品结构](../../docs/zh-Hans/architecture/PRODUCT_ARCHITECTURE.md)
