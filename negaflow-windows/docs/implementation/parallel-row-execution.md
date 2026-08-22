# 행 블록 병렬 실행

기준일: 2026-08-10

## 왜

실제 촬영본(3278×4944 16-bit, x64 Release)의 단계별 벽시계를 재 보니 현상 시간이 어디에
있는지가 분명했습니다.

| 단계 | 이전 |
|---|---|
| decode + color convert | 170 ms |
| **develop (반전)** | **1,887 ms** |
| tone (조정 켠 경우) | **2,057 ms** |
| film look (identity) | 29 ms |
| output (변환+encode+검증+게시) | 2,908 ms |

`develop` 은 픽셀당 `log10` → `pow` → `exp` → `pow` 를 채널마다 도는 완전한 pointwise 커널이고,
`tone` 도 같은 모양입니다. 16.2 M 픽셀 × 3 채널이 한 스레드에서 도는 것이 원인이었습니다.
미리보기는 output 이 빠진 경로이므로, 슬라이더를 한 번 움직일 때마다 사용자가 약 4.1 초를
기다리고 있었습니다.

## 무엇

`negaflow/core/parallel_rows.h` 의 `run_row_blocks` 하나가 행 분할을 소유합니다.

- 본문은 반열린 행 구간을 받고 그 밖을 읽거나 쓰지 않습니다. **따라서 결과는 순서대로 돌린
  것과 비트까지 같습니다.** 이것이 이 파일이 존재하는 유일한 계약입니다.
- 추가 스레드는 **프로세스 전역 예산**에서 꺼냅니다. 사진 여러 장을 동시에 현상해도 스레드가
  사진 수만큼 곱해지지 않습니다. 예산이 없거나 스레드 생성이 실패하면 호출 스레드에서
  인라인으로 끝까지 수행합니다 — 일이 사라지는 경로는 없습니다.
- 추정 작업량이 `minimum_parallel_row_work_units`(1 Mi) 미만이면 분할하지 않습니다.
- 블록당 최대 32개. 코어가 더 많아도 이 크기의 사진에서는 스케줄링 잡음만 늘어납니다.

**첫 실패 선택.** 단일 스레드 raster 스캔은 처음 만난 실패를 돌려줍니다. 블록은 순서 없이
끝나므로 각 블록이 자기 실패 행을 기록하고 **가장 작은 행이 이깁니다**. 행을 상위 32비트에
넣어 정수 최솟값 비교로 만들었고, 블록은 자기 첫 실패에서 멈추므로 같은 행이 두 번 기록될 수
없습니다.

`negaflow/core/pointwise.h` 가 그 위에 세 가지를 제공합니다.

| 함수 | 용도 |
|---|---|
| `apply_pointwise` | 검증 후 변환. 검증 순서(레이아웃 → 픽셀)가 계약입니다 |
| `transform_validated_pointwise` | 이미 검증한 단계용. 전체 이미지를 두 번 훑지 않습니다 |
| `copy_validated_rows` | 꺼져 있는 단계의 identity 경로 |

## 어디에 적용했나

`negative_inversion`, `validate_finite_pixels`, `working_to_srgb16`, `tone_mapping`,
`core/pointwise`(exposure·color matrix), `point_curve`, `color_mixer`, `color_grading`,
`primary_calibration`, `color_model`.

`working_to_srgb16` 은 clipped-component 합계를 블록마다 모아 더하므로 보고되는 숫자도
단일 스레드와 같습니다.

## 결과 (x64 Release, 16 논리 코어, 3278×4944)

| 단계 | 이전 | 이후 | 배수 |
|---|---|---|---|
| develop | 1,887 ms | **246 ms** | 7.7× |
| tone (조정 켬) | 2,057 ms | **285 ms** | 7.2× |
| 전체 export (조정 끔) | 4,995 ms | **3,001 ms** | 1.66× |
| 전체 export (조정 켬) | 4,170 ms | **2,437 ms** | 1.71× |
| **미리보기 경로**(output 제외, 조정 켬) | 약 4,112 ms | **약 721 ms** | 5.7× |

**출력 PNG16 은 두 구성 모두 SHA-256 이 변경 전과 동일합니다.**

- 조정 끔: `FDB7941EBEADD33F00503A2AFC053DD07722145F1BAB6D9E493721F7859D5A87`
- 조정 켬: `57961EF4186032864532CCE80D70B87D462504A1D7B6C36B2ADFE44EE2A3077B`

## 공간 필터 단계 — 다시 재고 나서 고쳤습니다

pointwise 단계를 정리한 뒤 실제 촬영본(5088×3401)의 **미리보기** 비용을 단계별로 다시 쟀습니다.
짐작으로 Texture 를 먼저 손댈 뻔했는데, 실제 범인은 따로 있었습니다.

| 미리보기 구성 | wall | 단계 비용 |
|---|---|---|
| identity | 550 ms | — |
| + Texture(선예도 0.6, 비네팅 0.3) | 1,393 ms | +844 ms |
| + GrainMend(1.0) | 2,024 ms | +1,474 ms |
| **+ FilmScanDenoise(0.7)** | **12,261 ms** | **+11,711 ms** |

FilmScanDenoise 하나가 identity 미리보기의 21배였습니다.

이 단계는 이미 512px 타일 구조이고, **각 타일은 apron 을 읽지만 자기 core 에만 씁니다.**
core 는 서로 겹치지 않으므로 타일 행을 코어에 나눠도 결과가 바뀔 수 없습니다. 타일 행 단위로
분할하고 타일 행마다 취소를 확인하도록 바꿨습니다.

Texture 의 blur 도 같은 모양이었습니다. `gaussian_transform` 이 이미 타일 구조이고 타일마다
`radius` 만큼의 apron 을 읽되 자기 core 에만 씁니다. 같은 방식으로 타일 행을 나눴고, grain 은
절대 좌표 해시라 행이 독립이며, vignette 은 좌표와 그 자리 픽셀만 봅니다. 타일마다 갱신하던
scratch peak 는 atomic 최댓값으로 모아 순차 때와 같은 숫자를 보고합니다.

| 미리보기 | 전부 순차 | 분할 | 배수 |
|---|---|---|---|
| FilmScanDenoise(0.7) | 15,004.7 ms | **2,949.7 ms** | 5.09× |
| Texture(선예도 0.6, 비네팅 0.3) | 3,904.7 ms | **774.2 ms** | 5.04× |
| identity | 2,997 ms | **552 ms** | 5.43× |

**픽셀은 모두 같습니다.** 근거는 논증이 아니라 측정입니다 —
`minimum_parallel_row_work_units` 를 올려 엔진 전체를 인라인으로 강제한 빌드와 통상 빌드가
같은 미리보기 픽셀 fingerprint 를 냅니다: FilmScanDenoise `3430ad44f47e1afd`,
Texture `1128b870586242f7`. 두 fingerprint 는 `native.develop_export_abi` 가 실촬영 fixture 로
계속 출력하므로 이후에도 확인 가능합니다.

실제 촬영본 export 결과 PNG16 SHA-256 도 이 모든 변경 전후로 같습니다
(frame_1 `1A4EB1A7…`, frame_12 `2ED77091…`).

## 남은 것

`output` 이 이제 export 시간의 대부분(약 86%)입니다. 내용은 WIC PNG encode(deflate)와
게시 뒤 전체 픽셀 readback 검증이며 둘 다 WIC 안의 단일 스레드 zlib 입니다. 인코더를 바꾸면
산출물 바이트가 달라지고 ADR-0004(OS API 우선)에 어긋나므로 이번 범위에서 손대지 않았습니다.
**미리보기 경로에는 이 비용이 없습니다.**

Local Dodge/Burn 도 분할했습니다. 여기는 타일이 아니라 **running-sum box blur** 이고, 가로
패스는 행마다, 세로 패스는 열마다 자기 줄의 합만 들고 갑니다. 줄 안의 연산 순서는 그대로이므로
합계가 달라지지 않습니다. 픽셀 적용도 마스크 대비 pointwise 입니다.

조정 하나당 `585 ms → 221 ms`(2.65배)이며, 사용자가 조정을 더할수록 그만큼 곱해집니다.
5배가 안 되는 것은 running-sum 이 메모리 대역폭에 묶여 있기 때문입니다. fingerprint
`7c8a60ab475f270d` 가 엔진 전역 인라인 강제 빌드와 같습니다.

ARM64 는 교차 빌드만 했고 실기 실행 증거가 아닙니다.

---

## 후속 (2026-08-18) — 아직 영속 풀이 아닙니다

`src/Native/core/parallel_rows.cpp:113` 은 **호출마다 `std::thread` 를 새로 만듭니다.**

```cpp
workers[started] = std::thread(
    [function, context, block]() noexcept { … });
```

화소 단계마다·타일마다 이것이 돕니다. 큰 이미지 한 장에서는 묻히지만,
**작은 프리뷰 프록시를 슬라이더 드래그 중에 초당 수십 번 돌릴 때** 드러납니다.

**할 것**: 영속 워커 풀 하나. 작업은 큐에 넣고 스레드는 살려 둡니다.

**지우지 말 것**: 지금 코드의 `catch (...)` → 인라인 실행 복구 경로.
스레드 생성 실패 시 그 블록의 행을 놓치지 않게 하는 것이고, 풀이 포화일 때 같은 역할을 합니다.

> 주의 **얼마나 빨라지는지는 재야 압니다.** 스레드 생성 비용은 수십 µs 급이라 **프록시 크기에서**
> 재야 보입니다. 계측기가 아직 없습니다 — [`../audit/13-performance-playbook.md`](../audit/13-performance-playbook.md) 2·3.1절.

**관련**: 화소 파이프라인에 **SIMD 가 없습니다**(히트 11개, 전부 `flatbed_frame_*` 3파일).
다만 SIMD 대상과 GPU 이식 대상이 정확히 같아서 **GPU 를 먼저** 하는 것으로 정했습니다 —
두 벌을 쓰면 서로 어긋납니다. 13번 3.3절.
