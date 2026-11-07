# GrainMend IR이 피해야 할 필름

[문서 홈](../README.md)

적외선 청소는 가시광 이미지와 적외선 이미지를 따로 읽어 겹쳐서 결함을 찾습니다. 모든 필름에 맞지는 않습니다.

- 일반 컬러 필름과 염료 기반 흑백 필름은 IR을 쓸 수 있습니다.
- 일반 흑백 필름은 은이 남아 IR을 막으므로 결함 지도가 틀릴 수 있습니다.
- 코다크롬은 다른 컬러 필름과 IR 감쇠가 달라 보정이 모자라거나 넘칠 수 있습니다.

근거:

- [Epson technical notes and limits](https://files.support.epson.com/pdf/pr48pr/pr48prps.pdf)
- [Epson film type table](https://files.support.epson.com/htmldocs/pr449p/pr449pug/projs_3.htm)
- [SilverFast on black and white and Kodachrome](https://www.silverfast.com/showdocu/en.html?direct=1&docu=1300)

> [!CAUTION]
> 필름 재질을 확인할 수 없으면 IR을 자동으로 적용하지 않습니다. 잘못된 IR 마스크는 실제 화면 구조를 결함으로 알고 지울 수 있습니다.

## 자동으로 적용되는 곳

기준은 상을 이루는 물질입니다. 컬러 필름은 현상 뒤 염료만 남고 염료는 적외선을 통과시킵니다. 흑백 필름은 은으로 된 상이라 적외선을 막으므로, 보정이 사진 자체를 큰 결함 하나로 읽어 지워 버립니다.

| 필름 종류 | 자동 IR | 이유 |
|---|---|---|
| 컬러 네거티브 | 조건부 | 염료 상. 플러그인이 IR을 보고하고 정렬 검사를 통과해야 함 |
| 컬러 포지티브 | 조건부 | 염료 상. 컬러 네거티브와 같은 조건 |
| 흑백 네거티브·포지티브 | 꺼짐 | 은 상이 적외선을 막음 |

`FilmType`은 염료 기반 흑백과 은 흑백을, 코다크롬과 일반 슬라이드를 구분하지 못합니다. 두 경우는 사용자에게 맡깁니다.

- 염료 기반 흑백은 흑백으로 스캔하므로 필름이 허락해도 IR이 꺼져 있습니다. 필름 종류만 보고 추측하지 않습니다.
- 코다크롬은 컬러 슬라이드라 IR을 제안합니다. 염료의 적외선 감쇠가 E-6과 달라 결함이 덜 지워지거나 더 지워질 수 있습니다. 결과가 이상하면 레이어를 끄세요.

## 정렬 검사

`InfraredDefectRemoval`은 IR의 누설 질감을 RGB의 빨강 채널과 비교해 정수 오프셋을 찾습니다. 결과에는 `AlignmentDiagnostics`가 붙습니다.

| 상태 | 뜻 |
|---|---|
| `notRequested` | 호출한 쪽이 두 평면이 이미 맞는다고 알림 |
| `aligned` | 상관이 기준을 넘고 최적점이 탐색 범위 안에 있음 |
| `insufficientTexture` | IR에 정렬 단서가 너무 적음 |
| `weakCorrelation` | 상관이 기준에 못 미침 |
| `searchLimitReached` | 최적점이 탐색 경계에 있음 |

뒤의 셋은 `alignmentUnreliable` 오류로 멈추며 `(0,0)`으로 대신하지 않습니다. 최적점이 탐색 경계에 닿으면 오프셋 크기와 상관없이 실패입니다.

자동 테스트는 실제 장치와 필름별 RGB/IR 정렬 확인을 대신하지 못합니다. 그 확인은 실제 필름으로 손으로 합니다.

SANE 장치 제어와 캡처 코드는 별도 저장소 `negaflow-scanner-sane`에만 있습니다.
