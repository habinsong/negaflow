# 노출·대비·파라메트릭·포인트 커브·Color Mixer·Color Grading·Primary Calibration 구현

## 처리 경계

첫 Windows 톤 조정은 수동 네거티브 반전이 끝난 `WorkingImage`를 받아 같은 float buffer 안에서 다음
순서로 처리합니다.

```text
extended-linear-sRGB WorkingImage
  → exposure: RGB × 2^stops
  → basic tone: tone-safe unit gamut, sRGB-luma contrast/masks
  → curve measurement: fixed fallback 또는 portable area percentile
  → parametric curve: four luma bands
  → point curve: DR/R/G/B 64-sample LUT
  → Color Mixer: HSL 8-band hue/saturation/luminance
  → Color Grading: shadows/midtones/highlights color wheel
  → Primary Calibration: R/G/B primary hue/saturation
  → verified sRGB16 PNG/TIFF output
```

alpha는 모든 단계에서 그대로 보존합니다. scanner 입력 수직 경로는 opaque alpha만 허용하지만 kernel
fixture는 fractional alpha도 보존하는지 별도로 확인합니다.

## 파일 책임

- `tone_mapping.h/.cpp`: 외부 할당이 없는 기본 톤·파라메트릭 커브 pointwise 수식
- `tone_curve_measurement.h/.cpp`: bounded downsample luma, percentile과 band 계산
- `point_curve.h/.cpp`: 고정 용량 제어점, 64표본 LUT 생성·합성과 픽셀 lookup
- `color_mixer.h/.cpp`: 고정 8대역 HSL control, 회색 gate와 pointwise 수학
- `color_grading.h/.cpp`: 고정 3구간 color wheel, luma weight와 pointwise 수학
- `primary_calibration.h/.cpp`: 고정 R/G/B 대역, 여섯 control과 HSL pointwise 수학
- `working_tone_adjuster.h/.cpp`: 제품 입력 범위, 단계 순서, 실패 시 pixel 폐기
- `tone_mapping_fixture.h`: 저장소 소유 3×2 합성 입력·recipe·Float32 기대값
- `point_curve_fixture.h`: 저장소 소유 3×2 포인트 커브 입력·LUT 표본·Float32 기대값
- `color_mixer_fixture.h`: 저장소 소유 4×3 RGB 입력·24개 control·Float32 기대값
- `color_grading_fixture.h`: 저장소 소유 4×3 extended RGB 입력·세 구간 recipe·Float32 기대값
- `primary_calibration_fixture.h`: 저장소 소유 4×3 extended RGB 입력·여섯 control·Float32 기대값
- `tone_pipeline_tests.cpp`: 수치, 검정 앵커, stride, 측정 한도와 실패 계약
- `point_curve_tests.cpp`: 제어점 경계, 합성 수치, identity와 tone 뒤 처리 순서
- `color_mixer_tests.cpp`: 8대역 수치, 회색 보호, point curve 뒤 순서와 실패 계약
- `color_grading_tests.cpp`: 세 구간 수치, identity, Color Mixer 뒤 순서와 실패 계약
- `primary_calibration_tests.cpp`: 세 primary 수치, identity, 회색 gate, Color Grading 뒤 순서와 실패 계약
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

### 포인트 커브

파라메트릭 커브 뒤에는 macOS post-pipeline의 첫 단계인 전체 RGB와 R/G/B 포인트 커브를 적용합니다.
각 커브는 최대 64개 제어점과 64표본 LUT를 사용합니다. 전체 RGB LUT를 먼저 채널 LUT와 합성한 뒤,
extended-linear RGB를 sRGB encoded `[0, 1]` domain에서 lookup하고 다시 linear로 되돌립니다. 활성 커브는
cube domain 밖을 제한하지만 전체 identity는 단계를 건너뛰어 extended RGB를 bit-exact로 보존합니다.
세부 계약은 `point-curve-scalar.md`에 있습니다.

### Color Mixer

포인트 커브 뒤에는 red/orange/yellow/green/aqua/blue/purple/magenta의 hue, saturation, luminance를
가중 평균하는 macOS `colorMixerHSL`을 적용합니다. 활성 단계는 extended-linear working RGB를 먼저
`[0, 1]`로 제한하고 HSL로 왕복합니다. saturation 0.04~0.18 smoothstep gate가 무채색을 보호하며,
identity는 단계를 건너뛰어 extended RGB를 bit-exact로 보존합니다. 세부 계약은
`color-mixer-scalar.md`에 있습니다.

### Color Grading

Color Mixer 뒤에는 shadows, midtones, highlights의 hue/saturation/luminance와 전역 blending/balance를
사용하는 macOS `colorGrade`를 적용합니다. source relative luma로 세 구간 weight를 계산하고 HSV
color-wheel tint의 zero-luma chroma와 luminance offset을 더한 뒤 최종 RGB를 `[0, 1]`로 제한합니다.
identity는 단계를 건너뛰어 extended RGB를 bit-exact로 보존합니다. 세부 계약은
`color-grading-scalar.md`에 있습니다.

### Primary Calibration

Color Grading 뒤에는 Red, Green, Blue Primary의 hue와 saturation을 조절하는 macOS
`calibrationPrimaries`를 적용합니다. 원형 HSL hue에서 고정 세 대역을 삼각형 weight로 섞고, 회색 gate로
무채색의 무의미한 hue 이동을 막습니다. 활성 단계는 RGB를 `[0, 1]`로 제한하지만 identity는 단계를
건너뛰어 extended RGB를 bit-exact로 보존합니다. 이것은 scanner·display ICC calibration이 아니라
Develop recipe의 창의적 Primary 조정입니다. 세부 계약은 `primary-calibration-scalar.md`에 있습니다.

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
거부합니다. JSON의 `stages.tone_adjust`에는 입력값, 적용 여부, sampling mode, target, sample 수, band,
peak temporary bytes와 wall/process-CPU microseconds가 들어갑니다. 경로·file identity 값·SHA 값은
넣지 않습니다. 커브가 적용되지 않으면 sampling mode는 `none`, `curve_bands`는 `null`입니다. 기본
export는 추가 pixel fingerprint scan을 하지 않고 별도 개발 진단에서만 단계 통계를 계산합니다.

현재 CLI와 WinUI는 포인트 목록, Color Mixer 24개 control, Color Grading과 Primary Calibration recipe
입력을 아직 노출하지 않습니다. 기본 빈 커브와 0 control은 무연산이며 JSON에는 각 알고리즘 버전과
적용 여부가 들어갑니다.
native unit/conformance 경로는 활성 recipe를 직접 전달해 실제 처리 순서를 검증합니다.

## 성능과 메모리

pixel 변환은 기존 `WorkingImage`에 제자리 적용하므로 추가 full-frame buffer는 0입니다. 모든 값이
적용 임계값 이하인 기존 명령은 layout만 확인하고 full-frame tone scan 없이 즉시 반환합니다. 동적 band는
최대 1,048,576개의 `double` luma만 허용하고 실제 peak를 보고합니다. 631×403 저장소 fixture의 x64
Release 한 번 측정에서는 35,636 luma, 285,088 temporary bytes, tone stage 42,874 µs였습니다. 무조정
명령의 tone stage는 같은 측정에서 10 µs였습니다. 이 값은
현재 PC의 단일 관찰이며 성능 보증이나 ARM64 결과가 아닙니다.

포인트 커브는 고정 배열로 LUT를 만들고 기존 image에 제자리 적용하므로 heap allocation과 추가
full-frame buffer가 없습니다. 별도 성능 benchmark는 아직 만들지 않았습니다.

Color Mixer도 고정 8회 loop와 stack scalar만 사용하며 추가 allocation이나 full-frame buffer가 없습니다.
identity이면 working orchestration이 kernel 호출을 생략합니다.

Color Grading은 세 구간 offset, pivot과 width를 image call마다 한 번만 준비합니다. pixel loop는 stack
scalar만 사용하며 추가 allocation이나 full-frame buffer가 없습니다. identity이면 working
orchestration이 kernel 호출을 생략합니다.

Primary Calibration은 여섯 control을 고정 3원소 hue/saturation 배열로 image call마다 한 번만
준비합니다. pixel loop는 고정 세 대역과 stack scalar만 사용하며 추가 allocation이나 full-frame
buffer가 없습니다. identity이면 working orchestration이 kernel 호출을 생략합니다.

## 남은 제한

- dynamic raster는 Core Image 내부 필터와 bit-exact하지 않을 수 있습니다.
- scalar `pow` 중심 구현이며 SIMD/GPU 최적화 전입니다.
- 실제 macOS runtime tone golden, 사진 corpus 비교와 cross-platform 허용오차 manifest는 아직 없습니다.
- 실제 Core Image point curve golden, recipe serialization과 UI 편집 상태 연결은 아직 없습니다.
- 실제 Metal Color Mixer golden과 24개 control의 recipe/UI 연결은 아직 없습니다.
- 실제 Core Image Color Grading golden과 세 color wheel recipe/UI 연결은 아직 없습니다.
- 실제 macOS Primary Calibration golden과 여섯 control의 recipe/UI 연결은 아직 없습니다.
