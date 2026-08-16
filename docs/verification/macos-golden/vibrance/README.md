# CIVibrance 사상과 vibrance 단계 실측 (macOS)

REQUEST-3 의 요청 A·B·C 에 대한 답입니다. `CIVibrance` 는 Apple 내장 필터라 커널 소스가
없으므로, 수식 대신 **값**을 넘깁니다.

원본: `GT-X900_frame_4.tiff`
(sha256 `9e3d0daf2537273a299d5a77ed17c2d3c617131e59cc6afa9d90daf867d1a198`)

모든 `.f32` 는 리틀엔디언 `Float32`, `RGBAf`, 행 우선(y-down), **linear sRGB** 입니다.

| 파일 | 크기 | sha256 |
| --- | ---: | --- |
| `civibrance-input-128x39.f32` | 79,872 | `75c3102c56181938a7ef292b7ea0389e734a03f9d6af5f0d490932ba0882881a` |
| `civibrance-a0.000-128x39.f32` | 79,872 | `75c3102c56181938a7ef292b7ea0389e734a03f9d6af5f0d490932ba0882881a` |
| `civibrance-a0.100-128x39.f32` | 79,872 | `d1d8a2ddc351467d089f1786fb2c1511c641d072fa30edbe3be19004d9c446e4` |
| `civibrance-a0.252-128x39.f32` | 79,872 | `758a90b63f50f596e8812356727df47550f1a950c1c7d61e4a5abd65f777e907` |
| `civibrance-a0.259-128x39.f32` | 79,872 | `a2bf05e45cc445bc07814dba8c92e5eb28b39a21d6f13a446bbaeea3d68b85b7` |
| `civibrance-a0.500-128x39.f32` | 79,872 | `7a3898301458f11286a5b89d7a46a374c58794035eacec3aa070dcabd5cb7969` |
| `frame4-preview-320x488.f32` | 2,498,560 | `b0b5cd59e24ba142d026251e1086722a90a85bc1d24cd28fb869a45b5b84a7d0` |
| `frame4-postvib-320x488.f32` | 2,498,560 | `ac3aed97f8afac685831faa5321881bac2406bfb8e031dd33d42d26551813df2` |
| `frame4-satproxy-160x244.f32` | 624,640 | `de2bf495585434c6d2a582f16a26b61832062679353973dd8e293bd1a328a662` |

## 요청 A — CIVibrance 격자

요청하신 규약 그대로입니다. 128 × 39 = 4,992 화소 중 앞 4,913 개가 17³ 격자이고 나머지는 0:

```
i → (R, G, B) = (i / 289, (i / 17) % 17, i % 17) / 16,  alpha = 1
```

입력 격자도 함께 올렸습니다(`civibrance-input-…`) — 인덱스 규약을 다시 만들 필요가 없습니다.

**`amount = 0.000` 은 입력과 sha256 이 같습니다.** 렌더 경로가 값을 건드리지 않는다는
확인이며, 요청하신 항등 검사입니다.

```python
import numpy as np
W, H, N = 128, 39, 4913
def load(name):
    return np.fromfile(name, dtype="<f4").reshape(H * W, 4)[:N, :3].astype(np.float64)
```

### 수식이 다릅니다 — 실측 대조

`vibrance_math.h` 의 수식을 같은 격자에 적용해 `CIVibrance` 와 비교했습니다.

| amount | 최대절대차 R / G / B | RMS R / G / B |
| --- | --- | --- |
| 0.259 | 0.064922 / **0.096432** / 0.059999 | 0.024159 / 0.030232 / 0.022814 |
| 0.500 | 0.098335 / **0.149590** / 0.115885 | 0.041784 / 0.042882 / 0.040645 |

표본 몇 점(amount 0.259):

| 입력 (R,G,B) | CIVibrance | Windows 수식 |
| --- | --- | --- |
| (0.0000, 0.0000, 0.0000) | (0.00000, 0.00000, 0.00000) | (0.00000, 0.00000, 0.00000) |
| (0.5000, 0.5000, 0.5000) | (0.50000, 0.50000, 0.50000) | (0.50000, 0.50000, 0.50000) |
| (1.0000, 0.0000, 0.0000) | (1.00008, −0.00004, −0.00004) | (1.00000, 0.00000, 0.00000) |
| (1.0000, 1.0000, 1.0000) | (1.00001, 1.00001, 1.00001) | (1.00000, 1.00000, 1.00000) |
| (0.2500, 0.7500, 0.1250) | (0.21988, **0.84036**, 0.06476) | (0.21614, **0.76471**, 0.07900) |
| (0.7500, 0.1250, 0.5000) | (0.80806, **0.05865**, 0.50830) | (0.79517, **0.10946**, 0.52089) |

성질:

- **무채색은 정확히 보존됩니다.** (0.5,0.5,0.5) 와 (1,1,1) 이 항등입니다.
- **순수 원색·검정도 사실상 항등**입니다(끝점에서 ±0.0001, float 반올림 수준).
- 차이는 **중간 채도**에서 벌어지고, 방향이 일정하지 않습니다 — (0.25,0.75,0.125) 에서는
  CIVibrance 가 G 를 더 밀고, (0.75,0.125,0.5) 에서는 G 를 더 내립니다. 단일 스케일
  보정으로 맞출 수 없다는 뜻입니다.
- 출력이 입력 범위를 살짝 벗어납니다(min −0.0001, max 1.0001). 클램프가 없습니다.

## 요청 B — 실제 프레임의 vibrance 전/후

`applyDensityEncoding` 직후(`frame4-preview-…`)와 `applyMutedSceneVibrance` 직후
(`frame4-postvib-…`)를 각각 320 폭 축소본으로 덤프했습니다. 축소 규칙은 2차 프록시와 같습니다
(폭 320 고정, 높이 비율, 상한 없음).

이 실행의 amount 는 **0.259** 입니다(`meanSat = 0.1538`).

| | R | G | B |
| --- | ---: | ---: | ---: |
| pre mean | 0.408421 | 0.443058 | 0.471108 |
| post mean | 0.388999 | 0.444527 | 0.489073 |
| Δ mean | **−0.019422** | +0.001470 | **+0.017965** |
| Δ min | −0.046387 | −0.025146 | −0.029053 |
| Δ max | +0.020020 | +0.015869 | +0.053223 |

가운데 채널이 거의 안 움직이고 R 이 내려가고 B 가 올라가는 양상이라, 그쪽이 관측한
"가운데 채널만 맞고 양끝이 두세 배 갈린다" 와 부호가 일치합니다.

## 요청 C — 채도 프록시 (160 × 244)

`sceneMeanSaturation` 이 재는 축소본입니다. 이 버퍼로 다시 계산한 평균 채도는
**0.153815** 로 Swift 로그의 `meanSat=0.1538` 과 같습니다.

알파: min 0.938965, `< 0.999` 비율 0.4098 %. 이 함수는 **inset 없이 전체 화소**를 쓰므로
2차 프록시와 달리 알파가 1 미만인 가장자리가 표본에 포함됩니다 — 대조할 때 이 점이
다릅니다.

## 재현

요청 A:

```bash
NEGAFLOW_VIBRANCE_GOLDEN_DIR=docs/verification/macos-golden/vibrance \
  swift test --filter VibranceMappingGoldenTests
```

요청 B·C:

```bash
NEGA_DEBUG=1 NEGA_DUMP_PROXY=1 negaflow develop GT-X900_frame_4.tiff /tmp/out.tif \
  --raw --look none --film-type colorNegative --target main
# /tmp/preview-320x488.f32, /tmp/postvib-320x488.f32, /tmp/satproxy-160x244.f32
```

두 환경변수 모두 opt-in 이라 평소 실행에는 영향이 없습니다.

## 이 실행의 로그

```
[nega-proxy] targetW=320 targetH=488 inset=(19,29) pixels=121260 film=121260
             gate=0.322839 darkCut=0.043237
             densest=(0.0637,0.0315,0.0250) densestFloor=(0.0637,0.0315,0.0250)
             measuredDmax=(0.7252,0.9690,0.9708)
[nega] dmin=(0.3381,0.2932,0.2334) dmaxNorm=(0.7252,0.9690,0.9708)
       blackIn=(0.1469,0.0927,0.0693) midD=0.626
[vib] meanSat=0.1538 amount=0.259
```

---

# REQUEST-4 추가분 (33³ · 65³ · 실사진 사다리)

규약은 3차와 같습니다 — 리틀엔디언 `Float32`, `RGBAf`, 행 우선(y-down), linear sRGB,
현상 파이프라인과 같은 컨텍스트(`SamplingContextPool`, workingColorSpace linearSRGB).

## 요청 A — 33³ 격자, amount 0.05…0.50

```
N = 33*33*33 = 35937,  이미지 256 × 141 = 36,096 화소, 앞 35,937 개가 격자
i → (R, G, B) = (i / 1089, (i / 33) % 33, i % 33) / 32,  alpha = 1
```

| 파일 | 크기 | sha256 |
| --- | ---: | --- |
| `civibrance33-a0.050-256x141.f32` | 577536 | `369642dc2cfd1c1b0aeca63fa3e13620274fd8732fffb089d8d3f188c0ac73ed` |
| `civibrance33-a0.100-256x141.f32` | 577536 | `84491e94010a22d4af01bb57f25170d2a45a65feb1d11def46eaf60b694d02b6` |
| `civibrance33-a0.150-256x141.f32` | 577536 | `7a1bce6fb84b11826296009dcdce038d066ae046b5e4cf27be8a198cb26bf124` |
| `civibrance33-a0.200-256x141.f32` | 577536 | `c0fc211feb7dafeec23f4c8eb6eb9edee7c50f6d3dddc8b67943ab5274233ecc` |
| `civibrance33-a0.250-256x141.f32` | 577536 | `61b49975722a206418b4ecfde13c92d322e9579001ceb9dd1f977950f51ee0fe` |
| `civibrance33-a0.300-256x141.f32` | 577536 | `61c19e43cc217674954ca4a0a6161afb43385c275621def71790840a39677898` |
| `civibrance33-a0.350-256x141.f32` | 577536 | `1280d9019b7024d314b0a316cd578bb13d896a58f69256a66e81c1653d28d160` |
| `civibrance33-a0.400-256x141.f32` | 577536 | `3a1942aa8d08b2f26da6d9a4cc7ef9eb4929362c047f3b774cbfd47d773fac18` |
| `civibrance33-a0.450-256x141.f32` | 577536 | `e8cc9046782f2bfb077969a30f7f16f2c009ca2cb0f134afbdf8ed3fb1a8c58d` |
| `civibrance33-a0.500-256x141.f32` | 577536 | `039f6cc299d8df76946c64c5bb91ec7d58fd47020bcaeb418655160edc4da44c` |
| `civibrance33-input-256x141.f32` | 577536 | `30498501656c7843eeb4e5ed5bf3045bbf5869a526758761709a310dabf82629` |

## 요청 B — 65³ 한 판 (독립 검증용)

```
N = 65*65*65 = 274625,  이미지 640 × 430 = 275,200 화소
i → (R, G, B) = (i / 4225, (i / 65) % 65, i % 65) / 64,  alpha = 1
```

| 파일 | 크기 | sha256 |
| --- | ---: | --- |
| `civibrance65-a0.250-640x430.f32` | 4403200 | `df7a8328ac5bad70baab3f99dceb35d26df94a16136769edd52772444aa25ecb` |
| `civibrance65-input-640x430.f32` | 4403200 | `6b57227acba448f117926c14ced3091c5239be123b289ee32d2e247721f8b5be` |

## 요청 C — 실제 프레임 한 쌍 더

**요청하신 형태로는 드릴 수 없습니다.** 8100 프레임은 vibrance 단계를 아예 건너뜁니다.

```
[nega-proxy] targetW=320 targetH=220 inset=(19,13) pixels=54708 film=54456
             gate=0.133005 darkCut=0.017813
             densest=(0.0005,0.0003,0.0003) densestFloor=(0.0030,0.0015,0.0011)
             measuredDmax=(1.8000,1.8000,1.8000)
[nega] dmin=(0.1913,0.0939,0.0711) dmaxNorm=(1.8000,1.8000,1.8000)
       blackIn=(0.1205,0.0697,0.0560) midD=0.482
[vib] meanSat=0.4099 amount=0.000
```

`meanSat 0.4099 > 0.24` 라 `amount = 0.000` 이고, `guard amount > 0.01` 에서 반환합니다.
그래서 전/후 두 덤프의 sha256 이 **같습니다**(`e99e5fe9…3ef3`). 게이트가 도는 것을 확인하는
자료로는 유효하지만, 표를 검증하는 자료로는 쓸 수 없습니다.

가진 스캔을 전부 재 봤는데 vibrance 가 실제로 도는 것은 `GT-X900_frame_4` 하나뿐입니다.

| 스캔 | meanSat | amount |
| --- | ---: | ---: |
| `GT-X900_frame_4` | 0.1538 | **0.259** |
| `OpticFilm8100_frame_1` | 0.4099 | 0.000 |
| `color_nega` | 0.3417 | 0.000 |
| `fa_2_colornegative_1slot` | 0.4032 | 0.000 |
| `fa_color_negative_2x2slot` | 0.2634 | 0.000 |

| 파일 | 크기 | sha256 |
| --- | ---: | --- |
| `frame8100-preview-320x220.f32` | 1,126,400 | `e99e5fe9c47f0cb9c129839dbd27f1a720e047500ed64b3f79ae5dde7cef3ef3` |
| `frame8100-postvib-320x220.f32` | 1,126,400 | `e99e5fe9c47f0cb9c129839dbd27f1a720e047500ed64b3f79ae5dde7cef3ef3` |

### 대신 드리는 것 — 같은 사진, amount 사다리

요청 C 의 목적은 "격자에 맞추고 사진에서 틀리는 것"을 잡는 것이었습니다. 그 목적은 사진이
달라야 달성되는 게 아니라 **맞출 때 쓰지 않은 자료**면 됩니다. `frame4-preview` 버퍼를
여러 amount 로 통과시킨 판을 드립니다 — 격자가 아니라 실제 화소 분포이고, 33³ 표를 맞출 때
쓰는 `a0.259` 한 판과 별개입니다.

| 파일 | 크기 | sha256 |
| --- | ---: | --- |
| `frame4-postvib-a0.050-320x488.f32` | 2,498,560 | `5671093fe2cb722e882b3c5a842c48824f1e115eec52aa0d190dc85e8c37cb82` |
| `frame4-postvib-a0.100-320x488.f32` | 2,498,560 | `6b957e28087c8ce38cf678ea321ad30f6c1836b9d9e80049e42f5836d90fbdfe` |
| `frame4-postvib-a0.150-320x488.f32` | 2,498,560 | `f1f67ed0638288e91c4b4e2e7a42a252e72984052456d6afa7640aa11519cc31` |
| `frame4-postvib-a0.250-320x488.f32` | 2,498,560 | `ce33a59b6de6056ce868bce9ae9c2dcfa2a0de5adca1802e1bebb917d806ac96` |
| `frame4-postvib-a0.350-320x488.f32` | 2,498,560 | `486c5610fbaf862271a95eddeaab96d8844cf2a9a6b585caee534ffb2358ba18` |
| `frame4-postvib-a0.500-320x488.f32` | 2,498,560 | `1fc1fdb1d8ea11a30130fd75e8f20ec6b7c8868e936797e5fe35bd88f2cbbd6b` |

입력은 전부 `frame4-preview-320x488.f32` 입니다.

## 그쪽 결론 1·2 를 새 격자로 재확인했습니다

`out = A + (in − A) · f`, `A = (R+G+B)/3` 로 화소마다 스칼라 `f` 하나를 맞춘 잔차입니다.

| 판 | 점 수 | 아핀 잔차 최대 | f 범위 |
| --- | ---: | ---: | --- |
| 33³ a0.05 | 35,937 | 1.25 × 10⁻⁶ | 1.0000 ~ 1.1251 |
| 33³ a0.25 | 35,937 | 6.14 × 10⁻⁶ | 1.0000 ~ 1.6195 |
| 33³ a0.50 | 35,937 | 1.23 × 10⁻⁵ | 1.0000 ~ 2.2239 |
| **65³ a0.25** | **274,625** | **6.26 × 10⁻⁶** | 1.0000 ~ 1.6288 |

274,625 점에서도 성립하므로 1·2번 결론은 17³ 우연이 아닙니다. `f ≥ 1` 이 항상 유지되는 것도
확인했습니다 — 이 필터는 채도를 낮추는 방향으로는 가지 않습니다.

## 재현

```bash
NEGAFLOW_VIBRANCE_GOLDEN_DIR=docs/verification/macos-golden/vibrance \
  swift test --filter VibranceMappingGoldenTests    # 17³ · 33³ · 65³
NEGAFLOW_VIBRANCE_GOLDEN_DIR=docs/verification/macos-golden/vibrance \
  swift test --filter VibranceRealFrameLadderTests  # 실사진 사다리
```
