<p align="center">
  <img src="../Sources/negaflowApp/Resources/AppIcon-1024.png" width="128" alt="negaflow">
</p>

<h1 align="center">negaflow for macOS</h1>

<p align="center">macOS ネイティブで作った negaflow です。</p>

<p align="center">
  <a href="#"><img src="https://img.shields.io/badge/version-1.1.0-EF8B26" alt="バージョン 1.1.0"></a>
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

## 必要なもの

動かすとき:

- macOS 14.0 以降
- Apple Silicon または Intel
- 35mm ならメモリ 8GB、中判を扱うなら 16GB が楽です

ビルドするとき:

- アプリは Xcode 26
- エンジンと CLI は Swift 5.9 以降

## インストール

[Releases](https://github.com/habinsong/negaflow/releases) からダウンロードします。

| ダウンロード | 対応する Mac |
|---|---|
| `negaflow-1.1.0-1-macOS-universal.pkg` | Apple Silicon、Intel |
| `negaflow-1.1.0-1-macOS-arm64.pkg` | Apple Silicon のみ |

通常は Universal PKG で構いません。開いて案内に従うと `/Applications` に入ります。
手動で置きたい場合は同じページの DMG か ZIP を使ってください。

Apple の公証を受けていないため、初回起動は macOS がブロックします。システム設定の
プライバシーとセキュリティで「このまま開く」を選ぶと起動します。

ライブラリと設定は `~/Library/Application Support/negaflow` に入ります。

## ビルド

```bash
git clone https://github.com/habinsong/negaflow.git
cd negaflow

# Release ビルドして起動
bash scripts/run-app.sh

# 起動せずビルドだけ
bash scripts/run-app.sh build
```

`run-app.sh` が `xcodebuild` を呼び、アプリバンドルを組み立ててローカル署名まで行います。
エンジンや CLI だけ触るなら `swift build` で足り、Xcode は要りません。

配布物を作るとき:

```bash
bash negaflow-mac/scripts/build-release.sh
bash negaflow-mac/scripts/create-release-artifacts.sh
```

## 点検

```bash
# Swift テスト
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test

# アプリの Release ビルド
bash scripts/run-app.sh build

# リポジトリ全体の点検
bash scripts/ci-gate.sh
```

## コマンドライン

macOS 版にはアプリと一緒に使える CLI が入っています。

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

# プロファイル一覧とエンジンの自己点検
.build/debug/negaflow list-scanner-profiles
.build/debug/negaflow selftest
```

引数なしで実行すると全オプションが出ます。

## スキャナー

プラグインを入れるまでスキャナーの操作は現れません。SANE 機器は
[`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane) が担当し、
別途インストールが必要です。

## モジュール構成

| モジュール | 役割 |
|---|---|
| `Chromabase` | Chroma Engine、GrainMend、プロファイル、書き出し |
| `ScannerKit` | スキャナー機能の確認と外部プラグイン接続 |
| `negaflowApp` | ライブラリ、現像、スキャン、書き出しの画面 |
| `negaflowCLI` | 現像、スキャン、ベンチマーク、自己点検 |

## 基準画像

リポジトリ最上位の `docs/verification/macos-golden` には、このビルドが書き出した画像が
入っています。Windows のエンジンテストがこれを読んで画素単位で比べます。二つの版を
揃えている仕組みがこれです。macOS の出力を変えるときだけ作り直してください。

## 関連ドキュメント

- [二つの版の違い](../../docs/ja/platform/PLATFORM_DIFFERENCES.md)
- [Chroma Engine](../../docs/ja/product/CHROMA_ENGINE.md)
- [GrainMend](../../docs/ja/product/GRAINMEND.md)
- [製品構成](../../docs/ja/architecture/PRODUCT_ARCHITECTURE.md)
