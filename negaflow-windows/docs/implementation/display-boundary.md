# 표시 경계 — hue-safe soft clip과 dithering

기준일: 2026-08-10

## 왜

macOS 소스를 대조하다 미리보기 경로에서 실제 차이를 찾았습니다.

macOS 표시 경로(`DevelopFrameRenderer+Developed.swift`)는 8비트로 내리기 전에 두 단계를
거칩니다.

```
DisplayGamutMap.apply   → gamutSoftClip 커널 (= toneSafeUnitRGB)
OutputDither.apply      → linear→sRGB, ±0.5/255 노이즈, sRGB→linear
createCGImage(.RGBA8)
```

Windows 미리보기는 둘 다 없었습니다. 채널별 하드 클립으로 [0,1]에 밀어 넣고 16비트를
`>> 8`로 잘랐습니다.

**게시 경로는 다릅니다.** macOS의 `appliesDither` 는 PNG/TIFF에서 `bitDepth == .eight` 일
때만 참입니다. Windows는 PNG16/TIFF16만 게시하므로 dither 없음이 맞고, 이번 변경도
게시 경로를 건드리지 않습니다. 실제 촬영본 export SHA-256이 그대로임을 확인했습니다.

## 무엇

`negaflow/imaging/display_gamut_map.h` 가 두 가지를 소유합니다.

**`tone_safe_unit_rgb`** — macOS `toneSafeUnitRGB` 와 같은 수식입니다. luma를 [0,1]로
고정하고, 모든 채널이 범위에 들어가는 가장 큰 배율로 chroma만 줄입니다.

- 이미 [0,1] 안의 픽셀은 **항등**입니다. 보통 사진은 그대로입니다.
- 한 채널만 넘친 채도 높은 색은 **채널 순서(=hue)를 지키며** 첫 채널이 경계에 닿을 때까지
  chroma가 줄어듭니다. 채널별 하드 클립이라면 넘친 채널만 잘려 색상이 끌려갑니다.
- luma 자체가 1을 넘는 과노출 픽셀은 남길 chroma가 없으므로 흰색으로 접힙니다. 놀람이
  아니라 결정이므로 회귀로 고정했습니다.

**`display_dither_offset`** — 양자화가 일어나는 sRGB 공간에서 한 스텝 미만(±0.5/255)의
노이즈입니다. 매끄러운 하늘이 8비트에서 밴딩되는 것을 stipple로 흩습니다. macOS는
`CIRandomGenerator` 라 공유 seed가 없고, Windows는 좌표 해시라 **미리보기가 재현 가능**합니다.
분포는 같고 개별 잡음만 다릅니다. macOS와 마찬가지로 **채널마다 독립**입니다.

## 미리보기 경로의 다른 변화

전체 해상도 16비트 중간 이미지를 만들지 않습니다. 종전에는 17 MP 프레임에서 약 104 MB를
할당해 축소에 쓰고 버렸습니다. 이제 working 이미지에서 바로 box 평균을 계산하며, 프레임을
한 번 덜 훑습니다. 이 새 경로도 행 블록으로 나뉩니다.

## 흑백 중립성 계약이 바뀐 자리

채널별 dither는 중립 픽셀의 8비트 값을 채널마다 최대 1 코드 흔듭니다. macOS도 같습니다.
중립성은 **현상 결과의 성질**이지 표시 양자화의 성질이 아니므로, ABI 회귀의 흑백 검사를
"채널 최대 차이 ≤ 1"로 바꿨습니다. 흑백 그래프가 실제로 틴트를 만들면 한 스텝보다 훨씬
크게 벗어납니다.

## 검증 (2026-08-10)

- x64 Debug/Release 네이티브 CTest **58/58** (새 `native.display_gamut_map` 포함)
- Interop **139**(ABI 0.28), Catalog **583**, Shell **317**, 경고 0·오류 0
- ARM64 Release 네이티브·관리 교차 빌드 통과(실기 실행 아님)
- provenance 통과

**게시는 바뀌지 않았습니다.** 실제 촬영본 export PNG16 SHA-256이 이전과 동일합니다 —
frame_1 `1A4EB1A7…`, frame_12 `2ED77091…`.

**새 미리보기 경로도 비트 정확합니다.** 엔진 전역을 인라인으로 강제한 빌드와 통상 빌드가 같은
미리보기 fingerprint 를 냅니다: FilmScanDenoise `b539956ad3c46820`, Texture `a63cd4c01b4c1e10`.
(이 값들은 dither 도입으로 이전 baseline에서 의도적으로 바뀌었습니다.)
같은 대조에서 Texture 미리보기는 `4,160.1 ms → 774.8 ms` 였습니다.

## 검증하지 않은 것

- 같은 입력의 macOS 미리보기 pixel golden. Core Image의 실제 출력과 비교하려면 macOS 호스트가
  필요합니다.
- soft-proof 경로. macOS는 gamut map 뒤 dither 앞에 soft-proof를 겁니다. Windows에는 아직
  soft-proof가 없습니다.
- 축소 순서. macOS 썸네일은 linear 축소 뒤 gamut map, Windows는 gamut map·sRGB 인코딩 뒤
  gamma 공간 box 평균입니다. 표시 전용 선택으로 남겨 두었습니다.
