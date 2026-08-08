# 압축 TIFF LZW 의미 사전 검사와 Deflate 격리

## 책임 경계

압축 사전 검사는 WIC를 대체하는 pixel decoder가 아닙니다. TIFF 구조와 segment geometry는 기존
`tiff_probe`, LZW code 의미는 작은 내부 validator, 실제 16-bit pixel decode는 Microsoft WIC가 각각
담당합니다.

```text
read-only IStream
  → TIFF 구조·segment 범위 검사
  → width × height × channels × 2 decoded-byte 한도
  → compression 1: WIC 진입
  → compression 5: segment별 LZW 의미·복원 길이 검사 → WIC 진입
  → compression 8: unsupported_layout로 격리
```

## 파일 구성

- `src/Native/core/tiff_probe.cpp`: segment 합계, geometry와 기대 복원 byte 계산, 상태 집계
- `src/Native/core/tiff_lzw_validator.h/.cpp`: 한 segment의 bit/code 상태 기계
- `src/Native/imageio/wic_tiff_decoder.cpp`: cheap limit 순서, LZW 검사 필수화와 Deflate allowlist 제외
- `tests/fixtures/tiff/synthetic_wic_tiff.cpp`: 외부 binary 없이 실행 시 합성하는 정상·손상 stream
- `tests/Native.UnitTests/wic_tiff_decoder_tests.cpp`: WIC 진입 전 실패와 정상 exact pixel 계약

내부 LZW header는 public include tree에 설치하지 않습니다. WIC adapter, TIFF parser와 validator가 서로의
COM handle이나 pixel ownership을 소유하지 않아 한 type에 I/O·형식·decode 책임이 몰리지 않습니다.

## 구조 단계와 작업 순서

첫 `probe_tiff`는 모든 strip/tile offset과 byte count의 범위·개수·합계를 확인합니다. decoder는 그 결과로
`width × height × samples × 2`를 checked 64-bit로 계산하고 512 MiB decoded-pixel 한도를 먼저 적용합니다.
이 순서 때문에 수 byte짜리 LZW payload가 수백 MiB 출력을 주장하는 입력은 code scan이나 pixel allocation
전에 끝납니다.

LZW일 때만 같은 reader로 두 번째 probe를 수행하며 `validate_lzw_code_streams=true`와 decode의
`stop_token`을 전달합니다. 전체 compressed segment 합계가 기본 512 MiB를 넘으면 첫 segment를 읽기
전에 `compressed_data_limit_exceeded`가 됩니다.

## segment별 기대 복원 길이

지원된 RGB/RGBA 16-bit contiguous TIFF에서는 다음 값을 정확히 계산합니다.

- strip: `ceil(width × bits-per-pixel / 8) × 실제 strip rows`
- 마지막 strip: image height에서 이미 지난 row를 뺀 나머지만 사용
- tile: `ceil(tile width × bits-per-pixel / 8) × tile length`
- planar 입력을 직접 검사할 때는 segment index에서 plane과 plane별 strip/tile index를 분리

현재 WIC pixel allowlist는 contiguous RGB/RGBA 16-bit라 subsampled YCbCr 같은 범용 TIFF layout을
지원한다고 주장하지 않습니다.

## LZW 상태 기계

`MsbBitReader`는 최대 16 KiB씩 segment 범위 안에서 읽고 code를 high bit부터 꺼냅니다. validator는
4,096개 `uint64_t` 길이 사전만 사용합니다.

1. 첫 code가 ClearCode `256`인지 확인합니다.
2. Clear 뒤 첫 data code는 literal `0..255` 또는 EOI `257`만 허용합니다.
3. 이후 literal, 이미 생성된 사전 entry 또는 `code == next_dictionary_code`인 표준 forward case의 복원
   길이를 계산합니다.
4. 새 entry 길이는 `previous_length + 1`이며 overflow와 기대 복원 byte 초과를 즉시 거부합니다.
5. entry 510, 1022, 2046 저장 뒤 다음 code 폭을 각각 10, 11, 12-bit로 올립니다.
6. entry 4094를 채운 뒤에는 EOI 또는 Clear만 허용합니다. Clear는 사전 index와 폭을 9-bit로 재설정합니다.
7. EOI에서 누적 복원 byte가 기대값과 정확히 같고 segment의 마지막 byte까지 소비됐는지 확인합니다.
   마지막 byte 안의 최대 7개 fill bit 값은 규격이 0으로 강제하지 않으므로 무시하고 추가 byte는 거부합니다.

검사기는 실제 문자열, pixel 또는 predictor 결과를 만들지 않습니다. Predictor가 있어도 LZW가 복원하는
packed byte 수 자체는 바뀌지 않습니다.

## 상태와 진단값

새 preflight 상태는 다음과 같습니다.

- `compressed_data_limit_exceeded`: LZW 입력 작업량 상한 초과
- `invalid_compressed_data`: code 의미, 복원 길이 또는 trailing data 불일치
- `cancelled`: 의미 검사 전·중 취소 관찰

WIC 결과와 관련 CLI JSON은 다음 값을 전달합니다.

- `compressed_segment_bytes`
- `compressed_bytes_validated`
- `lzw_code_count`
- `lzw_decoded_bytes_validated`
- `lzw_code_streams_validated`

일반 `--probe-tiff`는 compressed segment 합계만 보고하며 payload 전체를 읽지 않습니다. 실제
`--decode-tiff-wic`, scanner 준비와 export의 LZW 경로에서만 의미 검사가 필수로 실행됩니다.

## 취소와 시간 한계

segment 시작 전과 4,096 code마다 `stop_token`을 확인합니다. 이 검사 자체는 bounded cooperative
cancellation을 제공하지만, 이후 동기식 WIC `CopyPixels` 호출 안쪽을 선점하거나 시간을 중단할 수는
없습니다. 따라서 현재 경계는 compressed byte 작업량과 decoded memory를 제한할 뿐 hard CPU deadline을
보증하지 않습니다.

## Deflate 격리

Compression tag 8은 구조 probe를 통과할 수 있지만 WIC pixel allowlist에는 없습니다. 정상 fixture와
stored-block 길이가 모순되는 손상 fixture 모두 WIC decoder 생성 전에 `unsupported_layout`로 끝나며
sample을 공개하지 않습니다. 독립 Deflate validator 없이 정상 입력만 구분할 수 없기 때문에 의도적으로
같은 경계를 사용합니다.

## 검증 범위

- 정상 1×1 RGB16 LZW의 9 compressed byte, 8 code, 6 decoded byte exact accounting
- 300행 literal stream으로 9→10→11→12-bit 경계와 전체 WIC pixel exact 검증
- entry 4094 직후 12-bit Clear와 9-bit 재시작, `code == next` forward case의 exact pixel 검증
- EOI 뒤 마지막 byte의 nonzero fill bit 허용과 추가 trailing byte 거부
- Clear/EOI 누락, 복원 길이 부족·초과, 잘못된 forward code, trailing byte와 잘린 segment 거부
- compressed-input 8-byte 제한과 이미 요청된 취소
- 거대한 decoded 크기 주장을 의미 scan 전에 memory limit으로 거부
- 정상·손상 Deflate의 동일 격리
- 사용자 LZW 6개와 저장소 TIFF를 포함한 전체/streaming parity

세부 실행 증거는
[`../verification/2026-08-04-compressed-tiff-preflight.md`](../verification/2026-08-04-compressed-tiff-preflight.md)에
있습니다.
