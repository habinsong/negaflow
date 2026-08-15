# GrainMend FILM-R v2 자동 복원 검증

날짜: 2026-08-10

기준: `negaflow-windows-2026-08-04-m0`, macOS commit
`2fa1d6297378673b58b8bec72025e968ccc3125c`

대상: Windows x64 Release CPU, `chromabase-grain-mend-rgb-auto-v9`

## 입력과 경계

- FILM-R v2 고정 corpus의 damaged/restored JPEG 44쌍을 사용했습니다.
- corpus DOI는 `10.6084/m9.figshare.21803304.v2`, 표시된 라이선스는 CC BY 4.0입니다.
- macOS 저장소의 pinned fetch script가 88개 파일 hash와 `corpus-lock.json`을 검증했습니다.
- corpus는 무시되는 `negaflow-windows/out/` 아래에만 두었으며 제품·테스트 payload에 포함하지 않습니다.
- Windows runner는 WIC JPEG decode, sRGB→linear working RGB, GrainMend sensitivity `0.7`,
  linear→sRGB8 render를 거쳐 macOS evaluator와 같은 PSNR·pixel fraction을 계산합니다.
- 자동 복원 설정은 dust sensitivity `0.0`, scratch sensitivity `0.1`, detail protect `0.6`,
  structure-line rejection 활성입니다.

## 기준 관측값의 provenance 경계

- `Config/defect-removal-film-r-v2-baseline.json`의 `+0.465934 dB` 관측값은 macOS 문서가 명시한
  2026-07-25 안전 자동 결과입니다. 당시에는 고밀도 후보 사진을 자동 중지해 34장 개선, 6장 악화,
  4장 동일이었습니다.
- 고정 기준 commit `2fa1d629...`은 이후 `17f1f36d...`의 “자동 결과를 버리지 않고 경고” 변경과
  `696b5fdf...`의 이어지는 구조선 배제를 모두 포함합니다. 하지만 config blob은 고정 기준과 현재
  HEAD에서 같은 `c112bc2107cd6b0a7834aa3d317523c68542abbc`이며 이 변경 뒤 관측값은 재생성되지
  않았습니다.
- 따라서 config의 `baseline` 블록은 역사적 회귀 참고치이고 `qualityFloor`는 계속 유효한 절대 안전선입니다.
  현재 고정 macOS 소스와 Windows의 결과 동등성은 같은 44쌍을 macOS host에서 다시 실행한 per-image
  mask·pixel report로만 판정합니다. 현재 그 증거는 없습니다.

확인 명령:

```powershell
git merge-base --is-ancestor 17f1f36d38cf3a1ce92a049ea5c50246146ed4f4 `
  2fa1d6297378673b58b8bec72025e968ccc3125c
git merge-base --is-ancestor 696b5fdfb31aed85353aa93ed75c0971d998c695 `
  2fa1d6297378673b58b8bec72025e968ccc3125c
git rev-parse `
  2fa1d6297378673b58b8bec72025e968ccc3125c:Config/defect-removal-film-r-v2-baseline.json `
  HEAD:negaflow-mac/Config/defect-removal-film-r-v2-baseline.json
```

## 변경 범위

- 반복되는 평행·교차 구조선 component를 grid field·방향·거리 문맥으로 제외합니다.
- 짧은 scratch 후보의 양끝 바깥으로 같은 방향 response가 이어지면 scene line으로 제외합니다.
- dust/scratch/detail control을 detector threshold에 연결하고 finite `0...1` 범위를 벗어나면
  fail-closed합니다.
- 기본 post-pipeline 호출은 기존 `0.5/0.5/0.75`와 structure filter 비활성을 보존합니다.
- whole-frame 자동 검출은 원본 해상도의 1400px 이하 core와 80px effective halo를 사용하고, core 소유
  dust/scratch evidence를 전역 8-연결로 다시 잇습니다. 구조선 판단은 stitch 뒤 한 번만 실행합니다.
- labeled 경로에 radius 4 채널별 thin-scratch evidence, strong/weak hysteresis, sensitivity별
  dust/scratch aspect·thickness gate, strong dust-core 밀도 및 weak-only 장거리 scratch gate를
  추가했습니다.
- labeled thin evidence를 dust 통계 scope 안에서 확정해 dust magnitude·thin magnitude·near/far
  texture float buffer 4개를 scratch 방향 적분 전에 해제합니다. evidence OR 순서만 이동하므로
  후보·mask·복원 pixel 수학은 바뀌지 않습니다.
- opt-in corpus runner `negaflow_grain_mend_corpus_tests`는 대용량 corpus를 기본 CTest에 넣지 않습니다.

## 실행 명령

```powershell
py negaflow-mac/scripts/defect-corpus/fetch-film-r.py --all `
  --output negaflow-windows/out/defect-corpus/film-r-v2

cmake --build negaflow-windows/out/build/native/x64-release --config Release `
  --target negaflow_grain_mend_corpus_tests --parallel

& negaflow-windows/out/build/native/x64-release/Release/negaflow_grain_mend_corpus_tests.exe `
  negaflow-windows/out/defect-corpus/film-r-v2 `
  negaflow-windows/out/defect-corpus/film-r-v2-report/report-halo80.json `
  negaflow-windows/out/defect-corpus/film-r-v2-report/regressions-halo80

py negaflow-mac/scripts/defect-corpus/evaluate-quality.py `
  --config negaflow-mac/Config/defect-removal-film-r-v2-baseline.json `
  --report negaflow-windows/out/defect-corpus/film-r-v2-report/report-halo80.json `
  --output negaflow-windows/out/defect-corpus/film-r-v2-report/quality-gate-halo80.json

cmake --build negaflow-windows/out/build/native/x64-debug --config Debug `
  --target negaflow_grain_mend_tests --parallel
& negaflow-windows/out/build/native/x64-debug/Debug/negaflow_grain_mend_tests.exe

powershell -NoProfile -ExecutionPolicy Bypass -File `
  negaflow-windows/scripts/test.ps1 -Preset x64-debug

cmake --build negaflow-windows/out/build/native/x64-release --config Release `
  --target negaflow_grain_mend_tests negaflow_develop_export_abi_tests --parallel
& negaflow-windows/out/build/native/x64-release/Release/negaflow_grain_mend_tests.exe
& negaflow-windows/out/build/native/x64-release/Release/negaflow_develop_export_abi_tests.exe

cmake --build negaflow-windows/out/build/native/arm64-release --config Release `
  --target negaflow_grain_mend_tests negaflow_grain_mend_corpus_tests `
           negaflow_develop_export_abi_tests --parallel
```

## 결과

| 지표 | Windows v9 | 절대 quality floor | 역사적 macOS 관측값 |
|---|---:|---:|---:|
| 개선 이미지 | 40 | 30 이상 | 34 |
| 악화 이미지 | 3 | 10 이하 | 6 |
| 평균 PSNR 변화 | +0.332190 dB | 0 이상 | +0.465934 dB |
| 중앙 PSNR 변화 | +0.216207 dB | 0 이상 | +0.118050 dB |
| 최악 PSNR 변화 | -0.194325 dB | -1.5 이상 | -1.337816 dB |
| 가중 개선 픽셀 비율 | 0.000260812 | 0.0002 이상 | 0.000292509 |
| 가중 악화 픽셀 비율 | 0.000190639 | 0.0003 이하 | 0.000171249 |
| 변경 픽셀 비율 | 0.000343990 | 0.0006 이하 | 0.000429993 |

- 절대 quality floor 8개 조건은 모두 충족했습니다.
- 역사적 macOS 관측값+tolerance gate는 평균 PSNR 하나가 부족해 실패합니다. 이 실패는 현재 macOS
  결과와의 수치 차이를 증명하지 않으며, 동일 입력 hosted report가 없으므로 결과 동등성 통과로도
  간주하지 않습니다.
- v7 full-resolution 경로 대비 평균 PSNR은 `+0.306312`에서 `+0.332190 dB`, 중앙값은
  `+0.163058`에서 `+0.216207 dB`로 개선됐습니다. v8의 48px halo 대비 평균은 `0.000327 dB`
  낮고 중앙값과 악화 픽셀 비율은 좋아졌으며, v9은 고정 macOS effective halo 계약과 일치합니다.
- x64 Debug 전체 native CTest 43/43, x64 Release GrainMend와 develop-export ABI 2/2가 통과했습니다.
- ARM64 Release의 GrainMend test, corpus runner, develop-export ABI target이 교차 빌드됐습니다.
  ARM64 장치 실행 증거는 아닙니다.
- 수명 최적화 전후 3장 smoke report는 byte-exact했고 SHA-256도
  `229A7816AFA8F35BDA8196EC457C0B657D3478B5F39F0F77217A3C9E885097B1`로 같았습니다.
  20ms polling으로 관측한 프로세스 peak working set은 `383.86 MiB`에서 `363.86 MiB`로
  `20.00 MiB`(`5.2%`) 줄었습니다. 세 장 시간은 변경 전 `6907/5368/6086ms`, 변경 후
  `6981/5393/6281ms`여서 속도 향상으로 해석하지 않습니다.
- scratch 각도 작업자 상한을 4개에서 2개로 제한한 뒤에도 같은 3장 smoke report의 SHA-256은
  위 값과 byte-exact하게 같았습니다. peak working set은 다시 `363.86 MiB`에서 `343.82 MiB`로
  `20.04 MiB`(`5.5%`) 줄었고, 세 장 시간은 `7322/5659/6422ms`로 직전보다 `2.2~4.9%`
  늘었습니다. 결과 불변과 메모리 절감을 위해 이 제한을 유지하며 속도 향상으로 세지 않습니다.
- 두 작업자가 네 각도 묶음마다 ridge/integrated full-map을 다시 할당하던 경로를 작업자별
  workspace 재사용으로 바꿨습니다. 사진당 full-map vector storage 할당은 `16회`에서 `4회`로
  줄었고, 두 번의 3장 smoke report SHA-256은 모두 위 값과 byte-exact하게 같았습니다. 두 실행의
  시간은 각각 `7060/5467/6205ms`, `7123/5436/6246ms`로 worker-2 기준보다 `2.7~3.9%` 짧았습니다.
  peak working set은 두 실행 모두 `348.80 MiB`로 이전 단일 측정 `343.82 MiB`보다 `4.98 MiB`
  높았으므로 메모리 절감으로 주장하지 않습니다. 반복 할당 감소와 관측된 시간 개선만 기록합니다.
- workspace 재사용 뒤 x64 Debug 전체 native CTest `43/43`, x64 Release GrainMend와
  develop-export ABI `2/2`가 통과했습니다. ARM64 Release의 GrainMend test, corpus runner,
  develop-export ABI와 DLL target은 교차 빌드됐으며 ARM64 장치 실행 증거는 아닙니다.
- full-resolution tile마다 새로 소유하던 `DetectionImage`의 5개 float map, `CandidateMaps`의
  weak/strong/scratch map과 evidence byte map은 사진 단위 workspace의 capacity를 재사용하도록
  바꿨습니다. 두 번의 3장 smoke report SHA-256은 모두
  `229A7816AFA8F35BDA8196EC457C0B657D3478B5F39F0F77217A3C9E885097B1`로 기존과 byte-exact했습니다.
  실행 시간은 `6942/5366/6247ms`, `6980/5389/6162ms`로 직전 workspace 실행 두 번의 합보다
  `1.2%` 짧았습니다. 20ms polling peak working set은 `344.40/344.41 MiB`로 직전
  `348.80 MiB`보다 약 `4.40 MiB`(`1.26%`) 낮았습니다. 이는 통제된 benchmark가 아니라 동일
  호스트의 반복 관찰이며 결과 불변·반복 할당 감소를 우선 근거로 삼습니다.
- 최종 변경 뒤 x64 Debug/Release 전체 native CTest `44/44`가 통과했습니다. ARM64 Release의
  GrainMend test, corpus runner, develop-export ABI와 DLL target을 교차 빌드했고 네 PE machine
  field가 모두 `AA64`임을 확인했습니다. ARM64 장치 실행 증거는 아닙니다.
- detector phase 계측에서 각 원본해상도 타일의 채널별 먼지 morphology가 `806~912ms`, scratch
  방향 적분이 `118~124ms`로 관측됐습니다. bipolar top-hat의 독립 opening/closing을 한 background
  worker와 호출 thread에서 동시에 실행하되 process 전체 background worker를 하나로 제한했습니다.
  worker 생성 실패와 단일 hardware thread는 종전 순차 경로로 fallback합니다.
- 동일 3장 smoke의 변경 직전 시간은 `6890/5296/6081ms`, 변경 뒤 두 실행은
  `4584/3598/4064ms`, `4631/3598/4109ms`로 약 32~33% 짧았습니다. smoke report SHA-256은 세 실행
  모두 `229A7816AFA8F35BDA8196EC457C0B657D3478B5F39F0F77217A3C9E885097B1`입니다. 변경 뒤
  20ms polling peak working set `344.45 MiB`는 변경 전 반복 측정 `344.40/344.41 MiB`와 사실상
  같습니다.
- 전체 44장 결과 `report-morphology-parallel.json`은 기존 `report-halo80.json`과 SHA-256
  `866319631F907E7AD9528A770A4E18E1AD3A96EF43837568B0D4B889ECF686AD`로 byte-exact했습니다.
  전체 실행은 decode·render·평가를 포함해 `232.129초`, GrainMend 구간은 사진당
  `3.594~4.885초`였습니다. 기존과 같은 평균 PSNR `+0.332190 dB`여서 절대 quality floor 8개는
  유지합니다. 기존 역사적 관측값과 허용범위를 사용하는 평균 PSNR 조건은 계속 실패하지만,
  이를 현재 macOS parity 판정으로 사용하지 않습니다.
- 병렬화 최종 상태에서 x64 Debug 전체 native `44/44`, x64 Release GrainMend·ABI `2/2`가
  통과했습니다. ARM64 Release GrainMend test·corpus·ABI·DLL은 모두 `AA64`로 교차 빌드했지만
  ARM64 장치에서는 실행하지 않았습니다.

## 채택하지 않은 component repair 결합 실험

- FILM-R macOS bench가 영역 component repair를 사용한다는 이유만으로 Windows 전체 자동 mask에
  영역 repair 코어를 직접 대입하지 않았습니다. 현재 제품 계약은 사용자 검토·제외 뒤의 영역 Defects와
  전역 자동 PostPipeline을 분리합니다.
- 선택한 `portra400_135_1`, `provia100_135_1`, `velvia50_half_1`에서 기존 전역 median 결과의 PSNR은
  각각 `-0.160/+1.087/-0.194 dB`였습니다. 같은 검출 결과를 component repair에 연결하면 dust 0px
  mask에서 `-1.657/-9.031/-4.995 dB`, dust 2px mask에서 `-1.884/-14.719/-10.567 dB`로 후퇴했습니다.
- 두 실험은 `out/` 아래에만 결과를 남겼고 소스 변경은 모두 제거했습니다. 이 결과만으로 component
  repair 코어의 macOS 동등성 여부를 판정하지는 않습니다. 다만 검토되지 않은 전체 자동 mask에
  고급 복원을 연결하는 것은 안전하지 않다는 결론에는 충분합니다.

## 검증하지 않은 범위와 다음 격차

- macOS의 역사적 report와 같은 corpus/평가식은 사용했지만 Windows와 현재 고정 macOS 소스를 같은 입력에서 직접
  실행한 mask·pixel golden은 아닙니다.
- macOS component별 구조/질감 복원 코어는 별도 영역 Defects 경로로 C ABI·sidecar·preview/export에
  연결됐지만 같은 입력의 macOS pixel golden은 없습니다. 전역 자동 PostPipeline은 macOS와 같은
  median fallback 계약을 유지합니다. 먼지 dilation과 불완전한
  방향 보간을 전역 경로에 각각 분리 실험했을 때 악화 픽셀 또는 최악 PSNR이 크게 회귀해 제거했습니다.
  curve half 6 보조 적분도 단독 추가 시 품질 지표가 후퇴해 제거했습니다.
- morphology 병렬화 뒤 full-resolution tile의 전체 코퍼스 관측 시간은 약 3.6~4.9초/장이지만,
  정식 대형 batch 처리량 통계는 아닙니다.
- JPEG corpus는 실제 촬영 TIFF의 decode·색관리·최종 export 경로를 증명하지 않습니다.
- ARM64 runtime, WARP/GPU, 실제 촬영 TIFF와 수백 장 batch 처리량은 이번 검증에 포함하지 않았습니다.
