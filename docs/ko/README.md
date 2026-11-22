# negaflow 문서

필요한 문서부터 바로 찾을 수 있도록 내용별로 나눴습니다.

[English](../README.md) · 한국어 · [日本語](../ja/README.md) · [简体中文](../zh-Hans/README.md) · [Français](../fr/README.md) · [Deutsch](../de/README.md)

> [!NOTE]
> negaflow 1.2.7은 macOS와 Windows에서 모두 동작합니다. 양쪽 앱은 따로 개발했지만 똑같은 파일을 넣으면 일치하는 결과를 냅니다.

## 플랫폼

| 문서 | 언제 보나 |
|---|---|
| [macOS 버전과 Windows 버전의 차이](platform/PLATFORM_DIFFERENCES.md) | 두 버전의 공통점과 차이점을 알고 싶을 때 |
| [macOS 문서](../../negaflow-mac/docs/README_ko.md) | macOS에서 설치하거나 빌드하거나 CLI를 실행할 때 |
| [Windows 문서](../../negaflow-windows/docs/README_ko.md) | Windows에서 설치하거나 빌드하거나 엔진을 점검할 때 |

## 제품

| 문서 | 먼저 볼 때 |
|---|---|
| [라이브러리에서 인화까지](product/WORKFLOW.md) | 가져오기나 폴더 현상, 복사와 붙여넣기, 인화 동작이 필요할 때 |
| [Chroma Engine](product/CHROMA_ENGINE.md) | 필름 반전과 현상 순서를 알고 싶을 때 |
| [GrainMend](product/GRAINMEND.md) | 먼지와 스크래치 복원 방식을 보고 싶을 때 |
| [필름 프로파일](product/FILM_PROFILES.md) | 번들 프로파일의 출처와 적용 범위를 알고 싶을 때 |

## 구조

| 문서 | 설명 |
|---|---|
| [제품 구조](architecture/PRODUCT_ARCHITECTURE.md) | 앱과 엔진, 저장소, 내보내기 모듈의 데이터 흐름 |
| [카탈로그 저장 구조](architecture/CATALOG_STORAGE.md) | SQLite 카탈로그와 이전 JSON 가져오기, 실측 기록 |
| [스캐너 플러그인 구조](architecture/SCANNER_PLUGINS.md) | 외부 프로세스 실행과 승인, 스캔 파일 게시 |
| [라이브러리 보존 아카이브](architecture/LIBRARY_ARCHIVE.md) | 원본과 편집 기록을 함께 저장하는 방식 |

## 규격

| 문서 | 설명 |
|---|---|
| [CLI 스캐너 JSON](reference/CLI_JSON.md) | `detect --json`, `capabilities --json` 출력 |
| [렌더 기록](reference/RENDER_MANIFEST.md) | 원본과 편집 설정, 결과 파일을 연결하는 SHA-256 |
| [인화 레이아웃과 C-print 미리보기](reference/C_PRINT.md) | 레이아웃 8종과 완성 페이지 내보내기, 시안 전용 ICC의 정확도 범위 |
| [네거티브 반전 응답](reference/PRINT_RESPONSE.md) | `shoulder-print-response-v4`의 식과 출발점 |
| [스캐너 프로파일 품질 검사](reference/PROFILE_QUALITY_GATE.md) | REAL/TARGET 쌍 자료의 배포 기준 |
| [스캐너 노이즈 프로파일](reference/SCANNER_NOISE_PROFILES.md) | 반복 스캔 측정과 반영 조건 |
| [GrainMend IR이 피해야 할 필름](reference/INFRARED_LIMITS.md) | 흑백이나 코다크롬 필름, RGB/IR 정렬 제약 |
| [평판 프레임 자동 검출이 필름을 찾는 방법](reference/FRAME_DETECTION.md) | 필름과 빈 홀더의 구분, 컷 경계 |
| [IT8 색 검사](reference/IT8_COLOR_VALIDATION.md) | 패치 측정과 검증 단계, 합성 회귀 |

## 출처와 배포

| 문서 | 찾아볼 때 |
|---|---|
| [코드와 리소스 출처](legal/PROVENANCE.md) | Apache/GPL 경계와 번들 리소스 해시를 확인할 때 |
| [`TRADEMARKS.md`](../../TRADEMARKS.md) | 필름과 스캐너, 제품 이름을 어떻게 표기하는지 확인할 때 |

## 읽는 법

- 제품 문서는 지금 사용자가 보는 화면과 기능만 적고, 구조 문서는 모듈의 책임과 데이터 흐름을 설명합니다.
- 참고 문서의 코드 문자열과 필드 이름, 해시는 원문 그대로 지킵니다.
- 검증 문서는 통과한 항목과 확인하지 않은 범위를 나누며, 한 언어에 있는 절은 여섯 언어 모두에 똑같이 들어갑니다.
