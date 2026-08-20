# libtiff 설계 — TIFF 정밀도·태그·스트리밍·BigTIFF

조사 기준일: 2026-08-04  
기준 버전: libtiff 4.7.2  
대상: Windows x64와 ARM64, 네이티브 C++ 엔진

## 결론

Negaflow Windows판은 TIFF **쓰기 기준 구현**으로 libtiff를 사용합니다. 읽기는 WIC를 먼저 사용할 수 있지만, WIC가 정밀도·레이아웃·태그 계약을 만족하지 못하는 TIFF는 libtiff로 처리합니다.

선택 이유:

- 8/16-bit 정수 샘플과 필요 시 32-bit float TIFF를 명시적으로 제어할 수 있습니다.
- none/LZW/Deflate 압축 태그를 현재 macOS 계약과 같은 값으로 기록할 수 있습니다.
- ICC, resolution, orientation, alpha, sample format, strips/tiles를 직접 검증할 수 있습니다.
- 전체 프레임을 한 번에 복제하지 않고 행·스트립·타일 단위로 처리할 수 있습니다.
- Classic TIFF와 BigTIFF를 파일 생성 전에 명시적으로 선택할 수 있습니다.
- Windows Unicode 경로와 per-handle 오류 처리·메모리 제한 API를 제공합니다.

libtiff가 Negaflow의 색 관리, 현상 파이프라인, 메타데이터 개인정보 정책을 결정하지는 않습니다. 이 라이브러리는 TIFF 컨테이너 어댑터입니다.

## 1. 현재 제품 계약

현재 macOS 구현의 TIFF 출력은 두 종류입니다.

| 제품 포맷 | 비트 심도 | 압축 | 알파 | 추가 처리 |
|---|---:|---|---|---|
| `tiff16` | 8 또는 16 | none/LZW/Deflate | 선택 | resize, sharpen, color output 가능 |
| `rawScanTIFF` | 16 고정 | none 고정 | 불투명 고정 | resize·sharpen·printer ICC 금지 |

압축 값은 TIFF 태그 값과 같습니다.

```text
none      = 1 = COMPRESSION_NONE
LZW       = 5 = COMPRESSION_LZW
Deflate   = 8 = COMPRESSION_ADOBE_DEFLATE
```

`COMPRESSION_DEFLATE = 32946`을 현재 `deflate` 설정에 사용하지 않습니다. macOS가 기록하는 값 8과 일치시키기 위해 `COMPRESSION_ADOBE_DEFLATE`를 사용합니다.

## 2. 의존성과 라이선스

### 2.1 버전

2026-08-04 기준:

- upstream 문서 최신 안정 계열: 4.7.2
- 현재 vcpkg `tiff` 포트: 4.7.2
- CMake target: `TIFF::TIFF`

manifest는 baseline을 고정하고 실제 빌드 artifact의 버전·해시를 SBOM에 기록합니다.

### 2.2 라이선스

libtiff는 프로젝트 고유의 permissive 라이선스를 사용합니다. 배포물에 저작권·permission notice를 포함하고, 이름을 홍보에 임의 사용하지 않습니다. LZW 구현에 딸린 별도 Berkeley notice도 upstream license 파일 그대로 보존합니다.

법무 체크리스트:

- [ ] upstream `LICENSE.md`를 Third-Party Notices에 포함
- [ ] LZW notice 포함 여부 확인
- [ ] 정적/동적 링크 방식과 실제 패키지 파일 기록
- [ ] transitive compression dependency license 기록
- [ ] 수정한 libtiff 소스가 있다면 patch provenance 기록

### 2.3 vcpkg feature 최소화

현재 vcpkg 기본 feature는 `jpeg`, `lzma`, `zip`입니다. Negaflow의 TIFF 출력 계약에는 none, LZW, Deflate만 필요합니다.

권장 manifest 개념:

```json
{
  "name": "tiff",
  "default-features": false,
  "features": ["zip"]
}
```

- LZW는 libtiff 자체 구현을 사용합니다.
- Deflate를 위해 `zip`/zlib만 활성화합니다.
- JPEG-in-TIFF, LZMA, WebP, Zstd, LERC는 제품 요구가 생기기 전까지 넣지 않습니다.
- `tools`와 `cxx`도 앱 런타임에 필요하지 않으면 끕니다.

실제 port feature와 빌드 결과는 baseline 갱신 때 다시 감사합니다.

## 3. 아키텍처 경계

```text
ExportCoordinator
        │
        ├── Render/resize/sharpen
        ├── LittleCMS output transform
        ├── quantize + optional 8-bit dither
        │
        ▼
TiffEncoder
  - layout 결정
  - 태그 기록
  - strip/tile 순서화
  - libtiff handle 단독 소유
        │
        ▼
temporary sibling file
        │
        ├── libtiff readback
        ├── WIC/independent readback
        └── atomic publish
```

도메인 계층에 `TIFF*`, tag 번호, compression macro를 노출하지 않습니다. 엔진의 `TiffWriteRequest`를 검증한 뒤 adapter가 libtiff 호출로 변환합니다.

예상 요청 모델:

```text
TiffWriteRequest
  dimensions
  sampleType: uint8 | uint16 | float32
  channels: gray | grayAlpha | rgb | rgba
  alphaMode: none | unassociated
  compression: none | lzw | deflate
  planarConfiguration: contiguous
  organization: strips | tiles
  iccProfileBytes
  resolution
  metadataPolicyResult
  container: classic | big
```

이 모델은 구현 예시이며, 핵심은 사용자 옵션을 libtiff raw 호출 전에 한 번 검증하는 것입니다.

## 4. Windows 파일 열기

Windows 경로는 UTF-16입니다. `TIFFOpenWExt`를 우선합니다.

```text
read Classic/BigTIFF: TIFFOpenWExt(path, "r...", options)
write Classic TIFF:  TIFFOpenWExt(tempPath, "w4...", options)
write BigTIFF:       TIFFOpenWExt(tempPath, "w8...", options)
```

실제 mode suffix는 명시적 정책으로 고정합니다.

- `4`: Classic TIFF 생성
- `8`: BigTIFF 생성
- `m`: 읽기에서 memory map을 끄는 보수 경로
- `D`/`O`: 거대한 strip/tile offset 배열을 지연·on-demand 읽기
- endian 강제는 parity corpus가 필요할 때만 사용

출력은 사용자가 지정한 최종 경로를 바로 `w`로 열지 않습니다. 같은 디렉터리의 충돌 없는 임시 파일을 생성하고 검증 뒤 게시합니다. `w`는 기존 파일을 덮어쓰므로 최종 경로 직접 사용은 데이터 안전 계약과 맞지 않습니다.

libtiff는 쓰기 중 일부 데이터를 다시 읽을 수 있으므로, write-only 핸들만으로 충분하다고 가정하지 않습니다. 파일 공유 플래그·바이러스 검사기·동기화 클라이언트와의 상호작용을 실제 Windows에서 검증합니다.

## 5. `TIFFOpenOptions` 보안 기본값

libtiff 4.5+의 Ext open API와 4.6.1+의 누적 메모리 제한을 사용합니다.

각 handle에 다음을 설정합니다.

- 최대 단일 내부 할당
- 최대 누적 내부 할당
- per-handle re-entrant error handler
- per-handle re-entrant warning handler
- unknown tag 경고 정책

주의할 점:

- 이 제한은 libtiff의 모든 외부 `_TIFFmalloc`/`_TIFFrealloc` 호출을 대신 검증해 주지 않습니다.
- 애플리케이션이 할당하는 scanline/tile/ICC/metadata 버퍼는 별도 budget을 적용합니다.
- 압축 해제 후 크기는 파일 크기보다 훨씬 클 수 있습니다.
- 오류 handler 안에서 예외를 던지거나 UI를 호출하지 않습니다.
- format string을 다시 해석하지 않고 제한된 진단 문자열로 캡처합니다.

예산은 고정 숫자를 모든 장치에 적용하기보다 작업 전체 메모리 관리자와 연결하되, 파일이 주장하는 크기만으로 상한을 높이지 않습니다.

## 6. 읽기 계약

### 6.1 사전 검사

첫 IFD의 픽셀을 읽기 전에 다음 태그를 확인합니다.

- `ImageWidth`, `ImageLength`
- `BitsPerSample`
- `SampleFormat`
- `SamplesPerPixel`
- `PhotometricInterpretation`
- `PlanarConfiguration`
- `Compression`
- `Orientation`
- `ExtraSamples`
- `RowsPerStrip` 또는 `TileWidth`/`TileLength`
- strip/tile count와 byte count
- ICC profile 길이

모든 크기 계산은 checked 64-bit로 수행합니다. `TIFFScanlineSize64` 같은 64-bit API가 있으면 우선 사용하고, `tmsize_t`로 변환할 때 범위를 다시 확인합니다.

### 6.2 지원 baseline

초기 지원 대상:

| 항목 | 허용 |
|---|---|
| 샘플 | unsigned 8/16-bit |
| 채널 | Gray, Gray+Alpha, RGB, RGBA |
| planar | contiguous 우선 |
| 압축 | none, LZW, Deflate |
| 구성 | strips와 tiles |
| byte order | little와 big 모두 읽기 |
| 컨테이너 | Classic TIFF, BigTIFF 읽기 |

다음은 명시적 corpus·제품 요구 전에는 일반 사진으로 자동 해석하지 않습니다.

- palette
- YCbCr
- CIELab
- CMYK without usable ICC
- LogLuv
- signed integer
- float scanner input
- separated planar의 특수 채널
- CFA/raw mosaic TIFF
- JPEG-in-TIFF
- pyramid/subIFD

“libtiff가 읽을 수 있음”과 “Negaflow가 의미를 정확히 해석함”은 다릅니다.

### 6.3 WIC fallback 조건

표준 TIFF 읽기는 WIC fast path를 사용할 수 있습니다. libtiff fallback은 다음처럼 제한합니다.

1. WIC native codec이 입력을 거부
2. WIC가 native 정밀도보다 낮은 포맷만 제공
3. WIC가 필요한 ICC/태그를 노출하지 않음
4. 타일·strip streaming이 메모리 예산상 필요
5. parity corpus에서 WIC 결과가 기준을 벗어남

WIC 실패라면 무엇이든 libtiff로 재시도하는 식의 무제한 fallback은 금지합니다. 공격자가 두 개의 복잡한 디코더를 연속 실행시키는 경로가 될 수 있습니다.

## 7. 샘플 타입과 정밀도

### 7.1 제품 출력

현재 사용자 TIFF 출력은 unsigned 8-bit 또는 unsigned 16-bit입니다.

```text
BitsPerSample = 8 or 16
SampleFormat  = SAMPLEFORMAT_UINT
```

8-bit에서는 working float에서 양자화하기 직전에 출력 디더를 적용합니다. 16-bit에는 디더를 적용하지 않습니다.

### 7.2 32-bit float

libtiff는 32-bit IEEE float TIFF를 표현할 수 있습니다.

```text
BitsPerSample = 32
SampleFormat  = SAMPLEFORMAT_IEEEFP
```

하지만 현재 macOS 제품의 사용자 export 포맷에는 float TIFF가 없습니다. 그러므로 Windows v1 UI에 새 포맷으로 노출하지 않습니다.

사용 가능성이 있는 곳:

- 엔진 진단 artifact
- 내부 parity dump
- 색·필터 회귀 테스트

진단용 float TIFF도 ICC와 working-space 설명을 함께 기록해야 합니다. 단순히 float라는 이유로 scene-linear 의미가 자동 생기지 않습니다.

### 7.3 half-float

16-bit IEEE half TIFF는 baseline에서 금지합니다.

- reader 호환성이 일관되지 않습니다.
- 현재 제품 요구가 없습니다.
- FP16 GPU 표면을 파일에 그대로 덤프하는 것은 채널·alpha·색공간 의미를 숨깁니다.

내부 GPU staging이 FP16이어도 사용자 TIFF는 명시적으로 16-bit unsigned로 양자화하거나 진단용 32-bit float로 변환합니다.

## 8. 채널과 알파

RGB opaque:

```text
SamplesPerPixel = 3
Photometric     = PHOTOMETRIC_RGB
PlanarConfig    = PLANARCONFIG_CONTIG
```

RGBA:

```text
SamplesPerPixel = 4
Photometric     = PHOTOMETRIC_RGB
ExtraSamples    = EXTRASAMPLE_UNASSALPHA
```

Negaflow의 내부 버퍼가 premultiplied라면 encode 전에 straight/unassociated alpha로 안전하게 변환합니다.

- alpha = 0에서 RGB를 임의로 무한대/NaN으로 만들지 않음
- 거의 0인 alpha의 unpremultiply 정책을 고정
- `preserveAlpha = false`이면 정의된 배경 합성 또는 alpha 제거 정책 사용
- `rawScanTIFF`는 항상 opaque 3채널
- JPEG로 가는 경로는 alpha 옵션 자체를 validation에서 거부

associated alpha를 쓸 이유가 생기면 별도 호환성 corpus가 필요합니다. 태그 없이 4채널을 기록하지 않습니다.

## 9. orientation과 좌표

내보내기 픽셀에는 비파괴 회전이 이미 적용되어 있으므로 다음을 기록합니다.

```text
Orientation = ORIENTATION_TOPLEFT
```

원본 orientation을 그대로 복사하지 않습니다. 그렇게 하면 다운스트림 앱이 회전을 다시 적용합니다.

스캐너 raw 저장 경로도 장치 ROI 좌표와 파일 픽셀 좌표의 관계를 manifest에 기록하되, TIFF orientation으로 암묵 변환하지 않습니다.

## 10. ICC 프로파일

ICC는 `TIFFTAG_ICCPROFILE`에 원본 출력 프로파일 바이트를 기록합니다.

필수 검증:

1. LittleCMS에서 profile open 성공
2. expected color space와 채널 수 일치
3. 길이가 32-bit tag count와 제품 상한 안
4. 프로파일 바이트가 export job 동안 immutable
5. write 후 tag length와 digest readback
6. 독립 decoder에서도 profile 인식 확인

출력 종류별 규칙:

- 일반 TIFF: 선택한 sRGB/P3/Adobe RGB 또는 printer ICC
- paired MAIN flat sibling: 일반 export color space; primary printer ICC를 무조건 복사하지 않음
- `rawScanTIFF`: 로드된 source profile 또는 명시된 linear working profile를 보존, printer ICC 금지
- profile 없는 scanner raw: 파일만으로 의미가 충분하지 않으므로 sidecar/manifest의 `linearScannerRaw` provenance 유지

ICC가 기록되지 않았는데 TIFF 인코드가 성공했다는 이유로 export를 게시하지 않습니다.

## 11. 해상도 태그

`dpi > 0`이면 다음을 기록합니다.

```text
XResolution   = dpi
YResolution   = dpi
ResolutionUnit = RESUNIT_INCH
```

`dpi == 0`이면 사용자가 지정하지 않은 값입니다. libtiff의 기본 `ResolutionUnit = inch`가 존재한다고 해서 임의 X/Y resolution을 발명하지 않습니다.

- 정수가 아닌 내부 값이 필요해도 TIFF rational 표현 범위를 확인
- 0, 음수, NaN, Infinity 거부
- resize와 DPI는 독립: pixel dimensions를 바꿔도 DPI를 자동 추론하지 않음
- readback에서 X/Y/단위를 모두 확인

## 12. 메타데이터

### 12.1 원칙

libtiff가 지원하는 모든 태그를 원본에서 복사하지 않습니다. 현재 제품 정책을 통과한 allowlist만 기록합니다.

- `all`: 안전하게 파싱하고 지원하는 필드만 기록
- `removeLocation`: GPS IFD와 위치 IPTC 미기록
- `copyrightOnly`: author/copyright/credit/source/rights만 기록
- `minimal`: source metadata 미기록

scanner make/model, software, date, film comment는 정책에 따라 새로 생성합니다. source date가 없으면 촬영일을 만들지 않습니다.

### 12.2 복잡한 IFD

EXIF·GPS·SubIFD 쓰기는 tag 하나를 설정하는 것보다 복잡합니다. directory offset과 작성 순서를 잘못 다루면 파일은 열리지만 metadata가 사라질 수 있습니다.

따라서 초기 구현은 다음 중 하나를 스파이크에서 확정합니다.

1. libtiff로 raster와 허용 metadata를 모두 작성
2. libtiff raster 작성 후 WIC metadata writer로 안전하게 갱신

2번은 fast metadata encoding 지원, 재작성에 필요한 padding, ICC/strip offset 보존을 corpus로 증명한 경우에만 사용합니다. 기본 방향은 한 writer가 최종 컨테이너를 소유하는 1번입니다.

MakerNote와 vendor 사설 blob의 완전 보존을 `all` 정책의 무조건적 약속으로 만들지 않습니다. 보존 불가 항목은 사용자 데이터 모델과 문서에 정직하게 표시합니다.

## 13. strips와 tiles

### 13.1 사용자 export

일반 JPEG/PNG/TIFF 소비자 호환성과 순차 내보내기를 위해 strip 구성을 기본으로 합니다.

- `RowsPerStrip`은 목표 uncompressed strip byte budget으로 결정
- 전체 높이 하나의 거대한 strip 금지
- 너무 작은 strip으로 directory overhead와 codec 호출을 폭증시키지 않음
- 행 순서로 write

실측 시작점은 256 KiB~1 MiB uncompressed strip이지만, 고정 정답으로 문서화하지 않습니다. x64/ARM64와 none/LZW/Deflate 벤치로 결정합니다.

### 13.2 내부 캐시

random ROI와 화면 타일 재사용이 필요한 app-owned TIFF 캐시는 tile 구성을 고려할 수 있습니다.

- 타일 크기는 엔진 타일·GPU upload와 맞춤
- edge tile의 유효 영역과 padding을 구분
- 모든 타일이 전체 픽셀을 중복·누락 없이 덮는지 검증
- 동일 캐시를 여러 스레드가 동시에 쓰지 않음

사용자 TIFF export와 내부 캐시 포맷을 같은 레이아웃 정책으로 묶지 않습니다.

### 13.3 읽기 API 선택

- striped file: strip/scanline API
- tiled file: tile API
- tiled 입력을 scanline API로 억지 처리하지 않음
- compressed strip의 임의 scanline 접근은 반복 해제를 유발할 수 있으므로 strip 전체 단위로 계획

조직 형태는 tag에서 읽고 그에 맞는 API를 사용합니다.

## 14. Classic TIFF와 BigTIFF

### 14.1 경계

Classic TIFF는 32-bit offset을 사용하므로 약 4 GiB 경계가 있습니다. BigTIFF는 64-bit offset을 사용하며 `w8`로 파일 생성 전에 선택합니다.

중요한 점은 **픽셀 수만으로 압축 파일 크기를 정확히 알 수 없다는 것**입니다.

- uncompressed는 raster byte와 metadata/IFD overhead의 상한을 비교적 정확히 계산 가능
- LZW/Deflate는 실제 데이터에 따라 크기가 달라짐
- ICC/XMP/EXIF와 strip/tile arrays도 공간을 차지함
- 일부 악성·비정상 입력은 예상보다 큰 metadata를 주장

중간에 Classic TIFF를 BigTIFF로 변환하는 방식은 사용하지 않습니다. 생성 전에 선택합니다.

### 14.2 안전한 preflight

checked 64-bit로 다음을 계산합니다.

```text
rasterUpperBound
+ stripOrTileArrayUpperBound
+ metadataUpperBound
+ IFDAndAlignmentMargin
+ safetyMargin
```

압축 출력은 “보통 줄어든다”를 근거로 Classic을 선택하지 않습니다. 보수 upper bound가 Classic 한계를 넘으면 Classic 출력은 시작하지 않습니다.

### 14.3 제품 정책

BigTIFF는 같은 `.tif` 확장자를 사용하지만 일부 다운스트림 앱이 읽지 못합니다. 따라서 사용자 export에서 조용히 전환하면 안 됩니다.

초기 권장:

- 일반 export 기본: Classic TIFF
- Classic 한계 위험: encode 전에 명시적 오류와 해결 안내
- BigTIFF: 호환성 matrix를 확보한 뒤 명시 옵션으로 제공
- app-owned internal cache: manifest에 format을 기록하면 자동 BigTIFF 허용 가능
- `rawScanTIFF`: 원본 보존 요구와 호환성 사이의 UI 결정을 별도 확정

현재 macOS 동작보다 조용히 포맷 범위를 넓혀 99.9% parity를 깨지 않습니다.

## 15. 쓰기 순서

일반 TIFF 한 장의 기준 순서:

1. 요청 옵션 전체 validation
2. source/output 충돌과 hard-link identity 확인
3. 최종 크기·sample·channel·예산 preflight
4. Classic/BigTIFF 선택
5. sibling temporary path 생성
6. `TIFFOpenWExt`와 per-handle options 설정
7. 필수 image tags 기록
8. ICC·resolution·metadata 기록
9. 렌더/색 변환/양자화된 행 또는 타일 기록
10. 모든 write 반환값 확인
11. directory/handle finalize
12. libtiff readback
13. 독립 WIC readback
14. digest·dimensions·tags·픽셀 표본 확인
15. 취소·revision/session identity 재확인
16. atomic publish transaction

어느 단계든 실패하면 임시 파일을 최종 이름으로 게시하지 않습니다. 원본 파일은 건드리지 않습니다.

## 16. `rawScanTIFF` 특수 계약

`rawScanTIFF`는 일반 TIFF preset이 아니라 원본 보존 경로입니다.

validation:

- 16-bit unsigned
- uncompressed
- opaque RGB 또는 명시된 source channel contract
- original pixel dimensions
- resize 없음
- output sharpening 없음
- dither 없음
- printer profile 없음
- develop pipeline 우회
- loaded input profile/pixel 의미 보존

“raw”는 카메라 CFA RAW를 뜻하지 않습니다. Negaflow가 로드한 scanner raw pixel domain을 보존한다는 제품 용어입니다. 파일에 source role과 decode provenance가 없으면 재해석이 달라질 수 있으므로 sidecar/manifest가 함께 필요합니다.

## 17. 스레딩

libtiff 공식 문서의 기준:

- 열린 TIFF의 상태는 handle에 캡슐화됩니다.
- per-handle error/warning handler를 쓰면 서로 다른 handle의 병렬 처리가 가능합니다.
- 같은 TIFF 파일을 여러 스레드가 동시에 편집하는 것은 안전하지 않습니다.

Negaflow 규칙:

1. 한 output file은 한 writer task와 한 `TIFF*`가 소유
2. 서로 다른 export 파일은 bounded pool에서 병렬 처리 가능
3. 한 파일 내부 render/tile 계산은 병렬화 가능
4. libtiff write 호출은 순서가 보장된 단일 writer로 직렬화
5. queue 깊이를 제한하여 완성 타일이 메모리에 무한 축적되지 않게 함
6. 전역 `TIFFSetErrorHandler` 대신 ExtR per-handle handler 사용

압축을 위해 file 하나를 여러 handle로 나눠 쓰고 나중에 합치지 않습니다.

## 18. 취소

취소는 다음 경계에서 확인합니다.

- 파일 열기 전
- 렌더 타일 제출 전/후
- strip/tile write 사이
- metadata finalize 전
- readback 전/후
- publish 직전

이미 호출된 codec 압축을 강제 중단하기 위해 스레드를 종료하지 않습니다. 청크 크기와 동시 작업 수를 조절해 최대 취소 지연을 제한합니다.

취소 시:

- producer 중단
- writer queue drain 또는 폐기
- handle 정상 close/cleanup
- 임시 파일을 recoverable cleanup 정책에 따라 제거
- 카탈로그·UI에 결과 미게시

## 19. 오류 처리

libtiff 진단 메시지는 제품 오류와 분리합니다.

| 제품 오류 | 예시 |
|---|---|
| `invalidTiffHeader` | magic/version/IFD 손상 |
| `unsupportedTiffLayout` | sample/photometric/planar 미지원 |
| `invalidTiffDimensions` | 0, overflow, 예산 초과 |
| `unsupportedCompression` | baseline 밖 codec |
| `classicTiffLimitExceeded` | 안전 upper bound가 Classic 한계 초과 |
| `tiffAllocationLimit` | per-handle 또는 app memory budget 초과 |
| `tiffWriteFailed` | scanline/strip/tile 반환 실패 |
| `tiffMetadataFailed` | 필수 ICC/metadata 기록 실패 |
| `tiffReadbackMismatch` | 태그·픽셀·digest 불일치 |
| `cancelled` | 사용자 취소 또는 stale revision |

경고를 무시한 채 성공 처리하지 않습니다. 다만 unknown private tag 경고처럼 제품 결과와 무관한 항목은 분류하여 로그 노이즈를 제한합니다.

## 20. 보안과 fuzzing

libtiff는 복잡하고 오래된 컨테이너를 처리합니다. 최신 버전 고정만으로 안전이 끝나지 않습니다.

필수 방어:

- dependency update 감시
- upstream security advisory 확인
- ASan/UBSan 가능한 host fuzz job
- Windows x64/ARM64 corpus test
- 최대 IFD/SubIFD 수
- 최대 strip/tile 수
- 최대 ICC/XMP/IPTC 길이
- recursion/depth 상한
- checked offset+length 범위
- decompressed byte budget
- timeout/cancellation 관찰

corpus:

- 잘린 header/IFD
- 순환 directory offset
- offset+bytecount overflow
- zero-sized/거대 strip
- tile dimension overflow
- mismatched samples/bits arrays
- 잘린 LZW/Deflate stream
- invalid predictor
- BigTIFF endian 양쪽
- huge sparse file
- malformed ICC/EXIF/GPS/SubIFD

손상 TIFF가 실패하는 것은 정상입니다. 목표는 크래시·hang·무한 할당·원본 변경 없이 일관된 오류를 반환하는 것입니다.

## 21. 성능

측정할 항목:

- WIC vs libtiff 16-bit decode throughput
- strip 크기별 none/LZW/Deflate encode throughput
- x64 Intel/AMD와 ARM64 CPU 시간
- peak committed memory
- first-preview latency
- cancellation latency
- Classic/BigTIFF directory overhead
- ICC/metadata write/readback 비용

CPU 우선 원칙:

- 컨테이너 압축·태그 작성은 CPU가 담당
- GPU는 render/resize/color stage에서 이득이 검증될 때 사용
- GPU readback 때문에 전체 export가 느려지면 CPU tile path 사용
- CUDA 전용 TIFF encode 경로를 만들지 않음

SIMD는 libtiff ABI 바깥의 픽셀 변환·quantization에 적용하며, codec 내부 구현을 제품 코드에서 fork하지 않습니다.

## 22. 테스트

### 22.1 round-trip

- 8-bit RGB/RGBA none/LZW/Deflate
- 16-bit RGB/RGBA none/LZW/Deflate
- grayscale/gray alpha 입력 읽기
- little/big endian 읽기
- strip/tile 읽기
- Classic/BigTIFF 읽기
- ICC profile byte/digest
- DPI와 resolution unit
- orientation=1

### 22.2 픽셀 정확도

- 16-bit ramp exact round-trip
- channel impulse로 RGB 순서 확인
- alpha 0/1/중간값
- odd width와 padded stride
- edge strip/tile
- deterministic uncompressed TIFF with fixed metadata
- LZW/Deflate decode 결과가 none과 동일

압축 파일 byte-for-byte 동일성을 모든 버전에서 요구하지 않습니다. 픽셀·태그·명시한 deterministic 범위만 고정합니다.

### 22.3 제품 계약

- `rawScanTIFF` 잘못된 옵션 전부 거부
- printer ICC가 raw에 들어가지 않음
- general TIFF에 exact output profile
- paired MAIN flat profile 분리
- source/output 같은 파일 및 hard link 거부
- metadata policy별 금지 태그 부재
- source date 없을 때 original date 미생성
- final publish 전 실패 시 기존 파일 보존

### 22.4 독립 상호운용성

최소 다음 reader로 corpus를 확인합니다.

- WIC native TIFF decoder
- libtiff current pinned build
- macOS ImageIO가 생성한 기준 파일
- macOS ImageIO에서 Windows 출력 readback
- 대표 외부 편집기/인화 워크플로는 수동 QA

외부 앱에서 “열린다”만 확인하지 않고 bit depth, ICC, alpha, orientation, DPI를 확인합니다.

## 23. 단계별 도입

### Phase 0 — spike

- vcpkg 4.7.2 x64/ARM64 빌드
- `TIFFOpenWExt` Unicode 경로
- per-handle memory/error options
- 16-bit RGB strips none/LZW/Deflate
- WIC 독립 readback

완료 조건: 기본 corpus의 픽셀과 핵심 태그가 정확합니다.

### Phase 1 — 현재 export parity

- 8/16-bit TIFF
- alpha
- ICC/DPI/metadata
- rawScanTIFF validation
- temporary + atomic publish 연결

완료 조건: 현재 macOS `ExportEngineTests` 대응 계약이 통과합니다.

### Phase 2 — 대형 파일과 streaming

- memory budget
- strip/tile producer-consumer
- Classic preflight
- BigTIFF internal cache

완료 조건: 대형 virtual image가 전체 프레임 복제 없이 처리되고 취소가 bounded입니다.

### Phase 3 — hardening

- fuzzing
- malformed corpus
- multi-file parallel export
- dependency update/reproducibility gate

완료 조건: 지원하지 않는 입력도 안전하고 설명 가능한 방식으로 실패합니다.

## 24. 확정 사항과 열린 질문

### 확정

- TIFF write 기준은 libtiff입니다.
- 현재 사용자 출력은 unsigned 8/16-bit입니다.
- compression 값 1/5/8을 유지합니다.
- half-float TIFF는 사용하지 않습니다.
- 한 파일은 한 writer handle이 소유합니다.
- `TIFFOpenWExt`와 per-handle 제한·handler를 사용합니다.
- Classic/BigTIFF는 파일 생성 전에 선택합니다.
- 사용자 export에서 BigTIFF로 조용히 전환하지 않습니다.

### 실측 후 확정

- 사용자 BigTIFF 옵션 노출 여부
- rawScanTIFF가 4 GiB 위험일 때의 UX
- strip byte target
- standard TIFF read의 WIC/libtiff 우선순위
- EXIF/GPS 작성의 단일 libtiff writer 범위
- internal cache를 TIFF로 유지할지 별도 tile container로 갈지
- Deflate level과 ARM64 성능 기본값

## 25. 구현 전 체크리스트

- [ ] vcpkg baseline과 4.7.2 artifact hash 고정
- [ ] Third-Party Notices에 libtiff/LZW/zlib 반영
- [ ] default feature를 끄고 `zip`만 필요한지 빌드 확인
- [ ] Unicode temporary path와 atomic publish 설계
- [ ] `TIFFOpenWExt` options 예산 정의
- [ ] checked size/offset helper 정의
- [ ] sample/channel/alpha/layout allowlist 정의
- [ ] ICC tag write/readback
- [ ] orientation=top-left 강제
- [ ] DPI 0/positive 정책
- [ ] metadata allowlist와 GPS negative tests
- [ ] strip/tile queue backpressure
- [ ] Classic upper-bound 계산
- [ ] BigTIFF compatibility corpus
- [ ] WIC 독립 readback
- [ ] fuzz corpus와 dependency advisory gate

## 공식 출처

- [Using the TIFF Library — libtiff 4.7.2](https://libtiff.gitlab.io/libtiff/libtiff.html)
- [`TIFFOpen` and mode options](https://libtiff.gitlab.io/libtiff/functions/TIFFOpen.html)
- [`TIFFOpenOptions`](https://libtiff.gitlab.io/libtiff/functions/TIFFOpenOptions.html)
- [Per-handle error handling](https://libtiff.gitlab.io/libtiff/functions/TIFFError.html)
- [Scanline interface](https://libtiff.gitlab.io/libtiff/functions/TIFFReadScanline.html)
- [Strip interface](https://libtiff.gitlab.io/libtiff/functions/TIFFReadEncodedStrip.html)
- [Tile interface](https://libtiff.gitlab.io/libtiff/functions/TIFFReadTile.html)
- [libtiff 4.7.2 license](https://gitlab.com/libtiff/libtiff/-/blob/v4.7.2/LICENSE.md)
- [BigTIFF design](https://bigtiff.org/)
- [vcpkg `tiff` port manifest](https://github.com/microsoft/vcpkg/blob/master/ports/tiff/vcpkg.json)
- [vcpkg `tiff` CMake usage](https://github.com/microsoft/vcpkg/blob/master/ports/tiff/usage)

## 관련 문서

- [wic.md](wic.md)
- [export-formats.md](export-formats.md)
- [../04-color-management/color-pipeline.md](../04-color-management/color-pipeline.md)
- [../06-large-images/image-source-tiling.md](../06-large-images/image-source-tiling.md)
- [../07-threading/multithreading-export.md](../07-threading/multithreading-export.md)
- [../12-performance/ci-and-testing.md](../12-performance/ci-and-testing.md)
