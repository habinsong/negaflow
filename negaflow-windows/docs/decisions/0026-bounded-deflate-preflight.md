# ADR-0026: Deflate는 독립 의미 검사 뒤 WIC에 전달한다

- 상태: 채택
- 날짜: 2026-08-09

## 문제

TIFF compression tag `8`은 macOS 제품 입력 범위에 있지만, 기존 Windows 경로는 독립 무결성 검사가
없어 정상 입력까지 격리했습니다. WIC 성공만으로 손상 stream 거부를 보장할 수는 없습니다.

## 결정

같은 read-only stream에서 각 strip/tile의 zlib wrapper와 Deflate stored/fixed/dynamic block을 독립
검사합니다. CMF/FLG, 32 KiB 이하 window, Huffman table, LZ77 distance, 예상 복원 byte 수, Adler-32와
segment 끝의 정확한 일치를 확인한 경우에만 Microsoft 기본 WIC decoder로 전달합니다. preset dictionary는
거부하고, 전체 compressed input은 기본 512 MiB로 제한하며 복원 중 `stop_token`을 관찰합니다.

검사기는 32 KiB sliding window와 고정 크기 table만 사용합니다. 새 third-party dependency나 공개 C ABI는
추가하지 않으며 실제 제품 pixel materialization은 계속 WIC가 담당합니다.

## 결과와 한계

정상 tag `8` 입력 호환성을 복원하면서 손상 block 길이, 잘못된 code/distance, 복원 길이 불일치,
checksum 불일치와 trailing data를 WIC 전에 거부합니다. WIC `CopyPixels` 내부의 hard CPU deadline과
선점 취소, 모든 TIFF photometric/subsampling 지원은 별도 범위입니다.

형식 근거는 RFC 1950과 RFC 1951이며 외부 decoder source나 pseudocode를 복사하지 않았습니다.
