# negaflow ドキュメント

必要なドキュメントからすぐ開けるよう、内容ごとに分けています。

[English](../README.md) · [한국어](../ko/README.md) · 日本語 · [简体中文](../zh-Hans/README.md) · [Français](../fr/README.md) · [Deutsch](../de/README.md)

> [!NOTE]
> negaflow 1.2.6 は macOS と Windows で動きます。二つのアプリは別々に作られていて、同じファイルからは同じ絵になります。

## プラットフォーム

| ドキュメント | 見るとき |
|---|---|
| [macOS 版と Windows 版の違い](platform/PLATFORM_DIFFERENCES.md) | 両方で同じところと違うところを知りたいとき |
| [macOS のドキュメント](../../negaflow-mac/docs/README_ja.md) | macOS でインストール、ビルド、CLI の利用をするとき |
| [Windows のドキュメント](../../negaflow-windows/docs/README_ja.md) | Windows でインストール、ビルド、エンジン確認をするとき |

## 製品

| ドキュメント | 読むとき |
|---|---|
| [ライブラリからプリントまで](product/WORKFLOW.md) | 読み込み、フォルダー現像、コピー・ペースト、プリントの動作が必要なとき |
| [Chroma Engine](product/CHROMA_ENGINE.md) | フィルム反転と現像の順序を知りたいとき |
| [GrainMend](product/GRAINMEND.md) | ゴミとキズの修復の仕組みを見たいとき |
| [フィルムプロファイル](product/FILM_PROFILES.md) | 同梱プロファイルの出どころと限界を知りたいとき |

## 構造

| ドキュメント | 使うとき |
|---|---|
| [製品構造](architecture/PRODUCT_ARCHITECTURE.md) | アプリ、エンジン、保存、書き出しの間のデータの流れ |
| [カタログ保存構造](architecture/CATALOG_STORAGE.md) | SQLite カタログ、旧 JSON カタログの取り込み、実測 |
| [スキャナープラグイン構造](architecture/SCANNER_PLUGINS.md) | 外部プロセス、承認、スキャンファイルの公開 |
| [ライブラリ保存アーカイブ](architecture/LIBRARY_ARCHIVE.md) | 元ファイルと編集記録をまとめて保存する仕組み |

## 規格

| ドキュメント | 内容 |
|---|---|
| [スキャナーCLI JSON](reference/CLI_JSON.md) | `detect --json` と `capabilities --json` の出力 |
| [レンダー記録](reference/RENDER_MANIFEST.md) | 元ファイル、編集値、出力ファイルをつなぐ SHA-256 |
| [プリントレイアウトとC-printプレビュー](reference/C_PRINT.md) | 8種類のレイアウト、完成ページの書き出し、確認専用 ICC、精度の限界 |
| [ネガ反転応答](reference/PRINT_RESPONSE.md) | `shoulder-print-response-v4` の式と基準点 |
| [スキャナープロファイル品質判定](reference/PROFILE_QUALITY_GATE.md) | REAL/TARGET ペア資料のリリース基準 |
| [スキャナーノイズプロファイル](reference/SCANNER_NOISE_PROFILES.md) | 反復スキャンの測定と適用条件 |
| [GrainMend IRが避けるフィルム](reference/INFRARED_LIMITS.md) | 白黒、コダクローム、RGB/IR 位置合わせの限界 |
| [フラットベッドの自動フレーム検出がフィルムを見つける仕組み](reference/FRAME_DETECTION.md) | フィルムと空ホルダーの区別、コマ境界 |
| [IT8色検査](reference/IT8_COLOR_VALIDATION.md) | パッチ測定、証拠の等級、合成回帰 |

## 出所と配布

| ドキュメント | 内容 |
|---|---|
| [コードとリソースの出どころ](legal/PROVENANCE.md) | Apache/GPL の境界と同梱リソースのハッシュを確認するとき |
| [`TRADEMARKS.md`](../../TRADEMARKS.md) | フィルム、スキャナー、製品名の使い方を確認するとき |

## 書き方

- 製品ドキュメントには、いまユーザーが目にするものだけを書きます。
- 構造ドキュメントには、責務とデータの流れを書きます。
- リファレンスのコード値、フィールド名、ハッシュはそのまま残します。
- 検証ドキュメントは、通ったものと未確認のものを分けます。
- ある言語にある節は、6言語すべてにあります。
