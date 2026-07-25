# GrainMend IRが避けるフィルム

[ドキュメントホーム](../README.md)

赤外線クリーニングは、可視光の画像と赤外線の画像を別々に読み、重ねて欠陥を探します。すべての
フィルムに合う方式ではありません。

- 一般的なカラーフィルムと色素式の白黒フィルムはIRを使えます。
- 銀が残る一般的な白黒フィルムはIRを遮るため、欠陥マップが誤ることがあります。
- Kodachromeは他のカラーフィルムとIRの減衰が違うので、補正が足りない・効きすぎることがあります。

根拠:

- [Epsonの技術説明と制限](https://files.support.epson.com/pdf/pr48pr/pr48prps.pdf)
- [Epsonのフィルム種別表](https://files.support.epson.com/htmldocs/pr449p/pr449pug/projs_3.htm)
- [SilverFastの白黒・Kodachromeの説明](https://www.silverfast.com/showdocu/en.html?direct=1&docu=1300)

> [!CAUTION]
> フィルムの材質を確認できない場合、IRは自動で適用しません。誤ったIRマスクは、実際の画像構造を
> 欠陥として消してしまいます。

## 自動で適用する範囲

`FilmType`はカラーと白黒、ネガとポジしか区別しません。色素式の白黒と銀塩、通常のスライドと
Kodachromeを分ける情報はありません。

| フィルム種別 | 自動IR | 理由 |
|---|---|---|
| カラーネガ | 条件付き | プラグインがIRを報告し、整列検査を通る必要がある |
| カラーポジ | 使わない | Kodachromeかどうか分からない |
| 白黒ネガ・ポジ | 使わない | 色素式と銀塩を区別できない |

色素式の白黒や通常のカラースライドでIRが絶対に使えない、という意味ではありません。今ある情報
ではフィルムの材質を確認できないので、推測しないだけです。

## 整列検査

`InfraredDefectRemoval`は、IRの漏れ込みテクスチャとRGBの赤チャンネルを比べ、整数オフセットを
探します。結果には`AlignmentDiagnostics`が付きます。

| 状態 | 意味 |
|---|---|
| `notRequested` | 呼び出し側が2つの面はすでに合っていると指定した |
| `aligned` | 相関が基準を超え、最適点が検索範囲の中にある |
| `insufficientTexture` | IRに整列の手掛かりが足りない |
| `weakCorrelation` | 相関が基準を超えない |
| `searchLimitReached` | 最適点が検索の境界に乗っている |

後ろの3つを`(0,0)`で代替することはありません。`alignmentUnreliable`エラーで止めます。最適点が
検索の境界に乗った場合は、オフセットの大きさに関係なく失敗にします。

自動テストは、実機のRGB/IR整列やフィルムごとの結果の代わりにはなりません。実機での確認は
[実機点検リスト](../validation/REAL_QA_CHECKLIST.md)のIR項目に従います。

SANEの装置制御と取り込みコードは、別リポジトリ`negaflow-scanner-sane`にだけ置きます。
