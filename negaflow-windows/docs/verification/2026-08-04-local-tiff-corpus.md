# 2026-08-04 사용자 TIFF 코퍼스 검증

## 범위와 원본 정책

- 입력: 사용자가 직접 컬러 네거티브 필름을 스캔한 TIFF 15개
- 위치: 사용자가 지정한 로컬 TIFF 코퍼스(경로는 기록하지 않음)
- 전체 크기: 1,677,073,728 bytes
- 실행 산출물: x64 Release `negaflow-cli`
- 원본 정책: 복사·수정·삭제·decode 결과 저장·저장소 반입을 하지 않음
- 추적 문서 정책: 실제 파일명, 절대 경로와 SHA-256 값은 기록하지 않음

사용 허가는 개발·검증 범위로만 해석합니다. 원본 사진이나 embedded ICC의 재배포 권리가 생긴
것으로 간주하지 않으며 tracked fixture나 배포 payload에 넣지 않습니다.

## 구조 결과

모든 파일은 5088×3401, Classic TIFF, stripped, 16-bit unsigned integer, RGB photometric,
contiguous planar, orientation 1입니다.

| cohort | 파일 수 | byte order | sample | compression | segment | ICC | 파일 크기 |
|---|---:|---|---|---|---:|---:|---:|
| scanner 원본형 | 9 | little endian | RGB 3×16-bit | none (`1`) | 1 | 없음 | 각 103,825,968 bytes |
| LZW/ICC형 | 6 | big endian | RGBA 4×16-bit | LZW (`5`) | 1,134 | 각 572 bytes | 118,944,286~128,452,302 bytes |

LZW/ICC형은 ExtraSamples `1`, 즉 associated alpha를 선언합니다. 실제 decode 후 alpha minimum과
maximum은 모든 파일에서 65535여서 완전 불투명임을 확인했습니다.

embedded profile의 비식별 구조는 다음과 같습니다.

- ICC v4, monitor class, RGB data color space, XYZ PCS
- matrix/TRC profile
- 11 tags, 572 bytes
- profile bytes 자체는 저장하거나 문서에 포함하지 않음

## 실행한 단계

각 파일에 reference lane과 현재 streaming lane을 독립 적용했습니다.

1. 크기, 수정 시각, 파일 속성과 SHA-256 기록
2. reference: 같은 read-only `IStream`의 bounded probe와 whole-frame WIC decode
3. reference: ICC 없음 direct-linear, ICC 있음 Windows ICM→sRGB16→EOTF로 RGBA float32 생성
4. streaming: 새 read-only `IStream`에서 64행 WIC copy를 scanner-color sink에 직접 전달
5. streaming: full decoded source 없이 같은 transform으로 RGBA float32 생성
6. reference/streaming의 최종 float bit를 pixel마다 exact 비교
7. streaming CLI JSON과 buffer 관측값 확인
8. 원본의 같은 항목과 SHA-256 재계산 후 전후 비교

SHA-256은 이 일회성 개발 검증에서 원본 불변을 입증하려고 명시적으로 사용했습니다. 제품 이미지 설정의
기본값은 `끔`이며 일반 decode/working 경로는 hash를 계산하지 않습니다.

## 결과

| 검사 | 결과 |
|---|---:|
| probe | 15/15 성공 |
| WIC decode | 15/15 성공 |
| WIC format conversion | 0/15 |
| working 변환 | 15/15 성공 |
| 64행 streaming 변환 | 15/15 성공 |
| whole-frame/streaming 최종 float exact 일치 | 15/15 |
| streaming 결과의 full decoded sample 보유 | 0/15 |
| untagged direct-linear 경로 | 9/9 |
| embedded ICC Windows ICM 경로 | 6/6 |
| JSON parse | 15/15 |
| SHA-256 동일 | 15/15 |
| 크기 동일 | 15/15 |
| `LastWriteTimeUtc` 동일 | 15/15 |
| 파일 속성 동일 | 15/15 |

15장의 working RGBA32F 총 byte 수는 4,153,029,120 bytes입니다. streaming CLI 15개 집계는 약
14.4초, whole-frame/streaming exact parity 도구는 약 22.3초였습니다. warm cache, 파일 시스템과 process
시작 비용을 통제하지 않았으므로 성능 benchmark로 사용하지 않습니다.

## 메모리 관찰

기존 whole-frame 경로에서 각 이미지의 working RGBA32F는 276,868,608 bytes이며 다음 source와
intermediate가 추가로 필요했습니다.

- RGB형 decoded source: 103,825,728 bytes
- RGBA형 decoded source: 138,434,304 bytes
- ICC형 ICM용 packed RGB: 103,825,728 bytes
- ICC형 sRGB16 intermediate: 103,825,728 bytes

64행 streaming 경로에서는 full decoded source와 full-frame ICC intermediate를 보유하지 않습니다.

- 최대 application-owned WIC copy buffer: 2,605,056 bytes
- 최대 ICC conversion temporary: 3,907,584 bytes
- 한 파일의 최대 WIC copy 횟수: 54
- 최종 working RGBA32F: 276,868,608 bytes

최종 working buffer와 WIC codec 내부 allocation은 남아 있습니다. 현재 15개가 성공했다는 사실은
저메모리 장치의 전체 process budget을 입증하지 않습니다.

## 조사 중 발견한 Windows API 경계

WIC의 고수준 `IWICColorTransform`은 저장소 ICC fixture에서는 동작했지만 이 코퍼스의 ICC v4에는
1×1 RGB 입력에서도 `WINCODEC_ERR_UNSUPPORTEDPIXELFORMAT`을 반환했습니다. Windows ICM의
`CreateMultiProfileTransform`과 `TranslateBitmapBits`는 동일 profile을 처리했습니다.

`WCS_ALWAYS` float 경로는 동일 sRGB profile 간 중립 입력 보존이 충분하지 않아 채택하지 않았습니다.
현재 ICM 경로에는 16-bit output intermediate가 있고 CLI가 이를 명시합니다.

## 아직 입증하지 않은 것

- macOS ColorSync golden과 Windows ICM의 channel/ΔE 동등성
- 네거티브 반전 이후의 색 정확도와 화면 품질
- 독립 Deflate 검증 또는 dependency 결정과 WIC 압축 해제 CPU deadline
- tile decode와 최종 working/downstream streaming
- WIC 압축 해제·ICM callback 사이의 CPU deadline과 실제 취소 latency
- export/ICC embed/readback
- 실제 ARM64 장치에서 같은 15개 실행

따라서 이 기록은 사용자 코퍼스를 원본 불변 상태로 16-bit decode하고 working float buffer까지 만들 수
있음을 입증합니다. device-accurate color, ColorSync parity나 완성 제품 품질은 아직 입증하지 않습니다.

## 압축 사전 검사 체크포인트 재검증

같은 날 LZW 의미 사전 검사 도입 뒤 사용자 TIFF 15개와 권리 확인된 저장소 fixture 1개를 합친 16개를
x64 Release로 다시 읽었습니다. 이번 재검증은 일반 이미지 SHA-256을 명시적으로 끈 채 수행했으며
파일명·경로·hash를 기록하지 않았습니다.

| 검사 | 결과 |
|---|---:|
| 전체/64행 streaming 최종 float exact parity | 16/16 |
| 사용자 LZW 의미 사전 검사 후 decode | 6/6 |
| streaming 결과의 full decoded sample 보유 | 0/16 |
| 사용자 원본 크기·수정 시각·속성 변화 | 0/15 |
| SHA-256 계산 | 0 |

16개 전체 parity 실행은 통제되지 않은 warm-cache 관찰에서 약 34.9초였습니다. 사용자 LZW 한 개의 CLI
관찰은 의미 검사와 WIC 전체 decode가 약 1.66초, 64행 scanner→working 준비 전체가 약 2.61초였습니다.
이는 비교 benchmark나 성능 보증이 아닙니다. LZW compressed byte 전체와 기대 복원 byte 전체가
accounting됐고 code 수가 0보다 큼을 JSON으로 확인했습니다.

이 체크포인트로 LZW code-stream 의미 검증 공백은 닫혔습니다. 아직 남은 압축 I/O 위험은 독립 Deflate
검증 또는 dependency 결정, WIC 호출 내부 압축 해제 CPU deadline·선점 취소와 실제 ARM64 실행입니다.
