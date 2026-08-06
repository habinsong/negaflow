# Windows ICM 실측과 ColorSync 대조

기준일: 2026-08-06
대상 fixture: `colorsync-icm-parity-v1`
macOS 기준값: `baseline/colorsync-icm-parity-v1.json` (macOS 26.5.0)
Windows 실측값: `baseline/colorsync-icm-parity-windows-v1.json`

## 측정 환경

- Windows 11 Pro 10.0.26200, x64 Release
- Windows ICM(`mscms`) `CreateMultiProfileTransform`, `BEST_MODE`,
  `INTENT_RELATIVE_COLORIMETRIC`, black point compensation 없음
- 경로: 합성 프로파일 → `IcmRgb16Transform` → 16비트 sRGB 정수 →
  `srgb_encoded_to_linear` → linear float. 제품의 `scanner_to_working` 과 같은 순서입니다.
- 프로브: `tests/Native.UnitTests/colorsync_icm_parity_tests.cpp`

## 전제 조건 통과

`docs/research/colorsync-icm-parity-profile.md` 의 규칙만 보고 C++ 로 프로파일을 독립
재구현했고, 556바이트의 SHA-256 이 macOS 가 기록한
`8c2dce29801bda9b1f532b3236f61f91171267ad8bbc997d46fb662cf9125d02` 과 일치했습니다.

두 CMS 가 같은 바이트를 읽는다는 것이 확인됐으므로 아래 차이는 프로파일 차이가 아니라 CMS 차이입니다.
이 해시가 어긋나면 프로브는 비교를 수행하지 않고 실패합니다.

## 결과

중립 패치의 R 채널 기준입니다.

| src (u16) | 입력 | macOS ColorSync | Windows ICM | macOS/Windows |
|---:|---:|---:|---:|---:|
| 0 | 0.000 | 0 | 0 | — |
| 328 | 0.005 | 3.1281e-04 | 1.5354e-05 | **20.37×** |
| 655 | 0.010 | 6.2467e-04 | 4.6061e-05 | **13.56×** |
| 1311 | 0.020 | 1.2503e-03 | 1.8779e-04 | **6.66×** |
| 3277 | 0.050 | 3.1252e-03 | 1.3854e-03 | **2.26×** |
| 4915 | 0.075 | 4.6874e-03 | 3.3453e-03 | 1.40× |
| 8192 | 0.125 | 1.0309e-02 | 1.0284e-02 | 1.002× |
| 16384 이상 | ≥0.25 | — | — | 1.000× |

34개 패치 중 21개가 비율 1.000 이며 최대 편차는 0.04% 입니다. 중간톤, 하이라이트, 6개 프라이머리,
스킨톤은 사실상 동일합니다. **차이는 전부 깊은 섀도우 한 구간에 몰려 있습니다.**

## 원인

두 CMS 가 같은 감마 곡선(`2.19921875`)을 다르게 처리합니다.

- **Windows ICM** 은 사양대로 거듭제곱을 적용합니다. `src ≥ 1311` 에서 순수 거듭제곱 대비 1.02배
  이내입니다.
- **macOS ColorSync** 는 device 값 약 `0.0991` 아래에서 곡선을 기울기 `1/16` 인 직선으로 대체합니다.
  측정값은 그 구간에서 정확히 `x/16` 이며 상대오차가 1e-8 수준입니다. 연속성 breakpoint 는
  `(1/16)^(1/(γ-1)) = 0.09906` 이고 macOS 기준값이 기록한
  `analyticMaxAbsDeviation = 0.0017486` 은 `x=0.05` 에서의 `x/16 - x^γ` 와 소수점 7자리까지
  일치합니다.

역 TRC 의 최대 게인을 16:1 로 제한하는 처리이며, 섀도우 노이즈 증폭을 막는 CMM 설계 선택으로
보입니다. **ICM 이 틀린 것이 아니라 ColorSync 가 사양에서 벗어나 있는 쪽입니다.**

`src = 328` 에서 ICM 자체도 순수 거듭제곱보다 1.76배 높습니다. 이는 toe 클램프가 아니라 그 크기에서의
내부 정밀도 한계이며, `src = 655` 에서 1.15배, `src ≥ 1311` 에서 1.02배 이내로 사라집니다. 그래서 실제
격차가 순수 거듭제곱 기준의 산술 예측(36배)보다 작은 20.37배입니다.

## 결론이 바꾸는 것

**LittleCMS 로 교체하는 경로는 이 문제를 해결하지 못합니다.** LittleCMS 는 ICC 사양을 구현하므로 ICM 과
같은 거듭제곱 결과를 냅니다. 차이의 원인이 "Windows 쪽 CMS 선택"이 아니라 "ColorSync 의 비표준
처리"이므로, Windows 에서 CMS 를 바꾸는 것으로는 macOS 와 같아지지 않습니다.

`progress/overall-roadmap.md` 의 "차이가 허용 범위를 넘을 때만 LittleCMS 를 dependency gate 에
올린다" 항목은 이 문제에 대해서는 더 이상 유효한 해법이 아닙니다. ADR-0004 의 OS 우선 결정과
제3자 runtime dependency 0개는 이 사안 때문에 흔들리지 않습니다.

남은 선택은 CMS 교체가 아니라 다음 둘입니다.

1. ColorSync 의 toe 처리를 Windows 에서 재현해 macOS 와 같은 그림을 만든다.
2. 사양대로 두고 플랫폼 차이로 문서화한다.

이것은 엔지니어링 판단이 아니라 제품 판단입니다.

## 왜 무시할 수 없는 구간인가

발산 구간(`src < 8192`)은 컬러 네거티브의 고밀도부가 실제로 놓이는 곳입니다. 일반적인 컬러 네거티브의
최대 밀도는 base 대비 2.5~3.0 이고 투과율로는 0.1~0.3%, 즉 `src` 로 65~200 근방입니다. 20배 발산
구간보다 더 깊습니다. 그리고 네거티브에서 고밀도부는 반전 후 장면의 하이라이트가 됩니다.

즉 이 차이는 코너 케이스가 아니라 제품의 핵심 동작 구간에 있습니다.

## 아직 답하지 않은 것

**최종 이미지에 얼마나 남는지는 측정하지 않았습니다.** 입력단의 20배가 Dmin 차감, 네거티브 반전,
톤 매핑을 거친 뒤 출력 픽셀에서 얼마가 되는지는 별도 측정이 필요합니다. 증폭될 수도 압축될 수도
있습니다. 그 숫자 없이 위 1번과 2번을 고르는 것은 근거 없는 결정입니다.

이 문서는 판정이 아니라 관측 기록입니다.

## 재현

```
py Negaflow.Windows/scripts/generate_colorsync_parity_fixture.py
cmake --preset x64-release
cmake --build --preset x64-release --target negaflow_colorsync_icm_parity_tests
set NEGAFLOW_ICM_PARITY_OUTPUT=<경로>
out\build\native\x64-release\Release\negaflow_colorsync_icm_parity_tests.exe
```

환경변수 없이 실행하면 표만 출력하고 baseline 을 다시 쓰지 않습니다.
`ctest --preset x64-release -R colorsync_icm_parity` 로도 실행됩니다.
