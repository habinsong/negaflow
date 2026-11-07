# フィルムプロファイル

[ドキュメントホーム](../README.md)

同梱のスキャナープロファイルは、プロジェクトの作者が撮影し、ラボ用スキャナーでスキャンしたフィルムのフレームを分析し、JSON にしたものです。

| 項目 | 現在の値 |
|---|---:|
| フィルム種別の既定値 | 27 |
| 創作ルック | 6 |
| スキャナープロファイル | 15 |
| ロール観測 | 25 |
| フレーム数 | 928 |
| 検証状態 | すべて`realOnly` |

> [!NOTE]
> `928` は、プロジェクトの作者が撮影し、ラボ用スキャナーでスキャンしたフィルムのコマ数です。

## 別々の3種類のデータ

| データ | 形式 | 用途 | 数 |
|---|---|---|---:|
| フィルム種別 | Swift | Dmin/Dmax とフィルム種別の既定値 | 27 |
| ルックのプリセット | JSON | ユーザーが選ぶ創作ルック | 6 |
| スキャナープロファイル | JSON | 実際のスキャンで見られた相対的なトーンと色の統計 | 15 |

フィルム名27個が色の正確さのプロファイル27個ではなく、ルック6個はスキャナープロファイルとは別物です。以下は3つ目だけを扱います。

## 現在同梱しているもの

`Sources/Chromabase/ScannerProfiles/` に15個あります。

<details>
<summary>15個のプロファイルすべて</summary>

| スキャナー | フィルム種別 | フィルム | ロール観測 | フレーム数 | 状態 |
|---|---|---|---:|---:|---|
| NORITSU | カラーネガ | Fuji C200 | 3 | 111 | `realOnly` |
| NORITSU | カラーネガ | Kodak Ektar 100 | 2 | 76 | `realOnly` |
| NORITSU | カラーネガ | Kodak Portra 160 | 1 | 37 | `realOnly` |
| NORITSU | カラーネガ | Kodak Portra 400 | 2 | 75 | `realOnly` |
| NORITSU | カラーネガ | Kodak Portra 800 | 1 | 38 | `realOnly` |
| NORITSU | カラーネガ | Kodak Pro Image 100 | 1 | 37 | `realOnly` |
| NORITSU | カラーネガ | Kodak UltraMax 400 | 1 | 38 | `realOnly` |
| NORITSU | カラーネガ | Kodak Vision3 250D | 1 | 37 | `realOnly` |
| NORITSU | カラーネガ | Kodak Vision3 50D | 1 | 38 | `realOnly` |
| NORITSU | カラーポジ | Kodak Ektachrome 100 | 1 | 38 | `realOnly` |
| NORITSU | カラーポジ | Kodak Ektachrome 100D | 5 | 181 | `realOnly` |
| SP-3000 | カラーネガ | Kodak Ektar 100 | 2 | 76 | `realOnly` |
| SP-3000 | カラーネガ | Kodak Portra 160 | 1 | 38 | `realOnly` |
| SP-3000 | カラーネガ | Kodak Vision3 250D | 2 | 71 | `realOnly` |
| SP-3000 | カラーポジ | Kodak Ektachrome 100D | 1 | 37 | `realOnly` |
| **合計** |  |  | **25** | **928** | **15 `realOnly`** |

</details>

25 はプロファイルのグループごとのロール観測を足した値で、重複しないロール数ではありません。928 はコマ数です。

## 作り方

1. 撮影と仕分け。元資料を、スキャナー、フィルム種別、フィルム名、ロール名で分けます。分析の前に回転とファイルの解析を確かめ、空のファイルや読めないファイルは数えません。
2. フレームの測定。フレームごとに、明るさのパーセンタイルと両端のクリップ、シャドウ・中間調・ハイライトでのチャンネルの関係、彩度と色相の分布、低彩度ピクセルの Lab のニュートラル軸、勾配・シャープネス・粒子の基準値を測ります。これはシーンの観測です。1コマの露出や被写体を、スキャナー固有の性質と決めつけることはしません。
3. シーンのグループ化。明るさ、コントラスト、彩度、色相の範囲でシーンをまとめます。1種類のシーンがプロファイルを支配しないよう、グループごとの数と分布を記録します。
4. 代表フレーム。人が元資料に戻れるよう、コントラスト最大のフレーム、最もシャープなフレーム、粒子の基準値が最大のフレーム、明るさと彩度の範囲を代表するフレームを別に記録します。
5. ロールとグループの集計。`scripts/compile_scanner_profiles.py` が、ロールごとのデータをフィルムとスキャナーのグループにまとめます。空のビンを値0の観測として表すことはせず、すべての値は有限で、サンプル数は実数でなければなりません。
6. JSON とハッシュ。最終ファイルには、スキーマ、ID、元資料の数、元資料のパス、集計統計、検証状態、`profileHash` が入ります。検査ツールは、フィールド、数、有限性、ID とファイル名の一致、元資料の数、ハッシュを確かめます。

## JSON の形

<details>
<summary>プロファイル JSON の例</summary>

```json
{
  "schemaVersion": 2,
  "id": "noritsu__color-nega__kodak-portra-400",
  "displayName": "NORITSU · color nega · Kodak Portra 400",
  "scanner": "NORITSU",
  "kind": "color nega",
  "filmKey": "kodak portra 400",
  "validationStatus": "realOnly",
  "rollCount": 2,
  "imageCount": 75,
  "singleRollLimited": false,
  "sourceProfiles": [],
  "tone": {},
  "color": {},
  "neutralAxis": {},
  "neutralAxisBins": [],
  "hueResponse": [],
  "texture": {},
  "sceneBuckets": [],
  "coverageCandidates": [],
  "profileHash": "sha256:..."
}
```

</details>

## 主な項目

| 項目 | 内容 | 注意点 |
|---|---|---|
| `tone` | 明るさの分布と両端のクリップ | 1コマの露出は機械の性質ではない |
| `color` | シャドウ・中間調・ハイライトのチャンネルと彩度 | 観測した分布であり、絶対的な色行列ではない |
| `neutralAxis` | 低彩度ピクセルの Lab の `a*` と `b*` | ニュートラルな被写体がないシーンがあるため、サンプル数を併記する |
| `hueResponse` | 色相ビンごとの彩度の変化と色相の回転 | 両方の機械のデータがそろったときだけ相対比較する |
| `texture` | 勾配、シャープネス、粒子の基準値 | 機械のシャープネス値として直接は使わない |
| `sceneBuckets` | シーンごとの統計と代表フレーム | 人が元資料をたどり直せる |

`HS` ターゲットの明るさチャンネルのシャープ化は、`texture` から測った機械の定数ではなく、新しい粒子も合成しません。`SP`、`MAIN`、`PRINT` にはそのシャープ化は含まれません。

## 証拠の状態

| 状態 | 意味 | 使える場所 |
|---|---|---|
| `draft` | データやスキーマが未完成 | 同梱や自動での利用には使わない |
| `realOnly` | 実際のスキャンはあるが、別の基準資料がない | 手動で選ぶときだけ。正確さの主張はしない |
| `pairedSmoke` | ペアの資料が処理経路だけを確かめた | 品質の証拠としては使えない |
| `pairedValidated` | 校正・検証資料と回帰検査に通った | 方針が許せば自動選択できる |

現在は15個すべてが `realOnly` です。実際の資料の観測から作ったことは確かめられますが、機械と同じ結果になることは確かめられていません。

機械の正確さを主張するには、さらに資料が必要です。

- 同じ実物のフレームだと確かめる ID
- 校正とは分けて置いた検証資料
- 基準画像を作った条件
- スキャナーの設定とオペレーターの選択
- ターゲットのバッチ、照明、測定方法
- 画像ごとの合格基準

## アプリでの使い方

### 手動での選択

機種名やファイル情報から自動で選ばれるものはありません。`HS` または `SP` ターゲットとプロファイルは自分で選びます。自動の照合を許すのは `pairedValidated` だけなので、現在の同梱物には当てはまりません。

### 2台のスキャナーの相対差

絶対的なシーンの統計はそのまま使いません。2台の機械で対応するグループの間の差だけを、限定的に使います。

- 整理したロール名の集合が一致していなければなりません。
- 画像数の差が15%以下でなければなりません。
- 色相ビンは、両側でサンプル数がしきい値を超えている必要があります。
- 向きが逆転する値は適用しません。
- 反対側のゲインの間の値は、対数領域で計算します。
- トーンは Rec.709 ガンマの明るさに1回だけ適用し、Lab の色成分は保ちます。

元のプロファイルにはフレームごとの SHA-256 がなく、ロール名が一致しても同じフレームを対にした証拠にはなりません。

### 白黒とポジ

白黒では、色成分を捨てて相対的なトーンだけを使います。ポジでは、1本のロールの絶対的な明るさを別の写真に移しません。ただし `HS` と `SP` の基本スタイルは、ポジに半分の強さで適用されるので、結果が常に `MAIN` と同じとは限りません。

### テクスチャ

同じフレームで対になる資料がなければ、`texture` を機械固有のシャープネスや粒子の値としては使いません。その数値には、ピント、被写体、JPEG の処理、ラボのオペレーターの選択がすべて混ざっています。

## ファイルの完全性

`ScannerProfileRegistry` は、15個のうちの一部だけを開くことはしません。

1. マニフェストのスキーマを読みます。
2. すべてのファイルがあることを確かめ、SHA-256 を検査します。
3. 各 JSON の `profileHash` を計算し直します。
4. ID、ファイル名、スキーマ、状態、数、有限性を検査します。
5. どれかが合わなければ、バンドル全体を拒否します。
6. すべて一致した読み取り専用のスナップショットだけをキャッシュします。

書き出しの記録には、実際に使ったプロファイルの ID と SHA-256 が残ります。

## 確認のコマンド

`negaflow-mac/` で実行します。1つ目はプロファイルの規約検査、2つ目はプロファイルの再生成、3つ目は REAL/TARGET の品質判定です。

```bash
python3 scripts/validate_scanner_profiles.py \
  --mode profile-contract \
  --profiles Sources/Chromabase/ScannerProfiles
```

```bash
python3 scripts/compile_scanner_profiles.py \
  --source LUT_target/SOURCE \
  --out LUT_target/PROFILES \
  --resource-out Sources/Chromabase/ScannerProfiles
```

```bash
python3 scripts/evaluate_profile_quality.py \
  --manifest LUT_target/quality/corpus-v1.json \
  --candidate-summary LUT_target/SOURCE/summary.json \
  --baseline-summary LUT_target/quality/accepted-summary-v1.json \
  --data-root LUT_target \
  --verify-files all \
  --report build/profile-quality-report.json
```

このリポジトリには、リリースの主張を裏づける REAL/TARGET のマニフェストも承認済みの基準線もありません。合成テストが確かめるのは検査コードの失敗条件だけで、プロファイルの正確さを証明するものではありません。

## 参考資料

- [Kodak Professional Portra 400 technical data](https://www.kodakprofessional.com/sites/default/files/wysiwyg/pro/resources/e4050_portra_400.pdf)
- [darktable negadoctor](https://docs.darktable.org/usermanual/4.6/en/module-reference/processing-modules/negadoctor/)

プロファイルの数値は、これらの資料から取っていません。フィルムベース、シーンのトーン、機械のスタイルを別々に扱う必要がある理由の背景として読んだだけです。JSON の値は、このプロジェクトのために撮影した資料と、リポジトリの分析コードから出たものです。

## コードと関連ドキュメント

- `Sources/Chromabase/ScannerProfiles/`
- `Sources/Chromabase/Profiles/ScannerProfile/`
- `Sources/Chromabase/Profiles/ScannerTargetGrade/`
- `scripts/compile_scanner_profiles.py`
- `scripts/validate_scanner_profiles.py`
- `scripts/evaluate_profile_quality.py`
- [スキャナープロファイル品質判定](../reference/PROFILE_QUALITY_GATE.md)
- [IT8色検査](../reference/IT8_COLOR_VALIDATION.md)
- [Chroma Engine](CHROMA_ENGINE.md)
