# 지금 어디까지 됐나

[문서 홈](../README.md)

현재 구현과 검증 상태를 기록하는 기준 문서입니다.
README는 제품과 사용법을 설명하고, docs의 각 문서는 세부 규격과 결정을 맡습니다.

## 기본 정보

| 항목 | 현재 값 |
|---|---|
| 버전 | `1.0.3` |
| 빌드 | `1` |
| 운영체제 | macOS 14 이상 |
| 작업 순서 | 가져오기·스캔 → 현상 → 내보내기 |
| 기본 현상 | `main`, 수동 보정 |
| 원본 | 원본 파일과 제3자 사이드카를 수정하지 않음 |

> [!WARNING]
> `1.0.3` 표기와 빌드 성공만으로 실제 스캐너 호환성, 최종 화질, 외부 서명이나 공증까지
> 확인됐다고 보지는 않습니다. 실기기와 배포 승인은 아래 점검표에 따로 남깁니다.

## 구현했고 자동 검사하는 범위

- 비파괴 카탈로그, 사이드카, 가상 사본, 컬렉션, 롤, 별점, 선택·제외
- 중복 가져오기, 원본 다시 연결, 라이브러리 제거, 원본 휴지통 이동
- 카탈로그 건강 검사, 프로세스 잠금, 복구 차단, 백업 세대, 복원 연습과 선택 프레임 재현상
- 현상·내보내기 공통 경로, 메타데이터, 처리 이력, 편집 기록, 여러 파일 출력
- 적어 둔 카메라·렌즈·필름·노출을 내보낸 파일에 기록. EXIF 카메라는 스캐너보다 촬영 카메라가 우선
- 롤에 적은 기록으로 프레임의 빈 칸만 채우기, 롤 코드·필름·카메라 파일 이름 토큰
- 내려간 iCloud 원본을 내보내기 전에 확보, 표준·엄격 두 단계의 내보내기 검증
- 평판 프리뷰에서 선택한 필름 규격 비율로 고정되는 프레임 선택
- 현상 완료·재처리 상태를 따라 내보내기 버튼을 갱신하는 저빈도 관찰 경계
- 스캐너 플러그인 찾기와 승인, 기능 검사, 프로토콜 v1/v2, 취소, 시간 제한, 출력 상한
- 플러그인 소유자·권한 검사와 임시 출력 검증
- CLI 스캐너 JSON과 앱 화면 기능의 일치 검사
- 손쉬운 사용, 선택 상태, 글자 크기, 창 크기 대응, 화면 상태 복원
- 비교·설문 보기, 사진 스택, 중복 후보 확인
- 원본과 IR, GrainMend 기록, 가상 사본 관계를 넣는 BagIt 보존 아카이브
- 렌더 기록 v3의 원본·출력 SHA-256 연결
- IR 정렬 진단과 필름 호환성 제한
- 스캐너 노이즈 반복 측정과 별도 검증 규격
- 메모리 압박에 따른 프레임 캐시 정리
- CI의 엄격한 Swift 동시성 진단

## 카탈로그

기본 저장소는 `library.sqlite`입니다.
기존 `library.json`은 읽기 전용으로 열어 건강 상태를 확인하고 백업한 뒤 임시 SQLite로 옮깁니다.
두 카탈로그의 내용과 SQLite 무결성이 모두 맞을 때만 기본 저장소로 바꿉니다.

중간 작업을 이어갈 때 증거가 맞지 않으면 닫힌 상태로 실패합니다.
JSON은 이동 가능한 백업·아카이브 교환 형식으로 남지만 두 기본 저장소를 동시에 쓰지는 않습니다.

자세한 내용은 [카탈로그 저장 구조](../architecture/CATALOG_STORAGE.md)에 있습니다.

## 스캐너

이 저장소에는 장치와 무관한 외부 프로세스 호스트와 JSON 규격만 있습니다.
SANE 구현, 의존성, 설정, 배포 파일은 넣지 않습니다.
해당 코드는 별도 GPL 프로젝트
[`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane)에 있습니다.

앱은 설치한 플러그인이 보고한 기능만 보여 줍니다. 모델명으로 기능을 추측하지 않습니다.
사용자가 데모를 고르지 않으면 가짜 스캐너로 대신하지 않습니다.

자세한 규격:

- [스캐너 플러그인 구조](../architecture/SCANNER_PLUGINS.md)
- [CLI 스캐너 JSON](../reference/CLI_JSON.md)

## 빌드와 배포

<details>
<summary>로컬 확인과 배포 명령</summary>

로컬 확인:

```bash
bash scripts/ci-gate.sh
bash scripts/run-app.sh build
bash scripts/run-gui-e2e.sh  # macOS Automation Mode 필요
```

배포 파일 만들기:

```bash
bash scripts/build-release.sh
```

</details>

`build-release.sh` 한 번으로 Apple Silicon(`arm64`)과 Universal(`arm64`, `x86_64`) 앱을 각각
빌드하고 ZIP, PKG, DMG, dSYM, SHA-256 목록을 만듭니다.
로컬에서는 임시 서명을 쓰며, 실제 배포에는 Developer ID Application과 Developer ID Installer
서명이 모두 필요합니다.

수동 `Distribution` workflow는 보호된 Developer ID와 App Store Connect API 키를 사용합니다.
앱 아카이브, DMG와 PKG를 Apple에 보내고 공증 티켓을 붙인 뒤 체크섬과 Gatekeeper를 다시
확인합니다.
실제 workflow와 Apple 응답이 없으면 외부 서명과 공증에 성공했다고 말하지 않습니다.

## 성능 측정

성능 검사는 카탈로그, 라이브러리 검색, 고해상도 조절, GrainMend 영역 처리, 실제 픽셀 롤을
다룹니다.

최근 한 Mac의 Release 측정:

| 작업 | 결과 |
|---|---:|
| 50,000프레임 JSON 읽기 p95 | 약 7.4초 |
| 50,000프레임 SQLite 읽기 p95 | 약 7.4초 |
| 50,000프레임 SQLite 커밋 p95 | 약 3.7초 |
| 변경 없는 SQLite 커밋 p95 | 약 3.9초 |
| 50,000프레임 필터·이름 정렬 | 약 158 ms |
| 48프레임 빠른 미리보기 | 약 10.6초, 최대 RSS 약 504 MiB |
| 48프레임 현상 | 약 20.9초, 최대 RSS 약 1,012 MiB |

다른 Mac의 성능을 보장하는 값은 아닙니다. 새 측정은 다음 명령으로 만듭니다.

```bash
bash scripts/run-performance-suite.sh
```

`Config/performance-budget-v1.json`의 macOS 26 arm64 제한은 큰 회귀를 잡기 위한 넓은 상한입니다.
통과했다고 모든 지연이 좋은 사용자 경험이라는 뜻은 아닙니다.

## GrainMend 측정

FILM-R v2 자료는 DOI, 44쌍, 437,570,872바이트, Figshare MD5 정보로 고정했습니다.

출시 자동 경로는 민감도 0.7과 과검출 안전선을 적용했습니다.
직전 회귀 기준 3.0과 비교한 결과입니다.

| 지표 | 직전 기준 3.0 | 안전 자동 0.7 |
|---|---:|---:|
| 가중 악화 픽셀 | 0.792% | 0.017% |
| 가중 변경 픽셀 | 0.794% | 0.043% |
| 평균 PSNR 변화 | -1.688 dB | +0.466 dB |
| 최저 PSNR 변화 | -18.952 dB | -1.338 dB |
| 개선 / 악화 / 동일 이미지 | 11 / 33 / 0 | 34 / 6 / 4 |

관측값 회귀 검사와 별도로 평균·중앙 PSNR 0 dB 이상, 악화 10장 이하, 최저 -1.5 dB 이상의 절대
하한을 검사합니다.
자동 안전선이 3장에서 복원을 중지했고, 이 경우 가이드 사용을 안내합니다.

FILM-R은 GrainMend RGB 자동 경로만 검증합니다.
하드웨어 IR과의 동등함이나 실제 스캐너 RGB·IR 정렬 품질을 주장할 근거는 아닙니다.

수동 `GrainMend corpus` workflow는 44쌍을 받고 Release 기본 경로를 실행한 뒤 회귀 검사와 보고서
업로드를 합니다.

## 자동 검사로 끝나지 않는 항목

- 지원 화면 크기와 손쉬운 사용 설정의 최종 UI 확인
- 실제 플러그인과 스캐너
- 실제 네거티브와 IR 화질
- Developer ID, 공증, Gatekeeper, 깨끗한 Mac 설치
- 지원하는 모든 Mac의 성능

최종 화면과 실기기 확인은 사용자가 맡습니다.
빌드 성공으로 대신하지 않고 [출시 전 실기기 점검표](../validation/REAL_QA_CHECKLIST.md)에 결과를
남깁니다.

## 문서 기준

| 내용 | 기준 문서 |
|---|---|
| 현재 구현과 검증 | 이 문서 |
| 스캐너 호스트 규격 | [스캐너 플러그인 구조](../architecture/SCANNER_PLUGINS.md) |
| CLI 스캐너 JSON | [CLI 스캐너 JSON](../reference/CLI_JSON.md) |
| 카탈로그 저장 방식 | [카탈로그 저장 구조](../architecture/CATALOG_STORAGE.md) |
| 스캐너 프로파일 출시 기준 | [스캐너 프로파일 품질 검사](../reference/PROFILE_QUALITY_GATE.md) |
| GrainMend 구현과 한계 | [GrainMend](GRAINMEND.md) |
| 최종 화면·실기기 승인 | [출시 전 실기기 점검표](../validation/REAL_QA_CHECKLIST.md) |
| 설치와 사용법 | 저장소 루트의 README 파일 |
