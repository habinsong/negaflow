# ADR-0025: catalog SQLite는 관리 계층의 Microsoft.Data.Sqlite.Core로 열고 native SQLite 버전을 따로 고정한다

- 상태: 채택
- 날짜: 2026-08-07

## 문제

`Catalog.Core/Storage/`에 경로 해석(`StorageRootResolver`)과 단일 작성자 lock(`CatalogProcessLock`)까지
올라와 있으나 SQLite 자체가 없어 카탈로그가 저장되지 않습니다. 코드를 쓰기 전에 **어떤 SQLite를 쓸
것인가**를 정해야 합니다.

macOS는 OS가 `libsqlite3`를 공개 API로 제공하지만 Windows에는 앱이 쓸 수 있는 시스템 SQLite가
없습니다. `winsqlite3.dll`이 존재하나 Microsoft는 이를 Windows 구성요소와 Microsoft 앱을 위한 시스템
라이브러리로 규정하며, 제3자 빌드로 교체하지 말 것과 Windows Update로만 갱신될 것을 명시합니다.
서드파티 앱이 직접 링크하는 용도로 지원되는 API가 아닙니다.

동시에 이 저장소에는 **"제3자 runtime dependency 0개"** 기준이 있고, 그 범위가 문서상 애매하게 남아
있어 패키지를 하나 더할 때마다 같은 논쟁이 반복될 상태였습니다.

## 결정

### 1. `Microsoft.Data.Sqlite.Core` + `SQLitePCLRaw.config.e_sqlite3` + `SourceGear.sqlite3`

카탈로그는 관리 코드(`Negaflow.Catalog.Core`, C#)에 살고 `Storage/`도 C#입니다. 네이티브에 SQLite를
넣으면 C#이 자체 C ABI를 한 겹 더 타야 하고 ADR-0017의 vendoring 금지도 건드려야 하므로 배제합니다.
`winsqlite3.dll`도 배제합니다. 미지원 API 위에 제품 데이터베이스를 얹지 않습니다.

**편의 패키지 `Microsoft.Data.Sqlite`는 쓰지 않습니다.** 그 패키지는 native SQLite 하한을
`SQLitePCLRaw.lib.e_sqlite3` 2.1.11로 끌어오는데, 이 패키지는 **CVE-2025-6965(GHSA-2m69-gcr7-jv3q,
CVSS 7.2 High)** 대상이며 2.x 계열에 수정 릴리스가 없습니다. 실제로 그대로 참조하면 `NU1903`이
떠서 이 저장소의 `TreatWarningsAsErrors` 설정에서 restore가 실패합니다. 추측이 아니라 restore
출력으로 확인한 사실입니다.

SQLitePCLRaw 3.0에서 native 라이브러리 패키지는 `SQLitePCLRaw.lib.e_sqlite3`에서
`SourceGear.sqlite3`로 바뀌었고, native 의존성이 없는 `SQLitePCLRaw.config.e_sqlite3`가 새로
생겼습니다. 유지보수자가 권하는 형태가 바로 이 둘을 나눠 참조하는 것이며, 그러면 **SQLite 자체의
버전을 다른 것을 건드리지 않고 올릴 수 있습니다.** 보안 갱신이 잦은 구성요소에 이 성질이 중요합니다.

고정된 집합:

| 패키지 | 버전 | 라이선스 | 역할 |
|---|---|---|---|
| `Microsoft.Data.Sqlite.Core` | 10.0.10 | MIT | ADO.NET 표면 |
| `SQLitePCLRaw.config.e_sqlite3` | 3.0.5 | Apache-2.0 | provider 초기화 |
| `SQLitePCLRaw.provider.e_sqlite3` | 3.0.5 | Apache-2.0 | P/Invoke 계층 (transitive) |
| `SQLitePCLRaw.core` | 3.0.5 | Apache-2.0 | 공통 core (transitive) |
| `SourceGear.sqlite3` | 3.53.4 | Apache-2.0 | native `e_sqlite3.dll` |

전부 Apache-2.0과 양립합니다. SQLite 자체는 public domain입니다.

**한때 "MIT 한 절만 추가하면 된다"고 적혀 있었으나 사실이 아닙니다.** 실제 사슬은 MIT 하나와
Apache-2.0 넷이며, notice 의무는 Apache-2.0 쪽에서 나옵니다.

### 2. "제3자 의존성 0개"는 네이티브 엔진에만 적용된다

`Negaflow.Native.dll`과 `negaflow-cli.exe`는 Windows 기본 DLL(`kernel32`, `bcrypt`, `mscms`, `ole32`,
`shlwapi`) 외에 아무것도 링크하지 않습니다. **이 기준은 유지합니다.**

관리 계층에는 적용되지 않습니다. 셸은 이미 WinUI와 Windows App SDK 위에서 돕니다.

**다만 정직하게 적습니다.** 이 결정으로 배포 payload에 제3자 **native** 바이너리
(`runtimes/win-x64/native/e_sqlite3.dll`, `runtimes/win-arm64/native/e_sqlite3.dll`)가 처음으로
들어옵니다. 네이티브 엔진의 0개는 그대로지만 **제품 payload의 0개는 더 이상 아닙니다.** 이 구분을
흐리면 THIRD-PARTY-NOTICES와 SBOM이 실제 payload와 어긋납니다.

### 3. 물리 schema와 논리 catalog version을 분리한다

- 물리 schema version: `PRAGMA user_version`, 현재 **1**
- 논리 catalog version: `catalog_metadata.catalog_version`, Windows는 현재 **1**

두 축을 합치면 payload migration과 물리 schema migration을 독립적으로 판단할 수 없습니다.

**Windows 논리 version은 macOS의 6과 같은 번호 공간이 아닙니다.** 결정 4(카탈로그 스키마를 macOS와
공유하지 않음)에 따라 두 플랫폼이 같은 파일을 여는 것은 제품 요구가 아니므로, macOS 파일(6)은
Windows에서 `UnsupportedCatalogVersion`으로 **관측값과 함께** 거부됩니다. 조용히 읽거나 빈
라이브러리로 해석하지 않습니다. 반대 방향도 macOS 쪽에서 `.invalid`로 막힙니다. 양쪽 다
fail-closed입니다.

Windows가 전체 v6 payload parity를 갖추지 못한 상태에서 6을 선언하면 갖지 않은 호환을 주장하게
되므로 그렇게 하지 않습니다.

### 4. table 배치는 macOS 것을 그대로 옮긴다

`catalog_metadata` 하나와 entity table 9개(`folders`, `frames`, `rolls`, `scan_sessions`,
`scan_roll_assignments`, `manual_collections`, `smart_collections`, `saved_searches`, `stacks`)입니다.
각 entity row는 `id TEXT PRIMARY KEY`, `position INTEGER NOT NULL UNIQUE CHECK (position >= 0)`,
`payload BLOB NOT NULL`이고 payload는 key를 ordinal 정렬한 JSON입니다.

정규화된 관계형 모델로 재설계하지 않습니다. 저장소는 **payload 안을 해석하지 않습니다.** payload
계약은 `Catalog.Core/Recipes`가 계속 소유합니다.

table 이름은 `CatalogEntityTable` enum에서만 나옵니다. 호출자가 준 문자열이 SQL로 흘러가지 않습니다.

### 5. 자리를 바꾸는 row는 upsert 전에 먼저 옮긴다

`position`이 UNIQUE이므로, 살아남은 row가 아직 차지하고 있는 자리로 다른 row를 upsert하면 그
transaction이 `SQLITE_CONSTRAINT`로 중단됩니다. 따라서 한 transaction 안에서

1. 더 이상 필요 없는 id를 지우고,
2. **자리가 바뀌는 row만** 큰 오프셋(`1 << 40`)만큼 밀어낸 뒤,
3. 최종 position과 payload를 upsert합니다.

자리가 그대로인 row는 건드리지 않으므로 페이지를 다시 쓰지 않습니다. 이것은 이론이 아니라 측정된
것입니다. 2번을 빼면 frame 3개를 `(1,2,3)`에서 `(3,1,2)`로 재정렬하는 것만으로 쓰기가 실패합니다.
`store_reorder_write`가 그 회귀를 잡습니다.

### 6. `journal_mode=DELETE`, `synchronous=FULL`을 유지한다

macOS 기준선 그대로입니다. Windows라고 무조건 WAL로 바꾸지 않습니다. WAL은 로컬 NTFS/ReFS에서
동시 읽기 이득이 실측되고 전원 장애 내구성 시험을 통과할 때만 여는 후보입니다. 지금 이 제품은
단일 작성자이므로 WAL이 푸는 문제를 갖고 있지 않습니다.

`synchronous=EXTRA`도 지금은 쓰지 않습니다. DELETE 모드에서 EXTRA는 journal 삭제 후 디렉터리까지
sync하므로 내구성이 조금 더 높지만, 이는 macOS 기준선에서 벗어나는 변경이고 측정 없이 하지 않습니다.

### 7. connection pooling을 끈다

`Microsoft.Data.Sqlite` 6.0부터 native 연결이 **기본으로 pool**됩니다. 연결을 닫아도 파일 핸들이
남을 수 있습니다. 이 제품은 backup 세대 교체와 pending restore에서 catalog 파일을 치환해야 하므로
남은 핸들이 곧 실패입니다. 따라서 connection string에 `Pooling=False`를 명시합니다.
`store_no_lingering_file_handle`이 이 계약을 지킵니다.

### 8. 카탈로그를 여는 유일한 공개 입구는 `CatalogSession` 이다

`SqliteCatalogStore` 는 `internal` 입니다. lock 을 잡지 않고 카탈로그를 여는 공개 경로가 하나라도
있으면 단일 작성자 계약이 구조가 아니라 호출자의 규율에 의존하게 됩니다. `CatalogSession.Open` 이
프로세스 lock 을 먼저 잡고, 실패하면 세션 자체가 만들어지지 않습니다.

`CatalogSession.ReadOrCreate` 는 **`NotFound` 를 빈 라이브러리로 바꾸는 유일한 자리**입니다. 그
변환이 여러 곳에 흩어지면 손상된 카탈로그가 어딘가에서 빈 라이브러리로 조용히 대체될 수 있습니다.
손상, 알 수 없는 물리 schema, 외부 논리 version 은 `ReadOrCreate` 에서도 그대로 실패입니다.

`CatalogRecovery.IsValidCatalogSource` 만 lock 없이 쓸 수 있습니다. 파일을 열지도 payload 를 읽지도
않고 `integrity_check` 와 두 version 축만 보는 확인이며, 손상된 primary 가 유효한 backup 을 덮지
않게 하는 데 필요합니다.

세션은 SQLite 연결을 계속 붙들지 않습니다. 연산마다 열고 닫으므로 backup 세대 교체와 pending
restore 가 파일을 치환할 수 있습니다. lock 파일만 세션 수명 동안 유지됩니다.

### 9. 없는 파일과 손상된 파일을 구별한다

`NotFound`, `CorruptDatabase`, `UnsupportedStorageVersion`, `UnsupportedCatalogVersion`,
`MalformedContent`를 각각 다른 값으로 돌려줍니다. 어느 것도 빈 라이브러리로 해석하지 않으며 부분
snapshot을 반환하지 않습니다. 읽기는 `PRAGMA integrity_check`를 먼저 통과해야 합니다. 쓰기는 같은
연결의 `integrity_check` 뒤에도 성공을 확정하지 않고, `CatalogSession`의 commit verifier가 새 연결로
9개 table 전체를 다시 읽어 metadata·row 순서·ID·canonical payload가 요청 snapshot과 같을 때만
성공을 보고합니다.

## 결과

카탈로그가 실제로 디스크에 남고, 앱을 껐다 켜도 entity 순서와 payload가 보존됩니다. native SQLite
버전이 다른 패키지와 분리돼 고정되므로 다음 SQLite CVE에 `SourceGear.sqlite3` 한 줄만 올려서
대응할 수 있습니다. 알려진 취약 native 바이너리를 배포하지 않습니다.

대신 배포 payload에 제3자 native DLL이 처음 들어오므로 `THIRD-PARTY-NOTICES.md`와
`components.json`의 `third_party_runtime_dependencies`, 그리고 릴리스 SBOM이 이를 반영해야 합니다.

## 남은 한계

- raw 직전 primary 보존과 verified commit은 구현됐습니다. **immutable logical backup 세대, pending
  restore, legacy migration, defect sidecar는 아직 없습니다.**
- 5만 frame 성능은 측정했으나(`verification/2026-08-07-sqlite-catalog-store.md`) **fault-injection
  검증표는 실행하지 않았습니다.** 쓰기 도중 강제 종료와 전원 장애 시나리오가 남아 있습니다.
- 재저장 비용이 바뀐 양이 아니라 catalog 전체 크기에 비례합니다. 5만 frame 목표에서 1초 미만이라
  지금은 최적화하지 않으며, 재검토 시점은 `progress/next-steps.md`에서 관리합니다.
- lock은 **이 프로세스의 파일 핸들**입니다. 프로세스 경계에서 거부되는 것은 별도 프로세스를 띄워
  확인했지만, 프로세스가 죽으면 핸들이 풀리므로 남은 lock 파일은 소유권을 뜻하지 않습니다.
  크래시 뒤 "누가 잡고 있는가"를 사용자에게 설명하려면 lock 파일에 소유자 정보를 기록하는 별도
  작업이 필요합니다.
- catalog는 C ABI나 WinUI 셸에 아직 연결돼 있지 않습니다.
- `SourceGear.sqlite3`는 모든 플랫폼의 native를 담아 26MB이며, 그중 Windows 두 RID만 출력에
  복사됩니다. restore 비용일 뿐 payload 비용은 아닙니다.
- 제한형 공개 특허·라이선스 검색은 법률 자문이나 freedom-to-operate 보증이 아닙니다.

## 근거

- `windows_docs/14-persistence/catalog-and-storage.md`
- `Sources/negaflowApp/Services/Storage/Catalog/SQLite/LibraryCatalogSQLiteStore.swift` (관측 대상)
- [GitHub Advisory GHSA-2m69-gcr7-jv3q — CVE-2025-6965](https://github.com/advisories/GHSA-2m69-gcr7-jv3q)
- [SQLitePCLRaw 3.0 변경 안내](https://github.com/ericsink/SQLitePCL.raw/blob/main/v3.md)
- [Microsoft: Custom SQLite versions](https://learn.microsoft.com/en-us/dotnet/standard/data/sqlite/custom-versions)
- [Brice Lambson: Microsoft.Data.Sqlite 6 — connection pooling](https://www.bricelam.net/2021/11/08/microsoft-data-sqlite-6.html)
- [SQLite: PRAGMA synchronous / journal_mode](https://sqlite.org/pragma.html)
- [SQLite: UPSERT](https://sqlite.org/lang_upsert.html)

실행 증거는 `verification/2026-08-07-sqlite-catalog-store.md`에 기록합니다.
