# 2026-08-09 catalog logical backup generation 검증

대상: `CatalogSession.CreateBackup`과 `CatalogBackupStore`

## 구현 계약

- raw `library.backup.sqlite`와 분리된 immutable logical generation
- canonical `library.json` + empty `defects/` + manifest v3
- manifest의 monotonic sequence, UTC 시각, frame 수, catalog version, byte count, SHA-256
- `staging-*.tmp` 전체 검증 → write-through directory rename → final 재검증 → retention
- valid generation만 최신 3개 보존 대상으로 계산
- future/damaged generation은 sequence 재사용과 prune 모두에서 안전하게 처리
- defect edit이 선언되면 sidecar 구현 전까지 generation 생성 차단

## 실행 결과

```powershell
dotnet build tests\Catalog.UnitTests\Negaflow.Catalog.UnitTests.csproj `
  --configuration Debug -p:Platform=AnyCPU --no-restore
dotnet run --project tests\Catalog.UnitTests\Negaflow.Catalog.UnitTests.csproj `
  --configuration Debug -p:Platform=AnyCPU --no-build --no-restore
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\test-managed.ps1 -Preset x64-debug
```

결과: 빌드 경고 0·오류 0, Catalog 396과 Shell 300 assertions 통과.

서로 다른 실패 경계로 invalid staging 비공개, hash 손상 거부, sidecar 없는 defect edit 차단,
future manifest sequence 이후 단조 증가, future generation 비삭제, valid 세대 3개 retention을 확인했습니다.

## 남은 범위

- defect sidecar를 포함한 generation
- pending restore와 safe-startup apply
- external destination과 restore drill
- process-kill/disk-full/power-loss fault harness
