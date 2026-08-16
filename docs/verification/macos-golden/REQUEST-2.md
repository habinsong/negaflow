# macOS 측에 요청 (2차) — Windows 대조에서 남은 한 가지

1차 골든 덕분에 여섯 가지가 닫혔습니다. **남은 것은 하나**이고, 그것을 닫으려면 맥에서
값 몇 개를 더 찍어 주셔야 합니다. 새 이미지를 만들 필요는 없고, **1차와 같은 V700 프레임**을
그대로 쓰시면 됩니다.

| 항목 | 원본 | SHA-256 앞 16 |
| --- | --- | --- |
| RGB | `GT-X900_frame_4.tiff` | `9e3d0daf2537273a` |

## 요청 A — 장면 통계 중간값 (필수)

`NegativeInversion.sampleStats` 가 계산하는 중간값이 필요합니다. 이 함수에는 이미
`NEGA_DEBUG` 환경변수로 `dmin / dmaxNorm / blackIn` 을 stderr 에 찍는 코드가 있습니다
(`NegativeInversion.swift`, `[nega] dmin=... dmaxNorm=... blackIn=...`).

```bash
NEGA_DEBUG=1 negaflow develop GT-X900_frame_4.tiff /tmp/out.tif \
  --raw --look none --film-type colorNegative --target main
```

이 한 줄의 **stderr 출력을 그대로** 주십시오.

가능하면 아래 네 가지도 함께 찍어 주시면 확실합니다(같은 함수 안의 지역 변수입니다).

| 변수 | 위치 |
| --- | --- |
| `targetW`, `targetH` | 축소본의 실제 크기 |
| `film.count` | 게이팅 후 남은 표본 수 |
| `densest` (SIMD3) | `pct(_, 0.002)` 세 채널 |
| `measuredDmax` (SIMD3) | `log10(dmin/densestFloor)` 세 채널 |

## 요청 B — 축소본 자체 (**이쪽이 결정적입니다**)

`sampleStats` 가 렌더한 축소본(`bitmap`, RGBAf, `targetW × targetH`)을 그대로 파일로
덤프해 주시면 가장 확실합니다. 크기가 작아 부담이 없습니다(320×488 × 4 × 4바이트 ≈ 2.5MB).

```swift
// sampleStats 안, render(...) 직후
if ProcessInfo.processInfo.environment["NEGA_DUMP_PROXY"] != nil {
    let data = bitmap.withUnsafeBufferPointer { Data(buffer: $0) }
    try? data.write(to: URL(fileURLWithPath: "/tmp/proxy-\(targetW)x\(targetH).f32"))
}
```

## 왜 필요한가

Windows 는 이 축소본을 **직접 만들고** macOS 는 **Core Image 로 렌더**합니다. 그 필터가
다르면 `p0.002`(최농부)가 달라지고, 그것이 `dmaxNorm` 을 통해 최종 픽셀을 채널마다 다르게
움직입니다.

Windows 는 점 표본(bilinear)에서 **면적 평균**으로 바꿔 G·B 를 열 배 가까이 맞췄습니다.

| 채널 | 고치기 전 | 지금 | macOS |
| --- | ---: | ---: | ---: |
| R median | 44132 | 45883 | 44908 |
| G median | 45786 | 48191 | 47896 |
| B median | 47172 | 49653 | 49865 |

**R 만 반대쪽으로 +975 남았습니다**(8비트로 3.8 레벨). 단일 혼합 비율로는 설명되지
않습니다 — R 은 필요한 이동의 226%, G 는 114%, B 는 92% 를 받았습니다. 그러므로 "얼마나
평균하느냐" 하나를 맞추는 문제가 아니고, 축소본의 채널별 실제 값을 봐야 합니다.

**추측으로 계수를 맞추면 이 사진 한 장만 맞고 다른 사진은 어긋납니다.** 그래서 값을
받기 전까지 손대지 않고 있습니다.

### B 안이 A 안보다 결정적인 이유

Apple 문서를 확인한 결과, `transformed(by:)` 의 축소는 **제대로 된 리샘플링 필터가
아닙니다.** 고품질 축소용으로 `CILanczosScaleTransform` 이 따로 있고, 어파인 축소에서는
에일리어싱 대책을 별도로 안내합니다.

즉 macOS 는 깨끗한 면적 평균을 하는 것이 아닙니다. Windows 를 면적 평균으로 바꿨을 때
G·B 가 크게 붙고 R 만 반대로 넘어간 것이 그 증거입니다 — 면적 평균은 bilinear 보다
훨씬 가깝지만 동일하지는 않습니다.

정확히 맞추려면 Core Image 의 어파인 샘플러를 재현해야 하는데, 그 내부 동작은 문서화되어
있지 않아 추측으로 복제할 수 없습니다. **축소본 자체를 받으면 필터를 몰라도 맞출 수
있습니다.** A 안(숫자)만 오면 얼마나 어긋났는지는 알 수 있지만 무엇으로 고칠지는
여전히 모릅니다.

## 1차 골든으로 이미 닫힌 것 (참고)

| 항목 | 결과 |
| --- | --- |
| 적외선 정렬·검출 | **완전 일치** — coverage 0.1006%, offset (1,−1), peak 0.012, 120/59 |
| 인화 기하 | **소수점까지 일치** — 천공 반경 32.69507311586052 포함 |
| `{name}` 토큰 | 카드 표시 이름으로 확인, Windows 도 동일 |
| 8100 흑화 | Windows 쪽 결함이었고 **고쳤습니다** (base 0.0320 → 0.1764, macOS 0.1913) |
| GrainMend 복원 | ">100 비율 ≈ coverage" 관계가 양쪽에서 성립 |

1차에서 지적해 주신 두 가지도 반영했습니다 — 8100 IR 파일이 없어 작업 2·3 이 V700
쌍으로만 된 것, 그리고 작업 6 의 고정 합성 메타데이터를 Windows 도 같은 값으로 넣어야
대조가 성립한다는 것. 후자는 Windows 쪽 대조를 아직 하지 않았습니다.
