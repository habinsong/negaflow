# ADR-0021: macOS golden은 관측 기록이며 Core Image 재현물이 아니다

- 상태: 채택
- 날짜: 2026-08-06

## 문제

`tests/fixtures/v1/film_emulation_core_image_golden_fixture.h`는 macOS에서 Apple Core Image를 실제로
실행해 얻은 float 값을 Windows 구현의 허용오차 기준으로 사용합니다. 저장소의 다른 모든 수치는 이
프로젝트가 소유한 Swift source에서 왔지만, 이 fixture만은 제3자 독점 구현의 동작을 관측한 결과입니다.

지금까지 이 경계는 `docs/research/film-emulation-color-sources.md`에 산문으로만 적혀 있었습니다.
golden이 커지거나 허용오차가 좁아질 때 무엇이 선을 넘는 것인지 판단할 기준이 없으면, 개별 커밋마다
합리적으로 보이는 변경이 누적돼 결과적으로 Apple 필터의 대체 LUT를 만들게 됩니다. 그 지점을 미리
고정합니다.

## 관측된 값의 정확한 범위

현재 fixture에 들어 있는 Apple 관측 수치는 다음뿐입니다.

| 항목 | 수량 | 내용 |
|---|---:|---|
| 색상 cube 출력 | float 36개 | opaque RGB 12쌍 |
| acutance 출력 | float 216개 | 6개 case × 중심 9 표본 × RGBA |
| 합계 | **float 252개** | |

같은 파일의 `film_emulation_acutance_profile_signatures` 12행(radius·intensity)은 Apple 관측이
**아니라** 이 저장소의 Apache-2.0 Swift source에서 온 값입니다. 혼동하지 않도록 구분합니다.

입력 패턴(`neutral_impulse`, `saturated_step`)은 이 저장소가 만든 합성 이미지입니다. Apple의 sample
image, test asset이나 문서 예제를 입력으로 쓰지 않았습니다.

허용오차는 색상 `2.1e-3`, acutance `4.0e-4`입니다. bit-exact 일치가 아니라 **결과가 비슷한 범위에
있음**을 확인하는 값입니다.

## 결정

1. 이 fixture는 **test-only**입니다. `Negaflow.Native.dll`, `negaflow-cli.exe`, 셸 어느 배포물에도
   포함되지 않습니다. 제품은 이 수치를 실행 시점에 참조하지 않습니다.
2. 저장 대상은 **동작 관측값**으로 한정합니다. Apple의 코드, 헤더, sample code, 문서 문장, 알고리즘
   기술, kernel tap, radius→sigma 변환식은 어떤 형태로도 옮기지 않습니다.
3. Windows 구현은 관측값에서 역산하지 않고 **공개된 표준 수학으로 독립 작성**합니다. golden은 작성이
   끝난 뒤 결과를 비교하는 용도로만 씁니다. 구현이 막혔을 때 golden을 늘려 맞추는 방식은 금지합니다.
4. **크기 상한을 둡니다.** Apple 관측 float 총량은 512개를 넘기지 않습니다. 이 상한을 넘겨야 할
   이유가 생기면 그 자체를 별도 ADR로 다시 판단합니다. cube 격자를 조밀하게 sampling해 Apple 필터의
   입출력 표를 만드는 방향은 채택하지 않습니다.
5. **허용오차를 bit-exact로 좁히지 않습니다.** 현재 수준(1e-3~1e-4대)은 독립 구현의 근사 확인이지만,
   exact 일치를 목표로 삼는 순간 성격이 "관측"에서 "복제"로 바뀝니다. 좁히려면 재검토가 필요합니다.
6. 제품 문서와 마케팅에서 **Core Image 호환·동등을 주장하지 않습니다**. `docs/`의 기존 표현("ColorSync
   수치 동등성과 구분한다")을 유지합니다.
7. golden을 갱신할 때는 생성에 쓴 macOS 버전, runner commit, baseline commit을 fixture 안에 계속
   기록합니다. 현재 값은 macOS 26.5.2 (25F84), baseline `2fa1d62`, runner `6d9994f`입니다.

## 근거

- 저작권은 표현을 보호하며, 결정론적 함수에 임의 입력을 넣어 얻은 수치는 사실 기록에 가깝습니다.
  252개 float에는 Apple의 창작적 선택이 담겨 있지 않고, 선택한 입력은 이 저장소가 정했습니다.
- 목적이 상호 운용성 확인이고, 결과물이 Apple 구현을 대체하지 못합니다. 표본이 성기고 허용오차가
  넓어 이 표로는 Core Image 필터를 재구성할 수 없습니다.
- macOS SDK를 사용해 앱을 개발하고 그 출력을 관찰하는 것은 프레임워크의 통상적 사용입니다. 우회한
  기술적 보호 조치가 없고, 디컴파일이나 바이너리 분석을 하지 않았습니다.
- 값은 제품이 아니라 테스트에만 존재하므로 배포물에 Apple 유래 자산이 실리지 않습니다.

## 결과

Windows 구현이 macOS 제품과 시각적으로 어긋나지 않는지 자동으로 확인할 수 있으면서, 관측이 복제로
넘어가는 경계가 수치로 고정됩니다. 상한과 허용오차 조항이 있으므로 이후 커밋이 선을 넘으면 리뷰에서
바로 드러납니다.

## 검증 한계

이 문서는 기술적 판단이며 법률 자문이 아닙니다. Apple의 라이선스 해석이나 관할별 판단을 대신하지
않습니다. 상용 배포를 앞두고는 이 ADR과 `docs/research/film-emulation-color-sources.md`,
`film-emulation-acutance-sources.md`를 함께 전문가 검토에 넘기는 것을 전제로 합니다.
