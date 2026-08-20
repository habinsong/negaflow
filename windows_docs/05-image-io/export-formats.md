# 내보내기 설계 — JPEG·PNG·TIFF·Raw TIFF와 게시 트랜잭션

조사 기준일: 2026-08-04  
macOS 근거: `Sources/Chromabase/Export/`, `Sources/negaflowApp/Features/Export/`, 대응 XCTest  
대상: Windows 11, WinUI 3 셸과 네이티브 C++ 이미지 엔진

## 결론

Windows판은 현재 macOS의 네 가지 내보내기 포맷과 다중 artifact 트랜잭션을 그대로 옮깁니다.

| 제품 포맷 | 픽셀 계약 | 기본 encoder |
|---|---|---|
| JPEG | 8-bit RGB, alpha 없음, quality 0…1 | Windows native WIC JPEG |
| PNG | 8/16-bit RGB(A), lossless | Windows native WIC PNG |
| TIFF | 8/16-bit RGB(A), none/LZW/Deflate | libtiff |
| Raw TIFF | 16-bit, uncompressed, opaque, source pixel domain | libtiff |

WIC JPEG/PNG가 품질·정밀도·ICC·메타데이터 readback gate를 통과하지 못할 때만 libjpeg-turbo/libpng를 검토합니다. 의존성을 먼저 늘리지 않습니다.

내보내기는 `render → encode → 파일 하나 생성`으로 끝나지 않습니다. 현재 제품은 primary, MAIN flat, original source pair, Negaflow JSON sidecar, XMP를 하나의 논리 트랜잭션으로 다룹니다. Windows에서도 다음을 보장해야 합니다.

- source 불변
- source와 output의 path/file identity 충돌 거부
- 모든 옵션을 파일 생성 전에 검증
- sibling staging에서 인코드
- ICC·픽셀 크기·메타데이터 readback
- source generation 재확인
- journal 기반 다중 artifact 게시·복구
- catalog commit과 파일 publish의 상태 연결
- 취소·실패 시 미완성 파일을 성공으로 표시하지 않음

파일시스템은 여러 파일을 하나의 원자 연산으로 rename해 주지 않습니다. 그러므로 “다중 artifact가 물리적으로 한 번에 나타난다”고 약속하지 않고, journal로 부분 게시를 복구 가능한 상태로 만듭니다.

## 1. 현재 macOS 구현에서 확인한 계약

### 1.1 포맷

```swift
enum ExportFormat {
    case jpeg
    case png
    case tiff16
    case rawScanTIFF
}
```

`tiff16`이라는 저장 값은 이제 8-bit 옵션도 허용하지만 기존 호환을 위해 이름이 유지됩니다. Windows persisted model도 migration 없이 임의로 `tiff`로 바꾸지 않습니다.

### 1.2 기본 옵션

| 옵션 | 기본값 | 허용 범위 |
|---|---:|---|
| `colorSpace` | sRGB | sRGB, Display P3, Adobe RGB |
| `dpi` | 0 | 0 이상 |
| `longEdge` | 없음 | 있으면 양수 |
| `jpegQuality` | 1.0 | finite 0…1 |
| `tiffCompression` | none | none, LZW, Deflate |
| `tiffBitDepth` | 16 | 8, 16 |
| `pngBitDepth` | 16 | 8, 16 |
| `preserveAlpha` | false | JPEG와 Raw TIFF에는 불가 |
| `metadataPolicy` | minimal | all, removeLocation, copyrightOnly, minimal |
| `outputSharpening` | 0 | finite 0…1 |
| `outputSharpeningMedium` | screen | screen, mattePaper, glossyPaper |

오래된 macOS 설정에 `jpegQuality`가 없으면 현재 1.0으로 decode합니다. Windows는 처음부터 1.0을 기본으로 시작합니다.

### 1.3 validation 순서

아래 오류는 encoder나 최종 파일을 만들기 전에 발생해야 합니다.

- `dpi < 0`
- `longEdge <= 0`
- JPEG quality가 NaN/Infinity 또는 0…1 밖
- output sharpening이 NaN/Infinity 또는 0…1 밖
- JPEG + alpha
- Raw TIFF의 비트 심도·압축·alpha·resize·sharpen 조합 위반
- Raw TIFF + printer ICC
- PRINT target + 유효한 printer ICC 없음
- source/output 동일 path 또는 동일 existing file
- artifact끼리 같은 path/file을 가리킴
- 기존 destination이 이미 존재

validation 실패 뒤 빈 파일이 남으면 안 됩니다.

## 2. 출력 파이프라인 순서

일반 processed export의 기준 순서입니다.

```text
stable source snapshot
  → decode with provenance
  → defects/develop recipe
  → optional print composition
  → downscale only, if longEdge is smaller
  → output sharpening
  → destination ICC transform
  → 8/16-bit quantization
       └── 8-bit only: output dither immediately before quantization
  → format encoder
  → embedded destination ICC + metadata
  → readback verification
  → journaled publish
```

순서를 임의로 바꾸면 결과가 달라집니다.

- resize 전에 과도한 output sharpening을 걸지 않습니다.
- destination transform 후로 sharpening을 옮기지 않습니다.
- 8-bit dither를 develop recipe에 넣지 않습니다.
- encoder에 working float를 넘기고 암묵 색 변환을 기대하지 않습니다.
- printer profile transform과 display soft proof를 섞지 않습니다.

Raw TIFF는 별도 분기입니다.

```text
stable source snapshot
  → source decode/interpretation
  → 16-bit uncompressed opaque TIFF normalization
  → source profile/descriptor 보존
  → verification + publish
```

결함 제거, develop, resize, sharpen, dither, printer profile을 적용하지 않습니다.

## 3. `Raw TIFF`와 `Original` pair의 차이

두 기능은 같은 것이 아닙니다.

### Raw TIFF

- Negaflow가 해석한 source pixel domain을 16-bit uncompressed TIFF로 저장
- 현재 입력이 RAW 카메라 파일이면 디코드된 RGB 의미가 개입할 수 있음
- 원래 파일 container byte를 보존하는 기능이 아님
- loaded input profile 또는 명시된 linear source descriptor 보존

### Original pair

- 원본 파일의 byte-for-byte 사본
- source extension 유지
- 이름 suffix `-original`
- primary가 Raw TIFF이면 별도 original pair를 만들지 않음
- strict verification에서는 source와 full identity/hash 비교

UI copy와 문서에서 Raw TIFF를 “원본 파일 그대로”라고 부르면 안 됩니다. 정확한 표현은 “현상 전 스캔 픽셀 보존 TIFF”입니다.

## 4. 크기와 리샘플링

### 4.1 `longEdge`

- 없음: 원본 픽셀 크기
- 현재 긴 변보다 작음: 비율 유지 축소
- 현재 긴 변과 같거나 큼: 무연산
- upscale 없음
- width/height 결과 반올림 규칙 고정
- nonzero-origin 렌더 extent도 0-origin 출력 raster로 정확히 변환

Windows 고품질 CPU/GPU scaler는 macOS `CILanczosScaleTransform` corpus와 비교합니다. 알고리즘 이름만 Lanczos로 맞추고 동일하다고 주장하지 않습니다.

### 4.2 프록시 decode 최적화

현재 macOS app은 최종 출력이 작은 경우 현상 전에 source proxy를 읽을 수 있습니다. 단, 필요한 샘플을 잃지 않도록 출력 long edge에 crop/회전 여유와 2% margin을 둡니다.

프록시 금지 조건:

- Raw TIFF
- MAIN flat 동시 출력
- RenderManifest/sidecar가 full-resolution decode provenance를 요구
- decoder scaled output이 필요한 sample coverage를 증명하지 못함

Windows에서도 JPEG DCT scale 또는 WIC scaler를 무조건 사용하지 않습니다.

1. 목표 출력 샘플을 모두 포함하는지 geometry로 증명
2. full decode 기준과 실제 pixel metric 비교
3. 비정수 비율에서 품질 손실이 허용치를 넘으면 full decode 후 scale
4. proxy decoder/version/effective scale을 provenance에 기록

속도를 위해 최종 해상도·DPI·JPEG quality·ICC를 낮추는 것은 금지합니다.

## 5. 출력 샤픈

현재 medium은 세 가지입니다.

- `screen`
- `mattePaper`
- `glossyPaper`

strength 0은 무연산입니다. strength 0…1은 intensity를 조절하고, radius는 medium과 DPI에 따라 달라집니다. 현재 macOS parameter 계약은 다음 특성을 가집니다.

- screen reference DPI 144
- matte/glossy reference DPI 300
- effective DPI scale은 0.5…2.0으로 bounded
- radius는 scale의 제곱근에 비례
- 결과 extent를 원본 extent로 crop

Windows kernel은 이 parameter 계산과 시각 결과를 golden corpus로 옮깁니다. GPU가 없어도 CPU에서 같은 요청을 처리해야 합니다.

Raw TIFF는 strength가 0보다 크면 validation 단계에서 거부합니다.

## 6. 디더와 양자화

현재 계약:

| 출력 | 디더 |
|---|---|
| JPEG 8-bit | 적용 |
| PNG 8-bit | 적용 |
| TIFF 8-bit | 적용 |
| PNG 16-bit | 미적용 |
| TIFF 16-bit | 미적용 |
| Raw TIFF 16-bit | 미적용 |

디더는 destination encoding domain에서 ±0.5 code에 해당하는 분산을 주고 다시 quantization으로 들어갑니다. 목적은 부드러운 그라디언트 banding을 줄이면서 평균 톤을 유지하는 것입니다.

Windows 구현 규칙:

- absolute pixel coordinate에 고정된 noise pattern 또는 versioned blue-noise 사용
- 타일 경계에서 패턴 재시작 금지
- crop/타일 순서가 결과 통계를 바꾸지 않음
- RGB channel correlation과 spatial spectrum을 corpus로 고정
- 16-bit 경로에 8-bit amplitude noise를 실수로 적용하지 않음

macOS와 random sample byte equality를 요구하지는 않지만, code distribution·평균·banding 지표와 시각 결과를 비교합니다. 재현성이 필요한 sidecar에는 dither algorithm version을 기록합니다.

## 7. 색공간과 ICC

### 7.1 일반 출력

사용자 색공간:

- sRGB
- Display P3
- Adobe RGB (1998)

기본은 sRGB입니다. 출력 픽셀을 선택 프로파일로 변환하고 **그 destination ICC를 파일에 임베드**합니다.

Windows 원칙:

- LittleCMS float transform이 CPU 기준
- canonical profile asset/version/digest 고정
- OS에 우연히 설치된 같은 이름 profile을 자동 선택하지 않음
- profile description 문자열만으로 identity 판단하지 않음
- transform 실패 시 sRGB로 조용히 fallback하지 않음
- encode 후 embedded profile digest readback

Display P3와 Adobe RGB canonical asset은 macOS `CGColorSpace` snapshot·license·transform corpus를 통과해야 합니다. Adobe RGB profile 재배포 문제를 해결하지 못하면 옵션을 숨기거나 명시 오류로 처리하며, 다른 profile을 같은 이름으로 속이지 않습니다.

### 7.2 printer ICC

PRINT export와 print composition primary에는 측정 printer ICC snapshot을 사용할 수 있습니다.

validation 최소 조건:

- ICC 최소 header 길이
- declared size와 실제 byte size 일치
- signature `acsp`
- device class `prtr`
- input color space RGB
- PCS Lab 또는 XYZ
- 필요한 양방향 transform 생성 가능
- expected SHA-256와 실제 bytes 일치

필수 printer profile이 없거나 손상되면 export를 중단합니다. monitor profile, source profile, sRGB로 대체하지 않습니다.

### 7.3 MAIN flat pair

primary가 printer ICC를 사용해도 `-main-flat` sibling은 일반 사용자가 선택한 RGB export color space를 사용합니다. printer output profile을 sibling에 자동 복사하지 않습니다.

### 7.4 Raw TIFF

- printer ICC 금지
- 일반 sRGB/P3/Adobe 변환 금지
- loaded input profile 또는 source interpretation 보존
- 프로파일 없는 linear scanner raw는 sidecar/manifest에 역할 기록

## 8. JPEG

### 8.1 픽셀 계약

- 8-bit RGB
- alpha 없음
- destination ICC embedded
- orientation=1
- output dither 적용
- default quality 1.0

`preserveAlpha=true`는 합성으로 조용히 바꾸지 않고 오류입니다.

### 8.2 encoder

첫 후보는 Windows native WIC JPEG encoder입니다.

필수 property:

- `ImageQuality`
- `JpegYCrCbSubsampling`

WIC property bag에서 지원하지 않는 옵션이 무시될 수 있으므로 `Commit` 성공만 검사하지 않습니다. 완성 JPEG marker를 독립 parser로 읽어 실제 sampling factor를 확인합니다.

### 8.3 quality mapping

macOS ImageIO의 0…1과 WIC의 0…1이 동일한 quantization table을 의미한다고 가정하지 않습니다.

제품 UI 값은 추상 `ExportJPEGQuality`이고 encoder별 mapping을 version으로 관리합니다.

측정 grid:

```text
0.00, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95, 0.99, 1.00
```

각 점에서 비교:

- file size
- luma/chroma quantization tables
- PSNR/SSIM과 edge/color error
- artifact visual review
- encode time

단순 `round(quality × 100)`이나 identity mapping을 최종값으로 고정하지 않습니다.

### 8.4 chroma subsampling

현재 macOS는 공개 subsampling 옵션이 없어 user quality 0.95 이상을 encoder quality 0.995 이상으로 올려 4:4:4를 유도합니다. Windows WIC에는 명시 enum이 있으므로 이 우회를 복사하지 않습니다.

초기 의미 보존 규칙:

- 사용자 quality 0.95 이상: `WICJpegYCrCbSubsampling444`
- 그 아래: 용량/화질 mapping에서 4:2:0 또는 4:2:2 결정
- quality 값 자체는 Windows mapping에 따라 전달
- output marker로 실제 4:4:4 확인

채도 높은 간판·네온·필름 grain edge corpus가 필수입니다.

### 8.5 metadata

- EXIF/TIFF/IPTC allowlist
- GPS 정책
- ICC APP2 segment가 여러 segment로 나뉘어도 digest 재조립 확인
- orientation=1
- resolution 값과 단위 readback

JPEG는 byte-for-byte deterministic을 일반 계약으로 삼지 않습니다. OS codec update가 entropy stream을 바꿀 수 있으므로 decoded pixels, quantization/sampling, metadata, profile을 기준으로 검증합니다.

## 9. PNG

### 9.1 픽셀 계약

- 8-bit 또는 16-bit
- RGB 또는 RGBA
- lossless
- quality slider 없음
- 8-bit만 dither
- destination profile/chunks
- orientation은 픽셀에 구워짐

PNG에서 화질을 결정하는 사용자 옵션은 비트 심도입니다. compression/filter는 속도·크기를 바꿀 뿐 decoded pixel quality를 바꾸지 않으므로 일반 UI에 품질처럼 노출하지 않습니다.

### 9.2 encoder

첫 후보는 Windows native WIC PNG encoder입니다. 공식 native pixel format 표의 48bpp RGB와 64bpp RGBA encode를 사용합니다.

`SetPixelFormat` 뒤 returned GUID가 요청 16-bit 포맷과 같은지 확인합니다. 8-bit coercion이면 실패합니다.

### 9.3 16-bit endian

PNG 파일의 16-bit sample byte order와 Windows memory representation 차이는 encoder adapter가 책임집니다.

- WIC 경로에서는 16-bit ramp round-trip으로 실제 처리를 검증
- libpng fallback에서는 host little-endian buffer를 명시 변환
- R/G/B impulse와 0x00ff/0xff00 패턴으로 byte swap 검출

### 9.4 ICC와 chunks

- canonical ICC는 iCCP에 기록
- sRGB chunk와 custom ICC가 모순되지 않게 함
- gAMA/cHRM을 별도로 기록한다면 ICC와 의미 일치
- DPI는 pHYs pixels-per-meter로 변환
- XMP/text는 metadata policy와 size limit 적용

encode 후 WIC와 독립 PNG parser로 bit depth, color type, ICC, pHYs, forbidden metadata를 확인합니다.

## 10. TIFF

### 10.1 픽셀 계약

- unsigned 8/16-bit
- RGB 또는 RGBA
- contiguous channel layout
- alpha는 unassociated로 명시
- orientation top-left
- destination ICC embedded
- 8-bit만 dither

### 10.2 압축

```text
none     tag 1
LZW      tag 5
Deflate  tag 8, COMPRESSION_ADOBE_DEFLATE
```

`COMPRESSION_DEFLATE=32946`을 현재 옵션에 사용하지 않습니다.

### 10.3 encoder

libtiff가 기준입니다.

- Unicode path
- per-handle memory/error options
- strip/row streaming
- tag exact control
- readback

WIC TIFF encoder는 제품 기준 writer가 아닙니다. WIC는 independent readback reader로 사용합니다.

### 10.4 Classic TIFF/BigTIFF

사용자 export에서 크기 추정만으로 BigTIFF로 조용히 전환하지 않습니다.

- default: Classic TIFF
- checked upper bound가 한계를 넘을 위험: encode 전 명시 오류
- BigTIFF: 호환성 matrix 후 명시 옵션
- app-owned internal cache만 manifest와 함께 자동 전환 후보

현재 macOS UI에 없는 BigTIFF option을 Windows parity 단계에서 임의 추가하지 않습니다.

상세는 [libtiff.md](libtiff.md)를 따릅니다.

## 11. Raw TIFF validation

다음 조합만 유효합니다.

```text
bitDepth          = 16
compression       = none
preserveAlpha     = false
outputSharpening  = 0
longEdge          = nil
printerICC        = nil
developApplied    = false
ditherApplied     = false
```

추가 invariant:

- source pixels/profile을 조용히 sRGB로 변환하지 않음
- source orientation/geometry policy를 한 번만 적용
- scanner defect cache나 current develop recipe를 섞지 않음
- primary 외 MAIN flat/original pair를 중복 생성하지 않음
- pixel/profile readback이 실패하면 게시하지 않음

현재 tests가 일반 import와 scanner import 양쪽에서 source pixel/profile 보존을 확인합니다. Windows에서도 두 경로를 분리해 검증합니다.

## 12. 알파

### 허용

- PNG 8/16
- TIFF 8/16

### 금지

- JPEG
- Raw TIFF

내부 렌더 표면이 premultiplied alpha이면 encoder 전에 straight/unassociated alpha로 변환합니다.

- alpha 0에서 RGB 정책 고정
- NaN/Infinity 제거
- almost-zero alpha unpremultiply bound
- `preserveAlpha=false`의 채널 제거/배경 합성 정책 고정
- RGB profile transform과 alpha copy 분리

LittleCMS transform에는 alpha `COPY_ALPHA` 또는 별도 채널 copy를 사용하고, color transform이 alpha를 색 채널처럼 변경하지 않게 합니다.

## 13. DPI

`ExportOptions.dpi`의 의미:

- 양수: 사용자가 지정한 DPI
- 0: 사용자 override 없음

app export transaction은 override가 없으면 scanner resolution을 사용할 수 있습니다. scanner DPI도 없으면 임의 기본값을 발명하지 않습니다.

포맷별:

| 포맷 | 기록 |
|---|---|
| JPEG | WIC resolution + JFIF/EXIF 일관성 readback |
| PNG | pHYs pixels-per-meter |
| TIFF | XResolution/YResolution + ResolutionUnit inch |

PNG 변환:

```text
pixelsPerMeter = round(dpi / 0.0254)
```

반올림과 readback 허용차를 고정합니다. DPI는 pixel dimensions를 바꾸지 않으며, longEdge가 DPI를 자동 재계산하지 않습니다.

## 14. 메타데이터 정책

### 14.1 입력 값 모델

현재 source metadata는 TIFF, EXIF, IPTC, GPS의 bounded 값으로 정규화합니다.

- 문자열 최대 UTF-8 4,096 bytes
- 배열 최대 128개
- finite number만 허용
- integer array와 float array 구분
- 알 수 없는 blob/객체 그래프 자동 복사 금지

### 14.2 정책별 의미

| 정책 | source metadata | app-generated metadata |
|---|---|---|
| `all` | 지원되는 TIFF/EXIF/IPTC/GPS | scanner/date/software/film 규칙에 따라 주입 |
| `removeLocation` | GPS와 위치 IPTC 제거 | 위치가 아닌 생성 metadata 주입 |
| `copyrightOnly` | author/copyright/credit/source/rights만 | 현재 동작은 orientation 정규화 외 기술 metadata 주입을 생략 |
| `minimal` | source metadata 없음 | scanner/DPI/date/software와 film type 등 현재 허용된 최소 생성 metadata는 남을 수 있음 |

`minimal`은 “파일에 어떤 metadata도 0개”라는 뜻이 아니라 “원본에서 가져온 metadata를 싣지 않음”입니다. UI 문구는 이 차이를 숨기지 않아야 합니다.

`removeLocation`은 다음을 최소 제거합니다.

- 전체 GPS block
- IPTC City
- IPTC Sublocation
- IPTC Province/State
- IPTC Country code/name

### 14.3 생성 metadata

- scanner make/model은 원문 그대로
- film-shot camera make/model이 있으면 촬영 장비가 scanner보다 우선
- effective DPI
- source/original date와 metadata modification date 분리
- UTC offset `+00:00`
- software `negaflow <version>`
- film type/stock은 policy에 맞게 UserComment
- orientation=1

source date가 없으면 original date를 만들지 않습니다.

### 14.4 Windows writer

WIC metadata block을 원본째 복사한 뒤 GPS만 지우지 않습니다. 정책별 allowlist를 새 컨테이너에 기록합니다.

TIFF는 libtiff tag/IFD writer, JPEG/PNG는 WIC query writer를 사용하되 공통 `SanitizedExportMetadata`에서 생성합니다. 포맷별 writer가 privacy policy를 다시 결정하면 안 됩니다.

### 14.5 readback

각 정책·포맷 조합에서 다음을 검사합니다.

- 금지 GPS/위치 키 부재
- copyright key 보존
- orientation=1
- date 분리
- scanner/camera 우선순위
- ICC와 metadata가 서로 덮어쓰지 않음
- sidecar XMP가 같은 policy 적용

privacy negative test가 release blocker입니다.

## 15. 출력 artifact layout

primary가 `photo.tif`일 때 가능한 layout:

```text
photo.tif
photo-main-flat.tif
photo-original.<source extension>
photo.negaflow.json
photo.xmp
```

규칙:

- MAIN flat은 opt-in, Raw TIFF에는 없음
- original raw는 opt-in, Raw TIFF에는 없음
- sidecar JSON과 XMP는 함께 opt-in
- 모든 final path는 서로 달라야 함
- 모든 staged filename도 서로 달라야 함
- artifact 목록과 suffix는 macOS persisted/export tracking과 동일

UI 완료 메시지는 실제 생성된 paired filename을 표시합니다. 생성되지 않은 pair를 성공 메시지에 넣지 않습니다.

## 16. destination 안전성

### 16.1 path만 비교하면 부족

다음을 모두 검사합니다.

- normalized Unicode path
- case-insensitive filesystem semantics
- `.`/`..`
- symlink/junction/reparse point 최종 대상
- existing hard link identity
- volume identity + 128-bit file ID
- alternate path가 같은 file을 가리키는지
- output artifact끼리 중복

Windows 도구:

- `CreateFileW`
- `GetFinalPathNameByHandleW`
- `GetFileInformationByHandleEx`
- `FileIdInfo`
- reparse point attributes/tag

source와 existing output이 같은 file ID이면 거부합니다.

### 16.2 non-existing destination race

존재하지 않는 path는 file ID가 없습니다. 다음으로 외부 race를 줄입니다.

- parent directory를 handle로 열고 final path를 확정
- process 내부 artifact reservation
- staging file은 `CREATE_NEW`
- publish도 destination이 생기면 실패
- final 직전 parent/final path 재검증
- overwrite를 기본 허용하지 않음

TOCTOU를 path string 비교만으로 완전히 해결했다고 주장하지 않습니다.

### 16.3 기존 파일

현재 제품 계약은 destination이 이미 있으면 실패입니다. Windows에서도 조용히 덮어쓰지 않습니다.

향후 replace UX를 넣을 경우:

- 사용자 명시 동의
- `ReplaceFileW` + backup/journal 평가
- ACL/attributes/alternate streams 상속 의미 검토
- `REPLACEFILE_WRITE_THROUGH`는 공식 문서상 지원되지 않음을 고려
- failure code별 복구 시나리오

## 17. source snapshot과 변경 race

내보내기 도중 source가 바뀌면 같은 recipe가 다른 픽셀에 적용될 수 있습니다. current macOS는 stable staging copy와 source generation 재확인을 사용합니다.

Windows 권장 두 경로:

### A. handle-backed stable read

1. cloud placeholder materialize
2. source를 read-only로 열고 write/delete sharing을 제한
3. final path, volume/file ID, size, timestamps, optional hash 기록
4. WIC `IStream`, libtiff client I/O, LibRaw custom datastream이 같은 handle/snapshot을 읽음
5. publish 직전 identity 재확인

장점: 거대한 source 복사를 피합니다.  
제약: provider/codec과 sharing 호환성을 실제 검증해야 합니다.

### B. source-volume snapshot

handle-backed decode를 지원하지 않는 경로에서는 source와 같은 volume에 immutable staging copy를 만듭니다.

- 가능하면 filesystem clone/offload를 기능 탐색
- 안 되면 취소 가능한 실제 copy
- destination volume로 source를 불필요하게 복사하지 않음
- copy 뒤 size/hash/identity 확인
- original pair도 이 검증된 snapshot에서 생성

source 변경을 감지하면 이미 인코드가 끝났더라도 publish하지 않습니다.

## 18. staging과 journal

### 18.1 staging 위치

output artifact staging directory는 final destination과 같은 directory/volume에 둡니다.

```text
<destination>/.negaflow-export-<transaction-id>.tmp/
```

이유:

- final publish가 cross-volume copy/delete로 바뀌지 않음
- 같은 volume rename 사용
- cloud/network filesystem 특성을 한 경계에서 다룸
- crash cleanup owner 식별

### 18.2 상태

```text
preparing
  → prepared-and-verified
  → publish-intent-durable
  → artifacts-publishing
  → catalog-commit-intent
  → catalog-commit-attempted
  → catalog-committed
  → finalized
```

정확한 상태 이름은 구현에서 단순화할 수 있지만 다음 질문에 답할 수 있어야 합니다.

- 어느 artifact가 staged됐는가
- 어느 artifact가 final로 게시됐는가
- catalog event가 확정됐는가
- cleanup을 해도 안전한가
- 재시작 후 roll-forward/rollback 중 무엇을 해야 하는가

### 18.3 durability

- encoder close/finalize
- artifact readback
- 중요 journal update 뒤 flush
- 최종 publish 직전 journal intent durable
- artifact file handle에 필요한 시점에 `FlushFileBuffers`
- 모든 작은 write 뒤 flush하지 않음

Windows에는 여러 파일과 catalog를 하나의 범용 filesystem transaction으로 묶는 portable 보증이 없습니다. durable journal이 기준입니다.

### 18.4 publish

새 파일만 허용하는 현재 정책에서는 같은 volume의 `MoveFileExW`를 사용합니다.

- `MOVEFILE_COPY_ALLOWED` 사용 금지
- destination 존재 시 실패
- `MOVEFILE_WRITE_THROUGH` 후보
- 반환값과 `GetLastError` 확인
- 게시 뒤 final file identity/size 재확인

`MOVEFILE_WRITE_THROUGH`가 multi-file atomicity를 주는 것은 아닙니다. 한 artifact씩 게시하는 중 crash가 나면 journal recovery가 상태를 정리합니다.

### 18.5 network/cloud

NTFS 로컬 동작을 SMB, ReFS, FAT/exFAT, OneDrive Files On-Demand에 그대로 가정하지 않습니다.

- filesystem/volume capability 기록
- same-volume 판정
- placeholder materialization
- rename/share violation/retry 분류
- power-loss test
- sync client가 staging을 업로드하는 영향
- orphan staging cleanup

지원하지 못하는 durability 수준이면 사용자에게 제한을 알리고 성공을 과장하지 않습니다.

## 19. 검증 수준

현재 구조처럼 `standard`와 `strict`를 둘 수 있습니다.

### standard

- regular file
- size > 0
- dimensions/bit depth/format
- ICC digest
- key metadata
- source stat/file identity
- journal publish 시 full artifact hash 가능

### strict

- staged artifact full SHA-256
- publish 전 재hash
- original pair full source identity/hash
- primary pixel/profile inspection
- sidecar manifest validation

standard를 “검증 없음”으로 만들지 않습니다. strict는 대형 파일 비용이 있으므로 사용 목적과 UI를 정합니다.

## 20. provenance와 sidecar

RenderManifest는 최소 다음을 묶습니다.

- source identity
- complete render input 또는 source/develop recipe coverage
- decode provenance
- defect recipe hash
- develop recipe hash
- scanner profile ID/hash
- renderer version
- export recipe/configuration hash
- output profile hash
- output artifact size/hash/dimensions
- input kind: source/cleaned memory/cleaned file

Windows 추가 권장:

- backend: CPU/WARP/D3D adapter identity
- shader/kernel package version
- WIC codec CLSID/OS build
- libtiff/LibRaw/LittleCMS version
- JPEG quality mapping version
- dither algorithm version
- architecture x64/ARM64

GPU adapter identity는 결과를 재현하는 단서이지 vendor별 품질 차이를 정당화하는 면허가 아닙니다.

## 21. progress와 취소

사용자가 “0%에서 계속 로딩”으로 보지 않도록 준비와 픽셀 진행을 분리합니다.

```text
Preparing source
Decoding
Rendering
Encoding
Verifying
Publishing
Updating library
```

규칙:

- 첫 파일 preparation을 batch 0%와 구분
- tile/row progress는 실제 completed work 기준
- codec callback의 순서가 비단조여도 UI progress를 뒤로 돌리지 않음
- verification/hash 시간을 별도 단계로 표시
- publish 시작 뒤 취소 의미를 journal 상태와 연결
- catalog commit 뒤에는 “취소”로 파일을 지우지 않음

취소 결과:

- 아직 게시 전: staging 폐기 가능
- 일부 artifact 게시: journal recovery 대상으로 남김
- catalog commit 확정: 완료 처리 후 cleanup
- 상태 불명: 사용자에게 성공/실패를 추측하지 않고 recovery 필요 상태 표시

## 22. 메모리·스레딩

### 22.1 bounded pipeline

```text
decode/render producers
        │ bounded tile queue
        ▼
color/quantize workers
        │ ordered queue
        ▼
single format writer per output file
```

- queue 깊이를 memory budget에 포함
- edge tile 유효 범위 명시
- JPEG/PNG가 full frame을 요구하면 peak memory를 측정하고 row streaming 대안 평가
- TIFF는 strip streaming 우선
- 같은 output encoder 객체를 여러 스레드가 호출하지 않음
- 서로 다른 files는 bounded parallelism

### 22.2 CPU/GPU

- develop/resize/color transform은 vendor-neutral GPU가 빠르면 GPU
- codec/container/metadata/hash는 CPU
- GPU readback 포함 end-to-end가 느리면 CPU tile path
- CPU는 Intel/AMD x64와 ARM64 모두 지원
- CUDA는 NVIDIA 선택적 후속 최적화이며 export 가능 여부를 결정하지 않음

### 22.3 oversubscription

WIC/libtiff/zlib/LittleCMS 내부 동시성과 app thread pool을 함께 측정합니다. 한 파일 안의 과도한 병렬화보다 여러 export의 메모리·IO 균형을 우선합니다.

## 23. codec 선택 gate

### WIC JPEG 유지 조건

- quality mapping 허용
- explicit 4:4:4 적용
- ICC exact embed/readback
- metadata policy 구현
- x64/ARM64 throughput
- corpus no crash

### WIC PNG 유지 조건

- 16-bit exact ramp
- alpha semantics
- ICC/chunks
- metadata privacy
- endian 정확성

### fallback 도입 조건

위 계약 중 하나가 release blocker이고 WIC로 해결할 수 없을 때만:

- JPEG: libjpeg-turbo
- PNG: libpng

fallback을 도입하면 새 dependency license, CVE, SIMD dispatch, ARM64 build, output mapping을 별도 감사합니다. 같은 실행에서 encoder를 조용히 바꾸지 않고 provenance와 feature policy로 고정합니다.

## 24. 오류 모델

| 오류 | 의미 |
|---|---|
| `invalidExportOptions` | 범위·조합 validation 실패 |
| `destinationConflict` | source/artifact path 또는 file identity 충돌 |
| `destinationExists` | overwrite 금지 |
| `sourceChanged` | snapshot 이후 generation 변경 |
| `sourceUnavailable` | cloud materialization/read 실패 |
| `renderFailed` | develop/resize/sharpen/color 단계 실패 |
| `invalidOutputProfile` | general/printer ICC 검증 실패 |
| `encoderUnavailable` | required codec 없음 |
| `encoderCoercedFormat` | bit depth/pixel format 강등 |
| `metadataPolicyFailed` | required metadata/privacy 계약 실패 |
| `artifactVerificationFailed` | readback/hash/dimension/profile 불일치 |
| `publishFailed` | rename/share/permission/filesystem 오류 |
| `catalogCommitIndeterminate` | 파일과 catalog 상태를 즉시 확정 못함 |
| `cancelled` | 단계와 journal 상태에 따른 정상 취소 |

사용자 UI에는 해결 가능한 메시지를 표시하고, 내부에는 HRESULT/Win32/libtiff code와 transaction ID를 남깁니다. 전체 source/output path는 기본 telemetry에서 제거합니다.

## 25. 테스트 매트릭스

### 25.1 공통 옵션

- full dimensions + DPI
- downscale only
- nonzero source origin
- color spaces 3종
- exact printer profile
- alpha on/off
- metadata policies 4종
- output sharpening media 3종
- invalid NaN/Infinity/range

### 25.2 JPEG

- quality grid
- file size/quant tables
- 4:2:0/4:2:2/4:4:4 marker
- alpha rejection
- 8-bit dither statistics
- ICC split APP2 reassembly
- GPS removal

### 25.3 PNG

- 8/16-bit RGB/RGBA
- endian ramp
- alpha 0/partial/1
- ICC/iCCP
- pHYs
- dither only 8-bit

### 25.4 TIFF

- 8/16-bit
- none/LZW/Deflate tag 1/5/8
- RGB/RGBA
- ICC/DPI/orientation
- WIC independent readback
- deterministic 16-bit none with fixed provenance
- Classic size preflight

### 25.5 Raw TIFF

- invalid option 조합 전부 선제 거부
- general import source pixel/profile 보존
- scanner import source pixel/profile 보존
- printer ICC 거부
- develop parameters 미적용
- paired artifact 미생성

### 25.6 artifact transaction

- source symlink/junction/hard link collision
- artifact끼리 overlap
- destination external race
- source replacement before commit
- stage encode 실패
- verification 실패
- artifact N개 중 publish 중간 crash
- catalog intent 전/후 crash
- journal corrupt/future version
- orphan staging recovery
- OneDrive/SMB/ReFS/NTFS
- app restart recovery

### 25.7 architecture/performance

- Intel x64
- AMD x64
- Windows ARM64
- WARP/no GPU
- Intel/NVIDIA/AMD/Qualcomm GPU
- 1장 ordinary export
- 39장 batch와 contact sheet
- large virtual batch
- memory-pressure cancellation

automated pass와 실제 WinUI click-through·외부 앱 상호운용 QA를 구분합니다.

## 26. 단계별 도입

### Phase 0 — encoder spike

- WIC JPEG quality/subsampling
- WIC PNG 16-bit/ICC/alpha
- libtiff 8/16-bit/compression
- LittleCMS output transform
- independent readback

완료 조건: 포맷별 픽셀·ICC·핵심 metadata 계약이 x64/ARM64에서 확인됩니다.

### Phase 1 — single artifact parity

- options/validation
- resize/sharpen/dither
- 일반 profile/printer profile
- Raw TIFF
- source collision

완료 조건: 현재 `ExportEngineTests` 대응 Windows suite가 통과합니다.

### Phase 2 — metadata와 pair

- 정책 4종
- MAIN flat
- original source
- JSON/XMP sidecar
- provenance

완료 조건: `ExportMetadataPolicyTests`와 pair tests가 실제 파일에서 통과합니다.

### Phase 3 — transaction

- stable source handle/snapshot
- same-volume staging
- durable journal
- multi-artifact publish
- catalog commit handshake
- crash recovery

완료 조건: 모든 fault injection 지점에서 기존 source/destination과 catalog가 복구 가능합니다.

### Phase 4 — performance/hardening

- tile pipeline
- batch progress/cancel
- network/cloud filesystem
- malformed metadata/image fuzzing
- codec update regression

완료 조건: 품질을 낮추지 않고 목표 장치 matrix에서 memory·latency budget을 충족합니다.

## 27. 확정 사항과 열린 질문

### 확정

- 포맷 4종과 persisted 의미를 유지합니다.
- JPEG default quality는 1.0입니다.
- PNG/TIFF는 8/16-bit, 8-bit만 dither입니다.
- TIFF compression tag는 1/5/8입니다.
- Raw TIFF는 16-bit uncompressed opaque이며 develop/resize/sharpen/PRINT ICC를 금지합니다.
- WIC JPEG/PNG, libtiff TIFF가 최초 기준입니다.
- encoder pixel format coercion은 실패합니다.
- BigTIFF로 조용히 전환하지 않습니다.
- source와 hard-link/reparse collision을 검사합니다.
- 기존 destination은 덮어쓰지 않습니다.
- 다중 artifact는 journal recovery로 일관성을 만듭니다.
- CPU x64/ARM64 baseline이 항상 있어야 합니다.

### 실측 후 확정

- macOS quality slider와 WIC JPEG mapping table
- quality 0.95 미만 subsampling policy
- WIC PNG를 최종 유지할지
- output sharpening kernel의 exact Windows parity
- Display P3/Adobe RGB canonical profile asset/license
- user-facing BigTIFF 옵션 여부
- source stable handle과 snapshot copy 우선순위
- NTFS/ReFS/SMB/OneDrive publish durability 차이
- standard/strict verification 기본값
- batch concurrency와 memory budget

## 28. 구현 전 체크리스트

- [ ] 포맷 enum/persisted value 동결
- [ ] 모든 옵션의 preflight validation
- [ ] render stage 순서 golden
- [ ] downscale-only geometry와 proxy gate
- [ ] output sharpening parameter parity
- [ ] 8-bit coordinate-stable dither
- [ ] canonical sRGB/P3/Adobe assets와 digest
- [ ] printer ICC strict validation
- [ ] WIC JPEG explicit subsampling + marker readback
- [ ] WIC PNG 16-bit endian/alpha/ICC round-trip
- [ ] libtiff tag/compression/readback
- [ ] Raw TIFF source domain tests
- [ ] metadata allowlist와 privacy negative tests
- [ ] effective DPI rules
- [ ] artifact suffix/layout parity
- [ ] path/reparse/hard-link/file-ID checks
- [ ] source generation lock/snapshot
- [ ] same-volume staging
- [ ] journal flush/publish/recovery
- [ ] catalog commit handshake
- [ ] progress stage와 cancellation semantics
- [ ] x64/ARM64 + WARP + GPU vendor matrix

## 공식 출처

- [Windows Imaging Component Overview](https://learn.microsoft.com/en-us/windows/win32/wic/-wic-about-windows-imaging-codec)
- [WIC native pixel formats](https://learn.microsoft.com/en-us/windows/win32/wic/-wic-codec-native-pixel-formats)
- [WIC Encoding overview](https://learn.microsoft.com/en-us/windows/win32/wic/-wic-creating-encoder)
- [WIC JPEG format overview](https://learn.microsoft.com/en-us/windows/win32/wic/jpeg-format-overview)
- [`WICJpegYCrCbSubsamplingOption`](https://learn.microsoft.com/en-us/windows/win32/api/wincodec/ne-wincodec-wicjpegycrcbsubsamplingoption)
- [WIC PNG format overview](https://learn.microsoft.com/en-us/windows/win32/wic/png-format-overview)
- [WIC metadata overview](https://learn.microsoft.com/en-us/windows/win32/wic/-wic-about-metadata)
- [`IWICBitmapFrameEncode`](https://learn.microsoft.com/en-us/windows/win32/api/wincodec/nn-wincodec-iwicbitmapframeencode)
- [Using the TIFF Library — libtiff 4.7.2](https://libtiff.gitlab.io/libtiff/libtiff.html)
- [`MoveFileExW`](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-movefileexw)
- [`ReplaceFileW`](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-replacefilew)
- [`FlushFileBuffers`](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-flushfilebuffers)
- [`GetFinalPathNameByHandleW`](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-getfinalpathnamebyhandlew)
- [Hard Links and Junctions](https://learn.microsoft.com/en-us/windows/win32/fileio/hard-links-and-junctions)

## 관련 문서

- [wic.md](wic.md)
- [libtiff.md](libtiff.md)
- [libraw.md](libraw.md)
- [../04-color-management/color-pipeline.md](../04-color-management/color-pipeline.md)
- [../04-color-management/lcms2.md](../04-color-management/lcms2.md)
- [../06-large-images/image-source-tiling.md](../06-large-images/image-source-tiling.md)
- [../07-threading/multithreading-export.md](../07-threading/multithreading-export.md)
- [../14-persistence/catalog-and-storage.md](../14-persistence/catalog-and-storage.md)
- [../12-performance/ci-and-testing.md](../12-performance/ci-and-testing.md)
- [../99-plan/product-invariants.md](../99-plan/product-invariants.md)
