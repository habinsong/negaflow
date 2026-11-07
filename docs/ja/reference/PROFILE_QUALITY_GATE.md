# スキャナープロファイル品質判定

[ドキュメントホーム](../README.md)

`scripts/evaluate_profile_quality.py`(`negaflow-mac/` で実行)は、スキャナープロファイルを変えた結果が、承認済みの基準線より悪くなっていないかを調べます。`LUT_target/analyze_lut_target.py` が作った `SOURCE/summary.json` を2つ比べ、プロファイルの調整に使わずに取り分けた検証ケースだけを判定に反映します。

このツールは、良い色とは何かを決めません。どの数値が下がるべきか上がるべきか、どこまで動いてよいかは、人がコーパスマニフェストに書きます。既定の合格ラインはありません。

現在このリポジトリには REAL/TARGET の画像ペアがありません(`LUT_target/REAL` と `LUT_target/TARGET` は空です)。そのため、実際のコーパスマニフェストも、承認済みの基準線も、実機の合格結果もありません。合成テストが確かめるのは、検査ツールのコードだけです。

> [!WARNING]
> スキャナーの色の正確さは、このリポジトリだけでは承認できません。リリースの判断には、固定した REAL/TARGET ペア、調整に使っていない検証ケース、人が決めた許容差が必要です。

## 現在のプロファイルをアプリが使う範囲

ユーザー自身が `HS` または `SP` ターゲットを選ぶと、同梱の `realOnly` グループから得た限定的な相対差を使えます。

条件:

- フィルムの種類とフィルム名が一致する。
- 整理した元ロール名の集合が一致する。
- 画像数の差が15%以下である。

元のプロファイルにはフレームごとの ID や SHA-256 がなく、ロール名が一致しても同じフレームを対にした証拠にはなりません。そのため、実機と同じ結果とは呼べません。

適用の規則:

- 2つのグループで向きが逆の値は適用しません。
- 白黒では色成分をすべて捨て、相対的なトーンだけを残します。
- 対応するロールがないスライドのプロファイルには、相対補正を適用しません。
- 同じ位置で対になる資料がなければ、スキャナーのテクスチャとシャープネスは適用しません。
- トーンは Rec.709 ガンマの明るさに1回だけ適用し、Lab の `a*` と `b*` は保ちます。
- 色ゲインは対数領域で補間し、反対側の基準点との関係を保ちます。
- ファイルまたはマニフェストのどれかの SHA-256 が合わなければ、プロファイルのバンドル全体を拒否します。

## メーカー資料で確認できること

- [Fujifilm Frontier 570/SP-3000 のガイド](https://www.photolabdigital.com/fuji_frontier570_en%5B1%5D.pdf)は、エリア CCD、Hyper-tone、Hyper-sharpness などの機能を挙げていますが、伝達関数や設定値は公開していません。
- [Noritsu HS-1800 の製品情報](https://www.noritsu.eu/hardware/noritsu-film-scanner.html)は、対応規格、解像度、処理能力を載せていますが、固定の色の伝達関数は示していません。
- [Noritsu の特許 US 7,589,863](https://patents.google.com/patent/US7589863/en)は、オペレーターが濃度、階調、シャープネスを選ぶミニラボの流れを説明しています。

これらの資料が示すのは、処理がシーンとオペレーターで変わるということです。HS-1800 や SP-3000 を再現する定数は得られず、negaflow は製品名からそのような値を推測しません。

## コーパスマニフェストのスキーマ v1

マニフェストは、固定したい入力資料の隣に置きます。例: `LUT_target/quality/corpus-v1.json`。パスはマニフェストファイルからの相対で、`--data-root` を指定したときはそのパスが基準です。

<details>
<summary>マニフェストの例</summary>

```json
{
  "schemaVersion": 1,
  "corpusVersion": "scanner-corpus-2026-07-10.1",
  "acceptedBaselineSHA256": "sha256:<64 lowercase hex>",
  "cases": [
    {
      "role": "calibration",
      "stem": "NORITSU/color nega/Portra 400/calibration-01",
      "real": {
        "path": "REAL/NORITSU/color nega/Portra 400/calibration-01.tif",
        "sha256": "sha256:<64 lowercase hex>"
      },
      "target": {
        "path": "TARGET/NORITSU/color nega/Portra 400/calibration-01.tif",
        "sha256": "sha256:<64 lowercase hex>"
      }
    },
    {
      "role": "holdout",
      "stem": "NORITSU/color nega/Portra 400/holdout-01",
      "real": {
        "path": "REAL/NORITSU/color nega/Portra 400/holdout-01.tif",
        "sha256": "sha256:<64 lowercase hex>"
      },
      "target": {
        "path": "TARGET/NORITSU/color nega/Portra 400/holdout-01.tif",
        "sha256": "sha256:<64 lowercase hex>"
      }
    }
  ],
  "metrics": [
    {
      "name": "mean_delta_e2000",
      "direction": "lowerIsBetter",
      "allowedRegression": 0.0
    },
    {
      "name": "similarity_score_0_100",
      "direction": "higherIsBetter",
      "allowedRegression": 0.0
    },
    {
      "name": "neutral_a_shift",
      "direction": "absoluteLowerIsBetter",
      "allowedRegression": 0.0
    }
  ]
}
```

</details>

`0.0` は推奨値ではありません。測り方とリリース方針に合わせて、項目と許容差を決めてください。

## マニフェストの規則

- `schemaVersion` はちょうど `1` でなければなりません。未知のバージョンと未知のフィールドは拒否します。
- `corpusVersion` は、資料の固定した選び方と分割につける名前です。
- `acceptedBaselineSHA256` は、承認済みの `summary.json` のバイト列をそのまま固定します。
- ケースは `calibration` か `holdout` のどちらかです。名前は重複できません。
- 資料は空にできず、2つの役割それぞれに1件以上のケースが必要です。
- REAL と TARGET のファイルは、どちらも `sha256:<小文字16進64桁>` で固定します。
- 指標の名前は重複できません。
- `allowedRegression` は0以上の有限の数でなければなりません。真偽値は拒否します。
- 方向として受け付けるのは `lowerIsBetter`、`higherIsBetter`、`absoluteLowerIsBetter` だけです。

`absoluteLowerIsBetter` は0からの距離を比べます。0がレビュー済みの基準であるときだけ使ってください。

## 候補と承認済みの基準線の準備

```bash
python3 LUT_target/analyze_lut_target.py
```

リリースを承認する前に、候補の `SOURCE/summary.json` 全体を、次の承認済み基準線のファイルとして保管します。候補がレビューを通るまで、既存の承認済みファイルは上書きしません。承認済みファイルの正確な SHA-256 を `acceptedBaselineSHA256` に入れます。

候補と基準線のサマリーには、マニフェストの各ケースがちょうど1回ずつ入っている必要があります。欠けたケース、重複、処理の失敗、マニフェストにないケースは入力エラーです。

`calibration` ケースはプロファイルの当てはめに使えますが、判定には数えません。`holdout` ケースは調整と選択から外します。検証の数値はケースごとに比べるので、平均が良くなっても1枚の悪化は隠せません。

## 実行

<details open>
<summary>品質判定のコマンド</summary>

```bash
python3 scripts/evaluate_profile_quality.py \
  --manifest LUT_target/quality/corpus-v1.json \
  --candidate-summary LUT_target/SOURCE/summary.json \
  --baseline-summary LUT_target/quality/accepted-summary-v1.json \
  --data-root LUT_target \
  --verify-files all \
  --report build/profile-quality-report.json
```

</details>

ファイル検証のモード:

| 値 | 内容 | リリースの根拠として使えるか |
|---|---|---|
| `all` | REAL/TARGET の全ファイルのパスと SHA-256 を確認 | 使える |
| `holdout` | 検証ファイルだけを確認 | 手早い診断用 |
| `none` | 画像ファイルを確認しない | 使えない |

既定は `all` です。レポートには、使ったモード、マニフェストとサマリーファイルのハッシュ、ファイル検証の結果、検証セットのケースごとの比較と件数が記録されます。同じ JSON が stdout と `--report` ファイルに出力され、ファイルはアトミックに保存されます。

終了コード:

- `0`: 入力が有効で、許容差を超える悪化がない
- `1`: 入力は有効だが、検証値が1つ以上範囲を外れた
- `2`: スキーマ、資料、ハッシュ、パス、指標が誤っているか欠けている

## 検査ツールのテスト

```bash
python3 -m unittest scripts/tests/test_evaluate_profile_quality.py
```

テストは一時的な合成ファイルで、正常な比較、悪化、ハッシュの変更、誤ったスキーマと数値、重複・欠落・失敗したケース、空の資料を確かめます。実際のスキャナー出力の品質を証明するものではありません。
