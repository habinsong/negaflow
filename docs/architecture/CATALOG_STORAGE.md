# Catalog storage

[Docs home](../README.md)

The main store is `library.sqlite`. The older `library.json` is used only to import an older catalog; diagnostics write redacted support bundles rather than `library.json`. Nothing updates both at once, so there is no dual-write. On macOS, backups and BagIt archives use portable JSON (`version 7`) and exclude the running SQLite file. On Windows, the catalog uses schema `version 2` and packs `library.sqlite` into a ZIP `.negaflowarchive`, so backups move between machines on the same platform.

| Kind | Format | Used for |
|---|---|---|
| Main catalog | SQLite | Running the app, search, save, recovery |
| Older material | JSON | Importing an existing catalog |
| Backup and preservation archive | Portable JSON (`version 7`, macOS) or ZIP with `library.sqlite` (`version 2`, Windows) | Moving between machines on the same platform, restoring |

> [!IMPORTANT]
> A missing or damaged catalog does not start an empty library. The original catalog and the photo files stay untouched until a healthy generation is found.

## Measurements

JSON and SQLite were compared on the same Mac with these commands, run from `negaflow-mac/`.

<details>
<summary>Measurement commands</summary>

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

Measured on 2026-07-12: Mac14,3, arm64, 8 cores, 24 GiB, macOS 26.5, Swift Release build. The numbers are a regression baseline for that setup, not a prediction for another Mac.

| Frames | JSON size | Encode p50 | Decode p50 | File read p50 |
|---:|---:|---:|---:|---:|
| 1,000 | 2,192,671 bytes | 98 ms | 241 ms | 231 ms |
| 10,000 | 21,934,841 bytes | 811 ms | 2,301 ms | 2,299 ms |
| 50,000 | 109,721,335 bytes | 2,746 ms | 7,353 ms | 7,397 ms |

Encoding 50,000 frames to JSON raised resident memory by about 191 MiB and max RSS by about 107 MiB. On the same material, preparing the in-memory search took 32.86 ms, sorting all names 86.01 ms and sorting names after a filter 158.37 ms. Four filter projections in a row had a p50 of 512.80 ms.

The SQLite row store at 50,000 frames, Release p95:

| Operation | p95 |
|---|---:|
| New commit | 3,714 ms |
| Reading the main file | 7,446 ms |
| Commit with no changes | 3,856 ms |
| Size per frame | ≈ 4,211 bytes |

A backup does not pull the whole database into `Data`. It makes a temporary replicated copy and swaps it atomically. The pre-backup check verifies SQLite integrity and the schema instead of decoding every frame, which cut the p95 of a commit with no changes from 11,245 ms to 3,856 ms.

## Why SQLite

- Many row changes fit in one transaction.
- Rows and indexes let it read only the frames it needs.
- On macOS, the SQLite C API ships with the OS, so no new package is needed; Windows uses `Microsoft.Data.Sqlite`.
- The recovery rule survives: a damaged store is never treated as an empty library.

It runs with `journal_mode=DELETE` and `synchronous=FULL`. WAL would mean handling the database and the `-wal` file as one unit. The running database is not copied directly. Only the main file, checked after the connection closes, becomes a recovery copy.

## Who does what in the code

- `LibraryCatalogSQLiteStore` (Windows: `SqliteCatalogStore` and `SqliteCatalogSchema`): connection, transactions, schema version, integrity checks
- `LibraryCatalogSQLiteMigration` and `LibraryCatalogFile` (Windows: `CatalogVersionMigration`): read-only legacy JSON import and per-version upgrades
- Entity tables: `catalog_metadata` plus 9 entity tables (`folders`, `frames` with embedded original references, `rolls`, `scan_sessions`, `scan_roll_assignments`, `manual_collections`, `smart_collections`, `saved_searches`, `stacks`), ordered by each table's `position` column
- `LibraryBackupStore` (Windows: `CatalogBackupStore`): backups and restores

Develop values and versioned edit history are stored as a JSON BLOB per entity. Source pixels, thumbnails and GrainMend caches stay out of the database. Search and sorting still lack columns and indexes, so the whole catalog loads into memory at startup, and SQLite read time therefore looks like JSON. The next step is index lookups that read only the columns and frames in use.

## Moving older JSON across

1. Check the JSON version and `LibraryCatalogHealthInspector`.
2. Create a temporary SQLite.
3. Move the material in one transaction.
4. Compare IDs, order, membership and jobs.
5. Check `integrity_check` and the safety conditions.
6. Keep the JSON as a recovery generation.
7. Switch to SQLite as the main store.

If any step fails, the existing JSON stays as it is and an empty catalog is never started. The marker `library.sqlite-migration.json` exists only while migration is running so an interrupted move can resume when the source SHA-256 and both catalogs agree, and it is deleted on completion. Once finished, `library.json` is moved to `library.pre-sqlite-<sha12>.json` and there is no automatic fallback to JSON. Checking `minimumReaderVersion` prevents older builds from opening newer catalogs.

## Sources

- [Apple: Tuning for Performance and Responsiveness](https://developer.apple.com/library/archive/documentation/General/Conceptual/MOSXAppProgrammingGuide/Performance/Performance.html)
- [Apple: Reducing disk writes](https://developer.apple.com/documentation/xcode/reducing-disk-writes)
- [SQLite: Atomic Commit](https://sqlite.org/atomiccommit.html)
- [SQLite: Write-Ahead Logging](https://sqlite.org/wal.html)
