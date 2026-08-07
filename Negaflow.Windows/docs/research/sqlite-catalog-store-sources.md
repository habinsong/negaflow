# SQLite catalog store 공식 근거와 권리 조사

기준일: 2026-08-07

## 저장소 기준 구현

같은 Apache-2.0 저장소에서 다음 source를 **읽어서** 저장 의미를 확인했습니다.

- `Sources/negaflowApp/Services/Storage/Catalog/SQLite/LibraryCatalogSQLiteStore.swift`
- `Sources/negaflowApp/Services/Storage/Catalog/SQLite/LibraryCatalogSQLiteMigration.swift`
- `Sources/negaflowApp/Services/Storage/Catalog/IO/LibraryCatalogFile.swift`
- `windows_docs/14-persistence/catalog-and-storage.md`

확인한 사실은 다음과 같습니다.

1. metadata table 하나와 entity table 9개이며 각 entity row는 `id` / `position` / `payload`입니다.
2. `position INTEGER NOT NULL UNIQUE CHECK (position >= 0)`가 배열 순서를 보존합니다.
3. payload는 key를 정렬한 JSON blob이고 저장소는 그 안을 해석하지 않습니다.
4. PRAGMA 기준선은 `journal_mode=DELETE`, `synchronous=FULL`, `foreign_keys=ON`입니다.
5. 물리 schema는 `PRAGMA user_version`, 논리 catalog version은 metadata 행에 따로 있습니다.
6. 읽기는 `PRAGMA integrity_check`를 먼저 통과해야 하고, 실패는 빈 catalog가 아니라 거부입니다.

Windows 구현은 이 **의미**를 C#으로 다시 썼습니다. Swift 코드나 그 SQL 생성 로직을 옮겨 적지
않았고, `Microsoft.Data.Sqlite`나 SQLitePCLRaw의 내부 코드도 복사하지 않았습니다. 오류 분류
(`CatalogStoreError`), row 재배치, 스냅숏 모델은 Windows 쪽에서 새로 설계한 것입니다.

## 공식 기술 근거

- [SQLite: PRAGMA statements](https://sqlite.org/pragma.html) — `user_version`, `journal_mode`,
  `synchronous`, `integrity_check`, `foreign_keys`의 정의. `synchronous=EXTRA`가 DELETE 모드에서
  journal 삭제 후 디렉터리까지 sync한다는 점도 여기서 확인했고, 지금은 macOS 기준선을 유지하기 위해
  채택하지 않았습니다.
- [SQLite: UPSERT](https://sqlite.org/lang_upsert.html) — `ON CONFLICT ... DO UPDATE`가 지정한
  uniqueness 제약에 대해서만 동작하며, **다른** unique index를 어기면 그대로 제약 위반이라는 점.
  이번 재배치 단계가 필요한 이유가 여기서 나옵니다.
- [SQLAlchemy: Ordering List](https://docs.sqlalchemy.org/en/21/orm/extensions/orderinglist.html) —
  순서 컬럼에 unique 제약이 걸리면 두 행이 값을 맞바꿀 수 없고 최소한 한 행을 먼저 비워야 한다는
  같은 문제를 다른 생태계에서 문서화한 사례. 독립 확인용으로만 읽었고 코드는 참고하지 않았습니다.
- [Microsoft: Custom SQLite versions](https://learn.microsoft.com/en-us/dotnet/standard/data/sqlite/custom-versions) —
  `Microsoft.Data.Sqlite.Core`에 원하는 bundle/provider를 직접 붙이는 것이 지원되는 구성이라는 근거.
- [Brice Lambson: Microsoft.Data.Sqlite 6](https://www.bricelam.net/2021/11/08/microsoft-data-sqlite-6.html) —
  6.0부터 native 연결이 기본으로 pool되며 닫은 뒤에도 파일이 잠길 수 있고, `Pooling=False` 또는
  `ClearPool`로 푼다는 설명. `Pooling=False` 선택의 근거입니다.
- [SQLitePCLRaw v3 변경 안내](https://github.com/ericsink/SQLitePCL.raw/blob/main/v3.md) — native
  라이브러리 패키지가 `SQLitePCLRaw.lib.e_sqlite3`에서 `SourceGear.sqlite3`로 바뀌었고,
  native 의존성이 없는 `config.e_sqlite3`가 추가됐다는 1차 근거.

## 보안 근거

- [GHSA-2m69-gcr7-jv3q / CVE-2025-6965](https://github.com/advisories/GHSA-2m69-gcr7-jv3q) —
  `SQLitePCLRaw.lib.e_sqlite3` ≤ 2.1.11 영향, CVSS 7.2 High, 2.x 계열 수정 릴리스 없음. 근본
  결함은 SQLite 3.50.2 미만의 aggregate term 처리이며 메모리 손상으로 이어질 수 있습니다.
  고정한 `SourceGear.sqlite3` 3.53.4는 이보다 한참 위입니다.

## 라이선스 검토

| 구성요소 | 라이선스 | Apache-2.0 제품과의 관계 |
|---|---|---|
| SQLite 자체 | public domain | 의무 없음 |
| `SourceGear.sqlite3` | Apache-2.0 | 양립. 4(a) 라이선스 사본, 4(d) NOTICE 재현 |
| `SQLitePCLRaw.core` / `.provider.e_sqlite3` / `.config.e_sqlite3` | Apache-2.0 | 같음 |
| `Microsoft.Data.Sqlite.Core` | MIT | 양립. 라이선스·저작권 고지 동봉 |

[SQLite 저작권 페이지](https://sqlite.org/copyright.html)는 코드와 문서 전부가 public domain으로
헌정됐고 사용에 라이선스가 필요 없음을 명시합니다. 따라서 Apache-2.0 의무는 SQLite가 아니라
**SourceGear의 패키징**에서 나옵니다. 이 구분을 고지 문서에 그대로 적었습니다.

copyleft는 없습니다. 이 스택 어디에도 GPL/LGPL 구성요소가 들어오지 않으므로 ADR-0006의 SANE
플러그인 격리와 같은 프로세스 분리가 필요하지 않습니다.

`SQLitePCLRaw.bundle_winsqlite3`는 검토 후 배제했습니다. 라이선스 문제가 아니라 지원 문제입니다.
Microsoft는 `winsqlite3.dll`을 Windows 구성요소와 Microsoft 앱을 위한 시스템 라이브러리로 규정하고
Windows Update로만 갱신하며 제3자 빌드로 교체하지 말 것을 안내합니다. 제3자 앱이 제품 데이터베이스를
얹는 용도로 지원되는 API가 아닙니다.

## 제한형 공개 특허 검색

"sqlite catalog schema versioning", "ordered list position column unique constraint database",
"photo library catalog sqlite single writer" 범위에서 공개 검색을 했습니다. 이번 구현이 쓰는
요소는 전부 오래된 공지 기술입니다.

- 정수 순서 컬럼으로 리스트 순서를 보존하는 것
- 재배치 시 충돌을 피하려 임시 범위로 옮겼다 되돌리는 것
- schema version을 데이터베이스 안에 두고 열 때 검사하는 것
- 단일 작성자 잠금과 commit 후 무결성 재확인

특정 특허를 회피하기 위한 설계 변경은 하지 않았고, 그럴 필요를 보여 주는 자료도 찾지 못했습니다.
**이 검색은 법률 자문이나 freedom-to-operate 보증이 아닙니다.** 배포 전 검토가 필요하면 별도
절차로 진행해야 합니다.

## 참고하지 않은 것

경쟁·유사 제품의 카탈로그 스키마(Lightroom Classic의 `.lrcat`, darktable의 `library.db`,
digiKam의 `digikam4.db`)를 열어 보거나 구조를 옮기지 않았습니다. 이번 스키마는 이 저장소 자신의
macOS 구현에서 왔습니다.
