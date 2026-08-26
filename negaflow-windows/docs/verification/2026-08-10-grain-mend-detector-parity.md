# GrainMend whole-frame 검출 수학 정렬 검증

날짜: 2026-08-10

기준: `negaflow-windows-2026-08-04-m0`, macOS commit
`2fa1d6297378673b58b8bec72025e968ccc3125c`

대상: Windows x64 Debug/Release CPU 경로

## 변경 범위

- Develop post-pipeline `strength` 호출의 실제 기본값인 dust/scratch sensitivity `0.5`, detail protect
  `0.75`를 기준으로 검출 수학을 고정했습니다.
- sRGB 채널별 radius 4/8/12 bipolar top-hat, radius 12/36 문맥, dust strong/weak 후보를 적용했습니다.
- `max(R,G,B)`에 22.5도 간격 8방향 ridge와 25-tap 방향 적분을 적용했습니다.
- dust isolation, dust/scratch 공동 grain-field 제거, PCA scratch gate와 mask dilation을 적용했습니다.
- 1800px 초과 입력은 linear working RGB의 separable Lanczos-3 축소 뒤 sRGB로 변환하며, 필요한
  수평 행만 cache합니다. 긴 변에서 정한 단일 scale을 두 축 kernel에 공통 적용합니다. 확대 마스크는
  pixel-center affine bilinear weight를 strength blend에 반영합니다.
- morphology, detector, component mask, resampling, repair orchestration을 독립 파일로 분리했습니다.
- 알고리즘 식별자는 `chromabase-grain-mend-rgb-auto-v5`입니다.

## 실행 명령

```powershell
cmake --build --preset x64-debug --target negaflow_grain_mend_tests
ctest --test-dir out/build/native/x64-debug -C Debug -R '^native\.grain_mend$' --output-on-failure
cmake --build --preset x64-debug --target negaflow_develop_export_abi_tests
ctest --test-dir out/build/native/x64-debug -C Debug -R '^native\.develop_export_abi$' --output-on-failure

cmake --build --preset x64-release --target negaflow_grain_mend_tests
ctest --test-dir out/build/native/x64-release -C Release -R '^native\.grain_mend$' --output-on-failure
cmake --build --preset x64-release --target negaflow_develop_export_abi_tests
ctest --test-dir out/build/native/x64-release -C Release -R '^native\.develop_export_abi$' --output-on-failure

cmake --build --preset arm64-debug --target negaflow_grain_mend_tests negaflow_develop_export_abi_tests
cmake --build --preset arm64-release --target negaflow_grain_mend_tests negaflow_develop_export_abi_tests
```

## 결과

- x64 Debug: `native.grain_mend` 1/1 통과(테스트 2.00초, CTest 2.12초),
  `native.develop_export_abi` 1/1 통과(테스트 0.08초, CTest 0.09초).
- x64 Release: `native.grain_mend` 1/1 통과(테스트 0.23초, CTest 0.27초),
  `native.develop_export_abi`는 같은 최종 product source에서 1/1 통과(테스트 0.04초).
- ARM64 Debug/Release: `negaflow_grain_mend_tests`와 `negaflow_develop_export_abi_tests` 교차 빌드 통과.
  ARM64 장치 실행 증거는 아닙니다.
- Release 재구성에서 detector/components/morphology/resampling과 GrainMend 테스트가 모두 실제 컴파일됐습니다.
- 검증 사례는 단독 blue-channel 먼지, 세로·45도·18도·72도 scratch, 밀집 chromatic grain-field,
  일반 grain field, 넓은 명부·어두운 구조, 3600×129→1800×65 scratch, 3600×9 rounded short-axis
  uniform-scale phase, 1D/2D affine mask와 transparent-black 경계 weight, strength/alpha 및 invalid input입니다.

## 검증하지 않은 범위

- Windows에서는 macOS Swift/Core Image 테스트를 실행하지 않았습니다.
- 1800px 초과 입력의 처리 순서와 kernel 계열은 정렬했지만 Core Image 실제 phase·edge 수치와
  Windows Lanczos/affine 표본을 macOS fixture로 아직 비교하지 않았습니다.
- macOS가 생성한 동일 입력 mask/pixel golden 및 실제 촬영 TIFF를 아직 비교하지 않았습니다.
- ARM64 runtime, 전체 CI, WARP/GPU, 대형 TIFF와 다중 사진 처리량은 실행하지 않았습니다.

## v9 후속 검증

반복 grid와 이어지는 scene line을 제외하고 sensitivity/detail control 및 원본 해상도 tile stitch를
연결한 v7 뒤, labeled thin-scratch evidence와 sensitivity별 component gate를 추가하고 macOS의 80px
effective tile halo까지 정렬한 v9 결과는 별도
기록 `2026-08-10-grain-mend-film-r-v2.md`에 남깁니다. 이 문서의 v5 명령과 결과는 당시의 역사적
증거이며, 현재 동등성 상태는 v9 FILM-R 결과를 우선합니다.
