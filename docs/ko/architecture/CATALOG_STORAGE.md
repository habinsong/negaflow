# 카탈로그 저장 구조

[문서 홈](../README.md)

주 저장소는 `library.sqlite`입니다. 이전의 `library.json`은 옛 카탈로그를 가져올 때만 사용하며 진단은 `library.json` 대신 민감 정보를 가린 지원 번들을 내보냅니다. 저장소 갱신은 항상 SQLite 한 곳에서만 일어나므로 dual-write도 생기지 않습니다.

macOS 백업과 BagIt 아카이브는 이식 가능한 JSON(`version 7`)을 기록하고 실행 중인 SQLite 파일은 제외하는 반면 Windows는 자체 스키마(`version 2`)로 `library.sqlite`를 ZIP `.negaflowarchive` 안에 보관합니다. 따라서 백업은 각 운영체제끼리만 옮길 수 있습니다.

| 종류 | 형식 | 용도 |
|---|---|---|
| 주 카탈로그 | SQLite | 앱 실행과 검색, 저장과 복구 |
| 이전 자료 | JSON | 기존 카탈로그 가져오기 |
| 백업과 보존 아카이브 | 이식 가능한 JSON(`version 7`, macOS) / `library.sqlite` 포함 ZIP(`version 2`, Windows) | macOS끼리나 Windows끼리 다른 컴퓨터로 옮기기, 복원 |

> [!IMPORTANT]
> 카탈로그가 없거나 손상되면 빈 라이브러리로 시작하는 대신 복구 절차로 들어갑니다. 정상 백업본을 찾을 때까지 원래 카탈로그와 사진 파일은 그대로 보존합니다.

## 실측

한 Mac의 `negaflow-mac/` 폴더에서 아래 명령을 실행해 JSON과 SQLite를 비교했습니다.

<details>
<summary>측정 명령</summary>

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

2026-07-12에 Mac14,3(arm64 8코어와 24GiB 메모리)의 macOS 26.5 환경에서 Swift Release 빌드로 측정한 결과이며, 이 기록은 이 환경에서 회귀를 확인하는 비교 대상으로만 활용합니다.

| 프레임 | JSON 크기 | Encode p50 | Decode p50 | File read p50 |
|---:|---:|---:|---:|---:|
| 1,000 | 2,192,671 bytes | 98 ms | 241 ms | 231 ms |
| 10,000 | 21,934,841 bytes | 811 ms | 2,301 ms | 2,299 ms |
| 50,000 | 109,721,335 bytes | 2,746 ms | 7,353 ms | 7,397 ms |

50,000프레임을 JSON으로 인코딩하자 상주 메모리가 약 191MiB, 최대 RSS가 약 107MiB 늘어났습니다. 이 자료에서 메모리 검색 준비는 32.86ms, 전체 프레임의 이름 정렬은 86.01ms, 필터 뒤 이름 정렬은 158.37ms가 걸렸고 필터 투영 네 번 연속의 p50은 512.80ms로 나타납니다.

50,000프레임에서 SQLite 행 저장소의 Release p95입니다.

| 작업 | p95 |
|---|---:|
| 새 커밋 | 3,714 ms |
| 주 파일 읽기 | 7,446 ms |
| 변경 없는 커밋 | 3,856 ms |
| 프레임당 크기 | ≈ 4,211 bytes |

백업할 때는 데이터베이스 파일을 메모리의 `Data`로 읽어 들이는 대신 복제를 지원하는 임시 복사본을 먼저 만든 뒤 한 번에 교체합니다. 또한 백업 전 검사도 프레임을 일일이 디코딩하는 대신 SQLite 무결성과 스키마만 확인하므로 변경 없는 커밋의 p95가 11,245ms에서 3,856ms로 줄어듭니다.

## SQLite를 택한 이유

- 행을 많이 바꿔도 한 번의 트랜잭션으로 처리됩니다.
- 행과 인덱스로 필요한 프레임만 읽을 수 있습니다.
- macOS에서는 SQLite C API가 운영체제에 들어 있어서 새 패키지가 필요 없고, Windows에서는 `Microsoft.Data.Sqlite`를 사용합니다.
- 손상된 저장소를 빈 라이브러리로 덮어쓰는 일 없이 기존 복구 규칙을 그대로 지킵니다.

저장소는 `journal_mode=DELETE`와 `synchronous=FULL`로 동작하는데, WAL 모드를 켜면 데이터베이스와 `-wal` 파일을 항상 함께 복사해야 하기 때문입니다. 따라서 실행 중인 데이터베이스는 바로 복사하는 대신 연결을 닫고 무결성 검사를 통과한 주 파일만 복구용 복사본으로 삼습니다.

## 코드의 역할 분담

- `LibraryCatalogSQLiteStore`(Windows: `SqliteCatalogStore`, `SqliteCatalogSchema`): 연결과 트랜잭션, 스키마 버전, 무결성 검사
- `LibraryCatalogSQLiteMigration`, `LibraryCatalogFile`(Windows: `CatalogVersionMigration`): 읽기 전용 이전 JSON 가져오기와 버전별 업그레이드
- 엔티티 테이블: `catalog_metadata`와 엔티티 테이블 9개(`folders`, 원본 참조를 내장한 `frames`, `rolls`, `scan_sessions`, `scan_roll_assignments`, `manual_collections`, `smart_collections`, `saved_searches`, `stacks`). 각 테이블의 `position` 열로 정렬
- `LibraryBackupStore`(Windows: `CatalogBackupStore`): 백업과 복원

현상 설정과 버전별 편집 기록은 엔티티마다 JSON BLOB으로 저장하며 원본 픽셀이나 썸네일과 GrainMend 캐시는 데이터베이스 밖의 파일로 분리합니다. 아직은 검색과 정렬에 필요한 열과 인덱스가 충분하지 않아 앱을 시작할 때 카탈로그를 모두 메모리에 올리므로 SQLite 읽기 시간이 JSON과 비슷하게 걸립니다. 이후에는 필요한 열과 프레임만 인덱스로 조회하도록 바꿀 예정입니다.

## 이전 JSON 옮기기

1. JSON 버전과 `LibraryCatalogHealthInspector`를 점검합니다.
2. 임시 SQLite를 만듭니다.
3. 자료를 한 번의 트랜잭션으로 옮깁니다.
4. ID와 순서, 소속, 작업 내역을 대조합니다.
5. `integrity_check`와 안전 조건이 맞는지 살핍니다.
6. 기존 JSON을 복구용 사본으로 보관합니다.
7. SQLite를 주 저장소로 바꿉니다.

어느 단계에서든 실패하면 기존 JSON을 그대로 유지한 채 초기화를 멈춥니다. 이전이 진행되는 동안에는 작업을 다시 시작할 수 있도록 `library.sqlite-migration.json`을 임시로 만들었다가 완료 즉시 지우며 재개 시점에도 원본 SHA-256과 양쪽 데이터가 일치하는지 먼저 확인합니다.

이전을 마치면 `library.json`은 `library.pre-sqlite-<sha12>.json`으로 이름을 바꿔 보관하고 이후에는 SQLite만 사용하며 구버전 빌드가 새 저장소를 열려고 하면 `minimumReaderVersion` 검사로 막습니다.

## 출처

- [Apple: Tuning for Performance and Responsiveness](https://developer.apple.com/library/archive/documentation/General/Conceptual/MOSXAppProgrammingGuide/Performance/Performance.html)
- [Apple: Reducing disk writes](https://developer.apple.com/documentation/xcode/reducing-disk-writes)
- [SQLite: Atomic Commit](https://sqlite.org/atomiccommit.html)
- [SQLite: Write-Ahead Logging](https://sqlite.org/wal.html)
