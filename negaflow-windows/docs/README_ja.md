<p align="center">
  <img src="../../negaflow-mac/Sources/negaflowApp/Resources/AppIcon-1024.png" width="128" alt="negaflow">
</p>

<h1 align="center">negaflow for Windows</h1>

<p align="center">Windows ネイティブで作った negaflow です。</p>

<p align="center">
  <a href="#"><img src="https://img.shields.io/badge/version-1.1.0-EF8B26" alt="バージョン 1.1.0"></a>
  <a href="#"><img src="https://img.shields.io/badge/Windows-11-0078D4?logo=windows&logoColor=white" alt="Windows 11"></a>
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

## 必要なもの

動かすとき:

- Windows 11 (ビルド 26100 以降)、64ビット
- 35mm ならメモリ 8GB、中判を扱うなら 16GB が楽です

ビルドするとき:

- Visual Studio 2022、C++ によるデスクトップ開発のワークロード
- Windows 11 SDK (10.0.26100 以降)
- .NET 10 SDK
- CMake 3.28 以降
- アイコンとリソースのスクリプト用に Python 3.11 以降

Arm64 の機械でも動きます。ただし Arm64 のリリースは x64 ほど確認できていません。

## インストール

[Releases](https://github.com/habinsong/negaflow/releases) から
`negaflow-1.1.0-x64-setup.exe` をダウンロードして実行します。

管理者権限は要りません。初回実行時に SmartScreen が一度警告するので、詳細情報を押して
実行してください。

削除はスタートメニューの `negaflow の削除` か設定のアプリ一覧から行います。
ライブラリと写真はそのまま残ります。

## ビルド

```powershell
git clone https://github.com/habinsong/negaflow.git
cd negaflow\negaflow-windows

# C++ エンジンのビルド
.\scripts\build.ps1 -Preset x64-release

# アプリをビルドして起動
.\scripts\run-app.ps1 -Architecture x64 -Configuration Release
```

`build.ps1` には `x64-debug`、`x64-release`、`arm64-debug`、`arm64-release` を渡せます。

開発中にアプリを起動する方法は `run-app.ps1` だけです。アプリが MSIX パッケージとして
ビルドされるため、ビルドフォルダーの exe をそのまま実行しても起動しません。このスクリプトが
パッケージを作り、現在のユーザーに登録し、アプリ ID で起動します。インストーラがやることから
インストールの部分を抜いたものと同じです。

インストーラを作るとき:

```powershell
.\scripts\build-release.ps1 -Architecture x64
```

結果は `out\release\win-x64` にできます。

## 点検

```powershell
# C++ エンジンのテスト
ctest --preset x64-release --output-on-failure

# アプリとカタログのテスト
.\scripts\test-managed.ps1

# エンジンとアプリの境界のテスト
.\scripts\test-interop.ps1

# 上をまとめて
.\scripts\local-ci.ps1
```

エンジンのテストには基準画像の比較が入っています。macOS 版で書き出した参照ファイルを読み、
Windows のエンジンが同じ画素を出すか確かめます。

## コマンドラインでのエンジン確認

`negaflow-cli.exe` は、ファイル一つをエンジンがどう扱うか見る小さな道具です。日常の作業では
なく動作の確認のために作ったので、サブコマンドではなくフラグを取ります。

```powershell
$cli = "out\build\native\x64-release\Release\negaflow-cli.exe"

# このビルドが何か
& $cli --build-info

# スキャンに何が入っているか見る
& $cli --probe-tiff scan.tif

# 現像して 16bit TIFF に保存
& $cli --export-developed-tiff16 scan.tif out.tif

# 現像一回でどこに時間がかかるか
& $cli --develop-timing scan.tif

# フィルムベースを自動で探して、何を選んだか見る
& $cli --auto-base-probe scan.tif
```

引数なしで実行すると一覧が出ます。

## スキャナー

プラグインを入れるまでスキャナーの操作は現れません。SANE 機器は Windows でも
[`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane) が担当し、
別途インストールが必要です。

プラグインは Windows がもともと用意しているドライバー経路でスキャナーと通信します。
そのため同じ機械で VueScan や SilverFast をそのまま使えます。

## うまくいかないとき

アプリは `%LOCALAPPDATA%\Negaflow\Logs` にテキストの記録を残します。

| ファイル | 記録する内容 |
|---|---|
| `export-trace.txt` | 書き出しとクイック書き出し、失敗した場合を含む |
| `termination.txt` | アプリを閉じるあいだに起きたこと |
| `settings-change.txt` | 変わった設定と、変えたもの |

この三つは常に有効です。問題を知らせていただくとき、たいていどれかに原因が出ています。

特定の問題を追うときだけ有効にする記録が二つあります。

- `preview-trace.txt`。同じフォルダーに `preview-trace.on` という空のファイルを作ると有効になります。
- `stage-trace.txt`。起動前に環境変数 `NEGAFLOW_STAGE_TRACE=1` を置くと有効になります。
  現像の各段階で画素の統計を残すので、プレビューと書き出しがどこで食い違ったかを探すのに使います。

## フォルダー構成

```
negaflow-windows/
├── src/
│   ├── Native/        Chroma Engine、GrainMend、デコードと書き出し (C++)
│   ├── Interop/       エンジンとアプリをつなぐ層 (C#)
│   ├── Catalog.Core/  ライブラリの保存 (C#)
│   ├── Shell.Core/    現像、プリント、書き出しのロジック (C#)
│   ├── Shell/         ライブラリ、現像、プリントの画面 (WinUI 3)
│   └── Cli/           エンジン点検の道具 (C++)
├── scripts/           ビルド、テスト、パッケージのスクリプト
├── tests/             エンジン、アプリ、境界のテスト
└── Installer/windows/ NSIS のインストーラ
```

## 関連ドキュメント

- [二つの版の違い](../../docs/ja/platform/PLATFORM_DIFFERENCES.md)
- [Chroma Engine](../../docs/ja/product/CHROMA_ENGINE.md)
- [GrainMend](../../docs/ja/product/GRAINMEND.md)
- [製品構成](../../docs/ja/architecture/PRODUCT_ARCHITECTURE.md)
