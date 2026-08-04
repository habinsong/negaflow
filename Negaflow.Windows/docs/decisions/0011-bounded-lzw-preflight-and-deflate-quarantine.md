# ADR-0011: LZW는 독립 사전 검사하고 Deflate는 검증기 전까지 격리한다

- 상태: 채택
- 날짜: 2026-08-04

## 문제

기존 TIFF preflight는 IFD와 strip/tile offset·byte count가 파일 범위 안인지 확인했지만 압축 payload의
code 의미까지 읽지 않았습니다. 따라서 LZW segment가 범위 안에 있어도 Clear/EOI 누락, 잘못된 사전
reference, 조기 bit-width 전환 오류나 실제 복원 길이 불일치를 WIC 호출 전에 구분할 수 없었습니다.

WIC가 성공을 반환했다는 사실만으로 strict compressed-stream validation을 주장할 수도 없습니다. 실제
로컬 검사에서 TIFF 구조와 segment 범위는 맞지만 Deflate stored-block 길이가 남은 payload와 모순되는
합성 파일을 Microsoft WIC가 성공으로 처리하고 작은 pixel payload를 반환했습니다. 이 관찰은 특정
Windows servicing 상태의 동작이며 모든 WIC 버전의 일반 계약으로 확대하지 않습니다. 다만 공식 문서에
압축 stream 무결성 검증 보장이 없으므로 제품 경계는 더 엄격해야 합니다.

## 결정

1. 첫 구조 preflight와 decoded-pixel 상한을 먼저 적용합니다. 작은 파일이 거대한 복원 크기를 주장하면
   압축 stream 전체를 스캔하기 전에 거부합니다.
2. 허용된 RGB/RGBA 16-bit LZW는 WIC 호출 전에 같은 read-only `IStream`에서 독립 의미 검사를 반드시
   통과해야 합니다. 일반 구조 확인용 `probe_tiff`의 기본은 빠른 metadata 검사로 유지하고 decoder가
   의미 검사를 opt-in합니다.
3. 검사기는 pixel을 복원하거나 문자열을 보유하지 않습니다. 4,096개 사전 항목에는 복원 문자열 길이만
   저장하고 segment별 기대 복원 byte 수와 비교합니다.
4. TIFF 6.0의 strip별 ClearCode/EOI, high-to-low bit order, 현재 code reference, 특수 forward case,
   entry 510/1022/2046 뒤 early-change와 entry 4094 한계를 적용합니다.
5. EOI 뒤 마지막 byte 안의 최대 7개 fill bit는 값과 무관하게 허용하지만 추가 byte는 거부합니다. 기대
   복원 길이 부족·초과와 산술 overflow도 fail-closed로 거부합니다.
6. 전체 LZW compressed segment 기본 작업량은 512 MiB로 제한하고 segment 사이와 4,096 code마다
   `stop_token`을 확인합니다. 구현은 16 KiB 입력 버퍼와 약 32 KiB 길이 사전만 사용합니다.
7. Deflate tag 8은 독립 validator나 검토된 최소 dependency가 생기기 전까지 정상·손상 여부와 무관하게
   WIC decode allowlist에서 제외합니다. 구조 probe는 tag를 보고할 수 있지만 pixel decode는
   `unsupported_layout`으로 끝납니다.
8. 결과에는 압축 segment 합계, 실제 검증 byte, LZW code 수, 검증된 복원 byte와 완료 boolean을
   경로·파일명 없이 기록합니다.
9. 외부 LZW/Deflate source나 library를 추가하지 않습니다. 자체 코드는 길이 기반 validator이고 실제
   pixel decompression은 검증 뒤 Microsoft 기본 WIC가 담당합니다.
10. 일반 이미지 SHA-256 기본 `끔`, 공급망 hash 필수 정책과 출력 TIFF의 무압축 기본값은 바꾸지 않습니다.

## 결과

범위 안이지만 의미적으로 손상된 LZW는 WIC와 pixel allocation 전에 차단됩니다. 압축 폭탄형 입력은
decoded-byte 한도와 compressed-input 작업량 한도를 서로 다른 단계에서 차단하며, 정상 LZW의 모든
compressed byte와 기대 복원 byte가 accounting됩니다. 새 runtime dependency와 공개 C ABI symbol은
생기지 않았습니다.

Deflate 호환성은 의도적으로 줄었습니다. 이는 “지원”을 과장하지 않는 임시 fail-closed 경계이며, 실제
Deflate 입력 필요성과 독립 검증 비용이 확인되면 자체 최소 validator와 zlib/libtiff dependency gate를
다시 비교합니다.

## 현재 범위 밖

- WIC `CopyPixels` 호출 내부를 선점하는 취소나 hard CPU deadline
- Deflate/zlib stream 독립 검증과 Deflate 지원 복원
- 모든 TIFF photometric, YCbCr subsampling과 범용 LZW pixel decompression
- multi-IFD chain, tile streaming, fuzz/ASan과 실제 ARM64 실행
- 출력 TIFF의 LZW/Deflate compression 선택

## 권리와 근거

TIFF 6.0 문서의 형식 규칙을 바탕으로 독립 구현했고 문서 pseudocode나 외부 decoder source를 복사·번역하지
않았습니다. 테스트 TIFF는 저장소 test 코드가 실행 중 합성합니다. LZW 원 특허와 후속 LZW/TIFF 관련
특허는 제한적으로 claim을 대조했지만 이는 법률 의견이나 freedom-to-operate 보증이 아닙니다. 출처와
구체적인 한계는 [`../research/compressed-tiff-preflight-sources.md`](../research/compressed-tiff-preflight-sources.md)에
기록합니다.
