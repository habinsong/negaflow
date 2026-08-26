# スキャナーCLI JSON

[ドキュメントホーム](../README.md)

スクリプトや他のアプリがスキャナー情報を読むための規格です。
実際のスキャナー実装とは分けてあります。
CLIは`ScannerKit`が受け取った装置情報と機能をJSONに変えるだけです。

| 項目 | 契約 |
|---|---|
| 対応コマンド | `detect --json`、`capabilities <scannerID> --json` |
| stdout | JSON文書1つと最後の改行 |
| stderr | 診断ログ |
| 現在のスキーマ | `negaflow.scanner-cli`、バージョン`1` |

## コマンド

```bash
negaflow detect [--demo] --json
negaflow capabilities <scannerID> [--demo] --json
```

今のところ`--json`は上の2つの読み取り専用コマンドだけで使えます。
ファイルを変えたり進捗を送る `scan`、`develop`に付けると`unsupported_json_command`エラーで終わり
ます。

## 共通の形

成功でも失敗でも、stdoutにはJSON文書を1つだけ書きます。最後に改行が入ります。

<details>
<summary>成功応答の例</summary>

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

失敗すると`status`は`error`、`payload`は`null`です。
`error`には変わらない機械用コードと人が読む説明が入ります。診断ログはstderrに送ります。
stdoutにログや進捗を混ぜません。

## 機能情報

`capabilities`の`payload`には次のフィールドがすべて入ります。

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

装置が知らせなかった値は推測しません。
値に応じて`null`、空の配列、`false`、またはプラグインが送った`disabledReasons`をそのまま使います
。

`estimatedScanSpeeds`は次のオブジェクトの配列で、DPIの昇順です。

```json
{ "dpi": 3600, "seconds": 42.0 }
```

アプリの画面とCLIは同じ`ScannerCapabilities`を読みます。
一致検査では、画面で開いている機能と JSONフィールドが同じ値に従っているかを確認します。

## バージョンの決まり

- 既存フィールドの意味と型は変えません。
- 新しい任意フィールドは、以前のプログラムが知らないフィールドを無視できるときだけ足します。
- フィールドの削除、名前変更、型変更のときは`schemaVersion`を上げます。
- 解像度、モード、ビット深度はプラグインの順序を守ります。
- DPIで並べ替えるのは推定速度だけです。
