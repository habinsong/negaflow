# 目录存储结构

[文档首页](../README.md)

主存储是 `library.sqlite`。旧的 `library.json` 只用来导入旧目录或写诊断文件。没有任何地方同时更新两者，所以也没有 dual-write。备份和保存归档使用可移植的 JSON，不包含正在运行的 SQLite 文件。

| 类别 | 格式 | 用途 |
|---|---|---|
| 主目录 | SQLite | 运行应用、搜索、保存、恢复 |
| 旧资料 | JSON | 导入已有目录 |
| 备份和保存归档 | JSON 形式 | 迁移到另一台电脑、恢复 |

> [!IMPORTANT]
> 目录缺失或损坏时，不会以空图库启动。在找到完好的世代之前，原目录和照片文件都不会被改动。

## 实测

在同一台 Mac 上用下面的命令比较了 JSON 和 SQLite。

<details>
<summary>测量命令</summary>

```bash
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
- SQLite C API 随 macOS 提供，无需新增软件包。
- 恢复规则保持不变：损坏的存储不会被当作空图库。

当前使用 `journal_mode=DELETE` 和 `synchronous=FULL`。改用 WAL，就要把数据库和 `-wal` 文件当作一个整体处理。运行中的数据库不会被直接复制，只有连接关闭后通过检查的主文件才会成为恢复副本。

## 代码中的分工

- `CatalogStore`：连接、事务、架构版本、完整性检查
- `CatalogMigration`：只读的 JSON 导入和按版本转换
- 实体表：画幅、原始文件、排序、卷、文件夹、收藏集、搜索、扫描任务
- `LibraryBackupStore`：可移植的 JSON 备份、恢复前检查、恢复信息

显影值和带版本的编辑历史按实体存为 JSON BLOB。源像素、缩略图和 GrainMend 缓存不放进数据库。用于搜索和排序的列与索引还不够，所以启动时会把整个目录加载进内存，因此目前 SQLite 的读取时间和 JSON 相近。下一步是用索引查找，只读用到的列和画幅。

## 迁移旧 JSON

1. 检查 JSON 版本和 `LibraryCatalogHealth`。
2. 创建临时 SQLite。
3. 在一个事务里迁移资料。
4. 对比 ID、顺序、归属和任务。
5. 检查 `integrity_check` 和安全条件。
6. 把 JSON 保留为恢复世代。
7. 切换到 SQLite 作为主存储。

任何一步失败，现有 JSON 都保持原样，也不会以空目录启动。即使中间文件和标记被遗留，也只有在源文件 SHA-256 与两个目录都一致时才继续工作。迁移后不会自动回退到 JSON。为了防止旧版应用修改 JSON 而把存储分成两份，会检查最低读取版本和迁移标记。

## 来源

- [Apple: Tuning for Performance and Responsiveness](https://developer.apple.com/library/archive/documentation/General/Conceptual/MOSXAppProgrammingGuide/Performance/Performance.html)
- [Apple: Reducing disk writes](https://developer.apple.com/documentation/xcode/reducing-disk-writes)
- [SQLite: Atomic Commit](https://sqlite.org/atomiccommit.html)
- [SQLite: Write-Ahead Logging](https://sqlite.org/wal.html)
