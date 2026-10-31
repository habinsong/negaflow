# コードとリソースの出どころ

[ドキュメントホーム](../README.md)

ここにはnegaflow本体のApache-2.0配布範囲を書きます。リポジトリとリリース成果物をあとから確認できるようにまとめた出所記録であり、法律上の助言ではありません。

## コード

`negaflow-mac` の Swift・Python・シェル連携コードは本プロジェクトで書いています。ネガのカメラ RAW デコードには、固定リビジョンの LibRaw を交換可能な `libraw.dylib` として使い、CDDL-1.0 で配布します。両プラットフォームで LibRaw のファイルを二つ変更します。`src/demosaic/xtrans_demosaic.cpp` は Fuji X-Trans のタイル順序を保ち、タイル内の行を並列処理します。`src/postprocessing/mem_image.cpp` は出力ビットマップの行を並列にコピーします。パッチは [`xtrans-parallel-rows.patch`](../../../negaflow-mac/scripts/libraw/xtrans-parallel-rows.patch) と [`mem-image-parallel-rows.patch`](../../../negaflow-mac/scripts/libraw/mem-image-parallel-rows.patch) です。試験した RAW ファイルでは、変更前の直列ビルドと画素が一致しました。以前の並列 X-Trans ビルドでは実行ごとに画素が変わる場合がありました。macOS では LLVM OpenMP ランタイム(libomp 20.1.8、Apache License v2.0 with LLVM Exceptions)を静的リンクします。アプリの `Contents/Resources/licenses/libraw/` (`native-preview-bridge.cpp`: Negaflow contributors, CDDL-1.0) にソースアーカイブ、パッチ、ビルドスクリプト、著作権・ライセンス文書を含めます。Apache ソースツリーに LibRaw ソースは統合しません。Windows も同じリビジョン、Windows 用の行並列化パッチ、CR2・NEF・ARW のデータを全コアでデコードするパッチ、`native-preview-bridge.cpp` (CDDL-1.0。macOS の関数に、Windows 専用のリニア DNG 用関数と、画素ごとのループ 3 つを並列に実行する LibRaw のサブクラスを加えたもの。出力はバイト単位で同一。そのパッチが呼ぶ並列 Huffman デコーダーも含む) を使い、他の構成要素は [`negaflow-windows/THIRD-PARTY-NOTICES.md`](../../../negaflow-windows/THIRD-PARTY-NOTICES.md) に記録します。テスト専用 `CameraNativeRaw.dng` は raw.pixls.us 項目 2204 の CC0-1.0 資料で、出典 JSON を隣に置き、アプリからは除外します。

追加の告知ファイルがない場合も、警告を出してビルドとパッケージ作成を続けます。アップストリームのライセンスと対応するソースは同梱します。

フィルム反転は、公開された感光学の濃度、トウ、直線部、ショルダーの考え方を使います。 ここでの曲線と係数はnegaflowの4つの光度基準点から出したもので、他社プログラムの式や定数を写してはいません。 式と導出は[固定プリント応答](../reference/PRINT_RESPONSE.md)にあります。

公開されたメーカーの技術データシートは、フィルムごとのDminとDmaxのプリセット（`FilmStockDmin`）、モノクロの分光感度と特性曲線のプリセット（`BWFilmProfile`）、粒状とMTFの物理パラメータ（`DigitalFilmPhysics`）の3つの定数群で使います。 これらの数値はメーカーのデータシートにある図表から読んだ近似値で、`FilmStockDmin`は項目ごとに出所を`datasheetCurve`か`estimated`として示します。 公開された図表から読んだ数値はフィルムについての事実であって、他人のコードや文章を写したものではありません。スキャンから実測したフィルムベースがあれば、常にそちらが優先します。

GrainMend IRは次の順で動きます。

1. RGBとIRの整数オフセットを単独で推定する。
2. `log(red)`の区間ごとにIRのトリム平均を補間し、ノンパラメトリックな場面の漏れ込み曲線を作る。
3. 場面の漏れ込みを引き、局所平均に対する相対コントラストを出す。
4. トリムした局所ノイズのしきい値、連結成分、方向から欠陥マスクを作る。

このコードはSANEのIR補正をリンクも移植もしていません。 公開文献と製品説明は、フィルムと赤外線の物理的な限界を確認する背景資料です。 方法や原理を参考にすることと、コードの表現を写すことは別です。 米国著作権局も、方法・システムと具体的な表現を分けています。

- [U.S. Copyright Office Circular 33](https://www.copyright.gov/circs/circ33.pdf)
- [SANE backends source repository](https://gitlab.com/sane-project/backends)

## SANEプラグインの境界

本体には`scanimage`、SANEヘッダー、バックエンド設定、機種別の処理コードがありません。 本体はインストール済みの外部プログラムと、バージョン付きのJSON/NDJSON契約だけでやり取りします。 実際の SANEの処理は、別のGPL-2.0-or-laterリポジトリと実行ファイルとして配ります。

別プロセスだからといって、それだけでライセンスの答えが出るわけではありません。 GNUのFAQも、パイプやコマンドラインでのやり取りは普通は別プログラムに見えるが、やり取りが密接すぎると答えが変わり得ると書いています。 そこで契約は、装置に依存しない要求、機能、進捗、結果ファイルの情報だけを交換し、SANEのデータ構造は共有しません。

- [GNU license FAQ: aggregates and separate programs](https://www.gnu.org/licenses/gpl-faq.en.html)
- [Apache License 2.0 and GPL compatibility](https://www.apache.org/licenses/GPL-compatibility)
- [スキャナープラグイン構造](../architecture/SCANNER_PLUGINS.md)

リリース検査では、アプリバンドルにプラグイン、SANE実行ファイル、SANEライブラリが紛れ込んでいないことをもう一度確認します。 プラグイン側は自分の`LICENSE`、`COPYING`、完全な対応ソース、他社の告知を配ります。

## 同梱リソース

[`Config/bundled-resource-provenance-v1.json`](../../../negaflow-mac/Config/bundled-resource-provenance-v1.json) は、アプリとソースツリーに入るリソースの宣言された出どころ、ライセンス、SHA-256を固定します。

| まとまり | 出どころ | 配るもの |
|---|---|---|
| ScannerKit TIFF | 維持管理者が撮って整えたレイアウト資料 | TIFF 4点 |
| アプリアイコン | 維持管理者のプロジェクトアートワーク | 元PNG、ビルド用PNG、ICNS |
| ルックプリセット | negaflow用に書いた値 | JSON 6点 |
| スキャナープロファイル | 維持管理者が持つスキャン計測から生成 | 元スキャンを除く数値プロファイル |

TIFFに見えるカメラや色空間のメタデータは、撮影とエンコードのコンテナ情報です。 スキャナープロファイルの`sourceProfiles`は生成時のローカル計測資料の論理パスで、その元写真は配りません。

FILM-R v2の資料は品質計測のときだけダウンロードします。 画像そのものはリポジトリにもアプリにも入りません。 DOIバージョン、CC BY 4.0、ファイルサイズとハッシュは [`Config/defect-corpus-film-r-v2.json`](../../../negaflow-mac/Config/defect-corpus-film-r-v2.json)に固定します。

## DNG の書き出し

DNG 書き出し(`negaflow-mac` の `DNGLinearWriter`、`negaflow-windows` の `dng_linear_export`)は、Adobe が公開している Digital Negative Specification 1.6 のタグ番号と色モデルだけを見て新しく書きました。Adobe DNG SDK のコードも、LibRaw など他の DNG 書き出しのコードも含みません。色行列は sRGB、Display P3、Adobe RGB (1998) の公開された色度座標から計算します。Adobe は DNG ファイルを読み書きするソフトウェアにロイヤリティ不要の特許ライセンスを提供しており、この製品はそれを使っています。ライセンスは次の表示を求めています。

This product includes DNG technology under license by Adobe.

DNG は Adobe Inc. の商標です。この名称はファイル形式を指すためにだけ使います。

## 名称と相互運用

フィルム、スキャナー、色空間、XMP namespace、製品名は、対象の識別とファイルの相互運用のために使います。 Windowsエンジンが合成する出力ICCプロファイルは、説明用の名称（`"Negaflow Compatible P3"`、`"Compatible with Adobe RGB (1998)"`）と`CC0 1.0 Universal`の権利放棄を記し、書き出した画像にプロファイル著作権の制約を残しません。 商標の所有や提携は主張しません。範囲は[`TRADEMARKS.md`](../../../TRADEMARKS.md)にあります。

## 自動検査とその限界

`python3 scripts/ci/verify-provenance.py`は次のどれかで失敗します。

- 登録されていない、またはハッシュが変わった同梱リソース
- 本体に入ったC/C++/Objective-C、外部パッケージ、バイナリアーカイブ、vendorツリー
- 本体のコードに入ったSANE専用の名称や、確認対象の外部実装の痕跡
- リリーススクリプトがSANEプラグインをアプリに入れる変更
- リポジトリに入ったFILM-Rの画像資料

この検査は今のツリーの明らかな退行を止めます。 インターネット全体との類似性、写真やプロファイル入力の権利、特許、商標、各国の法的判断までは証明しません。 出どころが変わったら宣言とハッシュを一緒に見直します。 はっきりしないときは、そのリソースを配布から外し、権利者か専門家に確認します。
