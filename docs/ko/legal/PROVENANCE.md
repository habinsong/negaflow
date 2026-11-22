# 코드와 리소스 출처

[문서 홈](../README.md)

여기서는 저장소와 배포 산출물을 점검하기 위해 negaflow 앱의 Apache-2.0 배포 범위와 리소스 출처를 기술적 사실만 기준으로 기록합니다.

## 코드

`negaflow-mac`의 Swift와 Python, 셸 연동 코드는 negaflow를 위해 직접 작성했습니다.

네거티브 카메라 RAW 디코딩에는 고정된 LibRaw 리비전을 CDDL-1.0으로 빌드하며, macOS에서는 교체 가능한 `libraw.dylib`, Windows에서는 `libraw.dll`(Microsoft `vcomp140.dll` 포함)을 사용합니다. 양쪽 플랫폼에 똑같은 병렬 패치 세 개가 들어갑니다.

- [`xtrans-parallel-rows.patch`](../../../negaflow-mac/scripts/libraw/xtrans-parallel-rows.patch): `src/demosaic/xtrans_demosaic.cpp`에서 Fuji X-Trans 타일을 순서대로 처리하면서 타일 안의 행을 병렬로 계산하고 서로 겹치지 않는 행 그룹 단위로 초록 경계 패스를 수행합니다
- [`mem-image-parallel-rows.patch`](../../../negaflow-mac/scripts/libraw/mem-image-parallel-rows.patch): `src/postprocessing/mem_image.cpp`에서 출력 비트맵 행을 병렬로 복사합니다
- [`raw-decoders-parallel.patch`](../../../negaflow-mac/scripts/libraw/raw-decoders-parallel.patch): `src/decoders/decoders_dcraw.cpp`에서 일반 무손실 JPEG(CR2)와 Nikon NEF 데이터를 병렬 허프만 디코더에 넘기고 Sony ARW2 행을 병렬로 디코딩합니다

패치를 반영한 빌드는 시험한 RAW 파일에서 패치 없는 직렬 빌드와 일치하는 결과를 냅니다.

macOS에서는 LLVM OpenMP(libomp 20.1.8, Apache License v2.0 with LLVM Exceptions)를 라이브러리에 정적으로 링크하며 앱 번들의 `Contents/Resources/licenses/libraw/` 안에 소스 아카이브와 패치, 빌드 스크립트와 저작권 라이선스 파일을 함께 넣습니다.

`native-preview-bridge.cpp`(Negaflow contributors, CDDL-1.0)는 픽셀 단위 반복 세 개를 병렬로 실행하면서 출력이 바이트 단위로 일치하는 LibRaw 하위 클래스와 디코더 패치용 병렬 허프만 디코더를 제공하며 LibRaw 소스는 Apache 소스 트리와 분리해 관리합니다.

Windows도 똑같은 업스트림 리비전과 공통 패치 세 개를 따르며 `Makefile.msvc`에 `native-preview-bridge-msvc.patch`를 추가로 거칩니다. Microsoft의 선택적 WIC Raw Image Extension이 없을 때는 비네거티브 카메라 RAW의 대체 경로로도 `libraw.dll`을 호출합니다.

Windows의 `native-preview-bridge.cpp`(CDDL-1.0)는 선형 DNG용 Windows 전용 함수를 포함하고 그 밖의 구성 요소는 [`negaflow-windows/THIRD-PARTY-NOTICES.md`](../../../negaflow-windows/THIRD-PARTY-NOTICES.md)에 있습니다.

테스트 전용 `CameraNativeRaw.dng`는 raw.pixls.us 2204번 항목의 CC0-1.0 자료이고 옆의 출처 JSON으로 식별하며 앱에서는 제외합니다. 보충 고지 파일이 없으면 빌드와 패키징 단계가 경고하고 계속하며 업스트림 라이선스 파일과 대응 소스는 그대로 들어갑니다.

필름 반전은 공개된 감도 측정 개념인 광학 농도와 특성곡선(토와 직선부, 숄더)에 기초합니다. 이때 곡선과 계수는 제3자 프로그램의 식이나 상수를 가져오는 대신 negaflow가 정의한 광도 출발점 네 곳에서 직접 유도했으며 구체적인 식과 유도 과정은 [네거티브 반전 응답](../reference/PRINT_RESPONSE.md)에 정리했습니다.

출하되는 필름 상수 세 종류는 공개된 제조사 데이터시트를 근거로 삼는데 여기에는 필름 종류별 Dmin과 Dmax 프리셋인 `FilmStockDmin`, 흑백의 분광과 특성곡선 프리셋인 `BWFilmProfile`, 물리적 그레인과 MTF 매개변수인 `DigitalFilmPhysics`가 들어갑니다. 이 값들은 공개된 기술 차트에서 읽어 근사한 설정이며 `FilmStockDmin`은 모든 항목에 `datasheetCurve` 또는 `estimated`를 기록해 출처를 표시합니다.

공개 차트에서 읽은 물리량은 고유한 저작물이 아닌 필름 자체의 관측치이며 실제 스캔에서 구한 필름 베이스가 언제나 이 기본값에 앞섭니다.

GrainMend IR은 아래 순서로 동작합니다.

1. 전역 정수 RGB↔IR 오프셋을 시작 시드로 추정하며 신뢰도가 낮으면 강한 후보에서 구한 대략적 합의 오프셋으로 바꿉니다.
2. 가장자리와 맞닿은 어두운 필름 홀더와 여백 영역을 제외합니다.
3. 주변 영역의 형태학적 닫힘 바탕으로 배경면을 만들고 광학 농도 `log(baseline / value)`를 계산해 넓은 염료 고스팅을 지웁니다.
4. 스캔의 중앙값과 사분위수(IQR) 농도 분포에서 면적 가중 유의도로 후보를 추출한 뒤 가시광 적색 채널에서 주변 대비 4σ 이상(`>= 4σ`)인지 부분별로 확인하여 결함별 감쇠를 추정합니다.
5. 부분 차폐 화소는 투과 나눗셈 식인 `raw ÷ (1 - attenuation)`으로 복원하고 감쇠율이 50% 이상(`>= 50%`)인 불투명 코어만 RGB 패치 복원기에 맡깁니다.

이 코드는 SANE의 IR 보정과 독립적으로 작성했으며 공개된 논문과 제품 페이지는 필름과 적외선의 물리적 제약을 확인하는 배경 자료로만 참고했습니다. 방법이나 원리의 채택과 코드 표현의 복제는 서로 다른 영역이며 미국 저작권청 역시 방법이나 시스템 자체와 그 구체적 표현을 명확히 나눕니다.

- [U.S. Copyright Office Circular 33](https://www.copyright.gov/circs/circ33.pdf)
- [SANE backends source repository](https://gitlab.com/sane-project/backends)

## SANE 플러그인 경계

앱에는 `scanimage`나 SANE 헤더, 백엔드 설정, 장치별 처리 코드가 없습니다. 설치된 외부 프로그램과는 버전이 있는 JSON/NDJSON 규약으로만 통신합니다. 실제 SANE 작업은 GPL-2.0-or-later인 별도 저장소와 실행 파일로 나갑니다.

다만 프로세스를 분리했다는 사실만으로 라이선스 경계가 자동으로 성립하는 것은 아니며, GNU FAQ에서도 파이프나 명령줄 통신을 대개 별개 프로그램으로 보면서도 통신이 지나치게 긴밀해지면 판단이 달라질 수 있다고 설명합니다. 그래서 이 규약은 SANE 내부 데이터 구조를 배제한 채 장치와 무관한 요청과 기능, 진행 상황, 결과 파일 정보만 주고받습니다.

- [GNU license FAQ: aggregates and separate programs](https://www.gnu.org/licenses/gpl-faq.en.html)
- [Apache License 2.0 and GPL compatibility](https://www.apache.org/licenses/GPL-compatibility)
- [스캐너 플러그인 구조](../architecture/SCANNER_PLUGINS.md)

배포 검사는 플러그인이나 SANE 실행 파일, SANE 라이브러리가 앱 번들에 섞여 들어가지 않았는지 다시 확인합니다. 플러그인 쪽에는 자체 `LICENSE`와 `COPYING`, 대응 소스 일체와 서드파티 고지가 함께 들어갑니다.

## 번들 리소스

[`Config/bundled-resource-provenance-v1.json`](../../../negaflow-mac/Config/bundled-resource-provenance-v1.json)은 앱과 소스 트리에 들어가는 모든 리소스의 선언된 출처와 라이선스, SHA-256을 고정합니다.

| 구성 | 출처 | 배포하는 것 |
|---|---|---|
| ScannerKit TIFF | 관리자가 촬영해 준비한 레이아웃 자료 | TIFF 파일 4개 |
| 앱 아이콘 | 관리자의 프로젝트 아트워크 | 원본 PNG, 빌드용 PNG, ICNS |
| 룩 프리셋 | negaflow 전용으로 작성한 설정 | JSON 파일 6개 |
| 스캐너 프로파일 | 관리자가 보관한 스캔 측정에서 만듦 | 프로파일 데이터, 원본 스캔은 제외 |

TIFF 파일에 기록된 카메라와 색 공간 메타데이터는 촬영과 인코딩 과정에서 생긴 컨테이너 정보이며, 스캐너 프로파일의 `sourceProfiles`에는 빌드 때 참조한 로컬 측정 자료의 논리 경로만 기록하고 원본 사진은 배포본에서 뺍니다.

FILM-R v2 자료는 품질 측정 중에만 내려받아 활용하므로 이미지 파일이 저장소나 앱 번들에 포함되는 일은 없습니다.

[`Config/defect-corpus-film-r-v2.json`](../../../negaflow-mac/Config/defect-corpus-film-r-v2.json)은 논문 버전과 DOI, CC BY 4.0 라이선스, 쌍 개수, 총 바이트 수를 고정하고, `fetch-film-r.py`는 내려받을 때 Figshare 메타데이터의 파일별 크기와 MD5 다이제스트를 검사합니다.

## DNG 내보내기

DNG 기록기(`negaflow-mac`의 `DNGLinearWriter`, `negaflow-windows`의 `dng_linear_export`)는 Adobe가 공개한 Digital Negative Specification 1.6의 태그 번호와 색 모델만 참조해 자체 작성했으며, Adobe DNG SDK나 LibRaw, 다른 DNG 기록기의 외부 코드 없이 sRGB와 Display P3, Adobe RGB (1998)의 공개된 색도 좌표에서 색 행렬을 직접 구해 냅니다.

Adobe는 DNG 파일을 읽거나 기록하는 소프트웨어에 로열티 없는 특허 라이선스를 제공합니다. negaflow도 그 허가 조건에 따라 아래 고지문을 함께 싣습니다.

This product includes DNG technology under license by Adobe.

DNG는 Adobe Inc.의 상표입니다. 이 명칭은 파일 형식을 가리킬 때만 표기합니다.

## 기하 변환과 수평 보정

변환 섹션과 수평선 보정은 외부 코드 없이 negaflow 전용으로 직접 작성했습니다.

- 곧은 선분은 밝기 기울기 방향이 일치하는 화소군을 모으고 각 영역에 주성분 방향의 직선을 피팅해 찾는데, 이처럼 가장자리 화소를 방향별로 모으는 방법은 1980년대부터 공개된 기법입니다.
- 최적화 솔버는 수직이나 수평에서 30° 안에 드는 선분만 골라낸 뒤 초점거리가 고정된 가상 카메라를 회전시켜 선분을 각 모드가 허용하는 범위에서 수직과 수평에 가깝게 정렬합니다. 이때 카메라 내부 파라미터나 맨해튼 방향, 소실점을 따로 추정하는 대신 이상치에 둔감한 각도 오차 합만 Nelder–Mead 단체법으로 줄입니다.
- 도우미 모드는 사용자가 그린 안내선만 따릅니다.

Adobe는 사진 원근 자동 보정에 관한 미국 특허 두 건을 유효하게 보유하고 있습니다. 우선일은 양쪽 모두 2012년 4월 27일이고 Google Patents는 2033년 만료를 예상합니다.

- [US 9,519,954](https://patents.google.com/patent/US9519954B2/en)는 에너지 함수를 최적화해 내부 파라미터 행렬과 방향 행렬, 소실점을 함께 추정하는 방법을 청구하는데 negaflow의 솔버는 이 세 항목을 모두 계산 대상에서 뺍니다.
- [US 9,582,855](https://patents.google.com/patent/US9582855B2/en)의 독립항은 범위가 더 넓어서 사람의 지각 기준을 일부라도 반영해 선을 화면 축과 나란하게 정렬하는 호모그래피나 평면 변환 계산을 청구합니다. negaflow의 솔버 역시 선을 화면 축에 정렬하지만 그 발상 자체는 2012년 이전에도 공개돼 있었습니다. 예를 들어 2006년에 처음 소개되고 2008년 10월에 3.4판이 공개된 Marcus Hebel의 [ShiftN](https://www.shiftn.de/ShiftN_functionality.html)(판 기록: <https://newsgroup.xnview.com/viewtopic.php?p=57759>)도 수직에 가까운 곧은 가장자리를 찾아 서로 평행하고 화면 외곽과 나란해지도록 원근 변환을 최적화했으며 negaflow는 ShiftN의 코드를 참조하는 대신 자체 솔버를 따로 구현합니다.

특정 구현이 특허 청구항에 속하는지는 법률적 판단 영역이므로 이 기술 기록에서는 판단하지 않습니다.

## 이름과 상호 운용성

필름과 스캐너 이름, 색 공간과 XMP 네임스페이스, 제품 명칭은 대상을 식별하고 파일의 상호 운용성을 유지하기 위해서만 표기합니다.

Windows 엔진이 합성하는 출력 ICC 프로파일은 설명형 이름(`"Negaflow Compatible P3"`, `"Compatible with Adobe RGB (1998)"`, `"Linear sRGB"`)과 `CC0 1.0 Universal` 헌정을 적용하므로 내보낸 사용자 이미지에 프로파일 저작권 제한이 걸리지 않게 만듭니다. 또한 외부 상표의 소유권이나 제휴 관계와는 무관하며 자세한 기준은 [`TRADEMARKS.md`](../../../TRADEMARKS.md)에 정리했습니다.

## 자동 검사와 놓치는 것

`python3 scripts/ci/verify-provenance.py`(`negaflow-mac/`에서 실행)는 작업 트리와 도달 가능한 git 이력을 함께 검사하며 아래 항목 가운데 어느 것이라도 발견되면 실패합니다.

- 등록되지 않았거나 해시가 바뀐 번들 리소스
- 예외 경로(문서화된 Windows 네이티브 소스와 테스트, 매니페스트 경로, 두 개의 CDDL `native-preview-bridge.cpp` 브리지) 밖의 C/C++/Objective-C 코드나 외부 패키지, 바이너리 아카이브, 벤더 트리
- 앱 코드 안의 SANE 전용 이름이나 확인된 외부 구현의 흔적
- 릴리즈 스크립트가 SANE 플러그인을 앱에 넣게 되는 변경
- 저장소 안의 FILM-R 이미지 자료

이 검사는 현재 트리와 도달 가능한 git 이력의 명백한 퇴보를 걸러 내지만, 외부 코드와의 전반적인 유사성이나 사진과 프로파일 입력의 권리 관계, 특허와 상표나 국가별 법적 판단까지 대신 보증하지는 않습니다. 따라서 출처가 바뀌면 선언과 해시를 함께 검토하고, 권리 관계가 불분명한 리소스는 릴리즈에서 제외한 뒤 권리자나 전문가에게 확인하세요.
