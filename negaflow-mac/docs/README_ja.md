<p align="center">
  <img src="../Sources/negaflowApp/Resources/AppIcon-1024.png" width="128" alt="negaflow">
</p>

<h1 align="center">negaflow for macOS</h1>

<p align="center">macOS ネイティブで作った negaflow です。</p>

<p align="center">
  <a href="#"><img src="https://img.shields.io/badge/version-1.2.6-EF8B26" alt="バージョン 1.2.6"></a>
  <a href="#"><img src="https://img.shields.io/badge/macOS-14.0+-000000?logo=apple&logoColor=white" alt="macOS 14 以降"></a>
  <a href="../../LICENSE"><img src="https://img.shields.io/badge/license-Apache--2.0-6E7781" alt="Apache 2.0"></a>
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
  <a href="../../README_ja.md">共通ドキュメント</a> ·
  <a href="../../negaflow-windows/docs/README_ja.md">Windows</a>
</p>

---

## 動作環境

実行に必要なもの:

- macOS 14.0 以降（macOS 14、26、27 に対応）
- Apple Silicon または Intel
- メモリ 8GB（中判は 16GB を推奨）

ビルドに必要なもの:

- アプリ: Xcode 26 以降
- エンジンと CLI: Swift 5.9 以降

## インストール

[Releases](https://github.com/habinsong/negaflow/releases) から入手します。

| ファイル | 対応する Mac |
|---|---|
| `negaflow-1.2.6-mac-universal.pkg` | Apple Silicon、Intel |
| `negaflow-1.2.6-mac-arm64.pkg` | Apple Silicon のみ |

ほとんどの Mac では Universal PKG を使います。`/Applications` に入ります。アプリを自分で置きたいときは、同じページの DMG か ZIP を使ってください。

アプリは ad hoc 署名で公証を受けていないため、初回起動は macOS に止められます。システム設定のプライバシーとセキュリティで「このまま開く」を選んでください。

ライブラリと設定は `~/Library/Application Support/negaflow` にあります。

アプリは起動時に一度だけ GitHub に最新リリースを問い合わせます。新しい版があれば、右上の ⋯ メニューのいちばん下に「バージョン X.Y.Z にアップデート」が出ます。選ぶとリリースページが開き、この Mac に合う PKG をリリースの `SHA256SUMS.txt` で確かめてからダウンロードフォルダーに保存します。インストールはご自身で行います。最新のときは項目が「最新バージョンです。」になり、選ぶとプロジェクトページが開きます。オフラインなどで確認できなかったときは項目が出ません。

## ビルド

```bash
git clone https://github.com/habinsong/negaflow.git
cd negaflow/negaflow-mac

# Release ビルドして起動
bash scripts/run-app.sh

# 起動せずにビルドだけ
bash scripts/run-app.sh build
```

`run-app.sh` は `xcodebuild` を呼び、アプリバンドルを組み立ててローカルで署名します。エンジンや CLI だけなら `swift build` で足ります。

配布ファイル:

```bash
bash negaflow-mac/scripts/build-release.sh
bash negaflow-mac/scripts/create-release-artifacts.sh
```

## 確認

```bash
# Swift のテスト
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test

# アプリの Release ビルド
bash scripts/run-app.sh build

# リポジトリの全チェック
bash scripts/ci-gate.sh
```

## Custom カラーターゲット

ターゲットのカプセルは MAIN、HS、SP、F135、HR の次が CS です。CS を選ぶと、左下のセレクターに Custom ターゲット18個の2列リストが開き、ルックのセレクターは右に残ります。CS に入ると Emulsion が選ばれ、すでに Custom ターゲットを使っている写真はそのターゲットのままです。

リストは3つの組に分かれます。Emulsion から Dichroic までの11個、Wetzlar から Rochester までの4個、Slide Show から Point & Shoot までの3個です。Custom ターゲットは custom-3 のトーン・濃度・彩度の応答を適用します。保存、プレビュー、サムネイル、書き出しは選んだターゲット ID を使います。ほかのターゲットは変わりません。

CLI も同じ ID を受け取ります: `--target classic`、`--target dye-transfer`、`--target point-and-shoot`。

## コマンドライン

macOS 版には CLI が付いています。

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

# プロファイルとエンジンの自己確認
.build/debug/negaflow list-scanner-profiles
.build/debug/negaflow selftest
```

全オプションは、引数なしで `negaflow` を実行すると出ます。

## スキャナー

プラグインを入れるまで、スキャナーのコントロールは表示されません。SANE 機器は、別に入れる [`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane) が担当します。

## モジュール

| モジュール | 役割 |
|---|---|
| `Chromabase` | Chroma Engine、GrainMend、プロファイル、書き出し |
| `ScannerKit` | スキャナー機能の確認とプラグイン接続 |
| `negaflowApp` | ライブラリ、現像、スキャン、書き出しの画面 |
| `negaflowCLI` | 現像、スキャン、ベンチマーク、自己確認のコマンド |

## 基準画像

`docs/verification/macos-golden` に、このビルドで描画した画像があります。このフォルダーは Git が無視するため、画像を作ったマシンにしかありません。Windows のエンジンテストが、そのコピーとピクセル単位で比べます。macOS の出力をあえて変えるときだけ作り直してください。

## 関連ドキュメント

- [両バージョンの違い](../../docs/ja/platform/PLATFORM_DIFFERENCES.md)
- [Chroma Engine](../../docs/ja/product/CHROMA_ENGINE.md)
- [GrainMend](../../docs/ja/product/GRAINMEND.md)
- [製品構造](../../docs/ja/architecture/PRODUCT_ARCHITECTURE.md)
