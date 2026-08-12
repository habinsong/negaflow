# 구현·검증 상태

기준일: 2026-08-12

## 2026-08-12 Positive film develop route

네이티브 엔진과 request factory가 이미 지원하던 Color/B&W positive film scan이 catalog `CanDevelop`
게이트에서 잘못 막히던 문제를 수정했습니다. 이제 positive scan은 Dmin/base와 inversion을 건너뛰고 같은
preview/export 경로로 들어가며, 컬러 슬라이드의 GrainMend IR 자동 보정도 기존 색소 이미지 판정과 함께
실제로 도달할 수 있습니다. x64 Debug Catalog 595, Shell 353 assertions를 통과했습니다.

## 2026-08-12 Library phrase search

macOS `e49c07c`와 같이 Library 검색창이 입력 문구를 한 값 안에서 연속으로 찾도록 연결했습니다. 공백 유무,
대소문자, 발음 구별 기호 차이는 무시하지만 이름과 경로에 낱말이 나뉘어 있는 frame은 더 이상 잘못 포함하지
않습니다. 검색은 catalog를 다시 쓰거나 원본에 접근하지 않고, 현재 표시한 frame 목록만 즉시 좁힙니다. x64
Debug managed build와 Catalog 595, Shell 355 assertions를 통과했습니다.

## 2026-08-12 Library import activation

Library의 두 Import Photos 버튼을 실제 Windows file picker와 기존 catalog import 경로에 연결했습니다. TIFF를
여러 장 선택하면 catalog에 원자적으로 기록하고 현재 목록을 즉시 갱신합니다. 취소는 변경하지 않으며 picker나
파일 접근 실패는 모든 지원 언어 리소스의 오류 문구로 표시합니다. x64 Debug managed build와 Catalog 595,
Shell 355 assertions를 통과했습니다.

## 2026-08-12 Output sharpening native core

macOS `OutputSharpening`의 screen/matte/glossy 매체별 반경·강도와 DPI 제곱근 스케일을 Windows C++20
공통 현상 경로에 추가했습니다. 창작용 Texture sharpness와 분리되어 crop/rotation 뒤 최종 preview/PNG16/TIFF16
출력에 한 번만 적용되며, strength 0은 기존 픽셀·취소·진행 경로를 그대로 보존합니다. ABI 0.36/v26은
strength, medium, DPI를 append-only request로 전달하고 C# Interop이 같은 v26 preview/export entry point를
사용합니다. x64 Debug `native.texture_stage`, `native.develop_export_abi`, Interop 187 assertions를 통과했습니다.
실제 촬영 TIFF와 macOS-hosted pixel golden 비교는 아직 수행하지 않았습니다.

## 2026-08-12 GrainMend paired visible/IR detector native core

최신 macOS 계약의 paired-plane 검출 코어를 Windows C++20에 추가했습니다. 결함 신호 우선 정수 정렬과
누설 상관 fallback, 신뢰되지 않은 seed의 다중 결함 consensus, border-connected dark margin 제외,
true-scale closing·광학 밀도, scan-derived floor/sigma, 면적 누적 후보, 8방향 연결, 결함별 가시광
확인·median/MAD·significance-dependent inverse-Mills 보정, attenuation/core 분리와 bounded R16 cluster를
한 경로로 실행합니다. macOS anchor 의미의 `(3,2)` 정렬·5개 이상 성분·세로/대각 스크래치, 20px
consensus, IR-only 기각, margin halo 제외를 고정했고 x64 Debug native **62/62**가 통과했습니다.

ABI 0.33의 단일 실행 opaque handle로 이 코어를 C#에 연결했습니다. native가 소유한 cluster·component
payload는 크기 조회 뒤 한 번 복사하고 명시적으로 해제합니다. 관리 coordinator는 색상 네거티브·포지티브만
허용하며 검출 결과를 macOS와 같은 IR item으로 변환해 sidecar를 먼저 기록한 뒤 catalog를 commit합니다.
재시작 복원과 preview/export 공통 request 투영까지 x64 Debug에서 통과했습니다. ABI 0.34는 WIC가
RGB16 visible TIFF와 Gray16/RGB16 IR companion TIFF를 bounded row decode해 detector에 직접 공급하며,
합성 paired TIFF 검출과 decode 전 취소를 통과했습니다. scanner publication 경계는 committed RGB/IR
artifact 쌍만 `sourceKind: scanner`와 optional `infraredScanPath`로 catalog에 먼저 저장한 뒤 ABI 0.34
`RunFiles`를 호출합니다. IR DLL/입력 실패는 RGB frame publication을 되돌리지 않습니다. 실제 paired 촬영
TIFF와 macOS-hosted R16/pixel golden은 아직 연결되지 않았습니다. 이 경계는 x64 Debug
`test-managed.ps1`에서 Catalog 595, Shell 353 assertions로 확인했습니다.

## 2026-08-12 Flatbed film frame grid native core

최신 macOS `FlatbedFrameGridDetector`의 제품 계약을 Windows C++20 코어로 옮겼습니다. 이 검출기는
밝기·극성으로 빈 holder 창을 고르지 않고, 세로 질감으로 실제 필름 슬롯을 찾은 뒤 물리 mm 기반
aperture, 여백 폭·pitch 범위, gap의 content 대비와 local boundary fit으로 frame grid를 만듭니다.
밝은 빈 창, 어두운 slide/masked gap, half-frame의 24×18mm 축, 취소를 x64 Debug
및 Release `native.flatbed_frame_grid`에서 확인했고 ARM64 Release target도 교차 빌드했습니다.

ABI 0.35는 이 검출기를 caller-owned luminance preview→owned result handle로 C#에 연결합니다. C#은
정규화 rectangle·confidence의 유한 범위와 handle 수명을 검증한 뒤에만 scanner host에 결과를 넘깁니다.
x64 Debug `native.flatbed_frame_grid_abi` 및 Interop 184 assertions에서 실제 DLL 왕복을 확인했습니다.
scanner host·실물 preview/macOS golden 연결은 아직 없습니다.

## 2026-08-12 GrainMend IR item replay — ABI v25

ABI v24의 flat cluster replay는 겹치는 IR cluster에서 같은 attenuation을 반복 적용해 macOS보다
과보정되는 P1 결함이 독립 검토에서 발견됐습니다. v24의 통과 결과는 이 결함 발견 전 결과이므로
완료 증거로 채택하지 않습니다.

IR item 경계를 보존하는 append-only ABI 0.32/v25를 완료했습니다. 모든 cluster correction은 같은
item-level base에서 계산하고 `bbox(attenuation > 0 ∪ core > 8)`의 전체 사각 patch만 원래 cluster 순서와
item strength로 합성합니다. cluster별 ROI scratch를 즉시 해제하고 bounded bbox patch만 보관해 대형 스캔의
whole-frame snapshot을 피합니다. v25는 item range의 contiguous·gapless·exact-once와 order 참조를 검증하고,
flat cluster 4,096개와 native expanded order 8,192개 상한을 하위 할당 전에 거부합니다.

fingerprint는 macOS canonical v2를 바꾸지 않고 attenuation 결합을 명시적 v3로 분리했습니다. v2 sidecar는
읽을 수 있으며 재저장 시 v3 identity로 이동합니다. 합성 TIFF의 v25 preview/export가 같은 recipe와 수학을
사용하고 8-bit 표시 양자화 최대 1 code 안에서 일치하며, 원본 bytes와 SHA-256이 변하지 않음을 확인했습니다.
x64 Debug/Release native 61/61, Catalog 592, Shell 336, Interop 169(ABI 0.32)가 통과했고 ARM64 Release native·
managed graph는 교차 빌드만 통과했습니다. 실제 ARM64 실행과 macOS-hosted pixel golden은 아직 없습니다.

## 2026-08-11 IR attenuation replay — ABI v24 사전 체크포인트(미채택)

최신 macOS의 비파괴 IR layer 계약을 post-baseline delta로 채택했습니다. Windows Defects sidecar v2는
기존 core mask와 별도로 optional compressed R16 attenuation을 보존하고, fingerprint·logical backup·
pending restore도 같은 authoritative bytes를 사용합니다. 필드가 없는 기존 sidecar는 mask-only
component repair로 계속 재생하며 손상 압축과 크기 불일치는 실패 폐쇄형으로 거부합니다.

Shell은 IR을 Region으로 접지 않고 ordered edit로 투영합니다. native pre-develop stage는
`RGB / max(1 - attenuation, 0.5)`를 먼저 적용한 뒤 core mask가 있으면 그 결과를 문맥으로 component
repair하고 item strength를 한 번만 혼합합니다. preview/export는 ABI 0.31의 같은 v24 request와 native
stage를 사용합니다. x64 Debug/Release native 61/61, Interop 163, Catalog 587, Shell 336 assertions가
통과했고 ARM64 Release 전체 graph의 순수 AA64 교차 빌드도 통과했습니다. ARM64 runtime 결과는 아닙니다.

이 체크포인트는 저장된 attenuation의 재생 경계입니다. 최신 macOS의 true-scale 후보 검출, local
alignment·visible confirmation, null/MAD, significance-dependent inverse-Mills bias, attenuation/core 분리,
scanner companion 입력·coordinator·WinUI와 동일 입력 macOS-hosted mask/R16/pixel golden은 남아 있습니다.
상세는 `verification/2026-08-11-ir-attenuation-replay-v24.md`입니다.

## 2026-08-10 macOS 커널 수식 대조

macOS pixel golden 은 macOS 호스트가 필요하지만, **Core Image 가 실행하는 Metal 커널 소스가
저장소 안에 있습니다.** 상수까지 1:1 로 대조했습니다.

Basic Tone, Parametric Tone Curve, Negative Inversion, Color Mixer, Color Grading, Primary
Calibration, B&W Toning, Texture 전체, Film Grain 이 **수식과 상수 모두 일치**합니다.
Film Grain 은 잡음원만 다릅니다(macOS `CIRandomGenerator` vs Windows 좌표 해시, 분포 동일).

차이는 하나 나왔고 표시 경계였습니다. 게시 경로는 오히려 Windows 가 맞았습니다 — macOS 도
8비트 출력에만 dither 를 겁니다. "macOS 에 있으니 옮긴다"로 갔으면 게시 결과를 잘못 바꿨을
것입니다. 상세는 `verification/2026-08-10-macos-kernel-audit.md`.

이 대조는 **부동소수점 결과의 동일성을 증명하지 않습니다.** 같은 수식이어도 Core Image GPU 와
Windows CPU 는 마지막 자리에서 다를 수 있고, 그건 여전히 macOS 호스트가 필요합니다.

## 2026-08-10 표시 경계 — soft clip과 dithering

macOS 소스 대조에서 미리보기 경로의 실제 차이를 찾았습니다. macOS는 8비트로 내리기 전에
`DisplayGamutMap`(hue-safe soft clip)과 `OutputDither`(±0.5/255)를 거치는데 Windows는 채널별
하드 클립과 `>> 8` 뿐이었습니다. 확장 범위 값이 색상을 끌고 잘리고, 매끄러운 하늘이
밴딩됐습니다.

`tone_safe_unit_rgb` 와 좌표 해시 dither 를 넣어 미리보기 경계를 맞췄습니다. **게시 경로는
바꾸지 않았습니다** — macOS도 8비트 출력에만 dither 를 걸고 Windows는 16비트만 게시하므로
현재 동작이 맞습니다. 실제 촬영본 export SHA-256이 그대로임을 확인했습니다. 미리보기는
전체 해상도 16비트 중간 이미지(17 MP에서 약 104 MB)도 더 이상 만들지 않습니다.
상세는 `implementation/display-boundary.md`.

## 2026-08-10 다중 IFD TIFF

사용자의 Photoshop TIFF 가 거부되던 원인은 사진이 아니라 **디렉터리가 두 개**라는 것이었습니다.
전체 이미지 뒤에 축소 미리보기가 붙는 흔한 배치입니다. `NewSubfileType` 으로 동반 페이지를
구분해 전체 이미지가 정확히 하나일 때만 진행하고, 다중 페이지 문서는 어느 것이 그 사진인지
추측하지 않고 계속 거부합니다.

디코더에서 WIC 프레임 번호가 디렉터리 번호와 같다는 가정이 틀렸다는 것도 확인했습니다. WIC 는
축소 해상도 페이지를 프레임으로 노출하지 않아 디렉터리 2개 파일이 프레임 1개로 도착합니다.
probe 가 정한 치수와 일치하는 프레임을 고르도록 바꿔 양쪽 모두에서 성립하게 했습니다.
상세는 `implementation/multi-directory-tiff.md`.

## 2026-08-10 현상 속도와 취소·진행률

실제 촬영본의 단계별 벽시계를 처음 재고, 시간이 실제로 있던 곳을 고쳤습니다. `develop`(반전)과
`tone` 은 완전한 pointwise 커널인데 16 M 픽셀을 한 스레드에서 돌고 있었습니다. 행 블록 병렬
실행을 공용 `negaflow/core/parallel_rows.h` 로 넣고 반전·톤·포인트 커브·Color Mixer·Color
Grading·Primary Calibration·ColorModel·sRGB16 변환·픽셀 검증에 적용했습니다.

`develop 1,887 → 246 ms`, `tone 2,057 → 285 ms`, 미리보기 경로 약 `4,112 → 721 ms`(5.7배).
**출력 PNG16 의 SHA-256 은 조정 끔·켬 두 구성 모두 변경 전과 동일**하므로 속도만 바뀌고 결과는
바뀌지 않았습니다. 상세는 `implementation/parallel-row-execution.md`.

이어서 오래 비어 있던 ABI 공백인 취소와 진행률을 v22/0.28 로 채웠습니다. 콜백이 경계를 넘지
않는 caller 소유 정수 3개이며, 단계 경계·TIFF 디코드 행 덩어리·source 해시에서 협조적으로
취소합니다. 게시가 시작된 뒤에는 반쪽 파일을 남기지 않기 위해 의도적으로 확인하지 않습니다.
상세는 `implementation/develop-run-state-v22.md`.

실촬영 컬러 네거티브(OpticFilm 8100, 5088×3401) 체크포인트에서 두 변경을 확인했고, 그 과정에서
실촬영 fixture 경로가 잘못돼 테스트 11개가 조용히 죽어 있던 것과 그 안의 낡은 기대 3건을
고쳤습니다. 근거는 `verification/2026-08-10-real-negative-checkpoint.md`.

| 항목 | 상태 | 증거 |
|---|---|---|
| exact macOS baseline | 고정 | `baseline/bootstrap-manifest.json` |
| canonical source asset hash | bootstrap 완료 | `baseline/source-assets.sha256` |
| 개발 도구 | 검증 | Visual Studio Community 2026 18.8.2, MSVC 14.51 x64/ARM64, SDK 26100, .NET SDK 10.0.302/runtime 10.0.10, C# Windows App SDK component |
| x64 CMake configure/build/run | 통과 | Debug/Release clean configure·build·CLI 실행 |
| x64 native tests | 통과 | 2026-08-11 Debug/Release CTest **61/61** 통과. IR attenuation stage와 실제 ABI preview/export 회귀 포함 |
| 관리 시험 수 (현재) | 통과 | x64 Release Catalog **592**, Shell **336**, Interop **169** assertions 통과. Interop ABI 0.32 |
| 현상 속도 (16 논리 코어) | 측정 완료·비트 동일 | 3278×4944 에서 develop `1,887 → 246 ms`, tone `2,057 → 285 ms`. 5088×3401 미리보기에서 FilmScanDenoise `15,004.7 → 2,949.7 ms`(5.09배), Texture `3,904.7 → 774.2 ms`(5.04배), identity `2,997 → 552 ms`(5.43배), Local Dodge/Burn 조정당 `585 → 221 ms`(2.65배). 출력 PNG16 SHA-256 과 denoise/texture/dodge-burn 미리보기 fingerprint `b539956ad3c46820`/`a63cd4c01b4c1e10`/`7c8a60ab475f270d` 가 엔진 전역 인라인 강제 빌드와 동일 |
| 필름 베이스 자동 추정 | **macOS 대조 완료·실측 확인** | `FilmBaseEstimator.swift` 659줄을 함수·상수 단위로 재대조해 전부 일치 확인(후보 판정, 응집 모드·강등, 비필름 제외·팽창, 연결 성분, 가장자리/분산 표본, 보더 폴백, 선택 순서). 사용자 실제 OpticFilm 컬러 네거티브 **15장 전부가 1차 경로(connected component)** 로 측정되고 Dmin 이 `R>G>B` 오렌지 마스크와 일치. 가장자리·분산·스트립·고정 상수 폴백은 한 번도 사용되지 않음 |
| 자동 보정 | 네이티브·ABI·셸 연결 완료 | ABI `nf_auto_adjust_v1`(0.29)은 미리보기 BGRA8 을 그대로 받는 분석 호출이라 새 요청 struct 가 없습니다. `AutoAdjustCoordinator` 가 톤·warmth/tint 를 0 으로 되돌린 사본을 렌더해 재고 결과를 **대입**합니다(누적 아님). WinUI 버튼은 UI 단계 |
| 소프트 프루프 (용지·잉크) | 네이티브·ABI·셸 연결 완료 | ABI `nf_develop_preview_v23`(0.30)에만 프루프 인자가 있고 **내보내기에는 없습니다** — 인화물이 보기용 시뮬레이션을 담을 경로 자체가 없습니다. macOS 와 같은 `wtpt`/`bkpt` ÷ D50 계산, `scale = max(0, white-black)`, `bias = black`, 상한 1.2/0.3. **v2 프로파일 함정 해결**: Windows 시스템 sRGB·Adobe RGB 는 `wtpt` 에 보정되지 않은 D65 를 담고 있어 곧이곧대로 쓰면 화면이 파래집니다. matrix/TRC RGB 는 색소 합에서 D50 상대 흰색을 얻고, LUT(실제 인쇄) 프로파일은 측정된 용지를 그대로 씁니다. **설치된 RGB 출력 프로파일 4개로 실촬영 네거티브를 렌더한 결과가 프루프 없는 렌더와 전부 바이트 동일.** 비용 82.4 → 82.1~83.8 ms(잡음 안). WinUI 연결은 UI 단계 |
| 소프트 프루프 (gamut 경고·공간 변환) | 미구현 | macOS 는 프루프 공간으로 렌더해 프린터 gamut 밖 색이 잘리는 것을 보여주고, `DestinationGamutWarning` 이 ColorSync gamut-check 로 재현 불가 픽셀에 빨간 오버레이를 그립니다. Windows 대응은 mscms `CreateMultiProfileTransform`/`CheckBitmapBits`. 다음 백엔드 작업 |
| 자동 보정 (계산) | 네이티브 계산 구현 | macOS `AutoAdjust` 는 실제로 불리는 사용자 기능인데 Windows 에 없었음. 히스토그램 percentile 을 톤 슬라이더 전달함수로 역산하는 Auto Tone 과 근중립·Minkowski p=6 기반 부분 보정 Auto WB 를 이식. 노출은 밝히는 방향만, 하이라이트/섀도는 복구 전용. **실촬영 검사는 중립 현상본이 부실해 모든 값이 클램프까지 감 — 품질 증거 아님.** ABI·셸 연결 미구현 |
| macOS 커널 수식 대조 | 9개 단계 일치 | Basic Tone·Parametric Curve·Negative Inversion·Color Mixer·Color Grading·Primary Calibration·B&W Toning·Texture·Film Grain 이 상수까지 일치. Film Grain 은 잡음원만 상이. 부동소수점 결과 동일성은 별개이며 여전히 macOS 호스트 필요 |
| 표시 경계 | 미리보기 정렬 | macOS `toneSafeUnitRGB` 와 같은 hue-safe soft clip 과 ±0.5/255 dither 를 8비트 미리보기 직전에 적용. 게시 경로는 불변(16비트는 macOS 도 dither 없음)이며 실촬영 export SHA-256 동일. 전체 해상도 16비트 중간 이미지 제거. 흑백 중립성 회귀는 표시 dither 를 반영해 채널 최대 차이 1 코드 허용 |
| 취소·진행률 | ABI v22/0.28 통과·셸 연결 | caller 소유 run state 정수 3개, 단계 경계·디코드 행 덩어리·source 해시·GrainMend 내부(morphology 9패스·scratch 각도 묶음·타일)에서 협조적 취소, 게시 시작 뒤에는 의도적 미확인. 실촬영 5088×3401 에서 `decode` 취소가 `60.9 ms` 반환(미취소 export `3,323 ms`), GrainMend 켠 미리보기가 `2,014.7 → 835.0 ms`. 셸 `PreviewCoordinator` 가 겹친 요청에서 진행 중 렌더를 취소하고 취소 결과는 배달하지 않음 |
| ARM64 cross build | 통과 | Debug/Release 전체 target build, CLI/DLL PE `AA64` |
| ARM64 native run | 미검증 | 실제 ARM64 Windows runner 필요 |
| .NET 10/C ABI Interop | ABI v25 통과 | item range를 보존하는 append-only ABI 0.32/v25, layout·contiguous/gapless/exact-once range·order·capacity 검증과 실제 preview/export 회귀 통과 |
| 네이티브 파이프라인 라이브러리 | 분리 완료 | `negaflow_pipeline` 이 `develop_and_export` 와 Film Look workspace 를 소유. CLI 는 workspace 를 이 라이브러리에서 링크. CLI 자체 순서 코드의 수렴은 미완 |
| WinUI shell | 첫 관통 경로 통과 | component package 1.8 locked graph, x64 실제 최대화 실행, ARM64 교차 빌드, 6개 언어, 오른쪽 caption inset, Settings와 SHA 기본 `끔`; 2026-08-10 Shell 316 assertion 통과 |
| static runtime 배포 기반 | 통과 | Release CLI 직접 dependency가 Windows 기본 DLL 5개뿐이며 VC++ Redistributable DLL 없음 |
| float32 pixel contract | 부분 구현 | checked layout/stride/capacity, extended RGB, straight alpha, NaN/Inf 거부 |
| scalar pointwise·spatial | 부분 구현 | 4상태 film type, 현상 전 ordered region/IR attenuation→optional core repair/Clone Stamp/Brush Defects, 반전 직후 opt-in Auto Levels/Neutral Balance, documented character와 matched-pair 상대 signature를 갖춘 4종 ScannerTargetGrade, evidence-gated EXPIRED RescueGrade, 15종 ScannerProfileGrade와 ColorModel, tone/color, Film Emulation·DigitalFilmLook, GrainMend, FilmScanDenoise, 4종 Local Dodge/Burn mask, Texture, B&W 중립화·토닝, ImageTransform을 macOS 순서로 연결. x64 Debug/Release 통과; ARM64 runtime·macOS numeric golden은 미검증 |
| Film Look source routing | film·digital 공통 수직 경로 통과 | macOS correctness fix에 따라 film scan은 profile 선택과 무관하게 identity. rendered digital은 color/motion 27종 또는 B&W 15종의 kind가 process와 맞을 때만 각 고정 그래프를 실행하며, 불일치는 identity. 실제 룩이 실행될 때만 Texture grain/halation 중복을 막음. 새 16종의 macOS pixel golden과 정식 UI control surface는 미구현 |
| Catalog Develop route | SQLite→C ABI→WinUI 첫 연결 통과 | color/B&W와 negative/positive를 독립 축으로 투영해 4상태 film type을 보존. positive film/digital은 base·반전을 건너뛰고 tone/target/post pipeline을 공유. legacy marker·강도 1.0 호환, 새 강도 0.5, unknown field 보존, invalid 조합 fail-closed. 전체 macOS Develop control surface는 미구현 |
| 세로 슬라이스 (catalog→C ABI→WinUI) | 앱 안에서 한 바퀴 완결·미리보기 연결 | Import→필름 base 슬라이더→노출→Export 를 UI Automation 으로 실제 조작해 `Exported 631×403 in 101 ms` 확인. base 슬라이더 범위가 엔진의 0.001..1.0 을 그대로 받음. 시작 시 `library.sqlite` 생성·lock 획득. ABI 0.6 미리보기를 `WriteableBitmap` 캔버스에 표시하고 겹친 요청은 마지막 상태를 보존. macOS와 동일한 정식 Develop UI, base picker, 취소·진행률은 미구현 |
| catalog SQLite 영속성 | 검증 커밋·Defects sidecar·backup·pending restore 통과 | 새 연결 full canonical readback, 커밋 전용 UUID rollback snapshot, revision-aware Defects v2 sidecar와 optional compressed R16 attenuation, 논리 backup 세대, restart-only pending restore, 현재 catalog safety generation, future version 차단과 applied cleanup fence. x64 Debug/Release Catalog 587 assertions. process-kill/disk-full/power-loss 검증은 미구현 |
| catalog logical backup generation | authoritative v3 통과 | canonical `library.json`과 모든 선언된 Defects sidecar, v3 manifest, byte count·SHA-256, monotonic sequence, staging 전체 검증 뒤 write-through rename, valid 세대만 기본 3개 retention. future/damaged 세대는 prune하지 않으며 restore도 catalog와 sidecar를 같은 세대로 교체 |
| catalog 단일 작성자 강제 | 구조로 강제·프로세스 경계 관측 | `SqliteCatalogStore`는 `internal`. 공개 입구는 `CatalogSession` 하나이며 프로세스 lock 을 못 잡으면 세션이 만들어지지 않음. `NotFound`→빈 라이브러리 변환은 `ReadOrCreate` 한 자리뿐이고 손상·미지원 version 은 거기서도 실패. lock 없이 되는 것은 `CatalogRecovery.IsValidCatalogSource` 확인뿐 |
| catalog 성능 (5만 frame) | 목표 규모 측정 완료 | 최초 쓰기 527ms, 전체 읽기 255ms, 무변경 재저장 343ms, 1건 편집 337ms, 전체 뒤집기 582ms, 파일 10.1MB. 비용이 변경량이 아니라 catalog 크기에 비례함을 기록 |
| 관리 계층 SQLite 의존성 | 고정·취약점 0 | `Microsoft.Data.Sqlite.Core` 10.0.10(MIT) + `SQLitePCLRaw.config.e_sqlite3` 3.0.5 + `SourceGear.sqlite3` 3.53.4(Apache-2.0). 편의 package 는 CVE-2025-6965 native 하한 때문에 배제(ADR-0025) |
| 배포 payload 제3자 native | 최초 도입·범위 축소 | `e_sqlite3.dll` 2종. 네이티브 엔진의 제3자 0개는 유지되나 제품 payload 는 더 이상 0개가 아님. 비Windows RID 28종 제외로 53,571,344→3,788,288 바이트 |
| scalar negative inversion | 부분 구현 | color/B&W `shoulder-print-response-v4`, 고정 float bits와 합성 anchor test |
| 수동 negative develop | 첫 수직 경로 통과 | 채널별 Dmin, color/B&W 고정 response, macOS와 같은 uniform pixel-center bilinear 장면 범위 proxy, working buffer 제자리 변환과 scalar exact 일치 |
| Auto negative FilmBase | sampled-grid·선택·통계 계약 정렬 | 폭 32...256, 가로축 단일 scale, pixel-center bilinear와 transparent-black 경계로 만든 한 격자를 연결 성분·비필름 제외·continuous/distributed/strip 경로가 공유. 첫 하위 성분 강등, 상위 R−B 중앙값, Double edge/coverage와 affine scene-edge를 정렬. Float RGB 뒤 luma·percentile·MAD·threshold·채널 통계는 Double이고 최종 공개 Dmin만 Float. 같은 입력의 macOS Core Image float golden은 미검증 |
| 실촬영 15장 batch | 통과 | OpticFilm 8100 전체 15장이 현상·게시까지 통과. 합계 78,103ms, 장당 평균 5,207ms(17.3MP), peak working set 389.46MiB, 원본 15개 SHA-256 불변. 동시 batch 와 공간 필터 켠 batch 는 미측정 |
| 8비트 TIFF 입력 | 통과 | 레이아웃 게이트만 넓히고 하위 경로는 무변경. WIC 바이트 복제(`v * 257`)가 working 변환 뒤 `v / 255` 와 정확히 일치함을 실제 파일 채널 극값과 합성 전체 픽셀 회귀로 확인 |
| 다중 IFD TIFF | 수직 경로 통과 | `NewSubfileType` 으로 축소 미리보기·투명도 마스크 동반 페이지를 구분하고 전체 이미지가 정확히 하나일 때만 진행. 다중 페이지 문서는 계속 거부. 디코더는 프레임 번호를 디렉터리 번호로 가정하지 않고 probe 치수와 일치하는 프레임을 고름(WIC 는 축소 페이지를 프레임으로 노출하지 않음). 종전 거부되던 Photoshop 5100×3408 파일이 게시까지 통과하고 단일 IFD 결과는 byte-exact |
| TIFF bounded probe | 부분 구현 | Classic/BigTIFF, endian 양쪽, strip/tile bounds, compressed-byte 합계, 선택형 LZW code-stream 의미 검사·작업량 상한·취소, Unicode read-only CLI, 손상 합성 corpus |
| WIC TIFF decode | 수직 경로 통과 | 단일 read-only stream preflight/decode, Microsoft 기본 decoder 고정, RGB/RGBA 16-bit none/LZW/Deflate, LZW와 zlib/Deflate 독립 의미 검사 필수, ICC 추출, decoded-byte 사전 한도, sink 기반 행 streaming·취소·진행률; 사용자 TIFF 15/15 |
| scanner→working color | 수직 경로 통과 | untagged linear raw 9개와 embedded ICC→ICM→sRGB16→linear float 6개, 64행 streaming 15/15, whole-frame 최종 float exact 일치 15/15 |
| PNG16 output | phase 0 수직 경로 통과 | working→sRGB16, Microsoft WIC encode, 등록 sRGB ICC, 구조·전체 pixel·profile readback, 기존 파일 비덮어쓰기와 같은-directory 게시 |
| TIFF16 output | phase 1 수직 경로 통과 | 무압축 RGB16 Classic TIFF, 단일 IFD, 최소 metadata allowlist, 전체 pixel·ICC readback, 원본 상태 관찰, 단계별 CLI report와 비덮어쓰기 게시 |
| M4 최소 tone | 확장 수직 경로 통과·IR replay 연결 | region/IR attenuation→optional core repair/Clone Stamp/Brush Defects→Auto Levels/Neutral Balance→ScannerTargetGrade/RescueGrade/ScannerProfileGrade→ColorModel→tone/color→source별 Film Look→GrainMend→FilmScanDenoise→Local Dodge/Burn→Texture→B&W→ImageTransform이 공통 preview/export에서 실행. IR 자동 검출·scanner lifecycle·정식 제품 UI는 별도 작업 |
| M4 단계 진단 | 확장 수직 경로 통과 | 기본 export stage wall/process-CPU, 진단 전용 scanner/develop/tone/Film Look min/max·versioned 비암호 fingerprint, Film Look route·cube/scratch·시간 보고, tone 24·point curve 24·Color Mixer 48·Color Grading 48·Primary Calibration 48·Film Emulation 색상 48/acutance 36-value conformance |
| 이미지 SHA-256 | opt-in·source-bound 기반 통과 | 기본 `off`는 파일 I/O 0, 명시적 CNG SHA-256 known-answer/multi-chunk/cancel, 사용자 TIFF opt-in 15/15. 비어 있지 않은 Defects recipe만 렌더 정확성 경계에서 저장된 identity를 재검증 |
| 네이티브 엔진 제3자 runtime dependency | 0개 | 빈 vcpkg dependency, WIC/ICM/Win32만 사용 |
| WinUI package graph | 고정·감사 | Runtime/WinUI 1.8 component 직접 참조, transitive 명세, 취약 package 0, AI/ML/Widgets 제외, 미사용 WebView2 payload 1.6MB를 x64/ARM64 clean build 출력에서 제외 |
| 제3자 고지 | 기록 완료 | `THIRD-PARTY-NOTICES.md`에 App SDK 조건, 미배포 WebView2 경계, SQLite 스택의 MIT 1건·Apache-2.0 4건 기록. `components.json` 배포 게이트 갱신 |
| Windows 빌드 CI | 구현 완료 | `.github/workflows/windows.yml`의 native·managed·arm64-cross 잡과 로컬 짝 `scripts/ci-gate.ps1`. 러너의 VS 2026과 .NET 10.0.302를 그대로 써서 로컬과 같은 프리셋으로 빌드 |
| ColorSync↔ICM 색상 동등성 | **사용자 확인·종결** | 34패치 중 21개 비율 1.000, 깊은 섀도우에서 최대 20.37배(원인은 ColorSync의 1/16 toe). 현상 후 차이는 **암부에서 8비트 코드 2~7** 이며, 2026-08-10 사용자가 직접 확인해 **실질적으로 의미 없음**으로 종결했습니다. ADR-0024 유지 |
| GPU/WARP | 미구현 | M5 이후 |
| installer | 미구현 | .NET 10과 Windows App Runtime 1.8 prerequisite 연결. **코드 서명은 철회(ADR-0027)** — 서명 없이 배포하므로 MSIX 가 아니라 WiX/Inno Setup 이며 SmartScreen 경고를 감수합니다 |
| ARM64 실기 | 사용자 담당 | 이 저장소는 교차 빌드까지만 검증합니다(ADR-0027) |

## 2026-08-09 Chroma post-pipeline backend

고정 macOS baseline `2fa1d6297378673b58b8bec72025e968ccc3125c`의 실행 순서를 기준으로
Film Look 뒤에 GrainMend → FilmScanDenoise → Local Dodge/Burn → Texture를 native 공통
preview/export 경로로 연결했습니다. GrainMend는 ABI v8, FilmScanDenoise는 v9, Texture는 v10의
append-only suffix로 먼저 연결했습니다. Local Dodge/Burn은 이 단계에서 brush/radial/linear/polygon
native core를 닫았고, 아래 v12 후속 작업에서 가변 point/stroke ABI와 catalog projection까지 완료했습니다.

검증은 x64 Debug에서 다음 두 경로만 실행했습니다.

- `ctest --preset x64-debug -R '^native\.(grain_mend|film_scan_denoise|local_dodge_burn|texture_stage|develop_export_abi)$' --output-on-failure`: 5/5 통과
- `scripts/test-interop.ps1 -Preset x64-debug`: build 경고 0·오류 0, interop 75 assertions, ABI 0.16 x64 통과

새 단계의 ARM64 cross/runtime, 전체 x64 Release gate, 실제 대형 스캔 성능, macOS Core Image numeric
golden, GPU/WARP 경로는 이번 변경에서 검증하지 않았습니다.

### B&W finalization과 ImageTransform

같은 fixed baseline의 Texture 다음 순서를 이어 B&W film은 Rec.709 계수로 최종 중립화하고, 선택된
Selenium/Sepia 모드에 macOS `bwToning` kernel과 같은 HSV tint·tone mask·density 수식을 적용합니다.
그 뒤 flip H → flip V → 90도 회전 → 최대 내접 straighten → y-up normalized crop 순서의
`ImageTransform`을 적용합니다. 두 단계 모두 preview/export 공통 경로이며 alpha를 보존하고 malformed
recipe는 pixel을 폐기해 fail-closed 합니다.

ABI v11은 v10 byte prefix 뒤에 B&W toning과 fixed-size transform recipe를 append했고 ABI를 0.17로
올렸습니다. x64 Debug에서 새 native 2개와 실제 TIFF v11 preview를 포함한 ABI test 3/3, 관리 build
경고 0·오류 0, interop 78 assertions를 통과했습니다. macOS numeric golden, 대형 straighten 메모리·성능,
ARM64 cross/runtime과 Release gate는 아직 실행하지 않았습니다.

### DigitalFilmLook 전체 그래프

고정 macOS baseline의 실제 활성 그래프를 기준으로 rendered digital을 네거티브 반전 없이 decoded
positive working image에서 시작하게 했습니다. 처리 순서는 DigitalHalation → FilmEmulation 색상/acutance →
0.5배 DigitalFilmColorPreset → density-domain DigitalFilmGrain입니다. 11종 stock의 물성·색상 preset을
고정 source와 맞췄고, 사용자 grain/halation override가 있으면 stock 기본 강도 대신 사용합니다. digital
film이 활성일 때 뒤의 공통 Texture grain/halation은 0으로 만들어 같은 효과가 두 번 적용되지 않게 했습니다.

x64 Debug에서 새 코드를 재빌드한 뒤 현상 핵심 targeted native 9/9와 ABI 0.17 interop 78 assertions가
통과했습니다. halation의 512픽셀 tile 경계, warm halo와 alpha 보존, grain 결정성·density 반응, 서로 다른
stock color 방향, 실제 TIFF v11 digital preview route를 확인했습니다. macOS `CIRandomGenerator`에는 공유
seed가 없으므로 grain은 현재 Windows 절대 좌표 hash로 재현 가능하게 만들었으며, macOS와는 통계적
동등성만 주장합니다. embedded/assigned ICC가 없는 rendered-digital TIFF 입력 해석, macOS 수치 golden,
대형 이미지 peak memory, ARM64 runtime과 GPU/WARP는 아직 검증하지 않았습니다.

### Local Dodge/Burn v12, ColorModel v13, Scene Correction v14

가변 brush/radial/linear/polygon recipe를 macOS JSON key 그대로 catalog에 보존하고 Shell 요청에서
caller-owned flat point/stroke 배열로 투영했습니다. ABI v12는 동기 호출 동안 이를 복사해 공통
preview/export stage에 전달합니다. 이어 macOS `ColorModel`의 warmth→tint→colorDepth→vibrance→
saturation→RGB primary 순서를 반전 직후·톤 매핑 전에 연결하고 catalog부터 ABI v13까지 노출했습니다.
고정 행렬 축은 같은 계수를 사용하며, `CIVibrance`는 Windows CPU 저채도 우선 구현이라 macOS 수치 보정이
남아 있습니다. 이어서 opt-in `autoLevels`와 `autoNeutralBalance`를 macOS 순서와 수식으로 반전 직후에
연결했습니다. Auto Levels는 256px 채널 percentile, Neutral Balance는 192px median과 32-sample
gamma cube 보간을 사용합니다. x64 Debug scene-correction 1/1, Catalog 446, Shell 304, Interop 91
assertions(ABI 0.20)이 통과했고 실제 TIFF v14 활성 preview pixel 차이를 확인했습니다.

### EXPIRED RescueGrade와 DevelopTarget v15

macOS `EXPIRED`는 aged look이 아니라 보수적인 복구 target입니다. Windows도 192px 장면 표본에서 최소 3개
밝기 구간, 6개 공간 tile, 낮은 Lab 산포와 결정적 holdout 일치를 모두 만족할 때만 중립축 드리프트를
보정합니다. 건강한 장면과 흑백은 exact no-op이며 endpoint와 extended RGB는 보호합니다. `developTarget`의
7개 저장값을 catalog→Shell→ABI v15로 연결했습니다. x64 Debug RescueGrade/실제 TIFF ABI 2/2,
Catalog 447, Shell 304, Interop 92 assertions(ABI 0.21)이 통과했습니다.

### ScannerProfileGrade와 ABI v16

macOS ScannerProfiles manifest v2의 15개 immutable profile에서 grade가 실제로 소비하는 bounded
tone·color·texture 수치와 profile hash만 Windows 네이티브 registry로 고정했습니다. 런타임
JSON parser와 변경 가능한 resource 경로 없이 gamma→contrast/saturation→vibrance→명부 보호
film tint→tone curve→bounded unsharp 순서를 CPU로 실행합니다. 알 수 없는 profile ID는 macOS의
optional registry load와 같이 exact no-op입니다. `scannerProfileID`를 Catalog BaseRecipe→Shell→ABI v16→
native preview/export로 연결했습니다. x64 Debug native ScannerProfileGrade/ABI 2/2, Catalog 447,
Shell 304, Interop 93 assertions(ABI 0.22)가 통과했습니다.

### ScannerTargetGrade 4종 공용 파이프라인 연결

NORITSU/SP-3000/F135/HR의 macOS documented character를 장면 범위 tone anchor, Lab neutral·hue·chroma,
extended-domain bounded blend로 독립 구현했습니다. positive source는 절반 강도, 흑백은 tone·texture만
적용하며 NORITSU에는 guarded luminance texture를 더합니다. 이어 manifest v2에서 roll-label provenance와
관측 범위가 실제로 맞는 Ektar 100·Portra 160 쌍만 컴파일해 NORITSU/SP-3000 상대 signature를 추가했습니다.
프로파일이 없으면 두 쌍의 일관된 공통 성분, paired profile을 명시하면 해당 필름 성분을 사용하고,
pair가 없거나 target과 scanner가 다르면 상대 효과를 만들지 않습니다. F135/HR도 문서 기반 character만
유지합니다. 네 타깃은 ABI v15의 기존 DevelopTarget과 v16 scanner profile ID를 그대로 사용하므로 ABI
증가는 없습니다. x64 Debug에서 `native.scanner_target_grade`와 `native.develop_export_abi` 2/2가 통과했고
네 타깃의 구별, 공통·필름별 signature 차이와 공용 preview 선택을 확인했습니다. macOS numeric golden과
positive film profile 경로는 아직 미구현·미검증입니다.

### 4상태 film type, ABI v17, Film Look correctness fix

Color/B&W 축을 유지하면서 negative/positive polarity를 append-only ABI v17로 분리했습니다. positive
film scan과 rendered digital은 base·반전을 건너뛰고 positive scene correction, target, tone과 공통
post-pipeline을 사용합니다. B&W positive는 마지막에 중립화됩니다. macOS commit
`6b51695e747aa5d98531b8abee3c110a2531c0c7`의 버그 수정에 맞춰 film scan Film Look은 profile 선택과
무관하게 identity이며, 현재 color stock은 B&W digital process에 적용하지 않습니다. ABI는 0.23이고
x64 Debug native 42/42, Interop 95, Catalog 447, Shell 304 assertion을 통과했습니다.

## 2026-08-06 변경

권리·운영 점검에서 나온 변경입니다. 이 날짜에 x64 Release clean 네이티브 빌드와 `ctest` 37/37,
관리 solution clean 빌드(경고 0·오류 0)와 관리 테스트를 다시 실행해 확인했습니다.

- 저장소 루트에 `.gitattributes`(`* text=auto eol=lf`)를 추가했습니다. 그 전에는 Windows 체크아웃이
  CRLF 작업 사본을 만들어 `verify-provenance.py`의 리소스 SHA-256이 어긋났고, Windows에서 게이트를
  전혀 돌릴 수 없었습니다. 이제 로컬에서 통과합니다. blob은 원래부터 LF였으므로 저장소 내용은
  바뀌지 않았습니다.
- 미사용 WebView2 payload를 셸 출력에서 제외했습니다(ADR-0022).
- 제3자 고지를 `THIRD-PARTY-NOTICES.md`로 기록했습니다.
- macOS golden의 관측 경계를 ADR-0021로 고정했습니다.

build ID는 빌드 당시 미커밋 작업이 있으면 `-dirty`로 표시합니다. ARM64 test executable은 빌드됐지만 x64
호스트에서 실행하지 않았으므로 ARM64 runtime 통과로 표시하지 않습니다.

## 2026-08-07 변경

카탈로그가 처음으로 디스크에 남습니다. 근거는 `verification/2026-08-07-sqlite-catalog-store.md`,
결정은 ADR-0025입니다. 이 날짜에 `ci-gate.ps1 -Preset x64-release` 전체(네이티브 40/40, 관리
303+188 assertion과 interop 44, 경고 0)와 ARM64 관리 교차 빌드, `verify-provenance.py`를 다시 실행했습니다.

- `SqliteCatalogStore`를 추가했습니다. macOS의 table 배치를 그대로 옮기되 물리 schema version과
  논리 catalog version을 분리하고, 없는 파일·손상 파일·미래 물리 version·외부 논리 version·
  malformed payload를 각각 다른 값으로 거부합니다. 어느 것도 빈 라이브러리가 아닙니다.
- 재정렬에서 `position` UNIQUE 제약을 어기는 경로를 찾아 relocation 단계를 넣었습니다. 단계를
  빼면 frame 3개를 재정렬하는 것만으로 쓰기가 실패하는 것을 확인했습니다.
- `CatalogSession`으로 프로세스 lock 과 store 를 묶었습니다. store 를 `internal`로 내려
  lock 없이 카탈로그를 여는 공개 경로를 없앴습니다. 규율이 아니라 구조로 막습니다.
- 편의 package `Microsoft.Data.Sqlite`를 배제했습니다. native SQLite 하한이 CVE-2025-6965 대상이라
  restore 자체가 NU1903으로 실패합니다. 추측이 아니라 restore 출력에서 걸린 것입니다.
- 비Windows RID의 native payload 28종을 빌드 출력에서 제외했습니다. 53,571,344 → 3,788,288 바이트.
- **제품 payload에 제3자 native 바이너리가 처음 들어왔습니다.** 네이티브 엔진의 제3자 0개는
  그대로지만 두 문장은 이제 다른 뜻이므로 고지 문서에서 구분했습니다.
- `nf_develop_export_v1` 로 파이프라인 전체를 C ABI 에 노출했습니다. 그 전까지 셸이 프레임 한 장을
  현상하려면 CLI 프로세스를 띄우는 수밖에 없었습니다. 순서 코드를 복사하지 않기 위해 CLI 안에
  있던 것을 `negaflow_pipeline` 정적 라이브러리로 꺼냈습니다.
- ABI 를 0.2 로 올리고 관리 loader 의 최소 minor 도 올렸습니다. 낡은 엔진은 첫 export 호출이 아니라
  load 시점에 거부됩니다.
- `dumpbin /dependents` 로 확인: imaging·output 을 링크한 뒤에도 `Negaflow.Native.dll` 의 직접
  import 는 `KERNEL32`, `SHLWAPI`, `ole32`, `mscms` 뿐입니다. 네이티브 엔진의 제3자 0개는 유지됩니다.

전체 M0~M18 로드맵 진행률은 산출물 기준 약 31%, 현재 M0~M3 기반 구간은 약 66%로 추정합니다.
`M14 영속성`은 SQLite 왕복·revision-aware Defects sidecar·backup 세대·pending restore까지 올라왔으나
destructive fault harness가 남아 있으므로 완료로 세지 않습니다. 색상 수직 경로가 실제 코퍼스를 처리했다는 사실과
ColorSync 수치 동등성은 계속 구분합니다. 산정 방식과 단계별 공백은 `progress/overall-roadmap.md`에
있습니다.

## 2026-08-09 재검증과 문서 동기화

현재 코드가 ABI 0.5 미리보기와 WinUI 캔버스 렌더까지 포함하는데도 이 문서와
`progress/next-steps.md`가 ABI 0.4와 “미리보기 미구현/다음은 import” 상태에 머물러 있던 것을
수정했습니다.

- `scripts/ci-gate.ps1 -Preset x64-release`: native CTest 30/30, Catalog 303 assertion,
  Shell 200 assertion, managed build 경고 0·오류 0.
- `scripts/test-interop.ps1 -Preset x64-release`: Interop 44 assertion, ABI 0.5, x64.
- `py negaflow-mac/scripts/ci/verify-provenance.py`: 파일 1,764개, text 1,721개, binary 43개,
  선언 resource 29개, reachable commit 137개 검증 통과.

이번 재검증에서는 ARM64 교차 빌드나 실제 ARM64 실행을 다시 수행하지 않았습니다. 위 표의 기존
ARM64 교차 빌드 증거는 유지하지만 실제 ARM64 runtime은 계속 미검증입니다.

## 2026-08-09 Base recipe catalog projection

`params.baseEstimationMode`, `filmStockDminID`, `lightSourceProfileID`,
`scannerProfileID`를 기존 `manualBaseRGB`와 독립적으로 Catalog projection에
보존합니다. 이 저장 경계는 이후 Auto v2 resolver가 추가돼도 그대로 유지됩니다. Film preset
Dmin/Dmax/light-source resolver, scanner profile grade, WinUI mode/picker, canvas
base picker는 아직 없습니다. Catalog unit test는 이후 Auto 계약을 포함해 x64 Debug 315 assertions가
통과했습니다.
수동 Base RGB를 편집하면 기존 preset ID는 보존한 채 `baseEstimationMode`를 `Manual`로
기록합니다. 따라서 저장된 recipe가 실제 수동 Dmin 현상 경로와 모순되지 않습니다.

## 2026-08-09 Scene-ranged manual negative

수동 Dmin 현상은 충분한 linear working image에서 64…320 폭의 6% inset 표본을 사용해
채널별 low-percentile density range를 구합니다. base luma gate, chromogenic dark-pixel gate,
1.8D/0.4D 하한과 low-DR smoothstep 축소를 적용하며, B&W는 기하 평균 하나를 세 채널에
공통 적용합니다. 작은 입력은 기존 film-type normal range로 되돌아가고, malformed input은
기존처럼 fail-closed로 픽셀을 공개하지 않습니다. 일반 2:3 세로 frame의 macOS 320×480 표본은
보존하고, 더 극단적인 panoramic input만 통계용 표본 153,600개로 제한합니다. macOS full Auto
estimator와 Film preset resolver는 이 뒤의 별도 slice에 기록합니다.

x64 Debug native CTest 30/30과 `native.manual_negative_developer`의 색상 channel별
1.10/0.99/0.88D, B&W 공통 range 회귀 검사가 통과했습니다.

## 2026-08-10 Scene-range affine proxy parity

macOS `NegativeInversion.sampleStats`는 가로축에서 구한 단일 affine scale을 두 축에 같이 적용하고,
출력 pixel center를 bilinear로 표본화합니다. Windows 장면 범위 proxy만 각 축을 독립 정수 최근접으로
읽고 있어 짧은 축 반올림과 고주파 필름 스캔에서 채널별 Dmax가 달라질 수 있던 경로를 수정했습니다.
공용 `bilinear_rgb_sampler.h`가 uniform scale, pixel-center 역변환과 transparent-black 경계를 소유하며
muted-scene saturation proxy도 같은 좌표 계약을 재사용합니다.

640×65 fixture의 R은 열마다, G는 행마다 0.08/0.16을 교차시키고 B는 0.12로 고정했습니다. 0.5배
affine proxy라면 세 채널 모두 0.12가 되어 Dmax가 `log10(0.8/0.12)`로 일치해야 합니다. 이 회귀를
포함해 x64 Debug 전체 native 44/44, x64 Release 인접 3/3이 통과했고 ARM64 Release manual-negative test,
CLI와 DLL이 교차 빌드됐습니다. 실제 ARM64 실행과 같은 입력의 macOS 최종 pixel golden은 아닙니다.
상세는 `verification/2026-08-10-negative-scene-range-affine.md`에 기록합니다.

## 2026-08-10 Muted-scene vibrance

비프리셋 컬러 네거티브는 scene-ranged 반전 직후 linear working image를 최대 160px 폭으로
bilinear 표본화하고 HSV `S=(max-min)/max` 평균을 측정합니다. macOS와 같은
`amount=clamp((0.24-meanSaturation)*3, 0, 0.5)` 및 `amount > 0.01` gate를 적용하며, 기존
ColorModel vibrance와 같은 독립 Windows 저채도 우선 수학을 사용합니다. 측정과 적용은 전체 프레임
복사 없이 수행되고 preview/export 공통 `develop_manual_negative` 경로에 있습니다. preset, B&W,
4px 이하 입력과 이미 채도 높은 장면은 exact identity입니다.

x64 Debug 전체 native CTest 42/42와 Release의 `native.manual_negative_developer`,
`native.color_model`, `native.develop_export_abi` 3/3이 통과했습니다. ARM64 Debug/Release는 같은 세
target 교차 빌드만 통과했으며 runtime 검증이 아닙니다. 장면 gate·제외 경로는 고정했지만 Core
Image의 실제 affine sampling과 `CIVibrance` pixel 수치는 macOS fixture 비교 전이므로 수치 동등성을
주장하지 않습니다.

## 2026-08-10 Auto base 연결 성분 강건 측정

macOS 고정 기준은 연결 성분에서 선택한 밝은 절반에도 luma 중앙값/MAD 이상치 제거를 적용한 뒤
retained RGB의 채널별 중앙값을 Dmin으로 사용합니다. Windows의 1차 connected-component 경로만 이를
건너뛰던 차이를 닫고, continuous-border/distributed 경로와 같은 강건 측정 함수를 공유하게 했습니다.
같은 성분에 11개의 밝은 luma 오염 셀을 붙인 회귀에서 Dmin이 깨끗한 13개 표본의 중앙값
`(0.7212, 0.5406, 0.4003)`을 유지하는지 고정했습니다.

x64 Debug 전체 native CTest 43/43과 x64 Release `native.manual_negative_developer` 1/1이 통과했습니다.
ARM64 Release는 같은 test target과 `Negaflow.Native.dll` 교차 빌드만 통과했으며 runtime 증거가 아닙니다.
Core Image affine 축소와 Windows sampled-grid의 동일 입력 golden, 실제 TIFF Dmin·최종 pixel 비교는
여전히 남아 있습니다.

연결 성분·continuous border·distributed mask·strip fallback이 모두 성립하지 않을 때 macOS 엔진이
실행하는 마지막 scene-edge compatibility 측정도 복구했습니다. 6% 가장자리에서 유효 후보 32개 이상을
모아 채널 p90을 Dmin으로 사용하며, 이 경로까지 실패해야 color `(0.86, 0.68, 0.50)` 또는 B&W
`(0.80, 0.80, 0.80)` 상수를 사용합니다. 공간적으로 분리된 가장자리 후보 40개 회귀에서
`auto_scene_edge`와 `(0.48, 0.32, 0.16)`을 고정했습니다. 이 source는 preset의 confident measurement로
승격하지 않습니다.

## 2026-08-10 Auto FilmBase affine sampled-grid parity

macOS `FilmBaseSampleGrid`처럼 폭 `32...256`과 가로축 단일 scale에서 출력 높이를 정하고, output pixel
center를 bilinear로 읽는 격자 하나를 Auto의 연결 성분·비필름 제외·continuous border·distributed mask·
strip fallback이 공유하도록 수정했습니다. 이전에는 연결 성분과 후속 경로가 각 축 정수 비율의 최근접
격자를 별도로 만들어, 고주파 색 경계와 짧은 축 반올림에서 Dmin이 달라질 수 있었습니다.

`512×129 → 256×64` fixture가 두 축의 반 픽셀 혼합과 Dmin `(0.64, 0.48, 0.32)`을 고정합니다. x64 Debug
전체 native `44/44`, x64 Release manual-negative·develop-export ABI `2/2`가 통과했고 ARM64 Release의
두 테스트와 DLL을 교차 빌드해 PE `0xAA64`를 확인했습니다. 실제 macOS Core Image sampled-grid golden,
촬영 TIFF와 ARM64 runtime은 미검증입니다. 상세는
`verification/2026-08-10-auto-filmbase-affine.md`에 기록합니다.

## 2026-08-10 Auto FilmBase 선택·fallback 수학 parity

연결 성분 강등이 조건에 맞는 더 어두운 성분을 계속 찾지 않고 macOS처럼 첫 하위 성분 하나만 검사하게
했습니다. 두 강등 경로의 R−B는 짝수 표본의 위쪽 중앙값을 사용하고, non-film mode 후보에는 p99의
`0.10` 바닥을 적용합니다. `0.06` edge와 `0.65` coverage는 Double로 계산하며 strip RGB도 Double로
누적합니다. 마지막 scene-edge fallback 역시 uniform-scale pixel-center bilinear 표본으로 정렬했습니다.

세 성분 선택, `100×50` 정수 경계와 `640×64 → 320×32` scene-edge 위상 회귀를 포함해 x64 Debug 전체
native `44/44`, x64 Release manual-negative·develop-export ABI `2/2`가 통과했습니다. ARM64 Release의
두 테스트와 DLL은 교차 빌드됐습니다. 실제 macOS Core Image golden, 촬영 TIFF와 ARM64 runtime은
미검증입니다. 상세는 `verification/2026-08-10-auto-filmbase-selection.md`에 기록합니다.

## 2026-08-10 Auto FilmBase Double 통계 parity

macOS `FilmBaseSampleGrid`와 estimator처럼 sampled bitmap의 RGB는 Float로 유지하되, luma·percentile·
median·MAD·threshold·채널 중앙값·source 비교는 모두 Double로 승격했습니다. strip 평균도 Double로
유지하며 선택된 Dmin은 공개 `AutoNegativeBaseResult` 경계에서만 Float로 내립니다. 이전에는 Float
덧셈과 Float 상수가 `0.85` 후보 상한 바로 위의 표본을 포함할 수 있었습니다.

Float luma `0.849999964`, Double luma `0.850000003973643`이 되는 24픽셀 성분 회귀를 추가했습니다.
x64 Debug 전체 native `44/44`, x64 Release manual-negative·develop-export ABI `2/2`가 통과했습니다.
ARM64 Release의 두 테스트와 DLL을 교차 빌드해 PE `0xAA64`를 확인했습니다. 실제 macOS Core Image
golden, 촬영 TIFF, ARM64 runtime과 GPU 경로는 미검증입니다. 상세는
`verification/2026-08-10-auto-filmbase-double-statistics.md`에 기록합니다.

수동 Base R/G/B도 `InspectorSlider` composite로 교체했습니다. 이 controls는 54 DIP 편집값,
0.01/0.10 keyboard nudge와 stable AutomationId를 제공하지만 macOS 수동 Base 계약에 맞춰 reset은
제공하지 않습니다. x64 WinUI 렌더에서 Base Red `Right`의 `0.00 → 0.01`과 Export 가능 상태 전환을
확인했습니다. Auto/Film mode, picker, canvas base picker, UIA editor/고대비/compact/ARM64 runtime은
미검증입니다.

## 2026-08-09 Develop slider 첫 UI slice

임시 Develop surface의 Exposure를 `InspectorSlider` composite로 교체했습니다. 이 control은
54 DIP 편집값, 0.01/0.10 keyboard nudge, 범위·finite-value 검사, double-click reset과 기존
`negaflow.develop.exposure` AutomationId를 제공합니다. recipe, catalog, C ABI와 preview/export
수식은 변경하지 않았습니다. 값 editor는 `.value` AutomationId와 label·입력 범위 HelpText를 가지며,
`Enter`/수정한 focus-loss commit, `Escape`/수정하지 않은 focus-loss cancel, invalid input의 빨간색·beep·오류
HelpText 및 다음 입력의 오류 해제를 구현합니다. x64 Debug shell build(경고 0·오류 0), managed Catalog
314/Shell 209 assertion, native CTest 30/30과 실제 x64 WinUI 렌더·Right key `-1.00 → -0.99`를 확인했습니다.
Base의 Auto/Film/Manual contract와 최신 editor 상호작용의 UIA runtime, high contrast/compact/ARM64 runtime은
미검증입니다.
상세는 `implementation/develop-inspector-slider.md`에 기록합니다.

## 2026-08-09 Auto base v2 scene-edge slice

v1의 수동 Dmin request/result 레이아웃과 export를 유지한 채 ABI 0.6에
`nf_develop_export_v2`/`nf_develop_preview_v2`를 추가했습니다. v2는 Auto·Manual mode를
명시하고, 성공 결과에 실제 적용 Dmin과 `manual`/`auto_scene_edge`/`auto_fallback` provenance를
돌려줍니다. Preset은 stock resolver가 없으므로 Auto로 묵살하지 않고 Shell과 native validation에서
명시 거부합니다.

Auto는 decode 뒤 linear `WorkingImage`의 6% edge 표본에서 색상/중립 후보를 골라 90th-percentile
Dmin을 결정하고, 후보가 없으면 macOS의 color `(0.86, 0.68, 0.50)` 또는 B&W `(0.80, 0.80, 0.80)`
fallback을 사용합니다. 그 결과는 preview와 export가 공유하는 기존 scene-ranged inversion에 한 번만
전달됩니다. 저장된 stale manual Dmin은 Auto mode에서 request에 사용하지 않습니다. Color/B&W positive
film은 negative inversion으로 보내지 않고 Catalog/Shell에서 명시 거부합니다.

x64 Debug native CTest 30/30, managed Catalog 315/Shell 219 assertions, interop 50 assertions
(ABI 0.6)이 통과했습니다. 이 당시에는 연결 성분 외의 Auto fallback이 아직 없었으며,
이후 sampled-grid fallback update에서 비필름 배제/확장, distributed·strip fallback을 추가했습니다.
cache/diagnostic은 남아 있습니다. 정식 Auto parity나 Auto/Film/Manual mode UI 완료로 세지 않습니다.

## 2026-08-09 Auto sampled-grid fallback update

`auto_connected_component`가 성립하지 않을 때에도 동일한 32–256 linear sample grid에서
non-film dilation, continuous border, distributed mask, 그리고 strip fallback을 macOS 순서대로
실행합니다. 이 compatibility fallback은 ABI layout을 바꾸지 않고 경로별 provenance 값을 보고합니다.
x64 Debug `native.manual_negative_developer`에서 hard-bright backlight, 색상 backlight
demote, non-film masked strip, continuous border, distributed mask와 fixed fallback을 검증했습니다.
cache/diagnostic과 macOS golden fixture 기반 image-result 비교는 아직 없습니다.

같은 resolver는 B&W Auto 결과의 max/min channel ratio가 `1.25`를 넘으면 color candidate path를 한 번
재시도합니다. 이로써 chromogenic B&W의 tinted base를 channel별 Dmin으로 보존하되, color path도
측정에 실패하면 기존 neutral result를 유지합니다. x64 Debug native unit test로 이 재시도를 검증했습니다.

ABI 0.8에서는 결과 layout을 유지하면서 `auto_continuous_border`, `auto_distributed_mask`,
`auto_strip_fallback` 값을 추가했습니다. 이전 `auto_scene_edge` 값은 호환을 위해 보존하며,
새 managed enum과 native ABI test가 새 provenance 값을 검증합니다.
## 2026-08-09 Basic Tone v3 vertical slice

macOS Basic Tone recipe `contrast`, `density`, `highlight`, `shadow`, `whites`, `blacks`를 Catalog의 missing=0 reader/writer와 Shell request factory에 연결했습니다. ABI 0.9 append-only `nf_develop_export_request_v3`/`nf_develop_preview_v3`가 이 다섯 값을 native `BasicToneParameters`로 전달합니다. v1/v2 layout과 Parametric Tone Curve fields는 동결되어 있습니다.

WinUI Inspector에는 `Exposure → Contrast → Highlights → Shadows → Whites → Blacks → Density` 순서의 composite controls와 stable IDs를 추가했고, positive/digital frame에서 tone mutation을 거부합니다. x64 Debug native CTest 30/30, Catalog 317 assertions, Shell 248 assertions, interop 52 assertions(ABI 0.9)을 통과했습니다. computer-use로 Debug Shell 창은 관찰했지만 state/capture runtime 오류가 있어, 실제 WinUI render/UIA/keyboard/high-contrast/compact/ARM64 runtime 증거는 아직 없습니다.

## 2026-08-09 Film preset base v4 slice

Catalog recipe의 Film mode가 27개 bundled stock과 5개 light-source ID를 ABI 0.10 v4 request로 전달하고,
native CPU resolver가 measured-first/fallback Dmin, stock Dmax response, light gain을 적용합니다. Auto/Film/Manual
WinUI control과 stable picker IDs도 연결했습니다. v1~v3 ABI layout·entry point·Preset refusal은 유지합니다.

x64 Debug native CTest 30/30, Catalog 317 assertions, Shell 267 assertions, ABI 0.10 interop 54 assertions을
통과했습니다. 사용자가 제공한 5088×3401 16-bit TIFF는 CLI 수동 Dmin 경로로 PNG16 export까지 통과했으며 결과는
100,377,638바이트와 SHA-256 `eab2e899b9e9a913be5a141afca9835040f36d3d28dd8e3bb86dcf044b54708b`입니다.
2026-08-10에는 같은 실제 TIFF를 x64 Release ABI v4의 `kodak-portra-400` + `warm-led` Film request로
실행해 `preset_measured` Dmin `(0.2446564, 0.1377584, 0.06714519)`, 5088×3401 PNG16
101,864,918바이트, 5.33초와 원본 관찰값 불변을 확인했습니다. rendered/UIA/keyboard/high-contrast/
compact/ARM64 runtime, canvas picker/reset과 같은 입력의 macOS pixel golden 비교는 남아 있습니다.

같은 소스에서 x64 Release native CTest 30/30, Catalog 317 assertions, Shell 267 assertions, ABI 0.10
interop 54 assertions과 native/managed ARM64 교차 빌드를 통과했습니다. provenance gate는 files=1773,
text=1730, binary=43, declared_resources=29, reachable_commits=137을 확인했습니다. ARM64 runtime은
실행하지 않았습니다.

## 2026-08-09 Parametric Tone Curve control slice

기존 Catalog/ABI/native path의 `curveHighlights`, `curveLights`, `curveDarks`, `curveShadows`를 WinUI의
별도 `Tone curve` 그룹으로 연결했습니다. AutomationId는 각각
`negaflow.develop.curve.highlights`, `.lights`, `.darks`, `.shadows`이며, Basic Tone의 동명
Highlights/Shadows와는 다른 recipe field입니다. Shell state는 엔진 tone-control 범위로 clamp하고
positive/digital frame의 mutation을 거부합니다. x64 Debug 관리형 build warning/error 0, Catalog 317,
Shell 255 assertions을 통과했습니다. 아래 Point Curve v5 slice가 `ToneCurveEditor`를 연결했습니다.

## 2026-08-09 Color Mixer recipe v6 vertical slice

## 2026-08-09 Color Grading recipe v7 vertical slice

`params.colorGrading`의 Shadows/Midtones/Highlights hue·saturation·luminance와
blending/balance를 Catalog read/write, Shell request factory, ABI 0.13
`nf_develop_export_request_v7`/`nf_develop_preview_v7`, native CPU pipeline,
WinUI `ColorGradingEditor`까지 연결했습니다. v7는 v6 prefix 뒤에 11개 float를 append하므로
이전 ABI entry point와 layout은 유지합니다. Inspector는 세 range selector, 150 DIP
hue/saturation wheel, luminance/blending/balance slider 및 pointer capture·keyboard nudge를
제공하며 preview와 export가 같은 recipe를 공유합니다.

x64 Debug native CTest 30/30, Catalog 338 assertions, Shell 276 assertions, interop ABI 0.13
64 assertions을 통과했습니다. rendered WinUI/UIA, compact/high contrast, 실제 ARM64 runtime,
macOS golden pixel 비교는 미검증입니다. 상세는 `implementation/color-grading-v7.md`에 기록합니다.

x64 Release CI gate는 native CTest 30/30, Catalog 338 assertions, Shell 276 assertions과 managed
build 경고·오류 0을 통과했습니다. native/managed ARM64 교차 빌드도 경고·오류 없이 완료했지만
실제 ARM64 실행은 하지 않았습니다. provenance gate는 files=1787, text=1744, binary=43,
declared_resources=29, reachable_commits=140을 확인했습니다.

## 2026-08-09 InspectorSlider focus/reset follow-up

Exposure와 모든 `InspectorSlider` composite는 이제 Tab 순서에서 value button을 제외하고 slider 하나만
논리 focus 대상으로 둡니다. slider가 focus된 상태에서 Enter로 숫자 편집을 시작하며 기존 click/edit,
Enter/focus-loss commit, Escape cancel, invalid draft의 red/beep/focus 복귀는 유지합니다. slider 주위
8 DIP hit outset에서 double-click reset을 받고, Narrator HelpText에 reset과 edit keyboard 동작을
명시합니다. Basic Tone 그룹은 `TabFocusNavigation=Cycle`로 Exposure→Contrast→Highlights→Shadows→
Whites→Blacks→Density 순서의 Tab/Shift+Tab 순환을 유지합니다. x64 Debug managed build 경고·오류 0,
Catalog 338 및 Shell 276 assertions을 통과했습니다.
rendered/UIA, compact/high contrast, 실제 ARM64 runtime 증거는 여전히 없습니다.

`params.colorMixer`의 Hue/Saturation/Luminance 8밴드 recipe를 Catalog read/write, Shell request
factory, ABI 0.12 `nf_develop_export_request_v6`/`nf_develop_preview_v6`, native CPU pipeline,
WinUI `ColorMixerEditor`까지 연결했습니다. v6는 v5 prefix 뒤에 3×8 float를 append하므로 이전 ABI
entry point와 layout은 유지합니다. Inspector에는 macOS와 같은 HSL/All 선택과 Red~Magenta 8개 밴드,
-1…1 slider, reset 및 keyboard nudge를 제공합니다. preview와 export는 같은 recipe를 공유합니다.

x64 Debug native CTest 30/30, Catalog 336 assertions, Shell 275 assertions, interop ABI 0.12 61
assertions을 통과했습니다. v6 ABI test는 malformed mixer를 fail-closed로 거부하고 실제 fixture의
Color Mixer 조정이 preview pixel을 바꾸는 것을 확인합니다. rendered WinUI/UIA, compact/high contrast,
실제 ARM64 runtime, macOS golden pixel 비교는 미검증입니다. 상세는
`implementation/color-mixer-v6.md`에 기록합니다.

x64 Release CI gate는 native CTest 30/30, Catalog 336 assertions, Shell 275 assertions과 managed
build 경고·오류 0을 통과했습니다. native/managed ARM64 교차 빌드도 경고·오류 없이 완료했지만 실제
ARM64 실행은 하지 않았습니다. provenance gate는 files=1783, text=1740, binary=43,
declared_resources=29, reachable_commits=139을 확인했습니다.

## 2026-08-09 Point Curve recipe v5 vertical slice

`params.pointCurves`의 RGB/Red/Green/Blue recipe를 Catalog read/write, Shell request factory,
ABI 0.11 v5 preview/export, native `WorkingToneAdjustParameters.point_curves`, WinUI
`ToneCurveEditor`까지 연결했습니다. 빈 channel은 identity이며 finite 0...1, 64-point 상한,
정렬 뒤 1e-9 간격을 Catalog·Interop·native에서 fail-closed로 검증합니다. v5는 v4 prefix 뒤에
고정 channel 데이터를 append하므로 v1~v4 ABI layout과 export를 보존합니다.

WinUI editor에는 RGB/Red/Green/Blue 채널, click/drag, non-endpoint double-click delete,
1%/Shift 5% key nudge, input/output percent edit, add/delete/reset과 고정 AutomationId를 넣었습니다.
이는 x64 Debug 빌드만 확인됐습니다. `node_repl` Sky UI automation 세션이 이 환경에서
`node_repl exec context not found`로 시작하지 않아 rendered/UIA runtime, compact/high-contrast,
실 ARM64 runtime은 미검증입니다.

x64 Debug native CTest 30/30, Catalog 331 assertions, Shell 271 assertions, ABI 0.11 interop
58 assertions이 통과했습니다. native ABI test는 활성 curve preview의 pixel 변화와 malformed
channel의 request-validation 거절을 확인합니다.

## 2026-08-09 Develop inspector histogram·전폭 구조 체크포인트

고정 macOS 기준과 사용자 제공 macOS 렌더 캡처를 대조해 오른쪽 Develop inspector를
`Histogram → 6 tabs → tab content → common adjustments` 순서로 바꿨습니다. Histogram은 64-bin
luma/R/G/B와 clipping, 네 tone 영역의 pointer/keyboard 조정을 제공하며 Basic Tone recipe와 같은
preview 경로를 사용합니다. 카드·header·content·slider는 가용 폭 전체를 쓰고, disclosure를 위한
기본 `Expander`/중첩 card를 제거해 macOS section당 하나의 visual surface만 남겼습니다.

x64 Debug 관리형 빌드는 경고 0·오류 0, Catalog 338/Shell 300 assertions를 통과했습니다.
실제 150% DPI WinUI 창에서 Histogram과 네 adjustment card가 모두 603 physical pixel 폭임을 확인했고,
Tone Curve header는 UIA `ExpandCollapsePattern`의 `Collapsed → Expanded` 전환과 단일 section 확장을
확인했습니다. 6개 로캘 리소스와 저장소 UI 작업 규칙도 갱신했습니다.

이는 전체 Develop UI 완료가 아닙니다. Edit/Defects/Info/Reset 고유 content, 나머지 adjustment
sections, compact/high contrast와 실제 ARM64 runtime은 미검증입니다. 추가 UI 확장은 보류하고
`progress/next-steps.md` 순서의 immutable logical backup generation을 다음 backend 작업으로 둡니다.

## 2026-08-09 Catalog verified commit

`CatalogSession.Write`는 직전 primary를 커밋 전용 UUID snapshot과 고정 raw backup에 보존한 뒤
SQLite write를 수행합니다. 성공은 새 연결에서 9개 table의 순서·ID·canonical payload와 metadata가
요청 snapshot과 같은 때만 반환합니다. write/readback 실패는 직전 bytes 또는 직전 부재 상태로
원복하며, 원복 실패 세션은 후속 mutation을 차단하고 recovery artifact를 남깁니다. 최초 쓰기 실패의
`-journal`/`-wal`/`-shm`도 부재 상태 원복 범위에 포함합니다.

x64 Debug managed build는 경고 0·오류 0이고 Catalog 376, Shell 300 assertions를 통과했습니다.
immutable logical backup generation, pending restore, process-kill/disk-full/power-loss harness는 아직
완료하지 않았습니다.
상세 범위는 `verification/2026-08-09-catalog-verified-commit.md`에 기록합니다.

## 2026-08-09 Catalog logical backup generation

`CatalogSession.CreateBackup`이 live SQLite를 full read한 뒤 물리 schema와 분리된 canonical
`library.json`, empty `defects/`, v3 `manifest.json`을 새 staging에 기록합니다. manifest는 monotonic
sequence, UTC 생성 시각, frame 수, 논리 catalog version, authoritative file byte count와 SHA-256을
포함합니다. staging과 승격된 final generation을 모두 다시 검증한 뒤에만 성공을 반환하고, 그 뒤에만
검증된 세대의 기본 3개 retention을 적용합니다. future·damaged generation은 삭제하지 않습니다.

이 시점에는 defect sidecar writer가 없어 `hasDefectEdits=true` frame이 하나라도 있으면 generation 생성을
`DefectSidecarUnavailable`로 차단했습니다. 당시 x64 Debug managed build는 경고 0·오류 0이고 Catalog 396,
Shell 300 assertions를 통과했습니다. 이후 sidecar 포함 backup으로 확장한 현재 상태는 아래
`2026-08-10 revision-aware Defects sidecar v2`에 기록합니다. 당시 상세는
`verification/2026-08-09-catalog-backup-generations.md`에 기록합니다.

## 2026-08-09 Catalog pending restore

선택한 backup generation은 live catalog를 즉시 바꾸지 않고 `PendingRestore` 아래 검증된 private copy와
marker로 고정합니다. 다음 `CatalogSession.Open`이 process lock을 잡은 뒤에만 현재 catalog를 새 safety
generation으로 보존하고 선택 snapshot을 verified commit 경로로 적용합니다. future storage version,
손상 marker/copy, 당시의 defect sidecar 공백과 unresolved rollback artifact는 fail-closed입니다.

적용 뒤 marker를 `applied`로 먼저 기록해 cleanup 실패 시 다음 시작이 restore를 반복하지 않고 정리만
재시도합니다. 당시 x64 Debug Catalog 447 assertions를 통과했습니다. 상세는
`verification/2026-08-09-catalog-pending-restore.md`에 기록합니다.

## 2026-08-10 GrainMend 안전성·자동 복원 정렬과 preset 실측 Dmin 수정

결과 계약 변경은 `chromabase-grain-mend-rgb-auto-v9`로 구분합니다.
GrainMend의 방향성 표본은 최대 4픽셀 떨어진 값을 읽지만 후보 루프가 3픽셀 여백만 확보해,
x64 Debug에서 `std::vector subscript out of range` assertion으로 종료되던 결함을 수정했습니다.
현재 검출기는 이 임시 4방향 표본기를 제거하고 macOS 고정 기준의 경계 표본 계약을 사용합니다.

자동 먼지는 sRGB 감마 R/G/B 각 채널의 radius 4/8/12 양극성 top-hat 최댓값으로 검출합니다.
radius 12 국소 noise와 radius 36 far-texture 문맥, strong/weak 이중 임계 및 near-white/near-black
valid gate의 상수와 비교 연산을 macOS Develop whole-frame 기본값에 맞췄습니다. Scratch는
`max(R,G,B)` 위에서 22.5도 간격 8방향, 5-tap 양옆 균형 ridge, 25-tap 방향 적분과 radius 12
방향-texture floor를 계산합니다. 내부 픽셀은 사전 계산한 선형 offset을 사용하고 최대 2방향만
동시에 계산해 지연과 per-frame 메모리의 상한을 함께 제한합니다.

후단은 dust/scratch 연결요소를 독립 처리하고, macOS와 같은 dust isolation ring, dust와 scratch를
함께 보는 grain-field 제거, 회전 불변 PCA scratch gate, dust 0px/scratch 1px dilation 및 제한된
interior-hole 채움을 적용합니다. 검출·컴포넌트·morphology·resampling을 별도 파일로 분리해 복원 orchestration과
한 객체에 집중시키지 않았습니다.

whole-frame 자동 복원은 반복되는 평행·교차 구조선 component와 검출선 양끝으로 계속 이어지는
scene line을 제외합니다. 이 보호는 사용자 자동 검출 경로에서만 명시적으로 켜며, 기존 post-pipeline
기본 호출은 sensitivity `0.5/0.5`, detail protect `0.75`와 함께 이전 동작을 보존합니다. 세 검출
control은 `0...1` 범위 밖이거나 finite가 아니면 fail-closed입니다.

기존 post-pipeline 기본 호출에서 1800px를 넘는 프레임은 linear working RGB에서 separable Lanczos-3으로 긴 변 1800px까지
축소한 뒤 sRGB 검출 채널로 변환합니다. 긴 변에서 정한 단일 배율을 짧은 변의 반올림된 출력
크기와 분리해 두 축에 공통 적용하므로 종횡비에 따라 비등방 kernel phase가 생기지 않습니다.
수평 중간 영상 전체를 만들지 않고 현재 수직 kernel이
참조하는 원본 행만 cache해 대형 입력의 추가 메모리를 제한합니다. 검출 마스크를 원본 크기로
올릴 때는 pixel-center affine bilinear weight를 계산하고 이 값을 strength에 곱해 연속적인 마스크
경계가 실제 복원 blend에 반영되도록 했습니다. 작은 프레임의 1:1 이진 마스크 경로는 그대로입니다.

사용자 whole-frame 자동 경로는 원본 해상도를 1400px 이하의 비중첩 core와 80px effective halo로 나눠
검출합니다. dust/scratch evidence와 scratch response를 core 소유권으로 전역 좌표에 한 번만 복사하고,
같은 종류의 8-연결 component를 프레임 전체에서 다시 잇고 난 뒤 grid·continuation 구조 보호와
mask dilation을 적용합니다. 먼지 면적 상한은 긴 변 1800px 기준 물리 면적 비율로 환산합니다.
따라서 자동 경로는 1800px mask 확대 없이 원본 픽셀 좌표에서 검출·복원하며, 기본 post-pipeline
경로의 결과·지연 계약은 바꾸지 않습니다.

v8부터 whole-frame labeled 경로는 radius 4 채널별 bipolar top-hat에서 가는 scratch evidence를 추가하고,
scratch strong/weak hysteresis와 sensitivity별 dust/scratch aspect·thickness gate를 적용합니다. strong
dust core 밀도와 weak-only 장거리 scratch 조건도 분리해, 같은 픽셀의 dust/scratch 증거를 합치지
않습니다. v9은 macOS가 공개 48px 요청을 검출기의 최대 고정 문맥 80px로 올리는 계약을 반영해
타일 경계의 far-texture 통계를 자르지 않습니다. 기본 post-pipeline의 비-labeled 경로는 이 변경을 받지 않습니다.

복원은 고정 3×3 채널별 median과 strength blend를 사용합니다. median 좌표는 `uint32_t` 범위를
`int`로 축소하지 않아 공개 이미지 차원 계약의 정수 경계에서도 좌표 wrap을 만들지 않습니다.
단독 blue-channel 먼지, 18도·72도
비축 방향 scratch, 45도 scratch, 밀집 chromatic grain-field 무변경, grain-only 무변경, 넓은 명부와
어두운 구조 무변경, 3600×129 대형 scratch의 1800×65 검출·복원, 3600×9 비정수 짧은 축의
단일-scale phase, 확대 마스크의 1D 0.25/0.75와 2D transparent-black 경계 가중치,
검출 sensitivity, 반복 grid 보호, 고립 scratch 유지, strength/alpha 및 invalid input을
`native.grain_mend`에서 검증했습니다. 1600px 프레임의 800px core 경계를 가로지르는 scratch도
한 component로 이어져 양쪽 경계 픽셀이 모두 복원되는 것을 확인했습니다.
3×3 median은 전체 RGBA32F 원본 복사 대신 이전 행의 복원을 다음 행 계산 뒤에 적용하는 지연 행
방식을 사용합니다. 따라서 median 입력은 계속 미수정 원본이고, 추가 복원 저장 공간은 전체 사진이
아니라 최대 두 행으로 제한됩니다.

Film preset은 Auto base resolver의 `connected_component`뿐 아니라 macOS confident-only 계약의
`continuous_border`와 `distributed_mask`도 실측 Dmin으로 사용합니다. `strip_fallback`과 고정 fallback은
계속 stock Dmin을 사용합니다. 이 선택은 추가 영상 패스나 할당을 만들지 않습니다.

v9은 x64 Debug 전체 native 43/43과 x64 Release `native.grain_mend`·`native.develop_export_abi`
2/2를 통과했습니다. ARM64 Release에서는 두 test target과 corpus runner를 교차 빌드했습니다. 전체 CI, ARM64 runtime과
관리형/interop 전체 게이트는 실행하지 않았습니다. 세부 명령과 범위는
`verification/2026-08-10-grain-mend-detector-parity.md`에 기록합니다.

FILM-R v2의 고정 44쌍 JPEG를 sensitivity `0.7`로 실행한 Windows x64 Release CPU 결과는 개선 40장,
악화 3장, 평균 PSNR 변화 `+0.332190 dB`, 중앙값 `+0.216207 dB`, 최악 `-0.194325 dB`였습니다.
가중 개선/악화 픽셀 비율은 각각 `0.000260812`/`0.000190639`, 변경 픽셀 비율은
`0.000343990`입니다. v7 대비 평균·중앙 PSNR과 개선 픽셀 비율이 좋아졌고 절대 quality floor
8개 조건도 계속 만족합니다. 다만 config의 `+0.465934 dB` 관측값은 2026-07-25의 이전 자동 중지
정책으로 생성됐고, 고정 기준 commit이 포함하는 2026-07-26 결과 유지·경고 정책 뒤에는 다시 측정되지
않았습니다. 따라서 이 값은 역사적 회귀 참고치와 절대 quality floor이지 현재 macOS pixel parity
oracle이 아닙니다. 같은 고정 소스를 macOS host에서 다시 실행한 mask·pixel report가 없으므로
GrainMend 완전 동등성은 여전히 미검증입니다.

component별 구조/질감 복원을 전체 자동 결과에 바로 대입하는 실험도 채택하지 않았습니다. 선택한
3장 smoke에서 dust 0px mask는 PSNR `-1.657/-9.031/-4.995 dB`, macOS 영역 편집 기본인 dust 2px
mask는 `-1.884/-14.719/-10.567 dB`로 크게 후퇴했습니다. 이 실험은 user-reviewed 영역 Defects와
전역 자동 PostPipeline이 서로 다른 복원 계약이라는 경계를 재확인했으며 제품 소스에는 남기지
않았습니다. 먼지 2px 팽창만 먼저 적용한 실험, 불완전한 방향 보간과 curve half 6 보조 적분도 품질
지표가 후퇴해 제품 경로에서 제거했습니다. 원본 해상도 순차 타일 경로는 이 시점에 FILM-R 사진당 약 5.2~7.1초였으며,
아래 morphology 병렬화 뒤에도 대형 batch 처리량 검증은 남아 있습니다.
결과를 바꾸지 않는 첫 메모리 조치로 labeled thin evidence를 dust scope 안에서 끝내 scratch 적분 전에
대형 float buffer 4개를 해제했습니다. 3장 smoke report SHA-256은 전후 동일했고 peak working set은
`383.86 MiB → 363.86 MiB`로 `20.00 MiB` 줄었습니다. 이어 scratch 각도 작업자 상한을 4개에서
2개로 낮춰 같은 SHA-256을 유지하면서 `343.82 MiB`까지 `20.04 MiB` 더 줄였습니다. 3장 시간은
직전보다 `2.2~4.9%` 늘어 성능 향상으로 세지 않습니다. 이어 작업자별 scratch angle workspace를
네 각도 묶음에서 재사용해 사진당 ridge/integrated full-map vector storage 할당을 `16회 → 4회`로
줄였습니다. 두 번의 3장 smoke 결과는 같은 SHA-256을 유지했고 시간은 worker-2 기준보다
`2.7~3.9%` 짧았습니다. peak working set은 두 번 모두 `348.80 MiB`로 이전 단일 측정보다
`4.98 MiB` 높아 메모리 절감으로 주장하지 않습니다. 이 변경 뒤 x64 Debug 전체 native `43/43`,
x64 Release GrainMend·ABI `2/2`가 통과했고 ARM64 Release 관련 test·corpus·ABI·DLL target이
교차 빌드됐습니다.
타일마다 새로 만들던 `DetectionImage` 5개 float map, `CandidateMaps` 3개 map과 evidence byte map은
사진 단위 workspace의 vector capacity를 재사용하도록 바꿨습니다. 두 번의 3장 smoke report는 같은
SHA-256을 유지했고 시간은 각각 `6942/5366/6247ms`, `6980/5389/6162ms`였습니다. 직전 두 실행의
전체 시간 합보다 `1.2%` 짧았고, 20ms polling peak는 `344.40/344.41 MiB`로 직전 `348.80 MiB`보다
약 `4.40 MiB`(`1.26%`) 낮았습니다. 결과 수학과 알고리즘 버전은 바꾸지 않았습니다. 이 변경 뒤
x64 Debug/Release 전체 native CTest `44/44`가 통과했고 ARM64 Release GrainMend test·corpus·ABI·DLL
target은 모두 `AA64`로 교차 빌드됐습니다.
검출 profile에서 타일당 채널별 먼지 morphology가 `806~912ms`, scratch 방향 적분이 `118~124ms`로
관측돼 실제 병목을 좁혔습니다. 각 radius의 bipolar top-hat에서 서로 독립인 opening과 closing을
한 background worker와 호출 thread로 동시에 실행합니다. 사진 여러 장을 동시에 처리할 때 내부
작업자가 사진 수만큼 늘어나지 않도록 process 전체 background morphology worker는 하나만 허용하며,
worker 생성 실패나 단일 hardware thread에서는 종전 순차 경로로 돌아갑니다. 3장 smoke 시간은
`6890/5296/6081ms`에서 두 번의 실행 각각 `4584/3598/4064ms`, `4631/3598/4109ms`로 약 32~33%
줄었습니다. 같은 smoke report SHA-256 `229A7816...5097B1`을 유지했고 peak working set은
`344.45 MiB`로 종전 `344.40/344.41 MiB`와 사실상 같았습니다. 전체 44장 report도 기존
`report-halo80.json`과 SHA-256 `86631963...F686AD`가 byte-exact이고 품질 지표가 모두 같았습니다.
결과 수학과 algorithm version은 바꾸지 않았습니다. x64 Debug 전체 `44/44`, x64 Release
GrainMend·ABI `2/2`, ARM64 Release 관련 target의 순수 `AA64` 교차 빌드가 통과했습니다.
실제 촬영 TIFF의 macOS/Windows mask·pixel golden, ARM64 runtime과 대형 batch 처리량은 아직
미검증입니다. 코퍼스 명령·수치·경계는
`verification/2026-08-10-grain-mend-film-r-v2.md`에 기록합니다.

영역 Defects용 component repair v2 코어를 전역 자동 GrainMend와 분리해 추가했습니다. 1채널 ROI
mask의 8-connected component를 얇은 원본-only 8방향 isophote 또는 두꺼운 onion-peel로 채우고,
원본 damage mask를 구조 판정에 유지합니다. preferred angle이 있는 넓은 brush mask는 luma median/MAD로
실제 damage만 남기며, 주변 grain sigma와 context SSD로 고른 exemplar의 제한된 고주파 residual을
전사합니다. linear working RGB는 macOS와 같은 sRGB encoded 복원 domain을 거쳐 돌아오고 alpha는
보존됩니다. invalid input과 할당 실패는 부분 결과를 폐기합니다.

x64 Debug/Release 전체 native CTest `44/44`가 통과했습니다. ARM64 Release의 component repair test와
DLL을 교차 빌드했고 두 PE machine field가 `0xAA64`임을 확인했습니다. 구현 경계는
`implementation/defect-component-repair-v2.md`, 실행 근거는
`verification/2026-08-10-defect-component-repair-v2.md`에 기록합니다.

이어 ROI y-up 좌표, top-first mask, enabled·strength·preferred angle과 순서를 보존하는 caller-owned flat
payload를 ABI v18/0.24와 관리 Interop에 추가했습니다. decode와 원본 변경 관찰 뒤, 음화 base 측정·반전
전에 각 ROI를 순서대로 복원하며 preview와 export는 같은 `prepare_working_image` 경로를 사용합니다.
64×64 합성 RGB16 TIFF의 세로 결함을 실제 v18 preview와 PNG16 export에서 복원해 identity와 다른 결과를
확인했고 원본 TIFF는 byte-exact였습니다. 프레임 밖 ROI는 결과 게시 없이
`defect_component_repair/invalid_argument`로 실패합니다. x64 Debug/Release 전체 native `44/44`, Interop
Debug/Release `103 assertions`가 통과했고 ARM64 Release component repair·ABI test·DLL과 관리 전체 graph가
교차 빌드됐습니다. 세 네이티브 PE machine field는 `0xAA64`였습니다. 당시에는 catalog revision sidecar, WinUI 영역
편집, macOS 동일 입력 pixel golden, 실제 촬영 TIFF, 대형 ROI/batch 성능과 ARM64 runtime이
미검증이었습니다. 새 실행 근거는 `verification/2026-08-10-defect-region-pipeline-v18.md`에 기록합니다.

## 2026-08-10 revision-aware Defects sidecar v2

macOS 고정 기준의 Defects v2 계약을 Windows 네이티브 저장 구조로 구현했습니다. frame ID, 양의 recipe
revision, recipe SHA-256, 선택적 source identity와 ordered brush/region/infrared/clone item을 canonical JSON으로
저장하며 mask는 bounded zlib로 압축합니다. 같은 revision의 다른 내용은 충돌로 차단하고, 더 낮은 revision의
늦은 완료는 게시하지 않습니다. temp→flush→atomic replace 뒤 readback을 검증하며 실패 시 이전 파일을
복원합니다.

`CatalogSession.Open`은 `hasDefectEdits` 선언과 sidecar의 frame/revision/fingerprint를 교차 검증해 누락·손상·
미지원 version을 fail-closed 처리합니다. backup v3 manifest는 catalog와 모든 authoritative sidecar의 byte count와
SHA-256을 함께 고정하며, pending restore도 defects 디렉터리와 catalog를 같은 generation으로 교체합니다.
재시작한 `LibraryDocument`는 region/infrared mask를 선택 시점에 bounded decode하고 clone·brush stroke를
ABI v21 request로 투영합니다. 저장된 source identity를 렌더 직전에 재검증하므로 preview와 export가
같은 ordered recipe와 native 수학을 사용합니다.

x64 Debug/Release 관리 build는 경고 0·오류 0, 각각 Catalog 583·Shell 316 assertions가 통과했습니다.
ARM64 Release 관리 전체 graph는 교차 빌드됐으며 실제 ARM64 실행 증거는 아닙니다.
process-kill/disk-full/power-loss 중 디렉터리 교체 복구,
동일 입력 macOS pixel golden은 아직 미검증입니다. 상세는
`verification/2026-08-10-defect-sidecar-v2.md`에 기록합니다.

## 2026-08-10 Defects source identity ABI v19

비어 있지 않은 영역 Defects recipe는 sidecar의 source byte count와 SHA-256 없이 native 요청을 만들 수
없도록 했습니다. ABI v19의 caller-owned 32-byte digest를 native가 디코드 전에 Windows CNG로 재계산하고,
hash 전후 file observation과 decode 뒤 observation도 같아야 합니다. 불일치·교체 race는
`observe_source_before/defect_source_identity_mismatch`로 실패하며 preview pixel과 export artifact를 게시하지
않습니다. Defects가 없는 일반 요청은 hash를 계산하지 않습니다.

x64 Debug/Release의 image-content-hash와 develop-export ABI 표적 CTest `2/2`, Interop `107`, Catalog
`583`, Shell `314` assertions가 통과했습니다. ARM64 Release native DLL·두 표적 test와 관리 전체 graph는
교차 빌드됐으며 실기 실행 증거는 아닙니다. 실제 대형 TIFF에서 Defects 편집 중 반복 preview가 부담하는
추가 순차 hash latency와 cleaned-raw cache는 아직 측정·구현하지 않았습니다. 상세는
`verification/2026-08-10-defect-source-identity-v19.md`에 기록합니다.

## 2026-08-10 Clone Stamp ABI v20

macOS 고정 기준의 normalized y-down point, 정수 source offset, 직경 25% stamp spacing, hardness mask,
stroke별 linear RGBA16 full-strength patch와 item strength 합성을 Windows C++20으로 구현했습니다.
뒤 stroke는 앞 stroke의 full-strength 결과를 source로 읽고, region/infrared/clone edit의 sidecar 순서는
ABI v20 ordered reference 배열을 거쳐 음화 현상 전 공통 preview/export에 그대로 적용됩니다.

x64 Debug/Release native CTest `45/45`, Interop ABI `0.26`의 `118`, Catalog `583`, Shell `315`
assertions가 통과했습니다. 64×64 합성 RGB16 TIFF에서 실제 preview와 PNG16 export가 identity와 다른
결과를 냈고 원본 TIFF는 byte-exact였습니다. ARM64 Release 전체 graph는 교차 빌드했지만 실행하지
않았습니다. macOS hosted pixel golden, 실제 촬영 TIFF와 대량 겹침 stroke 성능은
남아 있습니다. 상세는 `implementation/defect-component-repair-v2.md`와
`verification/2026-08-10-defect-region-pipeline-v18.md`의 v20 후속 절에 기록합니다.

## 2026-08-10 Brush ABI v21

macOS 고정 기준의 normalized top-left 좌표, 짧은 raw 변 대비 두께, 240~640px stroke chunk,
최소 96px repair halo, sRGB float heal, 실제 source texture displacement와 저주파 tone matching,
1px feather, item strength 합성을 Windows C++20으로 연결했습니다. texture source를 찾지 못하면
영역 component repair로 실패 폐쇄형 fallback하며, region/infrared/clone/brush 교차 순서는 ABI v21의
기존 ordered reference 배열로 보존합니다. 손상 sidecar의 0~1 밖 좌표와 두께도 요청 경계에서 거부합니다.

x64 Debug/Release native CTest `46/46`, ABI `0.27` Interop `127`, Catalog `583`, Shell `316`
assertions가 통과했습니다. 64×64 합성 RGB16 TIFF의 실제 preview와 PNG16 export가 identity와 다른
결과를 냈고, 모든 Defects preview/export 뒤 원본 TIFF는 byte-exact였습니다. ARM64 Release native와
managed 전체 graph는 교차 빌드했지만 실행하지 않았습니다. macOS CoreGraphics antialias·Core Image
Gaussian 및 fallback의 동일 입력 pixel golden, 네 chunk마다 이루어지는 macOS RGBA16 flatten의 누적
양자화, 실제 촬영 TIFF와 대량 stroke 성능은 아직 미검증입니다.

## 2026-08-10 Digital B&W Film Look 15종

macOS 고정 기준의 B&W negative 13종과 B&W reversal 2종을 Windows registry, C++20 엔진,
CLI, C ABI enum, 관리 Interop, catalog JSON과 Shell request에 같은 profile ID로 연결했습니다. Windows가
지원하는 Film Emulation은 color 11종과 B&W 15종, 합계 26/42종입니다. ABI struct와 export는 바뀌지
않아 버전은 0.23을 유지합니다.

rendered digital B&W의 실행 순서는 halation → spectral emulsion response → acutance → single-channel
density grain입니다. profile별 spectral weight, contrast, toe/shoulder, density, halation, acutance와 grain
material을 고정하고 출력 RGB를 중립으로 유지합니다. film scan은 선택을 보존하되 항상 exact identity이며,
color/B&W process와 profile kind가 다를 때도 exact identity입니다. B&W 경로는 RGB33 color cube를 만들지
않고 행 단위 acutance scratch만 준비합니다.

x64 Debug/Release 전체 native CTest 43/43, Catalog 492, Shell 305, Interop 95 assertions가 통과했습니다.
실제 TIFF ABI preview에서 B&W route가 전체 graph를 실행하고 중립 RGB를 내는 것도 확인했습니다.
ARM64 Debug/Release는 새 B&W test, working router, CLI parsing, ABI, DLL과 CLI target의 순수 ARM64 교차
빌드가 통과했지만 실제 ARM64 실행 증거는 아닙니다.

남은 Film Emulation은 color/motion 16종입니다. B&W의 registry·상대 spectral signature·alpha/neutrality·
kind gate는 고정했지만, Core Image 실제 수치 golden과 비기준 acutance radius의 Gaussian sigma,
macOS `CIRandomGenerator`와의 grain 통계 허용오차는 아직 확정하지 않았습니다.
세부 명령과 검증 경계는 `verification/2026-08-04-film-look-routing.md`의 2026-08-10 addendum에
기록했습니다.

## 2026-08-10 Film Emulation color/motion 16종

macOS 고정 기준에 추가된 slide 4종, color negative 8종, motion picture 4종의 tone/color profile,
acutance, 활성 scatter·halation·grain material과 stock color preset을 Windows native graph에 연결했습니다.
기존 ABI 0~26 값은 그대로 두고 27~42를 append해 CLI, C ABI, Interop, catalog JSON과 Shell request가
모두 같은 선택을 보존합니다. 이로써 Windows registry는 전체 42/42종(+ `none`)을 지원합니다.

실제 film scan은 모든 선택에서 계속 identity이고, rendered digital의 color/motion profile만 color
DigitalFilmLook graph를 실행합니다. `DigitalFilmPhysics`는 macOS 구조를 기계적으로 복제하지 않고 현재
활성 graph가 읽는 scatter, halation, radius와 grain만 보존하며 tone/color는 같은 profile 기반 RGB33
cube가 담당합니다. preview와 export는 같은 route와 수학을 사용합니다.

x64 Debug/Release 전체 native CTest 43/43, Catalog 540, Shell 306 assertions가 통과했고 x64 Debug
Interop 95 assertions도 통과했습니다. 실제 TIFF ABI preview에서 Vision3 500T가 decode부터 전용
DigitalFilmLook graph와 preview 출력까지 실행됐습니다. ARM64 Release native·managed·WinUI 전체 graph는
순수 ARM64로 교차 빌드했지만 실제 ARM64 장치에서 실행하지 않았습니다.

새 16종은 macOS source 수치와 profile 간 상대 특성, Windows finite/distinct response와 실제 pipeline
연결을 검증했습니다. 다만 새 profile별 macOS Core Image pixel golden은 고정 기준에 없으므로 수치 결과
동등성을 완료로 주장하지 않습니다. 실제 촬영 TIFF의 macOS/Windows pixel 비교와 대형 batch도 남아
있습니다. 세부 명령과 경계는 같은 verification 문서의 color/motion addendum에 기록했습니다.

DigitalFilmLook의 stock color preset은 더 이상 사진 전체의 원본 RGB 복사본을 만들지 않습니다.
Color Mixer·Color Grading·Primary Calibration이 모두 pointwise인 경계를 이용해 1,048,576 pixel(약
12 MiB) 이하의 행 타일 원본 버퍼를 재사용하며, 한 행이 더 큰 비정상 폭에서는 한 행 크기만 허용합니다.
2,048×1,025, stride 2,051 합성 입력에서 종전 untiled graph와 전체 RGBA buffer가 byte-exact였고,
scratch는 25,190,400바이트에서 12,582,912바이트로 줄었습니다. x64 Debug 전체 CTest 44/44,
x64 Release 인접 3/3과 ARM64 Release 관련 target 교차 빌드가 통과했습니다. 실제 55MP batch의 process
working-set·처리 시간은 아직 측정하지 않았습니다.
