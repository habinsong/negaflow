# 2026-08-09 Catalog pending restore 검증

대상: x64 Debug, logical backup 선택부터 다음 safe startup 적용까지

## 실행

```powershell
dotnet run --project tests\Catalog.UnitTests\Negaflow.Catalog.UnitTests.csproj -c Debug
```

결과: Catalog 445 assertions, failure 0.

## 확인한 경계

- schedule 시 선택 generation을 private copy로 고정하고 live session catalog는 유지
- 원래 backup generation 삭제 후에도 pinned copy 유효
- cancel이 marker와 pinned copy 제거
- 다음 `CatalogSession.Open`에서만 적용하고 직전 live catalog를 safety generation으로 보존
- future storage version은 primary bytes와 marker/copy를 유지한 채 open 차단
- 적용 성공 뒤 cleanup 실패는 `applied` fence를 남기며 다음 open은 cleanup만 재시도

process-kill/disk-full/power-loss fault injection과 defect sidecar가 있는 restore는 이번 증거에 포함하지
않았습니다.
