# 장면 통계 축소본 (macOS 실측)

`NegativeInversion.sampleStats` 가 채널별 `densest`(=`dmaxNorm`)를 재는 바로 그 축소본입니다.
Windows 포팅본이 같은 값을 재는지 대조하기 위한 것이며, REQUEST-2 의 요청 B 에 대한 답입니다.

| 항목 | 값 |
| --- | --- |
| 원본 | `GT-X900_frame_4.tiff` (sha256 `9e3d0daf2537273a299d5a77ed17c2d3c617131e59cc6afa9d90daf867d1a198`) |
| 파일 | `GT-X900_frame_4-proxy-320x488.f32` |
| sha256 | `6b4b65871f66f00f653bb05c3687b2a7eeb327a9946267c22a31daf030836798` |
| 크기 | 2,498,560 byte = 320 × 488 × 4채널 × 4byte |
| 형식 | RGBAf, little-endian float32, 행 우선(y-down), premultiplied |
| 색공간 | linear sRGB (작업공간·출력공간 모두) |
| 커밋 | `4fd7450` |

## 어떻게 만들어졌나

```swift
let targetW = max(64, min(320, Int(extent.width)))        // 320 (폭 상한만 있고 높이 상한은 없다)
let scale   = Double(targetW) / Double(extent.width)      // 320 / 2272 = 0.14084507…
let targetH = max(1, Int(Double(extent.height) * scale))  // int(3471 × 0.140845) = 488
let scaled  = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
// CIContext(workingColorSpace: linearSRGB).render(scaled, format: .RGBAf, colorSpace: linearSRGB)
```

명시적 리샘플 필터를 지정하지 않으므로 Core Image 의 기본 어파인 샘플링이다. **정확한 박스
평균이라고 보장할 수 없다** — 이 파일을 남기는 이유가 그것이다. 필터 모양을 추측하는 대신
결과 값을 직접 대조하면 된다.

재현:

```bash
NEGA_DEBUG=1 NEGA_DUMP_PROXY=1 negaflow develop GT-X900_frame_4.tiff /tmp/out.tif \
  --raw --look none --film-type colorNegative --target main
```

두 환경변수 모두 opt-in 이라 평소 실행에는 영향이 없다.

## 읽는 법

통계는 **6% inset 안쪽만** 쓴다. `insetX = max(1, int(320 × 0.06)) = 19`,
`insetY = max(1, int(488 × 0.06)) = 29` → 표본 282 × 430 = 121,260.

```python
import numpy as np
a = np.fromfile("GT-X900_frame_4-proxy-320x488.f32", dtype="<f4").reshape(488, 320, 4)
inset = a[29:488-29, 19:320-19, :3].astype(np.float64).reshape(-1, 3)
```

## 퍼센타일 규약 — `0.002` 는 백분율이 아니다

`pct(_, f)` 의 `f` 는 분수다. 인덱스가 그대로다:

```swift
let idx = max(0, min(s.count - 1, Int(Double(s.count - 1) * f)))
```

`f = 0.002` → `idx = int(121259 × 0.002) = 242` → **0.2 퍼센타일**. numpy 로 대조할 때
`np.percentile(col, 0.002)` 를 쓰면 0.002% 를 재게 되어 값이 크게 어긋난다.

```python
def swift_pct(col, f):
    s = np.sort(col); n = len(s)
    return s[max(0, min(n - 1, int((n - 1) * f)))]
```

## 실측값 (inset 표본 121,260개, Swift 인덱스 규약)

| f | R | G | B |
| --- | ---: | ---: | ---: |
| **0.002** | **0.06365967** | **0.03149414** | **0.02496338** |
| 0.005 | 0.06854248 | 0.03469849 | 0.02767944 |
| 0.01 | 0.07312012 | 0.03808594 | 0.02932739 |
| 0.05 | 0.08502197 | 0.04281616 | 0.03123474 |
| 0.1 | 0.08929443 | 0.04458618 | 0.03256226 |
| 0.5 | 0.11151123 | 0.06079102 | 0.04507446 |
| 0.9 | 0.15148926 | 0.09552002 | 0.07147217 |
| 0.99 | 0.33471680 | 0.28833008 | 0.22619629 |
| 0.998 | 0.34033203 | 0.29589844 | 0.23742676 |
| min | 0.04159546 | 0.01701355 | 0.01141357 |
| max | 0.34741211 | 0.30371094 | 0.25341797 |
| mean | 0.12237967 | 0.07161678 | 0.05330181 |

inset 적용 **전** 전체 320 × 488: p0.002 = (0.04577637, 0.02038574, 0.01478577),
p0.5 = (0.11248779, 0.06137085, 0.04516602).

## 알파 — 표본에는 영향이 없다

RGBAf 는 premultiplied 라 확인했다.

| 범위 | alpha min | `< 0.999` 비율 |
| --- | ---: | ---: |
| 전체 320 × 488 | 0.909180 | 0.2049 % |
| inset 안 | **1.000000** | **0.0000 %** |

알파가 1 미만인 화소는 축소 배율이 정수가 아니라 생기는 가장자리 희석분이고, 6% inset 이
전부 제외한다. 대조에서 알파는 변수가 아니다.

## 이 축소본이 만든 값

```
[nega-proxy] targetW=320 targetH=488 inset=(19,29) pixels=121260 film=121260
             gate=0.322839 darkCut=0.043237
             densest=(0.0637,0.0315,0.0250) densestFloor=(0.0637,0.0315,0.0250)
             measuredDmax=(0.7252,0.9690,0.9708)
[nega] dmin=(0.3381,0.2932,0.2334) dmaxNorm=(0.7252,0.9690,0.9708)
       blackIn=(0.1469,0.0927,0.0693) midD=0.626
```

`film.count == pixels.count` 이므로 **비필름 게이트는 한 화소도 거르지 않았다**.
`neutralDarkRatioCut` 은 `baseRatio = 0.3381 / 0.2334 = 1.4487 < 1.5` 라 비활성이다.
