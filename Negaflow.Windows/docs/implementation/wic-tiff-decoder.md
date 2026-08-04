# WIC TIFF 디코더 구현

## 책임 경계

`src/Native/imageio`는 TIFF byte를 색상 변환 전 16-bit sample로 materialize하는 일만 담당합니다.
ICC 해석 정책, scanner role과 working float 변환은 `src/Native/imaging`에 있습니다.

```text
read-only IStream 1회 open
  → 같은 stream의 bounded TIFF 구조 preflight
  → decoded-byte 상한 선검사
  → LZW이면 같은 stream의 독립 code-stream 의미 preflight
  → Microsoft 기본 WIC TIFF decoder 확인
  → 48bpp RGB 또는 64bpp RGBA/PRGBA sample
  → embedded ICC bytes 추출·구조 검증
  ├→ 소유형 API: DecodedImage
  └→ streaming API: WicTiffRowSink의 begin/write/complete
```

## 파일 구성

- `decoded_image.h/.cpp`: decoder와 무관한 소유형 16-bit 이미지 모델
- `wic_tiff_decoder.h/.cpp`: Windows WIC adapter, 소유형/streaming API와 오류·한도
- `icc_profile.h/.cpp`: WIC 밖에서 실행되는 bounded ICC 구조 검사

WIC COM object, stream과 decoder handle은 함수 밖으로 나가지 않습니다.

## 입력 allowlist

현재 pixel decode가 허용하는 TIFF는 다음 조건을 모두 만족해야 합니다.

- single IFD/frame
- orientation 1
- RGB photometric (`2`)
- contiguous planar (`1`)
- unsigned integer 16-bit sample
- RGB 3-channel 또는 RGB+alpha 4-channel
- compression none (`1`) 또는 LZW (`5`)
- 4-channel이면 ExtraSamples가 associated (`1`) 또는 unassociated (`2`)

조건 밖 입력은 WIC에 맡겨 추측하지 않고 명시적으로 거부합니다.

Deflate (`8`)는 WIC가 형식상 지원하더라도 현재 allowlist에서 격리합니다. 구조상 범위가 맞지만 stored
block 길이가 segment와 모순되는 합성 입력을 로컬 Microsoft WIC가 성공으로 처리한 관찰이 있었고,
Microsoft 문서는 compressed stream 무결성의 엄격한 검증을 계약하지 않습니다. 독립 검증기나 검토된
최소 dependency가 생기기 전에는 정상 Deflate도 같은 `unsupported_layout` 경계에서 거부합니다.

## LZW 의미 사전 검사

LZW 입력은 구조 검사와 decoded-byte 한도를 먼저 통과한 뒤 WIC 호출 전에 다시 같은 read-only stream을
검사합니다. 검사기는 pixel을 만들지 않고 4,096개 사전 항목의 **복원 문자열 길이**만 보유합니다.

- 각 strip/tile은 ClearCode `256`으로 시작하고 EOI `257`로 끝나야 함
- literal, 이미 정의된 사전 code와 현재 다음 code인 특수 forward case만 허용
- TIFF 6.0 early-change에 따라 entry 510/1022/2046 뒤 10/11/12-bit로 전환
- entry 4094 뒤에는 EOI 또는 ClearCode만 허용하고 Clear 뒤 9-bit로 재설정
- code는 byte 안에서 high-to-low 순서로 읽고 segment 밖을 읽지 않음
- strip/tile geometry와 bit depth로 계산한 기대 복원 byte 수와 정확히 일치해야 함
- EOI 뒤 마지막 byte의 fill bit 값은 무시하지만 추가 byte는 허용하지 않음
- 전체 LZW compressed segment 기본 상한은 512 MiB이며 4,096 code마다 취소를 확인

검사 결과는 `compressed_segment_bytes`, `compressed_bytes_validated`, `lzw_code_count`,
`lzw_decoded_bytes_validated`, `lzw_code_streams_validated`로 남습니다. 일반 `--probe-tiff`는 빠른 구조
검사만 수행하고, 실제 WIC LZW decode 경로에서 의미 검사가 필수입니다. 자세한 책임과 형식은
[`compressed-tiff-preflight.md`](compressed-tiff-preflight.md)에 있습니다.

## decoder 고정과 읽기 전용 처리

- 파일은 `SHCreateStreamOnFileEx`의 read-only와 share-deny-write로 엽니다.
- `IStream`을 random-access reader로 감싸 preflight를 수행하고 position을 0으로 되돌립니다.
- WIC decoder에는 같은 `IStream` instance를 전달하므로 path를 다시 열지 않습니다.
- `CreateDecoder`에 TIFF container와 `GUID_VendorMicrosoftBuiltIn`을 지정합니다.
- 실제 decoder CLSID가 `CLSID_WICTiffDecoder`인지 다시 확인합니다.
- frame count는 정확히 1이어야 합니다.
- WIC가 보고한 치수는 preflight 치수와 같아야 합니다.
- source가 목표 48/64bpp 형식과 다를 때만 WIC format converter를 사용하며 그 사실을 기록합니다.

## ICC 처리

frame의 color context를 bounded 개수만 요청합니다. profile context가 있으면 bytes를 두 단계로
조회하고 TIFF tag가 주장한 길이와 같은지 확인합니다. 그 뒤 다음을 검사합니다.

- profile 전체 크기와 header declared size 일치
- `acsp` signature
- 최대 tag 수
- tag table과 payload 범위·정렬
- 중복 tag signature
- 허용되지 않은 payload overlap

profile bytes는 변환하지 않고 `DecodedImage`에 보존합니다. 개별 ICC의 재배포 권리를 얻었다고
간주하지 않습니다.

## 메모리와 실패 계약

- decoded pixel 기본 상한: 512 MiB
- LZW compressed input 검사 기본 상한: 512 MiB
- ICC 기본 상한: 16 MiB
- color context 기본 상한: 4개
- `width × height × channel × 2`를 checked 64-bit로 계산하고 format 변환, ICC 추출,
  sample buffer 할당과 `CopyPixels`보다 먼저 상한을 적용
- WIC `CopyPixels`가 받는 `UINT` 범위를 넘는 버퍼는 거부
- allocation 실패와 WIC decode 실패를 구분
- `CopyPixels` 실패 시 부분 sample을 비워 실패 결과에 pixel payload를 노출하지 않음
- 오류 JSON에는 사용자 경로를 넣지 않음

`WicTiffDecodeControl`은 행 묶음 크기, C++20 `stop_token`, 진행률 observer를 받습니다. 행 묶음 전후와
WIC 호출 사이에서 취소를 확인하고, 진행률은 `0 → completed rows → total rows`로 단조 증가합니다.

두 소비 방식의 메모리 계약은 의도적으로 다릅니다.

- `decode_tiff_with_wic`: 기존 소유형 API입니다. 기본값은 `UINT` 범위에 들어가는 프레임을 한 번에
  복사합니다. 행 묶음을 명시하면 ROI `CopyPixels`를 반복하지만 최종 `DecodedImage.samples`는 여전히
  전체 프레임을 소유합니다.
- `decode_tiff_rows_with_wic`: 양수 행 묶음과 `WicTiffRowSink`가 필수인 streaming API입니다. descriptor와
  ICC는 결과에 보존하지만 decoded sample vector는 만들지 않습니다. 재사용 가능한 한 묶음 버퍼만 sink에
  전달합니다.

streaming sink는 metadata가 확정된 뒤 `begin`을 한 번 받고, 각 성공 묶음마다 `write`, 그 뒤 성공·취소·
실패를 나타내는 terminal `complete`를 정확히 한 번 받습니다. sink가 묶음을 거부하면
`row_sink_failed`, stop이 요청된 경우에는 `cancelled`가 됩니다. 성공적으로 sink가 받아들인 행만
`completed_rows`에 포함하며, 실패 결과에는 decoded sample payload가 없습니다.

WIC codec이 ROI마다 실제 압축 데이터를 얼마나 다시 해제하는지는 구현체 의존입니다. 따라서 64행은 현재
CLI와 코퍼스 검증에 사용하는 application chunk일 뿐, codec CPU 비용까지 입증한 범용 제품 기본값은
아닙니다.

## 검증된 입력

- 합성 Classic/BigTIFF, little/big endian, strip/tile와 손상 변형
- 수동 구성한 정상 RGB16 LZW와 정확한 sample 값
- 9→10→11→12-bit early-change 경계를 모두 지나는 300행 LZW와 exact sample 값
- entry 4094 뒤 12-bit Clear·9-bit reset과 유효한 `code == next` forward case의 exact sample 값
- 5행 LZW에서 2행 묶음과 whole-frame decode의 exact sample 일치, 마지막 1행 remainder
- 첫 행 뒤 취소 시 단일 terminal `cancelled`, completed row 1, sample payload 0
- streaming sink의 exact sample 일치, 단일 terminal 완료, sink 거부 시 `row_sink_failed`
- 저장소 631×403 TIFF의 37행 묶음 11회와 whole-frame/streaming exact sample·ICC 일치
- 압축 segment 끝이 잘린 LZW를 preflight에서 거부하고 sample을 만들지 않는 경로
- Clear/EOI 누락, 잘못된 forward code와 trailing data를 독립 preflight에서 거부하는 경로
- 8-byte LZW 작업량 한도와 이미 요청된 취소를 WIC 전에 거부하는 경로
- 정상·손상 Deflate를 모두 WIC 전에 격리하는 경로
- 8192×8192 RGB16을 주장하는 작은 LZW 입력을 64 MiB 한도로 거부하는 사전 할당 경로
- 저장소의 16-bit big-endian RGB TIFF
- 사용자 5088×3401 TIFF 15개
  - RGB 무압축 9개
  - RGBA LZW 6개, 1,134 strips, associated opaque alpha, ICC 포함

사용자 코퍼스는 15/15가 native 16-bit 형식으로 decode됐고 WIC format conversion은 0건이었습니다.
64행 streaming 경로도 15/15 성공했으며 whole-frame 기준 경로와 최종 working float pixel이 모두 exact
일치했습니다. streaming 결과가 full decoded sample vector를 보유하지 않음도 확인했습니다. 관찰된 최대
application-owned WIC copy buffer는 2,605,056 bytes, 한 파일의 최대 `CopyPixels` 횟수는 54회였습니다.
초기 코퍼스 검증에서는 원본 크기·수정 시각·속성·SHA-256이 모두 유지됐습니다. 압축 사전 검사
재검증은 SHA-256을 끈 채 크기·수정 시각·속성 변화 0건을 다시 확인했습니다.

## 남은 위험

- Deflate 독립 검증기가 없어 정상 Deflate도 현재 격리됨
- WIC 내부 압축 해제의 CPU 시간·deadline과 호출 중 선점 취소 한도 미구현
- multi-IFD 정책 미완료
- 소유형 API의 4 GiB 초과 decoded buffer와 BigTIFF full decode 미지원
- tile streaming과 downstream 전체 working buffer 제거 미구현
- WIC servicing version에 따른 결과 재현성 관리
- independent decoder readback 비교 미실시
- network filesystem과 unusual `IStream` 구현의 seek/stat semantics 미검증
- LZW 의미 검사는 현재 WIC RGB16 allowlist의 안전 경계이며 모든 TIFF photometric/subsampling을
  지원하는 범용 LZW decoder가 아님

## 공식 API 근거

- [IWICBitmapSource::CopyPixels](https://learn.microsoft.com/en-us/windows/win32/api/wincodec/nf-wincodec-iwicbitmapsource-copypixels): ROI, caller-owned buffer, stride와 per-call buffer 크기 계약
- [Windows Imaging Component 동작](https://learn.microsoft.com/en-us/windows/win32/wic/-wic-howwicworks): 실제 pixel 생성과 codec object 수명은 decoder 구현이 소유
