# GrainMend IR이 피해야 할 필름

[문서 홈](../README.md)

적외선 청소는 가시광 이미지와 적외선 이미지를 따로 읽은 뒤 겹쳐서 결함을 찾습니다.
모든 필름에 맞는 방식은 아닙니다.

- 일반 컬러 필름과 염료 방식의 흑백 필름은 IR을 쓸 수 있습니다.
- 은이 남는 일반 흑백 필름은 IR을 막아 결함 지도가 잘못될 수 있습니다.
- Kodachrome은 다른 컬러 필름과 IR 감쇠가 달라 과소·과대 보정될 수 있습니다.

근거:

- [Epson 기술 설명과 제한](https://files.support.epson.com/pdf/pr48pr/pr48prps.pdf)
- [Epson 필름 종류 표](https://files.support.epson.com/htmldocs/pr449p/pr449pug/projs_3.htm)
- [SilverFast의 흑백·Kodachrome 설명](https://www.silverfast.com/showdocu/en.html?direct=1&docu=1300)

> [!CAUTION]
> 필름 재질을 확인할 수 없으면 IR을 자동 적용하지 않습니다. 잘못된 IR 마스크는 실제 이미지
> 구조를 결함으로 지울 수 있습니다.

## 자동 적용 범위

현재 `FilmType`은 컬러/흑백과 네거티브/포지티브만 구분합니다.
염료식 흑백과 은염 흑백, 일반 슬라이드와 Kodachrome을 가를 정보는 없습니다.

| 필름 종류 | 자동 IR | 이유 |
|---|---|---|
| 컬러 네거티브 | 조건부 사용 | 플러그인이 IR을 보고하고 정렬 검사를 통과해야 함 |
| 컬러 포지티브 | 사용 안 함 | Kodachrome 여부를 알 수 없음 |
| 흑백 네거티브·포지티브 | 사용 안 함 | 염료식과 은염을 구분할 수 없음 |

염료식 흑백이나 일반 컬러 슬라이드에 IR을 절대 쓸 수 없다는 뜻은 아닙니다.
현재 자료만으로 필름 재질을 확인할 수 없어 자동으로 짐작하지 않는 것입니다.

## 정렬 검사

`InfraredDefectRemoval`은 IR의 누설 질감과 RGB 적색 채널의 상관을 비교해 정수 오프셋을 찾습니다.
결과에는 `AlignmentDiagnostics`를 남깁니다.

| 상태 | 뜻 |
|---|---|
| `notRequested` | 호출자가 두 평면이 이미 맞는다고 지정함 |
| `aligned` | 상관 기준을 넘고 최적점이 검색 범위 안에 있음 |
| `insufficientTexture` | IR에 정렬 단서가 부족함 |
| `weakCorrelation` | 상관 기준을 넘지 못함 |
| `searchLimitReached` | 최적점이 검색 경계에 걸림 |

마지막 세 상태는 `(0,0)`으로 대신하지 않습니다. `alignmentUnreliable` 오류로 중단합니다.
검색 경계에 걸렸다면 오프셋의 크기와 상관없이 실패로 처리합니다.

자동 테스트는 실제 장치의 RGB/IR 정렬과 필름별 결과를 대신하지 못합니다.
실제 스캐너 확인은 [출시 전 실기기 점검표](../validation/REAL_QA_CHECKLIST.md) 의 IR 항목을
따릅니다.

SANE 장치 제어와 캡처 코드는 별도 저장소 `negaflow-scanner-sane`에만 둡니다.
