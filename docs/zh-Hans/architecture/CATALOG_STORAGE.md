# 目录存储结构

[文档首页](../README.md)

主存储是 `library.sqlite`。旧的 `library.json` 只用来导入旧目录；此外，诊断功能写的是脱敏后的支持包，不是 `library.json`。同时，没有任何地方同时更新两者，所以也没有 dual-write。其中，macOS 的备份和 BagIt 归档使用可移植 JSON（`version 7`），不包含正在运行的 SQLite 文件。而 Windows 使用自己的架构版本（`version 2`），把 `library.sqlite` 打包进 ZIP 格式的 `.negaflowarchive`，因此备份在同一平台的机器之间迁移。

| 类别 | 格式 | 用途 |
|---|---|---|
| 主目录 | SQLite | 运行应用、搜索、保存、恢复 |
| 旧资料 | JSON | 导入已有目录 |
| 备份和保存归档 | 可移植 JSON（`version 7`，macOS）/ 含 `library.sqlite` 的 ZIP（`version 2`，Windows） | 同平台跨机迁移、恢复 |

> [!IMPORTANT]
> 目录缺失或损坏时，不会以空图库启动。在找到完好的世代之前，原目录和照片文件都不会被改动。

## 实测

在同一台 Mac 上，在 `negaflow-mac/` 目录下用下面的命令比较了 JSON 和 SQLite。

<details>
<summary>测量命令</summary>

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

2026-07-12 测量：Mac14,3、arm64、8 核、24 GiB、macOS 26.5、Swift Release 构建。这些数字是该环境下的回归基线，不能预测其他 Mac 的性能。

| 画幅数 | JSON 大小 | Encode p50 | Decode p50 | File read p50 |
|---:|---:|---:|---:|---:|
| 1,000 | 2,192,671 bytes | 98 ms | 241 ms | 231 ms |
| 10,000 | 21,934,841 bytes | 811 ms | 2,301 ms | 2,299 ms |
| 50,000 | 109,721,335 bytes | 2,746 ms | 7,353 ms | 7,397 ms |

把 50,000 个画幅编码成 JSON，常驻内存增加约 191 MiB，最大 RSS 增加约 107 MiB。在同一批数据上，准备内存搜索用时 32.86 ms，对全部名称排序 86.01 ms，筛选后对名称排序 158.37 ms。连续四次筛选投影的 p50 为 512.80 ms。

50,000 个画幅时 SQLite 行存储的 Release p95：

| 操作 | p95 |
|---|---:|
| 新提交 | 3,714 ms |
| 读取主文件 | 7,446 ms |
| 无改动的提交 | 3,856 ms |
| 每个画幅的大小 | ≈ 4,211 bytes |

备份不会把整个数据库读进 `Data`，而是做一个支持复制的临时副本，再原子替换。备份前的检查也不解码每个画幅，只检查 SQLite 完整性和架构，使无改动提交的 p95 从 11,245 ms 降到 3,856 ms。

## 为什么用 SQLite

- 大量行的改动可以放进一个事务。
- 借助行和索引，只读需要的画幅。
- macOS 自带 SQLite C API，无需新增软件包；Windows 使用 `Microsoft.Data.Sqlite`。
- 恢复规则保持不变：损坏的存储不会被当作空图库。

当前使用 `journal_mode=DELETE` 和 `synchronous=FULL`。改用 WAL，就要把数据库和 `-wal` 文件当作一个整体处理。运行中的数据库不会被直接复制，只有连接关闭后通过检查的主文件才会成为恢复副本。

## 代码中的分工

- `LibraryCatalogSQLiteStore`（Windows：`SqliteCatalogStore` 和 `SqliteCatalogSchema`）：连接、事务、架构版本、完整性检查
- `LibraryCatalogSQLiteMigration` 和 `LibraryCatalogFile`（Windows：`CatalogVersionMigration`）：只读的旧版 JSON 导入和按版本升级
- 实体表：`catalog_metadata` 加上 9 张实体表（`folders`、内嵌原始文件引用的 `frames`、`rolls`、`scan_sessions`、`scan_roll_assignments`、`manual_collections`、`smart_collections`、`saved_searches`、`stacks`），按各表的 `position` 列排序
- `LibraryBackupStore`（Windows：`CatalogBackupStore`）：备份和恢复

显影值和带版本的编辑历史按实体存为 JSON BLOB。源像素、缩略图和 GrainMend 缓存不放进数据库。用于搜索和排序的列与索引还不够，所以启动时会把整个目录加载进内存，因此目前 SQLite 的读取时间和 JSON 相近。下一步是用索引查找，只读用到的列和画幅。

## 迁移旧 JSON

1. 检查 JSON 版本和 `LibraryCatalogHealthInspector`。
2. 创建临时 SQLite。
3. 在一个事务里迁移资料。
4. 对比 ID、顺序、归属和任务。
5. 检查 `integrity_check` 和安全条件。
6. 把 JSON 保留为恢复世代。
7. 切换到 SQLite 作为主存储。

任何一步失败，现有 JSON 都保持原样，也不会以空目录启动。`library.sqlite-migration.json` 只在迁移进行时存在，用于在中断后继续迁移，且只在源文件 SHA-256 与两个目录都一致时才恢复，迁移完成后即删除。完成后，`library.json` 会移至 `library.pre-sqlite-<sha12>.json`，且不会自动回退到 JSON。`minimumReaderVersion` 用于阻止旧版本构建打开更新的目录。

## 来源

- [Apple: Tuning for Performance and Responsiveness](https://developer.apple.com/library/archive/documentation/General/Conceptual/MOSXAppProgrammingGuide/Performance/Performance.html)
- [Apple: Reducing disk writes](https://developer.apple.com/documentation/xcode/reducing-disk-writes)
- [SQLite: Atomic Commit](https://sqlite.org/atomiccommit.html)
- [SQLite: Write-Ahead Logging](https://sqlite.org/wal.html)
