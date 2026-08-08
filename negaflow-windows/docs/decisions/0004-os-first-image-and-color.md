# ADR-0004: OS 우선 이미지·색상 경로와 제3자 의존성 게이트

- 상태: 채택
- 날짜: 2026-08-04

## 배경

macOS판은 스캐너 플러그인을 제외하면 제3자 런타임 라이브러리 없이 설치 후 실행됩니다. Windows판도
libtiff나 LittleCMS를 관성적으로 추가하지 않고, Windows 기본 API가 실제 Negaflow 입력 계약을
충족하지 못한다는 증거가 있을 때만 의존성을 허용해야 합니다.

사용자 코퍼스에는 다음 두 입력 집단이 있습니다.

- ICC가 없는 little-endian RGB 16-bit 무압축 TIFF 9개
- ICC v4가 있는 big-endian RGBA 16-bit LZW TIFF 6개

둘 다 5088×3401이며, 두 번째 집단의 alpha는 associated로 선언됐지만 실제 값은 전부 완전
불투명입니다.

## 결정

1. TIFF 경로는 read-only `IStream`으로 한 번 열고, 자체 bounded preflight와 WIC decoder가 같은
   stream instance를 순서대로 사용합니다.
2. 허용된 입력은 Microsoft 기본 WIC TIFF decoder로 읽습니다. 등록된 제3자 WIC codec은 사용하지
   않으며 vendor와 decoder CLSID를 확인합니다.
3. ICC가 없는 16-bit scanner TIFF는 호출자가 선택한 scanner 경로에서만 linear-sRGB primaries의
   linear raw로 해석합니다. 일반 이미지의 묵시적 기본값으로 확대하지 않습니다.
4. embedded RGB ICC는 Windows ICM의 `CreateMultiProfileTransform`과 `TranslateBitmapBits`로
   표준 sRGB 16-bit에 변환한 뒤, 명시적인 sRGB EOTF를 적용해 float32 linear-sRGB로 만듭니다.
5. ICM 변환은 relative colorimetric intent와 `BEST_MODE`를 명시합니다.
6. 네이티브 산출물은 정적 MSVC runtime을 사용해 별도 VC++ Redistributable 설치를 요구하지
   않습니다. CRT가 소유한 메모리는 C ABI 경계를 넘지 않습니다.
7. 현재 `vcpkg.json`은 빈 dependency 목록을 유지합니다.

## WIC 색상 변환을 사용하지 않는 이유

저장소의 RGB ICC fixture에서는 `IWICColorTransform`이 동작했지만, 사용자 코퍼스의 정상 ICC v4
matrix/TRC 프로파일에서는 1×1 RGB 입력으로 줄여도 `WINCODEC_ERR_UNSUPPORTEDPIXELFORMAT`을
반환했습니다. 따라서 WIC decoder는 유지하되 색상 변환 책임은 ICM으로 분리했습니다.

`WCS_ALWAYS`와 float BMFORMAT 조합도 시험했지만, 표준 sRGB→동일 표준 sRGB의 중립 입력을
충분히 보존하지 않아 working reference로 채택하지 않았습니다. 고전 ICM 경로의 16-bit 출력은 같은
검사에서 거의 항등이었고 사용자 ICC를 처리했습니다.

## 결과와 trade-off

- 실제 TIFF 15개 모두 decode와 working 변환에 성공했습니다.
- runtime 제3자 dependency는 0개입니다.
- ICC 경로에는 16-bit 중간 양자화가 있습니다. 이 사실은 provenance와 CLI 결과에 노출합니다.
- ICM과 macOS ColorSync의 수치 동등성은 아직 입증하지 않았습니다.
- whole-frame reference 경로의 peak memory는 약 495 MiB입니다. 현재 row 경로는 full decoded source와
  ICC intermediate를 chunk로 줄였지만 최종 working buffer와 downstream tile/row 처리는 남아 있습니다.
- 정적 CRT는 설치 의존성을 줄이지만 CRT 보안 수정은 앱을 다시 빌드·배포해야 반영됩니다.

## 제3자 라이브러리 재검토 조건

다음 중 하나가 재현될 때만 libtiff 또는 LittleCMS를 후보로 올립니다.

- 지원하기로 한 TIFF가 WIC에서 실패하거나 잘못 decode되고 OS API만으로 고칠 수 없음
- ColorSync golden corpus와 ICM 결과가 합의된 허용 오차를 넘음
- 출력 TIFF의 bit depth, compression, ICC byte 보존 계약을 WIC encoder가 충족하지 못함
- 보안상 필요한 allocation/compression 한도를 OS API 위에 안전하게 구성할 수 없음
- 동일 입력에 대한 재현성이 Windows servicing 범위에서 제품 계약을 깨뜨림

채택할 경우 exact version, 최소 feature, 라이선스 notice, 특허·보안 검토, x64/ARM64 payload와
업데이트 책임을 같은 변경에 기록합니다.
