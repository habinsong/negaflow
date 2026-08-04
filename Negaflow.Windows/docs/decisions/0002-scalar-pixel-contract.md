# ADR-0002: 첫 scalar 픽셀 계약과 네거티브 반전

상태: 채택
기준일: 2026-08-04

## 결정

- 작업 픽셀은 linear-sRGB primaries의 RGBA float32입니다.
- RGB는 음수와 1 초과 값을 보존하며, pointwise 단계에서 숨은 clamp를 하지 않습니다.
- 초기 사진 경로의 alpha는 straight, finite, `[0,1]`이며 RGB kernel이 정확히 보존합니다.
- raster 원점은 좌상단, pixel center는 `(x + 0.5, y + 0.5)`입니다.
- NaN/Inf 입력과 parameter는 명시적 오류로 거부하고 결과를 0으로 대체하지 않습니다.
- 첫 CPU 경로는 scalar/reference이며 전역 fast-math를 사용하지 않습니다.
- `negativeInvert`는 macOS `shoulder-print-response-v4`의 statement order와 epsilon을 유지합니다.
- 인화 응답의 파생 계수는 float32 bit pattern으로 고정해 향후 HLSL과 공유합니다.

## 구현 범위

첫 단계에는 checked dimension/stride/capacity 검증, exposure, RGB 3x4 matrix,
color/B&W negative inversion만 포함합니다. SIMD, HLSL, 이미지 decode, ICC 변환은 포함하지 않습니다.

## 저작권·라이선스 조사

저장소 기준선은 Apache-2.0입니다. 합성 fixture만 사용하며 외부 사진 byte는 포함하지 않습니다.
Darktable과 RawTherapee는 GPL-3.0이므로 구현 코드를 참고하거나 복사하지 않았습니다. 수식의 근거는
동일 저장소의 Swift/Metal 코드와 테스트뿐입니다.

## 특허 선행 조사

H&D 특성 곡선은 1890년부터 알려진 감광학 개념입니다. 검색에서 확인한 디지털 네거티브 관련
`EP0846390B1`, `US6274299B1`, `US5828793A`는 Google Patents상 만료 상태였습니다. 이 조사는
초기 engineering screen이며 법률 의견이나 최종 freedom-to-operate 보증은 아닙니다. 구현은 해당
특허의 LUT·장면 분석 청구를 복제하지 않고, Negaflow의 고정 인화 응답 primitive만 이식합니다.

## 검증 기준

- layout/overflow/stride 오류는 exact status로 비교합니다.
- pointwise extended-range와 alpha 보존은 직접 값으로 검사합니다.
- 네거티브 반전은 합성 density anchor에 abs+rel `5e-6`을 사용합니다.
- x64와 ARM64는 같은 fixture와 고정 상수 bit pattern으로 빌드합니다.
- ARM64 cross-build와 실제 ARM64 실행 증거를 구분합니다.
