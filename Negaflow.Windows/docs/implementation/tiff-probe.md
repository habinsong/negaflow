# 제한형 TIFF 사전 검사

## 목적

WIC나 libtiff가 픽셀과 복잡한 메타데이터를 해석하기 전에 파일이 주장하는 크기와 첫 IFD 구조를
고정 메모리로 검사합니다. 이 단계는 TIFF 디코더가 아니며 원본을 수정하거나 출력 파일을 만들지 않습니다.

## 원본 불변 계약

- `CreateFileW`를 `GENERIC_READ`로만 호출합니다.
- write sharing은 허용하지 않아 검사 중 동시 byte mutation을 막습니다.
- 파일 크기에 비례하는 메모리를 할당하지 않습니다.
- offset 기반 고정 크기 read만 수행합니다.
- 오류 JSON에 원본 경로를 넣지 않습니다.
- 합성 read-only Unicode path test와, 개발 검증에서만 명시적으로 켠 실제 TIFF SHA-256/수정 시각
  비교로 검증합니다. 제품 이미지 SHA-256 기본값은 `끔`입니다.

## 처리 순서

1. 파일을 읽기 전용으로 열고 64-bit 크기를 얻습니다.
2. `II`/`MM` byte order와 version 42/43을 확인합니다.
3. BigTIFF이면 offset-size 8과 reserved 0을 확인합니다.
4. 첫 IFD offset, entry count, 전체 IFD byte 범위를 checked 64-bit로 검증합니다.
5. entry를 하나씩 읽어 type width, count×width, 외부 value 범위를 검증합니다.
6. 핵심 tag 중복과 type을 검증하고 dimensions/layout을 수집합니다.
7. strip/tile offset과 byte-count 배열의 개수 및 각 실제 데이터 범위를 확인합니다.
8. packed raster와 내부 RGBA32F 예상 크기를 overflow 없이 계산합니다.
9. 다음 IFD가 있으면 조용히 첫 페이지만 선택하지 않고 현재 정책 오류를 반환합니다.

## 현재 제한값

| 제한 | 기본값 | 목적 |
|---|---:|---|
| file bytes | signed 64-bit 최대 | Windows file offset 표현 범위 |
| first IFD entries | 4,096 | 비정상 metadata loop 제한 |
| strip/tile segments | 1,048,576 | 반복 I/O와 table 폭증 제한 |
| single non-segment tag | 64 MiB | 거대 private metadata 제한 |
| ICC profile | 16 MiB | profile bomb 제한 |
| RGBA32F working estimate | 32 GiB | 다음 단계 allocation admission 제한 |

이 값은 Windows v1 probe의 방어 envelope입니다. 최종 제품의 device별 memory reservation 정책이나
지원 가능한 최대 사진 크기를 뜻하지 않습니다. 호출자는 더 작은 budget을 전달할 수 있습니다.

## 수집 결과

- Classic/BigTIFF
- little/big endian
- file/IFD bytes
- width/height
- SamplesPerPixel, BitsPerSample, SampleFormat
- Compression, PhotometricInterpretation, PlanarConfiguration, Orientation
- stripped/tiled organization과 segment 수
- ICC profile byte count
- packed raster와 RGBA32F working byte estimate

## 오류 분류

header, BigTIFF header, IFD offset/count, truncated IFD, invalid/duplicate tag, 외부 tag 범위,
tag/segment/memory limit, dimensions/layout, 다중 directory를 서로 다른 code로 반환합니다. 디코더
내부 메시지나 Win32 error text를 사용자 오류로 그대로 노출하지 않습니다.

## 현재 비범위

- LZW/Deflate 해제
- 실제 pixel decode
- EXIF/GPS/SubIFD traversal
- ICC 내용 검증
- WIC codec identity allowlist
- libtiff fallback
- 다중 페이지 사용자 경험
- atomic export

## 검증 corpus

- synthetic Classic little endian
- synthetic Classic big endian
- synthetic BigTIFF big endian
- synthetic Classic tiled little endian과 tile count 불일치
- truncated/invalid header와 IFD
- out-of-range external tag와 strip data
- duplicate tag, oversized ICC, memory limit, multi-IFD
- 저장소의 실제 16-bit big-endian uncompressed TIFF 4개
- 사용자 scanner의 5088×3401 RGB/RGBA 16-bit TIFF 15개

사용자 scanner corpus는 저장소로 복사하지 않았고, tracked 문서에는 파일명·경로·SHA-256을 남기지
않았습니다. 구조적 범위와 원본 불변 결과만 `verification/2026-08-04-local-tiff-corpus.md`에 기록합니다.
