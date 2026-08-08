# ADR-0013: Color Mixer는 고정 8대역 working-RGB HSL scalar로 시작한다

- 상태: 채택
- 날짜: 2026-08-04

## 문제

macOS Chroma Engine은 포인트 커브 뒤에 빨강·주황·노랑·초록·바다색·파랑·자주·자홍의 hue,
saturation, luminance를 조정하는 `colorMixerHSL`을 실행합니다. 일반 HSL 라이브러리나 Windows UI
색 선택기를 대신 사용하면 대역 중심, 회색 보호, 계수와 처리 domain이 달라집니다. 반대로 M6 전체
그래프를 한 객체에 미리 넣으면 아직 필요하지 않은 상태와 I/O가 섞여 유지보수가 어려워집니다.

## 결정

1. 같은 Apache-2.0 저장소의 macOS `ColorMixer`, `ColorMixerStage`, `colorMixerHSL`과 post-pipeline
   순서를 기준으로 C++20 scalar를 독립 작성합니다. 외부 HSL 구현이나 특허의 코드를 복사하지 않습니다.
2. 파라미터는 hue/saturation/luminance 각각 고정 8개 `float`이며 범위는 UI와 같은 `[-1, 1]`입니다.
   배열 순서는 red, orange, yellow, green, aqua, blue, purple, magenta로 고정합니다.
3. 모든 값의 `abs(value) < 1e-4`이면 identity입니다. identity는 픽셀을 변환하거나 clamp하지 않고
   extended RGB와 alpha를 bit-exact로 보존합니다.
4. 활성 mixer는 Core Image의 extended-linear sRGB working 값을 먼저 `[0, 1]`로 제한한 뒤 macOS
   kernel과 같은 RGB↔HSL Float32 수식을 적용합니다. 표준 HSL이 보통 gamma-encoded sRGB로 정의된다는
   이유로 임의의 transfer function을 추가하지 않습니다.
5. hue 중심은 `0, 0.083333, 0.166667, 0.333333, 0.5, 0.666667, 0.75, 0.833333`이고 원형 hue
   거리의 삼각 가중치 폭은 `0.14`입니다. 겹친 대역은 가중 평균합니다.
6. saturation `0.04~0.18` smoothstep gate로 무채색을 보호합니다. hue는 최대 약 ±30도
   (`control × 0.0833`), saturation은 `1 + control`, luminance는 `control × 0.16`을 적용하고 최종
   HSL과 RGB를 `[0, 1]`에 제한합니다. alpha는 보존합니다.
7. 처리 순서는 `포인트 커브 → Color Mixer`입니다. 수학은 `color_mixer.cpp`에, 순서와 소유 pixel
   실패 처리는 작은 working orchestration에 둡니다. 파일 I/O, TIFF, CLI parsing과 UI 상태는 kernel이
   소유하지 않습니다.
8. 제어값, image view 또는 입력 pixel이 유효하지 않으면 명시적으로 실패하고 orchestration은 결과
   pixel을 게시하지 않습니다. 픽셀 경로에는 heap allocation이나 추가 full-frame buffer가 없습니다.
9. 이번 체크포인트는 native recipe 경계와 conformance를 추가합니다. CLI와 WinUI는 아직 24개 값을
   입력·저장하지 않으며 report에는 알고리즘 버전과 적용 여부만 기록합니다.
10. 일반 이미지 SHA-256 기본값은 계속 `끔`입니다. Color Mixer는 hash를 요구하지 않습니다.

## 결과

고정 8회 loop의 scalar reference가 생겨 이후 Direct2D shader, AVX2와 NEON이 같은 수치 계약을
공유할 수 있습니다. Color Mixer 수학은 기존 tone·point curve 수학과 별도 파일에 있고 orchestration은
단계 순서와 실패 소유권만 담당하므로 한 타입이 수치·I/O·UI를 함께 소유하지 않습니다.

## 검증 한계

현재 fixture는 저장소 소유 Metal 수식을 별도 Float32 계산기로 재현한 합성 기준이며 실제 macOS GPU
render golden은 아닙니다. Metal compiler의 연산 결합과 Core Image runtime 차이는 실제 pixel diff가
생기기 전까지 bit-exact하다고 주장하지 않습니다.

## 공식 근거와 권리

- [Apple Core Image workingColorSpace](https://developer.apple.com/documentation/coreimage/cicontextoption/workingcolorspace)
- [Apple Core Image Kernel Language Reference](https://developer.apple.com/metal/CoreImageKernelLanguageReference11.pdf)
- [Apple Metal resources](https://developer.apple.com/metal/resources/)
- [W3C CSS Color 4 HSL](https://www.w3.org/TR/css-color-4/#the-hsl-notation)

새 runtime dependency, 외부 코드, 이미지, ICC profile 또는 sample payload는 추가하지 않습니다. 관련
공개 claims와 구현 차이, 법적 한계는 `research/color-mixer-sources.md`에 기록합니다.
