# 다음에 어디서부터 이어서 할 것인가

기준일: 2026-08-12 (Develop Calibration·Detail/Effects inspector 연결 완료)

이 문서는 작업을 한동안 놓았다가 돌아왔을 때 가장 먼저 읽는 곳입니다. 이미 결정된 것을 다시
논쟁하지 않고, 다음 한 걸음을 바로 시작하기 위한 기록입니다.

## 지금 상태

전체 M0~M18 로드맵의 약 31%, 기반 구간 M0~M3 는 약 66% 입니다. 산정 근거는
`overall-roadmap.md`, 항목별 증거는 `../STATUS.md` 에 있습니다.

동작하는 것은 **CLI 수직 경로와 첫 WinUI 관통 경로**입니다. TIFF 디코드 → 스캐너 색상 → 수동
Dmin 음화 현상 또는 film/rendered-digital positive 입력 → 톤·포인트 커브·Color Mixer·Color Grading·Primary
Calibration → source별 Film Look → 검증된 PNG16/TIFF16 게시까지 한 장이 끝까지 갑니다. WinUI 에서는 Import → 필름 base
설정 → 노출 조정 → 같은 파이프라인의 미리보기 → Export 가 카탈로그와 C ABI 를 거쳐 동작합니다.

반전 직후 opt-in Auto Levels → Neutral Balance → ColorModel과 고정 macOS post-pipeline의 GrainMend → FilmScanDenoise → Local Dodge/Burn →
Texture → B&W 중립화·토닝 → ImageTransform이 native 공통 preview/export 경로에 연결됐고,
카탈로그 `params.imageTransform`도 같은 preview/export 요청으로 전달됩니다. 다음 경계는 macOS
변환된 TIFF golden과 정식 Develop 조작 surface입니다.

macOS Texture와 FilmScanDenoise recipe도 catalog→Shell→native 공통 preview/export로 전달됩니다.
색/필름 상태별 denoise profile은 route에서 파생됩니다. 다음 우선순위는 이 레시피들의 실촬영 TIFF
golden 비교와 현상 조작 surface입니다.

Primary Calibration도 ABI 0.38/v27로 preview/export 공통 경로에 연결됐고, macOS 순서의
Calibration·Detail/Effects inspector surface가 각 catalog recipe와 shared preview에 연결됐습니다.
다음 작업은 사용자 촬영 TIFF와 macOS output golden을 사용한 수치 비교, 이어서 Geometry의
crop canvas session과 남은 Develop tool surface입니다.
scene correction은 ABI v14, DevelopTarget과 EXPIRED RescueGrade는 v15, ScannerProfileGrade는 v16,
film polarity는 v17, 현상 전 영역 Defects는 v18, source-bound Defects는 v19, 순서 보존 Clone Stamp는
v20, 순서 보존 Brush는 v21, 취소·진행률 run state는 v22, 자동 보정은 `nf_auto_adjust_v1`,
소프트 프루프는 `nf_develop_preview_v23`과 `nf_read_soft_proof_media_v1`까지 검증됐습니다. ordered IR
attenuation replay는 flat v24의 중첩 cluster 결함을 폐기하고 item range를 보존하는
`nf_develop_preview_v25`/`nf_develop_export_v25`, ABI 0.32로 완료했습니다. v25 export에도
soft-proof 입력은 없습니다. 소프트 프루프에 **대응하는 내보내기 의미는 만들지 않습니다** — 보기용
시뮬레이션이 인화물에 실릴 경로 자체를 두지 않는 것이 그 계약을 지키는 방법입니다.

rendered digital의 Film Look은 color/motion 27종과 B&W 15종, 전체 42종이 연결됐습니다. color/motion은 halation →
FilmEmulation → 0.5배 stock color preset → density grain, B&W는 halation → spectral emulsion →
acutance → single-channel density grain 순서입니다. macOS 최신 correctness fix에 따라 실제 film scan은
profile이 선택돼도 Film Look identity이며, process/profile kind가 다를 때도 identity입니다. 공통
Texture의 grain/halation은 룩이 실행된 경우에만 중복 적용하지 않습니다.
stock color preset의 원본 RGB scratch는 약 12 MiB 목표 행 타일로 제한됐고 종전 untiled graph와
byte-exact임을 고정했습니다. 대형 실제 촬영 TIFF batch의 process working set과 시간 측정은 남아 있습니다.

- 2026-08-09 x64 Release 재검증: native CTest 30/30, Catalog 303, Shell 200, Interop 44 assertion 통과
- 2026-08-10 x64 Debug 핵심 체크포인트: native CTest 42/42, Catalog 447, Shell 304, Interop 95 assertion 통과
- 2026-08-10 Digital B&W 체크포인트: x64 Debug/Release native CTest 43/43, Catalog 492,
  Shell 305, Interop 95 assertion 통과; ARM64 Debug/Release 관련 target 교차 빌드 통과
- 2026-08-10 Film Emulation 42종 체크포인트: x64 Debug/Release native CTest 43/43,
  Catalog 540, Shell 306, Debug Interop 95 assertion 통과; ARM64 Release 전체 graph 교차 빌드 통과
- 2026-08-10 영역 Defects v18 체크포인트: x64 Debug/Release native CTest 44/44,
  Debug/Release Interop 103 assertion 통과; ARM64 Release component repair·ABI·DLL과 관리 전체 graph
  교차 빌드 통과
- 2026-08-10 Defects sidecar v2 체크포인트: x64 Debug/Release Catalog 583, Shell 313 assertions 통과;
  ARM64 Release 관리 전체 graph 교차 빌드 통과
- 2026-08-10 Defects source identity v19 체크포인트: x64 Debug/Release native 표적 2/2,
  Interop 107, Catalog 583, Shell 314 assertions 통과; ARM64 Release native·managed 관련 target 교차 빌드 통과
- 2026-08-10 Clone Stamp v20 체크포인트: x64 Debug/Release native CTest 45/45,
  Debug/Release Interop 118, Catalog 583, Shell 315 assertions 통과; ARM64 Release 전체 native·managed graph
  교차 빌드 통과(실기 실행 아님)
- 2026-08-10 실촬영 네거티브 체크포인트: 실촬영 fixture 경로 수정으로 x64 Debug/Release native
  CTest **57/57**(종전 46), Interop 139(ABI 0.28), Catalog 583, Shell 316 assertions 통과;
  OpticFilm 8100 5088×3401 두 프레임(무압축 little-endian, LZW big-endian+ICC+alpha)이 게시까지
  통과하고 원본 SHA-256 불변; 실행 중 취소가 decode 단계에서 60.3 ms 반환; ARM64 Release 전체
  교차 빌드 통과(실기 실행 아님)
- 2026-08-10 Brush v21 체크포인트: x64 Debug/Release native CTest 46/46,
  Debug/Release Interop 127, Catalog 583, Shell 316 assertions 통과; 합성 RGB16 TIFF preview·PNG16 export
  실제 변화와 원본 byte-exact 보존 확인; ARM64 Release 전체 native·managed graph 교차 빌드 통과
  (실기 실행 아님)
- 2026-08-11 IR attenuation replay v24 체크포인트: x64 Debug/Release native CTest 61/61,
  Debug/Release Interop 163(ABI 0.31), Catalog 587, Shell 336 assertions 통과; 합성 TIFF의 공통
  preview/export 수학과 원본 bytes·SHA-256 불변 확인; ARM64 Release 전체 native·managed graph와
  IR stage test의 순수 AA64 교차 빌드 통과(실기 실행 아님)
- 2026-08-12 IR item replay v25 체크포인트: 같은 item base에서 exact bbox 사각 patch를 계산·순서 합성하고
  v25 range/order/capacity를 선검증. x64 Debug/Release native CTest 61/61, x64 Release Catalog 592,
  Shell 336, Interop 169(ABI 0.32) assertions 통과; ARM64 Release native·managed 전체 graph 교차 빌드
  통과(실기 실행 아님). 합성 TIFF preview/export 수학 일치와 원본 bytes·SHA-256 불변 확인.
- Windows CI 가 PR 마다 돌고 벽시계 약 2분 30초
- 네이티브 엔진의 제3자 runtime dependency 0개 (Windows 기본 DLL 5개만)
- **카탈로그가 SQLite 로 디스크에 남습니다.** frame 5만 개 기준 쓰기 527ms, 읽기 255ms

**앱의 첫 관통 경로는 존재하지만 제품 UI는 아직 초기 단계입니다.** 현재 Develop 패널은 배관을
검증하려고 만든 임시 표면이며, macOS Negaflow 의 UI/UX를 동일하게 옮긴 정식 Develop inspector,
필름 base picker, 취소·진행률과 나머지 제품 surface가 남아 있습니다. GPU 경로는 착수 전입니다.

## 2026-08-12 현재 재개 지점

현재 Library/Develop 우선순위는 영속화된 folder·availability 데이터를 소비하는 browser projection입니다.
All, Folders, Film Type, Offline을 하나의 순서 보존 frame projection에 연결하고, 전체 목록을 다시 만들지
않는 folder section 표시를 붙입니다. folder import는 top-level TIFF만 가져오고 빈 등록 folder를 보존하며,
기존 atomic catalog 저장 경계는 유지합니다. 그 다음 source-folder file-system refresh/relink를 Print 확장보다
먼저 구현합니다.

## 2026-08-10 이후 새로 알게 된 것 — 먼저 읽으십시오

**1. 실촬영 fixture 를 쓰는 테스트가 오래 죽어 있었습니다.** `CMakeLists.txt` 의
`NEGAFLOW_SOURCE_TIFF_FIXTURE` 경로가 한 세그먼트 짧아 `if(EXISTS)` 가 항상 거짓이었고, 실촬영
검사가 전부 조용히 합성 전용 분기로 떨어졌습니다. 고친 뒤 등록 테스트가 **46 → 57**로 늘었고,
되살아난 것 중 3건이 낡은 기대를 갖고 있어 함께 고쳤습니다. **앞으로 "실촬영으로 검증했다"고
쓰기 전에 그 테스트가 실제로 fixture 인자를 받았는지 확인하십시오.**

**2e. 도달 가능성 확인이 진짜 기능 공백을 찾습니다.** macOS 소스에 있는 것 중 실제로
불리는 것만 골라 보니 `AutoAdjust`(자동 보정)가 Windows 에 통째로 없었습니다. 네이티브 계산은
구현했고 **ABI(0.29)와 셸 조정자까지 연결했습니다**(`../implementation/auto-adjust.md`).
남은 것은 WinUI 버튼 연결(UI 단계)과, 잘 현상된 중립 프레임에서의 품질 확인입니다.

**2f. 같은 방식으로 찾은 `SoftProof` 는 용지·잉크 시뮬레이션까지 구현했습니다**
(`../implementation/soft-proof.md`). 여기서 배운 것이 하나 더 있습니다. **macOS 계산을 그대로
옮기는 것만으로는 부족할 때가 있고, 그 차이는 계산이 아니라 입력이 어디서 오는지에서
생깁니다.** macOS 는 프로파일을 CGColorSpace 가 재직렬화한 형태로 받으므로 `wtpt` 가 항상 D50
입니다. Windows 는 파일을 그대로 읽고, ICC v2 프로파일은 보정되지 않은 D65 를 담아도 됩니다 —
실제로 이 기계의 시스템 sRGB 와 Adobe RGB 가 그렇습니다. 곧이곧대로 옮겼다면 sRGB 를 프루프
목적지로 고르는 순간 화면이 파래졌을 것이고, 그것은 macOS 에서는 절대 나오지 않는 결과입니다.

앞으로 macOS 로직을 옮길 때 **그 로직에 들어가는 값이 어떤 경로로 만들어졌는지**까지 확인하십시오.

남은 것은 목적지 색공간 변환과 `DestinationGamutWarning`(mscms `CheckBitmapBits`)입니다.

**2g. 필름 베이스 추정은 이미 macOS 와 같습니다 — 재확인했습니다.** 사용자 요청으로
`FilmBaseEstimator.swift` 를 함수·상수 단위로 다시 대조했고 빠진 것이 없었습니다. 실제 필름
5장이 전부 1차 경로(연결 성분)로 측정됩니다.
`../verification/2026-08-10-film-base-parity.md`.

**2f. macOS 와의 색 차이는 종결됐습니다.** 2026-08-10 사용자가 직접 확인한 결과 차이는
**암부에서 8비트 256 단계 기준 2~7** 이며 실질적으로 의미가 없습니다. ADR-0024(ColorSync 의
toe 를 재현하지 않음)를 유지하고, **"macOS pixel golden 이 없어 수치 동등성을 모른다"는 표현은
더 이상 쓰지 않습니다.** 남은 수치 위험은 아래 blur 반경 하나입니다.

**2d. 커널 수식 대조는 macOS 호스트 없이도 할 수 있습니다.** Core Image 가 실행하는 Metal
커널 소스가 `negaflow-mac/.../ChromabaseMetalKernels.swift` 에 상수까지 들어 있습니다. 9개 단계를
대조해 전부 일치를 확인했고 차이는 표시 경계 하나였습니다 —
`../verification/2026-08-10-macos-kernel-audit.md`. **남은 수치 위험은 Apple 내장 필터
(`CIVibrance`·`CIUnsharpMask`·`CIGaussianBlur`)와 부동소수점 마지막 자리**로 좁혀졌습니다.

**2c. macOS 소스 대조는 실제로 차이를 찾아냅니다.** Texture 는 순서·상수가 전부 일치했지만,
같은 방식으로 표시 경로를 대조하다 **미리보기에 soft clip 과 dither 가 통째로 빠져 있는 것**을
찾았습니다. 게시 경로는 오히려 맞았습니다(16비트는 macOS 도 dither 를 걸지 않음). 앞으로도
"어느 경로에 걸리는가"를 함께 보십시오 — 조건까지 봐야 진짜 차이가 보입니다.

**2b. 공간 필터는 타일 core 가 겹치지 않는다는 사실이 열쇠였습니다.** FilmScanDenoise 와
Texture 의 blur 는 둘 다 타일마다 apron 을 읽되 자기 core 에만 씁니다. 그래서 타일 행을
나누는 것만으로 각각 `5.09배`·`5.04배`가 나왔고 픽셀은 그대로였습니다. 다음에 공간 필터를
볼 때도 **먼저 "무엇이 독립 단위인가"를 확인**하십시오 — 대개 이미 거기 있습니다.

**2a. 두 번째로 잰 곳도 짐작과 달랐습니다.** pointwise 를 정리한 뒤 미리보기 단계 비용을 다시
재 보니 Texture `+844 ms`, GrainMend `+1,474 ms` 옆에서 **FilmScanDenoise 가 `+11,711 ms`** 였습니다.
짐작으로 Texture 부터 손댔으면 헛수고였습니다. **매번 재고 나서 고치십시오.**

**2. 현상 시간은 짐작과 다른 곳에 있었습니다.** 3278×4944 기준 decode 는 전체의 3.4% 뿐이고
`develop`(반전)과 `tone` 이 각각 1.9초·2.1초였습니다. 둘 다 완전한 pointwise 커널인데 한
스레드에서 돌고 있었습니다. 행 블록 병렬 실행으로 각각 7배 이상 줄였고 **출력 바이트는 동일**
합니다. 다음에 속도를 볼 때도 **먼저 재고 나서 고치십시오** — 상세는
`../implementation/parallel-row-execution.md`.

**3. export 시간의 약 86%는 이제 `output` 입니다.** WIC PNG deflate 와 게시 후 전체 픽셀
readback 검증이며 둘 다 WIC 내부의 단일 스레드 zlib 입니다. 인코더를 바꾸면 산출물 바이트가
달라지고 ADR-0004 에 어긋나므로 손대지 않았습니다. **미리보기 경로에는 이 비용이 없으므로
대화형 응답성과는 무관합니다.**

**4. Photoshop 계열 다중 IFD TIFF 를 엽니다.** `NewSubfileType` 으로 축소 미리보기와 투명도
마스크를 동반 페이지로 구분하고, 전체 이미지가 정확히 하나일 때만 진행합니다. 다중 페이지
문서는 계속 거부합니다. 디코더는 **프레임 번호를 디렉터리 번호로 가정하지 않습니다** — WIC 는
축소 페이지를 프레임으로 노출하지 않으므로 probe 치수와 일치하는 프레임을 고릅니다.
**8비트 TIFF 입력도 엽니다.** WIC 가 바이트 복제(`v * 257`)로 16비트 대상 형식에 넓히므로
working 변환 뒤 `v / 255` 와 정확히 같고, 실제 파일과 합성 회귀 양쪽에서 확인했습니다.
남은 입력 형식 공백은 **SubIFD(태그 330) 미리보기**입니다.

## 현재 최우선: Chroma Engine과 GrainMend 품질 동등성

사용자가 체감하는 현상 품질을 카탈로그 주변 내구성보다 먼저 닫습니다. 다음 구현 순서는 아래와 같습니다.

**최신 GrainMend IR delta가 최우선입니다.** optional R16 attenuation replay와 paired visible/IR의
true-scale closing → area-weighted candidate → defect-local alignment/visible confirmation → null/MAD →
significance-dependent inverse-Mills → attenuation/core native 검출 코어와 ABI 0.33, managed coordinator,
sidecar 영속 lifecycle, preview/export 공통 request 투영은 완료했습니다. ABI 0.34는 RGB16 visible과
Gray16/RGB16 IR TIFF 쌍을 직접 row decode합니다. 색상 네거티브와 색상 슬라이드는 허용하고 silver
image가 IR을 막는 흑백 네거티브·포지티브는 거부합니다. scanner publication은 committed artifact 쌍의
companion IR 경로를 frame/catalog에 보존하고, durable RGB frame 뒤에 `RunFiles`를 호출합니다. 그 뒤 같은 입력의
macOS-hosted mask·R16 attenuation·최종 pixel golden을 통과하기 전에는 GrainMend IR 완전 동등성을 주장하지 않습니다.

Color/B&W positive film scan은 catalog `CanDevelop` 게이트까지 열어 Dmin/base를 건너뛰는 공통 preview/export와
컬러 슬라이드 GrainMend IR 경로에 도달합니다. 실제 슬라이드 TIFF에서의 macOS pixel golden은 아직 남아 있습니다.

최종 출력 선명화는 ABI 0.36/C# 공통 preview/export 경계까지 연결했습니다. 실제 촬영 TIFF의 macOS pixel golden과
매체별 DPI 비교가 남아 있으며, 이 비교 전에는 최종 출력 선명화의 완전 동등성을 주장하지 않습니다.

평판 스캐너의 최신 frame-grid 검출은 ABI 0.35/C# owned-handle 경계까지 올라왔습니다. scanner host가 preview의
실제 mm 영역과 정규화 luminance를 넘기는 C ABI, 그리고 같은 preview의 macOS golden 비교가 다음 연결 작업입니다.

1. ~~GrainMend 자동 검출을 채널별 top-hat(4/8/12), 원거리 texture/SNR, 8방향 scratch 적분,
   isolation/grain-field/PCA component gate로 분리 이식하고, 1800px 초과 linear Lanczos 축소와
   연속 affine mask blend를 연결합니다.~~ **구조 구현 완료.** v9은 반복 grid와 이어지는 scene line,
   1400px core·80px effective halo의 원본 해상도 자동 검출과 종류별 전역 component stitch를 포함합니다.
   thin scratch labeled evidence, hysteresis, sensitivity별 shape gate와 1600px core 경계 scratch
   회귀로 stitch seam도 고정했습니다. x64 Debug 전체 native 43/43과
   x64 Release GrainMend·ABI 회귀를 통과했습니다.
   ARM64 Release 관련 target도 교차 빌드했습니다. FILM-R v2 44쌍 x64 Release 결과는
   평균 `+0.332190 dB`, 중앙 `+0.216207 dB`로 올라 절대 quality floor 8개 조건을 모두 만족했고,
   config의 역사적 `+0.465934 dB` 관측값보다 평균이 낮습니다. 그러나 그 관측값은 2026-07-25의
   이전 자동 중지 정책 결과이고 고정 기준이 포함하는 다음 날 결과 유지·경고 변경 뒤 재측정되지
   않았으므로 현재 macOS parity oracle로 쓰지 않습니다. **다음 GrainMend 품질 작업은 고정 소스를
   macOS host에서 같은 44쌍에 다시 실행해 per-image mask·pixel report를 고정하는 것**입니다.
2. component별 구조/질감 복원 native 코어를 구조 채움과 texture transfer의 독립 파일로 구현했습니다.
   원본-only 8방향 얇은 보간, structure support 선택, thick component onion-peel, 넓은 guided mask
   refinement와 exemplar residual 전사가 x64 Debug/Release 전체 native `44/44`, ARM64 Release 교차
   빌드를 통과했습니다. 이 고급 복원은 macOS의 영역 Defects 편집 경로 계약이며 전역 자동
   PostPipeline의 `CIMedianFilter` 폴백을 대체하지 않습니다. ROI y-up/top-first mask와 strength·preferred
   angle을 ABI v18과 관리 Interop에 싣고, decode 뒤 음화 현상 전의 공통 preview/export 경로에
   순서대로 재적용하는 경계까지 연결했습니다. 합성 RGB16 TIFF에서 preview·PNG16 export의 실제 변화,
   원본 byte-exact 보존과 out-of-frame fail-closed를 고정했습니다. revision-aware catalog sidecar와
   재시작 재적용, backup/pending restore 동일 세대 교체도 연결했습니다. ABI v19는 비어 있지 않은 recipe의
   source byte count·SHA-256을 렌더 직전에 CNG로 재검증하고 불일치 시 preview/export를 모두 중단합니다.
   Clone Stamp는 normalized y-down 좌표, 정수 source offset, RGBA16 full-strength patch, layer strength,
   stroke 및 region/clone 교차 순서를 ABI v20과 공통 preview/export에 연결했습니다. Brush도 normalized
   y-down 좌표, 짧은 raw 변 대비 두께, chunk/halo, sRGB texture displacement·tone matching, feather와
   item strength를 ABI v21로 연결해 region/infrared/clone/brush 순서를 보존합니다. 합성 RGB16 TIFF에서
   Clone Stamp와 Brush 모두 preview·PNG16 export의 실제 변화와 원본 byte-exact 보존을 고정했습니다.
   **다음 영역 Defects 작업은 같은 입력의 macOS Clone Stamp/Brush pixel golden과 실제 촬영 TIFF 검증**입니다.
   morphology opening/closing만 process 전체 background worker 하나로 겹쳐 3장 smoke를
   `5.3~6.9초 → 3.6~4.6초`로 줄였고 전체 44장 결과는 byte-exact입니다. 실제 촬영 TIFF와 수백 장
   batch에서 scheduler 전체 처리량·메모리를 검증하는 일은 남아 있습니다.
   전체 자동 mask에 영역 component repair를 직접 대입하는 실험은 dust 0px/2px 모두 선택한 3장에서
   큰 PSNR 회귀를 만들어 제거했습니다. user-reviewed 영역 Defects와 전역 자동 median 경로를 섞지
   않으며, 동일 입력 macOS pixel golden 전에는 복원 코어를 대체하지 않습니다.
3. 컬러 네거티브 비프리셋 경로의 muted-scene vibrance 장면 측정·gate·Windows 저채도 우선
   pixel 수학을 preview/export 공통 경로에 추가했습니다. preset/B&W/고채도/tiny identity와
   x64 Debug/Release, ARM64 교차 빌드를 고정했습니다. Auto FilmBase도 가로축 단일 scale의
   pixel-center bilinear 격자 하나를 모든 측정 경로가 공유하도록 정렬했습니다. **남은 일은 같은 입력의
   macOS Core Image sampled-grid와 `CIVibrance` 관측 fixture로 허용오차를 확정하는 것**입니다. preset의 confident measured Dmin
   선택도 수정됐고, Auto base 연결 성분은 macOS와 같은 luma MAD 이상치 제거 뒤 채널 중앙값을
   사용합니다. grid 추정이 모두 실패하면 sparse scene-edge 후보의 채널 p90을 측정한 뒤에만 상수
   Dmin으로 떨어집니다. 실제 5088×3401 TIFF의 Film request는 `preset_measured`로 검증·게시까지 통과했습니다.
   반전 직전 scene-range proxy와 Auto FilmBase sampled-grid를 macOS 소스의 uniform pixel-center bilinear
   affine 계약으로 맞췄습니다. 연결 성분 첫 하위 모드·상위 R−B 중앙값, Double edge/coverage와 마지막
   scene-edge affine fallback도 정렬했습니다. FilmBase의 luma·percentile·median·MAD·threshold·채널 통계는
   macOS처럼 Float RGB를 Double로 승격해 계산하고 최종 공개 Dmin에서만 Float로 내립니다. **다음 수치
   작업은 같은 입력의 macOS Core Image sampled-grid와 `CIVibrance` pixel golden으로 실제 허용오차를
   고정하는 것**입니다. 최종 촬영 TIFF pixel golden은 아직 없습니다.
4. rendered digital B&W 15종과 color/motion 27종은 registry→catalog/ABI→preview/export 공통 그래프까지
   완료했습니다. **다음 Film Emulation 작업은 새 color/motion 16종의 macOS Core Image pixel golden과
   실제 촬영 TIFF 비교**입니다. B&W acutance sigma·grain 통계 허용오차도 같은 hosted macOS
   체크포인트에서 고정합니다.
5. full-resolution tile 검출 workspace 재사용은 완료했고, 다음은 대형 TIFF·수백 장 batch 처리량을
   측정해 per-frame full-buffer 할당과 장기 메모리 급증을 제거합니다. 첫 수명 단축으로 3장 smoke의 결과를
   byte-exact 유지하면서 peak working set을 `383.86 → 363.86 MiB`로 줄였고, scratch 각도 작업자
   상한을 4개에서 2개로 낮춰 같은 결과에서 `343.82 MiB`까지 더 줄였습니다. 세 장 시간은 직전보다
   `2.2~4.9%` 늘었으므로 이 단계는 속도 향상으로 세지 않습니다. 이어 작업자별 workspace를 네 각도
   묶음에서 재사용해 사진당 full-map vector storage 할당을 `16회 → 4회`로 줄였습니다. 두 번의 3장
   smoke는 byte-exact였고 worker-2 기준보다 `2.7~3.9%` 짧았지만, peak는 `348.80 MiB`로 이전
   단일 측정보다 `4.98 MiB` 높아 메모리 절감으로 주장하지 않습니다. 이어 타일별 검출 5개 float map,
   후보 3개 map과 evidence map의 capacity도 사진 단위로 재사용했습니다. 두 실행 모두 같은 SHA-256을
   유지했고 합산 시간은 직전보다 `1.2%` 짧았으며 peak는 `344.40/344.41 MiB`로 `4.40 MiB` 낮았습니다.
   다음은 같은 품질 fixture를 유지한 채 대형 TIFF와 수백 장 batch 처리량·장기 peak를 측정하는 것입니다.

defect sidecar는 닫았습니다. catalog fault harness 중 process-kill/disk-full/power-loss의 디렉터리 교체
중단 복구는 위 현상 품질 체크포인트 뒤에 남기며, 현재는 unresolved swap artifact를 fail-closed합니다.

**한 가지 사실이 바뀌었습니다.** 제품 payload 에 제3자 native 바이너리(`e_sqlite3.dll`)가
처음 들어왔습니다. 네이티브 엔진의 0개는 그대로지만 두 문장은 이제 다른 뜻입니다. ADR-0025.

## 닫힌 결정 — 다시 열지 마십시오

| 결정 | 내용 |
|---|---|
| ADR-0004 | 이미지·색상은 OS API 우선. **유효합니다.** |
| ADR-0017 | Windows `src`/`tests` 만 1차 native source, vendoring 금지 |
| ADR-0021 | macOS golden 은 test-only 관측. 관측 float 총량 512 상한 |
| ADR-0022 | 미사용 WebView2 페이로드 미배포 |
| ADR-0024 | ColorSync 의 섀도우 toe 를 재현하지 않음 |
| ADR-0025 | catalog SQLite 는 관리 계층에서 열고 native SQLite 를 따로 고정. "의존성 0개" 는 네이티브 엔진에만 적용 |
| ADR-0027 | 코드 서명 철회. 설치 파일은 서명 없이 배포하므로 MSIX 대신 WiX/Inno. ARM64 실기 검증은 사용자 담당 |

**LittleCMS 검토는 폐기됐습니다.** 색 차이의 원인이 Windows CMS 선택이 아니라 ColorSync 가 ICC
사양에서 벗어나 있다는 사실이므로, Windows 에서 CMS 를 교체해도 macOS 와 같아지지 않습니다.
`overall-roadmap.md` 의 해당 항목은 이 사안에 한해 무효입니다.

---

## 1. SQLite 영속성 — 첫 왕복은 끝났습니다

**종료 조건("앱을 껐다 켜도 카탈로그가 남고 source 종류와 stage 순서가 바뀌지 않는다")을
충족했습니다.** ADR-0025, `verification/2026-08-07-sqlite-catalog-store.md`.

들어간 것:

- `SqliteCatalogStore` — `catalog_metadata` + entity table 9개, 물리 `user_version` 과 논리
  `catalog_version` 분리, 단일 `BEGIN IMMEDIATE` transaction, commit 후 `integrity_check`
- missing / corrupt / 미래 물리 version / 외부 논리 version / malformed payload 를 각각 다른
  값으로 거부. 어느 것도 빈 라이브러리가 아니고 부분 snapshot 도 없음
- `Pooling=False`. 켜 두면 backup 교체와 pending restore 가 남은 핸들에 막힙니다
- 재정렬 시 position relocation. 이것이 없으면 frame 3개 재정렬만으로 쓰기가 실패합니다
- `CatalogSession` — 유일한 공개 입구. store 는 `internal` 이라 lock 을 우회할 수 없습니다

**계획과 달랐던 것 두 가지.** 첫째, 편의 package `Microsoft.Data.Sqlite` 를 쓸 수 없었습니다.
native SQLite 하한이 CVE-2025-6965 대상이라 restore 가 NU1903 으로 실패합니다.
`Microsoft.Data.Sqlite.Core` + `SQLitePCLRaw.config.e_sqlite3` + `SourceGear.sqlite3` 로 나눠
참조합니다. 둘째, 고지는 "MIT 한 절" 이 아니라 MIT 1건 + Apache-2.0 4건입니다.

### 다음 행동: 나머지 수명주기

`windows_docs/14-persistence/catalog-and-storage.md` 가 소유하는 것 중 아직 없는 것입니다.
**순서를 지키십시오.** 아래는 뒤가 앞을 필요로 합니다.

1. ~~`CatalogProcessLock` 과 store 를 하나의 open 경로로 묶기.~~ **완료.** `CatalogSession` 이
   유일한 공개 입구이고 store 는 `internal` 입니다. lock 을 못 잡으면 세션이 만들어지지 않습니다.
2. **commit verifier와 raw 직전 primary 보존. 동기 구현 완료.** 커밋 전용 UUID snapshot을 고정 rollback
   source로 사용하고, `library.backup.sqlite`를 별도로 갱신합니다. 새 연결 full canonical readback,
   write/readback 실패 원복, rollback 실패 뒤 mutation 차단까지 연결했습니다. process-kill/disk-full/
   power-loss fault gate는 남아 있습니다.
3. **immutable logical backup 세대. authoritative v3 완료.** canonical `library.json`과 선언된 모든
   Defects sidecar, v3 manifest/hash, monotonic sequence, staging·final 재검증, valid 세대 기본 3개
   retention을 구현했습니다. future·damaged 세대는 prune하지 않습니다.
4. **pending restore. 완료.** 선택 세대를 private copy로 고정하고, 다음 `CatalogSession.Open`에서만
   현재 catalog safety generation을 만든 뒤 catalog와 Defects sidecar를 같은 세대로 적용합니다. future
   version은 차단하며 applied marker로 cleanup 실패를 재시작에서 안전하게 재시도합니다.
5. **defect sidecar. 완료.** revision-aware writer, temp → flush → atomic replace/readback, stale completion
   차단과 same-revision conflict를 구현했습니다. catalog가 defect edit을 선언했는데 sidecar가 없거나
   손상됐으면 library open을 차단합니다.

**셸을 붙일 때 쓸 것:** `CatalogSession.Open(roots)` → `ReadOrCreate()` → `Write(snapshot)` →
`Dispose()`. `ReadOrCreate` 가 없는 카탈로그를 만드는 유일한 자리이며, 손상이나 알 수 없는
version 은 거기서도 실패합니다. **어디서도 `NotFound` 를 빈 라이브러리로 바꾸지 마십시오.**

legacy JSON → SQLite migration 은 **하지 않습니다.** Windows 에는 옮겨올 legacy 파일이 없습니다.
macOS catalog 를 여는 것은 결정 4에서 이미 배제했습니다.

**종료 조건: 쓰기 도중 프로세스를 죽여도 다음 실행에서 카탈로그가 열리고, 무엇이 손실됐는지
말할 수 있다.**

---

## 2. 세로 슬라이스 — 첫 관통 완료, 정식 UI/UX 이식이 다음입니다

`카탈로그 → C ABI → WinUI 셸` 첫 관통은 완료됐습니다. 이제 임시 Develop 표면을 macOS Negaflow의
실제 UI/UX와 동일하게 이식하는 것이 최우선입니다. 배관은 유지하되 표면을 창작하지 않습니다.

### 진행 상황

`nf_develop_export_v22` 와 `nf_develop_preview_v22` 를 포함한 현재 ABI 는 **0.28**입니다. 게시와
미리보기는 같은 요청 구조와 파이프라인을 사용하며, 관리 쪽 `NativeDevelopExporter`가 감쌉니다.
실패는 **거부한 단계 + 그 단계 자신의 상태 이름**으로 돌아오므로, 없는 파일
(`observe_source_before`) 과 잘못된 요청 (`request_validation`) 이 구별됩니다.

완료된 셸 관통 경로는 다음과 같습니다.

1. `CatalogSession` 으로 카탈로그를 열고 frame 목록을 Library/Develop 에 표시합니다.
2. Windows App SDK file picker 로 TIFF 를 import 하고 필름 base와 노출을 저장합니다.
3. `PreviewCoordinator` 가 `DevelopRun`으로 겹친 렌더를 취소하고 마지막 상태를 보존합니다. IR v25
   미리보기는 현재 WIP라 제품 경로 완료로 보지 않습니다.
4. Export 버튼이 `NativeDevelopExporter.Run` 을 호출하고 검증된 결과 파일을 씁니다.

**스레딩을 여기서 틀리면 안 됩니다.** `NativeDevelopExporter.Run` 은 현상 전체 동안 블로킹하며,
일부러 async 래퍼를 두지 않았습니다. UI 스레드에서 부르면 앱이 굳습니다. 백그라운드로 보내기
**전에** `DispatcherQueue` 를 캡처하고, 결과는 `TryEnqueue` 로 되돌리십시오. 아래 함정 절을
그대로 따르면 됩니다.

**취소와 진행률은 ABI v22/0.28 로 들어왔습니다.** caller 소유 정수 3개(`cancel_requested`,
`stage`, `progress_permille`)를 공유하고 콜백은 경계를 넘지 않습니다. 실촬영 5088×3401 에서
실행 중 취소가 `decode` 단계에서 `60.3 ms` 만에 반환했고(미취소 export 는 `3,323 ms`) 파일을
게시하지 않았습니다. 관리 쪽 입구는 `DevelopRun` 이며 `CancellationToken` 을 받습니다.

**셸의 `PreviewCoordinator` 가 이미 사용합니다.** 겹친 요청이 들어오면 돌고 있던 렌더를 즉시
취소하고, 취소된 결과는 픽셀이 없으므로 배달하지 않습니다. GrainMend 안에도 확인 지점을 넣어
같은 프레임에서 미리보기 `2,014.7 ms → 835.0 ms`(GrainMend 를 약 1,290 ms 다 돌지 않고 약
113 ms 에 중단)를 확인했습니다.
FilmScanDenoise 도 타일 행마다 확인하며, 같은 변경에서 미리보기가 `15,004.7 → 2,949.7 ms`
(5.09배)로 줄고 픽셀 fingerprint 는 그대로였습니다.
**남은 일은 WinUI 의 취소 버튼·진행 막대 연결**입니다. Local Dodge/Burn 은 조정 하나가
`221 ms` 로 줄어 단계 경계 확인으로 충분합니다.

다음 목표는 기능 수를 늘리는 것이 아니라, 이미 뚫린 경로를 macOS 제품과 동일한 UI/UX에 연결하는
것입니다. 화면 구조·치수·간격·컨트롤 순서·상태 전이·키보드·접근성 의미를 고정 기준에서 추출하고
WinUI 3 로 그대로 구현합니다. 운영체제가 강제하는 차이만 별도 delta 로 기록합니다.

### UI 는 창작하지 않습니다 — macOS 를 그대로 이식합니다

**현재 Develop 패널의 XAML 은 배관을 돌려 보려고 임시로 만든 것이며 버릴 것입니다.** Import 버튼,
필름 base 슬라이더 3개, 노출 슬라이더, Export 버튼, 상태 문구는 전부 macOS 에 대응물이 있거나
아예 다른 형태입니다.

이식 대상은 `negaflow-mac/Sources/negaflowApp/Features/Develop/Inspector/` 이며 순서는
`DevelopAdjustmentSections.swift` 가 정의합니다.

1. `basicToneSection`
2. `toneCurveSection` — `ToneCurveEditor.swift`
3. `colorSection`
4. `colorMixerSection` — `ColorMixerSection.swift`
5. `colorGradingSection` — `ColorGradingSection.swift`
6. `bwToningSection` — 흑백일 때만
7. `calibrationSection`
8. `detailSection`

필름 base 는 `BaseControlSection.swift` 가 소유합니다. 제가 만든 raw 슬라이더 3개가 아닙니다.
`FilmEmulationSection.swift`, `DevelopQuickActionsSection.swift`, `InteractiveHistogramView.swift`,
`InspectorSlider.swift`/`ResettableSlider.swift`/`EditableSliderValueText.swift` 같은 공통 컨트롤도
그쪽 구조를 따릅니다.

치수는 `baseline/swift-ui-metrics.json` 처럼 macOS 소스에서 가져옵니다. **판단으로 정하지
마십시오.** macOS 에 대응물이 없는 것이 필요하면 지어내지 말고 물어보십시오.

**배관은 이식 대상이 아닙니다.** C ABI, coordinator, 스레딩, 카탈로그는 Windows 쪽 설계입니다.
바뀌는 것은 표면뿐입니다.

### 왜 이것이 파이프라인 확장보다 먼저인가

지금까지 28단계를 CLI 로만 검증했습니다. CLI 검증은 앱에서 가장 위험한 것들을 **전부 우회합니다** —
UI 스레딩, 취소, 객체 수명, 사용자 조작 중 메모리 압박, C ABI 경계의 예외 전파.

구성요소를 격리해 만들면 통합 리스크가 프로젝트 끝으로 밀립니다. 데이터 계약과 지연·출력 형식이
뒤늦게 깨지고, 그때는 이미 각 구성요소를 최적화해 둔 뒤라 재작업 비용이 큽니다. 얇더라도 끝까지
한 번 뚫어 두면 구조와 패턴이 자리를 잡고 기본이 동작한다는 것이 증명됩니다.

첫 앱 경로가 동작해도 M9~M14 제품 표면 대부분은 남아 있습니다. UI 와 장치 연동처럼 검증이 어렵고
되돌리기 비싼 작업이 뒤에 몰려 있으므로, 임시 화면을 제품 완성으로 세지 않습니다.

### 미리 알아 둘 함정

WinUI 3 는 **STA** UI 모델입니다. 모든 UI 요소는 그것을 만든 스레드가 소유하고 그 스레드의
`DispatcherQueue` 에 묶입니다.

- 백그라운드 스레드에서 컨트롤을 건드리면 **예외가 납니다.**
- UWP 의 ASTA 와 달리 **reentrancy 보호가 없습니다.** 메시지를 펌프하는 async 코드에서 XAML
  컨트롤로 재진입하는 경로를 주의해야 합니다.
- 결과를 UI 로 돌릴 때는 `DispatcherQueue.TryEnqueue` 를 씁니다. 백그라운드 작업에 들어가기
  **전에** `DispatcherQueue` 를 캡처해 두는 편이 깔끔합니다. `HasThreadAccess` 로 확인할 수 있습니다.
- C++/WinRT 쪽 수명은 `winrt::implements` 파생과 `[this, self=get_strong()]` 캡처로 잡습니다.

이 함정들은 CLI 에서 절대 드러나지 않습니다. 세로 슬라이스를 미루면 이것들을 M9 이후에 한꺼번에
만나게 됩니다.

**첫 관통 종료 조건은 충족했습니다.** 실행 중인 앱에서 Import → base 설정 → 노출 → Export 를
UI Automation 으로 조작해 `Exported 631×403 in 101 ms`를 확인했습니다. 이후 ABI 0.5
`nf_develop_preview_v1`, 이어 Auto/Manual을 명시하는 ABI 0.6 v2와 WinUI 캔버스 렌더가 추가됐습니다. 관통 근거는
`verification/2026-08-07-vertical-slice.md`, 미리보기 구현·테스트 근거는 `bb8d248`와 `98df788`입니다.

**공통 slider/value control의 현재 연결은 Exposure와 수동 Base R/G/B입니다.** 고정 baseline의
inspector 구조와 `baseline/swift-ui-metrics.json`을 기준으로 label·편집값·slider·keyboard nudge를
재사용 control로 묶었습니다. Exposure만 double-click reset을 제공하며 수동 Base는 reset하지 않습니다.
구현과 x64 증거는 `implementation/develop-inspector-slider.md`에 기록했습니다.

**Base recipe의 Catalog persistence 경계와 첫 Auto v2 경로가 완료했습니다.** `baseEstimationMode`, film stock,
light source, scanner profile ID는 수동 Dmin과 독립적으로 보존됩니다. Auto는 ABI 0.6의 별도 request로
decode 후 linear working image edge를 측정해 scene-ranged inversion에 전달하며, Preview와 Export가 같은
resolver 결과를 사용합니다. v1 수동 ABI는 유지합니다. 이 resolver는 macOS의 scene-edge fallback만 이식한
`FilmBaseEstimator` sampled-grid fallback과 chromogenic B&W 재시도, bundled film-stock/light-source resolver,
Film mode picker, ABI 0.10 preview/export 연결은 구현되었습니다. Histogram과 6-tab strip,
전폭 single-surface disclosure, Basic Tone/Parametric Tone Curve/Point Curve/Color Mixer/Color Grading의
첫 rendered/UIA 체크포인트도 완료했습니다. 다만 고유 Edit/Defects/Info/Reset tab content와 나머지
adjustment sections, compact/high contrast/ARM64 runtime은 아직 별도 작업입니다.

### 사용자 우선순위와 구현 원칙

직접 보이는 UI/UX와 사진·현상·보정 결과, Chroma Engine, GrainMend는 고정 macOS 기준을 따릅니다.
그 밖의 내부 구조·라이브러리·함수는 1:1 이식을 목표로 삼지 않고, 단순하고 유지 가능한 Windows 네이티브
구현을 우선합니다. UI 잔여 작업보다 현상 백엔드를 먼저 진행하며, 결과 차이를 잡지 못하는 중복 검증은
추가하지 않습니다.

Local Dodge/Burn은 ABI v12, ColorModel은 v13, Auto Levels/Neutral Balance는 v14, DevelopTarget과
EXPIRED RescueGrade는 v15까지 catalog → Shell → native preview/export 연결을 완료했습니다.
macOS manifest v2의 15개 scanner profile에서 현상에 필요한 bounded 수치와 profile hash만
Windows 네이티브 immutable registry로 고정했고, `scannerProfileID`를 ABI v16으로 전달해
ScannerProfileGrade를 preview/export에 연결했습니다. 현재 macOS bundle에서 scanner monochrome tint는 근거 데이터가 없어 의도적으로 no-op이므로
Windows에 임의 효과를 만들지 않습니다. M3의 독립 Deflate preflight validator와 pending restore
safe-start는 완료했습니다. 현재 CPU kernel은 전부 baseline scalar이고 상위 ISA variant가 없으므로
동작 없는 dispatcher는 만들지 않습니다. NORITSU/SP-3000/F135/HR의 문서 기반 tone·Lab color·texture와
NORITSU/SP-3000의 Ektar 100·Portra 160 matched-pair 상대 signature를 공용 preview/export에 연결했습니다.
pair가 없는 profile과 F135/HR에는 근거 없는 상대 효과를 만들지 않습니다. color/B&W와 polarity를
분리한 ABI v17로 color negative, B&W negative, color positive, B&W positive 4상태를
catalog→Shell→native preview/export까지 연결했습니다.
최신 macOS의 Film Emulation 42종 profile-kind 계약은 Windows registry와 실제 pipeline까지 연결했습니다.
Film Emulation의 다음 hosted golden도 남아 있지만, **현재 다음 한 걸음은 같은 paired TIFF를 macOS host에서
검출해 mask·R16 attenuation·최종 pixel golden을 고정하는 것**입니다. 수치 golden은 실제 화면 결과 차이를 잡는
대표 profile·장면에 집중합니다.

---

## 3. GPU 스파이크 — 버릴 코드로

M5 전체가 아니라 **스테이지 하나만** D3D11 로 던져 보고, FP32 결과가 기존 scalar golden 의
허용오차 안에 드는지 확인하는 정도입니다.

현재 모든 수치 계약이 CPU scalar 기준으로 고정돼 있습니다. macOS 는 Core Image(GPU)로 돌고
Windows 는 scalar 로 맞췄으며 앞으로 D3D11/WARP 가 들어옵니다. 세 구현이 서로 허용오차 안에
있어야 하는데, GPU 는 결합 순서와 정밀도가 CPU 와 미묘하게 달라 지금 잡아 둔 2.1e-3 / 4.0e-4 가
유지될 보장이 없습니다.

20단계를 scalar 가정 위에 다 쌓은 뒤 알면 golden 체계를 다시 설계해야 합니다. 세로 슬라이스
작업 중 어디쯤에서 하루 던져 보는 것으로 충분합니다.

**중요: golden 허용오차를 조이지 마십시오.** 세 구현은 각각 **하나의 기준(Core Image)** 과
비교돼야 합니다. 서로 사슬처럼 비교하면 오차가 누적됩니다.

---

## 4. 그 외 (순서 무관)

- 스캐너 호스트(M15): 플러그인은 이미 있으므로 **프로토콜 v2 클라이언트 구현 + 실제 장치 검증**
  입니다. 자세한 내용은 아래 결정 11번을 보십시오.
- 최종 working buffer 와 출력을 downstream row/tile 소비자로 넘기고 전체 process budget 을
  적용합니다. (M7, 현재 6%)
- WinUI 셸의 축소 폭·DPI·High Contrast·keyboard matrix 를 검증합니다.
- 나머지 Develop 후처리 단계를 macOS 실행 순서대로 이식합니다.

---

## 하지 않기로 한 것

**다점 TRC 프로파일의 ColorSync 측정.** 한때 다음 작업 1순위로 적었으나 철회합니다.

ADR-0024 가 이미 "재현하지 않는다" 로 결정했으므로, 측정 결과가 어느 쪽이든 **지금 하는 행동이
바뀌지 않습니다.** 차이의 크기도 8비트 코드 255단계 중 2~6, 그것도 하이라이트에 한정됩니다.
행동을 바꾸지 않는 측정에 macOS 세션과 CI 시간을 쓰는 것은 비용 대비 효과가 맞지 않습니다.

ADR-0024 의 재검토 조건이 실제로 발생하면 그때 합니다. 그 조건과 재현 방법은 ADR 에 이미 적혀
있으므로 다시 조사할 필요가 없습니다.

## 남은 판단 — 전부 결정했습니다

앞으로 막힐 만한 갈림길을 미리 정해 둡니다. **다시 조사하거나 논쟁하지 마십시오.** 각 항목의
"뒤집는 조건" 이 실제로 발생했을 때만 다시 엽니다. 실행 시점에 결정 기록(ADR)으로 옮겨 적으면
됩니다.

### 1. SQLite 라이브러리 → 실행됨. ADR-0025 로 옮겨 적었습니다

`Microsoft.Data.Sqlite.Core` 10.0.10 (MIT) + `SQLitePCLRaw.config.e_sqlite3` 3.0.5 +
`SourceGear.sqlite3` 3.53.4 (Apache-2.0) 입니다.

**여기 적혀 있던 "`Microsoft.Data.Sqlite`" 는 실행해 보니 쓸 수 없었습니다.** 그 편의 package 는
native SQLite 하한을 `SQLitePCLRaw.lib.e_sqlite3` 2.1.11 로 끌어오는데, 이것이 CVE-2025-6965
(CVSS 7.2) 대상이고 2.x 에 수정 릴리스가 없습니다. restore 가 NU1903 으로 실패합니다.
SQLitePCLRaw 3.0 이 권하는 대로 native 를 분리해 참조하면 취약 package 가 사라지고, 다음 SQLite
권고에는 `SourceGear.sqlite3` 한 줄만 올리면 됩니다.

`winsqlite3.dll` 배제와 네이티브 vendoring 배제는 원래 판단대로입니다.

**뒤집는 조건:** 카탈로그를 네이티브로 옮기기로 결정하는 경우.

### 2. ORM → 쓰지 않습니다. ADO.NET 을 직접 씁니다

EF Core 도 Dapper 도 넣지 않습니다. 카탈로그 스키마는 우리가 소유하고 규모가 작으며, 이 저장소는
모든 경계를 명시적 계약으로 손으로 쓰는 방식으로 일관돼 있습니다. EF Core 는 패키지 다발과
마이그레이션 기구, 시작 비용을 함께 들여옵니다. 데스크톱 단일 사용자 카탈로그에 그 값을 치를
이유가 없습니다.

SQL 은 손으로 씁니다. 스키마 버전은 `PRAGMA user_version` 으로 관리합니다. **실행 결과 이 판단은
유지됩니다.** store 전체가 파일 하나이고, table 이름은 enum 에서만 나오며, 호출자 문자열이 SQL 로
흘러가지 않습니다.

**뒤집는 조건:** 스키마가 20개 테이블을 넘고 관계 매핑 유지 비용이 실제로 문제가 되는 경우.

### 3. "제3자 의존성 0개" 의 범위 → 네이티브 엔진에만 적용

`Negaflow.Native.dll` 과 `negaflow-cli.exe` 는 Windows 기본 DLL 외에 아무것도 링크하지 않습니다.
이 기준은 유지합니다.

**관리 계층에는 적용되지 않습니다.** 셸은 이미 WinUI 와 Windows App SDK 위에서 돕니다. 관리 코드에
MIT 패키지를 더해도 네이티브 엔진의 0개는 그대로입니다.

ADR-0025 에 명시했습니다.

**다만 실행하면서 한 가지가 드러났습니다.** 이 결정으로 배포 payload 에 제3자 **native** 바이너리
(`e_sqlite3.dll`) 가 처음 들어옵니다. "네이티브 엔진의 제3자 0개" 와 "제품 payload 의 제3자 0개"
는 이제 다른 문장이며, 두 번째는 더 이상 참이 아닙니다. `THIRD-PARTY-NOTICES.md` 가 이를 구분해
적고 있으니 SBOM 을 만들 때 흐리지 마십시오.

### 4. 카탈로그 스키마를 macOS 와 공유하는가 → 공유하지 않습니다

같은 `.sqlite` 파일을 두 플랫폼이 번갈아 여는 것은 제품 요구가 아닙니다. 스키마를 묶으면 양쪽 진화가
서로를 막습니다.

**호환은 recipe payload 수준에서만 유지합니다.** 그 경계는 이미 `Catalog.Core/Recipes` 의 develop
route projection 으로 구현돼 있고 legacy marker 와 강도 기본값까지 보존합니다. 라이브러리를 옮겨야
하는 상황이 생기면 DB 를 공유하는 대신 recipe 를 내보내고 들여옵니다.

**뒤집는 조건:** 한 라이브러리를 두 플랫폼에서 번갈아 쓰는 것이 명시적 제품 요구가 되는 경우.

### 5. Windows 가 macOS 와 같은 그림을 내야 하는가 → 필수 아닙니다

ADR-0024 를 유지합니다. 측정된 차이는 8비트 코드 2~6 이며 하이라이트에 한정됩니다. 플랫폼 차이로
문서화하고 넘어갑니다.

**뒤집는 조건:** ADR-0024 의 재검토 조건. 그 안에 재현 방법까지 적혀 있으므로 재조사는 필요 없습니다.

### 6. GPU 처리 경로 → D3D11 compute shader

Win2D 는 채택하지 않습니다. Win2D 는 XAML 과 잘 붙는 2D 캔버스 드로잉 라이브러리이고, 우리가 필요한
것은 FP32 색 파이프라인입니다. WinUI 3 지원도 여전히 작업 중 상태이며 서드파티 포크가 도는 상황이라
제품 기반으로 삼기에 이릅니다.

처리는 XAML 과 무관한 headless 경로로 둡니다. 그래야 CLI 와 셸이 같은 엔진을 공유합니다.

**뒤집는 조건:** compute 로 구현하기 어려운 효과가 나타나고 Direct2D 내장 효과가 그것을 정확히
제공하는 경우.

### 7. 화면 표시 → 처음에는 일반 비트맵. `SwapChainPanel` 은 나중에

세로 슬라이스에서는 결과를 sRGB8 비트맵으로 바꿔 `Image` 컨트롤에 얹는 것으로 충분합니다.
`SwapChainPanel` 은 DXGI·Direct2D·Direct3D 를 모두 알아야 하고 저지연 실시간 갱신이 필요할 때
쓰는 물건입니다. 지금 도입하면 통합 리스크만 키웁니다.

**뒤집는 조건:** 실시간 조정 중 프레임 지연이 실제로 문제가 되는 경우.

### 8. 배포 형식 → MSIX + `.appinstaller` 직접 배포

MSIX 가 WinUI 3 의 권장 경로입니다. 설치 경험이 하나로 끝나고, 제거하면 남는 것이 없으며, 차등
업데이트로 바뀐 블록만 내려받습니다. package identity 가 필요한 API 도 이때 열립니다.

현재는 `WindowsPackageType=None` 인 미패키지 구성입니다. M17 에서 바꿉니다. 미패키지 상태에서는
푸시 알림, 매니페스트 기반 백그라운드 작업, MSIX 자동 업데이트를 쓸 수 없습니다.

**뒤집는 조건:** MSIX 를 못 쓰는 기업 배포 요구가 생기는 경우. 그때는 WiX 또는 Inno Setup 이고
업데이트는 직접 구현해야 합니다.

### 9. 업데이트 → `.appinstaller` 자동 업데이트

8번의 결과입니다. 별도 업데이터를 만들지 않습니다.

### 10. 코드 서명 → **철회됨. ADR-0027 을 보십시오**

**이 항목은 무효입니다.** 비용을 들이지 않기로 했으므로 서명하지 않습니다. 설치 파일은 계속
만들되 서명 없이 배포하며, 그래서 MSIX 대신 WiX/Inno Setup 으로 갑니다(8·9번 항목도 함께
다시 열렸습니다). SmartScreen 경고는 그 결정의 대가로 받아들입니다.

아래 원문은 기록으로만 남깁니다.

### 10-old. (무효) 코드 서명 → Azure Trusted Signing 우선

2026년 기준 Basic 등급 월 $9.99, 서명 5,000건까지입니다. Microsoft 자체 CA 라 **SmartScreen 평판이
즉시 붙습니다.** 전통적 인증서는 평판을 쌓는 동안 사용자에게 경고가 뜨는데, 1인 프로젝트에는 이
차이가 큽니다. 인증서는 3일짜리 단기이며 자동 갱신되므로 하드웨어 토큰 관리가 없습니다.

**대한민국은 자격 국가 목록에 포함됩니다.** 다만 자료마다 "조직" 기준과 "개인" 공개 미리보기가
구분돼 있으므로, M17 착수 시점에 **개인 자격으로 등록 가능한지 먼저 확인**하십시오. 등록이 막히면
대안은 일반 CA 의 코드 서명 인증서이며, 전 세계에서 발급받을 수 있고 소유권이 본인에게 있습니다.
대신 평판을 처음부터 쌓아야 합니다.

**뒤집는 조건:** 개인 자격 등록 불가, 또는 Windows 외 플랫폼 서명이 필요해지는 경우.

### 11. 스캐너 연결 → 기존 SANE 플러그인을 그대로 씁니다

**이미 만들어져 있습니다.** [`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane)
저장소의 `windows/` 에 C++20 MSVC 구현이 있고 활발히 개발 중입니다. 새로 만들 것이 없습니다.

- 프로토콜은 **v2, 줄 단위 JSON**. `detect` / `capabilities` / `scan` 서브커맨드.
- **별도 실행 파일, 별도 프로세스.** macOS 와 같은 경계이며 ADR-0006 그대로입니다.
- backend 16개 분기 구현: `genesys`(Plustek OpticFilm), `epson2`, `coolscan`, `pieusb`.
- vcpkg static CRT 로 빌드. 의존성은 libtiff 와 RapidJSON.

TWAIN 과 WIA 는 검토할 필요가 없습니다. 참고로 WIA 는 600dpi 상한이 있어 애초에 필름 스캔에 쓸 수
없고, TWAIN 은 이미 동작하는 경로를 두고 새 드라이버 계층을 만드는 일이 됩니다.

**라이선스 경계가 이 구조의 핵심입니다.** 플러그인은 GPL-2.0-or-later 이고 negaflow 본체는
Apache-2.0 입니다. 그래서 별도 저장소, 별도 프로세스, JSON 경계입니다. `verify-provenance.py` 가
본체에 SANE 구현 마커(`sanei_`, `libsane`, `sane-backends`)가 들어오는 것과 릴리스 스크립트가
플러그인을 번들하는 것을 **자동으로 막습니다.** 이 경계를 흐리면 본체의 라이선스가 오염됩니다.
어떤 이유로도 SANE 코드를 `negaflow-windows` 안으로 들이지 마십시오.

**Windows 쪽에서 할 일은 플러그인을 만드는 것이 아니라 그 프로토콜의 클라이언트가 되는 것입니다.**
macOS 앱에 이미 호스트 구현이 있으므로 계약은 정해져 있습니다.

**알려진 위험:** 플러그인 Windows 빌드는 2026-08 기준 **실제 장치 검증이 0회** 입니다. 실행은 되지만
진짜 스캐너로 확인된 적이 없습니다. 그 외 read-path 핸들 검증 미완, macOS 와의 CRLF 처리 차이,
GUI 호스트에서 콘솔 기반 취소가 안 될 때 강제 종료로 대체되는 문제가 남아 있습니다. 설치·배포
스크립트는 그 저장소의 M7 예정입니다.

M15 에 착수할 때는 **플러그인 구현이 아니라 실제 장치 검증부터** 시작하십시오. 그것이 이 경로에
남은 유일한 큰 미지수입니다.

**뒤집는 조건:** 없습니다. 이 구조는 라이선스 격리 때문에라도 유지해야 합니다.

### 12. SQLite 재저장 비용 → 지금은 최적화하지 않습니다

무변경 재저장이 frame 5만 개에서 343ms 입니다. 이 store 의 비용은 **바뀐 양이 아니라 catalog 전체
크기에 비례**합니다. row 하나를 고쳐도 5만 건의 upsert 가 돌고 `integrity_check` 가 파일 전체를
훑습니다. `WHERE` 가드는 디스크 페이지 쓰기만 막고 statement 실행은 막지 못합니다.

**지금은 최적화하지 않습니다.** 목표 규모에서 1초 미만이고, 조기 최적화는 아직 없는 호출 패턴을
가정하게 만듭니다.

**뒤집는 조건:** 목표 규모가 5만을 크게 넘거나, 편집 한 번의 저장 지연이 UI 에서 감지되는 경우.
그때 손댈 곳은 두 군데입니다. (1) 호출자가 dirty 집합을 넘겨 바뀐 row 만 upsert 하는 것,
(2) `integrity_check` 를 매 쓰기가 아니라 열기와 backup 생성에서만 돌리는 것. 측정값은
`verification/2026-08-07-sqlite-catalog-store.md` 에 있습니다.

### 결정하지 않은 채 남기는 것

없습니다. 위 12개로 M4~M17 의 주요 갈림길은 전부 정해졌습니다. 새 갈림길이 나타나면 그때 이
문서에 같은 형식으로 추가하십시오 — **결정, 이유, 뒤집는 조건.** 12번이 실행 중에 그렇게 추가된
첫 항목입니다.

## 재개하는 방법

```powershell
# Windows 전체 게이트 (네이티브 + 관리)
.\negaflow-windows\scripts\ci-gate.ps1 -Preset x64-release
```

```bash
# 저장소 전체 provenance·라이선스 게이트
py negaflow-mac/scripts/ci/verify-provenance.py
```

macOS 쪽 짝은 `negaflow-mac/scripts/ci-gate.sh` 입니다. 두 입구는 분리돼 있으니 한쪽만 고치면 갈라집니다.
