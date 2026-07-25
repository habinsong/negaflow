# GrainMend実スキャン比較

[ドキュメントホーム](../README.md)

GrainMend RGBの回帰検査にはFILM-R v2を使います。

| 項目 | 値 |
|---|---|
| 損傷本・手作業の復元本 | 各44枚 |
| ライセンス | CC BY 4.0 |
| 全体サイズ | 437,570,872バイト |
| 置き場所 | `build/defect-corpus/` |
| 用途 | GrainMend RGBの回帰比較 |

## 資料

- 名前: *Authentically damaged & manually restored film scans*
- 著者: Daniela Ivanova
- DOI: <https://doi.org/10.6084/m9.figshare.21803304.v2>
- 論文: <https://doi.org/10.1111/cgf.14749>
- 説明: <https://daniela997.github.io/FilmDamageSimulator/>
- ライセンス: CC BY 4.0
- 構成: 損傷した35mmフィルムスキャン44枚と、専門家による手作業の復元本44枚
- 全体サイズ: 437,570,872バイト

画像はリポジトリに入れません。`Config/defect-corpus-film-r-v2.json`にDOIバージョン、ライセンス、
ペア数、全体サイズを固定しています。取得スクリプトはFigshareが出しているファイルごとのMD5と
サイズを検査します。落としたファイルと結果は`build/defect-corpus/`に置き、Gitからは外します。

## 受け取り

そのままのコマンドは、確認用に1ペアだけ取得します。

<details>
<summary>取得コマンド</summary>

```bash
python3 scripts/defect-corpus/fetch-film-r.py
```

44ペア全部:

```bash
python3 scripts/defect-corpus/fetch-film-r.py --all
```

FigshareのファイルCDNが自動リクエストを弾く場合は、データセットのページで`Download all`から
落としたZIPをそのまま検証して展開できます。ZIPのファイル名、サイズ、FigshareのMD5が固定契約と
すべて合ったときだけ展開が完了します。

```bash
python3 scripts/defect-corpus/fetch-film-r.py \
  --archive ~/Downloads/21803304.zip \
  --all
```

1件だけ:

```bash
python3 scripts/defect-corpus/fetch-film-r.py --case portra400_135_1
```

</details>

## 比較の実行

損傷本と、名前の末尾に`_restored`が付く復元本を同じフォルダーに置きます。

<details open>
<summary>44ペアの比較コマンド</summary>

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift run -c release negaflow defect-bench build/defect-corpus/film-r-v2 \
  --reference-dir build/defect-corpus/film-r-v2 \
  --out build/defect-corpus/film-r-v2-report \
  --metrics-only
```

</details>

`--metrics-only`は大きなPNGを作りません。外すと、手作業の確認用に`before`、`after`、`diff`、
`mask`と100%クロップも作ります。

レポートに入る値:

- 既存の検出数、信頼度、変わったピクセル数、処理時間
- 損傷本と専門家の復元本のPSNRと平均絶対誤差
- GrainMendの結果と専門家の復元本のPSNRと平均絶対誤差
- PSNRの変化
- 正解に対する誤差が減ったピクセルと増えたピクセルの割合

FILM-Rの論文はPSNR、SSIM、LPIPSを一緒に使います。このリポジトリはML依存を新しく入れないので、
標準ライブラリで計算できるPSNRと絶対誤差だけを自動で出します。

この数字だけでリリースを承認することはありません。手作業の復元本にも編集の判断とJPEGの差が
入っています。同じ資料と設定で再実行するときの自動品質の下限は
`Config/defect-removal-film-r-v2-baseline.json`に固定します。最終判断には`before`、`after`、
`diff`、`mask`と100%クロップを並べて見る必要があります。

> [!CAUTION]
> PSNRや平均誤差ひとつでGrainMendの画質を承認しません。元の質感の傷みと誤検出は、前後の画像、
> 差分画像、マスク、100%クロップを合わせて判断します。

この資料で確認できるのは、レンダー済み画像のGrainMend RGB経路だけです。RAWのデコード、フィルム
反転の正確さ、IRの整列、実機スキャナーの動作を示す用途には使えません。

## 2026-07-25の結果

44ペア全部をReleaseビルドで`--metrics-only --crops 0`を付けて実行しました。直前の回帰基準である
感度3.0と、リリースの自動経路である0.7を比べました。

| 指標 | 直前の基準3.0 | 安全な自動0.7 |
|---|---:|---:|
| 評価した画像 | 44 | 44 |
| PSNR改善 / 悪化 / 同じ | 11 / 33 / 0 | 34 / 6 / 4 |
| 平均PSNR変化 | -1.688 dB | +0.466 dB |
| 中央PSNR変化 | -0.237 dB | +0.118 dB |
| 最低PSNR変化 | -18.952 dB | -1.338 dB |
| 加重の改善ピクセル | 0.128% | 0.029% |
| 加重の悪化ピクセル | 0.792% | 0.017% |
| 加重の変更ピクセル | 0.794% | 0.043% |
| 自動の安全停止 | なし | 3枚 |

以前のアプリの既定値は6.0で、直前の3.0の基準よりも攻めていました。リリースの自動経路は0.7に
下げ、微細な異物の検出は既定で切りました。候補が1つのタイルの2%を超えると、そのタイルに触れる
成分を外します。5%を超えるタイルがあるか、フィルター後の全体候補が0.06%を超えると、その写真の
自動復元は適用しません。そのときはガイドで範囲を狭めて処理できます。

この安全線は自動だけに効きます。ガイド、ブラシ、クローンスタンプ、IRの検出範囲と復元の動きを、
自動の基準で縛ることはありません。

`Config/defect-removal-film-r-v2-baseline.json`は、観測値の回帰基準に加えて次の絶対的な下限も
検査します。

- 改善30枚以上、悪化10枚以下
- 平均と中央のPSNR変化が0 dB以上
- 最低PSNR変化が-1.5 dB以上
- 加重の悪化ピクセルが0.03%以下
- 全体の変更ピクセルが0.06%以下

今回は直前の基準より改善画像が23枚増え、悪化画像が27枚減り、最悪の事例は17.614 dB良くなりました。
それでも6枚は専門家の復元本よりPSNRが低いままです。FILM-Rは実際の損傷本と手作業の復元本を出す
一方で、復元の判断のあいまいさも含みます。資料と論文は
[FILM-Rプロジェクト](https://daniela997.github.io/FilmDamageSimulator/)と
[FILM-Rの論文](https://arxiv.org/abs/2302.10004)で見られます。

高密度の候補を自動から外したのは、質感の多い領域の誤検出を減らす既存の画像復元研究とも合います。
ただしこの結果から次を主張することはできません。

- どの写真でも自動の結果が手作業の復元より良い。
- GrainMend RGBがハードウェアのIRクリーニングと同じだ。
- 実機スキャナーのRGB・IR整列と光学品質が検証された。

全体の再現は手動の`GrainMend corpus` workflowで走らせます。自動の品質ゲートとは別に、100%
クロップの手作業確認が必要です。
