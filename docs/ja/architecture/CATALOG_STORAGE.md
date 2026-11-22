# カタログ保存構造

[ドキュメントホーム](../README.md)

主な保存先は `library.sqlite` です。旧来の `library.json` は古いカタログの取り込みにだけ使います。また、診断機能は `library.json` ではなく、機密情報を伏せたサポートバンドルを書き出します。さらに、両方を同時に更新する箇所はないので、dual-write もありません。macOS のバックアップと BagIt アーカイブは持ち運べる JSON（`version 7`）を使い、実行中の SQLite ファイルは含みません。一方、Windows は独自のスキーマ（`version 2`）を使い、`library.sqlite` を ZIP 形式の `.negaflowarchive` にまとめるため、バックアップは同じプラットフォームのマシン間で移行します。

| 種類 | 形式 | 用途 |
|---|---|---|
| 主カタログ | SQLite | アプリの実行、検索、保存、復旧 |
| 旧来の資料 | JSON | 既存カタログの取り込み |
| バックアップと保存アーカイブ | 持ち運べる JSON（`version 7`、macOS）/ `library.sqlite` を含む ZIP（`version 2`、Windows） | 同じプラットフォームの別マシンへの移行、復元 |

> [!IMPORTANT]
> カタログがない、または壊れているからといって、空のライブラリで始めることはありません。正常な世代が見つかるまで、元のカタログと写真ファイルには触れません。

## 実測

同じ Mac で、`negaflow-mac/` から次のコマンドを実行して JSON と SQLite を比べました。

<details>
<summary>測定コマンド</summary>

```bash
cd negaflow-mac

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  NEGAFLOW_CATALOG_PERF_REPORT="$PWD/build/performance/catalog.json" \
  bash scripts/performance/run-catalog.sh

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  NEGAFLOW_LIBRARY_QUERY_PERF_REPORT="$PWD/build/performance/library-query.json" \
  bash scripts/run-library-query-performance.sh

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  NEGAFLOW_SQLITE_CATALOG_PERF_REPORT="$PWD/build/performance/catalog-sqlite.json" \
  bash scripts/performance/run-sqlite-catalog.sh
```

</details>

2026-07-12 の測定: Mac14,3、arm64、8コア、24GiB、macOS 26.5、Swift Release ビルド。数値は同じ環境での回帰の基準線で、ほかの Mac の性能を予測するものではありません。

| フレーム数 | JSON サイズ | Encode p50 | Decode p50 | File read p50 |
|---:|---:|---:|---:|---:|
| 1,000 | 2,192,671 bytes | 98 ms | 241 ms | 231 ms |
| 10,000 | 21,934,841 bytes | 811 ms | 2,301 ms | 2,299 ms |
| 50,000 | 109,721,335 bytes | 2,746 ms | 7,353 ms | 7,397 ms |

50,000フレームを JSON にエンコードすると、常駐メモリが約191MiB、最大 RSS が約107MiB増えました。同じ資料で、メモリ検索の準備は32.86ms、全名前のソートは86.01ms、フィルター後の名前のソートは158.37msでした。フィルターの射影を4回続けたときの p50 は512.80msでした。

50,000フレームでの SQLite 行ストアの Release p95 です。

| 操作 | p95 |
|---|---:|
| 新規コミット | 3,714 ms |
| 主ファイルの読み込み | 7,446 ms |
| 変更なしのコミット | 3,856 ms |
| 1フレームあたりのサイズ | ≈ 4,211 bytes |

バックアップはデータベース全体を `Data` に読み込みません。複製に対応した一時コピーを作り、アトミックに入れ替えます。バックアップ前の検査も、全フレームをデコードする代わりに SQLite の整合性とスキーマを確かめるので、変更なしのコミットの p95 が11,245msから3,856msに縮みました。

## SQLite を使う理由

- 多くの行の変更を1つのトランザクションに収められます。
- 行とインデックスで、必要なフレームだけを読めます。
- macOS では SQLite の C API が OS に含まれるため新しいパッケージは不要で、Windows では `Microsoft.Data.Sqlite` を使います。
- 復旧の規則がそのまま保たれます。壊れた保存先を空のライブラリとして扱うことはありません。

`journal_mode=DELETE` と `synchronous=FULL` で動いています。WAL にすると、データベースと `-wal` ファイルを1つの単位として扱う必要があります。実行中のデータベースは直接コピーしません。接続を閉じた後に検査を通った主ファイルだけが復旧用のコピーになります。

## コードの役割分担

- `LibraryCatalogSQLiteStore`（Windows: `SqliteCatalogStore`、`SqliteCatalogSchema`）: 接続、トランザクション、スキーマのバージョン、整合性検査
- `LibraryCatalogSQLiteMigration`、`LibraryCatalogFile`（Windows: `CatalogVersionMigration`）: 読み取り専用の旧 JSON 取り込みとバージョンごとのアップグレード
- エンティティのテーブル: `catalog_metadata` と 9 つのエンティティテーブル（`folders`、元ファイル参照を埋め込んだ `frames`、`rolls`、`scan_sessions`、`scan_roll_assignments`、`manual_collections`、`smart_collections`、`saved_searches`、`stacks`）。各テーブルの `position` 列で並び替え
- `LibraryBackupStore`（Windows: `CatalogBackupStore`）: バックアップと復元

現像値とバージョン付きの編集履歴は、エンティティごとに JSON BLOB として保存します。元のピクセル、サムネイル、GrainMend キャッシュはデータベースに入れません。検索と並べ替えに使う列とインデックスがまだ足りないため、起動時にカタログ全体をメモリに読み込み、そのため SQLite の読み込み時間は今のところ JSON と同程度です。次の段階は、使う列とフレームだけを読むインデックス検索です。

## 旧来の JSON を移す

1. JSON のバージョンと `LibraryCatalogHealthInspector` を確かめます。
2. 一時的な SQLite を作ります。
3. 資料を1つのトランザクションで移します。
4. ID、順序、所属、ジョブを比べます。
5. `integrity_check` と安全条件を確かめます。
6. JSON を復旧用の世代として残します。
7. SQLite を主な保存先に切り替えます。

どの段階で失敗しても、既存の JSON はそのまま残り、空のカタログで始めることはありません。また、`library.sqlite-migration.json` は移行の実行中に中断から再開するためだけに存在し、完了すると削除されます。その再開も元の SHA-256 と両方のカタログが一致したときに限られます。その後、完了すると `library.json` は `library.pre-sqlite-<sha12>.json` に移動され、JSON へ自動で戻ることはありません。さらに、`minimumReaderVersion` により、古いビルドが新しいカタログを開くのを防ぎます。

## 出典

- [Apple: Tuning for Performance and Responsiveness](https://developer.apple.com/library/archive/documentation/General/Conceptual/MOSXAppProgrammingGuide/Performance/Performance.html)
- [Apple: Reducing disk writes](https://developer.apple.com/documentation/xcode/reducing-disk-writes)
- [SQLite: Atomic Commit](https://sqlite.org/atomiccommit.html)
- [SQLite: Write-Ahead Logging](https://sqlite.org/wal.html)
