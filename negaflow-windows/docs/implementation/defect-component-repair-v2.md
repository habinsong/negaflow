# Defect component repair v2

기준 macOS commit은 `2fa1d6297378673b58b8bec72025e968ccc3125c`입니다. 해당 소스는 저장소
분리 전 `Sources/Chromabase/DefectRemoval/`에 있었고 현재 `negaflow-mac/Sources/`로 내용 변화 없이
이동했습니다.

## 범위

`repair_defect_components`는 영역 Defects 작업 흐름이 검출·편집한 ROI-local mask를 복원하는 C++20
코어입니다. 전역 자동 GrainMend의 3×3 median 경로를 대체하지 않습니다.

- 입력은 linear working RGBA32F와 1채널 0...255 mask입니다. mask 값 `>8`을 구조 복원 대상으로
  사용하고 전체 byte 값은 최종 blend weight로 보존합니다.
- 복원 수학은 macOS `.RGBAf` sRGB render와 같은 encoded domain에서 실행하고 결과만 linear working
  RGB로 되돌립니다. 원본 alpha는 그대로 유지합니다.
- 얇은 component는 원본-only 양방향 isophote 보간을 사용합니다. 0/45/90/135도 외에
  26.6/63.4도 계열을 포함해 완만한 대각 구조를 잇습니다.
- 두꺼운 component는 8-neighbor 경계부터 안쪽으로 onion-peel하며, 이미 채운 값은 다음 layer의
  색 표본으로만 사용하고 원본 damage mask는 구조 판정에 유지합니다.
- preferred angle이 있는 넓은 mask는 component luma median/MAD로 실제 고대비 damage만 유지해
  사용자가 칠한 정상 질감을 복원 대상으로 만들지 않습니다.
- 구조 채움 뒤 component 주변 grain sigma와 외관 SSD로 exemplar displacement를 고르고, 3σ 제한
  high-frequency residual을 전사합니다. 표본이 없으면 고정 seed noise를 사용합니다.
- 잘못된 mask layout, 비유한 angle·pixel, 할당 실패는 부분 이미지를 폐기해 fail-closed합니다.

진입·색공간/blend, mask/component refinement, structure fill, texture transfer를 네 번역 단위로
나눴습니다. 새 dependency와 runtime payload는 없습니다.

## ABI v18/v19와 공통 파이프라인 연결

- `nf_defect_region_edit_v1`은 enabled, raw pixel의 bottom-origin ROI, top-first one-byte mask,
  strength와 optional preferred angle을 운반합니다. descriptor와 flat mask는 동기 호출 동안 caller가
  소유합니다.
- edit은 최대 4,096개, flat mask는 최대 512 MiB이며 크기·stride·offset·reserved·finite range를 C ABI와
  관리 계층 양쪽에서 검증합니다.
- `defect_region_stage`가 decode·원본 변경 관찰 뒤, 음화 base 측정과 반전 전에 ROI를 top-down working
  좌표로 변환해 입력 순서대로 복원합니다. 하나라도 잘못되거나 kernel/할당이 실패하면 전체 이미지를
  폐기하고 결과를 게시하지 않습니다.
- `nf_develop_preview_v18`과 `nf_develop_export_v18`은 같은 request와 `prepare_working_image`를 사용합니다.
  관리 `DevelopDefectRegionEdit` 목록은 한 번 flat payload로 복사해 동기 호출 동안 pin합니다.
- 제품 경로는 ABI v19를 사용합니다. 비어 있지 않은 region recipe는 저장된 source byte count와
  SHA-256을 함께 보내야 하며, native가 디코드 전에 share-deny-write CNG 순차 hash로 실제 원본을
  비교합니다. hash 전후 file ID·크기·수정 관측과 decode 뒤 관측도 같아야 합니다. 불일치·교체 race는
  `observe_source_before`에서 중단하고 preview pixel이나 export artifact를 게시하지 않습니다.
- Defects가 없는 v19 요청은 source identity 필드를 비워야 하며 일반 preview/export의 SHA-256 기본
  `off` 경로를 유지합니다. v18 export는 append-only ABI 호환을 위해 남겨 둡니다.
- strength는 구조·texture 후보를 바꾸지 않고 최종 linear blend에 곱합니다. 0은 bit-exact identity이고
  0.5는 같은 full repair의 linear midpoint입니다.

## Clone Stamp와 ABI v20

- 점과 offset은 raw 이미지의 top-left 기준 normalized y-down 좌표입니다. offset은 source-target이며
  각 축을 raw 크기에 곱한 뒤 가장 가까운 정수 픽셀로 스냅합니다.
- 직경의 25% 간격으로 stamp를 놓고 hardness smoothstep mask를 src-over 누적합니다. source가 프레임
  밖인 mask 픽셀은 0입니다.
- 각 stroke는 강도 1.0의 linear RGBA16 dirty patch를 만듭니다. 뒤 stroke의 source와 destination은
  앞 stroke의 full-strength patch를 읽습니다. 사용자 item strength는 이 patch들을 현재 working 이미지와
  순서대로 혼합할 때만 적용합니다.
- region/infrared와 clone descriptor를 별도 flat 배열로 운반하고, ABI v20의 ordered reference 배열이
  sidecar item 순서를 정확히 복원합니다.
- clone edit 4,096개, stroke 100,000개, point 5,000,000개, ordered edit 8,192개로 제한합니다. full-frame
  복사 대신 dirty RGBA16 patch를 item당 최대 512 MiB 보존합니다.

## Brush와 ABI v21

- 점은 raw 이미지의 top-left 기준 normalized y-down 좌표이며 두께는 짧은 raw 변의 비율입니다. 손상
  sidecar가 0~1 밖 좌표·두께를 제공하면 Shell, managed Interop과 native ABI에서 실패 폐쇄형으로 거부합니다.
- 긴 stroke는 macOS처럼 `max(240, min(shortSide × 0.16, 640))` 픽셀 단위 chunk로 나누고, dirty ROI는
  `max(96, shortSide × 0.025, lineWidth × 3.2)` halo를 포함합니다.
- 각 chunk는 sRGB float domain에서 brush mask `>8`의 8-connected component를 분리하고 PCA 또는 stroke
  방향으로 실제 source texture 후보를 찾습니다. context-ring SSD로 후보를 고른 뒤 box-mean 저주파 tone
  offset과 1px Gaussian feather를 적용하며 alpha는 원본을 보존합니다.
- 유효한 displaced source가 없으면 기존 영역 component repair를 사용합니다. 모든 chunk의 full-strength
  결과를 먼저 만든 뒤 item strength를 한 번만 적용하고, 뒤 chunk는 앞 chunk의 full-strength 결과를 읽습니다.
- ABI v21은 brush edit/stroke/point flat 배열을 v20 prefix 뒤에 append합니다. 기존 ordered reference 배열이
  region/infrared/clone/brush descriptor를 각각 정확히 한 번 가리켜 sidecar 순서를 보존합니다.
- 저장 patch 합계는 512 MiB로 제한하고 full-frame 복사 대신 최종 합성용 1 byte/pixel coverage map만 둡니다.

## IR attenuation replay와 ABI v24

macOS post-baseline commit `cec0db3d9444a22fda6f2f39165141b7f7151497`의 비파괴 IR layer 계약을
Windows sidecar→Shell→Interop→native 공통 preview/export 경로에 연결했습니다.

- IR cluster는 기존 core mask와 별도로 optional ROI-local R16 attenuation을 보존합니다. payload는 top-first,
  little-endian이며 정확히 `width × height × 2` bytes여야 합니다. 필드가 없는 구 sidecar는 mask-only
  component repair로 계속 재생합니다.
- sidecar read는 압축 손상·크기 불일치를 실패 폐쇄형으로 거부합니다. canonical fingerprint에는 attenuation
  storage의 SHA-256이 들어가므로 같은 revision의 서로 다른 attenuation을 충돌로 탐지합니다. 논리 backup과
  pending restore도 authoritative sidecar bytes를 그대로 교체합니다.
- native IR stage는 linear working RGB에 `source / max(1 - attenuation / 65535, 0.5)`를 먼저 적용합니다.
  core mask가 있으면 attenuation 결과를 문맥으로 component repair한 뒤 item strength를 한 번만 혼합합니다.
  alpha는 보존하며 core가 비어 있으면 inpaint하지 않습니다.
- append-only ABI 0.31은 `nf_defect_infrared_edit_v1`, `nf_develop_export_request_v24`,
  `nf_develop_preview_v24`, `nf_develop_export_v24`를 추가합니다. preview와 export는 같은 v24 request,
  `map_request_v24`, pre-develop stage를 사용하고 v18~v23 caller는 계속 유효합니다.
- 이 단계는 저장된 IR 결과의 정확한 재생 경계입니다. paired visible/IR plane 자동 검출, scanner companion
  입력, 자동 실행 coordinator, WinUI 수명주기는 포함하지 않습니다.

## 아직 연결하지 않은 범위

revision-aware Defects sidecar와 catalog→Shell→ABI v24 region/infrared attenuation/clone/brush projection은
연결했습니다.
component include/exclude UI, WinUI canvas와 cleaned-raw/preview cache는 아직 연결하지 않았습니다.
macOS 실행 host의 동일 입력 IR mask·attenuation·pixel golden과 Clone Stamp/Brush pixel golden, 실제 촬영 TIFF,
대량 겹침 stroke와
대형 ROI peak memory·batch 처리량, 실제 ARM64 실행도 남아 있습니다. 앞 patch 탐색은 최신순 선형이라
매우 많은 겹침 stroke의 최악 시간 복잡도도 측정이 필요합니다. macOS CoreGraphics mask antialias와
Core Image Gaussian, source 미발견 시 SoftwareDefectRemoval fallback, 네 chunk마다 RGBA16으로 flatten되는
누적 양자화는 동일 입력 golden 전까지 pixel parity로 주장하지 않습니다.
