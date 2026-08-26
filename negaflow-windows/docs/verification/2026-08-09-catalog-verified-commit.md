# 2026-08-09 catalog verified commit 검증

대상: `CatalogSession`의 SQLite write/readback/rollback 경계

## 기준과 구현

- 기준: 고정 macOS `LibraryCatalogSQLiteCommitVerifier`와
  `windows_docs/14-persistence/catalog-and-storage.md`의 P3 계약
- write 전 유효 primary를 커밋 전용 UUID rollback snapshot과
  `library.backup.sqlite`에 각각 보존
- write 뒤 pooling 없는 새 연결로 metadata와 9개 table의 row 순서·ID·canonical payload 전체 비교
- write/readback 실패 시 UUID snapshot에서 직전 primary bytes를 원복
- 직전 부재 상태는 main DB와 `-journal`/`-wal`/`-shm`을 함께 제거
- rollback 실패 시 세션의 후속 mutation을 차단하고 recovery artifact를 보존
- corrupt/future primary와 primary 부재+backup 존재 상태는 fail-closed

## 실행한 검증

```powershell
dotnet build tests\Catalog.UnitTests\Negaflow.Catalog.UnitTests.csproj `
  --configuration Debug -p:Platform=AnyCPU --no-restore
dotnet run --project tests\Catalog.UnitTests\Negaflow.Catalog.UnitTests.csproj `
  --configuration Debug -p:Platform=AnyCPU --no-build --no-restore
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\test-managed.ps1 -Preset x64-debug
```

결과: 빌드 경고 0·오류 0, Catalog 376과 Shell 300 assertions 통과.

서로 다른 실패 경계만 추가 검증했습니다.

- canonical readback mismatch 뒤 exact primary 복구
- writer가 fixed backup을 다른 유효 DB로 바꿔도 private snapshot 세대 복구
- rollback 실패를 별도 오류로 반환하고 후속 write 차단
- 최초 writer 실패가 남긴 main DB와 hot journal을 함께 제거
- missing/corrupt/future primary가 빈 library 생성 또는 backup 덮어쓰기로 이어지지 않음

## 남은 검증

- 실제 process-kill, disk-full, power-loss fault harness
- immutable logical backup generation과 retention
- pending restore 및 defect sidecar
- ARM64 Windows 실제 runtime

따라서 이번 증거는 동기 fault-injection과 정상 x64 경로를 닫지만 전원 장애 내구성 완료를 주장하지
않습니다.
