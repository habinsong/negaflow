# Gray 스캔 가져오기 — macOS 에서 남은 검증

기준일: 2026-08-25
소유 코드: `Sources/Chromabase/Imaging/ImageLoader/ImageLoader+ImageIO.swift`
관련 문서: `negaflow-scanner-sane` 저장소의 `negaflow-mac/docs/opticfilm-gray.md`

이 문서는 **macOS 실기 검증이 남아 있어서** 존재한다. 코드 수정은 이미 들어갔다.

## 1. 배경

OpticFilm 8100 의 Gray 스캔은 SANE 백엔드 결함으로 지금까지 **아예 만들어지지 않았다**(멈춤,
0 B). 그 결함을 고치면서 Negaflow 로 **Samples/Pixel 1, 16-bit, ICC 프로필 없는 TIFF** 가
처음으로 실제로 들어오게 됐다. 그 입력을 앱이 제대로 읽는지는 별개 문제다.

Windows 쪽에서는 그 입력이 **완전히 거부되고 있었다.** `ScannerWorkingRowSink::begin` 이
`rgb16`/`rgba16` 만 받고 `gray16` 은 `invalid_argument` 로 떨궈서
`--prepare-scanner-tiff` 가 `wic_row_sink_failed` 로 끝났다. 그건 Windows 에서 고쳤다.

macOS 는 `CIImage(cgImage:)` 가 회색 `CGImage` 를 그대로 받으므로 **거부되지는 않는다.**
대신 아래의 색공간 문제가 있다.

## 2. 확정한 macOS 문제

`ImageLoader.profileAwareImage(_:properties:untaggedTIFFRole:)` 는 프로필 없는 16bit TIFF 를
"스캐너 linear raw" 로 해석한다. 그 판정 자체는 맞다 — TIFF 에는 PNG 와 달리 태그가 없을 때의
기본 색공간이 없고, 프로필 없는 16bit TIFF 는 사실상 스캐너 소프트웨어의 raw 출력이다.

문제는 지정하는 색공간이 **항상 `CGColorSpace.linearSRGB`** 였다는 점이다.

```swift
// 고치기 전
if untaggedTIFFRole == .linearScannerRaw,
   shouldInterpretAsLinearRaw(cg, properties: properties),
   let linear = CGColorSpace(name: CGColorSpace.linearSRGB) {
    return CIImage(cgImage: cg, options: [.colorSpace: linear])
}
```

Samples/Pixel 1 인 TIFF 는 `CGImageSource` 가 **monochrome 모델** `CGImage` 로 준다. 거기에
3채널 RGB 색공간을 `kCIImageColorSpace` 로 지정하면 이미지 데이터와 색공간의 모델이 어긋난다.
Core Image 는 그 지정을 쓸 수 없고, gray raw 가 **linear 가 아닌 기본 해석**으로 들어간다.
결과는 크래시가 아니라 **같은 필름을 Color 로 스캔했을 때와 밝기·감마가 다른 사진**이다 —
로그에는 아무것도 남지 않는다.

## 3. 들어간 수정

`linearRawColorSpaceName(_:)` 을 추가해 이미지의 색 모델에 맞는 linear 색공간을 고른다.

```swift
static func linearRawColorSpaceName(_ cg: CGImage) -> CFString {
    cg.colorSpace?.model == .monochrome
        ? CGColorSpace.linearGray
        : CGColorSpace.linearSRGB
}
```

- RGB/RGBA 입력의 동작은 **한 글자도 바뀌지 않는다** — 기존과 같은 `linearSRGB` 다.
- monochrome 입력만 `linearGray` 로 간다.
- `CGColorSpace.linearGray` 는 macOS 10.12+ 다. 배포 대상(`macos: :tahoe`)보다 훨씬 아래다.

`profileAwareImage` 를 호출하는 경로는 전부 이 수정을 함께 받는다:
`ImageLoader+Standard.swift:12,27`, `ImageLoader.swift:260,297,330`,
`IT8PatchEvaluator.swift:405`.

## 4. 검증 상태

- **미검증.** 이 저장소의 Swift 는 Windows 개발기에서 빌드할 수 없어서 컴파일도 실행도
  하지 않았다. 아래 §5 를 통과하기 전에는 통과로 기록하지 않는다.
- 참고로 Windows 에서 같은 계약(1채널 표본을 R·G·B 에 복제, linear 해석)을 구현한 뒤 실기
  Gray 스캔의 화소가 `channel_max = [0.2074, 0.2074, 0.2074, 1]` 로 세 채널이 동일하게
  나오는 것을 확인했다. 같은 파일의 Color 스캔은 `[0.4043, 0.1679, 0.0934, 1]` 이었다.

## 5. macOS 에서 해야 할 일

### 5.1 준비

먼저 `negaflow-scanner-sane` 의 `negaflow-mac/docs/opticfilm-gray.md` §5 를 통과시켜
**Gray TIFF 를 실제로 만들 수 있는 상태**를 만든다. 그게 없으면 이 절은 시험할 입력이 없다.

### 5.2 합격 기준 1 — 빌드와 단위 시험

```bash
swift build
swift test
```

경고 0, 실패 0.

### 5.3 합격 기준 2 — 같은 프레임의 Gray 와 Color 가 같은 밝기로 들어온다

같은 필름 한 컷을 600 dpi 16-bit 로 **Gray 한 번, Color 한 번** 스캔한다.
둘 다 Negaflow 로 가져와 현상 없이 원본 상태의 밝기를 비교한다.

**합격**: Gray 사진의 밝기·감마가 Color 사진의 휘도와 눈에 띄게 어긋나지 않는다.
**불합격**: Gray 쪽만 밝거나 어둡고 대비가 다르다 → `kCIImageColorSpace` 지정이 여전히
안 먹고 있다. `cg.colorSpace?.model` 을 실제로 찍어 monochrome 이 맞는지부터 본다.

### 5.4 합격 기준 3 — Gray 사진이 세 화면을 통과한다

가져온 Gray 사진이 Library 썸네일 → Develop preview → Print 썸네일/이미지까지
같은 프레임으로 열린다. 흑백 네거/포지티브 현상 프로세스가 정상 동작한다.

### 5.5 합격 기준 4 — 컬러 회귀

기존 Color 스캔과 일반 가져오기(PNG/JPEG/TIFF/RAW)의 밝기·색이 수정 전과 **동일**하다.
이 수정은 monochrome 입력에만 걸리므로 달라지면 안 된다.

## 6. 아직 열려 있는 항목

**Gray + 임베디드 Gray ICC 프로필.** 이 수정은 **프로필이 없는** raw 경로만 다룬다.
회색 ICC 프로필이 박힌 16bit TIFF 를 가져오면 macOS 는 `CIImage(cgImage:)` 로 그 프로필을
그대로 쓰지만, Windows 는 ICM 변환이 RGB 입력만 받아 `unsupported_icc_color_space` 로
거부한다. 스캐너 Gray 출력에는 프로필이 없으므로 이번 범위 밖이지만, 가져오기 쪽에서는
남은 parity 차이다. 실제 fixture 가 생기면 그때 연다.
