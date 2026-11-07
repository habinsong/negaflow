# 카탈로그 저장 구조

[문서 홈](../README.md)

주 저장소는 `library.sqlite`입니다. 이전의 `library.json`은 옛 카탈로그를 가져오거나 진단 파일을 쓸 때만 씁니다. 둘을 동시에 갱신하는 곳은 없으므로 dual-write도 없습니다. 백업과 보존 아카이브는 이식 가능한 JSON을 쓰고 실행 중인 SQLite 파일은 담지 않습니다.

| 종류 | 형식 | 용도 |
|---|---|---|
| 주 카탈로그 | SQLite | 앱 실행, 검색, 저장, 복구 |
| 이전 자료 | JSON | 기존 카탈로그 가져오기 |
| 백업과 보존 아카이브 | JSON 형태 | 다른 컴퓨터로 옮기기, 복원 |

> [!IMPORTANT]
> 카탈로그가 없거나 손상됐다고 빈 라이브러리로 시작하지 않습니다. 정상 세대를 찾을 때까지 원래 카탈로그와 사진 파일은 건드리지 않습니다.

## 실측

같은 Mac에서 아래 명령으로 JSON과 SQLite를 비교했습니다.

<details>
<summary>측정 명령</summary>

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

2026-07-12 측정: Mac14,3, arm64, 8코어, 24GiB, macOS 26.5, Swift Release 빌드. 이 수치는 같은 환경의 회귀 기준선이며 다른 Mac의 성능을 예측하지 않습니다.

| 프레임 | JSON 크기 | Encode p50 | Decode p50 | File read p50 |
|---:|---:|---:|---:|---:|
| 1,000 | 2,192,671 bytes | 98 ms | 241 ms | 231 ms |
| 10,000 | 21,934,841 bytes | 811 ms | 2,301 ms | 2,299 ms |
| 50,000 | 109,721,335 bytes | 2,746 ms | 7,353 ms | 7,397 ms |

50,000프레임을 JSON으로 인코딩하자 상주 메모리가 약 191MiB, 최대 RSS가 약 107MiB 늘었습니다. 같은 자료에서 메모리 검색 준비는 32.86ms, 전체 이름 정렬은 86.01ms, 필터 뒤 이름 정렬은 158.37ms 걸렸습니다. 필터 투영 네 번 연속의 p50은 512.80ms였습니다.

50,000프레임에서 SQLite 행 저장소의 Release p95입니다.

| 작업 | p95 |
|---|---:|
| 새 커밋 | 3,714 ms |
| 주 파일 읽기 | 7,446 ms |
| 변경 없는 커밋 | 3,856 ms |
| 프레임당 크기 | ≈ 4,211 bytes |

백업은 데이터베이스 전체를 `Data`로 끌어오지 않습니다. 복제를 지원하는 임시 복사본을 만들어 원자적으로 바꿉니다. 백업 전 검사도 프레임을 모두 디코딩하는 대신 SQLite 무결성과 스키마를 확인하며, 이 덕에 변경 없는 커밋의 p95가 11,245ms에서 3,856ms로 줄었습니다.

## SQLite를 쓰는 이유

- 행을 많이 바꿔도 트랜잭션 하나에 담깁니다.
- 행과 인덱스로 필요한 프레임만 읽을 수 있습니다.
- SQLite C API는 macOS에 들어 있어서 새 패키지가 필요 없습니다.
- 복구 규칙이 그대로 유지됩니다. 손상된 저장소를 빈 라이브러리로 취급하지 않습니다.

`journal_mode=DELETE`와 `synchronous=FULL`로 동작합니다. WAL을 쓰면 데이터베이스와 `-wal` 파일을 한 덩어리로 다뤄야 합니다. 실행 중인 데이터베이스는 그대로 복사하지 않습니다. 연결을 닫은 뒤 검사를 통과한 주 파일만 복구용 복사본이 됩니다.

## 코드의 역할 분담

- `CatalogStore`: 연결, 트랜잭션, 스키마 버전, 무결성 검사
- `CatalogMigration`: 읽기 전용 JSON 가져오기와 버전별 변환
- 엔티티 테이블: 프레임, 원본, 순서, 롤, 폴더, 컬렉션, 검색, 스캔 작업
- `LibraryBackupStore`: 이식 가능한 JSON 백업, 복원 사전 검사, 복구 정보

현상 값과 버전이 있는 편집 기록은 엔티티마다 JSON BLOB으로 저장합니다. 원본 픽셀, 썸네일, GrainMend 캐시는 데이터베이스에 넣지 않습니다. 검색과 정렬에 쓸 열과 인덱스가 아직 부족해서 시작할 때 카탈로그 전체를 메모리에 올리고, 그래서 SQLite 읽기 시간이 지금은 JSON과 비슷합니다. 다음 단계는 쓰는 열과 프레임만 읽는 인덱스 조회입니다.

## 이전 JSON 옮기기

1. JSON 버전과 `LibraryCatalogHealth`를 확인합니다.
2. 임시 SQLite를 만듭니다.
3. 자료를 트랜잭션 하나로 옮깁니다.
4. ID, 순서, 소속, 작업을 비교합니다.
5. `integrity_check`와 안전 조건을 확인합니다.
6. JSON을 복구 세대로 남깁니다.
7. SQLite를 주 저장소로 바꿉니다.

어느 단계든 실패하면 기존 JSON은 그대로 남고 빈 카탈로그로 시작하지 않습니다. 중간 파일과 표식이 남아 있어도 원본 SHA-256과 두 카탈로그가 일치할 때만 작업을 이어 갑니다. 이전 뒤에는 JSON으로 자동 복귀하지 않습니다. 옛 앱이 JSON을 고쳐 저장소가 둘로 갈라지지 않도록 최소 읽기 버전과 이전 표식을 확인합니다.

## 출처

- [Apple: Tuning for Performance and Responsiveness](https://developer.apple.com/library/archive/documentation/General/Conceptual/MOSXAppProgrammingGuide/Performance/Performance.html)
- [Apple: Reducing disk writes](https://developer.apple.com/documentation/xcode/reducing-disk-writes)
- [SQLite: Atomic Commit](https://sqlite.org/atomiccommit.html)
- [SQLite: Write-Ahead Logging](https://sqlite.org/wal.html)
