# ADR-0007: 첫 출력은 검증된 16-bit sRGB PNG로 게시

- 상태: 채택
- 날짜: 2026-08-04

## 문제

현재 CPU 수직 경로는 TIFF를 읽어 scanner 색을 working linear-sRGB로 바꾸고 수동 네거티브 현상까지
수행하지만, 결과 파일을 만들지 않습니다. 첫 출력은 단순히 encoder 성공만 확인해서는 부족합니다.
잘못된 bit depth, 누락된 ICC, 부분 파일, 기존 파일 덮어쓰기와 게시 경합을 제품 경계에서 막아야 합니다.

로드맵의 최종 M4 계약은 16-bit TIFF와 metadata allowlist까지 요구합니다. 이번 단계는 그 전체를 한 번에
구현하지 않고, Windows 기본 codec으로 출력 변환·encode·readback·단일 파일 게시 계약을 먼저 닫는
phase 0입니다.

## 결정

1. 첫 출력 형식은 opaque 16-bit RGB PNG, 목적 색 공간은 sRGB로 제한합니다.
2. extended-linear-sRGB working RGB는 출력 직전에만 `[0, 1]`로 clamp하고 sRGB OETF를 적용해
   16-bit 정수로 반올림합니다. alpha가 정확히 1이 아니거나 픽셀이 finite가 아니면 거부합니다.
3. encoder와 readback decoder는 Microsoft 기본 WIC PNG CLSID로 고정합니다. WIC가 요청한
   `GUID_WICPixelFormat48bppRGB`를 다른 형식으로 바꾸면 실패합니다.
4. Windows에 등록된 표준 `LCS_sRGB` profile을 읽어 구조를 검사하고 PNG에 넣습니다. 게시 전에 decoder가
   돌려준 ICC bytes가 입력 profile과 정확히 같은지 확인합니다.
5. 목적지와 같은 디렉터리에 `CREATE_NEW` staging 파일을 만들고 encode 후 `FlushFileBuffers`를 수행합니다.
   PNG 구조, 치수, 16-bit truecolor, ICC 존재, 모든 pixel과 ICC bytes를 읽어 확인한 뒤에만
   `MoveFileExW(MOVEFILE_WRITE_THROUGH)`로 최종 이름에 게시합니다.
6. `MOVEFILE_REPLACE_EXISTING`과 `MOVEFILE_COPY_ALLOWED`는 사용하지 않습니다. 작업 중 목적지가 생기면
   먼저 생성한 쪽을 보존하고 staging을 폐기합니다.
7. 일반 이미지 content SHA-256은 이 경로에서도 기본 `끔`입니다. source와 artifact를 묵시적으로 다시
   읽어 hash하지 않으며, 공급망·배포 hash 정책은 ADR-0005의 별도 보안 경계를 유지합니다.
8. 출력 경로는 절대 경로이고 기존 파일이 없어야 합니다. 사용자 경로와 파일명은 구조화된 결과나
   오류 JSON에 넣지 않습니다.

## 현재 범위 밖

- 16-bit TIFF/JPEG/Raw TIFF 출력
- metadata와 DPI allowlist, resize, sharpen, dither
- output encode/readback progress와 cancellation
- 여러 artifact와 catalog를 묶는 transaction 또는 crash journal
- 최종 working image의 row/tile streaming
- machine 간 canonical sRGB profile bytes 고정

PNG 구조 검사는 chunk 범위와 순서를 제한하지만 CRC를 독립 계산하지 않습니다. 대신 Microsoft 기본 WIC
decoder로 같은 staging 파일을 다시 열어 전체 pixel과 profile을 exact 비교합니다. 이 조합을 독립 PNG
검증기 또는 전원 장애까지 포괄하는 filesystem transaction으로 표현하지 않습니다.

## 결과

CPU 수직 경로는 한 장을 `decode → scanner color → manual develop → sRGB16 → PNG encode → readback →
publish`할 수 있습니다. 출력은 단일 파일 게시 경계를 확보했지만, packed RGB16 전체 프레임을 추가로
소유하므로 M7 대형 이미지 완료로 간주하지 않습니다. 등록된 Windows sRGB profile이 machine별로 다를 수
있으므로 macOS golden과의 cross-machine 재현성은 후속 검증 대상입니다.

## 공식 근거와 권리

- [WIC encoder 생성 절차](https://learn.microsoft.com/en-us/windows/win32/wic/-wic-creating-encoder)
- [WIC 기본 pixel format 표](https://learn.microsoft.com/en-us/windows/win32/wic/-wic-codec-native-pixel-formats)
- [IWICBitmapFrameEncode::SetColorContexts](https://learn.microsoft.com/en-us/windows/win32/api/wincodec/nf-wincodec-iwicbitmapframeencode-setcolorcontexts)
- [GetStandardColorSpaceProfileW](https://learn.microsoft.com/en-us/windows/win32/api/icm/nf-icm-getstandardcolorspaceprofilew)
- [MoveFileExW](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-movefileexw)

Windows에 포함된 WIC/ICM/Win32 API만 사용하고 외부 codec, profile, sample 또는 구현 코드를 포함하지
않습니다. PNG와 DEFLATE의 표준·특허 검토 기록은 `research/output-encode-sources.md`에 분리합니다.
