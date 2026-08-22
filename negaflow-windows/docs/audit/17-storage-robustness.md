> # 하드코딩 · 가짜 구현 · 창작 · 병신 백엔드 · 병신 프론트엔드 = 죽음
>
> ** 추측 금지.** 이 문서의 모든 숫자는 실제로 돌려 센 것입니다. 못 잡은 것은 못 잡았다고 적습니다.

# 17 — 저장소(catalog) 견고성 (2026-08-19)

카탈로그 백업·복원 경로에서 **간헐적으로 깨지던 시험의 원인을 잡고 고친 기록**입니다.
시험이 "가끔 빨간색" 인 상태는 그 자체로 위험합니다 — 진짜 결손이 섞여 들어와도
"또 그거겠지" 로 넘어가게 됩니다.

---

## 1. 증상과 실측

`scripts/test-managed.ps1 -Preset x64-release` 의 catalog 게이트가 같은 코드에서 붙었다
떨어졌다 했습니다. 세어 봤습니다(2026-08-19, x64 Release, 같은 바이너리):

| | 실패한 실행 |
|---|---|
| 고치기 전 | **12회 중 5회** (앞선 표본에서는 6회 중 4회) |
| 고친 뒤 | **15회 중 0회** |

깨지는 이름은 매번 달랐습니다 — `backup_defect_generation_created` ·
`pending_future_schedule_success` · `pending_cleanup_schedule_success` ·
`interrupted_restore_scheduled` · `defect_restore_schedule_with_sidecars` …
공통점은 **백업 세대 승격과 복원 예약** 자리라는 것뿐이었습니다.

## 2. 원인을 확정한 방법

1. **실패 줄이 원인을 말하게 했습니다.** 시험의 `Check(x.IsSuccess, "name")` 은 실패해도
   "false" 만 남깁니다. 실패했을 때만 까닭을 덧붙이는
   `Check(condition, name, detail)` 을 넣어 여섯 자리에 붙였습니다.
   → 첫 수확: `interrupted_restore_scheduled (IoFailure generation='backup-…')`.
2. **어느 갈래인지 갈랐습니다.** `CatalogPendingRestoreStore.Schedule` 의 `IoFailure` 는
   두 곳에서 납니다(예외 catch · `PromoteDirectory` 가 false). catch 쪽에 임시 기록을
   붙여 10회 돌렸으나 **파일이 생기지 않았습니다** → 예외가 아니라 승격 실패입니다.
3. **Win32 오류를 P/Invoke 바로 다음 줄에서 읽었습니다.** 처음에는 `win32=0` 이 찍혔는데,
   `Path.GetTempPath()` 같은 중간 관리 호출이 마지막 오류를 덮어썼기 때문입니다.
   `MoveFileExW` 직후에 잡도록 고치니 세 번 모두 **`win32=5` ERROR_ACCESS_DENIED**.
4. **핸들 누수를 배제했습니다.** `CopyDurable`·`WriteDurable`·`ValidateGeneration` 의
   스트림은 전부 `using` 이고 `File.ReadAllBytes` 는 즉시 닫습니다 — 전수 확인.
5. **격리 재현으로 환경 요인을 확인했습니다.** 같은 순서(폴더 만들기 → WriteThrough 로
   파일 셋 → 읽어 검증 → `MoveFileExW`)를 %TEMP% 에서 **2,000회** 돌렸을 때 실패 **0회**.
   저장소 `out\build` 트리에서만 났습니다.

**결론:** Windows 는 폴더 안에 열린 파일이 하나라도 있으면 디렉터리 이름 바꾸기를
`ERROR_ACCESS_DENIED`(5) 또는 `ERROR_SHARING_VIOLATION`(32) 로 거절합니다. 우리 핸들은
모두 닫혀 있으므로, 방금 쓴 파일을 **바이러스 검사기·인덱서가 몇 ms 잡고 있는 것**입니다.

## 3. 조치

`src/Catalog.Core/Storage/StorageMoveRetryPolicy.cs` — **5 와 32 에 한해**
1·2·4·8·16·32·64·128 ms(합 255 ms)로 물러섰다가 다시 겁니다.

- 다른 오류는 **그대로 실패**입니다. 권한·경로·존재 문제를 재시도로 덮지 않습니다.
- 대상 경로는 부르는 쪽이 새 GUID 로 만들고, 실패해도 원본은 그대로 남습니다 —
  다시 걸어도 값이 바뀌지 않습니다.
- 붙인 자리 셋: 백업 세대 승격(`CatalogBackupFiles.MoveDirectory`), 복원 예약 승격
  (`CatalogPendingRestoreFiles.PromoteDirectory`), 결함 레시피 폴더 교체
  (`CatalogDefectRestoreTransaction.MoveDirectory`).
- `PromoteDirectory` 에 `out int win32Error` 갈래를 남겼습니다. 다음 사람이 같은 것을
  다시 계측하지 않게 하기 위해서입니다.

## 4. 이것은 제품 문제이기도 합니다

시험만의 문제가 아닙니다. 사용자 기계에도 검사기가 있습니다. 고치기 전이라면 백업이나
복원 예약이 **"IoFailure"** 한 줄만 남기고 실패할 수 있었고, 그 줄에는 까닭이 없었습니다.

## 5. 확인 못 한 것

- 파일 하나짜리 이동(마커·사이드카·커밋)에도 같은 일이 나는지는 **안 쟀습니다.**
  이번 실패는 전부 디렉터리 승격이었습니다. 나면 같은 정책을 붙이면 됩니다.
- 어떤 프로세스가 잡고 있었는지(Defender·Search·다른 것)는 **특정하지 못했습니다.**
  핸들 추적(`handle.exe`/ETW)까지는 가지 않았습니다. 오류 코드와 격리 재현으로 갈래는
  확정했습니다.


---

## 6. 2026-08-20 확인

`catalog` 시험 **737 assertions · 실패 0** (x64-release ci-gate). 이 정책을 넣은 뒤로
간헐 실패는 다시 나오지 않았습니다. 5절의 "확인 못 한 것" 둘은 **그대로 남아 있습니다.**
