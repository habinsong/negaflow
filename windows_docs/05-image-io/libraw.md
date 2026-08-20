# LibRaw 설계 — Windows 카메라 RAW 가져오기

조사 기준일: 2026-08-04  
upstream 최신 안정판: LibRaw 0.22.2  
대상: Windows x64와 ARM64, 네이티브 C++ 엔진

## 결론

카메라 RAW는 “후속 기능”이 아닙니다. 현재 macOS Negaflow가 이미 DNG와 주요 제조사 RAW를 `CIRAWFilter`로 가져오므로, 99.9% 기능·UI/UX parity를 목표로 하는 Windows판에도 RAW 가져오기 경로가 필요합니다.

Windows 기준 후보는 LibRaw입니다.

- WIC Raw Image Extension 설치 상태에 제품 핵심 동작을 맡기지 않습니다.
- 파일 확장자만 보고 일반 TIFF/JPEG로 fallback하지 않습니다.
- RAW 식별·unpack·기본 현상은 CPU에서 시작합니다.
- x64 Intel/AMD와 ARM64에서 같은 parameter profile을 사용합니다.
- CUDA 전용 RAW 경로는 만들지 않습니다.
- decoder version과 모든 결과 영향 parameter를 provenance에 남깁니다.

다만 **LibRaw를 채택하면 자동으로 macOS와 같은 픽셀이 나오는 것은 아닙니다.** Apple `CIRAWFilter`와 LibRaw는 카메라 지원, 디모자이크, 화이트밸런스, 색 행렬, 하이라이트, orientation, preview scaling이 다릅니다. 기능 parity는 만들 수 있지만 픽셀 parity는 실제 RAW corpus로 측정·조정해야 합니다.

또한 upstream은 dcraw 호환 post-processing을 production-quality renderer의 장기 기준으로 보지 않으며, API 문서도 `dcraw_process()`를 demonstration/testing 성격으로 설명합니다. 따라서 LibRaw의 **파서·unpacker 품질**과 **현상 결과 품질**을 분리해 평가해야 합니다. 이 경고를 해소하지 못하면 RAW를 “지원 완료”로 표시하지 않습니다.

## 1. 현재 macOS 동작

관련 코드:

- `Sources/Chromabase/Imaging/ImageLoader/ImageLoader.swift`
- `Sources/Chromabase/Imaging/ImageLoader/ImageLoader+RAW.swift`
- `Tests/ChromabaseTests/ImportedImageLoadTests.swift`
- `Tests/ChromabaseTests/ExportProvenanceTests.swift`

현재 계약:

1. 알려진 RAW 확장자와 ImageIO UTI로 RAW를 분류합니다.
2. RAW/DNG는 `CIRAWFilter(imageURL:)`로 디모자이크합니다.
3. Apple 기본 global tone curve를 끄기 위해 `boostAmount = 0.0`을 명시합니다.
4. preview는 `scaleFactor` 0 초과 1 이하를 사용합니다.
5. 디코더 버전, boost, scale을 `DecodeProvenance`에 기록합니다.
6. RAW 디코드 실패를 PNG/JPEG/TIFF fallback으로 위장하지 않습니다.
7. 일반 RAW 로드에서는 Apple RAW pipeline이 적용한 orientation을 다시 적용하지 않습니다.
8. 결과는 develop 전 linear-domain 입력으로 취급합니다.

현재 알려진 확장자:

```text
dng, crw, cr2, cr3, nef, nrw, arw, srf, sr2, raf,
rw2, raw, orf, pef, srw, 3fr, fff, mef, mos, erf,
kdc, dcr, k25, rwl, iiq, x3f
```

Windows 구현은 이 목록을 파일 선택 힌트로 유지하되, 실제 support는 `LibRaw::open_file()`과 decoder identification으로 확인합니다.

## 2. 버전과 공급망

### 2.1 2026-08-04 상태

- upstream 안정판: 0.22.2
- upstream 0.22.2 Windows binary: MSVC 2022, Win64 제공
- 현재 vcpkg `libraw` 포트: 0.22.1
- vcpkg CMake targets: `libraw::raw`, `libraw::raw_r`
- vcpkg 지원 표현: UWP/Xbox 제외

0.22.2는 bugfix release이며 float DNG tile index 검사, integer overflow 방어, read buffer 초기화 등 입력 안전성과 관련된 수정도 포함합니다. 따라서 0.22.1을 단순히 “충분히 최신”으로 간주하지 않습니다.

### 2.2 권장 pin

릴리스 후보는 0.22.2 이상으로 고정합니다.

vcpkg 포트가 아직 0.22.1이면 선택지는 다음과 같습니다.

1. vcpkg upstream이 0.22.2로 갱신될 때까지 기다림
2. 공식 0.22.2 source와 hash를 사용하는 최소 overlay port 유지
3. upstream CMake를 별도 ExternalProject로 관리

권장은 2번입니다. 다만 overlay는 다음을 갖춰야 합니다.

- upstream release URL과 SHA-512
- build option 전체 명시
- x64/ARM64 CI
- 실제 license 파일 설치
- patch가 있다면 최소 범위와 provenance
- port update 제거 조건

upstream 제공 prebuilt DLL을 그대로 가져오는 것보다 같은 toolchain과 CRT 정책으로 source build하는 편이 재현성·ARM64 지원에 유리합니다.

### 2.3 기능 선택

현재 vcpkg port에는 다음 feature가 있습니다.

- `dng-lossy`: lossy DNG codec support, `libjpeg-turbo` 추가
- `openmp`: OpenMP build

초기 권장:

- `openmp` 비활성화
- `dng-lossy`는 실제 corpus와 제품 지원 범위가 요구할 때만 활성화
- thread-safe target `libraw::raw_r` 사용
- app-owned bounded thread pool로 파일 단위 병렬성 관리

OpenMP를 켠 채 외부 export/import 풀에서도 여러 파일을 병렬 처리하면 oversubscription과 ARM64 편차가 생길 수 있습니다. 내부 병렬화는 벤치 후 별도 결정합니다.

## 3. 라이선스 — 이전 문서 정정

LibRaw는 다음 중 하나를 선택할 수 있는 dual license입니다.

- LGPL-2.1-only
- CDDL-1.0

이전 문서의 “CDDL을 고르면 변경 공개 의무가 없고 그냥 정적 링크하면 된다”는 설명은 정확하지 않습니다. CDDL은 covered file 단위 의무가 있으며, executable 형태로 배포할 때 해당 covered software의 source 제공·안내 의무를 검토해야 합니다. LibRaw 수정 파일은 CDDL 조건을 따라야 합니다.

LGPL도 “DLL로 만들면 끝”이 아닙니다. license/notice, corresponding source 또는 적절한 제공 방식, 사용자가 library를 교체·수정해 사용할 권리, 수정분 공개 등 실제 배포 형태에 따른 의무를 검토해야 합니다.

### 3.1 권장 기술 경계

법률 판단을 코드 구조가 대신할 수는 없지만, 다음 구조가 두 선택지 모두를 관리하기 쉽습니다.

```text
Negaflow Engine (Apache-2.0)
        │ narrow adapter ABI
        ▼
Negaflow.Raw.LibRaw.dll
        │
        ▼
LibRaw + pinned transitive dependencies
```

- LibRaw와 adapter의 파일 경계를 명확히 함
- upstream source·patch·build recipe를 별도 third-party source bundle로 재현
- DLL 버전과 decoder provenance를 기록
- 앱 코드와 LibRaw 수정 파일을 섞지 않음

이 경계가 out-of-process plugin이어야 한다는 뜻은 아닙니다. scanner GPL plugin과 달리 LibRaw는 dual license이고, 프로세스 분리는 별도의 보안·성능 판단입니다.

### 3.2 릴리스 전 법무 결정

반드시 결정할 항목:

- 선택 license: LGPL-2.1-only 또는 CDDL-1.0
- 정적/동적 링크
- source 제공 위치와 기간
- adapter 및 LibRaw patch의 license
- Third-Party Notices 문구
- transitive dependencies: Jasper, LittleCMS, zlib, 선택적 libjpeg-turbo 등
- MSIX와 unpackaged installer 양쪽의 source/notice 접근 방식
- 업데이트 후 license 변경 여부

문서의 권장은 법률 자문이 아닙니다. release gate에서 실제 배포 artifact와 선택 license 원문을 법무 검토합니다.

## 4. 역할 경계

### 4.1 LibRaw가 담당

1. RAW 컨테이너 식별
2. 카메라·센서 metadata 파싱
3. raw data unpack
4. embedded preview/thumbnail 추출
5. baseline 디모자이크와 camera color 처리를 위한 후보 구현
6. 진행·취소 callback
7. decoder 이름·버전·camera support 정보 제공

### 4.2 LibRaw가 담당하지 않음

1. Negaflow working space의 최종 정의
2. 필름 반전·현상 파라미터
3. 일반 export ICC 정책
4. 라이브러리 카탈로그·원본 파일 수명
5. 자동으로 Apple RAW와 픽셀 동일성 보장
6. 모든 카메라의 “정확한 색” 보증
7. UI capability를 추측으로 노출

### 4.3 제품 위치

```text
RAW file
  │
  ├── identity + metadata + embedded preview
  │
  └── unpack + raw processing
          │
          ▼
linear RGB candidate + provenance
          │
          ▼
working-space normalization
          │
          ▼
normal Negaflow develop pipeline
```

RAW 전용 화이트밸런스·노출 UI를 Windows판에 새로 추가하지 않습니다. 현재 macOS UI가 노출하지 않는 기능을 parity 작업 중 슬쩍 늘리지 않습니다. controlled API가 현재 macOS에 있더라도 실제 사용자 표면과 persisted model을 확인한 뒤 옮깁니다.

## 5. API와 객체 소유권

### 5.1 target

```cmake
find_package(libraw CONFIG REQUIRED)
target_link_libraries(negaflow_raw_adapter PRIVATE libraw::raw_r)
```

현재 vcpkg usage가 `raw_r`을 thread-safe target으로 안내합니다. 실제 Windows build의 target linkage와 defines는 binary inspection과 CI에서 확인합니다.

### 5.2 인스턴스 규칙

- RAW job 하나당 `LibRaw` 인스턴스 하나
- 인스턴스를 만든 스레드에서 사용
- 다른 스레드로 넘기면 외부 synchronization 필요하므로 기본 금지
- 파일 간 병렬성은 인스턴스를 각각 만들어 확보
- job 종료 시 `recycle()` 또는 destructor로 정리
- `dcraw_make_mem_image()` 결과는 반드시 `dcraw_clear_mem()`으로 해제

upstream 문서는 thread-safe build에서 각 스레드가 자신의 `LibRaw` 객체를 쓰는 방식을 보장합니다. 같은 객체에 여러 스레드가 동시에 접근하지 않습니다.

### 5.3 Windows 경로

Win32용 `open_file(const wchar_t*)` overload를 사용하여 Unicode 경로를 보존합니다. UTF-16 경로를 ANSI code page로 내리지 않습니다.

파일은 read-only로 열고 원본을 변경하지 않습니다. source URL/identity는 카탈로그의 불변 원본 계약을 따릅니다.

## 6. RAW 분류

### 6.1 확장자는 힌트

확장자가 RAW 목록에 있으면 LibRaw로 먼저 식별합니다. 하지만 확장자만으로 성공 처리하지 않습니다.

```text
extension says RAW
    │
    ├── LibRaw open succeeds → RAW path
    └── LibRaw open fails    → corrupt/unsupported RAW
                              표준 이미지 fallback 금지
```

이 규칙은 현재 `ImportedImageLoadTests`의 fake RAW 거부 계약과 같습니다.

### 6.2 확장자 없음·오분류

- 일반 WIC 분류 전에 파일 header와 LibRaw 식별을 제한적으로 시도할 수 있음
- TIFF/DNG 계열은 WIC가 일반 TIFF로 열 수 있어도 RAW 의미를 먼저 확인
- 파일이 RAW인지 모호하면 사용자가 지정한 import role과 provenance에 남김
- 지원하지 않는 새 카메라는 “손상”과 구분하여 `unsupportedRaw`로 안내

LibRaw의 지원 카메라 목록은 버전별 snapshot입니다. 마케팅 문구로 “모든 RAW 지원”을 사용하지 않습니다.

## 7. 기준 디코드 프로파일

### 7.1 중요한 원칙

Apple `boostAmount = 0`을 LibRaw 필드 하나에 이름만 보고 대응시키면 안 됩니다. 최소 다음 동작이 결과에 영향을 줍니다.

- automatic brightness
- transfer curve
- white balance
- camera matrix/profile
- black/white level scaling
- highlight mode
- demosaic algorithm
- exposure correction
- noise reduction
- orientation
- crop/active area

Windows는 이 전체를 versioned `RawDecodeProfile`로 고정합니다.

```text
RawDecodeProfile
  profileVersion
  outputBits
  outputColorSpace
  transferCurve
  autoBrightness
  whiteBalanceSource
  cameraMatrixPolicy
  highlightMode
  demosaicQuality
  exposureCorrection
  noiseReduction
  orientationPolicy
  previewPolicy
```

사용자 파일의 재현성을 위해 profile version은 sidecar/export provenance에 기록합니다.

### 7.2 최초 spike 시작값

다음은 최종값이 아니라 macOS의 “global tone curve를 끈 linear source”에 접근하기 위한 시작점입니다.

| LibRaw parameter | 시작값 | 이유 |
|---|---:|---|
| `output_bps` | 16 | 8-bit 조기 양자화 방지 |
| `no_auto_bright` | 1 | histogram 기반 자동 밝기 증가 차단 |
| `bright` | 1.0 | 추가 밝기 배수 없음 |
| `gamm[0]`, `gamm[1]` | 1.0, 1.0 | linear transfer 시작점 |
| `exp_correc` | 0 | 자동 노출 이동 없음 |
| `half_size` | 0 | full-resolution 기준 |
| `user_flip` | -1 후보 | 파일 orientation 사용, 중복 적용 검증 |
| `use_camera_wb` | corpus로 결정 | Apple default와 비교 필요 |
| `use_camera_matrix` | corpus로 결정 | DNG/제조사별 색 차이 검증 필요 |
| `output_color` | linear sRGB 후보 | 실제 matrix/ICC 경계 검증 필요 |
| `highlight` | corpus로 결정 | clip/rebuild 결과가 크게 다름 |
| `user_qual` | corpus로 결정 | Bayer/X-Trans 품질·속도 균형 |

`no_auto_bright=1`만으로 Apple `boostAmount=0`과 같다고 부르지 않습니다. `adjust_maximum_thr`, white balance fallback, highlight 처리까지 포함한 실제 출력 비교가 필요합니다.

### 7.3 output color

두 접근을 spike에서 비교합니다.

#### A. LibRaw가 linear sRGB RGB 생성

- camera matrix 적용
- 16-bit RGB
- linear gamma
- 엔진에서 float32 working buffer로 정규화

장점: 구현이 작고 초기 기능 parity가 빠릅니다.  
위험: LibRaw post-processing·clipping에 종속됩니다.

#### B. LibRaw는 unpack 중심, 앱이 float processing

- sensor data·black/white·matrix metadata를 추출
- app-owned demosaic/white balance/color pipeline
- extended float range 보존

장점: 장기 재현성과 headroom 통제가 좋습니다.  
위험: 카메라 RAW renderer를 사실상 새로 만드는 대형 프로젝트입니다.

초기 목표는 A이지만, highlight·색·X-Trans 품질 gate를 통과하지 못하면 B를 무리하게 즉시 구현하지 않고 대체 renderer/상용 라이선스까지 다시 평가합니다.

## 8. 디모자이크

LibRaw의 dcraw 호환 품질 선택은 단일 숫자지만 센서 종류별 결과가 다릅니다.

필수 분리:

- Bayer
- Fujifilm X-Trans
- full-color/linear DNG
- Foveon/X3F
- small RAW/YCC
- monochrome
- pixel-shift/multi-shot

하나의 `user_qual` 값을 모든 카메라에 강제로 적용하지 않습니다. 센서 유형별 support table과 fallback을 작성합니다.

품질 평가는 다음을 포함합니다.

- zipper/false color
- moiré
- fine grain 보존
- edge detail
- hot/dead pixel 영향
- highlight color
- low-light chroma noise
- 처리 시간·peak memory

필름 사진을 디지털 카메라로 재촬영하는 camera scanning 워크플로에서는 필름 grain과 고대비 edge가 많으므로 일반 풍경 RAW corpus만으로 충분하지 않습니다.

## 9. 화이트밸런스와 색

현재 Apple 경로는 명시적 WB 값을 코드에서 설정하지 않고 `CIRAWFilter` 기본 해석을 사용합니다. Windows에서 이를 추측으로 “camera WB”라고 고정하지 않습니다.

비교할 후보:

- camera-recorded WB
- daylight fallback
- LibRaw auto WB
- DNG AsShotNeutral/ColorMatrix
- embedded camera ICC/profile

규칙:

- WB source를 provenance에 기록
- camera WB가 없을 때 fallback 종류를 기록
- auto WB를 조용히 사용하지 않음
- camera profile과 output profile을 구분
- LittleCMS가 처리할 ICC와 LibRaw가 이미 적용한 matrix를 중복 적용하지 않음
- “정확한 카메라 색”은 측정·프로파일 evidence 없이 주장하지 않음

DNG의 두 illuminant matrix와 calibration 정보는 단순 embedded ICC와 다릅니다. DNG 색 처리 전체를 ICC 하나로 축약하지 않습니다.

## 10. 하이라이트와 범위

16-bit processed RGB는 저장 범위가 유한합니다. Apple Core Image RAW 결과의 extended range와 같은 headroom이 자동 보존된다고 가정하지 않습니다.

검증 항목:

- channel clipping 시작점
- sensor saturation 근처 RGB 비율
- magenta/green highlight artifact
- `highlight` mode별 색·detail
- negative orange mask처럼 channel imbalance가 큰 camera-scan RAW
- develop exposure를 낮췄을 때 복원 가능한 headroom

RAW 디코드 단계에서 잘린 highlight는 이후 float pipeline이 복구할 수 없습니다. 따라서 parity gate는 화면 결과뿐 아니라 exposure-down reconstruction을 포함합니다.

## 11. orientation과 active area

LibRaw의 raw size, visible size, output size는 다를 수 있습니다.

- `raw_width/raw_height`: sensor frame 포함
- `width/height`: visible area
- `iwidth/iheight`: rotation·pixel aspect·half-size가 반영될 수 있는 output estimate

규칙:

1. output 크기는 processing 후 값으로 확정
2. active area crop을 provenance에 기록
3. orientation을 픽셀에 적용했으면 이후 EXIF를 다시 적용하지 않음
4. preview/full crop과 orientation이 동일한 좌표계를 사용
5. Fuji rotation과 non-square pixel 동작을 별도 corpus로 검증

`adjust_sizes_info_only()`는 custom processing의 사전 크기 추정에 쓸 수 있지만 반복 호출에 대한 제약을 지킵니다.

## 12. 프리뷰

현재 macOS는 `CIRAWFilter.scaleFactor`로 임의 비율 preview를 만들 수 있습니다. LibRaw의 `half_size`는 주로 Bayer 1/2 출력이며 모든 RAW 형식의 범용 scaler가 아닙니다.

Windows preview 순서:

1. embedded preview가 충분히 크고 방향·ICC 정책이 확인되면 라이브러리 탐색용으로 사용
2. Bayer quick preview는 `half_size` 후보
3. full processed result를 engine 고품질 scaler로 목표 크기까지 축소
4. linear DNG/X-Trans 등 half-size가 적용되지 않는 형식은 명시적 fallback

embedded JPEG preview는 카메라 tone/style이 적용된 결과일 수 있으므로 develop preview의 색 기준으로 사용하지 않습니다.

provenance:

```text
previewSource: embedded | librawHalf | fullThenScale
rawScaleFactorRequested
rawScaleFactorEffective
embeddedPreviewIndex
```

프리뷰와 최종 픽셀이 다를 수 있는 동안 UI에 “최종 색”처럼 보이지 않게 해야 하지만, 99.9% parity를 위해 현재 macOS 전환 경험을 실제 화면으로 비교합니다.

## 13. 메타데이터

LibRaw는 camera/model, dimensions, exposure metadata, XMP, embedded ICC와 각종 vendor 정보를 제공합니다. 모두 카탈로그에 무제한 복사하지 않습니다.

적용 상한:

- 문자열 UTF-8 4,096 bytes
- 배열 128개 기본 상한
- ICC/XMP 별도 byte budget
- finite number만 허용
- raw pointer를 객체 수명 밖에 보관하지 않음
- MakerNote 원본 blob 자동 보존 금지

원본 metadata 정책은 일반 이미지와 같은 `all`, `removeLocation`, `copyrightOnly`, `minimal`로 정규화합니다. RAW sidecar와 export에 GPS가 새지 않는 negative test가 필요합니다.

카메라 RAW metadata와 scanner make/model metadata를 혼동하지 않습니다. camera-scanning으로 만든 파일이라도 scanner 장치로 표시하지 않습니다.

## 14. provenance

현재 macOS의 세 필드보다 확장된 RAW provenance가 필요합니다.

```text
decoderFamily: libraw
libRawVersion
libRawVersionNumber
buildArtifactDigest
vcpkgBaselineOrOverlayRevision
unpackFunctionName
cameraMake / cameraModel
rawFormat
sensorLayout
rawDimensions / visibleDimensions / outputDimensions
decodeProfileVersion
outputBits
whiteBalanceSource
cameraMatrixPolicy
highlightMode
demosaicQuality
autoBrightnessDisabled
transferCurve
orientationApplied
previewSource / effectiveScale
embeddedProfileDigest
warningFlags
```

개인 식별 가능 metadata와 전체 경로는 telemetry에 포함하지 않습니다. provenance는 결과 재현에 필요한 기술 필드 중심입니다.

LibRaw update로 결과가 달라졌을 때 기존 파일을 자동 재현상할지, 기존 decoder artifact를 유지할지는 catalog migration 문서에서 결정해야 합니다.

## 15. 메모리와 입력 제한

RAW는 compressed file 크기보다 unpacked memory가 훨씬 큽니다.

검증:

- source file size
- raw/visible/output dimensions
- channel count와 sample width
- `width × height × channels × bytes`
- LibRaw 내부 raw memory limit
- processed output buffer
- preview와 full decode 동시 상주
- 여러 import job의 총합

LibRaw의 raw memory limit parameter를 설정하더라도 앱 전체 memory budget을 대신하지 않습니다. 한 job이 허용 범위여도 여러 job을 동시에 열면 압박이 생깁니다.

권장:

- full RAW decode 동시성 1~2에서 측정 시작
- preview 작업이 full job보다 높은 우선순위라고 해서 무제한 선점하지 않음
- catalog thumbnail 생성과 interactive develop decode를 같은 큐로 기아시키지 않음
- 완성 RGB는 tiling/cache 정책으로 빠르게 이전
- memory pressure에서 새 full decode 제출 중단

## 16. 취소와 timeout

LibRaw는 progress handler와 cancel flag를 제공합니다.

규칙:

- job별 progress callback에 cancellation token 전달
- callback은 빠르고 lock-free에 가깝게 유지
- nonzero callback return을 `cancelled`로 정규화
- `setCancelFlag()` 사용 범위와 thread safety를 pinned 버전 corpus로 검증
- 취소 뒤 `recycle()`로 자원 회수
- stale frame/revision/session 결과 미게시

OpenMP build에서는 callback iteration 순서가 단조 증가하지 않을 수 있습니다. 초기에는 OpenMP를 끄지만 progress UI는 iteration 순서를 절대값으로 가정하지 않습니다.

코덱 내부 한 함수가 오래 걸리는 동안 강제로 스레드를 종료하지 않습니다. watchdog은 진단과 새 작업 억제에 사용하고 process termination을 기본 취소 수단으로 삼지 않습니다.

## 17. 오류 모델

LibRaw return convention은 system error와 library error를 구분합니다. adapter에서 제품 오류로 정규화합니다.

| 제품 오류 | 의미 |
|---|---|
| `notRaw` | 지원 RAW로 식별되지 않음 |
| `unsupportedRaw` | 형식/카메라를 현재 decoder가 지원하지 않음 |
| `corruptRaw` | 파일 구조·데이터 손상 |
| `rawIoFailed` | 파일 read/seek 오류 |
| `rawMemoryBudgetExceeded` | 내부/앱 예산 초과 |
| `rawDecodeFailed` | unpack/demosaic/postprocess 실패 |
| `rawProfileInvalid` | embedded profile/색 data 오류 |
| `rawCancelled` | 사용자 취소/stale session |
| `rawQualityGateFailed` | 알려진 지원 corpus와 결과 계약 불일치 |

표준 이미지 fallback은 없습니다. RAW decode 실패를 성공으로 위장하지 않습니다.

warning/data error callback은 파일 경로 전체를 일반 로그에 남기지 않고, module·offset·normalized code를 기록합니다.

## 18. CPU·GPU 전략

### 18.1 baseline

LibRaw decode와 baseline demosaic는 CPU에서 실행합니다.

- Intel x64
- AMD x64
- Qualcomm/기타 Windows ARM64

동일 parameter profile과 동일 support matrix를 사용합니다. CPU vendor별 별도 화질 경로를 만들지 않습니다.

### 18.2 SIMD

- upstream build가 사용하는 최적화와 컴파일러 flag를 SBOM/provenance에 기록
- `/arch` 설정이 ARM64/x64 baseline을 깨지 않게 CI 분리
- 런타임 CPU dispatch가 있다면 scalar/reference 결과와 허용 오차 검증
- fast-math로 색·NaN·clipping semantics를 바꾸지 않음

### 18.3 GPU

초기 RAW decode에 CUDA를 쓰지 않습니다.

향후 GPU demosaic를 검토한다면:

1. Direct3D 12/DirectML 또는 DirectCompute처럼 vendor-neutral API 우선
2. Intel/NVIDIA/AMD/Qualcomm hardware corpus
3. CPU reference와 pixel/visual parity
4. device loss와 CPU fallback
5. transfer overhead 포함 end-to-end 성능

NVIDIA-only CUDA path는 선택적 후속 최적화이며, RAW 지원 여부나 기본 UX를 결정하면 안 됩니다.

## 19. 보안 격리 선택지

RAW decoder는 신뢰할 수 없는 복잡한 파일을 파싱합니다. 초기 in-process adapter가 fuzz·budget gate를 통과하지 못하면 out-of-process codec host를 검토합니다.

```text
Negaflow.exe
   │ bounded request + shared read-only/mapped input contract
   ▼
Negaflow.ImageCodecHost.exe
   │ LibRaw
   ▼
owned pixel tiles + sanitized metadata
```

장점:

- decoder crash가 UI 프로세스를 직접 종료하지 않음
- job memory/time 제한을 프로세스 단위로 적용 가능
- library update 경계가 선명

비용:

- 대형 픽셀 IPC와 shared memory lifecycle
- duplicate memory 위험
- packaging/update 복잡도
- crash recovery UX

따라서 SANE처럼 license 때문에 무조건 plugin화하지 않습니다. 실제 threat model과 성능 측정으로 결정합니다.

## 20. 품질 corpus

### 20.1 최소 형식

- Adobe/Apple/Android DNG
- Canon CR2/CR3
- Nikon NEF/NRW
- Sony ARW
- Fujifilm RAF/X-Trans
- Panasonic RW2
- Olympus/OM System ORF
- Pentax PEF
- Samsung SRW
- Hasselblad 3FR/FFF
- Phase One IIQ
- Sigma X3F
- Kodak KDC/DCR/K25
- Leica RWL
- Leaf/Mamiya MOS/MEF

지원 이름을 문서에 나열하는 것만으로 완료가 아닙니다. 합법적으로 확보한 대표 corpus와 해당 LibRaw version의 실제 성공 evidence가 있어야 합니다.

### 20.2 장면

- color checker와 gray scale
- 과노출 highlight와 mixed lighting
- deep shadow
- saturated LED/neon
- skin tone
- fine text/moire
- foliage
- high ISO
- camera-scanned color negative
- camera-scanned black-and-white negative
- grain이 강한 고해상도 film capture

### 20.3 변형

- orientation 1…8 대응
- embedded preview 유무/여러 개
- embedded profile 유무
- compressed/uncompressed DNG
- lossy DNG feature on/off
- linear DNG
- floating-point DNG
- pixel-shift/multi-shot
- small RAW/YCC
- 잘린·손상·확장자 위장 파일

## 21. macOS parity 측정

같은 파일을 macOS `CIRAWFilter`와 Windows LibRaw로 처리합니다.

### 수치

- output dimensions/crop/orientation
- gray patch neutrality
- color checker ΔE
- linear ramp와 black/white point
- highlight recovery headroom
- channel clipping percentage
- per-channel histogram
- edge/texture metrics
- preview/full difference

### 시각

- false color와 moiré
- zippering
- highlight hue
- shadow chroma noise
- camera-scanned negative의 orange-mask channel balance
- grain texture

### 허용 범위

모든 카메라에서 byte equality는 현실적인 목표가 아닙니다. 대신 다음을 분리합니다.

- 기능 parity: 같은 파일을 열고 같은 워크플로 완료
- geometry parity: crop/orientation/size 동일
- colorimetric target: 측정 기준과 허용치
- perceptual target: blind review와 artifact threshold
- reproducibility: 같은 Windows decoder profile에서 deterministic

허용치는 corpus 결과를 본 뒤 확정합니다. 측정 전 숫자를 발명하지 않습니다.

## 22. 테스트

### 22.1 unit/contract

- 확장자 분류
- fake RAW의 표준 fallback 금지
- profile parameter serialization
- non-finite/범위 밖 parameter 거부
- return code 정규화
- provenance 필드 completeness
- memory calculation overflow
- metadata bounds

### 22.2 integration

- `open_file → unpack → process → memory image → clear`
- Unicode/긴 경로
- x64/ARM64 동일 corpus
- 각 센서 유형
- embedded thumbnail extraction
- cancellation callback
- parallel files with separate objects
- same object cross-thread 금지 검증
- corrupt input no crash

### 22.3 regression on update

LibRaw version을 올릴 때 전체 RAW corpus를 다시 실행합니다.

- 새 지원 파일
- 기존 지원 파일 success 유지
- pixel/geometry deltas
- warnings 변화
- memory/time 변화
- license/notice 변화
- transitive dependency 변화

“새 버전이므로 더 좋다”를 근거로 자동 승인하지 않습니다.

## 23. 성능

측정 단위:

- identify latency
- embedded preview latency
- full unpack
- demosaic/postprocess
- working-space conversion
- total first-visible/full-ready latency
- peak committed memory
- cancellation latency

장치 matrix:

- Intel x64 iGPU 시스템
- AMD x64 iGPU/dGPU 시스템
- NVIDIA dGPU 시스템
- Windows ARM64 시스템

LibRaw 단계는 GPU 유무와 독립적으로 완료되어야 합니다. CPU로 충분히 빠른 identify·metadata·thumbnail 경로를 GPU로 옮기지 않습니다.

## 24. 단계별 도입

### Phase 0 — legal/build spike

- 선택 license 후보별 obligations 표
- 0.22.2 overlay 또는 upstream port 확보
- x64/ARM64 build
- `libraw::raw_r` 확인
- third-party source bundle 재현

완료 조건: 두 architecture artifact와 source/notice provenance가 있습니다.

### Phase 1 — 기능 spike

- DNG/CR3/NEF/ARW/RAF 대표 입력
- 16-bit linear candidate output
- no-auto-bright 시작 profile
- orientation/active area
- preview/full path
- cancellation

완료 조건: crash 없이 결과·provenance가 생성되고 fallback 계약이 지켜집니다.

### Phase 2 — macOS parity

- camera corpus 양 플랫폼 실행
- WB/color/highlight/demosaic profile 조정
- camera-scanning negative 장면 평가
- support matrix 작성

완료 조건: release 대상으로 표시한 카메라군이 정의된 품질 gate를 통과합니다.

### Phase 3 — production hardening

- fuzzing
- memory/time budgets
- malformed corpus
- long batch
- decoder update gate
- 필요 시 codec host spike

완료 조건: 지원·미지원·손상·취소가 모두 안정적으로 분리됩니다.

## 25. 확정 사항과 열린 질문

### 확정

- RAW는 Windows parity 범위입니다.
- 기준 후보는 LibRaw입니다.
- 0.22.2 이상을 release 후보로 고정합니다.
- 현재 vcpkg 0.22.1은 그대로 release pin하지 않습니다.
- thread-safe target과 job별 객체를 사용합니다.
- OpenMP는 초기 비활성화입니다.
- RAW 실패의 표준 이미지 fallback은 금지합니다.
- CPU baseline이 모든 x64/ARM64 시스템에서 동작해야 합니다.
- CUDA는 기본 경로가 아닙니다.
- license는 CDDL/LGPL 중 실제 배포 구조에 맞춰 법무가 확정합니다.

### 실측 후 확정

- `RawDecodeProfile` 최종 parameter 값
- LibRaw processed path가 production quality gate를 통과하는지
- camera WB/matrix/highlight 기본값
- 센서별 demosaic 품질
- lossy DNG feature 포함 여부
- ARM64 성능과 upstream build 지원 evidence
- in-process vs codec host
- 기존 catalog의 decoder update migration
- 사용자에게 공개할 정확한 카메라 support matrix

## 26. 구현 전 체크리스트

- [ ] upstream 0.22.2 source/hash 고정
- [ ] vcpkg overlay 제거 조건 정의
- [ ] `libraw::raw_r` x64/ARM64 빌드 확인
- [ ] OpenMP 비활성 artifact 확인
- [ ] CDDL/LGPL 선택 및 source 제공 방식 법무 확인
- [ ] transitive dependency license 감사
- [ ] RAW extension/header 분류 계약
- [ ] standard-image fallback 금지
- [ ] versioned `RawDecodeProfile`
- [ ] 16-bit linear 후보와 highlight headroom 측정
- [ ] orientation/active-area parity
- [ ] preview/full parity
- [ ] memory limit와 checked calculations
- [ ] cancellation callback
- [ ] decoder provenance
- [ ] camera-scanning negative corpus
- [ ] corrupt RAW fuzz corpus
- [ ] LibRaw update regression gate

## 공식 출처

- [LibRaw home, licensing and scope](https://www.libraw.org/)
- [LibRaw 0.22.2 download and release notes](https://www.libraw.org/download)
- [LibRaw documentation](https://www.libraw.org/docs)
- [LibRaw C++ API](https://www.libraw.org/docs/API-CXX.html)
- [LibRaw data structures and processing parameters](https://www.libraw.org/docs/API-datastruct.html)
- [LibRaw API general notes and thread safety](https://www.libraw.org/node/34)
- [LibRaw GitHub repository](https://github.com/LibRaw/LibRaw)
- [LibRaw CDDL-1.0 license text](https://github.com/LibRaw/LibRaw/blob/0.22-stable/LICENSE.CDDL)
- [LibRaw LGPL-2.1 license text](https://github.com/LibRaw/LibRaw/blob/0.22-stable/LICENSE.LGPL)
- [vcpkg `libraw` manifest](https://github.com/microsoft/vcpkg/blob/master/ports/libraw/vcpkg.json)
- [vcpkg `libraw` CMake targets](https://github.com/microsoft/vcpkg/blob/master/ports/libraw/usage)

## 관련 문서

- [wic.md](wic.md)
- [export-formats.md](export-formats.md)
- [../04-color-management/color-pipeline.md](../04-color-management/color-pipeline.md)
- [../04-color-management/lcms2.md](../04-color-management/lcms2.md)
- [../06-large-images/image-source-tiling.md](../06-large-images/image-source-tiling.md)
- [../07-threading/multithreading-export.md](../07-threading/multithreading-export.md)
- [../12-performance/ci-and-testing.md](../12-performance/ci-and-testing.md)
- [../13-build-and-deps/vcpkg-cmake.md](../13-build-and-deps/vcpkg-cmake.md)
- [../99-plan/product-invariants.md](../99-plan/product-invariants.md)
