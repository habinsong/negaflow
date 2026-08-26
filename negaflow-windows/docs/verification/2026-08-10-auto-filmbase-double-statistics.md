# Auto FilmBase Double 통계 검증

검증일: 2026-08-10  
기준: fixed macOS baseline의 `FilmBaseSampleGrid.swift`, `FilmBaseStatistics.swift`,
`FilmBaseEstimator.swift`, `ChromabaseEngine+NegativePipeline.swift`

## 변경 계약

- affine sampled bitmap은 macOS와 같이 Float RGB입니다.
- RGB를 읽은 뒤의 luma, percentile, median, upper median, MAD, 후보 threshold, 채널 통계,
  strip 평균과 source 비교는 Double입니다.
- 선택된 Dmin은 공개 `AutoNegativeBaseResult`에 기록할 때만 Float로 좁힙니다.
- 공개 C ABI layout과 preview/export recipe 경로는 변경하지 않았습니다.

## 경계 회귀

`(0.949992359F, 0.85F, 0.7500076F)`의 기존 Float luma는 `0.849999964`이고 Double로 승격한
luma는 `0.850000003973643`입니다. 색상 후보 상한 `0.85`에서 Float 계산은 24픽셀 연결 성분을
포함하지만 macOS Double 계산은 제외합니다. 회귀 fixture는 이 성분이 `connected_component`로
선택되지 않는 것을 고정합니다.

## 실행 명령과 결과

```powershell
cmake --build out/build/native/x64-debug --config Debug --target negaflow_manual_negative_developer_tests
./out/build/native/x64-debug/Debug/negaflow_manual_negative_developer_tests.exe
```

- x64 Debug targeted: `manual_negative_developer`, failures `0`

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ./scripts/test.ps1 -Preset x64-debug
```

- x64 Debug native CTest: `44/44` 통과

```powershell
cmake --build out/build/native/x64-release --config Release --target `
  negaflow_manual_negative_developer_tests negaflow_develop_export_abi_tests
./out/build/native/x64-release/Release/negaflow_manual_negative_developer_tests.exe
./out/build/native/x64-release/Release/negaflow_develop_export_abi_tests.exe
```

- x64 Release 인접 회귀: `2/2` 통과

```powershell
cmake --build out/build/native/arm64-release --config Release --target `
  negaflow_manual_negative_developer_tests negaflow_develop_export_abi_tests negaflow_native
```

- ARM64 Release 세 target 교차 빌드 통과
- 두 테스트 실행 파일과 `Negaflow.Native.dll`의 PE machine: `0xAA64`
- ARM64 Windows 장치에서 실행한 증거는 아닙니다.

```powershell
py negaflow-mac/scripts/ci/verify-provenance.py
```

- provenance: files `1975`, text `1848`, binary `127`, declared resources `29`, reachable commits `148`

## 남은 검증

- 같은 입력을 Core Image로 축소·측정한 macOS numeric golden
- 실제 촬영 TIFF의 Auto Dmin과 최종 preview/export pixel 비교
- ARM64 Windows 장치 runtime
- GPU preview 경로와 CPU export 결과 비교
- 대량 batch에서 Double luma 격자의 처리량·peak memory 측정
