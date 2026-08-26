# 2026-08-07 SQLite catalog store 검증

기준일: 2026-08-07
대상: `Negaflow.Catalog.Core`의 `SqliteCatalogStore`와 관리 계층 SQLite 의존성 집합

## 검증 범위

- 없는 catalog를 빈 라이브러리로 읽지 않는지
- 앱을 껐다 켠 것과 같은 왕복에서 entity 순서와 payload가 보존되는지
- `position`이 UNIQUE인 상태에서 재정렬이 성립하는지
- row 삭제와 전체 비우기
- 미래 물리 schema version, 외부(macOS) 논리 version, 손상 파일, 상대 경로 거부
- 중복 id와 빈 id를 부분 쓰기 없이 거부하는지
- connection pooling이 파일 핸들을 남기지 않는지
- 프로세스 lock 없이 카탈로그를 여는 공개 경로가 남아 있지 않은지
- 취약한 native SQLite가 배포 대상에 들어오지 않는지
- Windows가 아닌 RID의 native payload가 출력에서 제외되는지

## 의존성 선택에서 실제로 걸린 것

`Microsoft.Data.Sqlite` 10.0.10을 그대로 참조하면 restore가 **실패합니다.**

```
error NU1903: 'SQLitePCLRaw.lib.e_sqlite3' 2.1.11 패키지에 알려진 높음 심각도 취약성인
https://github.com/advisories/GHSA-2m69-gcr7-jv3q 이(가) 있습니다.
```

CVE-2025-6965, CVSS 7.2입니다. 2.x 계열에 수정 릴리스가 없으므로 버전을 올려서 피할 수 없습니다.
`Microsoft.Data.Sqlite.Core` + `SQLitePCLRaw.config.e_sqlite3` 3.0.5 + `SourceGear.sqlite3` 3.53.4로
바꾼 뒤 lock 파일에서 `SQLitePCLRaw.lib.e_sqlite3`가 **완전히 사라졌고** restore가 통과합니다.

이것은 가설을 세워 피한 것이 아니라 restore 출력에서 걸려 고친 것입니다.

## RID payload 측정

| 대상 | 파일 수 | 바이트 |
|---|---:|---:|
| 제외 전 (`runtimes/`, 30개 RID) | 30 | 53,571,344 |
| 그중 Windows | 3 | 5,317,632 |
| 제외 후 (`win-x64`, `win-arm64`) | 2 | 3,788,288 |

`Directory.Build.targets`의 `RestrictRuntimeTargetsToWindows`가 android, ios, linux,
browser-wasm 등 28개 자산을 복사 대상에서 뺍니다. 빌드 로그가 이를 그대로 보고합니다.

```
[negaflow] dropped 0 non-Windows runtime asset(s) from Negaflow.Catalog.Core
[negaflow] dropped 28 non-Windows runtime asset(s) from Negaflow.Catalog.UnitTests
```

`win-x86`도 뺍니다. 이 제품의 대상 플랫폼이 아닙니다.

## 재정렬 회귀

`position INTEGER NOT NULL UNIQUE`이므로, 살아남은 row가 아직 쓰고 있는 자리로 다른 row를
upsert하면 `SQLITE_CONSTRAINT`로 transaction이 중단됩니다. 자리를 바꾸는 row만 먼저 큰 오프셋으로
밀어내는 단계를 **일부러 제거하고** 돌려 이를 확인했습니다.

```
{"status":"failed","operation":"catalog_unit_tests","assertions":246,
 "failures":["store_reorder_write","store_reorder_order","store_reorder_payload"]}
```

frame 3개를 `(1,2,3)`에서 `(3,1,2)`로 바꾸는 것만으로 쓰기가 실패합니다. 단계를 되돌리면 통과합니다.
즉 이 테스트는 실제로 무언가를 잡고 있으며, 통과가 우연이 아닙니다.

같은 구조가 macOS `LibraryCatalogSQLiteStore.swift`에도 보이지만 **macOS는 완성된 것으로 두므로
이번에 건드리지 않았습니다.** 그쪽에서 이 경로가 실제로 도달 가능한지는 별도로 확인할 일입니다.

## 단일 작성자 강제

`SqliteCatalogStore`를 `internal`로 내렸습니다. 공개 입구는 `CatalogSession` 하나이며,
`CatalogSession.Open`이 `CatalogProcessLock`을 먼저 잡습니다. 잡지 못하면 세션 객체 자체가
만들어지지 않으므로 **lock 없이 카탈로그를 여는 방법이 남아 있지 않습니다.** 이것은 호출자가
규율을 지키는지의 문제가 아니라 타입 접근성의 문제입니다.

lock 없이 쓸 수 있는 것은 `CatalogRecovery.IsValidCatalogSource` 하나입니다. 파일을 열지도 payload를
읽지도 않고 `integrity_check`와 두 version 축만 봅니다. 손상된 primary가 유효한 backup을 덮지 않게
하려면 이 확인이 lock 밖에서 필요합니다.

`NotFound`를 빈 라이브러리로 바꾸는 자리는 `CatalogSession.ReadOrCreate` **한 곳뿐**입니다. 그
변환이 흩어지면 손상된 카탈로그가 어딘가에서 조용히 빈 라이브러리로 대체될 수 있습니다.
`session_read_or_create_refuses_corrupt`가 손상 파일에서 `ReadOrCreate`가 여전히 실패하는 것을
확인합니다.

테스트는 `InternalsVisibleTo`로 store에 직접 닿습니다. 미래 schema version, 손상 파일, 상대 경로
같은 거부 경로는 정상 세션에서는 만들 수 없기 때문입니다.

**프로세스 경계도 관측했습니다.** 같은 프로세스 안에서 두 번째 세션이 거부되는 것만 보면
`FileShare.None`이 실제로 무엇을 막는지는 추론으로 남습니다. 테스트 실행 파일이 `--lock-contender`
인자로 자기 자신을 별도 프로세스로 띄워 확인합니다.

- lock 을 잡고 있는 동안 다른 프로세스 → `Busy` (`session_other_process_busy`)
- lock 을 놓은 뒤 다른 프로세스 → `acquired` (`session_other_process_acquires_when_free`)

두 번째 확인이 있어야 첫 번째가 의미를 가집니다. 경로 오류나 프로세스 기동 실패를 `Busy`로 잘못
읽는 경우를 배제하기 때문입니다.

## 실행 결과

| 대상 | 결과 |
|---|---|
| x64 Release 네이티브 build + CTest | 40/40 통과 |
| x64 Release 관리 solution build | 통과, 경고 0·오류 0 |
| x64 Release catalog unit | 267 assertion 통과 (이전 205, store 41, session 21) |
| x64 Release shell unit | 45 assertion 통과 |
| ARM64 Release 관리 solution cross-build | 통과, 경고 0·오류 0 |
| 저장소 provenance·라이선스 게이트 | 통과, files=1623 |
| `ci-gate.ps1 -Preset x64-release` 증분 벽시계 | 28.2초 |

ARM64 test executable은 빌드됐지만 x64 호스트에서 실행하지 않았으므로 ARM64 runtime 통과로
표시하지 않습니다.

## 성능 측정

설계 문서의 목표 규모인 frame 5만 개로 측정했습니다. x64 Release, 로컬 NVMe,
`journal_mode=DELETE`, `synchronous=FULL`, 매 쓰기마다 commit 후 `integrity_check` 포함입니다.

| 동작 | 시간 |
|---|---:|
| 최초 전체 쓰기 (50,000 frame) | 527 ms |
| 전체 읽기 (50,000 frame 디코드) | 255 ms |
| 아무것도 바뀌지 않은 재저장 | 343 ms |
| 1건만 편집한 재저장 | 337 ms |
| 전체 순서 뒤집기 (모든 position 변경) | 582 ms |
| catalog 파일 크기 | 10,108,928 바이트 |

뒤집은 뒤 다시 읽었을 때 첫 row가 `frame-049999`인 것까지 확인했습니다. relocation 경로의 최악에
가까운 입력에서도 정확합니다.

**해석.** 5만 frame 목표에서 모든 동작이 1초 미만입니다. 다만 무변경 재저장이 343 ms인 것은 이
store의 비용이 **바뀐 양이 아니라 catalog 전체 크기에 비례**한다는 뜻입니다. row 하나를 고치든
아무것도 안 고치든 5만 건의 upsert가 돌고 `integrity_check`가 전체 파일을 훑습니다. `WHERE` 가드가
디스크 페이지 쓰기는 막지만 statement 실행 자체는 막지 못합니다.

지금 규모에서는 문제가 아니므로 최적화하지 않습니다. **되돌아볼 조건:** 목표 규모가 5만을 크게
넘거나, 편집 한 번의 저장 지연이 UI에서 감지되는 경우. 그때 손댈 곳은 (1) dirty 집합만 upsert하도록
호출자가 변경분을 넘기는 것, (2) `integrity_check`를 매 쓰기가 아니라 열기와 backup 생성에서만
돌리는 것입니다.

## 하지 않은 것

- backup 세대, pending restore, legacy JSON→SQLite migration, defect sidecar
- commit 후 전체 payload 재디코드 비교 (지금은 `integrity_check`까지)
- fault injection: 쓰기 도중 강제 종료와 전원 장애 시나리오
- 크래시 뒤 남은 lock 파일의 소유자를 사용자에게 설명하는 것. 지금은 stale 파일이 소유권을 뜻하지
  않는다는 사실만 있고, 누가 잡고 있었는지는 기록하지 않습니다.
- WinUI 셸 연결. C ABI 쪽은 `nf_develop_export_v1` 로 열렸으나 카탈로그는 아직 셸에 붙지 않았습니다.
- WAL 도입 검토. macOS 기준선인 `DELETE` + `FULL`을 유지합니다.
