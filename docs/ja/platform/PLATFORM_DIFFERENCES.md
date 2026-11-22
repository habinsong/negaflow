# macOS 版と Windows 版の違い

[ドキュメントホーム](../README.md)

negaflow は macOS 用と Windows 用の二本立てです。二つはソースコードを共有せず、それぞれのシステムのやり方で作っています。

## 二本立てにした理由

クロスプラットフォームのコードベースを1つにすると、ツールキット1つとその妥協を両方のシステムに持ち込むことになります。メニューやファイルダイアログの挙動がぎこちなくなり、色の変換層が1つ増え、ウィンドウがシステムと合わなくなります。それぞれネイティブで作ると、機能ごとに2回作って2回テストするので手間が約2倍かかります。その代わり、どちらの版も、そのシステムで人が期待する通りに動きます。

## 同じもの

絵です。同じスキャンを入れると、どちらでも同じ結果になります。

macOS ビルドは `docs/verification/macos-golden` に基準画像を描画します。このフォルダーは Git が無視するため、画像は描画したマシンにしかありません。Windows のエンジンテストはそのコピーを読んでピクセル値を比べるので、Windows のエンジンがずれるとテストが失敗します。

次も同じです。

- フィルムベースの測定と反転
- すべての現像ターゲット: `MAIN`、`PRINT`、`HS`、`SP`、`F135`、`HR`、`EXPIRED`、`CS`
- トーン、カーブ、HSL、カラーグレーディング、白黒のトーニング
- 赤外線の経路を含む GrainMend の検出と修復
- プリントレイアウトとページの幾何
- 各形式での書き出しファイル名と、JPEG・TIFF・DNG における EXIF・メタデータの方針（Windows の PNG 書き出しは EXIF メタデータを含めず、DPI と ICC プロファイルのみを保持）
- カタログの形式(`library.sqlite`)

## 違うもの

### カラーマネジメント

macOS は ColorSync、Windows は ICM を使います。どちらも同じ ICC プロファイルを受け取り、丸めの範囲で同じ数値を出します。黙ってずれやすい部分なので、整合性テストが対象にしています。

画面表示では、macOS はディスプレイの ColorSync プロファイルを通して描きます。Windows がそうするのは Advanced Color がオンのときだけです。オフのときはアプリの画素を sRGB とみなしてそのまま送るので、negaflow が現像キャンバスと印刷プレビュー（小さなコンタクトシートのタイルを含む）を描く直前に、モニター ICC の 33³ LUT を適用します。モニターを切り替えたときや、ディスプレイ設定を変更してウィンドウへ戻ったときは自動で更新します。サムネイルとほかの画面要素は sRGB のまま描きます。

### グラフィックス

macOS は現像チェーンを Core Image 上で既定の 16 ビット半精度浮動小数点リニア（`RGBAh`）で処理します。Windows は Direct3D 11 のコンピュートシェーダーで動かし、GPU の経路が使えないときは CPU に切り替え、どちらの経路でも 32 ビット浮動小数点（`RGBA32F`）を使います。

### ファイルの場所

| | macOS | Windows |
|---|---|---|
| アプリ | `/Applications/negaflow.app` | `%LOCALAPPDATA%\Negaflow\App` |
| カタログ、欠陥サイドカー、レシピ、プリントテンプレート | `~/Library/Application Support/negaflow` | `%LOCALAPPDATA%\Negaflow` |
| アプリ環境設定 | `UserDefaults`（`~/Library/Preferences/com.songhabin.negaflow.plist`） | `%LOCALAPPDATA%\Negaflow` |

### インストールと削除

macOS は、アプリを `/Applications` に入れる PKG で配布します。削除はアプリをゴミ箱へ移します。Windows のインストーラーは `%LOCALAPPDATA%\Negaflow\App` に書き込み、署名のない展開済みアプリパッケージの登録（`AllowDevelopmentWithoutDevLicense`）がまだ許可されていない場合にだけ、初回に管理者確認を求めます。削除はスタートメニューの `Uninstall negaflow` か設定から行い、アプリのフォルダー、スタートメニューの項目、パッケージの登録が消えます。

### コマンドライン

GUI リリースのインストーラーには CLI バイナリは含まれず、各プラットフォームのソースビルドから用意します。macOS では `swift build` でビルドすると、スキャナーの検出、ファイルの現像、GrainMend の実行、ベンチマークができる `negaflow` が作られます。Windows では CMake でビルドすると、1つのファイルでエンジンが何をするかを確かめる小さな診断ツール `negaflow-cli.exe` が作られ、サブコマンドではなくフラグを受け取ります。

### 署名

どちらのビルドも有料の開発者証明書では署名していないため、初回起動で両システムが警告します。Mac 版は ad hoc 署名で公証は受けていないので、プライバシーとセキュリティで「このまま開く」を選んで許可します。Windows のインストーラーは署名がないため、SmartScreen で詳細情報を押してから実行します。

## スキャナー

スキャナープラグインは、別の GPL プロジェクト [`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane) で、両方のシステム用があります。別プロセスで動き JSON でやり取りするので、negaflow 本体にはどちらのプラットフォームにも SANE のコードはありません。Windows では Windows がすでに備えているスキャナードライバーの経路を通るため、同じ PC で VueScan や SilverFast も使い続けられます。

## そろえておく方法

機能はまず macOS に入り、次に Windows へ、実際の macOS の動作に合わせて入ります。出力を測れるところでは、macOS の基準画像が Windows の正しさを決めます。両者がずれたら正解は macOS で、Windows 側が不具合です。
