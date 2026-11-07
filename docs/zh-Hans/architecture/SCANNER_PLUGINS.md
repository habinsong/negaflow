# 扫描仪插件结构

[文档首页](../README.md)

negaflow 的默认输入是导入图像。只有存在外部插件时，才会连接真实的扫描仪。

> [!IMPORTANT]
> 应用不会根据扫描仪型号猜测功能。只有插件报告的内容才会进入界面和请求，演示设备只在你自己选择演示模式时出现。

## 组成部分

| 部分 | 作用 |
|---|---|
| 图像导入 | 把 RAW、DNG、TIFF、PNG 和 JPEG 送进显影路径。 |
| 外部插件 | 作为独立进程运行，驱动真实设备，通过 JSON 通信。 |
| 演示扫描仪 | 提供开发用的 `negaflow Scanner` 和 `negaflow Flatbed Scanner`。必须自己选择演示才能使用。 |
| ImageCaptureCore 连接 | 面向 macOS 图像捕捉设备的兼容代码，目前未启用。 |

这个仓库里没有 SANE 的实现。那部分代码在单独的 GPL 项目里：

- <https://github.com/habinsong/negaflow-scanner-sane>

## 连接方式

界面与 `ScannerKit` 通信，`ScannerKit` 把请求交给三个后端之一：

1. `ExternalScannerBackend`：运行已安装的外部插件。
2. `MockScannerBackend`：生成开发用的合成图像。
3. `InactiveImageCaptureBackend`：目前未启用。

界面只看到 `ScannerBackend`。插件的设备 ID 在应用里显示为 `plugin:<pluginId>:<deviceId>`。

运行插件时，会去掉 `plugin:<pluginId>:`，只发送插件自己的设备 ID。

## 查找插件

默认文件夹是 `~/Library/Application Support/negaflow/Plugins/<id>/manifest.json`。测试和本地开发时，用 `NEGAFLOW_PLUGINS_DIR` 指向其他文件夹。

| 字段 | 规则 |
|---|---|
| `schemaVersion` | 目前恰好是 `1` |
| `protocolVersion` | 省略时为 `1`，支持 `1` 和 `2` |
| `id` | 唯一的插件 ID |
| `name` | 界面上显示的名称 |
| `kind` | 插件类型 |
| `license` | 分发许可证 |
| `homepage` | 项目地址 |
| `executable` | 可执行文件路径 |

`id` 是 1 到 64 个 ASCII 字符。第一个是字母或数字，其余是字母、数字、`.`、`_` 或 `-`。`:` 是设备 ID 的分隔符，所以不允许使用。

只有清单和可执行文件都通过检查，插件才会打开。旧的或未来的架构以及未知的协议，不会靠猜测去读取。

### 文件安全检查

> [!WARNING]
> 清单或可执行文件的字节一旦变化，之前的批准就作废。所有者、权限、是否为符号链接以及 SHA-256，会在运行前再次检查。

- 插件文件夹、清单和可执行文件必须归当前用户所有。
- 组或其他用户可写时拒绝。
- 拒绝符号链接。
- 记录清单和可执行文件的 SHA-256。
- 首次使用时由用户批准。
- 文件字节变化会使批准失效。
- ID 在运行前重新计算。

## 命令

插件作为独立进程运行。

| 命令 | 结果 |
|---|---|
| `detect` | JSON 设备列表 |
| `capabilities <deviceId>` | JSON 能力列表。可通过 stdin 接收 `detect` 报告的设备 ID、厂商和型号 JSON |
| `scan` | stdin 接收设置 JSON；stdout 输出进度 NDJSON 和最终结果 |

## 扫描协议

### 版本 1

较早的兼容规范。请求和 NDJSON 里没有 `protocolVersion`、`requestID` 和 `sequence`。它无法报告实际应用的设置，所以结果记为 `.unknownLegacy(protocolVersion: 1)`。请求里的值不会被当作已验证而照抄过来。

### 版本 2

仅当清单带有 `"protocolVersion": 2` 时使用。

请求包含：

- `protocolVersion: 2`
- 应用生成的 `requestID` UUID

`capabilities` 响应可以返回可选字段 `capabilityToken`。应用不解释它，只把它原样传给同一设备的下一个 v2 `scan` 请求，不会用于别处。v1 请求里不带它，不同设备之间也不会混用令牌。令牌的格式和有效性要由插件自己检查。

为避免错误地重新连到同一后端的另一个型号，应用会把上次 `detect` 的 `deviceID`、`vendor` 和 `model` 作为 `capabilities` 的可选 stdin JSON 传回去。现有插件可以忽略这个输入。设备地址可能变化的插件，应把这份身份信息绑进能力快照，并在下一次 `scan` 时再次检查。

每个 NDJSON 事件都重复相同的版本和请求 ID，并带有一个大于前一个事件、不小于 0 的 `sequence`。只允许 `progress`、`result` 和 `error`。`result` 和 `error` 是最终事件，其后再有任何内容都算失败。没有以错误结束的扫描，恰好有一个 `result`。

以下情况全部按失败关闭处理：

- 无法读取的事件
- 缺少或不同的版本或请求 ID
- 重复或乱序的 sequence
- 未知事件
- 重复的 result
- 最终事件之后的多余输出
- 无效的 UTF-8

违反 v2 规范时，插件会被立即结束，不再等待通常的超时。

### 实际应用的设置

v2 的 `result` 必须带有 `appliedOptions`：

- `deviceID`、`resolutionDPI`、`bitDepth`、`colorMode`、`filmType`
- `scanArea`：`originXMM`、`originYMM`、`widthMM`、`heightMM`，即插件实际发给后端的区域。为绕开算错扫描尺寸的后端，插件可以做小于 1 mm 的调整。应用会用这个区域核对返回的像素尺寸，所以照抄请求会使检查失去意义。
- `infrared`、`multiExposure`
- `hardwareExposureTime`、`brightnessAdjustment`、`contrastAdjustment`
- `outputRawTIFF`

最后三项调整即使值为 `null`，键也必须存在。

`resolutionDPI: 0` 表示预览。不为 0 的预览或为 0 的正式扫描都会被拒绝。未知的值、不同的设备，以及结果头与 `appliedOptions` 之间不一致的分辨率、位深或 IR 状态，同样被拒绝。

检查通过后，应用记录自己的扫描仪 ID 和请求 ID，而不是插件 ID，并保留最终的输出路径。到这时才标记为 `.verified(options)`。

在 v1 中，`ScanResult.resolution` 和 `bitDepth` 可能回退为请求值。表示来源的 `reportedResolution` 和 `reportedBitDepth` 只接受结果自己报告的正确值。

## 指定位置的平板扫描区域

这个工作流的预览会明确请求一个分辨率（最接近 300 dpi 的受支持值），而不是交给设备决定。设备默认值可能低至 25 dpi，对摆放画幅和检测画幅来说都太粗。带分辨率的预览属于普通扫描，所以不走插件的预览路径。

只有插件报告以下全部内容时，才会启用指定位置的平板扫描：

- 预览
- `supportsPositionedScanArea`
- 以 mm 计的 `scanOriginXRange` 和 `scanOriginYRange`
- 以 mm 计的 `scanWidthRange` 和 `scanHeightRange`

应用把选定的区域向外扩展到插件的步长，并为每个区域生成一个正式扫描任务。不会凭型号猜测。没有这些可选字段的旧插件保持固定画幅的流程。

## 进程限制与取消

- stdout 上限：4 MiB
- stderr 上限：1 MiB

超过上限会结束进程并判定失败。清理时只读取已经到达的字节。即使子进程继承了管道，也不会等待 EOF。

`cancelScan()` 要等插件结束、管道处理器关闭、下一个任务的位置空出之后才返回。

## 发布扫描文件

插件把源图像写到应用给出的 `outputPath`，并在结果中返回同一路径。该路径是与最终文件夹同一磁盘上的临时位置。流程如下：

1. 应用把设置 JSON 和 `outputPath` 发给插件。
2. 插件把扫描文件写入临时文件夹。
3. 插件返回带有相同 `outputPath` 的结果。
4. 应用检查格式、尺寸和路径。
5. 检查通过后，应用以原子方式发布到最终的扫描文件夹。取消、失败或输出有误时，则删除临时材料。

应用会确认：

- 非空的普通文件
- ImageIO 能读取的图像
- 预期的格式和像素尺寸
- 请求与结果中的路径相同

取消、超时、输出有误或插件失败时，会删除临时文件夹，不发布不完整的扫描。

v2 的 IR 文件同样必须位于应用给出的临时文件夹内，并检查文件类型、可读性和像素尺寸。v1 为兼容已有的插件，可以接受外部的 IR 路径。

## SANE 边界

SANE 的实现、依赖、配置、针对具体设备的处理、测试和发布文档，都在单独的 [`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane) 仓库里。

该项目发布使用 Homebrew 原版 SANE 的标准 macOS 14+ 安装程序，以及另一个 macOS 26+ 的 Coolscan 安装程序，后者用上游最小的 `coolscan2`/`coolscan3` 内存分配修复来构建官方 SANE 1.4.0。标准路径不会主动阻止 Coolscan，但不含该修复。

本仓库只记录并检查与设备无关的外部进程规范。只导入图像文件的用户不需要扫描仪插件。

negaflow 应用不链接 SANE 的实现，也不把它放进应用分发包。插件有自己的仓库、可执行文件、源码分发和 GPL 许可证。本文只记录结构，不判定是否构成衍生作品。在实际发布之前，会再次核对两种产物里的文件和通信约定。

## 检查

应用测试把一个假的外部插件作为真实进程运行，并确认：

- 查找插件
- 查找设备
- 能力连接
- 进度事件
- 最终结果
- 取消和失败之后的清理

SANE 的实现在插件仓库的 SwiftPM 测试和 Release 构建里单独检查。
