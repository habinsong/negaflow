# 노출·대비·파라메트릭 커브 구현

## 처리 경계

첫 Windows 톤 조정은 수동 네거티브 반전이 끝난 `WorkingImage`를 받아 같은 float buffer 안에서 다음
순서로 처리합니다.

```text
extended-linear-sRGB WorkingImage
  → exposure: RGB × 2^stops
  → basic tone: tone-safe unit gamut, sRGB-luma contrast/masks
  → curve measurement: fixed fallback 또는 portable area percentile
  → parametric curve: four luma bands
  → verified sRGB16 PNG/TIFF output
```

alpha는 모든 단계에서 그대로 보존합니다. scanner 입력 수직 경로는 opaque alpha만 허용하지만 kernel
fixture는 fractional alpha도 보존하는지 별도로 확인합니다.

## 파일 책임

- `tone_mapping.h/.cpp`: 외부 할당이 없는 기본 톤·파라메트릭 커브 pointwise 수식
- `tone_curve_measurement.h/.cpp`: bounded downsample luma, percentile과 band 계산
- `working_tone_adjuster.h/.cpp`: 제품 입력 범위, 단계 순서, 실패 시 pixel 폐기
- `tone_mapping_fixture.h`: 저장소 소유 3×2 합성 입력·recipe·Float32 기대값
- `tone_pipeline_tests.cpp`: 수치, 검정 앵커, stride, 측정 한도와 실패 계약
- `export_developed_image.cpp`: 선택 인수 parsing, stage 시간·메모리·band JSON

픽셀 kernel이 파일 I/O, TIFF container, CLI parsing이나 측정 vector를 소유하지 않습니다.

## 수치 계약

### 노출

`abs(stops) <= 1e-3`이면 무연산이고, 그보다 크면 linear RGB에 `exp2(stops)`를 곱합니다. 이 단계는
음수와 1 초과 값을 보존합니다.

### tone-safe unit RGB

tone mask는 표시 참조 `[0, 1]`에서 정의됩니다. 먼저 Rec.709/sRGB luma 계수
`0.2126, 0.7152, 0.0722`로 luma를 구하고, 각 channel이 범위를 넘지 않는 최대 공통 chroma scale을
계산합니다. per-channel hard clipping보다 luma와 hue를 보존한 채 tone domain으로 들어갑니다.

### 기본 톤

linear luma를 sRGB로 인코딩하고 0.46 피벗에서 양·음 대비를 서로 다른 지수로 적용합니다. 음수 대비는
sRGB 0.12~0.30 smoothstep guard를 사용해 절대 검정과 deep shadow를 원본에 묶습니다. 나머지 다섯
control은 macOS와 같은 mask·계수를 사용하고, 최종 luma를 linear로 되돌려 RGB에 공통 delta로 더합니다.

### 파라메트릭 커브

fixed band는 다음과 같습니다.

| band | low | high | 최대 delta 계수 |
|---|---:|---:|---:|
| shadows | 0.05 | 0.24 | 0.160 |
| darks | 0.18 | 0.36 | 0.155 |
| lights | 0.34 | 0.68 | 0.165 |
| highlights | 0.36 | 0.50 | 0.150 |

shadow mask에는 0~0.045 절대 검정 anchor가 추가됩니다. 동적 mode는 basic tone 이후 이미지를 측정하며
target width, border와 percentile 계약은 macOS와 같고 raster filter만 `portable_area_v1`로 명시합니다.

## CLI

기존 명령은 그대로 유효합니다.

```powershell
negaflow-cli --export-developed-tiff16 <source> <destination> <dmin-r> <dmin-g> <dmin-b> <color|bw>
```

최소 톤 조정은 여섯 값을 전부 추가합니다.

```powershell
negaflow-cli --export-developed-tiff16 <source> <destination> <dmin-r> <dmin-g> <dmin-b> <color|bw> <exposure> <contrast> <curve-highlights> <curve-lights> <curve-darks> <curve-shadows>
```

PNG16도 같은 인수와 orchestration을 사용합니다. 일부 선택 인수만 주는 형식은 recipe 오해를 막기 위해
거부합니다. JSON의 `stages.tone_adjust`에는 입력값, 적용 여부, sampling mode, target, sample 수,
band, peak temporary bytes와 wall microseconds가 들어갑니다. 경로·file identity 값·SHA 값은 넣지
않습니다. 커브가 적용되지 않으면 sampling mode는 `none`, `curve_bands`는 `null`입니다.

## 성능과 메모리

pixel 변환은 기존 `WorkingImage`에 제자리 적용하므로 추가 full-frame buffer는 0입니다. 모든 값이
적용 임계값 이하인 기존 명령은 layout만 확인하고 full-frame tone scan 없이 즉시 반환합니다. 동적 band는
최대 1,048,576개의 `double` luma만 허용하고 실제 peak를 보고합니다. 631×403 저장소 fixture의 x64
Release 한 번 측정에서는 35,636 luma, 285,088 temporary bytes, tone stage 42,874 µs였습니다. 무조정
명령의 tone stage는 같은 측정에서 10 µs였습니다. 이 값은
현재 PC의 단일 관찰이며 성능 보증이나 ARM64 결과가 아닙니다.

## 남은 제한

- dynamic raster는 Core Image 내부 필터와 bit-exact하지 않을 수 있습니다.
- scalar `pow` 중심 구현이며 SIMD/GPU 최적화 전입니다.
- stage wall time만 있으며 CPU time과 canonical digest는 아직 없습니다.
- 실제 macOS runtime tone golden과 사진 corpus 비교는 아직 없습니다.
