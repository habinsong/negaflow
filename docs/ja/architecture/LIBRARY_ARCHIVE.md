# ライブラリ保存アーカイブ

[ドキュメントホーム](../README.md)

カタログのバックアップはアプリを再び動かすためのもので、元の写真は含みません。どちらのプラットフォームも `.negaflowarchive` を書き出しますが、macOS と Windows ではパッケージ形式と中身が異なります。

> [!WARNING]
> アーカイブの作成に失敗しても、元ファイル、他社製 XMP、実行中のカタログ、既存のアーカイブには触れません。

## macOS アーカイブ（BagIt フォルダー）

macOS の `.negaflowarchive` は [RFC 8493 BagIt](https://www.rfc-editor.org/rfc/rfc8493.html) のフォルダー構造に従い、カタログ状態と参照している写真を1つにまとめます。

| 含めるもの | 含めないもの |
|---|---|
| 持ち運べるカタログ JSON | 実行中の SQLite ファイル |
| 参照している元ファイルと残っている IR 元ファイル | サムネイルとプレビュー |
| GrainMend の欠陥レシピ | 作り直せる GrainMend キャッシュ |
| 仮想コピーと共有元ファイルの対応 | 書き出したファイル |

内容ファイルとタグファイルの SHA-256 マニフェスト（`manifest-sha256.txt`、`tagmanifest-sha256.txt`）は別々に書きます。`negaflow-archive.json` がフレーム ID と保存したファイル ID をつなぎ、1つの元ファイルから作った仮想コピーは保存した1つを共有します。

書き込み先のパスがすでにある場合、上書きは拒否されます。一時フォルダーは次のすべてに通った後にだけ最終のパスへ移ります。

1. 現在のアプリがカタログを安全に読める。
2. 元ファイルと IR 入力が通常のファイルで、コピー中にサイズと更新時刻が変わらない。
3. 必要な GrainMend の欠陥レシピをすべて読める。
4. SHA-256 ハッシュ（`manifest-sha256.txt`、`tagmanifest-sha256.txt`）、バイト数、ファイル一覧、`Payload-Oxum` が一致する。
5. フレームと元ファイル、IR ファイル、GrainMend レシピの対応がカタログと一致する。

失敗したときは、作りかけの一時フォルダーだけを削除します。

## Windows アーカイブ（ZIP ファイル）

Windows の `.negaflowarchive` はカタログと欠陥状態を収めた ZIP アーカイブです。元の写真ファイルはコピーしません。

| 含めるもの | 含めないもの |
|---|---|
| `library.sqlite` | 元の写真ファイルと IR 元ファイル |
| `defects/*` の欠陥レシピ | サムネイル、プレビュー、作り直せるキャッシュ |
| `archive.json`（項目ごとのバイト数と SHA-256 ハッシュ） | 書き出したファイル |

Windows は一時ファイルへ書き出してから検証し、成功したら出力先をアトミックに入れ替えます。作成に失敗した場合は一時ファイルを取り除き、既存のアーカイブには触れません。

## 限界

macOS と Windows の `.negaflowarchive` は形式とカタログのスキーマが異なるため、アーカイブは同じプラットフォームのマシン間で移行します。元の形式はそのまま保ち、長期互換のための変換はしません。PREMIS の保存イベントとエージェント記録、推奨形式への移行は v1 の対象外です。

アーカイブ1つは保存計画ではありません。別の媒体と別の場所にコピーを置き、ハッシュを定期的に確かめてください。

出典:

- [RFC 8493: The BagIt File Packaging Format](https://www.rfc-editor.org/rfc/rfc8493.html)
- [Library of Congress PREMIS](https://www.loc.gov/standards/premis/)
- [Library of Congress Recommended Formats Statement](https://www.loc.gov/preservation/resources/rfs/)
