# ライブラリ保存アーカイブ

[ドキュメントホーム](../README.md)

カタログのバックアップはアプリを再び動かすためのもので、元の写真は含みません。`.negaflowarchive` アーカイブは、それらを1つのパッケージにまとめます。

| 含めるもの | 含めないもの |
|---|---|
| 持ち運べるカタログ JSON | 実行中の SQLite ファイル |
| 参照している元ファイルと残っている IR 元ファイル | サムネイルとプレビュー |
| まだ必要な GrainMend 編集履歴 | 作り直せる GrainMend キャッシュ |
| 仮想コピーと共有元ファイルの対応 | 書き出したファイル |

> [!WARNING]
> アーカイブの作成に失敗しても、既存のアーカイブは上書きしません。元ファイル、他社製 XMP、実行中のカタログにも触れません。

## パッケージ構造と検査

パッケージは [RFC 8493 BagIt](https://www.rfc-editor.org/rfc/rfc8493.html) のフォルダー構造に従います。内容ファイルと管理ファイルの SHA-256 一覧は別々に書きます。`negaflow-archive.json` が、フレーム ID と保存したファイル ID をつなぎます。1つの元ファイルから作った仮想コピーは、保存した1つを共有します。

一時フォルダーは、次のすべてに通った後にだけ最終のパスへ移ります。

1. 現在のアプリがカタログを安全に読める。
2. 元ファイルと IR 入力が通常のファイルで、コピー中にサイズと更新時刻が変わらない。
3. 必要な GrainMend 記録をすべて読める。
4. SHA-256、バイト数、ファイル一覧、`Payload-Oxum` が一致する。
5. フレームと元ファイル、IR ファイル、GrainMend 記録の対応がカタログと一致する。

失敗したときは、作りかけの一時フォルダーだけを削除します。既存のアーカイブはそのまま残ります。

## 限界

元の形式はそのまま保ち、長期互換のための変換はしません。PREMIS の保存イベントとエージェント記録、推奨形式への移行は v1 の対象外です。

アーカイブ1つは保存計画ではありません。別の媒体と別の場所にコピーを置き、ハッシュを定期的に確かめてください。

出典:

- [RFC 8493: The BagIt File Packaging Format](https://www.rfc-editor.org/rfc/rfc8493.html)
- [Library of Congress PREMIS](https://www.loc.gov/standards/premis/)
- [Library of Congress Recommended Formats Statement](https://www.loc.gov/preservation/resources/rfs/)
