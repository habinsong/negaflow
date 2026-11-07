<p align="center">
  <img src="../../negaflow-mac/Sources/negaflowApp/Resources/AppIcon-1024.png" width="128" alt="negaflow">
</p>

<h1 align="center">negaflow for Windows</h1>

<p align="center">Windows ネイティブで作った negaflow です。</p>

<p align="center">
  <a href="#"><img src="https://img.shields.io/badge/version-1.2.6-EF8B26" alt="バージョン 1.2.6"></a>
  <a href="#"><img src="https://img.shields.io/badge/Windows-11%2024H2+-0078D4?logo=windows&logoColor=white" alt="Windows 11 24H2 以降"></a>
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
  <a href="../../negaflow-mac/docs/README_ja.md">macOS</a>
</p>

---

## 動作環境

実行に必要なもの:

- Windows 11 24H2（ビルド 26100）以降、64 ビット
- メモリ 8GB（中判は 16GB を推奨）

ビルドに必要なもの:

- Visual Studio 2026（C++ によるデスクトップ開発ワークロード付き。構成要素は `.vsconfig` にあります）
- Windows 11 SDK 10.0.26100 以降
- .NET 10 SDK（`global.json` が 10.0.302 に固定）
- CMake 4.2 以降（`Visual Studio 18 2026` ジェネレーターが必要とします）
- Python 3（アイコンとリソースのスクリプト用）

ビルドには Arm64 プリセットもあります。配布するのは x64 のみです。

## インストール

[Releases](https://github.com/habinsong/negaflow/releases) から `negaflow-1.2.6-win-x64.exe` を入手して実行します。既定のインストール先は `%LOCALAPPDATA%\Negaflow\App` で、管理者権限は求められません。

[negaflow-1.2.6-win-x64-setup.zip](https://github.com/habinsong/negaflow/releases/download/v1.2.6/negaflow-1.2.6-win-x64-setup.zip) には、同じインストーラー EXE と、インストール手順、ライセンス表記、SHA-256 チェックサムが入っています。すべて展開してからインストーラーを実行してください。インストーラーの圧縮版で、ポータブルアプリではありません。

インストーラーに署名はありません。初回の実行で SmartScreen が一度警告します。詳細情報を押してから実行してください。

削除は、スタートメニューの `Uninstall negaflow` か、設定のアプリ一覧から行います。ライブラリと写真はそのまま残ります。

アプリは起動時に一度だけ GitHub に最新リリースを問い合わせます。新しい版があれば、右上の ⋯ メニューのいちばん下に「バージョン X.Y.Z にアップデート」が出ます。選ぶとリリースページが開き、`win-x64.exe` のインストーラーをリリースの `SHA256SUMS.txt` で確かめてからダウンロードフォルダーに保存します。インストールはご自身で行います。最新のときは項目が「最新バージョンです。」になり、選ぶとプロジェクトページが開きます。オフラインなどで確認できなかったときは項目が出ません。

## ビルド

```powershell
git clone https://github.com/habinsong/negaflow.git
cd negaflow\negaflow-windows

# C++ エンジンをビルド
.\scripts\build.ps1 -Preset x64-release

# アプリをビルドして起動
.\scripts\run-app.ps1 -Architecture x64 -Configuration Release
```

`build.ps1` は `x64-debug`、`x64-release`、`arm64-debug`、`arm64-release` を受け付けます。

開発中は、`run-app.ps1` だけでアプリを起動します。アプリは MSIX パッケージとしてビルドされるため、ビルドフォルダーの exe を直接実行しても何も起きません。スクリプトがパッケージをビルドし、現在のユーザーに登録して、アプリ ID で起動します。

インストーラーのビルド:

```powershell
.\scripts\build-release.ps1 -Architecture x64
```

出力は `out\release\win-x64` に作られます。

## 確認

```powershell
# C++ エンジンのテスト
ctest --preset x64-release --output-on-failure

# アプリとカタログのテスト
.\scripts\test-managed.ps1

# エンジンとアプリの境界テスト
.\scripts\test-interop.ps1

# 上のすべてをまとめて実行
.\scripts\local-ci.ps1
```

`scripts\verify-installer.ps1`（`local-ci.ps1` からも呼ばれます）は、サインイン済みのデスクトップセッションで実行してください。SSH セッションでは AppX の登録が `0x80070005` で失敗することがあるため、スクリプトは既存のインストールに触れる前に止まります。

CI が実行するのは、それだけで完結するエンジンテストのみです。macOS の基準ファイルは Git の外に置いています。この比較を実行するには、CMake の構成時に `NEGAFLOW_MACOS_GOLDEN_ROOT` を基準フォルダーに設定します。フォルダーには `task6-metadata-policy`、`task9-bw-slide`、`task7-coreimage-filters`、`task8-digital-film-look`、`vibrance` が必要です。ファイルがないか読めない場合、選んだ比較は失敗します。`ctest --preset x64-release -L external-golden` がこの比較を実行し、通常の単体テストも有効なままです。

## Custom カラーターゲット

ターゲットのカプセルは MAIN、HS、SP、F135、HR の次が CS です。CS を選ぶと、左下に Custom ターゲット18個の2列リストが開き、11個・4個・3個の組に分かれています。ルックのセレクターは右に残ります。CS に入ると Emulsion が選ばれ、すでに Custom ターゲットを使っている写真はそのターゲットのままです。

Custom は macOS と同じ custom-3 の係数と文字列 ID を使います。選んだターゲットは写真の設定とカタログに保存され、プレビューと書き出しは同じ段階を通ります。フォルダーの見出しでは、既存の適用ボタンで選んだターゲットをフォルダーに適用します。

## コマンドラインでエンジンを確認

`negaflow-cli.exe` は、1つのファイルでエンジンを動かして確かめるツールです。サブコマンドではなくフラグを受け取ります。

```powershell
$cli = "out\build\native\x64-release\Release\negaflow-cli.exe"

# ビルド情報
& $cli --build-info

# スキャンファイルの中身
& $cli --probe-tiff scan.tif

# 現像して 16bit TIFF で保存
& $cli --export-developed-tiff16 scan.tif out.tif

# 現像1回の時間の内訳
& $cli --develop-timing scan.tif

# フィルムベースの自動測定と選ばれた値
& $cli --auto-base-probe scan.tif
```

全一覧は、引数なしで実行すると出ます。

## スキャナー

プラグインを入れるまで、スキャナーのコントロールは表示されません。SANE 機器は、別に入れる [`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane) が担当します。

プラグインは、Windows がすでに備えているドライバー経由でスキャナーと通信します。同じ PC に VueScan や SilverFast を入れたままにできます。

## 問題が起きたとき

アプリはテキストのログを `%LOCALAPPDATA%\Negaflow\Logs` に書きます。

| ファイル | 記録する内容 |
|---|---|
| `export-trace.txt` | 書き出しとクイック書き出し（失敗を含む） |
| `termination.txt` | アプリを閉じる間に起きたこと |
| `settings-change.txt` | 変わった設定と、変えたもの |

この3つは常に有効です。次の2つは初期状態で無効です。

- `preview-trace.txt`: 同じフォルダーに空のファイル `preview-trace.on` を作ると有効になります。
- `stage-trace.txt`: アプリを起動する前に環境変数 `NEGAFLOW_STAGE_TRACE=1` を設定します。現像の各段階でピクセルの統計を記録します。

## 構成

```
negaflow-windows/
├── src/
│   ├── Native/        Chroma Engine、GrainMend、デコードと書き出し (C++)
│   ├── Interop/       エンジンとアプリの間の層 (C#)
│   ├── Catalog.Core/  ライブラリの保存 (C#)
│   ├── Shell.Core/    現像、プリント、書き出しのロジック (C#)
│   ├── Shell/         ライブラリ、現像、プリントの画面 (WinUI 3)
│   └── Cli/           エンジン確認ツール (C++)
├── scripts/           ビルド、テスト、パッケージングのスクリプト
├── tests/             エンジン、アプリ、境界のテスト
└── Installer/windows/ NSIS インストーラー
```

## 関連ドキュメント

- [両バージョンの違い](../../docs/ja/platform/PLATFORM_DIFFERENCES.md)
- [Chroma Engine](../../docs/ja/product/CHROMA_ENGINE.md)
- [GrainMend](../../docs/ja/product/GRAINMEND.md)
- [製品構造](../../docs/ja/architecture/PRODUCT_ARCHITECTURE.md)
