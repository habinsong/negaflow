# レンダー記録

[ドキュメントホーム](../README.md)

サイドカーの `renderManifest` は、元ファイル、編集値、最終ファイルを SHA-256 でつなぎます。ファイルのパスは記録しません。

> [!IMPORTANT]
> `renderManifest` は、ファイルと設定の間のハッシュの関係を書いた記録です。電子署名や証明書がないので、C2PA Content Credentials ではありません。

## v3 に入るもの

- 元ファイルのバイト数、SHA-256、アルゴリズム名 `sha-256`
- 実際に使ったレンダー入力
- GrainMend キャッシュファイルまたはメモリ入力の検証範囲
- 現像、GrainMend、書き出し設定の SHA-256
- スキャナープロファイルの SHA-256
- デコーダーの出どころと Chroma Engine のレンダラーのバージョン
- 最終ファイルの SHA-256、バイト数、ピクセルサイズ、形式

エンコーダーが書き終えたら、ImageIO でファイルを開き直してピクセルサイズを確かめ、ファイル全体のハッシュを求めます。サイドカーはその後に書きます。v3 の検査に失敗した結果は、完成した出力一式としては公開しません。

## GrainMend の入力

- `cleanedMemory`: メモリ上のピクセルには標準的なハッシュがないため、検証範囲を `sourceAndDevelopRecipe` と記録します。GrainMend 編集履歴の SHA-256 は必ず入ります。
- `cleanedFile`: GrainMend キャッシュファイル全体と編集履歴の両方をハッシュします。

v1 と v2 のファイルも開けます。当時なかったハッシュを、あとから補うことはしません。

## C2PA との違い

電子署名、証明書、信頼の連鎖、埋め込みの claim ストアはなく、確認できる SHA-256 の値だけがあります。C2PA の hard binding と処理履歴、PREMIS の完全性の考え方を参考にしました。

出典:

- [C2PA Content Credentials 2.2](https://spec.c2pa.org/specifications/specifications/2.2/specs/C2PA_Specification.html)
- [C2PA hard-binding guidance](https://spec.c2pa.org/specifications/specifications/2.4/guidance/Guidance.html)
- [PREMIS preservation metadata](https://www.loc.gov/standards/premis/)
- [Apple Image I/O orientation and image properties](https://developer.apple.com/documentation/imageio/cgimagepropertyorientation)
