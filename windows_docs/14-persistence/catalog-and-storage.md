# 카탈로그·사이드카·백업·저장소 설계

기준일: 2026-08-04  
macOS 기준 커밋: `9be909c`  
Windows 상태: 구현 전 설계 기준

이 문서는 Windows판의 데이터 수명주기와 장애 복구 계약을 정의한다. 단순히 SQLite 파일을
어디에 둘지 정하는 문서가 아니다. 원본, 카탈로그, 결함 recipe, 파생 캐시, export journal,
백업 세대를 서로 다른 권위와 수명으로 분리하고, 어느 하나가 손상됐을 때 다른 데이터를
잘못 지우지 않도록 하는 것이 목적이다.

## 1. 결론

Windows판은 다음 원칙으로 시작한다.

1. 카탈로그는 로컬 SQLite primary 한 개를 앱이 단일 작성자로 소유한다.
2. 현재 macOS 저장소 스키마의 의미와 순서 보존 계약을 그대로 이식한다.
3. 현재 기준선은 `journal_mode=DELETE`, `synchronous=FULL`이다. Windows라고 무조건 WAL로
   바꾸지 않는다.
4. WAL은 로컬 NTFS/ReFS에서 동시 읽기 이득이 실측되고 전원 장애 내구성 시험을 통과할 때만
   채택하는 후보이다.
5. primary catalog를 SMB, NAS, OneDrive 동기화 폴더 또는 다른 cloud placeholder 루트에 두지
   않는다.
6. 결함 sidecar는 authoritative data다. cleaned-raw TIFF와 thumbnail은 재생성 가능한 cache다.
7. 백업 세대는 portable canonical catalog와 그 catalog가 참조하는 authoritative defect
   sidecar를 함께 보관한다.
8. missing, corrupt, future-version catalog를 빈 라이브러리로 해석하지 않는다.
9. 원본과 제3자 XMP는 불변이다. source URL 변경은 명시적 relink 또는 검증된 file identity
   복구에서만 허용한다.
10. scanner plugin은 catalog, defect directory, backup 또는 export journal을 직접 열지 않는다.

## 2. 범위와 비범위

### 이 문서가 소유하는 것

- Windows 저장소 루트와 폴더 구조
- SQLite schema 의미, 연결 및 transaction 규율
- process lock과 단일 작성자 계약
- commit, readback verification, rollback
- legacy migration과 interrupted migration 복구
- authoritative sidecar와 cache의 수명주기
- backup generation 생성·검증·보존·복원
- source identity와 relink
- folder change notification의 제품 의미
- OneDrive, network path, reparse point, package uninstall 위험
- 5만 frame 성능 및 fault-injection 검증표

### 이 문서가 소유하지 않는 것

- 이미지 픽셀 처리 수학
- scanner driver 또는 plugin 내부 저장 형식
- export codec 구현
- installer와 updater의 전체 구현
- cloud library synchronization
- 여러 장치가 하나의 live catalog를 동시에 편집하는 기능

Windows v1은 single-user, single-machine, single-writer local catalog다. cloud sync 또는 shared
network catalog는 기능이 아니라 별도 분산 시스템이므로 암묵적으로 지원하지 않는다.

## 3. 현재 macOS 구현에서 확인한 기준선

아래는 추측이 아니라 현재 소스에 존재하는 계약이다.

### 3.1 저장소 파일

| 역할 | 현재 구현 | Windows 이식 의미 |
|---|---|---|
| storage root | `AppStorageRoot.swift` | 제품·cache root를 한 resolver로 중앙화 |
| primary catalog | `LibraryCatalogFile.defaultURL()`의 `library.sqlite` | 같은 logical catalog와 명시적 schema version |
| SQLite store | `Catalog/SQLite/LibraryCatalogSQLiteStore.swift` | 스키마, transaction, readback 계약 이식 |
| legacy migration | `LibraryCatalogSQLiteMigration.swift` | JSON→SQLite crash-safe migration 이식 |
| commit verification | `LibraryCatalogSQLiteCommitVerifier.swift` | 직전 primary 보존 후 write/readback/rollback |
| process lock | `LibraryProcessLock.swift` | catalog별 단일 작성자 lock |
| defect recipe | `DefectSidecarFile.swift` | frame별 authoritative, versioned sidecar |
| cleaned raw | `CleanedRawCacheFile.swift` | 삭제 가능한 파생 TIFF cache |
| backup | `Backup/LibraryBackupStore*.swift` | portable catalog+defect 세대 |
| pending restore | `PendingRestore/*` | 다음 safe startup에서만 적용 |

### 3.2 현재 경로

macOS 기본 경로는 다음 의미를 갖는다.

```text
Application Support/negaflow/
├── library.sqlite
├── library.backup.sqlite
├── library.sqlite.lock
├── defects/
├── Backups/
└── PendingRestore/

Caches/negaflow/
└── cleaned-raw/
```

정확한 부가 파일은 실행 상태와 migration 여부에 따라 달라질 수 있다. 중요한 점은 catalog와
defect recipe는 Application Support 계열이고 cleaned raw는 Caches 계열이라는 권위 분리다.

### 3.3 현재 catalog version

- logical catalog version: `LibraryCatalog.currentVersion == 6`
- oldest supported reader version: `6`
- SQLite storage schema: `PRAGMA user_version == 1`
- backup manifest current version: `3`
- checksummed backup manifest 시작 version: `2`
- pending restore marker current version: `2`

logical catalog version과 SQLite storage version은 다른 축이다.

- logical version은 frame/roll/search 같은 제품 payload 계약을 나타낸다.
- storage version은 SQLite table/column 배치를 나타낸다.

두 값을 하나로 합치면 payload migration과 physical schema migration을 독립적으로 판단할 수
없으므로 Windows에서도 분리한다.

### 3.4 현재 SQLite table

metadata table:

```sql
CREATE TABLE catalog_metadata (
  singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
  catalog_version INTEGER NOT NULL,
  minimum_reader_version INTEGER NOT NULL,
  active_roll_id TEXT
);
```

entity table:

```sql
CREATE TABLE <entity> (
  id TEXT PRIMARY KEY NOT NULL,
  position INTEGER NOT NULL UNIQUE CHECK (position >= 0),
  payload BLOB NOT NULL
);
```

현재 entity table은 다음 9개다.

1. `folders`
2. `frames`
3. `rolls`
4. `scan_sessions`
5. `scan_roll_assignments`
6. `manual_collections`
7. `smart_collections`
8. `saved_searches`
9. `stacks`

각 payload는 sorted-key JSON blob이며, `position`이 배열 순서를 보존한다. Windows 초기 이식은
이를 정규화된 관계형 모델로 재설계하지 않는다. UI 검색 성능 때문에 index가 필요하다면 먼저
read model 또는 명시적 materialized index를 별도 version으로 제안하고, authoritative payload의
해석을 조용히 바꾸지 않는다.

## 4. 데이터 권위 분류

삭제·백업·복구 정책은 파일 확장자가 아니라 권위로 결정한다.

| 분류 | 예 | 재생성 가능 | 기본 백업 | 자동 삭제 |
|---|---|---:|---:|---:|
| 사용자 원본 | imported scan/photo, scanner raw, IR source | 아니오 | catalog backup과 별도 | 절대 금지 |
| authoritative app data | catalog, defect sidecar | 아니오 | 필수 | 절대 금지 |
| durable workflow state | scan job, export checkpoint/journal | 조건부 | 목적별 | 완료·확인 후만 |
| user output | exported JPEG/TIFF/PNG, print package | 아니오 | 사용자가 관리 | 절대 금지 |
| derived cache | thumbnail, cleaned raw, developed cache | 예 | 제외 | 제한된 정책으로 가능 |
| diagnostics | structured log, crash/support bundle staging | 예 | 제외 | retention 가능 |
| settings | UI preference, Quick Export preset, paths | 일부 | 선택 | reset 동작에서만 |

### 4.1 authoritative defect sidecar

현재 defect recipe는 frame ID별 sidecar로 영속화된다. 낮은 revision의 늦은 write가 높은 revision을
덮지 못하도록 revision-aware writer가 있으며, backup health는 `hasDefectEdits == true`인 모든
frame의 sidecar 존재와 decode 성공을 요구한다.

Windows판도 다음을 지킨다.

- sidecar는 app-owned directory에 둔다.
- frame ID, schema version, recipe revision을 검증한다.
- write는 temp file → flush → atomic replace 순서다.
- 오래된 async completion은 더 높은 revision을 덮지 못한다.
- catalog가 defect edit을 선언했는데 sidecar가 없거나 invalid면 library open을 차단한다.
- missing sidecar를 빈 recipe로 치환하지 않는다.
- source image 또는 제3자 `.xmp` 옆에 자동 생성하지 않는다.

### 4.2 cleaned raw와 thumbnail

cleaned raw는 recipe 결과를 materialize한 cache일 뿐이다. recipe와 source identity가 맞지 않으면
사용하지 않고 재생성한다.

- catalog/sidecar backup에 포함하지 않는다.
- cache clear로 사용자 편집이 없어지면 설계 실패다.
- 파일 이름만 신뢰하지 않고 manifest/source identity/revision을 검증한다.
- cache write 실패는 recipe commit 실패로 승격하지 않는다.
- cache hit가 없어도 같은 품질의 결과를 재구성할 수 있어야 한다.

## 5. Windows 저장소 루트

### 5.1 v1 기본안

v1 배포 기본안은 unpackaged self-contained installer이므로 `FOLDERID_LocalAppData`를 Win32 Known
Folder API로 해석한다. 환경 변수 문자열을 직접 이어 붙이지 않는다. Known Folder는 사용자 또는
관리자 정책으로 redirect될 수 있기 때문이다.

```text
%LOCALAPPDATA%\Negaflow\
├── Library\
│   ├── library.sqlite
│   ├── library.backup.sqlite
│   ├── library.sqlite.lock
│   ├── defects\
│   ├── Backups\
│   ├── PendingRestore\
│   └── Migration\
├── Cache\
│   ├── Thumbnails\
│   ├── CleanedRaw\
│   ├── Develop\
│   └── ScanPreview\
├── Journals\
│   ├── Export\
│   └── SourceMoves\
├── Plugins\
│   ├── Installed\
│   ├── Quarantine\
│   └── State\
├── Logs\
└── Settings\
```

디렉터리 이름의 대소문자는 표시 계약일 뿐이다. 비교와 ownership 검증은 Windows path semantics를
따른다.

### 5.2 사용자 데이터 루트와 내부 루트를 분리한다

설정의 storage 선택은 다음을 바꿀 수 있다.

- scanner가 새 원본을 저장하는 위치
- import-copy가 앱 소유 원본을 저장하는 위치
- export/Quick Export 기본 위치
- cleaned raw cache의 선택적 custom 위치
- 외부 backup 목적지

하지만 primary catalog를 선택한 source/output/cloud 폴더로 옮기지 않는다. catalog는 짧은
transaction과 predictable locking이 필요한 로컬 내부 데이터다. source와 output은 대용량 사용자
파일이며 다른 수명주기를 가진다.

### 5.3 OneDrive를 iCloud의 이름 바꾸기로 취급하지 않는다

Windows Known Folder의 Documents/Pictures가 OneDrive로 redirect될 수 있고 Files On-Demand 파일은
reparse point 또는 placeholder일 수 있다. 따라서 다음 규칙을 적용한다.

- picker가 돌려준 실제 경로와 Known Folder redirect 여부를 표시한다.
- cloud-backed source를 지원하되 open 시 hydration이 발생할 수 있음을 UI에 알린다.
- background enumeration만으로 모든 placeholder를 강제 hydrate하지 않는다.
- export destination이 cloud-backed이면 commit 완료와 cloud upload 완료를 구분한다.
- primary catalog, process lock, live journal을 OneDrive root에 두지 않는다.
- backup 목적지로 OneDrive를 허용하려면 local commit 완료 후 immutable generation을 복사하고
  다시 hash 검증한다. 동기화 완료는 별도 provider 상태이며 backup 생성 성공과 같은 의미가 아니다.

### 5.4 MSIX를 나중에 추가할 때

Microsoft 문서상 app-data 저장소는 앱 제거 수명과 연결된다. Negaflow catalog와 defect recipe는
사용자가 가치 있다고 인식하는 데이터이므로 이를 단순 `ApplicationData.LocalFolder`에 넣고
uninstall 시 삭제되게 해서는 안 된다.

Store/MSIX 채널은 다음 중 하나를 release gate로 확정해야 한다.

1. full-trust packaged app의 unvirtualized durable product root를 사용하고 설치·업데이트·제거를
   실기 검증한다.
2. Windows 11 flexible virtualization의 excluded directory와 필요한 capability 승인을 확인한다.
3. MSIX 전환 전 unpackaged catalog를 새 위치로 안전하게 migrate하고, 제거 전에 외부 archive를
   제공한다.

어느 방식을 택하든 packaged와 unpackaged가 서로 다른 숨은 catalog를 여는 상태는 금지한다.
startup 진단에 deployment identity, resolved catalog root, virtualization state를 path 원문 없이
분류된 형태로 남긴다.

## 6. Path resolver 계약

모든 저장소는 `StorageRootResolver`에 해당하는 단일 서비스에서 경로를 받는다. UI, SQLite,
scanner plugin host, cache writer가 환경 변수를 각각 해석하지 않는다.

resolver 출력에는 최소 다음이 있다.

```text
ProductDataRoot
CatalogUrl
DefectRecipeRoot
BackupRoot
PendingRestoreRoot
CacheRoot
JournalRoot
PluginRoot
LogRoot
SettingsRoot
```

### 6.1 테스트 격리

현재 macOS `AppStorageRoot`처럼 test process는 PID/worker별 임시 root를 주입한다.

- unit/integration test에서 실제 `%LOCALAPPDATA%\Negaflow`를 열지 않는다.
- parallel test worker끼리 catalog, sidecar, cache를 공유하지 않는다.
- test root 주입 중에는 사용자 custom cache/backup 설정을 무시한다.
- test가 만든 root만 test 종료 후 정리한다.
- production root와 동일한 상대 구조와 파일명을 사용한다.

실제 사용자 root를 test fixture로 사용하는 옵션은 만들지 않는다.

### 6.2 path 안전성

파일을 만들거나 교체하기 직전에 다음을 검증한다.

- root가 absolute path인지
- 대상 relative component에 `..`, drive prefix, UNC escape가 없는지
- 예상 parent 아래에 남는지
- existing component가 의도하지 않은 reparse point인지
- regular file/directory인지
- source와 destination이 같은 file identity인지
- temp와 destination이 같은 volume인지

문자열 prefix 비교만으로 containment를 판단하지 않는다. canonicalized path, handle 기반 final path,
file identity를 함께 사용한다. TOCTOU를 줄이기 위해 검증한 handle을 가능한 한 작업에 유지한다.

## 7. SQLite ownership과 API 경계

### 7.1 누가 catalog를 여는가

| 프로세스 | catalog 접근 |
|---|---|
| WinUI shell/domain process | 유일한 read/write owner |
| native render DLL | 접근 금지 |
| CLI | 명시적 offline/diagnostic mode에서만, 같은 lock 획득 |
| scanner plugin | 접근 금지 |
| exporter worker를 별도 프로세스로 만들 경우 | catalog 접근 금지, immutable job payload만 수신 |
| support tool | 기본 read-only, live app과 충돌하면 중단 |

plugin에 catalog 경로를 넘기지 않는다. plugin은 scan request, capability, cancel, progress, artifact
경로만 안다.

### 7.2 managed/native 선택

SQLite provider는 다음 조건을 만족하는 하나만 선택한다.

- x64와 ARM64 native binary를 같은 SQLite source/version/compile options로 만든다.
- `sqlite3_threadsafe`, JSON/blob, backup API, integrity check가 필요한 설정으로 build된다.
- NuGet의 transitive native binary와 vcpkg SQLite가 동시에 로드되지 않는다.
- provider version과 `sqlite3_libversion()`을 support bundle에 기록한다.
- Microsoft Store 또는 installer별 native DLL 탐색이 결정적이다.

C# domain이 persistence orchestration을 소유하더라도 SQLite native handle 수명은 provider 한 곳에
격리한다. C++ render engine에 catalog 책임을 넣지 않는다.

## 8. 연결과 단일 작성자 모델

### 8.1 process lock

앱 startup은 SQLite를 열기 전에 `library.sqlite.lock`을 획득한다.

Windows 구현 후보:

- 별도 lock file을 `CreateFileW`로 열고 다른 writer가 열 수 없는 share mode를 사용하거나,
- 별도 lock file의 고정 byte range를 `LockFileEx(LOCKFILE_EXCLUSIVE_LOCK |
  LOCKFILE_FAIL_IMMEDIATELY)`로 잠근다.

중요한 규칙:

- DB 파일 자체가 아니라 별도 lock file을 잠근다.
- lock ownership은 열린 handle 수명에 묶는다.
- 정상 종료와 crash 후 OS가 handle을 닫으면 lock이 해제되어야 한다.
- lock 파일이 디스크에 남아 있다는 이유로 stale lock이라 판단하지 않는다.
- lock 획득 실패는 read/write를 강행하지 않고 “다른 Negaflow가 이 라이브러리를 사용 중” 상태로
  연다.
- `LockFileEx` byte-range lock은 memory-mapped file access에 적용되지 않으므로 process lock을
  catalog 보안 경계로 오해하지 않는다.

### 8.2 connection model

v1 기본안:

- 하나의 장수명 writer connection
- 필요 시 짧은 read-only connection 또는 writer queue에서 snapshot read
- 모든 mutation은 serial persistence queue로 순서화
- UI model publish는 verified commit 성공 뒤에만 최종 성공으로 확정
- cancellation은 transaction 경계에서만 상태를 되돌림
- busy timeout은 짧고 명시적이며, 무한 재시도하지 않음

다수 connection은 WAL 채택의 전제가 아니다. 먼저 실제 UI read와 background indexing이 같은
writer queue로 충분한지 측정한다.

### 8.3 open flags와 startup check

read-only probe:

- read-only
- full mutex 또는 provider가 보장하는 serialized mode
- file 존재, schema version, metadata version 확인
- `PRAGMA integrity_check` 또는 정의한 startup health tier 실행

writer open:

- read/write/create는 새 library 생성 또는 verified migration에서만 허용
- 기존 파일이 missing일 때 recovery artifact 존재 여부를 먼저 확인
- `foreign_keys=ON`
- 실제 적용된 `journal_mode`, `synchronous`, `user_version`을 읽어 확인

future `user_version`이나 future logical catalog version은 downgrade recovery로 덮지 않는다.

## 9. journal과 durability

### 9.1 기준선

현재 macOS 코드는 write connection마다 다음을 설정한다.

```sql
PRAGMA journal_mode=DELETE;
PRAGMA synchronous=FULL;
PRAGMA foreign_keys=ON;
```

Windows 첫 구현도 이 값을 conformance baseline으로 사용한다. 이유는 다음과 같다.

- 현재 raw primary/rollback copy가 single-file SQLite 상태를 전제로 한다.
- writer가 하나이고 mutation이 직렬화되어 있다.
- FULL durability를 의도적으로 선택한 제품 계약이 이미 있다.
- WAL로 바꾸면 `-wal`, `-shm`, checkpoint, backup, crash recovery 표면이 추가된다.

### 9.2 WAL은 측정 후보

WAL의 장점은 reader와 writer 동시성, 순차 I/O, 적은 sync 호출이다. 그러나 다음 비용이 있다.

- 모든 process가 같은 host에 있어야 하며 network filesystem에서는 동작하지 않는다.
- DB와 함께 `-wal`, `-shm`이 persistent state가 될 수 있다.
- checkpoint 지연과 long reader에 의한 checkpoint starvation을 관리해야 한다.
- read-mostly, write-rare workload에서는 rollback journal보다 약간 느릴 수 있다.
- `synchronous=NORMAL`은 power loss 시 최근 transaction durability를 낮춘다.

따라서 “WAL이면 빠르다” 또는 “NORMAL이면 안전하다”를 문서 기본값으로 두지 않는다.

### 9.3 journal-mode 결정표

| 조건 | 기본 선택 | 이유 |
|---|---|---|
| local NTFS/ReFS, single connection | `DELETE/FULL` | 기준선, 단순한 recovery |
| local NTFS/ReFS, UI read와 writer contention 확인 | WAL spike | concurrency 이득 측정 |
| SMB/NAS/network filesystem | WAL 금지 | shared-memory WAL index 전제 불충족 |
| OneDrive/cloud-sync folder | primary 금지 | placeholder/sync/rename 간섭 |
| removable drive | primary 금지, import/export만 | disconnect와 write caching 위험 |
| read-only portable archive | canonical backup JSON | DB journal 상태를 운반하지 않음 |

### 9.4 WAL 채택 gate

다음을 모두 통과할 때만 decision register를 갱신한다.

1. 5만 frame real-shaped catalog에서 UI p95/p99 stall이 유의미하게 줄어든다.
2. commit throughput뿐 아니라 startup, search, scroll, backup, exit 총시간을 측정한다.
3. x64 Intel/AMD와 ARM64에서 동일 시험을 수행한다.
4. process crash, power-cut harness, disk-full, antivirus/backup scanner 동시 접근을 통과한다.
5. `FULL`과 `NORMAL`을 별도 결과로 보고하고 durability 저하를 성능 수치에 숨기지 않는다.
6. checkpoint duration, busy count, WAL bytes, long reader를 관측할 수 있다.
7. backup과 support tooling이 `-wal` 파일을 빠뜨리지 않는다.

WAL을 채택해도 primary를 network/cloud root로 옮기지 않는다.

### 9.5 검토만 할 PRAGMA

다음 값은 benchmark matrix이지 기본 설정이 아니다.

```sql
PRAGMA cache_size = ...;
PRAGMA mmap_size = ...;
PRAGMA temp_store = ...;
PRAGMA wal_autocheckpoint = ...;
PRAGMA journal_size_limit = ...;
```

- `mmap_size`는 32/64-bit address space, antivirus, file replacement와 함께 잰다.
- `temp_store=MEMORY`는 unbounded memory 사용을 만들지 않는지 확인한다.
- `locking_mode=EXCLUSIVE`는 support/diagnostic read와 충돌하므로 기본값이 아니다.
- hard-coded cache page 수보다 byte budget과 memory pressure 대응을 우선한다.

## 10. write transaction

현재 store의 transaction 구조를 유지한다.

```text
validate in-memory catalog and authoritative recipes
→ acquire persistence queue
→ preserve verified previous primary
→ BEGIN IMMEDIATE
→ upsert metadata
→ synchronize entity rows
→ COMMIT
→ integrity/readback verification
→ mark generation acknowledged
→ publish success
```

### 10.1 row synchronization

현재 구현은 이전 catalog write cache와 새 배열의 count 및 ID 순서가 같으면 변경된 row만 upsert한다.
구조가 바뀌면 desired ID temp table을 만들고 삭제·upsert를 transaction 안에서 처리한다.

Windows 이식 조건:

- `id`, `position`, `payload`의 의미를 유지한다.
- duplicate ID 또는 duplicate position을 commit 전에 거부한다.
- JSON encoding은 ISO 8601 date와 deterministic key ordering을 사용한다.
- prepared statement를 재사용하고 매 row마다 reset/clear/bind한다.
- partial table sync가 transaction 밖으로 새지 않는다.
- write cache는 optimization일 뿐 authoritative source가 아니다.

### 10.2 commit verification

성공은 `sqlite3_step(COMMIT)` 반환만으로 결정하지 않는다.

1. commit 전 catalog health를 검사한다.
2. 직전 valid primary를 rollback artifact로 보존한다.
3. write한다.
4. 한-frame/제한된 변화면 incremental verifier를 사용한다.
5. 그 외에는 전체 readback 후 canonical payload와 health를 비교한다.
6. 검증 실패 시 직전 primary를 원복한다.
7. 원복도 실패하면 `rollbackFailed`로 library mutation을 차단한다.

UI는 6단계까지 성공하기 전에 “저장됨”을 표시하지 않는다.

### 10.3 raw SQLite copy

현재 macOS는 serialized writer와 rollback-journal single-file 상태에서 primary를 복사한다. Windows는
connection이 열린 상태의 일반 파일 복사에 의존하지 않는다.

선택 기준:

- connection을 닫고 journal이 정리된 상태면 `CopyFileEx` + byte comparison을 사용할 수 있다.
- live DB snapshot은 SQLite Online Backup API를 우선 평가한다.
- Online Backup API는 source를 copy 전체 시간 동안 잠그지 않고 단계적으로 consistent snapshot을
  만든다.
- WAL을 채택했다면 main `.sqlite`만 복사하는 경로는 전면 금지한다.

raw rollback artifact와 user backup generation은 다른 목적이다. 전자는 즉시 같은 버전으로
돌아가기 위한 내부 상태이고, 후자는 장기 복구와 portability를 위한 logical snapshot이다.

## 11. startup state machine

```text
resolve roots
→ acquire process lock
→ apply or finish PendingRestore
→ recover interrupted storage migration
→ probe primary catalog
→ validate schema + logical version + integrity + authoritative sidecars
→ if valid: open
→ if recoverable: preserve unsafe state, apply latest valid generation, verify, open
→ if truly new and no artifacts: create new library
→ otherwise: block with recovery UI
```

### 11.1 상태별 동작

| 상태 | 동작 |
|---|---|
| primary valid | 정상 open |
| primary missing, recovery artifact 없음 | 새 library 생성 가능 |
| primary missing, sidecar/backup 존재 | `missingAuthoritativeData`, 자동 새 library 금지 |
| primary corrupt/unreadable | unsafe state 보존 후 valid backup 탐색 |
| logical future version | 차단, 과거 backup으로 자동 downgrade 금지 |
| storage future version | 차단, 파일 보존 |
| defect sidecar missing/invalid | authoritative data missing으로 차단 |
| pending restore scheduled | library UI 전 safe-startup transaction 적용 |
| process lock busy | 두 번째 writer 금지 |

### 11.2 cleanup 금지 조건

catalog open이 완전히 성공하기 전에는 다음을 하지 않는다.

- orphan source 삭제
- orphan sidecar 삭제
- cache와 authoritative data의 연관 정리
- scan job 폐기
- export journal 정리
- empty catalog 저장

“읽지 못했다”는 “비어 있다”가 아니다.

## 12. legacy JSON→SQLite migration

현재 구현의 crash-safe 순서를 이식한다.

1. `library.sqlite`와 migration marker 상태를 검사한다.
2. legacy `library.json`을 decode하고 logical version을 판정한다.
3. catalog health와 authoritative defect sidecar를 검사한다.
4. migration 전 portable backup generation을 만든다.
5. source JSON의 SHA-256을 계산한다.
6. 같은 volume에 temporary SQLite를 만든다.
7. SQLite write 후 전체 readback canonical equality를 검사한다.
8. marker를 atomic write하고 다시 읽어 검증한다.
9. source JSON을 hash가 포함된 preserved 이름으로 이동한다.
10. temporary SQLite를 primary로 승격한다.
11. 다음 startup이 marker와 hash로 중단 지점을 복구할 수 있게 한다.

marker 최소 필드:

```json
{
  "version": 1,
  "sourceSha256": "...",
  "sourceCatalogVersion": 6,
  "sqliteStorageVersion": 1,
  "temporaryDatabaseFileName": ".library-migrating-<uuid>.sqlite",
  "preservedLegacyFileName": "library.pre-sqlite-<hash>.json",
  "createdAt": "..."
}
```

Windows는 `ReplaceFileW` 또는 같은-volume atomic rename 후보를 사용하되, 실제 filesystem별 atomicity와
write-through 동작을 fault test로 검증한다. 단순히 `File.Move(..., overwrite: true)`가 모든 단계의
내구성을 보장한다고 가정하지 않는다.

## 13. backup generation

### 13.1 backup 내용

현재 backup은 live SQLite 파일 자체가 아니라 canonical `library.json`으로 catalog를 내보낸다.
이는 physical schema와 journal mode에 덜 묶이며 macOS와 Windows 간 진단·복구에도 유리하다.

```text
Backups\
└── backup-<20자리 sequence>-<UTC timestamp>-<uuid>\
    ├── manifest.json
    ├── library.json
    └── defects\
        └── <frame-id>.plist
```

Windows판도 v1에서 이 logical generation 형식을 유지한다. plist를 계속 쓸지 platform-neutral
binary/JSON envelope로 바꿀지는 sidecar schema 결정으로 관리하되, 형식 변경은 versioned migration과
dual-reader 기간을 필요로 한다.

### 13.2 manifest

manifest에는 최소 다음이 있다.

- manifest version
- monotonic optional sequence
- UTC created time
- frame count
- defect edit frame ID 목록
- logical catalog version
- 각 authoritative file의 relative path
- byte count
- SHA-256

절대 경로를 manifest key로 사용하지 않는다. path traversal을 막고 generation root 아래의 regular
file만 허용한다. symlink/reparse point는 거부한다.

### 13.3 생성 transaction

```text
read and validate live catalog
→ derive exact defect frame IDs
→ allocate next monotonic sequence
→ create staging-<uuid>.tmp directory
→ write canonical library.json atomically
→ copy validated defect sidecars
→ hash every file
→ write manifest atomically
→ validate entire staging generation
→ rename staging to immutable backup generation
→ prune only validated older generations
```

실패한 staging은 다음 startup에서 식별 가능해야 하며, valid generation과 이름이 겹치지 않는다.
retention prune은 새 generation이 완전히 검증·승격된 뒤에만 실행한다.

### 13.4 검증

restore 가능한 generation은 다음을 모두 만족한다.

- 지원하는 manifest version
- catalog decode와 supported logical version
- manifest frame count와 실제 frame count 일치
- `hasDefectEdits` frame ID 집합과 manifest 집합 일치
- 모든 sidecar decode와 frame ID/revision 계약 통과
- catalog health safe
- manifest file 목록과 실제 허용 파일 목록 일치
- 각 file byte count와 SHA-256 일치
- generation root 밖으로 나가는 link 없음

legacy structure-only generation은 UI에 그 상태를 명시한다. checksummed generation과 같은 증거 수준으로
표현하지 않는다.

### 13.5 backup destination

외부 backup 목적지는 다음 상태를 구분한다.

- not configured
- disconnected
- same volume
- read-only
- insufficient capacity
- ready

“다른 폴더”와 “다른 failure domain”은 다르다. 기본 외부 backup은 source catalog와 다른 volume을
요구한다. volume identity는 drive letter 문자열이 아니라 volume GUID/serial과 handle 정보를
사용한다.

network/cloud destination을 허용하는 경우:

- 먼저 local staging generation을 완성한다.
- destination에 temp 이름으로 copy한다.
- destination에서 byte count/hash를 다시 읽어 검증한다.
- final 이름으로 승격한다.
- 연결 중단 시 기존 valid generation을 삭제하지 않는다.

### 13.6 retention

현재 기본 retention은 3 generation이다. Windows도 초기값 3으로 시작하되, 사용자가 외부 backup
일정을 설정하면 용량 예상치를 보여준다.

prune 규칙:

- sequence가 있으면 sequence가 ordering의 1순위다.
- timestamp와 directory mtime만으로 최신을 결정하지 않는다.
- invalid/damaged generation을 latest valid로 계산하지 않는다.
- future-version generation을 삭제하지 않는다.
- prune failure는 새 valid generation 성공을 되돌리지 않지만 사용자에게 경고한다.

## 14. restore

### 14.1 즉시 live state 위에 덮지 않는다

사용자가 generation을 고르면 현재 세션에서 catalog를 바로 교체하지 않는다.

1. generation을 다시 검증한다.
2. `PendingRestore` 아래 staging에 완전 복사한다.
3. staging을 다시 검증한다.
4. immutable pending directory로 rename한다.
5. atomic pending marker를 기록한다.
6. 재시작 필요 상태를 보여준다.

다음 startup에서 process lock을 획득하고 UI가 catalog를 사용하기 전에 적용한다.

### 14.2 적용 transaction

```text
validate marker and pending generation
→ reject unsupported current future-version catalog
→ preserve current primary + defects as a recovery point
→ prepare replacement defects directory
→ validate replacement catalog against replacement defects
→ swap defects
→ write catalog
→ full readback + canonical + health verification
→ mark restore phase applied
→ cleanup old/pending artifacts
```

중간 실패 시 previous catalog와 previous defects를 함께 복구한다. catalog만 새 세대고 sidecar는 이전
세대인 split-brain 상태를 허용하지 않는다.

cleanup이 실패하면 restore 자체를 다시 적용하지 않고 `applied/cleanupPending` phase에서 정리만
재시도한다.

### 14.3 unsafe state 보존

손상 또는 불완전한 live 상태는 recovery 성공 전에 삭제하지 않는다.

```text
library.corrupt-<uuid>.sqlite
defects.corrupt-<uuid>\
```

사용자에게 자동 복구되었다고 알리되, 보존 artifact 삭제는 지원 번들 생성 가능 기간과 명시적
retention 정책 뒤에 한다.

## 15. source identity와 relink

macOS bookmark는 Windows에 그대로 존재하지 않는다. Windows에서는 path와 handle 기반 identity를
분리한다.

### 15.1 identity 후보

local filesystem의 동일 파일 판정은 `FILE_ID_INFO`의 다음 조합을 우선한다.

- `VolumeSerialNumber`
- 128-bit `FileId`

Microsoft 문서도 두 열린 handle이 같은 파일인지 판단할 때 이 두 값을 함께 비교하도록 한다.

catalog record에는 최소 다음을 versioned field로 둔다.

```text
lastKnownPath
volumeIdentity
fileId128
fileSize
lastWriteTime
optional quick/full content hash
identityCapturedAt
```

file ID 지원은 filesystem별로 다르고 시간이 지나 재사용될 수 있으므로 영구 전역 ID로 과장하지
않는다. network share, cloud placeholder, FAT/exFAT, offline volume에서는 사용할 수 없을 수 있다.

### 15.2 relink 순서

1. last-known path가 열리면 file identity와 source fingerprint를 확인한다.
2. 같은 volume에서 file ID lookup이 가능하면 후보를 찾는다.
3. 파일 크기·metadata·필요 시 content hash로 후보를 검증한다.
4. 자동 확신 기준을 못 넘으면 사용자에게 후보를 보여준다.
5. 사용자가 명시적으로 고른 relink만 다른 픽셀 identity를 허용한다.
6. relink 직전 frame ID와 expected old identity를 다시 검사한다.
7. catalog commit 성공 후에만 UI path를 최종 publish한다.

source relink가 다른 픽셀로 바뀌면 cleaned raw, render manifest, reviewed state 등 source-dependent
derived state를 무효화한다. defect recipe 자체는 보존하되 새 geometry와의 적용 가능성을 검증한다.

### 15.3 virtual copy

virtual copy는 source 파일을 복제하지 않는다.

- root frame과 같은 source identity를 공유한다.
- 독립 develop/defect presentation state를 가질 수 있다.
- source 삭제 판단은 같은 source를 공유하는 전체 family를 고려한다.
- virtual copy 하나 삭제가 physical source 삭제로 이어지지 않는다.
- physical source를 휴지통으로 보내는 동작은 library removal과 별도 confirmation이다.

## 16. folder monitoring

Windows implementation은 `ReadDirectoryChangesW`/`ReadDirectoryChangesExW` 후보를 사용한다. notification은
힌트이지 authoritative event log가 아니다.

- rename pair가 잘리거나 순서가 바뀔 수 있다고 가정한다.
- `ERROR_NOTIFY_ENUM_DIR`이면 subtree를 다시 enumerate하고 catalog와 reconcile한다.
- network path는 buffer와 protocol 제약이 다르므로 별도 시험한다.
- burst event를 debounce하되 최종 reconciliation을 생략하지 않는다.
- change event에서 파일을 즉시 열 수 없으면 bounded retry 후 offline/pending으로 둔다.

제품 규칙:

- 기존 source의 이동·rename·offline 상태를 반영한다.
- 등록 folder에 새 파일이 생겼다는 이유만으로 자동 import하지 않는다.
- 새 파일 import는 사용자의 명시적 refresh/import 동작에서만 수행한다.
- watcher 손실이 catalog 삭제를 유발하지 않는다.

## 17. atomic file operation

SQLite 밖의 marker, sidecar, manifest, settings는 공통 writer를 사용한다.

```text
serialize deterministic payload
→ create random temp in destination directory
→ write all bytes
→ FlushFileBuffers where durability requires it
→ close temp handle
→ ReplaceFileW or verified same-volume rename
→ reopen and validate critical files
```

규칙:

- temp를 `%TEMP%`에 만들고 다른 volume으로 move하지 않는다.
- destination이 symlink/reparse point인지 생성 직전에 다시 확인한다.
- existing ACL을 보존해야 하는 파일은 `ReplaceFileW` semantics를 검토한다.
- write-through flag만으로 directory entry durability가 모든 filesystem에서 같다고 단정하지 않는다.
- antivirus가 file handle을 잠깐 잡는 경우 bounded retry와 정확한 오류를 제공한다.
- 무한 retry 또는 실패 숨김은 금지한다.

## 18. export와 scan journal 연계

catalog transaction과 대형 artifact write를 하나의 SQLite transaction으로 묶지 않는다.

### 18.1 scan publish

```text
plugin writes to host-owned staging path
→ host validates file contract and source metadata
→ move/commit source artifact
→ create/update catalog record
→ commit catalog and sidecar state
→ publish UI success
```

plugin exit success만으로 frame을 catalog에 추가하지 않는다. artifact 검증과 catalog acknowledgement가
필요하다.

### 18.2 export

```text
persist immutable export plan/checkpoint
→ render to staging
→ encode + metadata/ICC validation
→ atomic artifact commit
→ update journal
→ optional catalog acknowledgement
```

앱 crash 후 journal은 incomplete artifact를 안전하게 재시도하거나 사용자에게 보여준다. source가
missing이거나 authoritative recipe를 재구성할 수 없으면 original을 대신 export하지 않고 명시적으로
실패한다.

## 19. 관측성

path 원문과 개인 파일명은 기본 telemetry/support bundle에서 제거하거나 salted hash로 대체한다.

### 19.1 catalog metric

- SQLite version/compile option hash
- storage schema와 logical catalog version
- journal mode와 synchronous mode
- catalog bytes, row count, frame count
- open duration, integrity-check duration
- transaction duration p50/p95/p99
- changed row count와 full-replace table count
- busy/locked/error count
- readback type: incremental/full
- rollback attempt/result

### 19.2 WAL을 채택한 경우 추가 metric

- WAL bytes/pages
- checkpoint attempt/result/duration
- checkpointed/remaining page count
- long-lived reader age
- auto/manual checkpoint 원인

### 19.3 backup/restore metric

- generation sequence와 상태
- catalog/sidecar byte count
- hash duration
- destination class: local/removable/network/cloud
- validation failure category
- restore scheduled/applied/cleanup-pending phase

개별 source path, frame 이름, EXIF, catalog payload는 사용자 동의 없는 진단 로그에 넣지 않는다.

## 20. 성능 목표와 benchmark

정확한 예산은 Windows prototype 측정 뒤 고정하지만, 다음 시나리오는 처음부터 필요하다.

### 20.1 fixture

- empty catalog
- 1천 frame
- 1만 frame
- 5만 frame
- 5만 frame + roll/collection/search/stack 실제 비율
- 5만 frame 중 1 frame edit
- 5만 frame에서 reorder/add/delete 혼합
- defect sidecar 0%, 10%, 100%
- source online/offline/cloud-placeholder 혼합

fixture는 실제 사용자 catalog를 복사하지 않고 deterministic generator로 만든다.

### 20.2 측정 항목

- cold/warm startup
- full catalog decode
- 1-row incremental commit
- reorder transaction
- full canonical readback
- incremental verification
- integrity check
- backup generation creation
- hash throughput
- restore schedule/apply
- Library search/filter/scroll 중 commit stall
- app termination flush
- x64 Intel, x64 AMD, ARM64
- fast NVMe, low-end SSD, nearly-full disk

### 20.3 성공 기준 원칙

- 평균만 보고하지 않고 p95/p99와 worst fixture를 기록한다.
- `synchronous` 또는 품질을 낮춘 결과를 최적화로 계산하지 않는다.
- cache warm 결과만으로 startup을 주장하지 않는다.
- debug build와 release build를 구분한다.
- antivirus exclusion을 켠 수치는 일반 사용자 기준이 아니다.
- journal mode 비교는 같은 durability 수준과 다른 durability 수준을 별도 표로 낸다.

## 21. fault-injection matrix

### 21.1 catalog

- DB header/page truncation
- random page corruption
- `user_version` future/zero/mismatch
- logical version future/mismatch
- duplicate/missing entity payload
- invalid JSON blob
- missing metadata singleton
- `integrity_check` failure
- disk full at BEGIN/mid-write/COMMIT/readback
- process kill at each transaction boundary
- rollback copy failure
- antivirus sharing violation
- second process lock contention

### 21.2 sidecar

- missing file for edited frame
- truncated/oversized payload
- wrong frame ID
- future schema
- stale lower revision completion
- atomic replace failure
- reparse point substitution

### 21.3 migration

- crash before/after backup
- crash during temp DB write
- marker written but temp incomplete
- legacy preserved but SQLite not promoted
- SQLite promoted but marker remains
- hash mismatch
- insufficient disk space

### 21.4 backup/restore

- missing manifest/catalog/sidecar
- wrong byte count/hash
- extra unexpected file
- symlink/reparse point
- sequence overflow/duplicate
- destination disconnect mid-copy
- restore after current catalog became future version
- crash after defect swap but before catalog commit
- crash after apply but before cleanup
- damaged newest generation with older valid generation present

### 21.5 source filesystem

- drive letter change
- volume offline/reconnect
- same path, different file
- same file, renamed path
- hard link and symlink
- OneDrive placeholder not hydrated
- hydration cancellation/failure
- SMB watcher overflow
- source deleted while export is preparing

모든 시험은 “사용자 데이터가 조용히 사라지지 않는다”를 먼저 검증한다. 정상 open 또는 자동 repair가
불가능하면 recovery UI로 차단되는 것이 성공이다.

## 22. 구현 순서

### Phase P0 — 사양 fixture

- logical catalog v6 canonical fixture 고정
- backup manifest v1–v3 fixture 고정
- defect sidecar version fixture 고정
- corrupt/future/missing fixture 고정
- macOS canonical export와 hash 기록

### Phase P1 — roots와 lock

- `FOLDERID_LocalAppData` resolver
- test process isolation
- catalog별 process lock
- reparse/containment helper
- x64/ARM64 path tests

### Phase P2 — SQLite baseline

- schema v1 creation/read
- `DELETE/FULL/foreign_keys=ON`
- deterministic payload encoding
- 9개 entity round trip
- `user_version`/logical version fail-closed

### Phase P3 — verified commit

- serial writer
- previous-primary snapshot
- incremental/full verifier
- rollback
- disk-full/process-kill harness

### Phase P4 — sidecar/cache

- revision-aware authoritative sidecar
- cleaned raw cache manifest
- cache clear/rebuild
- catalog health integration

### Phase P5 — migration와 backup

- JSON→SQLite interrupted migration
- portable generation v3
- external destination validation
- retention
- restore drill

### Phase P6 — source identity

- `FILE_ID_INFO` capture
- path+identity relink
- offline/placeholder state
- watcher reconciliation
- virtual-copy family safety

### Phase P7 — 성능 선택

- 5만 frame baseline
- connection/read model 측정
- WAL spike와 rollback journal 비교
- 채택 또는 제외 decision 갱신

## 23. 완료 gate

- [ ] macOS canonical fixture를 Windows가 동일 logical model로 읽는다.
- [ ] 9개 entity의 ID·position·payload가 round trip된다.
- [ ] missing/corrupt/future catalog가 empty로 열리지 않는다.
- [ ] edited frame의 missing sidecar가 library open을 차단한다.
- [ ] cache 전체 삭제 후 recipe와 source로 같은 결과를 재구성한다.
- [ ] commit readback 실패가 직전 primary를 복구한다.
- [ ] migration 각 crash point에서 legacy 또는 SQLite 중 하나의 valid 세대가 남는다.
- [ ] backup generation의 모든 authoritative file이 checksummed된다.
- [ ] restore는 다음 safe startup에서 catalog+defects를 한 세대로 적용한다.
- [ ] 두 번째 process가 writer lock을 우회하지 못한다.
- [ ] scanner plugin이 catalog path나 DB 권한을 받지 않는다.
- [ ] source relink가 같은-file과 different-file을 구분한다.
- [ ] virtual copy 삭제가 physical source를 지우지 않는다.
- [ ] 5만 frame x64/ARM64 성능 결과가 기록된다.
- [ ] WAL 채택 여부가 같은 durability 조건의 측정으로 결정된다.
- [ ] unpackaged install/update/uninstall이 catalog/backup 보존 정책을 지킨다.
- [ ] future MSIX 채널은 hidden split catalog와 uninstall loss를 실기 검증한다.

## 24. 금지 목록

- `library.sqlite`를 OneDrive/SMB에 놓고 지원한다고 표기
- WAL을 benchmark 없이 기본 활성화
- `synchronous=NORMAL` 성능을 `FULL`과 같은 durability로 표기
- live WAL DB의 main file만 복사
- corrupt catalog를 empty catalog로 저장
- missing sidecar를 empty recipe로 대체
- cleaned raw를 authoritative edit로 취급
- 원본 또는 제3자 XMP 덮어쓰기
- plugin의 catalog 직접 접근
- 문자열 prefix만으로 path containment 확인
- backup을 검증하기 전에 이전 generation prune
- restore 중 current unsafe state 삭제
- file watcher event만 믿고 source/catalog 삭제
- unit test가 실제 사용자 `%LOCALAPPDATA%\Negaflow`에 접근

## 25. 공식 자료

SQLite:

- [SQLite Online Backup API](https://www.sqlite.org/backup.html)
- [SQLite Online Backup C API](https://www.sqlite.org/c3ref/backup_finish.html)
- [Write-Ahead Logging](https://www.sqlite.org/wal.html)
- [SQLite database file format](https://www.sqlite.org/fileformat.html)
- [Temporary files used by SQLite](https://www.sqlite.org/tempfiles.html)
- [PRAGMA integrity_check](https://www.sqlite.org/pragma.html#pragma_integrity_check)
- [SQLite recovery API](https://www.sqlite.org/recovery.html)
- [How to corrupt an SQLite database](https://www.sqlite.org/howtocorrupt.html)

Windows storage/file APIs:

- [KNOWNFOLDERID and FOLDERID_LocalAppData](https://learn.microsoft.com/en-us/windows/win32/shell/knownfolderid)
- [Store and retrieve settings and app data](https://learn.microsoft.com/en-us/windows/apps/develop/data/store-and-retrieve-app-data)
- [Manage files with Windows App SDK](https://learn.microsoft.com/en-us/windows/apps/develop/files/)
- [FILE_ID_INFO](https://learn.microsoft.com/en-us/windows/win32/api/winbase/ns-winbase-file_id_info)
- [Locking and unlocking byte ranges](https://learn.microsoft.com/en-us/windows/win32/fileio/locking-and-unlocking-byte-ranges-in-files)
- [Moving and replacing files](https://learn.microsoft.com/en-us/windows/win32/fileio/moving-and-replacing-files)
- [ReadDirectoryChangesW](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-readdirectorychangesw)
- [Reparse points](https://learn.microsoft.com/en-us/windows/win32/fileio/reparse-points)
- [MSIX flexible virtualization](https://learn.microsoft.com/en-us/windows/msix/desktop/flexible-virtualization)
- [MSIX containerization overview](https://learn.microsoft.com/en-us/windows/msix/msix-containerization-overview)

관련 문서:

- [아키텍처](../00-overview/architecture.md)
- [제품 불변식](../99-plan/product-invariants.md)
- [Settings surface](../08-ui/surfaces/settings.md)
- [scanner protocol](../10-scanner/protocol-contract.md)
- [scanner plugin 보안](../10-scanner/plugin-security-and-lifecycle.md)
- [배포](../11-distribution/msix-signing.md)
