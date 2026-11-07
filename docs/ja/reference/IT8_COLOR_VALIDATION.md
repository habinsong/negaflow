# IT8色検査

[ドキュメントホーム](../README.md)

色の正確さは、目視だけでなく測定で確かめる必要があります。IT8 画像を実物ターゲットの基準ファイルと対にして、パッチごとに数値の結果を記録します。

> [!IMPORTANT]
> 公開されている IT8 資料で確かめられるのは、検査ツールと色計算の退行です。実際のスキャナーやカラーネガフィルムの正確さは証明できません。機器を判断するには、確認済みの実物ターゲットと、その機器での実測が必要です。

## 証拠の種類

| 名前 | 確かめられること | 確かめられないこと |
|---|---|---|
| `algorithmRegression` | ファイルの解析、ICC 変換、パッチの面積、Lab、CIEDE2000 | 実際のスキャナーの正確さ |
| `deviceCharacterization` | 確認済みの実物ターゲットを実機で測った結果 | 別のターゲットや機器の正確さ |
| `syntheticModel` | 独立した合成モデルの数学的な往復 | 実際のフィルムや機器の正確さ |

`deviceCharacterization` には、実物ターゲットのメーカー、素材、シリアル、バッチが必要です。1つでも基準ファイルのヘッダーと違えば、何も評価しません。

IT8.7/1 と ISO 12641-1 の透過ターゲットは、ポジの透過原稿向けです。この結果は、カラーネガのオレンジマスク、染料の相互作用、C-41 のばらつき、HS・SP の出力の正確さについて何も語りません。そうした主張には、同じカラーネガを両方の経路に通した対の資料と、別の検証セットが必要です。

公開されている FADGI OpenDICE の画像と基準のペアを、264パッチで測りました。中央値 ΔE00 9.8815、p95 13.2745、最大 15.5996です。独立した LittleCMS の変換と評価ツールの差は、Lab で最大 0.105でした。これらの観測は、フィルムの正確さの関門を通過しません。このスキャンはポジの IT8 で、実物のシリアルが未確認であり、ネガのカメラ・光源・フィルムの測定も付いていないためです。

公開されているネガのデータセットも調べました。FADGI のネガの基準には、測定した色パッチではなく濃度しか入っていません。BlueNeg は、復元した基準を pseudo ground truth と呼んでいます。2024年の ARRI AQUA 分光測定の研究は、データを公開ダウンロードではなく、請求に応じて提供しています。どれも、現在の反転のための独立したシーンの色の基準にはなりません。

[公開されている Kodak ColorPlus 200 の露出シリーズ](https://discuss.pixls.us/t/any-interest-in-a-film-negative-feature-in-rt/12569/262)(Sony ILCE-7 の RAW スキャン5枚、−1 から +3 EV)も調べました。チャートは Grey White Balance Colour Card なので、X-Rite の基準値は退けました。サンプルしたパッチ領域120か所のうち、デコード後のカメラ RGB で0や最大値に達したものはありませんでした。これはデコード後の信号の確認で、センサーのモザイクの直接測定でも色の正確さの結果でもありません。そのチャートとスキャン環境の測定済みの基準がなければ、出力の色かぶりが入力のせいかアプリのせいかを分けられません。再配布の権利が確認できないため、ファイルはリポジトリの外に置いています。

[FADGI](https://www.digitizationguidelines.gov/guidelines/digitize-OpenDice.html) · [BlueNeg](https://huggingface.co/datasets/ttgroup/blueneg-release) · [Plutino 2024](https://doi.org/10.1002/col.22946)

## 公開されている回帰用資料

FADGI/OpenDICE の次の2つのファイルを対で使います。

- ガイド: <https://www.digitizationguidelines.gov/guidelines/digitize-OpenDice.html>
- 画像: <https://www.digitizationguidelines.gov/guidelines/OpenDICE/IT8-7.1.tif>
  - SHA-256: `c62ee73f26390a2ad90e7e28280cbd1efb4f18834425bb7112ff1f8016832ffd`
  - サイズ: `6255 x 4170`
  - 形式: `Adobe RGB (1998)` を埋め込んだ16bit RGB
- 基準ファイル: <https://www.digitizationguidelines.gov/guidelines/OpenDICE/Profile_IT8-7.1.txt>
  - SHA-256: `19337b85f213eb4397e91c91298201f421ef3ca33b0ef6da3d752a0880491840`
  - パッチ: `A1` から `L22` までの Lab 値264個
  - 16列目: 濃度

再配布の権利が確認できないため、ファイルはリポジトリにもアプリにも入れません。自分でダウンロードし、[サンプルのマニフェスト](../../reference/IT8_FADGI_OPENDICE.example.json)にそのパスを指定してください。サンプルの等級は `algorithmRegression` で、`deviceCharacterization` に書き換えると検査ツールが拒否します。`negaflow-mac/` で実行します。

```bash
swift run negaflow it8-bench ../docs/reference/IT8_FADGI_OPENDICE.example.json \
  --image /path/to/IT8-7.1.tif \
  --reference /path/to/Profile_IT8-7.1.txt \
  --out /path/to/it8-report.json
```

## 測定の規則

- 画像、基準ファイル、選んだ ICC のどれかの SHA-256 がマニフェストと違えば止まります。
- レポート v2 は、マニフェストのテキストの SHA-256 も記録します。
- `A01` と `A1` は同じ座標を読み、元の ID はレポートに残ります。
- 22 × 12 のグリッドで、各パッチの中央60%を元の解像度の浮動小数点で読みます。行は `A`–`L`、列は `1`–`22` の順です。
- 埋め込みの ICC に従います。
- 計算は、リニア sRGB D65 から XYZ、Bradford による D50 への適応を経て、Lab D50/2° に進みます。
- パッチごとに、面積、ピクセル数、RGB の平均と標準偏差、両端のクリップの割合、有限でない値の数、基準と測定の Lab、L/a/b の差、CIEDE2000 を記録します。
- 中央値、p95、最大は観測であって合格ラインではありません。根拠のない平均の基準は作らず、`qualityDecision` は `notEvaluated` のままです。
- プロファイルの当てはめに使ったターゲットは、独立した検証には再利用しません。

### 実物ターゲットの詳細

実機で測るときは、オペレーターがターゲットのラベルから次の項目を読み取って書きます。

<details>
<summary>測定ブロックの例</summary>

```json
{
  "measurement": {
    "samplerVersion": "center-mean-v1",
    "renderingIntent": "relativeColorimetric",
    "physicalTargetIdentity": {
      "manufacturer": "target label manufacturer",
      "material": "target label material",
      "serial": "target label serial",
      "batchMetadataKey": "PROD_DATE",
      "batchValue": "reference header production date"
    }
  }
}
```

</details>

`MANUFACTURER`、`MATERIAL`、`SERIAL`、バッチのヘッダー(`BATCH`、`BATCH_ID`、`PROD_DATE` のどれか)が、基準ファイルと一字一句同じでなければなりません。最上位の `targetID` は `serial` と、`batchID` は `batchValue` と同じである必要があります。

この記録が示すのは、オペレーターが書いた内容と基準ファイルが一致することだけです。画像からラベルを読み取ったり、オペレーターの入力を保証したりはしません。詳細がないとき、最も近い日付や汎用の基準ファイルで代用することはありません。

基準ファイルに光源や観測者の情報があれば、D50/2° の規約と照合し、矛盾すれば止まります。現在は `measurement.renderingIntent` で Core Image の変換を直接固定できないため、レポートには `manifestDeclarationNotControlledByEvaluator` と書きます。

## `PRINT` の出力

IT8.7/1 は入力機器向けです。プリンター出力には、プリンター、用紙、インクまたは薬品、ドライバーや工程の条件の組み合わせを実測して作った RGB プリンター ICC が必要です。

確認と使用の順序:

1. ICC のサイズ、`prtr` のデバイスクラス、`RGB ` のデータ空間、Lab/XYZ の PCS、`acsp` の署名を確かめます。
2. ColorSync が双方向に変換できることを確かめます。
3. 選択時に、プロファイルの名前、バイト数、SHA-256 を固定します。
4. `MAIN` の作業画像とページレイアウトが終わった後の最終出力に、1回だけ適用します。
5. `rawScanTIFF` や `-main-flat` には適用しません。
6. プロファイルがないか誤っていれば、一時出力を作る前に失敗します。sRGB で代用することはありません。

現在の Core Image と ColorSync の経路が、すべての macOS のバージョンでレンダリングインテントとブラックポイント補正をビット単位で固定するとは主張しません。

## `MAIN` の合成パッチ回帰

`NegativeAutoBalanceTests` と `shoulder-print-response-v4` です。

MAIN/CS は、スイッチがオンでもオフでも v4 カーブを使います。残してある v6 のテストは自分の固定プリミティブを検査するもので、そこでのフレーム間のばらつきゼロは、自動バランス ON の結果ではありません。

[ネガ反転応答](PRINT_RESPONSE.md)

## HS と SP の相対スタイル回帰

`A1` から `L22` までの Lab D50 パッチ264個の基準ファイルを SHA-256 で固定します。各パッチから合成ネガを作り、`MAIN`、`HS`、`SP` の経路をそれぞれ2回動かします。

```bash
swift run negaflow scanner-relative-it8-bench \
  /path/to/Profile_IT8-7.1.txt \
  --sha256 sha256:19337b85f213eb4397e91c91298201f421ef3ca33b0ef6da3d752a0880491840 \
  --out /path/to/scanner-relative-it8-report.json
```

レポートには、パッチごとの RGB と Lab、基準に対する `DeltaE00`、ターゲット間の相対 `DeltaE00`、クリップと有限でない値のフラグが入ります。ニュートラルの階調の単調性は、`A16...L16` の濃度列から読みます。

リニア sRGB に変換したときに 0...1 の外に出る色は、合成ネガとして正確に作れないため、表示できる範囲に制限します。そのため、広い範囲の統計は観測であって合格ラインではありません。

証拠の等級は常に `syntheticModel`、判定は常に `notEvaluated` です。プロファイルのマニフェストやどれかのファイルの SHA-256 が合わなければ止まります。実機の正確さには、同じ実物のネガを両方の機械でスキャンした資料と、別の検証資料が必要です。

D50/2° は、基準ファイルのヘッダーから確認したものではありません。Lab を D50/2° として読む、このベンチ自身の規約なので、`colorimetryInterpretationProvenance` は `benchmarkContractNotVerifiedFromReferenceHeader` です。
