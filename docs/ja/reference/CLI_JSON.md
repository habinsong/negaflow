# スキャナーCLI JSON

[ドキュメントホーム](../README.md)

スクリプトや他のアプリは、この JSON でスキャナー情報を読みます。CLI は、`ScannerKit` が受け取った機器情報と機能を JSON に直すだけです。

| 項目 | 規約 |
|---|---|
| コマンド | `detect --json`、`capabilities <scannerID> --json` |
| stdout | JSON ドキュメント1つと末尾の改行 |
| stderr | 診断ログ |
| スキーマ | `negaflow.scanner-cli`、バージョン `1` |

## コマンド

```bash
negaflow detect [--demo] --json
negaflow capabilities <scannerID> [--demo] --json
```

`--json` が使えるのは、読み取り専用のこの2つのコマンドだけです。`scan` や `develop` に付けると `unsupported_json_command` エラーで終わります。

## 共通の形

成功でも失敗でも、stdout に JSON ドキュメントを1つ書きます。

<details>
<summary>成功レスポンスの例</summary>

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

失敗すると `status` は `error`、`payload` は `null` になります。`error` には、変わらない機械向けコードと説明が入ります。ログと進行状況は stderr にだけ出ます。

## 機能情報

`capabilities` の payload には、次のフィールドが必ずすべて入ります。

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

機器が報告しなかった値は推測しません。`null`、空の配列、`false`、またはプラグインが送った `disabledReasons` になります。

`estimatedScanSpeeds` は次のオブジェクトの配列で、DPI の昇順です。

```json
{ "dpi": 3600, "seconds": 42.0 }
```

アプリと CLI は同じ `ScannerCapabilities` を読みます。画面のコントロールが JSON のフィールドに従っているかは、整合性チェックで確かめます。

## バージョン規則

- 既存フィールドの意味と型は変えません。
- 新しい任意フィールドは、古いプログラムが知らないフィールドを無視できるときだけ追加します。
- フィールドの削除、名前の変更、型の変更をしたら `schemaVersion` を上げます。
- 解像度、モード、ビット深度はプラグインが渡した順序のままです。推定速度だけを DPI 順に並べます。
