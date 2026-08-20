# WIC 설계 — 표준 이미지 디코드·메타데이터·JPEG/PNG 인코드

조사 기준일: 2026-08-04  
대상: Windows 11 데스크톱, WinUI 3 셸과 네이티브 C++ 이미지 엔진  
macOS 근거: `Sources/Chromabase/Imaging/ImageLoader/`, `Sources/Chromabase/Export/`

## 결론

Windows Imaging Component(WIC)는 Negaflow Windows판의 **표준 이미지 컨테이너 입구**로 사용합니다.

- JPEG·PNG·BMP와 일반 TIFF의 컨테이너 식별, 프레임 정보, 썸네일, 메타데이터 읽기
- JPEG 8-bit와 PNG 8/16-bit 인코드 후보
- 픽셀 포맷 변환과 방향 메타데이터 읽기
- 내장 또는 Microsoft 확장 코덱의 기능 탐색

다만 WIC를 이미지 파이프라인 전체나 색 관리의 기준 구현으로 사용하지는 않습니다.

- 작업 공간 변환과 ICC 처리는 LittleCMS가 기준입니다.
- TIFF 쓰기는 비트 심도·압축·태그·스트리밍을 통제할 수 있는 libtiff가 기준입니다.
- 카메라 RAW는 설치 상태가 달라지는 WIC RAW 코덱이 아니라 LibRaw가 기준입니다.
- WinUI 미리보기 렌더링은 WIC 비트맵을 그대로 붙잡는 구조가 아니라 엔진의 정규화된 이미지 표면을 사용합니다.
- 사용자가 설치한 임의의 서드파티 WIC 코덱을 프로덕션 입력 경로에서 자동 신뢰하지 않습니다.

WIC의 장점은 Windows 기본 구성 요소라는 점입니다. 반대로 플러그인 방식으로 코덱이 런타임 등록되는 구조이므로, 재현성과 공격 표면을 애플리케이션이 직접 제한해야 합니다.

## 1. 현재 macOS 계약에서 옮길 것

현재 구현은 단순한 파일 열기보다 더 많은 의미를 갖습니다. Windows 포트는 아래 계약을 보존해야 합니다.

| 현재 계약 | Windows 구현 |
|---|---|
| 표준 입력 확장자 `tiff/tif/jpeg/jpg/png/heic/heif/bmp` | WIC 컨테이너 검사 후 허용 포맷으로 확정 |
| 카메라 RAW와 일반 이미지 분리 | RAW는 LibRaw, 표준 이미지는 WIC/libtiff |
| 임베디드 ICC 존중 | ICC 바이트를 추출·검증한 뒤 LittleCMS로 작업 공간 변환 |
| ICC 없는 16-bit 이상 TIFF의 역할 명시 | `standardImage`와 `linearScannerRaw`를 호출자가 명시 |
| ICC 없는 PNG를 임의로 linear로 보지 않음 | PNG 기본 정책을 표준 이미지로 유지 |
| 일반 가져오기는 EXIF orientation 적용 | 픽셀에 한 번만 굽고 이후 orientation을 1로 정규화 |
| 스캐너 원본은 EXIF orientation을 자동 적용하지 않음 | 장치·세션의 비파괴 회전과 중복되지 않게 별도 경로 유지 |
| 풀해상도는 한 번 완전 디코드하여 재사용 | 지연 디코더 객체를 UI·GPU 스레드 사이에 공유하지 않음 |
| 프리뷰와 풀해상도 색 해석 동일 | 공통 `SourceInterpretation` 결과를 사용 |
| 손상 입력은 정상 오류로 종료 | 크래시, 범위 초과, 무한 할당, 원본 변경 금지 |
| 디코더 provenance 저장 | 디코더 종류·버전·코덱 CLSID·입력 역할을 기록 |

현재 macOS의 `ImageLoader.defaultRAWBoostAmount = 0.0` 같은 RAW 정책은 WIC가 담당하지 않습니다. [libraw.md](libraw.md)에서 별도로 정의합니다.

## 2. 책임 경계

### 2.1 WIC가 소유하는 것

1. 파일 시그니처와 컨테이너 형식 확인
2. 허용된 WIC 디코더 선택 및 식별
3. 프레임 수, 픽셀 크기, 기본 픽셀 포맷 확인
4. 임베디드 썸네일·프리뷰 조회
5. EXIF·TIFF·IPTC·XMP·GPS 메타데이터 읽기
6. ICC color context 원본 바이트 조회
7. 표준 정수 픽셀 버퍼로 디코드
8. JPEG·PNG 출력 인코더의 협상과 결과 검증

### 2.2 WIC가 소유하지 않는 것

1. 작업 색공간 결정
2. ICC 프로파일 유효성·정책 판단
3. 필름 반전·현상·결함 제거
4. 출력 샤픈·디더링
5. 색 관리된 화면 표시
6. Raw TIFF 의미 판단
7. 카메라 RAW 현상
8. 내보내기 트랜잭션과 최종 파일 게시

이 경계를 지키면 WIC 코덱 동작과 GPU 렌더러 동작이 제품 도메인 로직 안으로 새지 않습니다.

## 3. 제안 계층

```text
WinUI 3 / ViewModel
        │
        ▼
ImageImportService
        │
        ├── SourceClassifier
        │     ├── 확장자 힌트
        │     ├── 파일 시그니처
        │     └── 허용 컨테이너 정책
        │
        ├── WicStandardDecoder ── JPEG / PNG / BMP / HEIF 조건부
        ├── TiffDecoder ───────── WIC fast path + libtiff fallback
        └── RawDecoder ────────── LibRaw
                │
                ▼
DecodedSource
  - 픽셀 또는 타일 공급자
  - 원본 크기·방향
  - ICC 원본 바이트
  - 정제된 메타데이터
  - SourceInterpretation
  - DecodeProvenance
                │
                ▼
LittleCMS → float32 linear working image → Develop pipeline
```

`IWICBitmapSource`나 COM 포인터를 도메인 모델에 노출하지 않습니다. WIC 어댑터가 종료되기 전에 필요한 정보와 픽셀을 소유 버퍼로 옮깁니다.

## 4. 코덱 선택은 결정적이어야 함

WIC는 등록된 코덱을 런타임에 발견합니다. 이는 범용 이미지 뷰어에는 유리하지만, 사진 원본을 다루는 앱에는 다음 문제가 있습니다.

- 같은 파일이 PC마다 다른 코덱으로 열릴 수 있습니다.
- 설치된 코덱 업데이트가 디코드 결과를 바꿀 수 있습니다.
- 파일 확장자만 바꾼 악성 입력이 예상하지 않은 코덱으로 들어갈 수 있습니다.
- 제3자 in-process COM 코덱의 오류가 Negaflow 프로세스에 영향을 줄 수 있습니다.

따라서 프로덕션 기본 정책은 다음과 같습니다.

1. 확장자는 빠른 분류 힌트로만 사용합니다.
2. WIC가 보고한 실제 컨테이너 GUID를 확인합니다.
3. `IWICBitmapDecoder::GetDecoderInfo`에서 선택된 디코더 정보를 읽습니다.
4. JPEG·PNG·BMP·TIFF는 Microsoft 기본 CLSID allowlist와 대조합니다.
5. HEIF는 Microsoft HEIF 확장 코덱의 존재와 실제 디코드 성공을 기능 탐색합니다.
6. 알 수 없는 서드파티 CLSID이면 자동 사용하지 않고 `unsupportedCodec`으로 종료합니다.
7. 향후 서드파티 코덱 지원이 필요하면 별도 opt-in과 별도 프로세스 격리를 설계합니다.

`CreateDecoderFromFilename`의 vendor GUID는 선호값이지 제품 품질 계약 전체가 아닙니다. 최종 선택된 디코더 정보를 다시 읽어 검증합니다. 더 엄격한 경로에서는 알려진 native decoder CLSID를 직접 생성하고 스트림으로 초기화하는 방식을 스파이크에서 비교합니다.

## 5. COM과 스레딩

### 5.1 초기화

- 이미지 작업자 스레드는 `CoInitializeEx(nullptr, COINIT_MULTITHREADED)`로 MTA에 참여합니다.
- 이미 다른 apartment 모델로 초기화된 스레드를 이미지 풀에 재사용하지 않습니다.
- UI 스레드의 STA COM 객체를 이미지 작업자 스레드로 넘기지 않습니다.
- `CoUninitialize`는 같은 스레드의 성공한 초기화와 짝을 맞춥니다.

### 5.2 팩터리 수명

Windows 11 기준으로 `IWICImagingFactory2` 생성을 시도하고, 필요한 기능이 없는 경우 `IWICImagingFactory` 범위만 사용합니다. 팩터리의 존재 자체를 픽셀 디코더 동시성 보증으로 해석하지 않습니다.

권장 규칙:

- 각 작업 스레드가 자신의 COM 인터페이스 그래프를 소유합니다.
- 디코더·프레임·포맷 변환기는 작업 경계를 넘겨 공유하지 않습니다.
- 같은 디코더나 프레임에 동시 호출하지 않습니다.
- 결과가 필요하면 엔진 소유 버퍼로 복사합니다.
- 동시성은 파일 단위로 확보합니다.

WIC는 MTA 호출을 지원하지만, 개별 코덱 구현의 내부 병렬성을 가정하면 안 됩니다. 한 파일을 여러 WIC 객체로 중복 디코드해 속도를 내는 방식도 기본 경로에서 금지합니다.

## 6. 입력 분류

### 6.1 확장자 집합

현재 macOS와 동등한 사용자 선택 필터는 유지합니다.

```text
표준: tif, tiff, jpg, jpeg, png, bmp, heic, heif
RAW:  dng, crw, cr2, cr3, nef, nrw, arw, srf, sr2, raf,
      rw2, raw, orf, pef, srw, 3fr, fff, mef, mos, erf,
      kdc, dcr, k25, rwl, iiq, x3f
```

그러나 파일 선택 필터와 실제 지원 판정은 분리합니다.

### 6.2 판정 순서

1. 경로가 일반 파일인지 확인합니다.
2. 파일 핸들을 읽기 전용·공유 정책에 맞게 엽니다.
3. 크기 상한과 최소 시그니처 길이를 확인합니다.
4. RAW 확장자이면 LibRaw의 `open_file`/식별 경로로 확인합니다.
5. 표준 확장자 또는 확장자 없음이면 WIC 컨테이너를 확인합니다.
6. TIFF 계열이라도 카메라 RAW/DNG이면 표준 TIFF로 오인하지 않습니다.
7. 확장자와 컨테이너가 충돌하면 실제 시그니처를 우선하되 provenance에 충돌을 기록합니다.
8. 제품 allowlist 밖 컨테이너는 WIC가 열 수 있어도 거부합니다.

`unknown → 일반 이미지로 마지막 시도`라는 현재 macOS 동작은 사용자 편의상 유지할 수 있지만, Windows에서는 allowlist 검증을 통과해야 합니다.

## 7. 신뢰할 수 없는 입력 제한

이미지 크기와 메타데이터 값은 파일이 주장하는 값일 뿐입니다. 픽셀 할당 전에 모두 검증합니다.

### 7.1 필수 선검증

- 파일 크기: 제품 최대 입력 크기 이하
- 프레임 수: 1 이상, 제품이 허용한 최대 이하
- 폭·높이: 각각 1 이상, 제품 최대 차원 이하
- `width × height`: checked 64-bit 곱셈
- `rowBytes`: checked 64-bit 계산 후 API의 32-bit 인수 범위 확인
- `rowBytes × height`: 주소 공간·작업 메모리 예산 이하
- ICC 길이: 설정한 최대 크기 이하
- 메타데이터 문자열·배열: 현재 macOS의 4,096 UTF-8 bytes, 배열 128개 상한을 최소 기준으로 적용
- 모든 실수 메타데이터: finite 확인

API가 `UINT` 크기를 받는 곳에 `uint64_t`를 단순 캐스팅하지 않습니다. 32-bit 인수 범위를 넘으면 타일 또는 스트리밍 디코더로 전환하거나 명시적으로 거부합니다.

### 7.2 다중 프레임

Negaflow의 사진 가져오기는 한 파일을 한 원본으로 다룹니다. 초기 버전의 정책은 다음과 같습니다.

- JPEG·PNG·BMP: 정확히 1 프레임 기대
- TIFF: 기본적으로 첫 IFD만 가져오되, 다중 IFD이면 사용자에게 명확히 알리고 자동 무시 여부를 제품 결정으로 남김
- HEIF: 대표 이미지 선택 규칙을 고정하기 전에는 단일 주 이미지로 검증된 corpus만 지원
- 애니메이션·페이지 묶음: 자동으로 여러 라이브러리 항목을 만들지 않음

프레임 0을 무조건 읽는 것은 구현이 아니라 정책 결정이어야 합니다.

## 8. 디코드 순서

표준 파일 한 장의 기준 순서는 다음과 같습니다.

1. 읽기 전용 스트림 생성
2. 허용 디코더 선택
3. 컨테이너 GUID·코덱 CLSID 기록
4. 프레임 수 및 대표 프레임 확인
5. 폭·높이·native pixel format 확인
6. orientation·ICC·메타데이터 읽기
7. `SourceInterpretation` 결정
8. 목표 정수 픽셀 포맷 결정
9. WIC 포맷 변환 또는 코덱 native copy
10. 소유 버퍼로 완전 복사
11. EXIF orientation을 일반 가져오기에서만 한 번 적용
12. LittleCMS로 working space 변환
13. `DecodeProvenance`와 함께 반환

메타데이터 캐시는 다음처럼 구분합니다.

- 미리보기/브라우징: `WICDecodeMetadataCacheOnDemand`
- 가져오기 확정 및 파일 핸들을 빨리 닫아야 하는 경로: 필요한 메타데이터를 명시적으로 읽고 소유 값으로 복사
- `WICDecodeMetadataCacheOnLoad` 사용 여부는 codec corpus로 메모리와 파일 수명을 측정한 뒤 결정

지연 디코드 객체가 원본 스트림을 붙잡을 수 있으므로, COM 객체를 닫은 뒤에도 픽셀을 읽을 수 있다고 가정하지 않습니다.

## 9. 픽셀 포맷 계약

### 9.1 내부 경계

WIC에서 엔진으로 넘기는 기본 정수 경계는 다음과 같습니다.

| 입력 | 우선 경계 포맷 | 비고 |
|---|---|---|
| JPEG | 24bpp RGB/BGR 또는 32bpp RGBA/BGRA 8-bit | JPEG는 알파 없음 |
| PNG 8-bit | 32bpp RGBA | 원래 알파와 straight/premultiplied 상태 명시 |
| PNG 16-bit | 64bpp RGBA 또는 48bpp RGB | 16-bit 값을 보존 |
| TIFF 8-bit | 32bpp RGBA 또는 채널 수에 맞는 포맷 | ICC·photometric 확인 |
| TIFF 16-bit | 64bpp RGBA 또는 48bpp RGB | 스캐너 기본 경로 |
| grayscale | 명시적 Gray 포맷 후 working RGB로 변환 | 채널 복제와 ICC 처리를 혼동하지 않음 |
| CMYK JPEG/TIFF | native CMYK로 수신 후 ICC 기반 RGB 변환 | 임의 수식 변환 금지 |

엔진의 기준 작업 포맷은 float32 linear RGB입니다. WIC의 `128bppRGBAFloat`를 모든 파일에 요구하지 않습니다. 정수 원본을 WIC 내부에서 float으로 올리는 것보다, 원본 정밀도를 보존한 정수 버퍼를 받고 LittleCMS/엔진 경계에서 통제된 방식으로 float으로 변환하는 편이 재현성 검증에 유리합니다.

### 9.2 인코더 포맷 협상

`IWICBitmapFrameEncode::SetPixelFormat`은 요청 포맷을 그대로 보장하지 않습니다. 가장 가까운 지원 포맷으로 인수의 GUID를 바꿀 수 있습니다.

따라서 모든 WIC 인코드 경로는 다음을 강제합니다.

```text
requested = exact format GUID
SetPixelFormat(&negotiated)
if negotiated != requested:
    fail UnsupportedEncoderPixelFormat
```

8-bit 요청이 24bpp/32bpp 채널 순서 차이로 바뀌는 경우도 자동 수용하지 않습니다. 허용 가능한 변환 목록을 포맷별로 정의하고, 변환은 인코더 전에 애플리케이션이 수행합니다. 16-bit 요청이 8-bit로 내려가는 일은 절대 허용하지 않습니다.

### 9.3 stride와 버퍼 크기

- `stride >= packedRowBytes`
- `stride`는 API가 요구하는 정렬을 만족
- `bufferSize >= stride × height`
- `CopyPixels` 사각형은 프레임 범위 안
- 타일 경계는 전체 픽셀 범위를 정확히 한 번 덮음
- 음수 stride나 bottom-up DIB는 엔진 경계 전에 top-down으로 정규화

채널 순서, alpha 표현, endian, transfer function을 포맷 GUID 이름만 보고 추정하지 않고 adapter의 명시 필드로 전달합니다.

## 10. 포맷별 WIC 지원 판단

### 10.1 JPEG

Windows 기본 WIC JPEG 코덱은 8-bit 출력용입니다.

- 디코드: 일반 JPEG 가져오기
- 인코드: 8-bit JPEG 내보내기 후보
- 알파: 지원하지 않음
- 품질: `ImageQuality`를 명시
- 크로마 서브샘플링: `JpegYCrCbSubsampling`을 명시

기본 WIC JPEG 인코더의 기본 서브샘플링은 4:2:0입니다. macOS에서 품질을 0.995로 올려 4:4:4를 유도하는 우회 규칙을 Windows에 복사하지 않습니다.

Windows 규칙:

- 사용자가 고품질 구간을 선택하면 `WICJpegYCrCbSubsampling444`
- 용량 우선 구간은 제품 매핑에 따라 4:2:0 또는 4:2:2
- 품질 0…1 값은 macOS와 출력 크기·PSNR·SSIM·시각 corpus로 보정
- 실제 출력 JPEG의 SOF/샘플링 인자를 재파싱하여 설정이 반영됐는지 테스트

지원하지 않는 property bag 옵션은 코덱이 무시할 수 있으므로, `Write` 성공만으로 옵션 적용을 증명하지 않습니다.

### 10.2 PNG

Windows 기본 WIC PNG 코덱은 8-bit와 16-bit RGB/RGBA 인코드 경로를 제공합니다.

- 8-bit 내보내기: 양자화 직전 출력 디더 적용
- 16-bit 내보내기: 디더 없음
- 알파: 사용자가 보존을 선택한 경우 straight/premultiplied 변환을 명시
- ICC: iCCP 기록 후 readback으로 동일 바이트 또는 의미상 동등 프로파일 확인
- DPI: PNG `pHYs` 의미에 맞게 pixels-per-meter로 변환하고 반올림 규칙 고정

WIC가 endian 처리를 담당하더라도 corpus에서 16-bit ramp를 재디코드하여 샘플 값이 보존되는지 확인합니다. libpng를 fallback으로 도입한다면 Windows 메모리의 little-endian 샘플과 PNG의 network byte order를 명시적으로 처리해야 합니다.

### 10.3 TIFF

WIC 기본 TIFF 디코더는 여러 정수·float 입력 포맷을 읽을 수 있지만, Microsoft의 native pixel format 표에서 TIFF 인코더는 정수 8/16-bit 포맷을 제공합니다. 따라서 기존 문서의 “float TIFF 쓰기 지원 불명”을 다음처럼 확정합니다.

- WIC TIFF **디코드**: float 포맷을 포함한 지원 표가 있음
- WIC TIFF **인코드**: 기본 코덱의 공식 표에 float 인코더 포맷이 없음
- Negaflow 출력: 현재 제품 계약은 8/16-bit 정수 TIFF이지만, 압축·태그·행 스트리밍을 통제하기 위해 libtiff 사용
- WIC TIFF 읽기: 빠른 표준 경로
- libtiff 읽기: WIC가 거부하거나 정밀도·태그 계약을 만족하지 못하는 corpus의 fallback

WIC TIFF 인코더가 제공하는 `TiffCompressionMethod`와 `CompressionQuality`만으로 현재 macOS 계약 전체를 재현한다고 보지 않습니다.

### 10.4 BMP

BMP는 가져오기 호환용입니다.

- 8-bit/정수 이미지로 취급
- ICC가 있으면 추출하고, 없으면 표준 이미지 역할
- 내보내기 포맷에는 노출하지 않음
- indexed palette를 실제 RGB(A) 픽셀로 전개
- bottom-up 행 방향을 top-down으로 정규화

### 10.5 HEIC/HEIF

HEIF는 Windows 기본 설치만으로 항상 열린다고 보장할 수 없습니다. Microsoft HEIF Image Extension과 HEVC/AV1 구성 요소의 설치 여부가 PC마다 다를 수 있습니다.

초기 정책:

1. 파일 선택기에는 현재 macOS parity를 위해 확장자를 표시합니다.
2. 실행 시 `CLSID_WICHeifDecoder` 생성과 실제 대표 corpus 디코드를 기능 탐색합니다.
3. 코덱이 없으면 “파일 손상”이 아니라 “HEIF codec unavailable”로 안내합니다.
4. Microsoft Store로 자동 이동하거나 설치를 강제하지 않습니다.
5. HEIF 내보내기는 현재 제품 포맷이 아니므로 구현하지 않습니다.
6. depth/gain map을 일반 RGB 프레임으로 잘못 선택하지 않습니다.

Microsoft 문서의 HEIF encoder/AVIF 관련 부분에는 prerelease 표시가 있으므로, 해당 기능은 baseline 계약으로 삼지 않습니다.

## 11. ICC와 색 해석

### 11.1 WIC color context는 입력 자료

`IWICColorContext`는 프로파일을 메모리·파일·EXIF color space로 표현할 수 있습니다. Negaflow는 여기서 얻은 값을 다음처럼 사용합니다.

1. color context 개수를 확인
2. 우선순위가 있는 embedded ICC인지 확인
3. 프로파일 바이트 길이를 제한
4. 불변 바이트 배열로 복사
5. LittleCMS 검증 컨텍스트에서 열기
6. 정상 프로파일이면 working space 변환에 사용
7. 손상 프로파일이면 사용자에게 명시적 오류 또는 정책상 fallback을 기록

WIC가 “색 관리 가능”하다는 설명을 `IWICColorTransform`을 반드시 써야 한다는 뜻으로 해석하지 않습니다. CPU 기준 결과는 LittleCMS로 통일합니다.

### 11.2 untagged TIFF 역할

비트 심도만으로 transfer function을 확정할 수 없습니다. 현재 제품의 의미를 그대로 옮깁니다.

```text
UntaggedTIFFRole.standardImage
UntaggedTIFFRole.linearScannerRaw
```

- 스캐너 플러그인과 스캔 워크플로: `linearScannerRaw`
- 일반 파일 가져오기 기본: 현재 macOS parity를 위해 `linearScannerRaw`이지만 provenance에 기록
- IT8 차트 등 일반 이미지로 알아야 하는 호출: `standardImage` 명시
- 8-bit untagged TIFF: 일반 감마 이미지
- untagged PNG: 비트 심도와 무관하게 TIFF 규칙을 적용하지 않음

향후 일반 가져오기 기본값을 바꾸려면 사용자 데이터 의미가 달라지므로 migration과 UI 설명이 필요합니다.

### 11.3 여러 color context

프레임·컨테이너 수준에 여러 프로파일이 존재할 수 있습니다. 자동으로 첫 항목만 선택하지 않습니다.

- 프레임 수준 프로파일 우선
- 컨테이너 수준은 프레임에 없을 때만 후보
- EXIF sRGB 표시는 실제 ICC보다 낮은 우선순위
- 서로 충돌하면 provenance와 진단 로그에 남김
- CMYK 입력은 CMYK 프로파일 없이는 정확한 RGB 변환을 주장하지 않음

## 12. 방향 처리

EXIF orientation 1…8은 한 번만 적용합니다.

### 일반 가져오기

1. 원본 방향 태그 읽기
2. 프리뷰와 풀해상도에 같은 transform 적용
3. 픽셀 좌표가 정립된 결과를 엔진으로 전달
4. 내보내기 orientation을 1로 기록

### 스캐너 입력

1. EXIF orientation을 자동으로 굽지 않음
2. 플러그인 capability·세션·사용자 비파괴 회전을 별도 보관
3. 최종 렌더 시 해당 transform을 한 번 적용

WIC의 `IWICBitmapFlipRotator` 사용 여부는 구현 세부입니다. 중요한 계약은 프리뷰·풀해상도·ROI·결함 recipe의 좌표계가 일치하는 것입니다.

## 13. 썸네일과 프리뷰

조회 순서:

1. 컨테이너 thumbnail
2. 컨테이너 preview
3. 프레임 thumbnail
4. 축소 디코드가 검증된 코덱 경로
5. 풀 디코드 후 고품질 축소

단, 임베디드 썸네일은 원본과 다음 항목이 다를 수 있습니다.

- orientation이 이미 적용됐는지
- ICC가 포함됐는지
- 카메라가 자체 tone curve를 적용했는지
- crop과 active area
- 색공간과 bit depth

따라서 썸네일은 라이브러리 탐색 가속용입니다. 현상 결과·export·색 측정의 근거로 사용하지 않습니다.

프리뷰 parity 테스트는 같은 입력에 대해 다음을 비교합니다.

- 정립 후 aspect ratio
- 주요 패치의 ΔE 또는 linear RGB 오차
- embedded ICC 사용 여부
- untagged TIFF 역할
- 프리뷰와 풀해상도의 crop/좌표 대응

## 14. 메타데이터

### 14.1 읽기

WIC는 컨테이너와 프레임 수준의 metadata reader를 제공합니다. 도메인에는 WIC query path를 직접 저장하지 않고 현재 구조와 동등한 안전한 값 모델로 변환합니다.

```text
ExportSourceMetadata
  - tiff: bounded key/value
  - exif: bounded key/value
  - iptc: bounded key/value
  - gps: bounded key/value
```

지원 값:

- 제한된 UTF-8 문자열
- finite number
- 범위 확인된 integer
- boolean
- 제한된 문자열/숫자 배열

알 수 없는 COM variant, blob, 중첩 그래프를 그대로 카탈로그에 직렬화하지 않습니다.

### 14.2 쓰기

현재 정책은 `all`, `removeLocation`, `copyrightOnly`, `minimal` 네 가지입니다. Windows에서는 원본 metadata block을 복사한 뒤 빼는 방식보다 정책별 allowlist를 새로 쓰는 방식을 사용합니다.

- `all`: 지원·검증된 키만 복원하며 “모든 사설 MakerNote 보존”을 약속하지 않음
- `removeLocation`: GPS 블록과 IPTC 위치 키를 기록하지 않음
- `copyrightOnly`: 작가·저작권·credit·source·rights 키만 기록
- `minimal`: 원본 메타데이터를 기록하지 않음

제품이 생성하는 scanner make/model, DPI, 원본/메타데이터 날짜, software, film 정보는 현재 정책과 같은 조건으로 주입합니다. source date가 없으면 촬영일을 발명하지 않습니다.

### 14.3 readback 검증

인코드 성공 뒤 임시 파일을 다시 열어 다음을 확인합니다.

- GPS 부재
- location IPTC 부재
- orientation = 1
- ICC 존재와 지문
- DPI 값과 단위
- scanner make/model exact string
- 날짜가 UTC offset 계약을 만족
- 예상하지 않은 source metadata가 되살아나지 않음

privacy 테스트는 “필요한 태그가 있다”보다 “금지된 태그가 없다”를 중심으로 작성합니다.

## 15. 오류 모델

WIC의 `HRESULT`를 UI에 그대로 노출하지 않습니다. 원본 코드는 진단 정보에 보존하고 제품 오류로 정규화합니다.

| 제품 오류 | 의미 |
|---|---|
| `unsupportedContainer` | WIC가 열어도 제품 allowlist 밖 |
| `unsupportedCodec` | 허용되지 않은 제3자 코덱 선택 |
| `codecUnavailable` | HEIF 등 선택적 코덱 없음 |
| `corruptImage` | 컨테이너·프레임·픽셀 데이터 손상 |
| `invalidDimensions` | 0, 상한 초과, 곱셈 overflow |
| `memoryBudgetExceeded` | 완전 디코드 또는 변환 예산 초과 |
| `invalidColorProfile` | ICC가 손상되거나 정책 위반 |
| `unsupportedPixelFormat` | 정밀도 보존 가능한 변환 없음 |
| `encoderCoercedPixelFormat` | 요청과 협상 포맷 불일치 |
| `metadataWriteFailed` | 필수 metadata/ICC 기록 실패 |
| `cancelled` | 사용자 취소·세션 교체 |

`WINCODEC_ERR_*`와 `HRESULT_FROM_WIN32` 원인은 로그에 남기되 경로와 개인정보는 기본 로그에서 축약합니다.

## 16. 취소와 자원 회수

모든 WIC 코덱이 픽셀 복사 중간 취소를 동일하게 제공하지는 않습니다. 그래서 취소 계약을 작업 경계에 둡니다.

- 디코드 시작 전 취소 확인
- 메타데이터·썸네일·풀 픽셀 단계 사이 확인
- 행/타일 복사가 가능한 경로는 청크 사이 확인
- 완료 직전 frame/revision/session identity 재확인
- 취소된 결과는 캐시·카탈로그·UI에 게시하지 않음
- COM 포인터·스트림·임시 버퍼를 즉시 해제

취소가 즉시 preempt되지 않는 코덱은 최대 입력 크기와 동시 작업 수로 지연 상한을 관리합니다. 강제 스레드 종료는 사용하지 않습니다.

## 17. 관측성

`DecodeProvenance`에 최소 다음을 기록합니다.

```text
decoderFamily: wic | libtiff | libraw
decoderVersion: OS build 또는 library version
codecClsid
containerGuid
nativePixelFormatGuid
normalizedPixelFormat
sourceWidth / sourceHeight
frameIndex
orientationOriginal / orientationApplied
colorProfileDigest
untaggedTiffRole
thumbnailSource
extensionContainerMismatch
```

파일명·전체 경로·EXIF 개인정보는 telemetry 기본값에서 제외합니다. 로컬 진단 bundle에 포함할 때도 사용자의 명시적 동의를 받습니다.

## 18. 테스트 매트릭스

### 18.1 정상 corpus

- JPEG: grayscale/RGB/CMYK, EXIF orientation 1…8, ICC 유무
- PNG: 8/16-bit RGB/RGBA/gray, ICC/sRGB/gAMA 조합
- TIFF: 8/16-bit RGB/RGBA/gray, LZW/Deflate/none, strips/tiles, endian 양쪽
- TIFF: embedded ICC와 untagged scanner raw
- BMP: indexed/24-bit/32-bit, top-down/bottom-up
- HEIF: 확장 설치/미설치, HEVC/AV1 가능 여부, 대표 이미지

### 18.2 악성·손상 corpus

- 0 또는 비정상 차원
- 폭×높이 overflow
- 너무 큰 stride·프레임 수·IFD 수
- 잘린 스트립·타일·JPEG stream
- 순환 또는 깊은 metadata 구조
- 수백 MB ICC/XMP 주장
- NaN/Infinity metadata
- 확장자와 시그니처 불일치
- 등록된 제3자 코덱이 같은 포맷을 가로채는 환경

### 18.3 parity

- macOS와 Windows 작업 공간 float 샘플 비교
- 프리뷰/풀해상도 색 해석 비교
- orientation 및 crop 좌표 비교
- 16-bit ramp의 단조성과 endpoint 보존
- embedded profile transform의 ΔE 허용치
- 같은 export 설정의 크기·메타데이터·프로파일 계약 비교

### 18.4 아키텍처

- COM 객체가 작업 스레드 경계를 넘지 않음
- 취소 결과가 UI에 게시되지 않음
- `SetPixelFormat` coercion 시 실패
- 제3자 codec CLSID 기본 거부
- raw 확장자를 표준 WIC TIFF로 잘못 열지 않음
- source 파일을 write access로 열지 않음

## 19. 단계별 도입

### Phase 0 — corpus spike

- WIC native codec CLSID 식별
- JPEG/PNG/TIFF/BMP 디코드
- 16-bit PNG/TIFF 정밀도 검증
- HEIF 설치 상태별 오류 확인
- metadata query mapping 작성

완료 조건: 같은 corpus가 x64와 ARM64에서 동일 계약으로 열리고 실패 유형이 분류됩니다.

### Phase 1 — 표준 입력

- `WicStandardDecoder`
- allowlist와 크기 제한
- orientation·ICC·metadata 추출
- 완전 디코드 소유 버퍼
- preview/full interpretation parity

완료 조건: 현재 `ImportedImageLoadTests`에 대응하는 Windows 테스트가 통과합니다.

### Phase 2 — 내보내기

- JPEG 8-bit
- PNG 8/16-bit
- 픽셀 포맷 협상 검증
- ICC/metadata readback
- atomic publish 연결

완료 조건: 현재 `ExportEngineTests`와 `ExportMetadataPolicyTests` 계약을 재현합니다.

### Phase 3 — 방어 강화

- fuzz corpus
- 메모리/시간 예산
- codec hijack 환경 테스트
- 장시간 batch와 취소

완료 조건: 손상 입력이 프로세스 크래시·원본 변경·무한 할당을 만들지 않습니다.

## 20. 결정 사항과 열린 질문

### 확정

- WIC는 표준 컨테이너 어댑터입니다.
- LittleCMS가 색 변환 기준입니다.
- TIFF 쓰기는 libtiff가 기준입니다.
- RAW는 LibRaw가 기준입니다.
- 제3자 WIC 코덱 자동 신뢰는 금지합니다.
- 인코더 픽셀 포맷 coercion은 검출하고 실패합니다.
- HEIF는 설치 상태를 기능 탐색하는 조건부 입력입니다.

### 실측 후 확정

- 표준 TIFF 읽기에서 WIC와 libtiff의 최종 우선순위
- JPEG 0…1 품질 슬라이더의 WIC mapping
- high-quality 구간의 4:4:4 경계
- PNG 16-bit WIC 출력의 전 corpus 안정성
- HEIF 대표 프레임·orientation·ICC 규칙
- multi-page TIFF 사용자 경험
- 완전 디코드 임계값과 타일 전환점

## 21. 구현 전 체크리스트

- [ ] Microsoft native codec CLSID allowlist 정의
- [ ] WIC factory·COM apartment 소유권 정의
- [ ] checked dimension/stride/buffer 계산 유틸리티 정의
- [ ] source classification과 raw 우선 판정 정의
- [ ] `SourceInterpretation`과 `DecodeProvenance` 스키마 확정
- [ ] ICC 바이트 크기 제한과 LittleCMS 검증 연결
- [ ] orientation 일반/스캐너 경로 분리
- [ ] metadata allowlist와 privacy negative test 작성
- [ ] `SetPixelFormat` 반환 GUID 검증
- [ ] JPEG subsampling 출력 재검증
- [ ] PNG 16-bit ramp round-trip 테스트
- [ ] HEIF codec unavailable UX 정의
- [ ] WIC 실패→libtiff fallback 조건을 명시적으로 제한
- [ ] 소스 파일 read-only와 원자적 출력 게시 보장

## 공식 출처

- [Windows Imaging Component Overview](https://learn.microsoft.com/en-us/windows/win32/wic/-wic-about-windows-imaging-codec)
- [How the Windows Imaging Component works](https://learn.microsoft.com/en-us/windows/win32/wic/-wic-howwicworks)
- [WIC codecs from Microsoft](https://learn.microsoft.com/en-us/windows/win32/wic/native-wic-codecs)
- [Native pixel formats overview](https://learn.microsoft.com/en-us/windows/win32/wic/-wic-codec-native-pixel-formats)
- [`IWICBitmapDecoder`](https://learn.microsoft.com/en-us/windows/win32/api/wincodec/nn-wincodec-iwicbitmapdecoder)
- [`CreateDecoderFromFilename`](https://learn.microsoft.com/en-us/windows/win32/api/wincodec/nf-wincodec-iwicimagingfactory-createdecoderfromfilename)
- [Encoding overview](https://learn.microsoft.com/en-us/windows/win32/wic/-wic-creating-encoder)
- [JPEG format overview](https://learn.microsoft.com/en-us/windows/win32/wic/jpeg-format-overview)
- [`WICJpegYCrCbSubsamplingOption`](https://learn.microsoft.com/en-us/windows/win32/api/wincodec/ne-wincodec-wicjpegycrcbsubsamplingoption)
- [PNG format overview](https://learn.microsoft.com/en-us/windows/win32/wic/png-format-overview)
- [TIFF format overview](https://learn.microsoft.com/en-us/windows/win32/wic/tiff-format-overview)
- [WIC Metadata Overview](https://learn.microsoft.com/en-us/windows/win32/wic/-wic-about-metadata)
- [Reading and writing metadata](https://learn.microsoft.com/en-us/windows/win32/wic/-wic-codec-readingwritingmetadata)
- [`IWICColorContext`](https://learn.microsoft.com/en-us/windows/win32/api/wincodec/nn-wincodec-iwiccolorcontext)
- [HEIF extension codec](https://learn.microsoft.com/en-us/windows/win32/wic/heif-codec)
- [WIC GUIDs and CLSIDs](https://learn.microsoft.com/en-us/windows/win32/wic/-wic-guids-clsids)
- [Multi-threaded apartment support in WIC](https://learn.microsoft.com/en-us/windows/win32/wic/what-s-new-in-wic-for-windows-8-1)

## 관련 문서

- [libtiff.md](libtiff.md)
- [libraw.md](libraw.md)
- [export-formats.md](export-formats.md)
- [../04-color-management/color-pipeline.md](../04-color-management/color-pipeline.md)
- [../04-color-management/lcms2.md](../04-color-management/lcms2.md)
- [../06-large-images/image-source-tiling.md](../06-large-images/image-source-tiling.md)
- [../07-threading/multithreading-export.md](../07-threading/multithreading-export.md)
