# macOS 版和 Windows 版的差异

[文档首页](../README.md)

negaflow 有两套，一套给 macOS，一套给 Windows。两套不共享源代码，各自按所在系统的方式编写。

## 为什么做两套

用一套跨平台代码，就意味着选定一个工具包，并在两个系统上接受它的妥协：菜单和文件对话框行为古怪，颜色多经过一层转换，窗口与系统风格不一致。为每个系统分别原生编写，工作量大约翻倍，因为每个功能都要做两遍、测两遍。作为回报，两个版本在各自系统上的表现都符合人们的预期。

## 相同的部分

画面。同一张扫描在两边得到同样的结果。

macOS 版会把一组基准图像渲染到 `docs/verification/macos-golden`。Git 忽略这个文件夹，所以图像只存在于渲染它们的那台电脑上。Windows 引擎测试读取其副本并比较像素值，Windows 引擎一旦偏离，测试就会失败。

以下内容同样一致：

- 片基测量与反相
- 所有显影目标：`MAIN`、`PRINT`、`HS`、`SP`、`F135`、`HR`、`EXPIRED`、`CS`
- 影调、曲线、HSL、颜色分级、黑白调色
- GrainMend 的检测与修复，包括红外路径
- 印相版式与页面几何
- 导出文件命名、EXIF 写入和元数据策略
- 目录格式（`library.sqlite`）

## 不同的部分

### 色彩管理

macOS 使用 ColorSync，Windows 使用 ICM。两者读取同样的 ICC 配置文件，在舍入误差内得到相同数值。这是最容易悄悄偏离的部分，所以一致性测试覆盖了它。

### 图形

macOS 在 Core Image 上运行显影链。Windows 在 Direct3D 计算着色器上运行，GPU 路径不可用时退回 CPU。

### 文件位置

| | macOS | Windows |
|---|---|---|
| 应用 | `/Applications/negaflow.app` | `%LOCALAPPDATA%\Negaflow\App` |
| 图库和设置 | `~/Library/Application Support/negaflow` | `%LOCALAPPDATA%\Negaflow` |

### 安装与卸载

macOS 以 PKG 分发，把应用装进 `/Applications`；卸载时把应用拖进废纸篓。Windows 以安装程序分发，写入用户文件夹，不要求管理员权限；卸载通过开始菜单里的 `Uninstall negaflow` 或设置进行，会清除应用文件夹、开始菜单条目和包注册。

### 命令行

macOS 自带完整的 CLI `negaflow`，可以检测扫描仪、显影文件、运行 GrainMend 和做基准测试。Windows 的 `negaflow-cli.exe` 是较小的诊断工具，用来检查引擎对单个文件做了什么，它接受参数标志，而不是子命令。

### 签名

两个版本都没有用付费开发者证书签名，所以两个系统在首次启动时都会警告。Mac 版是 ad hoc 签名，没有经过公证，在隐私与安全性里点「仍要打开」即可放行。Windows 安装程序没有签名，在 SmartScreen 里点「更多信息」后再运行。

## 扫描仪

扫描仪插件是独立的 GPL 项目 [`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane)，两个系统都有对应版本。它作为单独进程运行，通过 JSON 通信，所以 negaflow 本体在两个平台上都不含 SANE 代码。在 Windows 上它走 Windows 自带的扫描仪驱动路径，因此同一台电脑上的 VueScan 和 SilverFast 仍然可用。

## 如何保持一致

每个功能先在 macOS 上完成，再对照 macOS 的实际行为移到 Windows。凡是能测量输出的地方，由 macOS 基准图像判定 Windows 是否正确。两边不一致时，以 macOS 为准，问题出在 Windows 一侧。
