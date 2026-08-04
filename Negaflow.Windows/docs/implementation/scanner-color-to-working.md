# Scanner TIFF에서 working linear-sRGB까지

## 목적

`src/Native/imaging`은 decode된 scanner sample에 명시적 색상 의미를 부여해 Negaflow의
`extended linear-sRGB RGBA float32` working 계약으로 바꿉니다. TIFF parse, WIC decode와 현상
알고리즘을 이 모듈에 섞지 않습니다.

## 파일과 책임

```text
src/Native/color
  icc_profile              bounded ICC 구조 검사
  srgb_transfer            clamp 없는 sRGB EOTF

src/Native/imageio
  decoded_image            RGB16/RGBA16 sample와 ICC bytes
  wic_tiff_decoder         TIFF → DecodedImage

src/Native/imaging
  scanner_to_working       정책·검증·작은 dispatcher
  linear_scanner_converter ICC 없는 scanner raw 정규화
  icm_rgb16_transform      재사용 가능한 Windows ICM row transform
  icm_icc_converter        소유형 DecodedImage용 ICM adapter
  scanner_tiff_to_working  WIC row sink→working orchestration
```

단일 class가 decode, color, policy와 현상을 모두 소유하지 않습니다.

## 두 변환 경로

### 1. ICC 없는 16-bit scanner raw

scanner 전용 entry point에서만 sample을 linear-sRGB primaries의 linear 값으로 해석합니다.

```text
uint16 RGB / 65535 → float32 linear RGB, alpha 1
```

sRGB EOTF를 적용하지 않습니다. 이는 macOS의 `linearScannerRaw` 정책과 같은 역할입니다.

### 2. Embedded RGB ICC

1. ICC 구조, RGB data color space와 scanner/display/color-space source class를 확인합니다.
2. alpha가 있으면 모든 값이 65535인지 먼저 확인합니다.
3. RGB만 `BM_16b_RGB`로 준비합니다.
4. embedded profile과 Windows에 등록된 표준 sRGB profile을 엽니다.
5. relative colorimetric intent와 `BEST_MODE`로 ICM transform을 만듭니다.
6. `TranslateBitmapBits`로 sRGB 16-bit를 얻습니다.
7. W3C에 명시된 sRGB EOTF를 적용해 float32 linear-sRGB로 변환합니다.
8. alpha는 1로 설정합니다.

CLI는 이 경로를
`embedded_icc_via_windows_icm_srgb16_to_linear_srgb_f32`로 보고하고 중간 정밀도 16-bit를 함께
출력합니다.

## row streaming 경로

`decode_scanner_tiff_to_working_rows`는 `WicTiffRowSink`를 구현한 작은 scanner-color consumer에 WIC
행 묶음을 직접 전달합니다. full decoded source vector를 만들지 않으며 한 job에서 다음 객체만 소유합니다.

- 최종 RGBA32F `WorkingImage`
- 재사용하는 한 행 묶음의 WIC copy buffer
- ICC형일 때 한 행 묶음의 packed RGB16과 sRGB16 intermediate
- source/destination profile handle과 재사용하는 ICM transform 한 개

ICC가 없는 RGB/RGBA는 행별로 직접 정규화합니다. ICC가 있으면 RGB만 묶음 단위로 pack하고 같은 ICM
transform을 재사용한 뒤 sRGB EOTF를 적용합니다. ICM progress callback은 `stop_token`을 확인하며 callback이
취소하거나 중간 변환이 실패하면 부분 intermediate와 최종 working pixel을 publish하지 않습니다.

현재 CLI는 64행 묶음을 사용합니다. 이는 초기 strip 후보와 실제 코퍼스 진단을 위한 application 설정이며
WIC 내부 codec 비용까지 고려한 범용 기본값으로 확정하지 않았습니다.

## alpha 정책

현재 scanner working 경로는 완전 불투명 이미지만 지원합니다. associated 또는 unassociated alpha
선언은 보존해 decode하지만 값 하나라도 65535가 아니면 `non_opaque_alpha`로 실패합니다. 임의로
unpremultiply하거나 배경에 합성하지 않습니다.

## 정밀도

- working buffer는 float32이며 이후 단계에서 음수와 1 초과 값을 허용합니다.
- ICC 입력 경로는 ICM 출력에서 16-bit로 한 번 양자화됩니다.
- sRGB EOTF는 0.04045 breakpoint와 12.92/1.055/0.055/2.4 상수를 사용합니다.
- transfer 함수 자체는 extended 값을 clamp하지 않습니다.
- 현재 입력이 uint16이므로 source 범위는 0~1입니다.

16-bit 중간 경로가 ColorSync parity에 부족하다고 입증되면 그때 LittleCMS float transform을
재평가합니다. 현재는 이를 숨기거나 float-native라고 주장하지 않습니다.

## 메모리

기존 whole-frame 기준으로 5088×3401 한 장의 주요 buffer는 다음과 같습니다.

| buffer | RGB형 | RGBA/ICC형 |
|---|---:|---:|
| decoded source | 103,825,728 B | 138,434,304 B |
| ICM용 packed RGB | 없음 | 103,825,728 B |
| sRGB16 intermediate | 없음 | 103,825,728 B |
| working RGBA32F | 276,868,608 B | 276,868,608 B |

ICC형은 packed RGB가 해제된 뒤 working buffer를 만들지만 source+intermediate+working만으로도
약 495 MiB입니다.

현재 64행 streaming 경로의 application-owned peak 관측값은 다음과 같습니다.

| buffer | 최대 관측값 |
|---|---:|
| WIC row copy | 2,605,056 B |
| ICC packed RGB16 + sRGB16 temporary | 3,907,584 B |
| 최종 working RGBA32F | 276,868,608 B |

따라서 full decoded source 103~138 MiB와 full-frame ICC intermediate 두 개는 제거됐습니다. 그러나 최종
working RGBA32F는 아직 전체 프레임을 소유합니다. WIC codec 내부 allocation도 이 수치에 포함되지 않으므로
downstream tile/row consumer와 명시적 process budget은 여전히 필요합니다.

## 현재 검증

- sRGB breakpoint, midpoint, 0/1, extended negative/positive 단위 test
- untagged direct-linear 변환 test
- stride, invalid ICC와 non-opaque alpha 거부 test
- 저장소 ICC TIFF integration test와 입력 sample/profile 불변성
- 합성 untagged/ICC TIFF의 whole-frame과 streaming 최종 float exact 일치
- temporary-byte 한도 실패와 취소 시 working pixel 미공개
- 사용자 TIFF 15개 전체 streaming 변환: 15/15 성공
- 사용자 TIFF 15개 whole-frame/streaming 최종 float pixel exact 일치
- 현재 x64 Debug/Release CTest 26/26 통과
- ARM64 Debug/Release cross-build

## 아직 입증하지 않은 것

- macOS ColorSync golden과의 ΔE·channel tolerance
- profile intent/BPC 정책의 최종 제품 동등성
- monitor ICC, HDR와 display transform
- output/print ICC와 gamut-check
- 비불투명 alpha
- 최종 working buffer를 제거하는 downstream streaming과 WIC 내부 peak memory
- ICM callback 사이의 CPU deadline
- ARM64 장치 수치 실행

## 공식 API 근거

- [TranslateBitmapBits](https://learn.microsoft.com/en-us/windows/win32/api/icm/nf-icm-translatebitmapbits)
- [ICM progress callback](https://learn.microsoft.com/en-us/windows/win32/wcs/icmprogressproccallback)
- [CreateMultiProfileTransform](https://learn.microsoft.com/en-us/windows/win32/api/icm/nf-icm-createmultiprofiletransform)
- [OpenColorProfileW](https://learn.microsoft.com/en-us/windows/win32/api/icm/nf-icm-opencolorprofilew)
