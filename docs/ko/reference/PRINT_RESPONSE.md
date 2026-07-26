# 고정 인화 응답

[문서 홈](../README.md)

구현 위치:

- Swift: `Sources/Chromabase/Film/NegativeInversion.swift`의 `PrintResponse`
- Metal: `negativeInvert` 커널
- 고정 검사:
  `NegativeInversionCalibrationTests.testPrintResponseDerivesFromPhotometricContract`

## 곡선

필름의 특성곡선은 노출과 밀도의 관계를 검정점, 직선부, 숄더로 나눠 설명합니다.
negaflow는 밀도 영역의 숄더를 stretched exponential 곡선으로 근사합니다.

```math
\begin{aligned}
D &= \log_{10}\left(\frac{D_{\min}}{T}\right) \\
d &= \frac{D}{d_{\max}} \\
\log_{10}(P) &= y_{\mathrm{ceil}} - A \exp\left(-(r d)^s\right)
\end{aligned}
```

식의 `A`, `r`, `s`는 코드의 `amplitude`, `rate`, `shape`를 짧게 쓴 기호입니다.
`d_{\max}`는 `dmaxNorm`입니다.

- `D`: 필름 베이스를 뺀 광학 밀도
- `d`: 사용할 밀도 범위로 나눈 값
- `P`: 선형 출력 밝기

곡선은 전 구간에서 계속 증가합니다. `d ≥ 0`일 때 출력은 `[baseToe, ceiling)` 안에 있습니다.
베이스보다 밝은 백라이트나 퍼포레이션처럼 `d < 0`인 값도 0으로 잘라내지 않고 유한한 양수로
이어집니다.

```math
y(-|d|) = 2\log_{10}(P_{\mathrm{toe}}) - y(|d|)
```

역함수도 닫힌 식으로 구할 수 있습니다. 합성 네거티브를 만들고 왕복 검사할 때 씁니다.

```math
d = \frac{\left[\ln\left(\frac{A}{y_{\mathrm{ceil}}-\log_{10}(P)}\right)\right]^{1/s}}{r}
```

## 네 기준점

곡선 계수를 저장하지 않고 다음 값에서 계산합니다.

| 기준점 | 컬러 | 흑백 | 쓰임 |
|---|---:|---:|---|
| `P(0)` 베이스 검정점 | 0.001 | 0.0005 | 8-bit 코드 0에 붙지 않게 함 |
| `P(midFraction)` 중간 회색 | 0.18 | 0.18 | 18% 회색 |
| `P(1)` 흰색 | 0.70 | 0.85 | 측정한 최농부의 밝기 |
| `P(∞)` 천장 | 0.90 | 0.98 | 반사광 여유 |

`midFraction`은 `0.60D / 1.55D`, 약 `0.387`입니다.

계수 계산:

```math
\begin{aligned}
y_{\mathrm{ceil}} &= \log_{10}(P_{\mathrm{ceil}}) \\
A &= y_{\mathrm{ceil}} - \log_{10}(P_{\mathrm{toe}}) \\
r_X &= \ln\left(\frac{A}{y_{\mathrm{ceil}}-\log_{10}(X)}\right) \\
s &= \frac{\ln(r_{\mathrm{white}}/r_{\mathrm{mid}})}
          {\ln(1/f_{\mathrm{mid}})} \\
r &= r_{\mathrm{white}}^{1/s}
\end{aligned}
```

## 기본 밀도 범위

`normalRange`는 필름의 물리적 최대 밀도가 아니라 정상 노출 장면이 쓰는 범위입니다. 베이스를
측정하지 못했거나 장면 대비가 매우 낮을 때만 주로 영향을 줍니다.

```math
\begin{aligned}
\operatorname{normalRange}(\mathrm{color}) &= 0.62 \times 2.5 = 1.55\,D \\
\operatorname{normalRange}(\mathrm{B\&W}) &= 0.62 \times 3.5 = 2.17\,D
\end{aligned}
```

- `0.62`: C-41 특성곡선 직선부 기울기의 근삿값
- 컬러 `2.5`: 약 7⅓스탑의 확산 휘도 범위와 밝은 영역 여유
- 흑백 `3.5`: 더 긴 직선부를 쓰는 흑백 인화 관례
- `0.60D`: 정상 노출 장면의 중간 회색 밀도

`applySceneRanged`는 이 값 대신 프레임의 채널별 사용 밀도 범위를 잽니다.

## v4에서 바뀐 점

이전 방식은 세 구간으로 나뉜 함수와 고정 프리셋을 썼습니다. v4는 한 곡선과 네 기준점으로
바꿨습니다. 구간 경계가 없고 모든 값의 유도를 코드와 테스트에서 확인할 수 있습니다.

이전 결과와의 차이:

- 컬러 중간·밝은 영역, 정규화 밀도 0.3~1.1: ±0.05스탑 이내
- 컬러 깊은 어두운 영역, 0.1~0.2: 약 -0.2스탑
- 컬러 베이스 검정점: 약 +0.25스탑
- 흑백: 어두운 영역 약 -0.4스탑, 중간 영역 약 +0.1스탑
- NORITSU/FUJI의 중간 회색 0.18 기준점은 유지

## 참고 자료와 범위

검정점, 직선부, 숄더와 감마라는 틀은 공개된 사진 감광학에서 가져왔습니다. 이 문헌의 곡선
계수를 복사하지 않았습니다. negaflow의 계수는 위 네 기준점에서 따로 계산합니다.

- [Sensitometry](https://en.wikipedia.org/wiki/Sensitometry)
- [Hurter–Driffield Characteristic Curve](https://studyguides.com/study-methods/overview/cmpanf83znm1201neitjb4waw)
- [RA-4 용지 비교](https://tinker.koraks.nl/photography/on-a-color-mission-comparing-two-ra4-color-papers/)

RA-4 자료에 알려진 대비 범위를 직접 쓰지 않습니다. 현재 곡선의 대비는 네 기준점에서 나온
`shape`가 정합니다.
