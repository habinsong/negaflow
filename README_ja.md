<p align="center">
  <img src="Sources/negaflowApp/Resources/AppIcon-1024.png" width="128" alt="negaflow アプリアイコン">
</p>

<h1 align="center">negaflow</h1>

<p align="center">アナログフィルムのカメラ複写・スキャンから現像までを支える macOS アプリ</p>

<p align="center">
  <a href="docs/product/PROJECT_STATUS.md"><img src="https://img.shields.io/badge/status-1.0.0%20release-EF8B26" alt="リリース状況"></a>
  <a href="#動作環境"><img src="https://img.shields.io/badge/macOS-14.0+-000000?logo=apple&logoColor=white" alt="macOS 14 以降"></a>
  <a href="Package.swift"><img src="https://img.shields.io/badge/Swift-5.9+-F05138?logo=swift&logoColor=white" alt="Swift 5.9 以降"></a>
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

---

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
> 確認済みの範囲は[プロジェクトの状況](docs/product/PROJECT_STATUS.md)に記録しています。<br>
> **ニエプスが最初の写真を撮ってから200年となる、この夏を記念して。**

---

## インストール

現在のリリースは[GitHub Releases](https://github.com/habinsong/negaflow/releases)からダウンロードできます。<br>
通常はUniversal PKGを使用してください。

| ダウンロード | 対応するMac |
|---|---|
| `Negaflow-1.0.0-1-macOS-universal.pkg` | Apple Silicon、Intel |
| `Negaflow-1.0.0-1-macOS-arm64.pkg` | Apple Siliconのみ |

1. Macに合うPKGをダウンロードします。
2. PKGを開き、インストーラの案内に従います。
3. `/Applications`から**Negaflow**を起動します。

PKGは`Negaflow.app`を`/Applications`へ直接インストールします。<br>
手動インストール用のDMGとZIPも同じリリースページにあります。<br>
GitHubで公開するファイルは、Developer IDで署名し、Appleの公証を済ませたものです。

> スキャナー実機を使うには、別途スキャナープラグインが必要です。<br>
> SANEスキャナーには[`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane)を使用します。

## 機能

- フィルムベースの測定と、カラー・白黒フィルムの反転
- 露出、コントラスト、カーブ、HSL、カラーグレーディング、白黒トーニング
- シャープネス、ノイズ除去、グレイン、ビネット、ハレーション
- ゴミやキズを修復する GrainMend
- ロール、フォルダー、コレクション、評価、スタック、仮想コピー
- 拡大、切り抜き、回転、比較表示、ヒストグラム、クリッピング表示
- JPEG と 16-bit TIFF の書き出し、ICC プロファイル、プリントレイアウト

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
反転と色処理の順序は [Chroma Engine](docs/product/CHROMA_ENGINE.md)にあります。

## GrainMend

GrainMend は、フィルムのゴミ、ピンホール、キズ、乳剤の傷みを修復します。<br>
画面上の名前はどの言語でも `GrainMend` のままです。<br>
各ツール名とヘルプだけを翻訳しています。

| ツール | 用途 |
|---|---|
| 自動 | 画像全体から欠陥を探して修復します。 |
| ガイド | 指定した範囲の中から欠陥を探します。 |
| ブラシ | 修復したい場所を直接塗ります。 |
| コピースタンプ | 指定した場所のピクセルを別の場所へ複製します。 |

自動とガイドは周囲の質感を使って欠陥を埋めます。<br>
写真内の線や格子をキズと間違えて消さないように、方向と周囲の構造も調べます。<br>
修正結果は GrainMend レイヤーとして残り、強さの変更、マスクの確認、個別の無効化や削除ができます。

自動は写真全体の一般的な欠陥を処理します。<br>
安全に適用できないほど候補が密集した場合、自動は画像を変更せずに停止し、範囲を絞ってガイドを使うよう案内します。<br>
ガイドはスキャン時に生じるさまざまなゴミを狙うための機能です。<br>
ブラシは自動処理で見落とした欠陥を補い、コピースタンプは選んだ参照元を修復先へ直接複製します。

スキャナープラグインが赤外線チャンネルを提供する場合、IR の検出結果も同じ編集履歴へ追加します。<br>
GrainMend RGB はハードウェアの赤外線クリーニングとは別の方式です。<br>
GrainMend IR も Digital ICE、iSRD、SRDx の実装や互換モードではありません。

実装方法と画質・性能の基準は [GrainMend](docs/product/GRAINMEND.md)にあります。

## フィルムプロファイル

作者が実際に撮影したフィルム資料から作ったスキャナープロファイルを 15 個収録しています。<br>
画像の観測値は合計 928 件で、現在はすべて `realOnly` です。<br>
`realOnly` は実スキャンを元に作られているものの、独立した基準スキャンとの組み合わせで精度確認を終えていない状態です。

スキャナー名だけでプロファイルを自動適用することはありません。<br>
利用者が自分で選択します。<br>
各ファイルと一覧の SHA-256 も確認します。

`928` はプロファイルごとの観測数を足した値です。<br>
同じフィルムが複数のスキャナーに重複して数えられるため、異なる写真が 928 枚あるという意味ではありません。<br>
元になった 928 件のスキャンはすべて自分で確認し、誤検出や見逃しのあるファイルを測定前に除外しました。<br>
資料と生成手順は [フィルムプロファイル](docs/product/FILM_PROFILES.md)に記載しています。

## 基本の使い方

1. 画像ファイルを読み込むか、導入済みのプラグインでスキャンします。
2. フィルムの種類を選び、フィルムベースを測定します。
3. Chroma Engine で色とトーンを調整します。
4. 必要な写真に GrainMend を使います。
5. 比較表示とヒストグラムで確認してからプリントまたは書き出します。

画面は、写真を扱う人が使いやすいように作りました。<br>
AI が形だけ作ったような UI ではなく、写真が趣味なら迷わず使える操作を目指しています。

## ソースからビルド

### 動作環境

- macOS 14.0 以降
- GUI アプリ: Xcode 26
- エンジンと CLI: Swift 5.9 以降
- ハードウェアスキャン: 別途スキャナープラグイン

```bash
git clone https://github.com/habinsong/negaflow.git
cd negaflow

# Release ビルド後に起動
bash scripts/run-app.sh

# 起動せずにビルド
bash scripts/run-app.sh build
```

GUI アプリは `xcodebuild` でビルドします。<br>
`scripts/run-app.sh` がビルド、アプリバンドルの組み立て、ローカル署名を行います。<br>
エンジンと CLI だけをビルドする場合は `swift build` を使います。

## CLI

```bash
swift build

# スキャナーを探す
.build/debug/negaflow detect
.build/debug/negaflow capabilities <scannerID>

# 現像
.build/debug/negaflow develop in.tiff out.jpg --look rich-neutral --target main

# GrainMend
.build/debug/negaflow develop scan.tif out.jpg --defects 1
.build/debug/negaflow defect-bench ./scans --out ./report

# プロファイル一覧とエンジンの自己診断
.build/debug/negaflow list-scanner-profiles
.build/debug/negaflow selftest
```

すべてのオプションは、引数を付けずに `negaflow` を実行すると確認できます。

## スキャナー

negaflow はスキャナーの機種名から機能を推測しません。<br>
プラグインが返した解像度、ビット深度、スキャン範囲、露出、IR 機能だけを使います。

SANE 機器は別の GPL プロジェクト [`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane)が担当します。<br>
プラグインは別プロセスで動き、本体とは JSON で通信します。<br>
negaflow 本体は SANE コードを含まず、リンクもしません。

## リポジトリ構成

| モジュール | 役割 |
|---|---|
| `Chromabase` | Chroma Engine、GrainMend、プロファイル、書き出し |
| `ScannerKit` | スキャナー機能の確認と外部プラグイン接続 |
| `negaflowApp` | ライブラリ、現像、スキャン、書き出しの画面 |
| `negaflowCLI` | 現像、スキャン、ベンチマーク、自己診断コマンド |

モジュール間のデータの流れは [製品構成](docs/architecture/PRODUCT_ARCHITECTURE.md)にあります。

## 開発時の確認

```bash
# Swift テスト
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test

# GUI Release ビルド
bash scripts/run-app.sh build

# リポジトリ全体の確認
bash scripts/ci-gate.sh
```

自動テストはコードの動作と回帰を確認します。<br>
スキャナー固有の動作、最終画質、署名、公証は別に確認します。

## ドキュメント

| ドキュメント | 内容 |
|---|---|
| [Chroma Engine](docs/product/CHROMA_ENGINE.md) | フィルムベース、反転、色処理、現像順序 |
| [GrainMend](docs/product/GRAINMEND.md) | 欠陥の検出と修復、IR、編集履歴、性能と画質基準 |
| [フィルムプロファイル](docs/product/FILM_PROFILES.md) | 撮影資料の分析とプロファイル生成 |
| [製品構成](docs/architecture/PRODUCT_ARCHITECTURE.md) | アプリ、エンジン、スキャナー、保存、書き出し |
| [プロジェクトの状況](docs/product/PROJECT_STATUS.md) | 実装状況、測定結果、残っている確認 |
| [実機・画質確認表](docs/validation/REAL_QA_CHECKLIST.md) | 実機と画面で確認する項目 |

## ライセンス

negaflow 本体は [Apache License 2.0](LICENSE) で配布します。

Negaflow は Kodak、Fujifilm、Noritsu、LaserSoft Imaging、その他の商標権者と提携しておらず、支援も受けていません。<br>
製品名は測定対象や互換対象を示す場合にだけ使います。<br>
詳しくは [商標について](TRADEMARKS.md)をご覧ください。
