# 코드와 리소스 출처

[문서 홈](../README.md)

이 문서는 negaflow 본체의 Apache-2.0 배포 범위를 기록합니다.
법률 의견서가 아니라, 현재 저장소와 출시 산출물을 다시 검사할 수 있게 만든 출처 기록입니다.

## 코드

`Sources`, `Tests`, `scripts`의 구현은 negaflow를 위해 작성한 Swift, Python, 셸 코드입니다.
본체에는 C/C++/Objective-C 소스, 외부 패키지, 정적·동적 라이브러리, vendored 소스 트리가
없습니다.
Apple이 macOS에서 제공하는 시스템 프레임워크만 링크합니다.

필름 반전은 공개된 사진 감광학의 밀도, 토우, 직선부, 숄더 개념을 사용합니다.
현재 구현의 곡선과 계수는 negaflow의 네 광도 기준점에서 유도하며 제3자 프로그램의 수식이나
상수를 복사하지 않습니다.
식과 유도 과정은 [고정 인화 응답](../reference/PRINT_RESPONSE.md)에 있습니다.

필름별 Dmin·Dmax 프리셋은 공개된 제3자 자료가 배포 상수로 들어오는 유일한 지점입니다.
이 수치는 제조사 데이터시트의 특성곡선에서 읽은 근사값이며, `FilmStockDmin`은 항목마다 출처를
`datasheetCurve` 또는 `estimated`로 표시해 그 사실을 드러냅니다.
공개 차트에서 읽은 수치는 필름의 사실이지 남의 코드나 문장을 복사한 것이 아니며, 스캔에서
실측한 필름 베이스가 있으면 언제나 실측이 우선합니다.

GrainMend IR은 다음 순서로 작동합니다.

1. RGB와 IR의 정수 오프셋을 독립적으로 추정합니다.
2. `log(red)` 구간별 IR 절사 평균을 보간해 비모수 장면 누설 곡선을 만듭니다.
3. 장면 누설을 뺀 뒤 국소 평균에 대한 상대 대비를 계산합니다.
4. 절사한 국소 노이즈 기준, 연결요소, 방향 분류로 결함 마스크를 만듭니다.

이 구현은 SANE의 IR 보정 코드를 링크하거나 이식하지 않습니다.
공개 문헌과 제품 설명은 필름과 적외선의 물리적 한계를 확인하는 배경 자료로만 사용합니다.
방법과 원리를 참고하는 것과 코드 표현을 복사하는 것은 구분합니다.
미국 저작권청도 방법·시스템과 그 구체적 표현을 구분해 설명합니다.

- [U.S. Copyright Office Circular 33](https://www.copyright.gov/circs/circ33.pdf)
- [SANE backends source repository](https://gitlab.com/sane-project/backends)

## SANE 플러그인 경계

negaflow 본체에는 `scanimage`, SANE 헤더, 백엔드 설정, 장치별 처리 코드가 없습니다.
본체는 설치된 외부 프로그램과 버전이 있는 JSON/NDJSON 계약으로만 통신합니다.
실제 SANE 구현은 별도 GPL-2.0-or-later 저장소와 실행파일로 배포합니다.

별도 프로세스라는 사실만으로 라이선스 결론을 자동으로 내리지 않습니다.
GNU FAQ도 파이프나 명령행 통신은 보통 별도 프로그램의 형태지만 통신 의미가 지나치게 밀접하면
판단이 달라질 수 있다고 설명합니다.
그래서 본체 계약은 장치와 무관한 요청, 기능, 진행, 결과 파일 정보만 교환하며 SANE 내부
자료구조를 공유하지 않습니다.

- [GNU license FAQ: aggregates and separate programs](https://www.gnu.org/licenses/gpl-faq.en.html)
- [Apache License 2.0 and GPL compatibility](https://www.apache.org/licenses/GPL-compatibility)
- [스캐너 플러그인 구조](../architecture/SCANNER_PLUGINS.md)

출시 검사는 본체 앱 번들에 플러그인, SANE 실행파일, 라이브러리가 들어가지 않았는지 다시
확인합니다.
플러그인 쪽은 자체 `LICENSE`, `COPYING`, 완전한 대응 소스와 제3자 고지를 별도로 제공합니다.

## 번들 리소스

[`Config/bundled-resource-provenance-v1.json`](../../../Config/bundled-resource-provenance-v1.json)
은 앱과 소스 트리에 들어가는 리소스의 선언된 출처, 라이선스, SHA-256을 고정합니다.

| 묶음 | 출처 | 배포 내용 |
|---|---|---|
| ScannerKit TIFF | 유지관리자가 촬영·정리한 레이아웃 자료 | 4개 TIFF |
| 앱 아이콘 | 유지관리자가 제공한 프로젝트 아트워크 | 원본 PNG, 빌드용 PNG, ICNS |
| 룩 프리셋 | negaflow용으로 작성한 값 | 6개 JSON |
| 스캐너 프로파일 | 유지관리자가 관리하는 스캔 측정에서 생성 | 원본 스캔을 제외한 수치 프로파일 |

TIFF에 보이는 카메라와 색공간 메타데이터는 촬영·인코딩 과정의 컨테이너 정보입니다.
스캐너 프로파일의 `sourceProfiles`는 생성 당시 로컬 측정 자료의 논리 경로이며 그 원본 사진은
배포하지 않습니다.

FILM-R v2 자료는 품질 측정 때만 내려받습니다. 이미지 자체는 저장소나 앱에 넣지 않습니다.
DOI 버전, CC BY 4.0, 파일 크기와 해시는
[`Config/defect-corpus-film-r-v2.json`](../../../Config/defect-corpus-film-r-v2.json)에
고정합니다.

## 이름과 상호운용 정보

필름, 스캐너, 색공간, XMP namespace와 제품 이름은 대상 식별과 파일 상호운용을 위해 씁니다.
상표 소유권이나 제휴를 주장하지 않습니다.
자세한 범위는 [`TRADEMARKS.md`](../../../TRADEMARKS.md)에 있습니다.

## 자동 검사와 한계

`python3 scripts/ci/verify-provenance.py`는 다음을 실패 조건으로 둡니다.

- 등록되지 않았거나 해시가 달라진 번들 리소스
- 본체에 들어온 C/C++/Objective-C, 외부 패키지, 바이너리 아카이브, vendor 트리
- 본체 구현에 들어온 SANE 전용 이름이나 확인 대상 외부 구현 표식
- 출시 스크립트가 SANE 플러그인을 앱에 포함하는 변경
- 저장소에 들어온 FILM-R 이미지 자료

이 검사는 현재 트리의 명백한 회귀를 막습니다.
인터넷 전체와의 유사성, 사진·프로파일 입력의 권리, 특허, 상표, 국가별 법률 판단까지 자동으로
증명하지는 않습니다.
출처가 바뀌면 선언과 해시를 함께 검토하고, 불명확하면 해당 리소스를 배포에서 제외한 뒤 권리자나
전문가에게 확인해야 합니다.
