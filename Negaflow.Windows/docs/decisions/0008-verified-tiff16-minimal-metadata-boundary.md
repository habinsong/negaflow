# ADR-0008: TIFF16 출력은 최소 메타데이터를 검증한 뒤 게시

- 상태: 채택
- 날짜: 2026-08-04

## 문제

M4 한 장 수직 경로는 16-bit TIFF 출력, ICC 삽입, metadata allowlist와 게시 전 readback을 요구합니다.
encoder가 성공했다는 사실만으로는 bit depth, compression, IFD 구성, source metadata 유출, 부분 파일과
목적지 덮어쓰기를 막았다고 볼 수 없습니다. PNG phase 0에서 확보한 출력 변환과 원자적 단일 파일 게시를
복제하지 않고 TIFF container 계약으로 확장해야 합니다.

macOS 기본 TIFF export는 sRGB, 16-bit, opaque, 무압축, dither 없음이며 기본 metadata policy는
`minimal`입니다. Windows 첫 단계도 이 기본 경로만 닫고 optional metadata·DPI·compression 조합은
후속 범위로 둡니다.

## 결정

1. 첫 TIFF 출력은 단일 IFD, stripped Classic TIFF, opaque unsigned RGB 16-bit, chunky planar,
   orientation 1, sRGB로 제한합니다.
2. `WorkingImage`에서 packed sRGB16으로 가는 변환과 등록 sRGB profile 로딩, pixel 쓰기와 exact
   readback은 PNG와 같은 작은 WIC 공통 모듈을 사용합니다. encoder와 decoder의 실제 CLSID 및
   `GUID_WICPixelFormat48bppRGB`를 확인합니다.
3. Microsoft WIC TIFF encoder의 `TiffCompressionMethod`를 `VT_UI1`의
   `WICTiffCompressionNone`으로 명시합니다. 기본값이나 codec 추측에 맡기지 않습니다.
4. `IWICBitmapFrameEncode::SetColorContexts`로 Windows 등록 표준 sRGB profile을 기록합니다. 게시 전
   TIFF tag 34675 존재, profile 길이와 decoder가 돌려준 ICC bytes의 exact 일치를 요구합니다.
5. source metadata는 복사하지 않습니다. 첫 IFD는 이미지 구조와 ICC에 필요한 고정 allowlist만
   허용하고 중복·알 수 없는 tag를 fail-closed로 거부합니다. Make, Model, Software, DateTime, Artist,
   Copyright, XMP, EXIF, GPS, IPTC와 private metadata pointer는 허용하지 않습니다.
6. 게시 전 bounded TIFF probe로 container·치수·sample·compression·orientation·strip byte 수와 단일
   IFD를 확인하고, 별도 IFD allowlist 검사와 Microsoft WIC 전체 pixel·ICC readback을 모두 수행합니다.
7. 목적지와 같은 디렉터리의 `CREATE_NEW` staging, flush, 기존 파일 비대체 게시 계약은 ADR-0007의
   검증된 구현을 그대로 재사용합니다.
8. source는 decode 전후에 file ID, 크기, 최종 수정 시각만 관찰합니다. 이 관찰은 content를 읽지 않으며
   source/artifact SHA-256은 계속 기본 `off`입니다. source가 읽는 동안 바뀌면 출력 전에 중단합니다.
9. PNG16과 TIFF16 CLI는 decode·color·develop orchestration을 공유합니다. 결과 JSON은 경로를 빼고
   단계별 byte 수, memory peak, wall time, 출력 검증 상태와 SHA mode를 기록합니다.

## 최소 IFD allowlist

현재 허용 tag는 다음 구조 tag와 ICC tag뿐입니다.

`254, 256, 257, 258, 259, 262, 266, 273, 274, 277, 278, 279, 282, 283, 284, 296, 317, 339, 34675`

WIC가 실제로 생성한 tag만 존재할 수 있으며, 이 목록은 source metadata 보존 정책이 아닙니다.
X/Y resolution 관련 구조 tag가 존재하더라도 source DPI를 전달하거나 별도 값을 주입하지 않습니다.

## 현재 범위 밖

- LZW/Deflate compression과 compression 선택 UI
- source metadata 전달, `all`, `removeLocation`, `copyrightOnly` 정책
- 사용자 지정 DPI, resize, sharpen, dither
- BigTIFF와 2 GiB 초과 artifact
- output encode/readback cancellation과 progress
- macOS pixel diff와 cross-platform 허용오차 manifest
- exposure·contrast·curve는 후속 ADR-0009 경계에서 구현됨
- 실제 ARM64 Windows에서의 WIC TIFF 실행

stage process CPU와 진단 전용 versioned fingerprint는 후속 ADR-0010에서 구현했습니다.

## 결과

한 장을 `TIFF probe/decode → scanner color → manual negative develop → sRGB16 → TIFF encode →
structure/metadata/pixel/ICC readback → publish`할 수 있습니다. 실패 시 검증 전 staging만 폐기하고 기존
목적지를 바꾸지 않습니다. 출력 adapter, 공통 WIC frame 지원, IFD 검사와 CLI orchestration은 서로 다른
파일에 있어 한 type이 decode·develop·container·filesystem 책임을 동시에 소유하지 않습니다.

fail-closed allowlist는 다른 Windows WIC servicing version이 새로운 정상 구조 tag를 생성할 때도 출력을
거부할 수 있습니다. 그 경우 tag를 무조건 허용하지 않고 생성 원인과 privacy 의미를 다시 검토합니다.

## 공식 근거와 권리

- [WIC TIFF format overview](https://learn.microsoft.com/en-us/windows/win32/wic/tiff-format-overview)
- [WIC encoding overview](https://learn.microsoft.com/en-us/windows/win32/wic/-wic-creating-encoder)
- [WIC native pixel formats](https://learn.microsoft.com/en-us/windows/win32/wic/-wic-codec-native-pixel-formats)
- [IWICBitmapFrameEncode::SetColorContexts](https://learn.microsoft.com/en-us/windows/win32/api/wincodec/nf-wincodec-iwicbitmapframeencode-setcolorcontexts)
- [IWICBitmapFrameEncode::GetMetadataQueryWriter](https://learn.microsoft.com/en-us/windows/win32/api/wincodec/nf-wincodec-iwicbitmapframeencode-getmetadataquerywriter)

Windows에 포함된 WIC/ICM/Win32 API만 사용하고 외부 TIFF codec, source code, ICC asset, sample 또는
표준 문구를 저장소와 설치 payload에 포함하지 않습니다. 이번 phase는 무압축만 사용하므로 LZW/Deflate
특허나 별도 codec license에 의존하지 않습니다. 세부 기록은
`research/tiff16-output-sources.md`에 있습니다.
