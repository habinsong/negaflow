# コードとリソースの出どころ

[ドキュメントホーム](../README.md)

この文書は、negaflow アプリの Apache-2.0 での配布範囲を記録します。リポジトリと配布物を確認するための出どころの記録であり、法的な助言ではありません。

## コード

`negaflow-mac` の Swift、Python、シェルの連携は、negaflow のために書いたものです。

ネガのカメラ RAW のデコードには、固定した LibRaw のリビジョンを、差し替え可能な `libraw.dylib` としてビルドして使い、CDDL-1.0 で配布します。両プラットフォームとも同じ3つのパッチを当てます。

- [`xtrans-parallel-rows.patch`](../../../negaflow-mac/scripts/libraw/xtrans-parallel-rows.patch): `src/demosaic/xtrans_demosaic.cpp` で、Fuji X-Trans のタイルを順番どおりに処理し、タイル内の行を並列に処理し、互いに触れない行のまとまりごとに緑の境界パスを実行します
- [`mem-image-parallel-rows.patch`](../../../negaflow-mac/scripts/libraw/mem-image-parallel-rows.patch): `src/postprocessing/mem_image.cpp` で、出力ビットマップの行を並列にコピーします
- [`raw-decoders-parallel.patch`](../../../negaflow-mac/scripts/libraw/raw-decoders-parallel.patch): `src/decoders/decoders_dcraw.cpp` で、通常のロスレス JPEG(CR2)と Nikon NEF のデータを並列のハフマンデコーダーに渡し、Sony ARW2 の行を並列にデコードします

パッチを当てたビルドは、試験した RAW ファイルで、パッチなしの直列ビルドと同じ結果になります。

macOS では、LLVM OpenMP(libomp 20.1.8、Apache License v2.0 with LLVM Exceptions)をライブラリに静的にリンクします。アプリには、ソースアーカイブ、パッチ、ビルドスクリプト、著作権とライセンスのファイルが `Contents/Resources/licenses/libraw/` に入っています。`native-preview-bridge.cpp`(Negaflow contributors、CDDL-1.0)には、ピクセル単位の3つのループを並列に動かしながら出力がバイト単位で同一になる LibRaw のサブクラスと、デコーダーのパッチが呼ぶ並列ハフマンデコーダーがあります。LibRaw のソースは Apache のソースツリーに混ぜません。

Windows も同じ上流のリビジョンとパッチを使います。Windows の `native-preview-bridge.cpp`(CDDL-1.0)は、リニア DNG 向けの Windows 専用の関数を加え、そのほかの構成要素は [`negaflow-windows/THIRD-PARTY-NOTICES.md`](../../../negaflow-windows/THIRD-PARTY-NOTICES.md) に記録しています。テスト専用の `CameraNativeRaw.dng` は raw.pixls.us の2204番のエントリーにある CC0-1.0 の資料で、隣にある出どころの JSON で特定でき、アプリからは除外します。補足の告知ファイルがなければ、ビルドとパッケージングの段階は警告して続行し、上流のライセンスファイルと対応するソースは含めたままにします。

フィルムの反転には、濃度、トウ、直線部、ショルダーという公表された感光測定の考え方を使います。カーブと係数は、第三者のプログラムの式や定数ではなく、negaflow の4つの測光アンカーから出したものです。式と導出は[ネガ反転応答](../reference/PRINT_RESPONSE.md)にあります。

公表されているメーカーのデータシートが、出荷するフィルム定数の3つのまとまりの根拠になっています。フィルム種別ごとの Dmin・Dmax のプリセット(`FilmStockDmin`)、白黒の分光と特性曲線のプリセット(`BWFilmProfile`)、物理的な粒子と MTF のパラメータ(`DigitalFilmPhysics`)です。これらの数値は、公表された技術資料からおおよそ読み取った値、または当てはめた値で、`FilmStockDmin` はすべての項目に `datasheetCurve` か `estimated` を付けて出どころを残します。公表されたチャートから読んだ数値はフィルムについての事実であり、誰かのコードや文章の複製ではなく、スキャンで測ったフィルムベースが常にそれらより優先されます。

GrainMend IR は次の順で動きます。

1. RGB と IR の間の整数のずれを自前で推定する。
2. `log(red)` のビンごとに IR の刈り込み平均を補間して、ノンパラメトリックなシーンの漏れ曲線を作る。
3. シーンの漏れを引き、局所平均に対する相対コントラストを計算する。
4. 刈り込んだ局所ノイズのしきい値、連結成分、方向から欠陥マスクを作る。

このコードは、SANE の IR 補正をリンクも移植もしていません。公表された論文や製品ページは、フィルムと赤外線の物理的な限界を確かめるための背景資料です。方法や原理を取り入れることと、コードの表現を写すことは別です。米国著作権局も、方法・システムとその具体的な表現との間に同じ線を引いています。

- [U.S. Copyright Office Circular 33](https://www.copyright.gov/circs/circ33.pdf)
- [SANE backends source repository](https://gitlab.com/sane-project/backends)

## SANE プラグインの境界

アプリには、`scanimage`、SANE のヘッダー、バックエンドの設定、機器ごとの処理コードがありません。インストールされた外部プログラムとは、バージョン付きの JSON/NDJSON の規約だけでやり取りします。実際の SANE の仕事は、GPL-2.0-or-later の別リポジトリと実行ファイルとして配布します。

別プロセスだというだけで、ライセンスの問題が片づくわけではありません。GNU の FAQ は、パイプやコマンドラインでの通信は通常は別プログラムに見えるが、通信が密接すぎると答えが変わりうる、と述べています。そのため、この規約は機器に依存しない要求、機能、進行状況、結果ファイルの情報だけをやり取りし、SANE のデータ構造は共有しません。

- [GNU license FAQ: aggregates and separate programs](https://www.gnu.org/licenses/gpl-faq.en.html)
- [Apache License 2.0 and GPL compatibility](https://www.apache.org/licenses/GPL-compatibility)
- [スキャナープラグイン構造](../architecture/SCANNER_PLUGINS.md)

リリース時の検査で、プラグイン、SANE の実行ファイル、SANE のライブラリがアプリバンドルに紛れ込んでいないことを改めて確かめます。プラグイン側は、自前の `LICENSE`、`COPYING`、対応するソース一式、サードパーティの告知を添えて配布します。

## 同梱リソース

[`Config/bundled-resource-provenance-v1.json`](../../../negaflow-mac/Config/bundled-resource-provenance-v1.json) は、アプリとソースツリーに入るすべてのリソースについて、申告された出どころ、ライセンス、SHA-256 を固定します。

| まとまり | 出どころ | 配布するもの |
|---|---|---|
| ScannerKit TIFF | メンテナーが撮影して用意したレイアウト資料 | TIFF ファイル4個 |
| アプリアイコン | メンテナーによるプロジェクトのアートワーク | 元の PNG、ビルド用の PNG、ICNS |
| ルックのプリセット | negaflow のために書いた値 | JSON ファイル6個 |
| スキャナープロファイル | メンテナーが保管するスキャン測定から作成 | 数値のプロファイル。元のスキャンは含まない |

TIFF ファイルから見えるカメラと色空間のメタデータは、撮影とエンコードで生じたコンテナの情報です。スキャナープロファイルの `sourceProfiles` は、ビルド時に使ったローカルの測定資料の論理パスで、その元の写真は配布しません。

FILM-R v2 の資料は、品質測定のときだけダウンロードします。画像がリポジトリやアプリに入ることはありません。DOI のバージョン、CC BY 4.0、ファイルサイズ、ハッシュは [`Config/defect-corpus-film-r-v2.json`](../../../negaflow-mac/Config/defect-corpus-film-r-v2.json) に固定されています。

## DNG の書き出し

DNG ライター(`negaflow-mac` の `DNGLinearWriter`、`negaflow-windows` の `dng_linear_export`)は、Adobe が公開している Digital Negative Specification 1.6 のタグ番号と色モデルから書きました。Adobe DNG SDK のコードも、LibRaw や他の DNG ライターのコードも含みません。色行列は、sRGB、Display P3、Adobe RGB (1998) の公表されている色度座標から計算します。

Adobe は、DNG ファイルを読み書きするソフトウェアに、ロイヤリティ無償の特許ライセンスを提供しています。この製品はそれを利用しており、ライセンスは次の告知を求めています。

This product includes DNG technology under license by Adobe.

DNG は Adobe Inc. の商標です。この名前はファイル形式を指すためだけに使います。

## 変形と傾き補正

変形セクションと基準線による傾き補正は negaflow のために書いたもので、外部のコードは含みません。

- まっすぐな線分は、明るさの勾配の向きがそろった画素をまとめ、まとまりごとに主成分の向きで直線を当てはめて求めます。縁の画素を向きでまとめる手法は 1980 年代から公開されています。
- ソルバーは垂直か水平から 30° 以内の線分だけを残し、焦点距離を固定したカメラを回して、モードが許す範囲で線分を垂直・水平に近づけます。外れ値に強い角度誤差の和を Nelder–Mead 単体法で小さくします。カメラの内部パラメーター、マンハッタン方向、消失点は推定しません。
- ガイド付きモードは、ユーザーが引いたガイドだけを使います。

Adobe は写真の遠近の自動補正に関する米国特許を 2 件、有効なまま持っています。優先日はどちらも 2012 年 4 月 27 日で、Google Patents は 2033 年の満了を見込んでいます。

- [US 9,519,954](https://patents.google.com/patent/US9519954B2/en) は、エネルギー関数の最適化で内部パラメーター行列、姿勢行列、消失点をまとめて推定する方法を請求しています。negaflow はこのどれも推定しません。
- [US 9,582,855](https://patents.google.com/patent/US9582855B2/en) の独立請求項はもっと広く、人の知覚の基準に少なくとも一部基づいて、線を画像の軸にそろえるホモグラフィーや平面変換を計算するものです。negaflow のソルバーも線を画像の軸にそろえます。この考え方は 2012 年より前に公開されていました。Marcus Hebel の ShiftN は 2006 年に紹介され、2008 年 10 月に 3.4 版が出ています。垂直に近いまっすぐな縁を探し、それらが平行で枠とそろうように遠近変換を最適化していました([ShiftN](https://www.shiftn.de/ShiftN_functionality.html)、[版の記録](https://newsgroup.xnview.com/viewtopic.php?p=57759))。ShiftN のコードは使っていません。

ある実装が請求項に当たるかどうかは法的な判断で、この記録はその答えを出しません。

## 名前と相互運用性

フィルム、スキャナー、色空間、XMP の名前空間、製品名は、対象を指し、ファイルの相互運用性を保つために使います。Windows のエンジンが合成する出力 ICC プロファイルは、説明的な名前(`"Negaflow Compatible P3"`、`"Compatible with Adobe RGB (1998)"`)と `CC0 1.0 Universal` の宣言を使うので、書き出したユーザーの画像にプロファイルの著作権の制約は付きません。商標の所有や提携は主張しません。全体の範囲は [`TRADEMARKS.md`](../../../TRADEMARKS.md) にあります。

## 自動検査と、見落とすもの

`python3 scripts/ci/verify-provenance.py`(`negaflow-mac/` で実行)は、次のどれかがあると失敗します。

- 登録されていない、またはハッシュが変わった同梱リソース
- アプリの中の C/C++/Objective-C、外部パッケージ、バイナリのアーカイブ、ベンダーのツリー
- アプリのコードの中の SANE 専用の名前や、確認済みの外部実装の痕跡
- リリーススクリプトが SANE プラグインをアプリに入れるようになる変更
- リポジトリの中の FILM-R の画像資料

この検査は、現在のツリーにある明らかな退行を止めます。インターネット全体との類似、写真やプロファイルの入力の権利、特許、商標、どこかの国での法的な結論は証明しません。出どころが変わったら、申告をハッシュと併せて見直してください。不明なときは、そのリソースをリリースから外し、権利者か専門家に尋ねてください。
