# 출력 encode·게시 근거와 권리 검토

기준일: 2026-08-04

## 조사 질문

1. Windows 기본 PNG encoder가 16-bit RGB를 정확히 받을 수 있는가
2. WIC가 output ICC를 어떤 API로 container에 기록하는가
3. Windows의 등록된 표준 sRGB profile을 어떻게 찾는가
4. 기존 파일을 덮어쓰지 않는 같은-directory 게시에 어떤 Win32 계약을 쓸 수 있는가
5. PNG/DEFLATE 구현에 제3자 코드·재배포 권리·알려진 특허 차단이 필요한가

## 공식 자료와 적용

- Microsoft의 [WIC encoder 생성 절차](https://learn.microsoft.com/en-us/windows/win32/wic/-wic-creating-encoder)는
  stream 초기화, frame 생성, pixel 쓰기와 commit 순서를 정하는 근거입니다.
- [WIC 기본 pixel format 표](https://learn.microsoft.com/en-us/windows/win32/wic/-wic-codec-native-pixel-formats)는
  기본 PNG encoder의 48bpp RGB 지원과 `SetPixelFormat`이 가장 가까운 형식을 반환할 수 있음을 설명합니다.
  따라서 반환된 GUID를 exact 비교합니다.
- [`IWICBitmapFrameEncode::SetColorContexts`](https://learn.microsoft.com/en-us/windows/win32/api/wincodec/nf-wincodec-iwicbitmapframeencode-setcolorcontexts)는
  PNG encoder가 ICC profile을 `iCCP` 계열 metadata로 기록하는 공식 경계입니다.
- [`GetStandardColorSpaceProfileW`](https://learn.microsoft.com/en-us/windows/win32/api/icm/nf-icm-getstandardcolorspaceprofilew)는
  현재 Windows에 등록된 표준 sRGB profile 경로를 얻는 근거입니다.
- [`MoveFileExW`](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-movefileexw)는
  replace, cross-volume copy와 write-through flag의 의미를 구분합니다. 이번 구현은 replace와 copy를 쓰지
  않고 같은 디렉터리에서만 게시합니다.
- W3C의 [PNG 3 표준](https://www.w3.org/TR/png-3/)은 PNG를 royalty-free 정책 아래 유지되는 개방형
  형식으로 설명합니다.
- IETF의 [RFC 1951](https://www.rfc-editor.org/info/rfc1951/)은 DEFLATE가 특허로 막히지 않도록 설계된
  공개 압축 형식임을 기록합니다.

## 라이선스·특허·저작권 결론

- 제품은 Windows에 포함된 WIC PNG encoder/decoder와 ICM/Win32 API를 호출하며 codec source나 binary를
  저장소 또는 설치 payload에 복사하지 않습니다.
- ICC profile도 저장소 자산으로 추가하지 않습니다. 실행 시 해당 Windows 설치에 등록된 표준 sRGB
  profile을 읽어 사용합니다. 해당 profile을 독립 redistributable 자산으로 취급하지 않습니다.
- PNG/DEFLATE는 위 표준의 공개·royalty-free/patent 비차단 설명을 구현 선택의 근거로 삼았습니다. 특정
  특허의 만료나 라이선스 grant에 의존하는 알고리즘을 새로 채택하지 않았으므로 별도 특허 만료 계산은
  적용되지 않습니다.
- 외부 source code, sample image, ICC file, 표준 문구 또는 테스트 vector를 복사하지 않았습니다. 테스트
  이미지는 코드에서 만든 합성 pixel과 권리 확인된 저장소 fixture만 사용합니다.
- 새 vcpkg/NuGet/runtime package는 없습니다. 네이티브 링크는 Windows system library에 한정됩니다.

이 기록은 개발 단계의 권리 검토이며 법률 의견이 아닙니다. installer에 codec/profile을 별도 포함하거나
다른 encoder를 도입하면 M17 배포 gate에서 라이선스·특허·notice를 다시 검토해야 합니다.
