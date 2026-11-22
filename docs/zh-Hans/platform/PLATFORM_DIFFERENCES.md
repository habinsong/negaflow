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
- 各格式的导出文件命名，以及 JPEG、TIFF 和 DNG 上的 EXIF 与元数据策略（在 Windows 上，PNG 导出保留 DPI 和 ICC 配置文件，不含 EXIF 元数据）
- 目录格式（`library.sqlite`）

## 不同的部分

### 色彩管理

macOS 使用 ColorSync，Windows 使用 ICM。两者读取同样的 ICC 配置文件，在舍入误差内得到相同数值。这是最容易悄悄偏离的部分，所以一致性测试覆盖了它。

屏幕显示方面，macOS 通过显示器的 ColorSync 配置文件绘制。Windows 只有在开启 Advanced Color 时才这样做。关闭时，Windows 把应用像素当作 sRGB 直接送到显示器，所以 negaflow 在绘制前通过 33³ LUT 把冲洗画布和打印预览（包括较小的印样缩略图块）转换到显示器的 ICC 配置文件，并在切换显示器或修改显示设置后回到窗口时自动刷新。缩略图和界面其余部分按 sRGB 绘制。

### 图形

macOS 在 Core Image 上运行显影链，默认采用 16 位半精度浮点线性格式（`RGBAh`）。Windows 在 Direct3D 11 计算着色器上运行，GPU 路径不可用时退回 CPU，两条路径都使用 32 位浮点精度（`RGBA32F`）。

### 文件位置

| | macOS | Windows |
|---|---|---|
| 应用 | `/Applications/negaflow.app` | `%LOCALAPPDATA%\Negaflow\App` |
| 目录、缺陷边车文件、配方、印相模板 | `~/Library/Application Support/negaflow` | `%LOCALAPPDATA%\Negaflow` |
| 应用偏好设置 | `UserDefaults`（`~/Library/Preferences/com.songhabin.negaflow.plist`） | `%LOCALAPPDATA%\Negaflow` |

### 安装与卸载

macOS 以 PKG 分发，把应用装进 `/Applications`；卸载时把应用拖进废纸篓。Windows 安装程序写入 `%LOCALAPPDATA%\Negaflow\App`，仅在 Windows 尚未允许注册未签名的松散应用包（`AllowDevelopmentWithoutDevLicense`）时请求一次管理员确认。卸载通过开始菜单里的 `Uninstall negaflow` 或设置进行，会清除应用文件夹、开始菜单条目和包注册。

### 命令行

GUI 发行版安装程序不包含命令行程序，各平台都由源码构建提供 CLI。在 macOS 上通过 `swift build` 构建会得到 `negaflow`，可以检测扫描仪、显影文件、运行 GrainMend 和做基准测试。在 Windows 上通过 CMake 构建会得到 `negaflow-cli.exe`，这是一个较小的诊断工具，用来检查引擎对单个文件做了什么，接受参数标志而不是子命令。

### 签名

两个版本都没有用付费开发者证书签名，所以两个系统在首次启动时都会警告。Mac 版是 ad hoc 签名，没有经过公证，在隐私与安全性里点「仍要打开」即可放行。Windows 安装程序没有签名，在 SmartScreen 里点「更多信息」后再运行。

## 扫描仪

扫描仪插件是独立的 GPL 项目 [`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane)，两个系统都有对应版本。它作为单独进程运行，通过 JSON 通信，所以 negaflow 本体在两个平台上都不含 SANE 代码。在 Windows 上它走 Windows 自带的扫描仪驱动路径，因此同一台电脑上的 VueScan 和 SilverFast 仍然可用。

## 如何保持一致

每个功能先在 macOS 上完成，再对照 macOS 的实际行为移到 Windows。凡是能测量输出的地方，由 macOS 基准图像判定 Windows 是否正确。两边不一致时，以 macOS 为准，问题出在 Windows 一侧。
