# 이미지 I/O 조사와 권리 검토

기준일: 2026-08-04

## 구현에 사용한 1차 자료

- [TIFF Revision 6.0](https://www.itu.int/itudoc/itu-t/com16/tiff-fx/docs/tiff6.pdf)
- [BigTIFF format overview](https://bigtiff.org/)
- [libtiff 4.7.2 documentation](https://libtiff.gitlab.io/libtiff/libtiff.html)
- [`TIFFOpenOptions`](https://libtiff.gitlab.io/libtiff/functions/TIFFOpenOptions.html)
- [`TIFFOpenWExt`](https://libtiff.gitlab.io/libtiff/functions/TIFFOpen.html)
- [libtiff 4.7.2 releases](https://gitlab.com/libtiff/libtiff/-/releases)
- [libtiff license](https://gitlab.com/libtiff/libtiff/-/blob/v4.7.2/LICENSE.md)
- [WIC overview](https://learn.microsoft.com/en-us/windows/win32/wic/-wic-about-windows-imaging-codec)
- [Microsoft native WIC codecs](https://learn.microsoft.com/en-us/windows/win32/wic/native-wic-codecs)
- [WIC TIFF format overview](https://learn.microsoft.com/en-us/windows/win32/wic/tiff-format-overview)
- [WIC native pixel formats](https://learn.microsoft.com/en-us/windows/win32/wic/-wic-codec-native-pixel-formats)
- [`IWICColorContext::GetProfileBytes`](https://learn.microsoft.com/en-us/windows/win32/api/wincodec/nf-wincodec-iwiccolorcontext-getprofilebytes)
- [`IWICColorTransform::Initialize`](https://learn.microsoft.com/en-us/windows/win32/api/wincodec/nf-wincodec-iwiccolortransform-initialize)
- [Windows ICM `OpenColorProfileW`](https://learn.microsoft.com/en-us/windows/win32/api/icm/nf-icm-opencolorprofilew)
- [`GetStandardColorSpaceProfileW`](https://learn.microsoft.com/en-us/windows/win32/api/icm/nf-icm-getstandardcolorspaceprofilew)
- [`CreateMultiProfileTransform`](https://learn.microsoft.com/en-us/windows/win32/api/icm/nf-icm-createmultiprofiletransform)
- [`TranslateBitmapBits`](https://learn.microsoft.com/en-us/windows/win32/api/icm/nf-icm-translatebitmapbits)
- [`BMFORMAT`](https://learn.microsoft.com/en-us/windows/win32/api/icm/ne-icm-bmformat)
- [W3C CSS Color 4 sRGB transfer](https://www.w3.org/TR/css-color-4/#color-conversion-code)
- [ICC.1:2010 profile specification](https://www.color.org/specification/ICC1v43_2010-12.pdf)
- [MSVC `/MD`와 `/MT`](https://learn.microsoft.com/en-us/cpp/build/reference/md-mt-ld-use-run-time-library)

## 확인한 기술 사실

- Classic TIFF header는 8바이트이고 version 42와 32-bit first-IFD offset을 사용합니다.
- Classic IFD count는 16-bit, entry는 12바이트, next-IFD offset은 32-bit입니다.
- BigTIFF header는 16바이트이고 version 43, offset-size 8, reserved 0을 사용합니다.
- BigTIFF IFD count/offset은 64-bit이고 entry는 20바이트입니다.
- WIC는 확장 가능한 codec 등록 구조이므로 실제 decoder CLSID allowlist가 필요합니다.
- WIC TIFF native decoder는 48bpp RGB와 64bpp RGBA/PRGBA를 지원합니다.
- TIFF 6.0 LZW는 strip마다 ClearCode로 시작해 EOI로 끝나고, code를 high-to-low bit 순서로 저장하며,
  decoder는 string #510/#1022/#2046을 저장한 뒤 10/11/12-bit로 조기에 전환해야 합니다.
- `IWICColorTransform`의 목적 format은 16-bit RGB/RGBA 계열까지이고 float format은 목록에 없습니다.
- Windows ICM은 memory buffer ICC와 시스템 표준 sRGB profile을 profile handle로 열 수 있습니다.
- `TranslateBitmapBits`는 `BM_16b_RGB` 입력·출력을 지원합니다.
- `/MT`는 multithread static runtime을 링크하며 같은 linker invocation의 module은 runtime 옵션이
  일치해야 합니다.
- libtiff의 single/cumulative allocation limit는 library 내부 allocation만 제한하며 외부
  `_TIFFmalloc`/`_TIFFrealloc` 전체를 대신 제한하지 않습니다.
- libtiff 4.7.2는 현재 조사 기준 버전이며 release notes에 compression ratio 관련 방어 추가가 있습니다.

## 저작권과 코드 provenance

현재 TIFF probe, 길이 전용 LZW 의미 검사기, WIC adapter, ICC validator와 ICM adapter는 Apache-2.0
저장소 코드입니다. TIFF, BigTIFF와 ICC 문서의 binary field 구조를
바탕으로 독립 구현했으며, libtiff나 다른 프로젝트의 parser source를 복사하거나 번역하지 않았습니다.
외부 사진 byte를 새 fixture로 포함하지 않고 합성 TIFF는 test 코드가 실행 시 생성합니다.

실제 검증에 사용한 네 TIFF는 기존 Negaflow 저장소 자산이며 원본 위치에서 읽기만 했습니다. SHA-256은
`baseline/source-assets.sha256`에 기록했습니다.

ICC specification의 사용 허가는 특정 ICC profile payload의 재배포 허가와 다릅니다. 사용자 profile은
원본 TIFF에서 읽기만 하고 저장소나 배포물에 포함하지 않습니다. Windows WIC/ICM과 MSVC runtime은
Microsoft OS·toolchain 구성 요소이며 별도 제3자 payload로 재배포하지 않습니다.

## 실제 OS API 평가 결과

- Microsoft 기본 WIC TIFF decoder는 사용자 TIFF 15개를 native 16-bit로 decode했습니다.
- LZW 6개는 독립 code-stream 의미 검사를 통과한 뒤 별도 libtiff/zlib 없이 WIC로 decode됐습니다.
- 구조상 유효한 Deflate는 독립 zlib/Deflate 의미 검사와 Adler-32를 통과한 경우에만 WIC에 전달하며,
  손상 합성 입력은 WIC 전에 거부합니다.
- WIC format conversion은 0건이었고 ICC bytes 길이와 구조를 확인했습니다.
- WIC 고수준 color transform은 사용자 ICC v4에 unsupported pixel format을 반환했습니다.
- Windows ICM `BEST_MODE` 16-bit 경로는 같은 profile을 처리했습니다.
- `WCS_ALWAYS` float 경로는 동일 sRGB 중립 입력 보존이 충분하지 않아 제외했습니다.

따라서 현재 none/LZW scanner input decode와 첫 ICC working 변환에는 libtiff, zlib, LittleCMS가
필요하다는 증거가 없습니다. Deflate 지원 복원, 출력 encoder와 ColorSync parity는 별도 gate입니다.

## 향후 libtiff/zlib/LittleCMS gate

현재 runtime에는 libtiff와 zlib이 아직 없습니다. 추가할 때 다음을 함께 수행합니다.

1. vcpkg baseline에서 exact port version과 artifact hash 기록
2. default feature를 끄고 Deflate에 필요한 최소 `zip` feature만 검증
3. libtiff license, LZW BSD notice, zlib notice를 Third-Party Notices에 포함
4. x64/ARM64 동적/정적 payload와 transitive file 목록 기록
5. upstream security advisory와 dependency update lane 연결
6. WIC 실패 후 무조건 재시도하지 않고 fallback 조건 allowlist 고정
7. ColorSync golden 수치가 ICM 허용 오차를 넘을 때만 LittleCMS float path 평가
8. 채택하지 않은 후보는 runtime payload나 notice에 넣지 않음

## 특허 screen

자체 코드는 TIFF LZW의 pixel decompressor를 만들지 않고 code reference와 복원 길이만 독립 검증한 뒤
Windows 기본 WIC decoder를 호출합니다. Deflate decoder는 구현하지 않았습니다. 공개 특허 검색에서
원 LZW 특허의 lifetime 만료 표시는 확인했지만 관할권별 법적 결론으로 간주하지 않습니다. TIFF 파일
재생성·복구, modified LZW bit 제거와 fragment recovery에 관한 후속 문헌도 claim 범위를 제한적으로
대조했으며 이번 fail-closed 검사기는 파일을 고치거나 재생성·복구하지 않습니다. 세부 링크와 한계는
[`compressed-tiff-preflight-sources.md`](compressed-tiff-preflight-sources.md)에 기록합니다.

최종 배포 전에는 적용 지역과 실제 linked implementation을 기준으로 법무·라이선스 검토를 다시
수행합니다. ICC specification도 제3자 IP 가능성을 고지하므로 제품 배포 전 검토를 유지합니다. 이 문서는
법률 의견이나 freedom-to-operate 보증이 아닙니다.
