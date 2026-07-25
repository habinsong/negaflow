# Negaflow 문서

필요한 문서부터 바로 찾을 수 있도록 내용별로 나눴습니다.

[English](../README.md) · 한국어 · [日本語](../ja/README.md) · [简体中文](../zh-Hans/README.md) · [Français](../fr/README.md) · [Deutsch](../de/README.md)

```mermaid
flowchart LR
    A["제품을 먼저 알고 싶다"] --> P["product"]
    B["코드와 데이터 흐름을 본다"] --> R["architecture"]
    C["형식과 수치를 확인한다"] --> S["reference"]
    D["출시 가능 여부를 확인한다"] --> V["validation"]
```

> [!NOTE]
> 현재 버전은 `1.0.0`입니다. 구현 여부와 실제로 확인한 범위는
> [지금 어디까지 됐나](product/PROJECT_STATUS.md)를 기준으로 봅니다.

## 제품

| 문서 | 먼저 볼 때 |
|---|---|
| [크로마 엔진](product/CHROMA_ENGINE.md) | 필름 반전과 현상 순서가 궁금할 때 |
| [GrainMend](product/GRAINMEND.md) | 먼지·스크래치 복원이 어떻게 작동하는지 볼 때 |
| [필름 프로파일](product/FILM_PROFILES.md) | 번들 프로파일의 출처와 한계를 확인할 때 |
| [지금 어디까지 됐나](product/PROJECT_STATUS.md) | 구현, 측정, 배포 상태를 확인할 때 |

## 구조

| 문서 | 다루는 내용 |
|---|---|
| [제품 구조](architecture/PRODUCT_ARCHITECTURE.md) | 앱, 엔진, 저장소, 출력 사이의 데이터 흐름 |
| [카탈로그 저장 구조](architecture/CATALOG_STORAGE.md) | SQLite 선택 이유, 이전 방식, 측정값 |
| [스캐너 플러그인 구조](architecture/SCANNER_PLUGINS.md) | 외부 프로세스, 승인, 스캔 파일 공개 |
| [라이브러리 보존 아카이브](architecture/LIBRARY_ARCHIVE.md) | 원본과 편집 기록을 묶어 보관하는 방식 |

## 규격

| 문서 | 다루는 내용 |
|---|---|
| [CLI 스캐너 JSON](reference/CLI_JSON.md) | `detect --json`, `capabilities --json` 출력 형식 |
| [렌더 기록](reference/RENDER_MANIFEST.md) | 원본, 편집 값, 출력 파일의 SHA-256 관계 |
| [고정 인화 응답](reference/PRINT_RESPONSE.md) | `shoulder-print-response-v4`의 식과 기준점 |
| [스캐너 프로파일 품질 검사](reference/PROFILE_QUALITY_GATE.md) | REAL/TARGET 쌍 자료의 출시 판정 규칙 |
| [스캐너 노이즈 프로파일](reference/SCANNER_NOISE_PROFILES.md) | 반복 스캔 측정과 자동 적용 조건 |
| [GrainMend IR이 피해야 할 필름](reference/INFRARED_LIMITS.md) | 흑백, Kodachrome, RGB/IR 정렬 한계 |
| [IT8 색 검사](reference/IT8_COLOR_VALIDATION.md) | 패치 측정, 증거 등급, 합성 회귀 |

## 검증

| 문서 | 쓰는 때 |
|---|---|
| [출시 전 실기기 점검표](validation/REAL_QA_CHECKLIST.md) | 실제 Mac, 화면, 스캐너, 필름을 확인할 때 |
| [GrainMend 실제 스캔 비교](validation/GRAINMEND_CORPUS.md) | FILM-R v2 44쌍을 다시 측정할 때 |

## 출처와 배포

| 문서 | 쓰는 때 |
|---|---|
| [코드와 리소스 출처](legal/PROVENANCE.md) | Apache/GPL 경계와 번들 리소스 해시를 확인할 때 |
| [`TRADEMARKS.md`](../../TRADEMARKS.md) | 필름·스캐너·제품 이름의 식별 목적을 확인할 때 |

## 읽는 법

- 제품 설명에는 지금 사용자가 보는 동작만 적습니다.
- 구조 문서에는 책임과 데이터 이동을 적습니다.
- 규격 문서의 코드값, 필드명, 해시는 원문 그대로 둡니다.
- 검증 문서는 통과한 것과 아직 확인하지 않은 것을 나눠 적습니다.
