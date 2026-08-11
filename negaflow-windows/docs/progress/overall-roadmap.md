# 전체 로드맵과 진행률

기준일: 2026-08-12
기준 로드맵: `windows_docs/99-plan/migration-roadmap.md`의 M0~M18

## 현재 숫자

- 전체 M0~M18 제품 로드맵: **약 31%**
- 기반 구간 M0~M3: **약 66%**
- 제한형 TIFF 사전 검사 세부 작업: **약 97%**

이 수치는 일정이나 개발 시간의 5%가 아닙니다. 각 milestone의 정의된 산출물과 종료 조건을
동일 가중치로 놓고, 현재 확보한 증거의 비율을 보수적으로 추정한 값입니다. UI와 실제 장치 검증이
뒤에 많이 남아 있으므로 작은 기반 코드가 완성됐다는 이유로 전체 진행률을 크게 잡지 않습니다.

## milestone별 상태

| 단계 | 추정 | 현재 증거 | 주요 미완료 |
|---|---:|---|---|
| M0 제품 기준선 | 35% | exact commit, bootstrap manifest, delta, 일부 asset hash, canonical Film Emulation Core Image artifact | 전체 surface/stage manifest, 권리 결정, 나머지 macOS 기준 artifact |
| M1 저장소·빌드·CI | 68% | 별도 build root, x64/ARM64 native·managed·WinUI graph, dual-RID lock, C ABI, CLI, VS 18.8.2와 Windows App SDK C# component, 고정 SDK/vcpkg, static CRT | shader/packaging, CI, 실제 ARM64 run |
| M2 적합성·CPU scalar | 72% | 4상태 film type, scene-ranged negative와 muted-scene vibrance, Auto Levels/Neutral Balance, documented+matched-pair ScannerTargetGrade 4종, EXPIRED RescueGrade, 15종 ScannerProfileGrade, color/motion 27종+B&W 15종 DigitalFilmLook, GrainMend, FilmScanDenoise, Local Dodge/Burn, ColorModel, Texture, B&W 토닝, ImageTransform을 포함한 현재 kernel은 모두 architecture baseline scalar로 직접 실행 | 새 Film Emulation의 macOS numeric golden, 실제 ARM64 실행, 계측으로 상위 ISA variant가 필요해질 때의 dispatch |
| M3 이미지 I/O·색·영속성 | 88% | bounded TIFF none/LZW/Deflate decode와 독립 압축 검사, row streaming, ICC→linear working, 이미지 SHA·검증 게시, catalog route, SQLite verified commit, optional R16 attenuation을 포함한 revision-aware Defects sidecar와 렌더 직전 source identity 재검증, 모든 authoritative 파일의 논리 backup·restart-only pending restore | WIC CPU deadline, tile/fuzz, process-kill/disk-full/power-loss harness |
| M4 CLI end-to-end | 97% | 4상태 film type과 비프리셋 color negative muted-scene vibrance를 포함해 Auto Levels/Neutral Balance→ScannerTargetGrade/RescueGrade/ScannerProfileGrade→ColorModel→tone/color→source별 Film Look→GrainMend→FilmScanDenoise→가변 Local Dodge/Burn→Texture→B&W→ImageTransform을 공통 preview/export 순서로 연결하고 ABI v17 검증 | 나머지 runtime pixel diff manifest와 대형 입력 evidence |
| M5 GPU/WARP | 0% | 문서만 존재 | D3D11/Direct2D/WARP FP32 vertical slice |
| M6 전체 Develop graph | 94% | revision-aware sidecar에서 재시작 재적용되는 현상 전 ordered region/IR attenuation→optional core repair/Clone Stamp/Brush Defects, 4상태 film type, scene-ranged 반전 직후 muted-scene vibrance와 opt-in Auto Levels/Neutral Balance, documented+matched ScannerTargetGrade 4종, RescueGrade, 15종 ScannerProfileGrade와 ColorModel, 42종 source별 Film Look 뒤 GrainMend→FilmScanDenoise→Local Dodge/Burn→Texture→B&W→ImageTransform까지 native CPU graph 구현 | 최신 paired-plane IR 자동 검출·scanner lifecycle·macOS mask/R16/pixel golden, Defects Brush·Clone Stamp macOS golden, 새 Film Emulation·`CIVibrance`·나머지 현상 축의 macOS golden, 대형 이미지/GPU/ARM64 runtime |
| M7 대형 이미지 | 6% | WIC row sink, chunk ICC transform, 단조 progress/cancel, full decoded source 제거와 exact parity | 최종 working streaming, tile, byte reservation, cache, TDR |
| M8 ABI·WinUI shell/canvas | 80% | v12 가변 Local Dodge/Burn, v13 ColorModel, v14 scene correction, v15 DevelopTarget, v16 scanner profile ID, v17 film polarity, v18 ordered 영역 Defects, v19 source identity, v20 ordered Clone Stamp, v21 ordered Brush, v22 run state, v23 preview-only soft proof, IR item-boundary v25/ABI 0.32까지 검증 | WinUI Defects 편집과 paired-plane IR lifecycle, GPU canvas, handles/events, lifetime·activation 전체 경로 |
| M9~M14 제품 surface | 8% | Library 목록, 파일 picker import, Develop의 필름 base·노출, Export가 실제 동작 | 미리보기 렌더, base picker, 취소·진행률, Defects, Print, Settings 기능 |
| M15 scanner host | 0% | 문서만 존재 | protocol host와 격리 |
| M16 qualification | 0% | 문서만 존재 | 실제 CPU/GPU/ARM64/display matrix |
| M17 배포·컴플라이언스 | 0% | 설치 선언 초안만 존재 | MSIX/installer, signing, update, SBOM |
| M18 Beta/RC/Stable | 0% | 없음 | release gate 전체 |

계산은 M0 35, M1 68, M2 72, M3 88, M4 97, M6 94, M7 6, M8 80, M9~M14 각각 8, 나머지 0을 19개
milestone의 100점 만점에 대입한 약 30.9%입니다. 표시는 정수 31%이며, 숫자는 구현
증거가 추가될 때만 올립니다.

2026-08-07 에 올라간 것과 그 근거:

- **M3 56 → 70.** SQLite 영속성, 단일 작성자 세션, 5만 frame 성능 측정.
  `verification/2026-08-07-sqlite-catalog-store.md`. 남은 것은 backup 세대·pending restore·
  defect sidecar·WIC CPU deadline·tile/fuzz 입니다.
- **M4 50 → 72.** projection 이 실제 DB 에 저장되고 C ABI 로 연결됐습니다. 남은 것은 고급
  color recipe 전체 입력과 runtime pixel diff manifest 입니다.
- **M6 14 → 18.** 실제 DB 저장·재로드가 붙었습니다. digital film 전체 그래프와 나머지 stage 는
  그대로 남아 있습니다.
- **M8 18 → 45.** C ABI 가 develop/export/preview/limits 를 실어 나르고, 셸이 시작할 때
  카탈로그를 열며, 스레딩 정책이 시험됩니다. GPU canvas 와 전체 lifetime/activation 은 미착수.
- **M9~M14 2 → 8.** Library 목록, import, Develop 의 필름 base·노출, Export 가 실제로 돕니다.
  `verification/2026-08-07-vertical-slice.md`. 나머지 제품 표면은 그대로입니다.

M5(GPU), M15(scanner host), M16(qualification), M17(배포·서명), M18(release gate)은 **여전히
0%** 입니다. 남은 80% 의 대부분이 여기와 M9~M14 에 있고, 이쪽이 검증이 어렵고 되돌리기 비싼
구간입니다.

2026-08-09 Chroma backend 반영:

- **M2 40 → 43, M4 80 → 84, M6 38 → 47, M8 52 → 53.** 고정 macOS baseline의 실제
  DigitalFilmLook 전체 그래프와 11종 stock material을 native preview/export에 연결하고, 실제 TIFF
  digital route와 ABI 0.17 interop을 검증했습니다. 이 단계 직후 남았던 Local Dodge/Burn 가변 mask
  projection은 아래 후속 작업에서 닫았습니다. scanner monochrome tint는 현재 macOS bundle에서도 근거
  데이터가 없어 no-op이며, 임의 효과를 추가하지 않습니다.

- **M2 43 → 45, M4 84 → 88, M6 47 → 52, M8 53 → 56.** 가변 Local Dodge/Burn을
  catalog→Shell→ABI v12로 닫고, 반전 직후 ColorModel 8축을 native graph와 ABI v13에 연결했습니다.
  이어 Auto Levels/Neutral Balance를 ABI v14로 연결해 당시 ABI 0.20의 x64 실제 TIFF preview에서
  활성 recipe가 identity와 다른 픽셀을 냅니다.

- **M2 45 → 48, M4 88 → 91, M6 52 → 59, M8 56 → 59.** 7종 `DevelopTarget`을
  catalog→Shell→ABI v15로 연결하고 EXPIRED target의 evidence-gated RescueGrade를 native preview/export에
  추가했습니다. 이 단계의 ABI는 0.21이었으며, 아직 profile grade가 없는 scanner target은 MAIN으로 대체하지
  않고 명시적으로 거부합니다.

- **M2 48 → 51, M4 91 → 93, M6 59 → 64, M8 59 → 62.** macOS manifest v2의 15개
  scanner profile grade 수치와 hash를 immutable native registry로 고정하고, `scannerProfileID`를
  catalog→Shell→ABI v16→preview/export로 연결했습니다. 현재 ABI는 0.22입니다.

- **M2 57 → 60, M4 96 → 97, M6 77 → 80, M8 62 → 64.** film polarity를 ABI v17로 분리해
  4상태 film type을 공용 preview/export에 연결했습니다. macOS correctness fix에 따라 film scan의
  중복 유제 응답을 제거하고, 현재 color stock이 B&W digital process에 적용되지 않게 했습니다.
  x64 Debug native 42/42, Interop 95, Catalog 447, Shell 304 assertion을 통과했습니다.

- **M2 60 → 65, M6 80 → 85, M8 64 → 66.** B&W negative 13종과 reversal 2종의 spectral
  emulsion·acutance·grain을 registry→catalog/ABI→preview/export에 연결했습니다. Windows Film
  Emulation은 26/42종이며, x64 Debug/Release native 43/43, Catalog 492, Shell 305, Interop 95와
  ARM64 Debug/Release 관련 target 교차 빌드로 고정했습니다.

- **M2 65 → 72, M6 85 → 90, M8 66 → 68.** 나머지 slide 4종, color negative 8종,
  motion picture 4종의 tone/color·acutance·활성 material·stock preset을 공통 preview/export graph와
  append-only ABI/catalog/Shell에 연결해 Film Emulation 42/42종을 채웠습니다. x64 Debug/Release native
  43/43, Catalog 540, Shell 306, Debug Interop 95와 ARM64 Release 전체 교차 빌드가 통과했습니다.

- **M3 78 → 86, M6 91 → 92, M8 70 → 72.** revision-aware Defects v2 sidecar의 atomic writer/readback,
  library open fail-closed, 재시작 region/infrared request 투영, authoritative backup과 pending restore 동일 세대
  교체를 연결했습니다. x64 Debug/Release Catalog 583·Shell 313 assertions와 ARM64 Release 관리 전체 graph
  교차 빌드가 통과했습니다.

## 현재 완료된 작은 루프

1. exact macOS 기준선과 Windows 기술 경계를 고정했습니다.
2. x64/ARM64 네이티브 코어, DLL, CLI, 테스트 골격을 만들었습니다.
3. float32 extended-linear 픽셀과 첫 scalar 수치 계약을 실행 가능하게 만들었습니다.
4. TIFF 디코더 전에 실행되는 읽기 전용 구조 검사와 손상 fixture를 만들었습니다.
5. x64 Debug/Release 실행과 ARM64 Debug/Release 교차 빌드를 분리해 검증했습니다.
6. WIC decode와 Windows ICM 색상 경로로 사용자 TIFF 15개를 working float까지 변환했습니다.
7. static CRT로 별도 VC++ Redistributable DLL 의존성을 제거했습니다.
8. .NET 10 Interop이 x64 native DLL을 실제 로드하고 ABI를 검증하며 ARM64 target으로 교차 빌드됩니다.
9. TIFF preflight와 WIC decode가 경로를 재개방하지 않고 같은 read-only `IStream`을 사용합니다.
10. 정상 합성 LZW를 exact sample로 검증하고, 잘린 압축 segment와 decoded-byte 한도 초과를
    pixel buffer 할당 전에 차단합니다.
11. WIC pixel copy를 선택적 행 묶음으로 나누고 묶음 사이 취소, 단조 진행률과 부분 sample 폐기를
    검증했습니다.
12. WIC row sink와 재사용 ICM transform을 연결해 full decoded source와 full-frame ICC intermediate를
    제거하고 사용자 TIFF 15개의 최종 float exact parity를 확인했습니다.
13. 일반 이미지 SHA-256 기본값을 `끔`으로 고정하고, 명시적으로 켠 경우에만 CNG 순차 경로가 동작하도록
    known-answer와 실제 코퍼스로 검증했습니다.
14. TIFF decode→scanner color→수동 Dmin negative inversion을 연결하고 기존 scalar와 exact 일치 및
    추가 full-frame pixel allocation 0을 검증했습니다.
15. Swift 기준 치수와 6개 언어를 사용하는 WinUI 셸을 x64 전체 작업영역에서 실행하고, 오른쪽 Windows
    caption inset, Settings와 일반 이미지 SHA-256 기본 `끔` 상태를 확인했습니다.
16. 현상된 working float를 16-bit sRGB PNG로 encode하고 구조·전체 pixel·ICC를 readback한 뒤 기존
    파일을 덮어쓰지 않고 같은 디렉터리에서 게시하는 CPU 수직 경로를 검증했습니다.
17. 같은 출력 변환·게시 경계를 재사용해 무압축 RGB16 TIFF를 만들고 단일 IFD 최소 metadata,
    전체 pixel·ICC, source 상태 전후와 단계별 CLI report를 검증했습니다.
18. macOS Float32 수식의 노출·기본 톤·4-band curve를 제자리 scalar로 연결하고 fixed fixture, bounded
    동적 percentile 측정과 TIFF16/PNG16 실제 게시를 검증했습니다.
19. 기본 export에 프로세스 전체 CPU 시간을 추가하고, 별도 개발 진단에서 scanner→working, develop,
    tone의 active RGBA32F 통계와 versioned 비암호 fingerprint를 검증했습니다.
20. TIFF 6.0 조기 비트폭 규칙을 따르는 길이 전용 LZW 의미 검사기를 추가해 WIC 전에 손상 code stream과
    압축 입력 작업량을 차단하고, 독립 검증기가 없는 Deflate는 fail-closed로 격리했습니다.
21. zlib wrapper와 stored/fixed/dynamic Deflate, 32 KiB back-reference, 예상 복원 byte 수와 Adler-32를
    독립 검사해 정상 compression tag 8을 WIC 경로에 복원하고 손상 입력은 WIC 전에 차단했습니다.
22. macOS post-pipeline의 첫 DR/R/G/B 포인트 커브를 고정 64표본·무할당 scalar로 연결하고, 제어점
    경계·처리 순서·합성 fixture를 x64에서 실행하고 ARM64로 교차 빌드했습니다.
23. 포인트 커브 뒤 8대역 HSL Color Mixer를 고정 배열·무할당 scalar로 연결하고, 회색 보호·원형 hue
    대역·48개 합성 값을 x64에서 실행하고 ARM64로 교차 빌드했습니다.
24. Color Mixer 뒤 shadows/midtones/highlights Color Grading을 준비값 기반·무할당 scalar로 연결하고,
    identity·세 구간·48개 합성 값을 x64에서 실행하고 ARM64로 교차 빌드했습니다.
25. Color Grading 뒤 R/G/B Primary Calibration을 고정 세 대역·무할당 scalar로 연결하고, identity·회색
    gate·48개 합성 값을 x64에서 실행하고 ARM64로 교차 빌드했습니다.
26. 다음 film-scan source 분기의 11종 profile을 5% intensity·caller-owned RGB33 색상 cube로 격리하고,
    11개 node signature와 48개 합성 값을 x64에서 실행하고 ARM64로 교차 빌드했습니다. acutance와 실제
    source routing은 아직 연결하지 않았습니다.
27. 두 macOS hosted run에서 12,912개 Film Emulation numeric value의 exact 반복성을 확인하고 canonical
    Core Image artifact를 고정했습니다. 색상 platform envelope와 11행 caller-owned scratch의 acutance를
    분리 구현해 x64 Debug/Release 32/32, ARM64 Debug/Release 교차 빌드로 검증했습니다.
28. source 종류를 추정하지 않는 native Film Look route를 만들고 film scan의 RGB33 색상→acutance 순서를
    수동 호출과 bit-exact로 비교했습니다. cube 재사용, 낮은 강도, identity, 부족한 workspace 조기 거부와
    미완성 digital graph의 fail-closed를 검증해 x64 Debug/Release 33/33과 ARM64 전체 교차 빌드를 통과했습니다.
29. 명시적 source/profile/intensity CLI parsing과 bounded workspace 소유를 분리하고, 진단·PNG16·TIFF16에서
    Primary Calibration 뒤 Film Look을 실행했습니다. 같은 tone의 identity/활성 TIFF가 달라지는지, report 단계
    순서, I/O 전 digital-source 거부와 SHA 기본-off를 검증해 x64 Debug/Release 37/37과 ARM64 전체 교차
    빌드를 통과했습니다.
30. catalog의 `scanner`/`imported` transport와 film/digital signal을 분리하고, legacy marker와 missing
    intensity `1.0`, 새 기본 `0.5`를 고정한 관리 코드 projection을 만들었습니다. unknown field 보존,
    invalid 조합 fail-closed와 12개 profile round trip을 x64 Debug/Release 각각 163 assertion으로 실행하고
    ARM64 Debug/Release managed solution을 교차 빌드했습니다.
31. Defects v2 sidecar를 revision-aware atomic store로 구현하고 catalog 선언과 교차 검증했습니다. backup과
    pending restore가 catalog·sidecar를 같은 세대로 다루며, 재시작한 region/infrared edit가 공통
    preview/export request로 다시 투영됩니다. x64 Debug/Release Catalog 583·Shell 313 assertions가 통과했습니다.
32. 네거티브 장면 범위 proxy를 macOS affine과 같은 가로축 단일 scale·pixel-center bilinear 표본으로
    바꿨습니다. 640×65 고주파 fixture가 최근접·비등방 회귀를 고정하고 x64 Debug 전체 44/44, Release 3/3
    인접 native 검증과 ARM64 Release 교차 빌드를 통과했습니다.
33. Auto FilmBase도 같은 affine 계약으로 만든 RGB/luma 격자 하나를 연결 성분과 모든 sampled-grid
    fallback이 공유하게 했습니다. 512×129 고주파 fixture, x64 Debug 전체 44/44, Release 인접 2/2와
    ARM64 Release 관련 target 교차 빌드를 통과했습니다.
34. Auto FilmBase의 첫 하위 성분 강등, 상위 R−B 중앙값, 후보 바닥, Double edge/coverage·strip 누적과
    affine scene-edge fallback을 macOS 선택 수학에 맞췄습니다. 세 결과 회귀와 x64 Debug 44/44,
    Release 인접 2/2 및 ARM64 Release 관련 target 교차 빌드를 통과했습니다.
35. Auto FilmBase의 Float RGB 표본을 luma·percentile·median·MAD·threshold·채널 통계에서 Double로
    승격하고 최종 공개 Dmin에서만 Float로 내리도록 맞췄습니다. `0.85` 후보 경계 회귀, x64 Debug
    44/44, Release 인접 2/2와 ARM64 Release 관련 target 교차 빌드를 통과했습니다.
36. DigitalFilmLook stock color preset의 사진 전체 원본 RGB 복사를 약 12 MiB 목표 행 타일 버퍼로
    바꿨습니다. 2,048×1,025 padded-stride fixture가 종전 untiled graph와 전체 RGBA byte-exact임을
    고정했고, x64 Debug 전체 44/44, Release 인접 3/3과 ARM64 Release 관련 target 교차 빌드를
    통과했습니다.
37. GrainMend 먼지 검출의 독립 morphology opening/closing을 process 전체 background worker 하나로
    겹쳐 3장 FILM-R smoke 시간을 약 32~33% 줄였습니다. peak working set은 사실상 같았고 전체 44장
    report가 종전 결과와 byte-exact였습니다. x64 Debug 44/44, Release 인접 2/2와 ARM64 Release 관련
    target 교차 빌드를 통과했습니다.
38. FILM-R config의 `+0.465934 dB`는 2026-07-25 자동 중지 정책의 역사적 관측값이며, 고정 기준에
    포함된 다음 날 결과 유지·경고 변경 뒤 재측정되지 않았음을 확인했습니다. 이를 현재 pixel parity
    oracle로 추격하지 않고 절대 quality floor와 macOS hosted mask·pixel golden을 분리했습니다. 전체
    자동 mask에 영역 component repair를 바로 적용한 두 실험은 큰 회귀를 만들어 제품 소스에서
    제거했습니다.
39. Defects sidecar의 source byte count·SHA-256을 ABI v19로 운반하고 native가 디코드 전에 CNG로
    재검증하게 했습니다. hash 전후 file observation과 decode 뒤 관측이 모두 같아야 하며, 불일치는
    preview pixel과 export artifact를 게시하지 않습니다. Defects가 없는 일반 렌더는 SHA-256 기본
    `off`를 유지합니다. x64 Debug/Release 표적 CTest 2/2, Interop 107, Catalog 583, Shell 314 assertions와
    ARM64 Release 관련 target 교차 빌드로 고정했습니다.
40. Clone Stamp를 normalized y-down 좌표와 정수 source offset, stroke별 RGBA16 full-strength patch,
    item strength 합성으로 구현하고 region/clone 교차 순서를 ABI v20으로 보존했습니다. 합성 TIFF의 실제
    preview/export 변화와 원본 byte-exact 보존, x64 Debug/Release native 45/45, Interop 118,
    Catalog 583, Shell 315 assertions 및 ARM64 Release 전체 교차 빌드로 고정했습니다.
41. Brush를 normalized y-down 좌표·짧은 raw 변 대비 두께·bounded chunk/halo와 sRGB 실제 texture
    displacement·저주파 tone matching·1px feather로 구현하고 region/infrared/clone/brush 순서를 ABI v21로
    보존했습니다. 합성 TIFF preview/export 변화와 원본 byte-exact 보존, x64 Debug/Release native 46/46,
    Interop 127, Catalog 583, Shell 316 assertions 및 ARM64 Release 전체 교차 빌드로 고정했습니다.

42. post-baseline IR layer의 optional compressed R16 저장을 유지하면서 flat v24 replay의 중첩 cluster
    과보정을 폐기하고, 같은 item base에서 exact bbox 사각 patch를 계산·순서 합성하는 ABI v25/0.32로
    교체했습니다. v2 fingerprint canonical은 유지하고 attenuation을 결합한 v3 migration을 분리했습니다.
    x64 Debug/Release native 61/61, Catalog 592, Shell 336, Interop 169 assertions와 ARM64 Release 전체
    교차 빌드를 통과했습니다. ARM64 실기 실행과 macOS-hosted IR pixel golden은 남아 있습니다.

## 다음 완료 조건

가까운 순서대로 다음을 닫습니다.

1. 최신 GrainMend IR의 true-scale 후보 검출, local confirmation·alignment, null/MAD와
   significance-dependent inverse-Mills bias, attenuation/core 분리, scanner 영속 lifecycle을 연결하고
   같은 입력 macOS-hosted mask·R16 attenuation·pixel golden을 고정합니다.
2. DigitalFilmLook과 `CIVibrance`를 포함한 화면 영향 단계의 macOS numeric golden·통계 허용오차를 고정합니다.
3. WIC 압축 해제 CPU budget과
   deadline을 검증합니다.
4. Defects Brush·Clone Stamp의 같은 입력 macOS pixel golden과 실제 촬영 TIFF를 연결합니다.
5. 최종 working buffer와 출력을 downstream row/tile 소비자로 넘기고 전체 process budget을 적용합니다.

## 진행률을 올리지 않는 항목

- ARM64 cross-compile만 성공하고 실제 ARM64에서 실행하지 않은 경우
- 코덱이 파일을 열었지만 bit depth, ICC, orientation을 검증하지 않은 경우
- UI mockup만 있고 네이티브 수명·오류·키보드 경로가 없는 경우
- 빌드 artifact가 있으나 clean restore와 재현 가능한 lock이 없는 경우
