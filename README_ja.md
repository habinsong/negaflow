<p align="center">
  <img src="negaflow-mac/Sources/negaflowApp/Resources/AppIcon-1024.png" width="128" alt="negaflow アプリアイコン">
</p>

<h1 align="center">negaflow</h1>

<p align="center">アナログフィルムのスキャンから現像、プリントまで。macOS と Windows それぞれにネイティブなアプリです。</p>

<p align="center">
  <a href="https://habinsong.github.io/negaflow-site/ja/"><img src="https://img.shields.io/badge/website-negaflow-1F6FEB" alt="ウェブサイト"></a>
  <a href="#install"><img src="https://img.shields.io/badge/version-1.1.0-EF8B26" alt="バージョン 1.1.0"></a>
  <a href="negaflow-mac/docs/README_ja.md"><img src="https://img.shields.io/badge/macOS-14.0+-000000?logo=apple&logoColor=white" alt="macOS 14 以降"></a>
  <a href="negaflow-windows/docs/README_ja.md"><img src="https://img.shields.io/badge/Windows-11-0078D4?logo=windows&logoColor=white" alt="Windows 11"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache--2.0-6E7781" alt="Apache 2.0 ライセンス"></a>
</p>

<p align="center">
  <a href="README.md">English</a> ·
  <a href="README_ko.md">한국어</a> ·
  <strong>日本語</strong> ·
  <a href="README_zh-Hans.md">简体中文</a> ·
  <a href="README_fr.md">Français</a> ·
  <a href="README_de.md">Deutsch</a>
</p>

<p align="center">
  <a href="https://habinsong.github.io/negaflow-site/ja/">ウェブサイト</a> ·
  <a href="https://habinsong.github.io/negaflow-site/ja/camera-scanning/">カメラスキャンのガイド</a> ·
  <a href="https://habinsong.github.io/negaflow-site/ja/faq/">FAQ</a>
</p>

---

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/ja/develop-dark.webp">
    <img src="docs/images/ja/develop-light.webp" alt="negaflow 現像画面">
  </picture>
</p>

negaflow は、スキャンしたフィルムやデジタルカメラで複写したフィルムを読み込み、反転して現像する macOS アプリです。<br>
カラーと白黒、ネガとポジに対応し、補正内容は元のファイルと分けて保存します。<br>
ライブラリ管理から現像、プリントまで、フィルムをデジタルで扱う一連の作業を支えます。

現像エンジンの名前は **Chroma Engine**、ゴミやキズの修復機能は **GrainMend** です。<br>
画像ファイルを読み込むだけでも現像と書き出しが使えます。<br>
スキャナー接続は、別途プラグインを導入した場合だけ有効になります。

> 技術は進歩を続けていますが、フィルム人気の再燃とは裏腹に、アナログ写真を取り巻く作業は足踏みしています。<br>
> 暗室でプリントしない限り、フィルムはデジタル化して初めて多くの人が見たり共有したりできます。<br>
> ところが、ラボや現像所が減り、そのための選択肢も少なくなっています。
> <br>
> このプロジェクトは、いくつもの作業方法を試す中で感じた不便と、「こんな機能があれば」と思ったことから始まりました。<br>
> 35mm と中判フィルムで得た経験を土台に、すべてを一から自分で開発しています。<br>
> 最初は自分だけで使う小さなプロジェクトでしたが、今の **negaflow** はそれ以上のものになっています。<br>
> 結局のところ、道具はきちんと動き、気軽に使えて、速く、面倒なことを正しく片づけてくれるのが一番です。<br>
> **negaflow** は独立して開発しているネイティブ macOS アプリで、フィルムラボと個人の両方の作業を取り入れています。
>
> **ニエプスが人類最初の一枚を写してから二百年。その夏に寄せて。**

---

## 二つを別々に作りました

negaflow は macOS でも Windows でも動きます。二つのアプリはコードを共有していません。

| | macOS | Windows |
|---|---|---|
| 画面 | SwiftUI | WinUI 3 |
| エンジン | Swift と Core Image | C++ と Direct3D |
| カラーマネジメント | ColorSync | Windows ICM |

同じ写真を渡せば同じ結果が出ます。macOS 版で書き出した基準画像を Windows のテストが読み込み、
画素単位で照合しています。

それぞれのプラットフォームの流儀で書いたので、片方を移植して継ぎ足したものではありません。
結果として二度作ることになりましたが、どちらもそのOSのアプリとして自然に動きます。

- [macOS のドキュメント](negaflow-mac/docs/README_ja.md)
- [Windows のドキュメント](negaflow-windows/docs/README_ja.md)
- [二つの版の違い](docs/ja/platform/PLATFORM_DIFFERENCES.md)

---

## インストール

[GitHub Releases](https://github.com/habinsong/negaflow/releases)から現在のリリースをダウンロードします。

### macOS

| ダウンロード | 対応するMac |
|---|---|
| `negaflow-1.1.0-1-macOS-universal.pkg` | Apple Silicon、Intel |
| `negaflow-1.1.0-1-macOS-arm64.pkg` | Apple Siliconのみ |

通常は Universal PKG を使ってください。

1. Macに合うPKGをダウンロードします。
2. PKGを開き、インストーラの案内に従います。
3. `/Applications`から**negaflow**を起動します。

手動インストール用のDMGとZIPも同じリリースページにあります。
Appleの公証を受けていないため、初回起動時は**システム設定 → プライバシーとセキュリティ**で
**このまま開く**を選ぶ必要があります。

### Windows

| ダウンロード | 対応するPC |
|---|---|
| `negaflow-1.1.0-x64-setup.exe` | Windows 11 (x64) |

1. インストーラをダウンロードして実行します。
2. 言語を選び、案内に従います。
3. スタートメニューから**negaflow**を起動します。

インストール先はユーザーフォルダーの中だけで、管理者権限は要りません。
削除はスタートメニューの`negaflow の削除`か、設定のアプリ一覧から行います。
署名していないインストーラなので、SmartScreen が一度警告します。詳細情報を押して実行してください。

> スキャナー実機を使うには、別途スキャナープラグインが必要です。<br>
> SANEスキャナーには[`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane)を使用します。macOS と Windows の両方に対応しています。

---

## 機能

- フィルムベースの測定と、カラー・白黒フィルムの反転
- 露出、コントラスト、カーブ、HSL、カラーグレーディング、白黒トーニング
- シャープネス、ノイズ除去、グレイン、ビネット、ハレーション
- ゴミやキズを修復する GrainMend、スキャナーの赤外パスを使う GrainMend IR を含む
- ロール、フォルダー、コレクション、評価、スタック、仮想コピー
- 拡大、切り抜き、回転、比較表示、ヒストグラム、クリッピング表示
- カメラ、レンズ、フィルム、露出の記録を書き出したファイルの EXIF に記録
- ロール単位の撮影記録と、カメラ・レンズ・フィルムで探すライブラリ検索
- JPEG と 16-bit TIFF の書き出し、ICC プロファイル、プリントレイアウト
- レイアウト別の黒・グレー・白シート、共通のマット・光沢・ラスター・シルク表示、
  写真用・ISO用紙、任意のin/cmルーラー
- C-printのラボ・印画紙設定とラボICCソフトプルーフプレビュー
- 読み込み進捗、フォルダー単位の現像プロセス・ターゲット適用と進捗表示
- 折りたたみ状態を記憶するフォルダー一覧、写真のドラッグ移動、Finder変更の自動反映
- プロセス、ターゲット、補正、クロップ、向きを含むプリセットとコピー・ペースト
- 単一画像、コンタクトシート、ピクチャーパッケージ、カスタムパッケージ、サイアノタイプ、
  ガラス乾板、ゼラチンシルバーの7種類のプリントレイアウト
- 39枚の6 × 7コンタクトシートは合成済みの1ファイル、個別画像レイアウトは制限付き
  39ファイルのバッチとして扱い、バーとパーセントを示すプリント書き出しとクイック書き出し


## Chroma Engine

Chroma Engine は `Chromabase` モジュールに入っているフィルム反転・現像エンジンです。<br>
ネガを反転する前に、未露光部分からフィルムベースを測定します。<br>
自動測定が合わないときは、スポイトで範囲を選ぶか RGB 値を直接入力できます。

初期状態は `MAIN` と手動補正です。<br>
自動トーン、自動ホワイトバランス、自動レベル、自動カラーは、自分で実行したときだけ適用されます。

現像ターゲット:

- `MAIN`: 標準現像
- `PRINT`: プリンター ICC を使う出力
- `HS`, `SP`: ミニラボ系の現像
- `F135`, `HR`: 各機器系列の現像スタイル
- `EXPIRED`: 古いフィルムの救済

出力には sRGB、Display P3、Adobe RGB、または任意の RGB ICC を使えます。<br>
反転と色処理の順序は [Chroma Engine](docs/ja/product/CHROMA_ENGINE.md)にあります。

## GrainMend

**GrainMend は、フィルムのゴミ、ピンホール、キズ、乳剤の傷みといった欠陥を修復します。** <br>


| GrainMend RGB | 使い方 |
|---|---|
| 自動 | 写真全体から欠陥を探して修復します。 |
| ガイド | 指定した範囲の中から欠陥を探します。 |
| ブラシ | 修復したい場所を直接塗ります。 |
| コピースタンプ | 指定した場所のピクセルを別の場所へ複製します。 |


**GrainMend RGB** の自動とガイドは周囲の質感を手がかりに欠陥を埋め、 <br>
写真の中の線や格子をキズとして消してしまわないよう、方向と周囲の構造もあわせて調べます。 <br>
修正結果は GrainMend レイヤーとして残ります。 <br><br>
> 自動は写真によくある欠陥を取り除きます。安全に適用できないほど候補が密集した場合は、画像を変えずに停止してガイドの使用を案内します。 <br>
> ガイドはスキャン時に生じるさまざまなゴミに向いています。ブラシは自動で見つからなかった欠陥を直接修復し、コピースタンプは選んだ参照元のピクセルを複製します。 <br>
**GrainMend RGB** のレイヤーはそれぞれ、強さの変更、マスクの確認、個別の無効化や削除ができます。


スキャナープラグインが赤外線チャンネルを提供する場合、**GrainMend IR** の検出結果も同じ編集履歴に加わります。<br><br>

**GrainMend RGB** はハードウェアの赤外線クリーニングとは異なる、独自のソフトウェア方式であり、 <br>
**GrainMend IR** はスキャナーの赤外線チャンネルを使います。Digital ICE、iSRD、SRDx の実装や互換モードではありません。

実装方法と画質・性能の基準は [GrainMend](docs/ja/product/GRAINMEND.md) にあります。

## フィルムプロファイル

作者が実際に撮影したフィルム資料から作ったスキャナープロファイルを 15 個収録しています。<br>
画像の観測値は合計 928 件で、現在はすべて `realOnly` です。<br>
`realOnly` は実スキャンを元に作られているものの、独立した基準スキャンとの組み合わせで精度確認を終えていない状態です。

スキャナー名だけでプロファイルを自動適用することはありません。<br>
利用者が自分で選択します。<br>
アプリは各ファイルと一覧の SHA-256 も検証します。

`928` はプロファイルごとの観測数を足した値です。<br>
同じフィルムが複数のスキャナーに重複して数えられるため、異なる写真が 928 枚あるという意味ではありません。<br>
元になった 928 件のスキャンはすべて自分で確認し、誤検出や見逃しのあるファイルを測定前に除外しました。<br>
資料と生成手順は [フィルムプロファイル](docs/ja/product/FILM_PROFILES.md)に記載しています。

## 基本の使い方

1. 画像ファイルを読み込むか、導入済みのプラグインでスキャンします。
2. フィルムの種類を選び、フィルムベースを測定します。
3. Chroma Engine で色とトーンを調整します。
4. 必要な写真に GrainMend を使います。
5. 比較表示とヒストグラムで確認してからプリントまたは書き出します。

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/ja/library-dark.webp">
    <img src="docs/images/ja/library-light.webp" alt="negaflow ライブラリ画面">
  </picture>
</p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/ja/print-dark.webp">
    <img src="docs/images/ja/print-light.webp" alt="negaflow プリント画面">
  </picture>
</p>

画面は、写真を扱う人が使いやすいように作りました。<br>
AI が形だけ作ったような UI ではなく、写真が趣味なら迷わず使える操作を目指しています。

## ライブラリからプリントまで

画像を読み込んだだけでは、初期設定では現像しません。まず元画像のサムネイルとフォルダーを
作り、フォルダーでプロセスとターゲットを適用するか、現像画面に入った時点で現像を始めます。
自動現像は設定のワークフローで有効にでき、初期値はオフです。

フォルダーの折りたたみ状態は再起動後も残ります。写真はフォルダー間でドラッグでき、同名の
ファイルがある場合は上書きせず番号を付けます。Finderで元画像やフォルダーを移動・改名すると、
変更されたフォルダーだけを読み直してライブラリの位置を合わせます。

現像設定のコピー・ペーストとユーザープリセットには、プロセス、ターゲット、フィルムベース、
トーン、色、ディテール、クロップ、回転、反転、傾き補正が含まれます。複数選択時は選択した
すべての写真に適用します。

プリント画面のプリンター出力プロファイルは、組み上げたページ全体に適用されます。同じ写真を
繰り返す写真パッケージや複数写真のレイアウトでも、すべての配置に反映されます。現像画面の
プレビューには入りません。

詳しい動作は[ライブラリからプリントまで](docs/ja/product/WORKFLOW.md)にまとめています。

## ソースからビルド

必要な道具とコマンドはプラットフォームごとに違います。詳しくは各ドキュメントにあります。

**macOS**

```bash
git clone https://github.com/habinsong/negaflow.git
cd negaflow

# Release ビルドして起動
bash scripts/run-app.sh

# 起動せずビルドだけ
bash scripts/run-app.sh build
```

macOS 14 以降と Xcode 26 が必要です。エンジンとCLIだけなら `swift build` で足ります。
[macOS のドキュメント](negaflow-mac/docs/README_ja.md)に続きがあります。

**Windows**

```powershell
git clone https://github.com/habinsong/negaflow.git
cd negaflow\negaflow-windows

# エンジンのビルド
.\scripts\build.ps1 -Preset x64-release

# アプリをビルドして起動
.\scripts\run-app.ps1 -Architecture x64 -Configuration Release
```

Windows 11、Visual Studio 2022、.NET 10 SDK が必要です。
[Windows のドキュメント](negaflow-windows/docs/README_ja.md)に続きがあります。

## スキャナー

negaflow はスキャナーの機種名から機能を推測しません。<br>
プラグインが返した解像度、ビット深度、スキャン範囲、露出、IR 機能だけを使います。

SANE 機器は別の GPL プロジェクト [`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane)が担当します。<br>
プラグインは別プロセスで動き、本体とは JSON で通信します。<br>
negaflow 本体は SANE コードを含まず、リンクもしません。

## リポジトリ構成

```
negaflow/
├── negaflow-mac/       macOS のアプリとエンジン (Swift)
├── negaflow-windows/   Windows のアプリとエンジン (C#, C++)
└── docs/               共通のドキュメント
```

**macOS**

| モジュール | 役割 |
|---|---|
| `Chromabase` | Chroma Engine、GrainMend、プロファイル、書き出し |
| `ScannerKit` | スキャナー機能の確認と外部プラグイン接続 |
| `negaflowApp` | ライブラリ、現像、スキャン、書き出しの画面 |
| `negaflowCLI` | 現像、スキャン、ベンチマーク、自己点検 |

**Windows**

| モジュール | 役割 |
|---|---|
| `Native` | Chroma Engine、GrainMend、書き出し (C++) |
| `Interop` | エンジンとアプリをつなぐ層 |
| `Catalog.Core` | ライブラリの保存 |
| `Shell.Core` | 現像、プリント、書き出しのロジック |
| `Shell` | ライブラリ、現像、プリントの画面 (WinUI 3) |

モジュール間のデータの流れは[製品構成のドキュメント](docs/ja/architecture/PRODUCT_ARCHITECTURE.md)にあります。

## ドキュメント

| ドキュメント | 内容 |
|---|---|
| [Chroma Engine](docs/ja/product/CHROMA_ENGINE.md) | フィルムベース、反転、色処理、現像の順序 |
| [GrainMend](docs/ja/product/GRAINMEND.md) | 欠陥の検出と修復、IR、編集履歴、品質と性能の基準 |
| [フィルムプロファイル](docs/ja/product/FILM_PROFILES.md) | 撮影素材の分析とプロファイル生成 |
| [ライブラリからプリントまで](docs/ja/product/WORKFLOW.md) | 読み込み、フォルダー同期、一括現像、設定のコピー、プリントプロファイル |
| [製品構成](docs/ja/architecture/PRODUCT_ARCHITECTURE.md) | アプリ、エンジン、スキャナー、保存、書き出しの構成 |
| [二つの版の違い](docs/ja/platform/PLATFORM_DIFFERENCES.md) | macOS と Windows で同じところと違うところ |
| [macOS のドキュメント](negaflow-mac/docs/README_ja.md) | macOS のインストール、ビルド、CLI |
| [Windows のドキュメント](negaflow-windows/docs/README_ja.md) | Windows のインストール、ビルド、エンジン点検 |

## ライセンス

negaflow 本体は [Apache License 2.0](LICENSE) で配布します。

negaflow は Kodak、Fujifilm、Noritsu、LaserSoft Imaging、その他の商標権者と提携しておらず、支援も受けていません。<br>
製品名は測定対象や互換対象を示す場合にだけ使います。<br>
詳しくは [商標について](TRADEMARKS.md)をご覧ください。
