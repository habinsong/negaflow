# Film Emulation acutance 구현

## 현재 범위

`chromabase-film-emulation-acutance-v1`은 film-scan source의 RGB33 색상 단계 뒤에 오는 spatial
acutance를 Windows CPU reference로 구현합니다. 아직 실제 `WorkingToneAdjuster`, export, CLI, ABI나
WinUI가 이 component를 호출하지 않습니다.

```text
RGB33 Film Emulation 색상 결과의 extended-linear sRGB
  → radius별 11-tap horizontal Gaussian blur
  → 11개 horizontal row ring을 이용한 vertical Gaussian blur
  → source + amount × (source - blur)
  → RGB overshoot 허용, alpha 보존
```

## 파일 책임

- `film_emulation_acutance.h`: 공개 parameters/profile/scratch와 apply 계약
- `film_emulation_acutance_profiles.h/.cpp`: profile별 radius, base intensity와 fitted sigma
- `film_emulation_acutance.cpp`: 검증, Gaussian 생성, 11행 ring과 unsharp 연산
- `film_emulation_core_image_golden_fixture.h`: macOS run에서 추출한 profile·impulse·step 기대값
- `film_emulation_acutance_tests.cpp`: 수치, 메모리, in-place, alpha와 오류 계약
- `scalar_conformance.cpp`: canonical Velvia impulse 36개 RGBA 값과 오차·scratch 보고

한 타입이 명부, kernel, 파이프라인, 파일 I/O와 UI를 함께 소유하지 않도록 분리했습니다.

## profile 계약

| profile | radius | base acutance |
|---|---:|---:|
| none | 1.0 | 0.00 |
| Ektachrome E100 | 1.0 | 0.12 |
| Provia 100F | 1.1 | 0.20 |
| Velvia 50 | 1.2 | 0.22 |
| Portra 160 | 1.0 | 0.08 |
| Portra 400 | 1.0 | 0.05 |
| Portra 800 | 1.0 | 0.03 |
| Ektar 100 | 1.0 | 0.16 |
| UltraMax 400 | 1.0 | 0.04 |
| ColorPlus 200 | 1.0 | 0.07 |
| Fujicolor C200 | 1.0 | 0.06 |
| Pro 400H | 1.0 | 0.04 |

사용자 intensity는 finite여야 하고 `[0, 1]`로 clamp합니다. 최종 amount는 다음과 같습니다.

```text
amount = baseAcutance × clamp(userIntensity, 0, 1)
```

색상 cube는 cache 재사용을 위해 5% 단위로 양자화하지만 spatial amount는 macOS stage와 같이 원래
사용자 강도를 그대로 사용합니다. profile 또는 사용자 강도가 `1e-3` 이하인 경우 scratch 없이 active
pixel만 복사합니다.

## Gaussian과 경계

radius는 직접 kernel 표준편차로 사용하지 않습니다. macOS canonical run의 intensity 1.0 impulse 응답을
radius별 separable Gaussian에 맞춰 다음 호환 계수를 고정했습니다.

| macOS radius | fitted sigma | 한 축 support |
|---:|---:|---:|
| 1.0 | 1.042 | 5 |
| 1.1 | 1.137 | 5 |
| 1.2 | 1.238 | 5 |

가중치는 `exp(-d² / (2σ²))`를 정규화해 Float32로 저장합니다. 경계 바깥 tap은 가장 가까운 유효 pixel로
clamp합니다. 이는 관측된 출력을 재현하기 위한 명시적 Windows 계약이며 Core Image 내부 알고리즘을
단정하지 않습니다.

## bounded memory와 in-place

horizontal blur는 RGB Float32 세 값만 저장합니다. scratch 요구량은 다음과 같습니다.

```text
scratchPixels = width × 11
scratchBytes  = width × 11 × 12
```

33픽셀 fixture는 4,356바이트, 10,000픽셀 행은 1,320,000바이트입니다. 높이가 커져도 scratch는 늘지
않습니다. 첫 6행을 미리 blur한 뒤 앞으로 필요한 한 행만 ring slot에 채우므로, exact in-place에서도
아직 읽지 않은 source 행을 덮지 않습니다.

- input/output base와 stride가 모두 같으면 exact in-place를 지원합니다.
- 서로 다른 base의 memory range가 겹치는 부분 alias는 거부합니다.
- scratch의 실제 사용 range가 input 또는 output range와 겹치면 거부합니다.
- identity는 row padding을 건드리지 않습니다.

## 수치·오류 계약

- 입력/output RGB는 extended-linear이므로 0 미만과 1 초과 값을 허용합니다.
- alpha는 `[0, 1]` finite여야 하며 결과에 bit-exact로 복사합니다.
- 입력 RGB/alpha, intensity와 활성 결과 RGB는 모두 finite여야 합니다.
- unknown enum, invalid dimensions/stride/capacity, size overflow, 작은 scratch를 구조화된
  `KernelStatus`로 반환합니다.
- 내부 heap, 파일 I/O, 이미지 SHA-256, 전역 mutable cache와 제3자 runtime dependency는 없습니다.

## native route와 남은 제품 연결

`chromabase-working-film-look-v1` native route는 RGB33 cube 뒤 이 acutance를 호출하며, 명시적
film/digital source를 분리합니다. 활성 digital 요청은 전체 `DigitalFilmLook`이 준비될 때까지
`unsupported_route`로 실패합니다.

남은 것은 다음과 같습니다.

1. CLI report와 recipe serialization, catalog/import source metadata 연결
2. caller-owned cube/scratch cache 수명 관리자, cancellation과 progress 계약
3. 좁은 C ABI와 WinUI 노출
4. megapixel scalar benchmark 후 필요성이 확인될 때 SIMD/DirectCompute/WARP 구현
5. 실제 ARM64 Windows와 더 넓은 border·fractional-alpha golden
