# ColorSync ↔ Windows ICM 색변환 일치 조사

- 날짜: 2026-08-06
- 질문: 같은 ICC 프로파일로 같은 색을 변환할 때 macOS ColorSync 와 Windows ICM(mscms)이 같은 숫자를 내는가
- 이유: 다르면 Windows 가 OS 색상 API 를 버리고 LittleCMS 를 들여야 하고, ADR-0004 의 "네이티브 엔진 제3자 런타임 의존성 0개"가 무너진다

## 1. 두 경로의 설정 대조

### Windows

`Negaflow.Windows/src/Native/imaging/scanner_to_working.cpp` 의
`convert_scanner_to_working` 이 입구입니다. 임베디드 ICC 가 있으면
`detail::convert_embedded_icc_to_srgb16` 로 넘깁니다
(`Negaflow.Windows/src/Native/imaging/scanner_to_working.cpp:176`).

| 항목 | 값 | 근거 |
|---|---|---|
| 변환 담당 | `IcmRgb16Transform::initialize` / `translate` | `Negaflow.Windows/src/Native/imaging/icm_icc_converter.cpp:67`, `:113` |
| 대상 프로파일 | 시스템 표준 sRGB (`GetStandardColorSpaceProfileW(LCS_sRGB)`) | `Negaflow.Windows/src/Native/imaging/icm_icc_converter.cpp:20` |
| rendering intent | `INTENT_RELATIVE_COLORIMETRIC` 하드코딩 | `Negaflow.Windows/src/Native/imaging/icm_icc_converter.cpp:96` |
| black point compensation | 설정 없음. ICM 은 이 intent 에서 BPC 를 적용하지 않음 | 같은 파일 96–104행에 BPC 설정 부재 |
| 중간 비트 심도 | 16비트 정수, sRGB 인코딩 도메인 (`BM_16b_RGB` → `BM_16b_RGB`) | `Negaflow.Windows/src/Native/imaging/icm_icc_converter.cpp:130` |
| working color space | linear sRGB float32 | `Negaflow.Windows/src/Native/imaging/scanner_to_working.cpp:113` |

즉 Windows 는 **ICC → (ICM, 상대색도, BPC 없음) → sRGB 인코딩 16비트 → linear float32** 입니다.

### macOS

대응 경로는 `Sources/Chromabase/Imaging/ImageLoader/` 입니다. 스캐너 raw
(`loadScannerTIFFDecoded`)와 일반 가져오기(`loadImportedDecoded`)가 **같은 함수**
`profileAwareImage` 를 공유합니다
(`Sources/Chromabase/Imaging/ImageLoader/ImageLoader+Standard.swift:27`,
`Sources/Chromabase/Imaging/ImageLoader/ImageLoader.swift:181`).

| 항목 | 값 | 근거 |
|---|---|---|
| 변환 담당 | `ImageLoader.profileAwareImage` → `CIImage(cgImage:)`. 명시적 변환 코드 없음 | `Sources/Chromabase/Imaging/ImageLoader/ImageLoader+ImageIO.swift:18` |
| 실제 변환 주체 | Core Image / ColorSync 가 렌더 시점에 암묵 수행 | `Sources/Chromabase/Imaging/ImageLoader/ImageLoader+ImageIO.swift:28` |
| rendering intent | **제품 코드가 지정하지 않음** | 같은 파일 28행. `CIImage(cgImage:)` 에 intent 인자 없음 |
| black point compensation | **제품 코드가 지정하지 않음** | 위와 같음 |
| working color space | `CGColorSpace.linearSRGB` | `Sources/Chromabase/Engine/SamplingContextPool.swift:39`, `Sources/Chromabase/Engine/ChromabaseEngine.swift:44` |
| 중간 비트 심도 | `CIContext.workingFormat` = **RGBAh (half float)**. 실측값이며 코드가 지정하지 않은 기본값 | `SamplingContextPool.context` 는 `.workingFormat` 을 설정하지 않음 |

즉 macOS 는 **ICC → (ColorSync, intent 미지정) → linear sRGB half float → float32** 입니다.

### 설정 차이 정리

| | macOS | Windows |
|---|---|---|
| intent | 미지정 (ColorSync 기본) | 상대색도 명시 |
| BPC | 미지정 | 없음 |
| 중간 도메인 | linear, half float | sRGB 인코딩, 16비트 정수 |

**중간 도메인이 구조적으로 다릅니다.** Windows 는 sRGB 인코딩 16비트를 거쳤다가 다시 선형화하고
macOS 는 선형 도메인에서 끝냅니다. 이 자체로 근암부에 양자화 바닥이 생깁니다(인코딩 도메인
1/65535 ≈ 1.5e-5 → 선형 약 1.2e-6). 작지만 0 은 아니므로 비교 허용오차에 반영해야 합니다.

macOS 쪽에 intent 를 지정할 자리가 없다는 점이 중요합니다. `CIImage(cgImage:)` 경로에는 intent 를
넣는 공개 API 가 없습니다. 따라서 "설정을 맞춘다"는 해법은 macOS 쪽에서는 성립하지 않고, 맞춰야
한다면 Windows 쪽을 ColorSync 의 실제 거동에 맞추는 방향이 됩니다.

## 2. 측정: ColorSync 는 순수 감마 곡선을 그대로 쓰지 않는다

`colorsync-icm-parity-v1` fixture 로 실측했습니다. 프로파일은 sRGB 프라이머리 + 감마
2.19921875 의 matrix/TRC 입력 프로파일이라, 대상 sRGB 와 프라이머리가 같아 **행렬이 상쇄되고 TRC
만 남습니다.** 상대색도·BPC 없음이라면 결과는 정확히 `out = in ^ 2.19921875` 여야 합니다.

실측은 다릅니다.

| in | 측정 out | `in^2.19921875` | 측정/in |
|---|---|---|---|
| 0.005 | 0.00031281 | 0.00000870 | 0.0626 |
| 0.010 | 0.00062467 | 0.00003995 | 0.0625 |
| 0.020 | 0.00125029 | 0.00018348 | 0.0625 |
| 0.050 | 0.00312524 | 0.00137642 | 0.0625 |
| 0.099 | 0.00618753 | 0.00618276 | 0.0625 |
| 0.125 | 0.01030900 | 0.01032542 | 0.0825 |
| 0.500 | 0.21764499 | 0.21775553 | 0.4353 |

ColorSync 는 device 값 약 **0.099 아래에서 곡선을 기울기 정확히 1/16 = 0.0625 인 직선으로
대체합니다.** 0.099 위에서는 순수 거듭제곱과 사실상 일치합니다(잔차 약 1.6e-5, half float 정밀도
수준).

직선과 곡선이 만나는 지점은 `x^1.19921875 = 1/16` → `x ≈ 0.09905` 로, 측정과 맞습니다. 접선이
아니라 원점에서 곡선 위 한 점으로 그은 **현(chord)** 입니다. 즉 ColorSync 는 곡선의 유효 이득
`f(x)/x` 가 1/16 아래로 내려가지 않도록 하한을 겁니다. 역방향 곡선의 기울기를 16 으로 제한하는,
암부 노이즈 증폭을 막는 통상적인 처리로 보입니다.

**in = 0.005 에서 측정값은 순수 거듭제곱의 36배입니다.** 근암부에서 이 정도 차이는 반전
파이프라인이 흡수할 수 있는 크기가 아닙니다.

### 원인 분리 (검증한 것)

이 토우가 우리 렌더 경로의 부작용인지 ColorSync 자체인지 분리했습니다.

- `CIContext` working format 을 `RGBAh`(제품 기본값) 와 `RGBAf` 로 각각 렌더 → **두 결과가 완전히
  동일**. half float 정밀도 문제가 아닙니다.
- Core Image 를 우회해 `CGColor.converted(to:intent:.relativeColorimetric)` 로 직접 변환 →
  같은 값(0.005 → 0.00031250, 0.099 → 0.00618750). **Core Image 가 아니라 ColorSync 의 곡선
  평가 방식입니다.**

이 분리 실행은 일회성 진단이었고 저장소에 남기지 않았습니다. 재현하려면 위 두 경로를 같은
프로파일·같은 입력으로 렌더해 비교하면 됩니다.

## 3. 아직 답하지 않은 것

**Windows ICM 이 같은 프로파일에서 같은 토우를 쓰는지는 측정하지 않았습니다.** 이 저장소의 작업
환경은 macOS 이고 Windows 네이티브 코드를 빌드·실행할 수 없습니다. 그래서 이번 산출물은 결론이
아니라 **기준값**입니다.

Windows 쪽에서 해야 할 일은 하나입니다. 같은 합성 프로파일을 만들고(SHA-256 대조),
`patches[].in` 을 `round(in * 65535)` 로 정수화해 기존 `convert_scanner_to_working` 에 넣은 뒤,
결과 working 값을 `patches[].out` 과 비교하십시오.

판정 기준 제안:

- 중간톤·하이라이트(in ≥ 0.125): 차이가 5e-4 를 넘으면 행렬/TRC 수학이 어긋난 것입니다.
- 근암부(in ≤ 0.05): 여기서 갈리는지가 이 조사의 핵심입니다. ICM 이 순수 거듭제곱을 쓰면
  `in = 0.005` 에서 약 36배 차이가 납니다. 이 경우 두 CMS 는 같은 엔진으로 볼 수 없습니다.

## 4. 결과가 갈릴 때의 선택지

근암부가 갈린다고 해서 LittleCMS 도입이 바로 정당화되지는 않습니다. 먼저 볼 것은 순서대로입니다.

1. **ICM 쪽에서 같은 하한을 재현할 수 있는가.** TRC 를 그대로 넘기지 말고 ColorSync 와 같은
   토우(기울기 하한 1/16)를 적용한 곡선으로 프로파일을 리라이트해 ICM 에 넘기면, 의존성 없이
   양쪽을 맞출 수 있습니다. 우리 쪽 코드만으로 끝나므로 ADR-0004 를 지킵니다.
2. **하한이 정말 필요한 값인가.** 스캐너 입력 도메인에서 device 0.099 아래는 Dmax 근처입니다.
   실제 필름 스캔에서 이 구간이 최종 결과에 얼마나 기여하는지 먼저 재고, 무시할 수 있으면
   허용오차를 넓히는 것도 정당한 답입니다.
3. 위 둘이 모두 실패할 때만 제3자 CMS 를 논의합니다.

## 5. 이 조사가 만든 것

- `Tests/ChromabaseTests/SyntheticScannerICCProfile.swift` — 합성 프로파일 바이트
- `Tests/ChromabaseTests/ColorSyncParityPatchSet.swift` — 패치 34개
- `Tests/ChromabaseTests/ColorSyncIcmParityGoldenTests.swift` — emitter + fixture 계약 테스트
- `Negaflow.Windows/docs/research/colorsync-icm-parity-profile.md` — 프로파일 합성 규칙(규범)
- `Negaflow.Windows/docs/decisions/0023-colorsync-icm-parity-probe.md` — ADR

제품 코드(`Sources/`)는 변경하지 않았습니다.
