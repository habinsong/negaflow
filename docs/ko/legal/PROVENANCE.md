# 코드와 리소스 출처

[문서 홈](../README.md)

이 문서는 negaflow 앱의 Apache-2.0 배포 범위를 기록합니다. 저장소와 배포 산출물을 확인하기 위한 출처 기록이며 법률 자문이 아닙니다.

## 코드

`negaflow-mac`의 Swift, Python, 셸 연동은 negaflow를 위해 작성했습니다.

네거티브 카메라 RAW 디코딩에는 고정된 LibRaw 리비전을 교체 가능한 `libraw.dylib`로 빌드해 CDDL-1.0으로 배포합니다. 두 플랫폼 모두 같은 패치 세 개를 적용합니다.

- [`xtrans-parallel-rows.patch`](../../../negaflow-mac/scripts/libraw/xtrans-parallel-rows.patch): `src/demosaic/xtrans_demosaic.cpp`에서 Fuji X-Trans 타일을 순서대로 처리하고, 타일 안의 행을 병렬로 처리하며, 서로 닿지 않는 행 묶음 단위로 초록 경계 패스를 돌립니다
- [`mem-image-parallel-rows.patch`](../../../negaflow-mac/scripts/libraw/mem-image-parallel-rows.patch): `src/postprocessing/mem_image.cpp`에서 출력 비트맵 행을 병렬로 복사합니다
- [`raw-decoders-parallel.patch`](../../../negaflow-mac/scripts/libraw/raw-decoders-parallel.patch): `src/decoders/decoders_dcraw.cpp`에서 일반 무손실 JPEG(CR2)와 Nikon NEF 데이터를 병렬 허프만 디코더에 넘기고 Sony ARW2 행을 병렬로 디코딩합니다

패치를 적용한 빌드는 시험한 RAW 파일에서 패치 없는 직렬 빌드와 같은 결과를 냅니다.

macOS에서는 LLVM OpenMP(libomp 20.1.8, Apache License v2.0 with LLVM Exceptions)를 라이브러리에 정적으로 링크합니다. 앱에는 소스 아카이브, 패치, 빌드 스크립트, 저작권·라이선스 파일이 `Contents/Resources/licenses/libraw/`에 들어 있습니다. `native-preview-bridge.cpp`(Negaflow contributors, CDDL-1.0)에는 픽셀 단위 반복 세 개를 병렬로 돌리면서 출력이 바이트 단위로 같은 LibRaw 하위 클래스와, 디코더 패치가 부르는 병렬 허프만 디코더가 있습니다. LibRaw 소스는 Apache 소스 트리에 섞지 않습니다.

Windows도 같은 업스트림 리비전과 패치를 씁니다. Windows의 `native-preview-bridge.cpp`(CDDL-1.0)는 선형 DNG용 Windows 전용 함수를 더하고, 그 밖의 구성 요소는 [`negaflow-windows/THIRD-PARTY-NOTICES.md`](../../../negaflow-windows/THIRD-PARTY-NOTICES.md)에 있습니다. 테스트 전용 `CameraNativeRaw.dng`는 raw.pixls.us 2204번 항목의 CC0-1.0 자료이고 옆의 출처 JSON으로 식별하며 앱에서는 제외합니다. 보충 고지 파일이 없으면 빌드와 패키징 단계가 경고하고 계속하며, 업스트림 라이선스 파일과 대응 소스는 그대로 포함합니다.

필름 반전은 밀도, 토, 직선부, 숄더라는 공개된 감도 측정 개념을 씁니다. 곡선과 계수는 제3자 프로그램의 식이나 상수가 아니라 negaflow의 광도 기준점 네 개에서 나왔습니다. 식과 유도는 [네거티브 반전 응답](../reference/PRINT_RESPONSE.md)에 있습니다.

공개된 제조사 데이터시트가 출하하는 필름 상수 세 묶음에 근거를 줍니다. 필름 종류별 Dmin·Dmax 프리셋(`FilmStockDmin`), 흑백의 분광·특성곡선 프리셋(`BWFilmProfile`), 물리적 그레인과 MTF 매개변수(`DigitalFilmPhysics`)입니다. 이 수치는 공개된 기술 자료에서 대략 읽거나 맞춘 값이며, `FilmStockDmin`은 모든 항목에 `datasheetCurve` 또는 `estimated`를 표시해 출처를 남깁니다. 공개 차트에서 읽은 수치는 필름에 대한 사실이지 누구의 코드나 글을 베낀 것이 아니며, 스캔에서 측정한 필름 베이스가 언제나 이 값보다 우선합니다.

GrainMend IR은 이 순서로 동작합니다.

1. RGB와 IR 사이의 정수 오프셋을 스스로 추정합니다.
2. `log(red)` 구간마다 IR 절사 평균을 보간해 비모수 장면 누설 곡선을 만듭니다.
3. 장면 누설을 빼고 국소 평균에 대한 상대 대비를 계산합니다.
4. 절사한 국소 노이즈 임계값, 연결 성분, 방향으로 결함 마스크를 만듭니다.

이 코드는 SANE의 IR 보정을 링크하거나 옮겨 오지 않습니다. 공개된 논문과 제품 페이지는 필름과 적외선의 물리적 한계를 확인하는 배경 자료입니다. 방법이나 원리를 취하는 것과 코드의 표현을 베끼는 것은 다릅니다. 미국 저작권청도 방법·시스템과 그 구체적 표현 사이에 같은 선을 긋습니다.

- [U.S. Copyright Office Circular 33](https://www.copyright.gov/circs/circ33.pdf)
- [SANE backends source repository](https://gitlab.com/sane-project/backends)

## SANE 플러그인 경계

앱에는 `scanimage`, SANE 헤더, 백엔드 설정, 장치별 처리 코드가 없습니다. 설치된 외부 프로그램과는 버전이 있는 JSON/NDJSON 규약으로만 통신합니다. 실제 SANE 작업은 GPL-2.0-or-later인 별도 저장소와 실행 파일로 배포합니다.

별도 프로세스라는 사실만으로 라이선스 문제가 정리되지는 않습니다. GNU FAQ는 파이프나 명령줄 통신이 보통 별개 프로그램으로 보이지만 통신이 지나치게 긴밀하면 답이 달라질 수 있다고 말합니다. 그래서 이 규약은 장치와 무관한 요청, 기능, 진행 상황, 결과 파일 정보만 주고받고 SANE 데이터 구조는 공유하지 않습니다.

- [GNU license FAQ: aggregates and separate programs](https://www.gnu.org/licenses/gpl-faq.en.html)
- [Apache License 2.0 and GPL compatibility](https://www.apache.org/licenses/GPL-compatibility)
- [스캐너 플러그인 구조](../architecture/SCANNER_PLUGINS.md)

배포 검사는 플러그인, SANE 실행 파일, SANE 라이브러리가 앱 번들에 섞여 들어가지 않았는지 다시 확인합니다. 플러그인 쪽은 자체 `LICENSE`, `COPYING`, 대응 소스 전체, 서드파티 고지를 함께 배포합니다.

## 번들 리소스

[`Config/bundled-resource-provenance-v1.json`](../../../negaflow-mac/Config/bundled-resource-provenance-v1.json)은 앱과 소스 트리에 들어가는 모든 리소스의 선언된 출처, 라이선스, SHA-256을 고정합니다.

| 묶음 | 출처 | 배포하는 것 |
|---|---|---|
| ScannerKit TIFF | 관리자가 촬영해 준비한 레이아웃 자료 | TIFF 파일 4개 |
| 앱 아이콘 | 관리자의 프로젝트 아트워크 | 원본 PNG, 빌드용 PNG, ICNS |
| 룩 프리셋 | negaflow를 위해 쓴 값 | JSON 파일 6개 |
| 스캐너 프로파일 | 관리자가 보관한 스캔 측정에서 만듦 | 수치 프로파일, 원본 스캔은 제외 |

TIFF 파일에 보이는 카메라와 색 공간 메타데이터는 촬영과 인코딩에서 생긴 컨테이너 정보입니다. 스캐너 프로파일의 `sourceProfiles`는 빌드 때 쓴 로컬 측정 자료의 논리 경로이며, 그 원본 사진은 배포하지 않습니다.

FILM-R v2 자료는 품질 측정 중에만 내려받습니다. 이미지는 저장소나 앱에 들어오지 않습니다. DOI 버전, CC BY 4.0, 파일 크기, 해시는 [`Config/defect-corpus-film-r-v2.json`](../../../negaflow-mac/Config/defect-corpus-film-r-v2.json)에 고정되어 있습니다.

## DNG 내보내기

DNG 기록기(`negaflow-mac`의 `DNGLinearWriter`, `negaflow-windows`의 `dng_linear_export`)는 Adobe가 공개한 Digital Negative Specification 1.6의 태그 번호와 색 모델로 작성했습니다. Adobe DNG SDK 코드도, LibRaw나 다른 DNG 기록기의 코드도 들어 있지 않습니다. 색 행렬은 sRGB, Display P3, Adobe RGB (1998)의 공개된 색도 좌표에서 계산합니다.

Adobe는 DNG 파일을 읽거나 쓰는 소프트웨어에 로열티 없는 특허 라이선스를 제공합니다. 이 제품이 그 라이선스를 쓰며, 라이선스가 아래 고지를 요구합니다.

This product includes DNG technology under license by Adobe.

DNG는 Adobe Inc.의 상표입니다. 이 이름은 파일 형식을 가리키는 데만 씁니다.

## 변환과 수평 맞추기

변환 섹션과 기준선 수평 맞추기는 negaflow용으로 작성했고 외부 코드가 없습니다.

- 곧은 선분은 밝기 기울기 방향이 같은 화소를 묶고 묶음마다 주성분 방향으로 직선을 맞춰 찾습니다. 가장자리 화소를 방향으로 묶는 방법은 1980년대부터 공개된 기법입니다.
- 풀이기는 수직이나 수평에서 30° 안에 드는 선분만 남기고 초점거리가 고정된 카메라를 돌려 선분을 모드가 허용하는 만큼 수직·수평에 가깝게 만듭니다. 이상값에 둔감한 각도 오차 합을 Nelder–Mead 단체법으로 줄입니다. 카메라 내부 값, 맨해튼 방향, 소실점은 추정하지 않습니다.
- 도우미 모드는 사용자가 그린 안내선만 씁니다.

Adobe는 사진 원근 자동 보정에 관한 미국 특허 두 건을 유효하게 보유하고 있습니다. 우선일은 둘 다 2012년 4월 27일이고 Google Patents는 2033년 만료를 예상합니다.

- [US 9,519,954](https://patents.google.com/patent/US9519954B2/en)는 에너지 함수를 최적화해 내부 파라미터 행렬, 방향 행렬, 소실점을 함께 추정하는 방법을 청구합니다. negaflow는 이 가운데 어느 것도 추정하지 않습니다.
- [US 9,582,855](https://patents.google.com/patent/US9582855B2/en)의 독립항은 더 넓습니다. 사람의 지각 기준에 적어도 일부 기대어 선을 화면 축에 맞추는 호모그래피나 평면 변환을 계산하는 것입니다. negaflow의 풀이기도 선을 화면 축에 맞춥니다. 같은 발상은 2012년 전에 공개돼 있었습니다. Marcus Hebel의 ShiftN은 2006년에 소개됐고 2008년 10월에 3.4판이 나왔습니다. 수직에 가까운 곧은 가장자리를 찾아 서로 평행하고 화면 테두리와 나란해지도록 원근 변환을 최적화했습니다([ShiftN](https://www.shiftn.de/ShiftN_functionality.html), [판 기록](https://newsgroup.xnview.com/viewtopic.php?p=57759)). ShiftN 코드는 쓰지 않았습니다.

어떤 구현이 청구항에 걸리는지는 법률 판단이고 이 기록은 그 답을 내리지 않습니다.

## 이름과 상호 운용성

필름, 스캐너, 색 공간, XMP 네임스페이스, 제품 이름은 대상을 가리키고 파일의 상호 운용성을 지키기 위해 씁니다. Windows 엔진이 합성하는 출력 ICC 프로파일은 설명형 이름(`"Negaflow Compatible P3"`, `"Compatible with Adobe RGB (1998)"`)과 `CC0 1.0 Universal` 헌정을 쓰므로, 내보낸 사용자 이미지에 프로파일 저작권 제한이 붙지 않습니다. 상표 소유나 제휴를 주장하지 않습니다. 전체 범위는 [`TRADEMARKS.md`](../../../TRADEMARKS.md)에 있습니다.

## 자동 검사와 놓치는 것

`python3 scripts/ci/verify-provenance.py`(`negaflow-mac/`에서 실행)는 아래 중 하나라도 있으면 실패합니다.

- 등록되지 않았거나 해시가 바뀐 번들 리소스
- 앱 안의 C/C++/Objective-C, 외부 패키지, 바이너리 아카이브, 벤더 트리
- 앱 코드 안의 SANE 전용 이름이나 확인된 외부 구현의 흔적
- 릴리스 스크립트가 SANE 플러그인을 앱에 넣게 되는 변경
- 저장소 안의 FILM-R 이미지 자료

이 검사는 현재 트리의 뻔한 퇴보를 막습니다. 인터넷 전체와의 유사성, 사진이나 프로파일 입력의 권리, 특허, 상표, 어느 나라에서의 법적 결과는 증명하지 못합니다. 출처가 바뀌면 선언을 해시와 함께 검토하세요. 불분명하면 그 리소스를 릴리스에서 빼고 권리자나 전문가에게 물으세요.
