# 扫描仪 CLI JSON

[文档首页](../README.md)

脚本和其他应用通过这份 JSON 读取扫描仪信息。CLI 只是把 `ScannerKit` 收到的设备信息和能力转成 JSON。

| 项目 | 约定 |
|---|---|
| 命令 | `detect --json`、`capabilities <scannerID> --json` |
| stdout | 一份 JSON 文档加结尾换行 |
| stderr | 诊断日志 |
| 模式 | `negaflow.scanner-cli`，版本 `1` |

## 命令

```bash
negaflow detect [--demo] --json
negaflow capabilities <scannerID> [--demo] --json
```

`--json` 只对这两个只读命令有效。加在 `scan` 或 `develop` 上，会以 `unsupported_json_command` 错误结束。

## 通用结构

成功和失败都向 stdout 写一份 JSON 文档。

<details>
<summary>成功响应示例</summary>

```json
{
  "schema": "negaflow.scanner-cli",
  "schemaVersion": 1,
  "command": "capabilities",
  "status": "ok",
  "payload": {},
  "error": null
}
```

</details>

失败时 `status` 为 `error`，`payload` 为 `null`。`error` 包含稳定的机器可读代码和说明。日志和进度只写到 stderr。

## 能力信息

`capabilities` 的 payload 始终包含以下全部字段：

- `resolutionsDPI`, `modes`, `bitDepths`
- `sourceModes`, `transparencyModes`
- `supportsPreview`, `supportsTransparency`, `supportsInfrared`
- `supportsMultiExposure`, `supportsScanArea`, `supportsPositionedScanArea`
- `supportsLampWarmupStatus`
- `brightnessRange`, `contrastRange`, `hardwareExposureRange`
- `scanOriginXRange`, `scanOriginYRange`, `scanWidthRange`, `scanHeightRange`
- `disabledReasons`
- `minScanArea`, `maxScanArea`, `scanAreaUnit`
- `outputFormats`, `estimatedScanSpeeds`

设备没有报告的值不做猜测，会成为 `null`、空数组、`false`，或插件发来的 `disabledReasons`。

`estimatedScanSpeeds` 是下面这种对象的数组，按 DPI 升序排列：

```json
{ "dpi": 3600, "seconds": 42.0 }
```

应用和 CLI 读取同一个 `ScannerCapabilities`。一致性检查确认界面上的控件遵循 JSON 字段。

## 版本规则

- 已有字段的含义和类型不变。
- 只有旧程序可以忽略新字段时，才加入新的可选字段。
- 删除、改名或改变类型的字段会提高 `schemaVersion`。
- 分辨率、模式和位深保持插件给出的顺序。只有预估速度按 DPI 排序。
