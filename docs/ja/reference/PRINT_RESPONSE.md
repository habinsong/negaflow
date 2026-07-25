# 固定プリント応答

[ドキュメントホーム](../README.md)

置き場所:

- Swift: `Sources/Chromabase/Film/NegativeInversion.swift`の`PrintResponse`
- Metal: `negativeInvert`カーネル
- 固定検査:
  `NegativeInversionCalibrationTests.testPrintResponseDerivesFromPhotometricContract`

## 曲線

フィルムの特性曲線は、露光と濃度の関係をトウ、直線部、ショルダーに分けて説明します。Negaflowは
濃度領域のショルダーをstretched exponential曲線で近似します。

```math
\begin{aligned}
D &= \log_{10}\left(\frac{D_{\min}}{T}\right) \\
d &= \frac{D}{d_{\max}} \\
\log_{10}(P) &= y_{\mathrm{ceil}} - A \exp\left(-(r d)^s\right)
\end{aligned}
```

`A`、`r`、`s`はコードの`amplitude`、`rate`、`shape`を短く書いた記号です。`d_{\max}`は
`dmaxNorm`です。

- `D`: フィルムベースを引いた光学濃度
- `d`: 使う濃度範囲で割った値
- `P`: 線形の出力の明るさ

曲線は全区間で上がり続けます。`d ≥ 0`のとき出力は`[baseToe, ceiling)`に入ります。ベースより
明るいバックライトやパーフォレーションのような負の値も0で切らず、有限の正の値として続きます。

```math
y(-|d|) = 2\log_{10}(P_{\mathrm{toe}}) - y(|d|)
```

逆関数も閉じた式で書けます。合成ネガを作って往復検査をするときに使います。

```math
d = \frac{\left[\ln\left(\frac{A}{y_{\mathrm{ceil}}-\log_{10}(P)}\right)\right]^{1/s}}{r}
```

## 4つの基準点

曲線の係数は保存しません。次の値から計算します。

| 基準点 | カラー | 白黒 | 用途 |
|---|---:|---:|---|
| `P(0)` ベース黒点 | 0.001 | 0.0005 | 8-bitコード0に貼り付かせない |
| `P(midFraction)` 中間グレー | 0.18 | 0.18 | 18%グレー |
| `P(1)` 白 | 0.70 | 0.85 | 測定した最高濃度部の明るさ |
| `P(∞)` 天井 | 0.90 | 0.98 | 反射光の余裕 |

`midFraction`は`0.60D / 1.55D`、およそ`0.387`です。

係数の計算:

```math
\begin{aligned}
y_{\mathrm{ceil}} &= \log_{10}(P_{\mathrm{ceil}}) \\
A &= y_{\mathrm{ceil}} - \log_{10}(P_{\mathrm{toe}}) \\
r_X &= \ln\left(\frac{A}{y_{\mathrm{ceil}}-\log_{10}(X)}\right) \\
s &= \frac{\ln(r_{\mathrm{white}}/r_{\mathrm{mid}})}
          {\ln(1/f_{\mathrm{mid}})} \\
r &= r_{\mathrm{white}}^{1/s}
\end{aligned}
```

## 既定の濃度範囲

`normalRange`はフィルムの物理的な最大濃度ではありません。正常露光の場面が使う範囲です。ベースを
測れなかったときや、場面のコントラストがとても低いときに効いてきます。

```math
\begin{aligned}
\operatorname{normalRange}(\mathrm{color}) &= 0.62 \times 2.5 = 1.55\,D \\
\operatorname{normalRange}(\mathrm{B\&W}) &= 0.62 \times 3.5 = 2.17\,D
\end{aligned}
```

- `0.62`: C-41特性曲線の直線部の傾きのおおよその値
- カラー`2.5`: 約7⅓段の拡散輝度範囲と明部の余裕
- 白黒`3.5`: 長い直線部を使う白黒プリントの習慣
- `0.60D`: 正常露光の場面の中間グレー濃度

`applySceneRanged`はこの値を使わず、フレームがチャンネルごとに実際に使っている濃度範囲を測ります。

## v4で変えたところ

前の方式は3区間に分けた関数と固定プリセットでした。v4は1本の曲線と4つの基準点にしました。区間の
境目がなく、どの値もコードとテストで追えます。

前の結果との差:

- カラーの中間・明部、正規化濃度0.3〜1.1: ±0.05段以内
- カラーの深い暗部、0.1〜0.2: 約-0.2段
- カラーのベース黒点: 約+0.25段
- 白黒: 暗部が約-0.4段、中間部が約+0.1段
- NORITSU/FUJIの中間グレー0.18の基準点はそのまま

## 参考資料と範囲

トウ、直線部、ショルダー、ガンマという枠組みは公開された感光学のものです。文献の曲線係数は
写していません。Negaflowの係数は上の4つの基準点から自分で計算します。

- [Sensitometry](https://en.wikipedia.org/wiki/Sensitometry)
- [Hurter–Driffield Characteristic Curve](https://studyguides.com/study-methods/overview/cmpanf83znm1201neitjb4waw)
- [RA-4用紙の比較](https://tinker.koraks.nl/photography/on-a-color-mission-comparing-two-ra4-color-papers/)

RA-4資料で知られるコントラスト範囲はそのまま使いません。この曲線のコントラストは、4つの基準点
から出た`shape`が決めます。
