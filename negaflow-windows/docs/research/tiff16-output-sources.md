# TIFF16 출력·메타데이터 공식 근거와 권리 검토

기준일: 2026-08-04

## 조사 질문

1. Windows 기본 TIFF codec이 16-bit RGB encode를 지원하는가
2. 무압축을 추측이 아닌 명시적 option으로 고정할 수 있는가
3. ICC profile이 TIFF container의 어느 경계에 기록되는가
4. descriptive/private metadata를 넣지 않는 최소 출력은 어떻게 검증할 것인가
5. 외부 codec·코드·자산·특허 의존성 없이 첫 수직 경로를 닫을 수 있는가

## 공식 자료와 적용

- Microsoft의 [TIFF format overview](https://learn.microsoft.com/en-us/windows/win32/wic/tiff-format-overview)는
  Windows native TIFF codec과 `TiffCompressionMethod`의 `VT_UI1` 계약을 설명합니다. 구현은
  `WICTiffCompressionNone`을 명시하고 encode 결과 compression tag 1을 다시 확인합니다.
- [WIC encoding overview](https://learn.microsoft.com/en-us/windows/win32/wic/-wic-creating-encoder)는
  encoder option property bag, frame 초기화, pixel 쓰기와 commit 순서의 근거입니다. 같은 자료가
  `TiffCompressionMethod`의 값 형식을 `WICTiffCompressionOption`으로 정의합니다.
- [WIC native pixel formats](https://learn.microsoft.com/en-us/windows/win32/wic/-wic-codec-native-pixel-formats)는
  `GUID_WICPixelFormat48bppRGB`가 3채널×16-bit unsigned format임을 정의하고, encoder가 요청과 다른 가장
  가까운 format을 반환할 수 있음을 설명합니다. 따라서 반환 GUID를 exact 비교합니다.
- [`IWICBitmapFrameEncode::SetColorContexts`](https://learn.microsoft.com/en-us/windows/win32/api/wincodec/nf-wincodec-iwicbitmapframeencode-setcolorcontexts)는
  TIFF에서 profile color context를 ICC profile IFD metadata block, tag `0x8773`에 기록한다고 명시합니다.
  `0x8773`은 decimal 34675이며 구현의 필수 allowlist tag입니다.
- [`IWICBitmapFrameEncode::GetMetadataQueryWriter`](https://learn.microsoft.com/en-us/windows/win32/api/wincodec/nf-wincodec-iwicbitmapframeencode-getmetadataquerywriter)는
  metadata를 설정한다면 `WritePixels`/`WriteSource` 전에 해야 한다고 명시합니다. 현재 minimal 경로는
  query writer로 descriptive metadata를 추가하지 않습니다.
- [WIC metadata overview](https://learn.microsoft.com/en-us/windows/win32/wic/-wic-about-metadata),
  [metadata query language](https://learn.microsoft.com/en-us/windows/win32/wic/-wic-codec-metadataquerylanguage),
  [native image format metadata queries](https://learn.microsoft.com/en-us/windows/win32/wic/-wic-native-image-format-metadata-queries)는
  TIFF의 IFD, EXIF, XMP, GPS, IPTC metadata 계층을 구분하는 근거입니다. source metadata를 복사하지 않고
  encode 후 첫 IFD numeric tag를 fail-closed allowlist로 확인합니다.

## macOS 기준선과 적용 범위

저장소의 macOS `ExportEngine`, `ExportOptions`, `ExportEncodingOptions`, `ExportMetadataPolicy`와 관련 test를
읽어 기본 TIFF 계약을 확인했습니다. 기본은 sRGB, 16-bit, opaque, 무압축, dither 없음과 `minimal`
metadata입니다. Windows phase 1은 이 기본만 구현합니다.

macOS가 지원하는 LZW/Deflate, optional DPI와 `all`·`removeLocation`·`copyrightOnly` 정책은 현재 구현하지
않습니다. 존재하지 않는 값이나 정책을 Windows에서 새로 만들지 않았습니다.

## 라이선스·특허·저작권 결론

- Windows에 포함된 Microsoft WIC TIFF encoder/decoder와 ICM/Win32 API만 호출합니다. codec source나
  binary를 저장소, installer와 배포 payload에 복사하지 않습니다.
- 새 vcpkg/NuGet/native runtime dependency는 없습니다. Release CLI의 직접 dependency는 Windows system
  DLL로 한정됩니다.
- ICC 파일도 저장소 자산으로 추가하지 않습니다. 실행 중 해당 Windows에 등록된 표준 sRGB profile을
  읽고, 출력 파일 안에 color context로 기록합니다.
- 이번 phase는 무압축 TIFF만 생성합니다. LZW, DEFLATE 또는 다른 압축 구현을 추가하지 않았으므로
  압축 특허 만료나 제3자 codec license를 구현 성립 조건으로 삼지 않습니다. 압축 variant를 추가할 때는
  별도 권리·성능·손상 입력 검토를 다시 수행해야 합니다.
- 외부 source code, 예제, ICC, 사진, 표준 문구와 test vector를 복사하지 않았습니다. 구현은 공식 API의
  기능적 계약과 저장소의 기존 제품 기준만 참고했고, test image는 코드에서 만든 합성 pixel과 권리
  확인된 저장소 fixture만 사용했습니다.
- TIFF tag 번호와 구조 필드는 상호운용에 필요한 기능적 식별자입니다. TIFF specification 본문이나
  제3자 parser 구현을 복제하지 않았으며 bounded parser는 독립 작성했습니다.

이 기록은 개발 단계 권리 검토이며 법률 의견이 아닙니다. 외부 TIFF codec, compression library,
redistributable ICC 또는 specification 자산을 배포에 포함하면 M17 gate에서 license·patent·notice·SBOM을
다시 검토해야 합니다.
