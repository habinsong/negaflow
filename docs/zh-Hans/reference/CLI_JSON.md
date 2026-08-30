# 扫描仪 CLI JSON

[文档首页](../README.md)

这是脚本或其他应用读取扫描仪信息用的规格，和实际的扫描仪实现分开。 CLI 只是把 `ScannerKit` 收到的设备信息和功能转成 JSON。

| 项目 | 约定 |
|---|---|
| 支持的命令 | `detect --json`、`capabilities <scannerID> --json` |
| stdout | 一个 JSON 文档加末尾换行 |
| stderr | 诊断日志 |
| 当前 schema | `negaflow.scanner-cli`，版本 `1` |

## 命令

```bash
negaflow detect [--demo] --json
negaflow capabilities <scannerID> [--demo] --json
```

目前 `--json` 只能用在上面两个只读命令上。 加在会改文件或发进度的 `scan`、`develop` 上，会以 `unsupported_json_command` 错误结束。

## 通用格式

无论成功还是失败，stdout 只写一个 JSON 文档，末尾带换行。

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

失败时 `status` 是 `error`，`payload` 是 `null`。`error` 里有不会变的机器码和给人看的说明。 诊断日志走 stderr，stdout 里不混日志和进度。

## 功能信息

`capabilities` 的 `payload` 一定包含下面全部字段。

- `resolutionsDPI`、`modes`、`bitDepths`
- `sourceModes`、`transparencyModes`
- `supportsPreview`、`supportsTransparency`、`supportsInfrared`
- `supportsMultiExposure`、`supportsScanArea`、`supportsPositionedScanArea`
- `supportsLampWarmupStatus`
- `brightnessRange`、`contrastRange`、`hardwareExposureRange`
- `scanOriginXRange`、`scanOriginYRange`、`scanWidthRange`、`scanHeightRange`
- `disabledReasons`
- `minScanArea`、`maxScanArea`、`scanAreaUnit`
- `outputFormats`、`estimatedScanSpeeds`

设备没报的值不会去猜。视情况用 `null`、空数组、`false`，或者直接用插件发来的 `disabledReasons`。

`estimatedScanSpeeds` 是下面这个对象的数组，按 DPI 升序。

```json
{ "dpi": 3600, "seconds": 42.0 }
```

应用界面和 CLI 读的是同一份 `ScannerCapabilities`。 一致性检查会确认界面上打开的功能和 JSON 字段遵循同样的值。

## 版本规则

- 已有字段的含义和类型不变。
- 只有旧程序能忽略未知字段时，才加新的可选字段。
- 删除字段、改名或改类型时，提升 `schemaVersion`。
- 分辨率、模式、位深保持插件给的顺序。
- 只有预计速度按 DPI 排序。
