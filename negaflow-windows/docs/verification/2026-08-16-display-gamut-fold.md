# 색역 클리핑 — 적용 지점 대조

기준일: 2026-08-16

STATUS 에 "색역 클리핑" 이 오래 남아 있었습니다. 커널은 이미 있었고, 남은 것은 **어디에
거는가** 였습니다. macOS 와 나란히 놓고 끝까지 봤습니다.

## 커널은 같습니다

macOS `toneSafeUnitRGB`(`ChromabaseMetalKernels.swift`)와 Windows `tone_safe_unit_rgb`
(`display_gamut_map.h`)는 같은 계산입니다 — 같은 Rec.709 계수, 같은 `1e-5` 문턱, 같은
`min` 구조, 같은 마지막 클램프. 휘도를 붙들고 크로마만 줄여 hue 를 지키는 방식입니다.

## 거는 자리

| | macOS | Windows |
| --- | --- | --- |
| 내보내기(게시 파일) | **안 겁니다** — `createCGImage` 의 하드 클립 | **안 겁니다** — 평범한 클램프 |
| 현상 캔버스 | `DisplayGamutMap.apply` → 소프트 프루프 | 화소마다 fold → 프루프 |
| 썸네일 | 축소 → `DisplayGamutMap.apply` | 화소마다 fold → 축소 |
| 톤 마스크 입력 | 커널 안에서 `toneSafeUnitRGB` | `apply_basic_tone` 안에서 같은 함수 |

**내보내기에 걸지 않는 것이 맞습니다.** macOS 의 `ExportRenderedImage.make` 는
`createCGImage` 로 바로 가고 `DisplayGamutMap` 을 부르지 않습니다. Windows 도 게시 경로는
평범한 클램프입니다. 이 줄은 원래부터 일치했고, STATUS 의 "남은 것" 은 확인이 없었을 뿐입니다.

**프루프보다 먼저 접는 것도 같습니다.** macOS 주석이 "soft-proof 는 [0,1] 입력만 종이 gamut
으로 압축하므로 반드시 그 전에 접어야 한다" 고 못 박아 두었고, Windows 도
`folded = tone_safe_unit_rgb(source)` 다음에 `folded * proof.scale + proof.bias` 입니다.

**썸네일과 캔버스가 한 경로인 것도 같습니다.** Windows 의 썸네일은 `ThumbnailService` 가
`develop_preview` 를 부르는 것이고, 캔버스와 **같은 함수**입니다. macOS 도 썸네일이 캔버스와
같은 표시 gamut 매핑을 거쳐야 한다고 주석에 적어 두었습니다.

## 한 가지 남는 차이 — 접는 순서

썸네일에서 macOS 는 **축소한 뒤** 접고, Windows 는 **접은 뒤** 축소합니다. 접기는 비선형이라
색역 밖 화소가 있으면 두 순서가 다른 값을 냅니다.

**기본 현상에서는 관측되지 않습니다.** 인화 응답의 출력은 구조적으로 `(baseToe, ceiling)`
안이고 컬러 응답의 ceiling 은 0.90 입니다 — 기본값으로 현상한 그림은 [0,1] 을 벗어나지
않으며, 색역 안 화소에 대해 `tone_safe_unit_rgb` 는 항등입니다. 색역 밖 값은 사용자가 톤·색을
밀어야 생깁니다.

여기는 화면 전용이고 골든이나 계약에 들어가지 않습니다. Windows 의 축소가 sRGB 인코딩 공간의
박스 평균인 것도 이미 의도된 차이로 적혀 있습니다(`develop_export.h`). 그래서 이 순서 차이는
**고치지 않고 적어 둡니다** — 재서 보이지 않는 것을 고치면 픽셀만 바뀝니다.

## 결론

내보내기·프루프 순서·경로 공유는 macOS 와 같습니다. 썸네일의 접는 순서 하나가 다르고, 기본
현상에서는 항등이라 보이지 않습니다.
