# コードとリソースの出どころ

[ドキュメントホーム](../README.md)

ここにはnegaflow本体のApache-2.0配布範囲を書きます。法律意見書ではありません。リポジトリと
リリース成果物をあとから確認できるようにするための出所記録です。

## コード

`Sources`、`Tests`、`scripts`はnegaflowのために書いたSwift、Python、シェルのコードです。本体
にはC/C++/Objective-Cのソース、外部パッケージ、静的・動的ライブラリ、vendoredソースツリーは
ありません。AppleがmacOSで提供するシステムフレームワークだけをリンクします。

フィルム反転は、公開された感光学の濃度、トウ、直線部、ショルダーの考え方を使います。ここでの
曲線と係数はnegaflowの4つの光度基準点から出したもので、他社プログラムの式や定数を写しては
いません。式と導出は[固定プリント応答](../reference/PRINT_RESPONSE.md)にあります。

GrainMend IRは次の順で動きます。

1. RGBとIRの整数オフセットを単独で推定する。
2. `log(red)`の区間ごとにIRのトリム平均を補間し、ノンパラメトリックな場面の漏れ込み曲線を作る。
3. 場面の漏れ込みを引き、局所平均に対する相対コントラストを出す。
4. トリムした局所ノイズのしきい値、連結成分、方向から欠陥マスクを作る。

このコードはSANEのIR補正をリンクも移植もしていません。公開文献と製品説明は、フィルムと赤外線の
物理的な限界を確認する背景資料です。方法や原理を参考にすることと、コードの表現を写すことは
別です。米国著作権局も、方法・システムと具体的な表現を分けています。

- [U.S. Copyright Office Circular 33](https://www.copyright.gov/circs/circ33.pdf)
- [SANE backends source repository](https://gitlab.com/sane-project/backends)

## SANEプラグインの境界

本体には`scanimage`、SANEヘッダー、バックエンド設定、機種別の処理コードがありません。本体は
インストール済みの外部プログラムと、バージョン付きのJSON/NDJSON契約だけでやり取りします。実際の
SANEの処理は、別のGPL-2.0-or-laterリポジトリと実行ファイルとして配ります。

別プロセスだからといって、それだけでライセンスの答えが出るわけではありません。GNUのFAQも、
パイプやコマンドラインでのやり取りは普通は別プログラムに見えるが、やり取りが密接すぎると答えが
変わり得ると書いています。そこで契約は、装置に依存しない要求、機能、進捗、結果ファイルの情報
だけを交換し、SANEのデータ構造は共有しません。

- [GNU license FAQ: aggregates and separate programs](https://www.gnu.org/licenses/gpl-faq.en.html)
- [Apache License 2.0 and GPL compatibility](https://www.apache.org/licenses/GPL-compatibility)
- [スキャナープラグイン構造](../architecture/SCANNER_PLUGINS.md)

リリース検査では、アプリバンドルにプラグイン、SANE実行ファイル、ライブラリが紛れ込んでいない
ことをもう一度確認します。プラグイン側は自分の`LICENSE`、`COPYING`、完全な対応ソース、他社の
告知を配ります。

## 同梱リソース

[`Config/bundled-resource-provenance-v1.json`](../../../Config/bundled-resource-provenance-v1.json)は、
アプリとソースツリーに入るリソースの宣言された出どころ、ライセンス、SHA-256を固定します。

| まとまり | 出どころ | 配るもの |
|---|---|---|
| ScannerKit TIFF | 維持管理者が撮って整えたレイアウト資料 | TIFF 4点 |
| アプリアイコン | 維持管理者のプロジェクトアートワーク | 元PNG、ビルド用PNG、ICNS |
| ルックプリセット | negaflow用に書いた値 | JSON 6点 |
| スキャナープロファイル | 維持管理者が持つスキャン計測から生成 | 元スキャンを除く数値プロファイル |

TIFFに見えるカメラや色空間のメタデータは、撮影とエンコードのコンテナ情報です。スキャナー
プロファイルの`sourceProfiles`は生成時のローカル計測資料の論理パスで、その元写真は配りません。

FILM-R v2の資料は品質計測のときだけダウンロードします。画像そのものはリポジトリにもアプリにも
入りません。DOIバージョン、CC BY 4.0、ファイルサイズとハッシュは
[`Config/defect-corpus-film-r-v2.json`](../../../Config/defect-corpus-film-r-v2.json)に固定します。

## 名称と相互運用

フィルム、スキャナー、色空間、XMP namespace、製品名は、対象の識別とファイルの相互運用のために
使います。商標の所有や提携は主張しません。範囲は[`TRADEMARKS.md`](../../../TRADEMARKS.md)に
あります。

## 自動検査とその限界

`python3 scripts/ci/verify-provenance.py`は次のどれかで失敗します。

- 登録されていない、またはハッシュが変わった同梱リソース
- 本体に入ったC/C++/Objective-C、外部パッケージ、バイナリアーカイブ、vendorツリー
- 本体のコードに入ったSANE専用の名称や、確認対象の外部実装の痕跡
- リリーススクリプトがSANEプラグインをアプリに入れる変更
- リポジトリに入ったFILM-Rの画像資料

この検査は今のツリーの明らかな退行を止めます。インターネット全体との類似性、写真やプロファイル
入力の権利、特許、商標、各国の法的判断までは証明しません。出どころが変わったら宣言とハッシュを
一緒に見直します。はっきりしないときは、そのリソースを配布から外し、権利者か専門家に確認します。
