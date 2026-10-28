# 코드와 리소스 출처

[문서 홈](../README.md)

이 문서는 negaflow 본체의 Apache-2.0 배포 범위를 기록합니다. 저장소와 출시 산출물을 다시 검사할 수 있게 정리한 출처 기록이며, 법률 자문이나 의견서가 아닙니다.

## 코드

`negaflow-mac`의 Swift·Python·셸 연동 코드는 negaflow에서 작성했습니다. 음화 카메라 RAW 디코드는 고정 LibRaw 리비전을 교체 가능한 `libraw.dylib`로 사용하며 CDDL-1.0로 배포합니다. 두 플랫폼 모두 LibRaw 파일 두 개를 수정합니다. `src/demosaic/xtrans_demosaic.cpp`는 Fuji X-Trans 타일을 원래 순서대로 두고 타일 안의 행만 병렬로 처리합니다. `src/postprocessing/mem_image.cpp`는 출력 비트맵의 행을 병렬로 복사합니다. 패치는 [`xtrans-parallel-rows.patch`](../../../negaflow-mac/scripts/libraw/xtrans-parallel-rows.patch)와 [`mem-image-parallel-rows.patch`](../../../negaflow-mac/scripts/libraw/mem-image-parallel-rows.patch)입니다. 시험한 RAW 파일에서 패치 빌드는 수정 전 직렬 빌드와 픽셀이 일치했습니다. 이전 병렬 X-Trans 빌드는 실행마다 픽셀이 달라질 수 있었습니다. macOS에서는 LLVM OpenMP 런타임(libomp 20.1.8, Apache License v2.0 with LLVM Exceptions)을 라이브러리 안에 정적으로 링크합니다. 앱의 `Contents/Resources/licenses/libraw/`에 소스 아카이브, 패치, 빌드 스크립트, 저작권·라이선스 파일을 넣습니다. Apache 소스 트리에 LibRaw 소스를 병합하지 않습니다. Windows도 같은 패치와 업스트림 리비전을 사용하며 다른 구성 요소는 [`negaflow-windows/THIRD-PARTY-NOTICES.md`](../../../negaflow-windows/THIRD-PARTY-NOTICES.md)에 기록합니다. 시험용 `CameraNativeRaw.dng`는 raw.pixls.us 항목 2204의 CC0-1.0 자료입니다. 출처 JSON을 함께 두고 앱에서는 제외합니다.

추가 고지 파일이 없으면 경고를 남기고 빌드와 패키징을 계속합니다. 업스트림 라이선스와 대응 소스는 함께 둡니다.

필름 반전은 공개된 사진 감광학의 밀도, 토우, 직선부, 숄더 개념을 사용합니다. 현재 구현의 곡선과 계수는 negaflow의 네 광도 기준점에서 유도하며 제3자 프로그램의 수식이나 상수를 복사하지 않습니다. 식과 유도 과정은 [고정 인화 응답](../reference/PRINT_RESPONSE.md)에 있습니다.

공개된 제조사 기술 데이터시트는 세 가지 필름 상수 묶음에 쓰입니다. 필름별 Dmin·Dmax 프리셋(`FilmStockDmin`), 흑백 분광 감도와 특성곡선 프리셋(`BWFilmProfile`), 입자와 MTF 물리 파라미터(`DigitalFilmPhysics`)가 여기에 해당합니다. 이 수치는 공개 기술 자료의 차트에서 읽거나 근사한 값이며 `FilmStockDmin`은 항목마다 출처를 `datasheetCurve` 또는 `estimated`로 표시해 그 사실을 드러냅니다. 공개 차트에서 읽은 수치는 필름의 사실이지 남의 코드나 문장을 복사한 것이 아니며 스캔에서 실측한 필름 베이스가 있으면 언제나 실측이 우선합니다.

GrainMend IR은 다음 순서로 작동합니다.

1. RGB와 IR의 정수 오프셋을 독립적으로 추정합니다.
2. `log(red)` 구간별 IR 절사 평균을 보간해 비모수 장면 누설 곡선을 만듭니다.
3. 장면 누설을 뺀 뒤 국소 평균에 대한 상대 대비를 계산합니다.
4. 절사한 국소 노이즈 기준, 연결요소, 방향 분류로 결함 마스크를 만듭니다.

이 구현은 SANE의 IR 보정 코드를 링크하거나 이식하지 않습니다. 공개 문헌과 제품 설명은 필름과 적외선의 물리적 한계를 확인하는 배경 자료로만 사용합니다. 방법과 원리를 참고하는 것과 코드 표현을 복사하는 것은 구분합니다. 미국 저작권청도 방법·시스템과 그 구체적 표현을 구분해 설명합니다.

- [U.S. Copyright Office Circular 33](https://www.copyright.gov/circs/circ33.pdf)
- [SANE backends source repository](https://gitlab.com/sane-project/backends)

## SANE 플러그인 경계

negaflow 본체에는 `scanimage`, SANE 헤더, 백엔드 설정, 장치별 처리 코드가 없습니다. 본체는 설치된 외부 프로그램과 버전이 있는 JSON/NDJSON 계약으로만 통신합니다. 실제 SANE 구현은 별도 GPL-2.0-or-later 저장소와 실행파일로 배포합니다.

별도 프로세스라는 사실만으로 라이선스 결론을 자동으로 내리지 않습니다. GNU FAQ도 파이프나 명령행 통신은 보통 별도 프로그램의 형태지만 통신 의미가 지나치게 밀접하면 판단이 달라질 수 있다고 설명합니다. 그래서 본체 계약은 장치와 무관한 요청, 기능, 진행, 결과 파일 정보만 교환하며 SANE 내부 자료구조를 공유하지 않습니다.

- [GNU license FAQ: aggregates and separate programs](https://www.gnu.org/licenses/gpl-faq.en.html)
- [Apache License 2.0 and GPL compatibility](https://www.apache.org/licenses/GPL-compatibility)
- [스캐너 플러그인 구조](../architecture/SCANNER_PLUGINS.md)

출시 검사는 본체 앱 번들에 플러그인, SANE 실행파일, SANE 라이브러리가 들어가지 않았는지 다시 확인합니다. 플러그인 쪽은 자체 `LICENSE`, `COPYING`, 완전한 대응 소스와 제3자 고지를 별도로 제공합니다.

## 번들 리소스

[`Config/bundled-resource-provenance-v1.json`](../../../negaflow-mac/Config/bundled-resource-provenance-v1.json) 은 앱과 소스 트리에 들어가는 리소스의 선언된 출처, 라이선스, SHA-256을 고정합니다.

| 묶음 | 출처 | 배포 내용 |
|---|---|---|
| ScannerKit TIFF | 유지관리자가 촬영·정리한 레이아웃 자료 | 4개 TIFF |
| 앱 아이콘 | 유지관리자가 제공한 프로젝트 아트워크 | 원본 PNG, 빌드용 PNG, ICNS |
| 룩 프리셋 | negaflow용으로 작성한 값 | 6개 JSON |
| 스캐너 프로파일 | 유지관리자가 관리하는 스캔 측정에서 생성 | 원본 스캔을 제외한 수치 프로파일 |

TIFF에 보이는 카메라와 색공간 메타데이터는 촬영·인코딩 과정의 컨테이너 정보입니다. 스캐너 프로파일의 `sourceProfiles`는 생성 당시 로컬 측정 자료의 논리 경로이며 그 원본 사진은 배포하지 않습니다.

FILM-R v2 자료는 품질 측정 때만 내려받습니다. 이미지 자체는 저장소나 앱에 넣지 않습니다. DOI 버전, CC BY 4.0, 파일 크기와 해시는 [`Config/defect-corpus-film-r-v2.json`](../../../negaflow-mac/Config/defect-corpus-film-r-v2.json)에 고정합니다.

## DNG 내보내기

DNG 기록기(`negaflow-mac`의 `DNGLinearWriter`, `negaflow-windows`의 `dng_linear_export`)는 Adobe가 공개한 Digital Negative Specification 1.6의 태그 번호와 색 모델만 보고 새로 작성했습니다. Adobe DNG SDK 코드와 LibRaw 등 다른 DNG 기록기의 코드는 들어 있지 않습니다. 색 행렬은 sRGB, Display P3, Adobe RGB (1998)의 공개된 색도 좌표에서 계산합니다. Adobe는 DNG 파일을 읽고 쓰는 소프트웨어에 로열티 없는 특허 라이선스를 제공하며, 이 제품은 그 라이선스를 씁니다. 라이선스가 아래 고지를 요구합니다.

This product includes DNG technology under license by Adobe.

DNG는 Adobe Inc.의 상표입니다. 이 이름은 파일 형식을 가리키는 데만 씁니다.

## 이름과 상호운용 정보

필름, 스캐너, 색공간, XMP namespace와 제품 이름은 대상 식별과 파일 상호운용을 위해 씁니다. Windows 엔진이 합성하는 출력 ICC 프로파일은 설명용 이름(`"Negaflow Compatible P3"`, `"Compatible with Adobe RGB (1998)"`)과 `CC0 1.0 Universal` 권리 포기 문구를 기록해 내보낸 사용자 이미지에 프로파일 저작권 제약이 남지 않게 합니다. 상표 소유권이나 제휴를 주장하지 않습니다. 자세한 범위는 [`TRADEMARKS.md`](../../../TRADEMARKS.md)에 있습니다.

## 자동 검사와 한계

`python3 scripts/ci/verify-provenance.py`는 다음을 실패 조건으로 둡니다.

- 등록되지 않았거나 해시가 달라진 번들 리소스
- 본체에 들어온 C/C++/Objective-C, 외부 패키지, 바이너리 아카이브, vendor 트리
- 본체 구현에 들어온 SANE 전용 이름이나 확인 대상 외부 구현 표식
- 출시 스크립트가 SANE 플러그인을 앱에 포함하는 변경
- 저장소에 들어온 FILM-R 이미지 자료

이 검사는 현재 트리의 명백한 회귀를 막습니다. 인터넷 전체와의 유사성, 사진·프로파일 입력의 권리, 특허, 상표, 국가별 법률 판단까지 자동으로 증명하지는 않습니다. 출처가 바뀌면 선언과 해시를 함께 검토하고 불명확하면 해당 리소스를 배포에서 제외한 뒤 권리자나 전문가에게 확인해야 합니다.
