# macOS 版和 Windows 版的差异

[文档首页](../README.md)

negaflow 有两套。macOS 版是 Core Image 上的 Swift 和 SwiftUI，Windows 版是 Direct3D 上的 C++ 引擎加 C# 和 WinUI 3。两者不共用源码。

这一页写清楚：实际上哪些一样、哪些看起来不同、哪些只有一边有。

## 做两套的理由

用一套代码覆盖两个系统，就要挑一个跨平台工具包，然后在两边都接受它的结果。菜单位置不对， 文件对话框行为古怪，颜色多走一层转换，窗口始终不像那个系统上的应用。

按各自平台的方式写，工作量大约翻一倍，每加一个功能都要做两遍、验两遍。换来的是两个版本在各自系统上都符合用户的习惯。

## 一样的部分

出片。同一张扫描交给两边，得到同一张照片。

这不是口头承诺。macOS 版渲染出的基准图放在仓库的 `docs/verification/macos-golden` 里。 Windows 的引擎测试读回这些文件，逐像素比对。改 Windows 引擎时如果偏离了 macOS 的结果， 测试会失败。

下面这些也一样：

- 片基测量与反转
- 全部冲洗目标：`MAIN`、`PRINT`、`HS`、`SP`、`F135`、`HR`、`EXPIRED`
- 影调、曲线、HSL、调色、黑白色调
- GrainMend 的检测与修复，包括红外通路
- 打印布局与页面排布
- 导出文件命名、EXIF 写入、元数据策略
- 图库格式。一边建的图库另一边能读

## 不一样的部分

### 色彩管理

macOS 用 ColorSync，Windows 用 ICM。两者接受同样的 ICC 配置文件，在舍入范围内给出相同的值。 这部分最容易悄悄跑偏，所以基准图比对专门盯着它。

### 图形

macOS 在 Core Image 上跑冲洗流程。Windows 跑在 Direct3D 计算着色器上，遇到用不了 GPU 的机器就退回 CPU。

快慢取决于机器而不是平台。Apple Silicon 的 Mac 和装了独立显卡的 PC，处理一张 35mm 扫描都不用等。

### 文件位置

| | macOS | Windows |
|---|---|---|
| 应用 | `/Applications/negaflow.app` | `%LOCALAPPDATA%\Negaflow\App` |
| 图库与设置 | `~/Library/Application Support/negaflow` | `%LOCALAPPDATA%\Negaflow` |
| 日志 | 控制台与应用支持目录 | `%LOCALAPPDATA%\Negaflow\Logs` |

### 安装与卸载

macOS 用 PKG 把应用装进 `/Applications`。要删除就和别的 Mac 应用一样，拖进废纸篓。

Windows 不要管理员权限，装在用户目录里。卸载走开始菜单的`卸载 negaflow`或者设置，会一并清掉应用目录、开始菜单项和包注册。

### 命令行

macOS 带一个叫 `negaflow` 的 CLI，能找扫描仪、冲洗文件、跑 GrainMend、做性能测试，是给人日常用的。

Windows 带的是 `negaflow-cli.exe`，用来看引擎怎么处理某一个文件。它接受参数标志而不是子命令， 为排查问题准备，不是日常工具。

### 签名

两边都没有用付费开发者证书签名，所以第一次启动都会有提示。macOS 在隐私与安全性里点仍要打开， Windows 在 SmartScreen 点更多信息再点仍要运行。

## 扫描仪

扫描仪插件是另一个 GPL 项目 [`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane)，两个系统都有。 插件作为独立进程运行，用 JSON 通信，所以 negaflow 本体在两个平台上都不含 SANE 代码。

在 Windows 上，插件走系统自带的扫描仪驱动通路，不替换任何东西，VueScan 和 SilverFast 在同一台机器上照常可用。

## 怎么保持一致

功能先落在 macOS，Windows 这边照着 macOS 的实际行为做，而不是照着写好的规格文档。凡是能测输出的部分，由 macOS 的基准图判定 Windows 是否正确。

两边对不上时，macOS 是标准答案，Windows 是 bug。
