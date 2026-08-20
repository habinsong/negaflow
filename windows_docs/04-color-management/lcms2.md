# LittleCMS 2 통합 설계

상태: 1차 구현 기준선 확정  
최종 확인: 2026-08-04  
확인한 최신 upstream release: `lcms2.19.1`  
대상: Negaflow Native Windows x64·ARM64 CPU 색 관리 참조 경로

이 문서는 LittleCMS를 단순히 “ICC를 읽는 라이브러리”로 추가하는 방법이 아니다. Negaflow의
입력 색 변환, export, PRINT, soft proof, destination gamut warning에서 LittleCMS가 맡는 정확한
책임, lifetime, thread, profile 보안, 라이선스, 재현 가능한 빌드 계약을 정한다.

---

## 1. 결론

LittleCMS 2는 Windows판의 **CPU 색 관리 기준 구현이자 필수 폴백**이다.

- 입력 ICC → 내부 linear-sRGB float32
- 내부 작업 이미지 → sRGB / Display P3 / Adobe RGB export
- 내부 작업 이미지 → 검증된 RGB printer ICC
- legacy SDR monitor ICC 출력
- soft-proof와 destination gamut warning
- CLI·CI의 결정적 참조 변환
- Direct2D `QUALITY_BEST` 결과를 승인하는 oracle

기준 결정:

| 항목 | 결정 |
|---|---|
| upstream | `mm2/Little-CMS` |
| 현재 채택 후보 | `2.19.1`, exact vcpkg baseline과 source hash로 고정 |
| vcpkg port 이름 | `lcms` |
| CMake imported target | `lcms2::lcms2` |
| core library license | MIT |
| optional `fastfloat` feature | vcpkg 기준 GPL-3.0-or-later, 사용 금지 |
| optional `threaded` feature | vcpkg 기준 GPL-3.0-or-later, 사용 금지 |
| pixel 기준 | float32 `TYPE_RGB_FLT` / 명시적 alpha 계약 |
| API 스타일 | `...THR` + app-owned `cmsContext` |
| profile open | immutable bytes에서 `cmsOpenProfileFromMemTHR` |
| transform execution | `cmsDoTransformLineStride`, app thread pool로 row partition |
| raw handle 노출 | C ABI·C#에 노출 금지 |

선택적 GPL plugin을 쓰지 않아도 core transform API는 같은 handle을 여러 thread에서 재사용할 수
있다고 공식 API 문서에 명시돼 있다. 따라서 Negaflow는 base MIT library와 자체 bounded worker
pool을 사용한다.

---

## 2. 버전과 공급망

### 2.1 확인한 현재 상태

2026-08-04 기준:

- GitHub latest release는 `lcms2.19.1`이다.
- `2.19.1`은 `2.19`의 hot-fix release다.
- upstream `lcms2.h`는 `Version 2.19`, `LCMS_VERSION 2190`을 노출한다.
- 현재 vcpkg `lcms` port는 `2.19.1`, `port-version: 1`이다.
- vcpkg port는 upstream tag와 SHA-512를 고정한다.
- upstream 2.19에서 CMake build system이 추가됐지만 현재 vcpkg port는 Meson으로 빌드한다.

`LCMS_VERSION == 2190`만으로 `2.19.0`과 `2.19.1` package provenance를 구분할 수 있다고 가정하지
않는다. 다음을 모두 기록한다.

```text
vcpkg baseline commit
port version
upstream version/tag
download/source hash
triplet
linkage
compiler/toolset
build options/features
runtime cmsGetEncodedCMMversion()
```

`cmsGetEncodedCMMversion()`은 header와 linked binary의 major/minor version 혼합을 탐지하는 runtime
guard로 사용한다. 공급망 patch-level 증거는 lock/baseline과 SBOM이 담당한다.

### 2.2 업데이트 정책

최신 release가 보인다고 자동 갱신하지 않는다.

1. upstream release notes와 diff 확인
2. vcpkg port/hash/features 확인
3. license 파일과 optional feature license 재확인
4. x64·ARM64 build
5. invalid-profile fuzz/regression corpus
6. transform golden corpus
7. soft-proof/gamut mask corpus
8. export/PRINT end-to-end
9. 성능·메모리 비교
10. baseline·SBOM·third-party notices 갱신

security hot-fix도 동일한 품질 gate를 통과하되 우선순위를 높인다.

---

## 3. 라이선스 경계

### 3.1 core library

LittleCMS core repository의 `LICENSE`는 MIT다. Negaflow 본체에 static 또는 dynamic link하는 것은
MIT notice를 포함하는 배포 절차와 함께 허용 가능한 후보지만, 최종 배포 전 third-party notice와
SBOM 검토는 별도로 수행한다.

필수 배포 기록:

- component: Little CMS
- upstream URL
- exact version/tag
- exact source/package hash
- MIT license text
- copyright notice
- local patches 또는 “none”
- linkage 형태
- 포함된 optional features

### 3.2 GPL optional plugins

현재 vcpkg `lcms` port는 다음 feature를 별도로 노출한다.

| vcpkg feature | 기능 | vcpkg 선언 license | 결정 |
|---|---|---|---|
| `fastfloat` | float transform 최적화 plugin | GPL-3.0-or-later | 본체·in-process DLL에 포함 금지 |
| `threaded` | transform을 여러 CPU thread로 분배 | GPL-3.0-or-later | 본체·in-process DLL에 포함 금지 |
| `tools` | `jpgicc`, `linkicc` 등 utility | 각 dependency/utility 검토 필요 | 제품 package에 포함 금지, 개발 도구도 별도 승인 |

upstream `meson_options.txt`도 `fastfloat`와 `threaded`를 GPL 3.0이 허용되는 경우에만 쓰라고
명시한다.

따라서 manifest는 feature 이름을 생략하는 데 그치지 않고 default feature가 바뀌어도 켜지지 않게
명시적으로 검증한다. CI는 installed package metadata와 license inventory에서 두 plugin binary가
없는지 확인한다.

다음도 금지한다.

- GPL plugin source를 읽고 동일 구조를 복제한 “자체 최적화”
- plugin DLL 이름만 바꿔 제품에 포함
- 개발 build에만 켠 뒤 benchmark 결과를 MIT base 제품 성능이라고 보고
- 별도 process라는 이유만으로 법률 검토 없이 GPL plugin 배포

독립적인 SIMD 최적화가 필요하면 public ICC 사양, Negaflow 수학, clean provenance를 기반으로 별도
법률·코드 검토를 거친다.

### 3.3 scanner plugin과의 차이

SANE처럼 GPL scanner backend를 out-of-process plugin으로 격리하는 제품 전략과 LittleCMS core
MIT link는 다른 문제다. 라이선스 경계를 한 규칙으로 뭉뚱그리지 않는다.

- LittleCMS core: permissive MIT, native engine 안의 색 관리 후보
- LittleCMS GPL plugins: 사용하지 않음
- SANE: 별도 GPL scanner process/package

---

## 4. 빌드와 package pin

### 4.1 vcpkg manifest

port 이름은 `lcms2`가 아니라 `lcms`다. 문서 예시는 다음 의미를 가져야 한다.

```json
{
  "name": "lcms",
  "default-features": false
}
```

실제 version은 dependency 항목의 느슨한 minimum만으로 고정하지 않고 repository의 exact vcpkg
baseline/lock이 결정한다. 필요 시 검증된 port version override를 사용한다.

### 4.2 CMake

현재 vcpkg usage contract:

```cmake
find_package(lcms2 CONFIG REQUIRED)
target_link_libraries(Negaflow.Native PRIVATE lcms2::lcms2)
```

문서 예시의 target 이름을 추측으로 `lcms`, `LittleCMS`, `unofficial::lcms2` 등으로 바꾸지 않는다.
baseline 변경 시 installed `usage`와 config target을 다시 확인한다.

### 4.3 triplet

필수 build:

- x64 Windows
- ARM64 Windows
- Debug
- Release
- app과 일치하는 MSVC runtime

MIT core library는 `static-md` 후보가 될 수 있다. 최종 static/dynamic 선택은 전체 native dependency
정책과 MSIX servicing을 함께 결정한다.

정적 링크 장점:

- 별도 `lcms2` DLL 배치 누락 감소
- ABI mismatch 표면 축소
- native engine DLL 하나에 third-party dependency 결박

동적 링크 장점:

- library 교체와 SBOM file inventory가 명확
- crash dump에서 module version 확인이 쉬움

어느 쪽도 성능이 자동으로 더 좋다고 가정하지 않는다. 선택 후 x64/ARM64 package layout,
runtime dependency, license notice를 검증한다.

### 4.4 빌드 feature 검사

CI가 기록해야 하는 항목:

```text
lcms port version and port-version
installed files
linked library/DLL hash
fastfloat absent
threaded absent
tools absent from shipping package
LCMS_VERSION
cmsGetEncodedCMMversion()
CRT/linkage
architecture
```

ARM64 package가 만들어졌다는 사실만으로 ARM64에서 실행된 것은 아니다. 실제 ARM64 smoke와 transform
corpus가 필요하다.

---

## 5. native wrapper 구조

LittleCMS C API를 render graph 전체에 직접 퍼뜨리지 않는다.

```text
Negaflow.Native.Color
  ProfileSnapshot
  ProfileValidator
  ProfileRepository
  ColorContextPool
  TransformDescriptor
  TransformCache
  ColorTransform
  ProofTransform
  GamutMaskGenerator
  ColorErrorTranslator
```

### 5.1 역할

`ProfileSnapshot`

- immutable bytes
- SHA-256
- source/provenance
- validated header metadata
- policy version

`ProfileValidator`

- LittleCMS 호출 전 bounded structural validation
- LittleCMS open/header/intent/transform-direction probe
- product policy validation

`TransformDescriptor`

- source/destination/proof profile IDs
- pixel formats
- intent/proof intent/BPC/flags
- alpha policy
- color policy version

`ColorTransform`

- `cmsHTRANSFORM` RAII
- immutable descriptor
- profile/context lifetime ownership
- concurrent use lease

`TransformCache`

- bounded LRU
- duplicate creation suppression
- immutable key
- eviction 안전성

### 5.2 금지하는 노출

다음은 C ABI와 C#에 노출하지 않는다.

- `cmsContext`
- `cmsHPROFILE`
- `cmsHTRANSFORM`
- LittleCMS formatter bitfields
- LittleCMS error strings
- raw profile pointer

C ABI는 Negaflow-owned opaque handle과 stable enum/reason code만 노출한다.

---

## 6. context 모델

LittleCMS의 non-`THR` 함수는 global context를 사용한다. Negaflow는 global mutable state를 피하고
`...THR` API를 기본으로 한다.

### 6.1 context가 소유하는 것

공식 API 문서에 따르면 context는 다음을 분리할 수 있다.

- plugins
- logger
- context user data
- alarm codes
- adaptation state
- 기타 `THR` 설정

Negaflow의 context user data는 최소 다음을 담는다.

```text
contextIdentity
errorSink pointer
request/profile correlation token without private path
allocation/accounting state, if introduced
```

callback이 살아 있는 동안 user data가 먼저 파괴되지 않게 한다.

### 6.2 기본 topology

기준안:

- `ColorEngine` instance마다 root context 하나
- 일반 transform creation용 immutable policy context
- gamut alarm code 또는 adaptation state가 다른 proof policy마다 별도 context 또는 freeze된 duplicate
- global context 사용 금지
- context 설정은 transform 생성 전 완료하고 사용 중 변경 금지

`cmsDupContext`는 plugin/logger 설정을 복제할 수 있지만 user data lifetime과 alarm/adaptation state가
정확히 어떻게 복제되는지 테스트한다. 단순 편의 때문에 매 tile마다 context를 만들지 않는다.

### 6.3 destruction order

보수적 수명 순서:

```text
모든 transform 실행 lease 종료
  → cmsDeleteTransform
  → cmsCloseProfile
  → cmsDeleteContext
  → context user data 파괴
```

공식 문서는 `cmsDeleteTransform`이 profile을 대신 free하지 않는다고 명시한다. profile을 transform
생성 직후 닫을 수 있는 버전별 최적화에 의존하지 않고 wrapper가 명시적으로 lifetime을 묶는다.

---

## 7. profile snapshot과 open

### 7.1 path 대신 memory

렌더 경로는 `cmsOpenProfileFromFileTHR`보다 다음을 사용한다.

```text
read file once under app IO policy
  → immutable byte snapshot
  → SHA-256
  → structural validation
  → cmsOpenProfileFromMemTHR(context, bytes, size)
```

이유:

- 선택 뒤 파일 교체 방지
- removable/network path 소실과 transform 분리
- batch checkpoint 재현성
- embedded ICC와 같은 코드 경로
- profile hash cache
- path encoding과 TOCTOU 감소

`cmsOpenProfileFromMemTHR`의 size는 32-bit unsigned다. host의 `size_t`를 무검사 cast하지 않는다.
app policy upper bound와 `UINT32_MAX`를 모두 검사한다.

### 7.2 upstream 4GB 지원의 의미

2.19는 large-file support를 추가했고 header는 ICC 32-bit offset/size 때문에 실질 최대가 4GiB보다
작다고 설명한다. 동시에 그 크기의 profile을 메모리에 넣는 것은 보통 좋지 않다고 경고한다.

Negaflow 정책:

- 4GB를 허용 상한으로 채택하지 않는다.
- 실제 display/printer profile corpus를 조사해 더 작은 product bound를 정한다.
- 상한 결정 전 “무제한 profile 지원”을 완료로 표시하지 않는다.
- profile size rejection은 원본 파일 삭제나 catalog 손상을 일으키지 않는다.

### 7.3 structural validation

LittleCMS open 전:

- byte count ≥ ICC fixed header
- declared length == snapshot length라는 현재 PRINT 정책
- `acsp` signature
- tag count multiplication overflow 없음
- tag offset + size overflow 없음
- tag range가 snapshot 내부
- product policy가 요구하는 class/color space/PCS
- duplicate/shared tag range 정책
- hash 계산 성공

LittleCMS open 후:

- `cmsGetDeviceClass`
- `cmsGetColorSpace`
- `cmsGetPCS`
- `cmsGetProfileVersion`
- `cmsIsIntentSupported` for required direction
- 필요한 `cmsCreateTransformTHR` probe

LittleCMS는 요청 intent가 profile에 없을 때 다른 intent로 fallback할 수 있다. PRINT나 parity가 exact
intent를 요구하면 `cmsIsIntentSupported`를 먼저 확인하고 implicit fallback을 허용하지 않는다.

---

## 8. built-in profile

### 8.1 sRGB

LittleCMS는 `cmsCreate_sRGBProfileTHR`를 제공한다. 그러나 Negaflow의 built-in profile identity는
호출할 때마다 생성한 bytes가 아니라 `BuiltInColorSpaceVersion`과 검증된 canonical descriptor로
관리한다.

### 8.2 linear sRGB working profile

작업공간용 profile은 `cmsCreateRGBProfileTHR`로 다음을 명시해 생성할 수 있다.

- D65 white point
- sRGB/Rec.709 primaries
- linear transfer curve 1.0

하지만 ICC PCS는 D50이며 chromatic adaptation과 profile 생성 semantics가 개입한다. 임의 matrix를
하드코딩하고 “linear sRGB ICC”라고 부르지 않는다.

필수 검증:

- canonical sRGB encode/decode patch
- D65↔D50 adaptation
- ColorSync linear-sRGB profile과 round-trip 비교
- negative/extended float behavior
- profile serialization이 필요한지 여부
- x64/ARM64 동일 descriptor hash

가능하면 검증된 canonical profile bytes를 versioned asset으로 고정해 runtime 생성 drift를 줄인다.
asset license/provenance와 hash를 기록한다.

### 8.3 Display P3와 Adobe RGB

표준 이름만으로 profile 구현을 즉석 생성하지 않는다. macOS `CGColorSpace.displayP3`와
`adobeRGB1998`의 실제 ICC snapshot 및 출력 corpus를 확보하고 Windows canonical asset을 고정한다.

profile description string이 같다고 수치 transform이 같은 것은 아니다.

---

## 9. transform 생성

### 9.1 일반 transform

기준 API:

```c
cmsCreateTransformTHR(
    context,
    sourceProfile,
    inputFormat,
    destinationProfile,
    outputFormat,
    intent,
    flags);
```

wrapper는 `NULL`을 typed failure로 변환하고 context logger가 수집한 가장 최근 structured reason을
첨부한다. 영어 upstream string을 사용자 UI의 stable message로 직접 노출하지 않는다.

### 9.2 proof transform

기준 API:

```c
cmsCreateProofingTransformTHR(
    context,
    inputProfile,
    inputFormat,
    displayOrFinalProfile,
    outputFormat,
    proofProfile,
    intent,
    proofingIntent,
    flags);
```

관련 flags:

- `cmsFLAGS_SOFTPROOFING`
- `cmsFLAGS_GAMUTCHECK`
- `cmsFLAGS_BLACKPOINTCOMPENSATION`, policy에 따라
- `cmsFLAGS_COPY_ALPHA`, 명시적 alpha copy가 필요할 때

flags를 호출부에서 임의 OR하지 않는다. versioned `TransformPolicy`가 목적별 정확한 조합을 만든다.

### 9.3 optimization flags

다음은 기본값으로 강제하지 않는다.

- `cmsFLAGS_FORCE_CLUT`
- `cmsFLAGS_HIGHRESPRECALC`
- `cmsFLAGS_LOWRESPRECALC`
- `cmsFLAGS_NOOPTIMIZE`
- `cmsFLAGS_NOCACHE`
- `cmsFLAGS_GRIDPOINTS(n)`

각 flag는 품질, transform 생성시간, 메모리, 실행시간을 바꿀 수 있다. default optimizer와 corpus를
기준으로 하고 변경은 profile class별 benchmark 및 pixel diff 뒤에만 한다.

### 9.4 DeviceLink

`cmsTransform2DeviceLink`가 있다는 이유로 export batch마다 DeviceLink를 생성하지 않는다.

문제:

- 생성 비용
- intent/BPC/profile chain별 cache 폭발
- profile sequence와 metadata 관리
- transform optimizer와 중복
- generated artifact security/provenance
- 2.19에서 관련 colorant-table bug가 수정된 이력

먼저 normal transform cache를 구현한다. DeviceLink는 PIX/ETW/CPU profile에서 transform 실행이 실제
병목이고, 대표 batch에서 생성·cache 비용을 포함해 순이득이 있을 때만 별도 spike한다.

---

## 10. pixel format과 alpha

### 10.1 float 기준

작업공간 경계의 기준 포맷:

- `TYPE_RGB_FLT` for opaque photo RGB
- `TYPE_RGBA_FLT` only when alpha must cross the transform

WIC/D3D resource channel order가 BGRA라고 formatter 이름을 추측하지 않는다. 실제 memory layout,
stride, endianness, alpha 위치를 wrapper가 검증한다.

### 10.2 alpha 기본 동작

공식 API 문서에 따르면 LittleCMS는 기본적으로 extra alpha channel을 건너뛰며 output alpha를
초기화하지 않는다. copy가 필요하면 `cmsFLAGS_COPY_ALPHA`가 필요하다.

따라서 다음을 명시한다.

- opaque 사진은 RGB-only transform을 우선
- output RGBA buffer는 alpha initialization 정책을 가짐
- alpha 보존이 필요하면 input/output formatter와 `COPY_ALPHA`를 함께 검증
- premultiplied alpha를 straight formatter로 전달하지 않음
- color transform 전에 unpremultiply가 필요한 경우 0-alpha RGB 처리 규칙 고정
- transform 뒤 presentation/composition 요구에 맞춰 premultiply

사진 canvas 내부 working image는 불필요한 alpha 변환을 피하고 명시적으로 opaque를 유지한다.

### 10.3 stride

`cmsDoTransformLineStride`는 padding이 있는 row와 planar buffer를 지원한다. wrapper는 호출 전 다음을
checked arithmetic으로 검증한다.

```text
pixelsPerLine
lineCount
bytesPerPixelIn/Out
bytesPerLineIn/Out
bytesPerPlaneIn/Out
last accessed byte offset
buffer byte length
```

`PixelsPerLine * LineCount`를 32-bit로 먼저 곱하지 않는다. 각 API parameter 범위를 확인하고 매우
큰 이미지는 row chunk로 나눈다.

---

## 11. extended float와 음수

LittleCMS float formatter를 사용한다고 모든 profile transform이 임의의 음수·1 초과 값을 원하는
방식으로 보존하는 것은 아니다. profile curve와 CLUT의 정의 범위, optimizer, intent가 영향을 준다.

규칙:

- `cmsFLAGS_NONEGATIVES`를 기본으로 켜지 않는다.
- 입력 → working transform의 negative/over-range behavior를 profile type별 테스트한다.
- export/PRINT destination encoding의 범위 밖 값은 output policy에서 처리한다.
- NaN/Inf는 transform 전에 거부하거나 명시적 finite sanitize를 수행한다.
- transform 뒤 NaN/Inf와 unexpected magnitude를 검사하는 debug/QA path를 둔다.
- LittleCMS를 현상 graph의 arbitrary extended math 대체물로 사용하지 않는다.

matrix/shaper profile과 CLUT profile은 extended input에서 다른 동작을 보일 수 있다. 해당 profile이
정의하지 않은 범위의 결과를 “device-accurate”라고 하지 않는다.

---

## 12. rendering intent와 BPC

LittleCMS 기본 intent 이름을 UI와 직접 결박하지 않는다.

```text
perceptual
relative colorimetric
saturation
absolute colorimetric
```

목적별 policy:

| 목적 | 현재 근거 | Windows 결정 |
|---|---|---|
| destination gamut warning | macOS ColorSync relative + BPC | relative + BPC를 parity 시작점으로 사용 |
| current soft-proof profile | current code가 full proof intent를 저장하지 않음 | corpus 전 release default 미확정 |
| general export | Core Graphics output conversion에 의존 | corpus 전 release default 미확정 |
| PRINT | profile/print workflow 의미 필요 | profile corpus와 실측 뒤 명시적으로 결정 |

`cmsIsIntentSupported`는 요청 방향에서 intent 구현 여부를 확인한다. LittleCMS의 내부 fallback을
사용자 선택과 동일하다고 가장하지 않는다.

BPC도 “품질 향상” boolean이 아니다. relative/perceptual, profile class, proof/output 목적과 함께
정의하고 render manifest에 기록한다.

absolute intent의 adaptation state는 context-specific API로 설정할 수 있다. 현재 제품 요구가 없는
상태에서 global/default 값을 바꾸지 않는다.

---

## 13. soft proof 구현

### 13.1 current parity mode

현재 macOS `SoftProof`는 다음 조합이다.

1. completed working image를 표시 범위로 매핑
2. `paperAndBlackInk`이면 ICC `wtpt`/`bkpt` 기반 matrix 적용
3. 선택 RGB output profile을 출력 색공간으로 사용
4. 시스템 display 색 관리로 모니터에 표시

Windows v1은 이 제품 의미를 먼저 재현한다. LittleCMS proof transform이 더 표준적이라는 이유로
현재 화면을 즉시 바꾸지 않는다.

### 13.2 accurate proof mode 후보

LittleCMS `cmsCreateProofingTransformTHR`는 proof device의 결과를 최종 display/output profile로
시뮬레이션할 수 있다. 이를 도입하려면 다음이 명시돼야 한다.

- input profile
- final display/scRGB target profile
- proofing profile
- rendering intent
- proofing intent
- BPC
- adaptation state
- gamut-check 여부
- alarm codes

current parity mode와 결과가 다르면 별도 versioned mode다. macOS판도 같은 기능으로 변경하지 않는 한
Windows만 기본값을 바꾸지 않는다.

### 13.3 Advanced Color

Advanced Color에서는 physical monitor ICC를 직접 final output으로 두지 않는다. proof 결과를 scRGB
presentation 의미로 변환하고 Windows가 display transform을 한다. legacy SDR에서는 monitor ICC가
final target이다.

한 proof transform descriptor를 두 display mode에서 무조건 재사용하지 않는다.

---

## 14. gamut warning mask

`cmsFLAGS_GAMUTCHECK`는 out-of-gamut pixel을 context alarm code로 표시한다. `cmsSetAlarmCodesTHR`로
최대 channel 수의 16-bit code를 설정한다.

### 14.1 collision 문제

output RGB가 alarm code와 우연히 정확히 같을 수 있으므로 단일 magic RGB 비교만으로 완전한 binary
mask라고 단정하지 않는다.

검토할 방법:

1. alarm color를 실제 output gamut에서 만나기 어려운 값으로 선택하고 collision corpus 측정
2. 서로 다른 alarm code로 두 번 변환해 alarm에 따라 바뀐 pixel만 경고로 판정
3. LittleCMS internal gamut pipeline을 public API 범위에서 안전하게 mask로 추출할 수 있는지 조사
4. ColorSync 1-bit gamut mask와 profile별 비교

두 번 변환은 비용이 크므로 preview proxy에서는 허용 가능하지만 full-resolution interactive path는
계측이 필요하다. 정확도를 희생해 channel-difference 근사로 바꾸지 않는다.

### 14.2 context isolation

alarm code는 context state다.

- context를 transform 사용 중 mutate하지 않는다.
- alarm policy가 다른 transform은 별도 frozen context 또는 안전하게 복제된 context를 사용한다.
- cache key에 alarm policy version을 포함한다.
- same transform을 concurrent execute할 수 있어도 그 context를 동시에 재설정하지 않는다.

### 14.3 macOS parity

현재 macOS는 decision buffer를 8-bit linear RGB로 만들고 exact 0/255를 1/254로 이동한 뒤 ColorSync
gamut-check를 실행한다. Windows는 다음 네 mask를 비교한다.

- ColorSync raw boundary
- ColorSync 1/254 adjusted
- LittleCMS raw boundary
- LittleCMS 1/254 adjusted

false warning을 줄이는 규칙을 엔진별로 실측하며, macOS workaround를 이유 없이 복사하지 않는다.

---

## 15. thread와 병렬 실행

### 15.1 공식 API 보장

LittleCMS 2.18 API 문서는 다음을 명시한다.

- `cmsDoTransform`은 re-entrant다.
- 같은 transform handle을 여러 thread에서 재사용할 수 있다.
- `cmsDoTransformLineStride`도 re-entrant이며 같은 handle의 multi-thread 사용이 가능하다.

따라서 GPL `threaded` plugin 없이 app worker pool에서 서로 겹치지 않는 row range를 병렬 처리할 수
있다.

### 15.2 기준 병렬화

```text
한 immutable transform lease
  → image rows를 bounded chunk로 분할
  → worker마다 독립 input/output byte range
  → 같은 cmsHTRANSFORM으로 cmsDoTransformLineStride
  → barrier
  → 다음 pipeline stage
```

규칙:

- output range가 겹치지 않는다.
- transform 삭제/eviction은 모든 lease가 끝난 뒤다.
- context/profile 설정을 실행 중 변경하지 않는다.
- 작은 이미지와 프록시는 single-thread가 더 빠를 수 있다.
- worker 수는 logical processor 수에 고정하지 않고 memory bandwidth와 다른 render task를 고려한다.
- interactive preview가 batch export에 굶지 않도록 scheduler priority를 분리한다.
- x64와 ARM64에서 각각 threshold를 측정한다.

### 15.3 `cmsDoTransformLineStride`

whole image나 row block에는 repeated one-row `cmsDoTransform`보다 `cmsDoTransformLineStride`를 우선한다.
공식 문서와 plugin 문서 모두 stride API가 image geometry를 알려줘 더 효율적일 수 있다고 설명한다.

그러나 `threaded` plugin benchmark 숫자를 base library + Negaflow scheduler의 성능 약속으로 인용하지
않는다.

### 15.4 cancellation

transform 실행 API는 `void`이며 호출 중 앱 cancellation token을 확인하지 않는다. 따라서 큰 이미지를
무제한 한 호출로 처리하지 않는다.

- row block 사이에서 cancellation 확인
- block height는 cancellation latency와 throughput을 함께 benchmark
- partially written output은 publish하지 않음
- export temp artifact는 transaction 정책으로 정리
- canceled transform/cache는 재사용 가능하지만 request 결과는 폐기

---

## 16. transform 실행은 실패를 보고하지 않는다

공식 문서는 `cmsDoTransform`과 stride variant가 실행 중 실패를 반환하거나 error log를 보내지 않는다고
설명한다. 이것은 모든 입력이 안전하다는 뜻이 아니다.

wrapper가 호출 전에 보장해야 하는 것:

- non-null live transform
- formatter와 profile channel count 일치
- finite sizes
- checked row/plane offsets
- input/output buffer capacity
- non-overlap 또는 API가 허용하는 exact in-place 계약
- transform lifetime lease
- profile/context lifetime
- cancellation state

transform creation에서 모든 profile·intent·formatter 실패를 잡는다. release build에서 LittleCMS debug
assert에 의존하지 않는다.

buffer overrun이 가능한 잘못된 size는 library error callback으로 복구되지 않는다. native wrapper
boundary validation과 fuzz가 필수다.

---

## 17. cache 설계

### 17.1 key

```text
TransformKey
  sourceProfileSHA256
  destinationProfileSHA256
  proofProfileSHA256, optional
  inputFormatter
  outputFormatter
  intent
  proofIntent
  BPC
  flags
  alarmPolicyVersion
  adaptationState
  colorPolicyVersion
  lcmsPackageIdentity
```

profile display name이나 path를 key로 쓰지 않는다.

### 17.2 entry

```text
TransformEntry
  immutable key
  context/profile/transform RAII owners
  creation diagnostics
  memory estimate
  active lease count
  last used monotonic time
```

### 17.3 eviction

- bounded by entry count와 추정 memory 둘 다 고려
- active lease가 있는 entry는 삭제하지 않음
- display profile 변경은 해당 target entry만 무효화
- LittleCMS/policy update는 전체 관련 cache namespace 변경
- failure result는 짧은 negative cache 후보지만 profile이 바뀌면 즉시 새 key
- transient allocation failure를 영구 negative cache하지 않음

current macOS gamut cache capacity 8을 전체 Windows transform cache에 그대로 쓰지 않는다.

---

## 18. 성능 정책

### 18.1 먼저 측정할 것

- transform creation time
- first execution과 warm execution
- matrix/shaper vs CLUT
- float32 vs final 16-bit/8-bit
- row block height
- 1/2/4/8 worker scaling
- x64 Intel/AMD
- ARM64 Qualcomm
- input/output memory bandwidth
- WIC encoder handoff
- cache hit ratio
- proof/gamut two-pass 비용

### 18.2 CPU가 적합한 경로

- 작은 preview/profile probe
- CLI/CI
- export encoder가 CPU pixels를 요구하는 경로
- transform 생성
- exact soft proof/gamut oracle
- GPU device loss fallback

### 18.3 D2D와 비교

GPU 변환은 다음 총비용으로 비교한다.

```text
CPU LittleCMS:
  source ready in CPU memory
  + transform
  + upload or encoder handoff

D2D BEST:
  upload/interoperability
  + GPU transform
  + synchronization
  + readback if encoder needs CPU memory
```

GPU kernel 시간만 빠르다고 export backend를 전환하지 않는다. interactive canvas처럼 texture가 이미
GPU에 있고 결과도 GPU에 남는 경로에서 D2D가 가장 유리할 가능성이 높다.

### 18.4 SIMD

GPL fast-float plugin은 사용하지 않는다. base library에서 추가 CPU 최적화가 필요하면 다음 순서다.

1. call/stride/chunk/cache 구조 개선
2. app-level row parallelism
3. compiler optimization과 PGO 가능성 측정
4. profile class별 hot path 확인
5. clean-room, permissive-license 또는 original Negaflow SIMD 후보 검토

정확도 corpus 없이 fast-math를 활성화하지 않는다. x64 AVX2와 ARM64 NEON은 기능을 나누는 경계가
아니며 dispatch로 속도만 달라야 한다.

---

## 19. export와 PRINT 통합

### 19.1 일반 export

```text
working RGBA/RGB float32
  → resize
  → output sharpen
  → LittleCMS destination transform
  → encoder bit-depth conversion/dither
  → WIC/libtiff encode
  → destination ICC embed
  → read-back validation
```

transform 성공 뒤 profile embedding이 실패하면 export 전체가 실패한다. profile 없는 파일을 성공
결과로 publish하지 않는다.

### 19.2 PRINT

- `prtr` class
- `RGB ` data color space
- Lab/XYZ PCS
- required direction/intent support
- immutable hash-bound snapshot
- render 직전 revalidation

LittleCMS가 CMYK transform을 지원해도 current product UI가 CMYK printer profile을 받도록 확장하지
않는다.

### 19.3 atomicity

색 변환 실패는 source나 기존 output을 덮어쓰지 않는다.

```text
temporary output
  → pixel encode
  → profile embed
  → container finalize
  → reopen and inspect
  → expected profile hash/metadata 확인
  → atomic publish
```

batch checkpoint에는 transform policy, profile hash, package identity를 포함한다. resume 시 하나라도
다르면 기존 partial 결과를 그대로 이어가지 않는다.

---

## 20. display 통합

LittleCMS가 monitor ICC를 사용하는 것은 **legacy SDR explicit ICC mode**뿐이다.

Advanced Color mode에서는:

- LittleCMS는 proof/output simulation 또는 working→scRGB 준비에 사용할 수 있다.
- physical monitor ICC로 직접 최종 encode하지 않는다.
- swap chain을 정확한 DXGI color space로 tag한다.
- Windows가 display transform을 수행한다.

display mode가 바뀌면 transform cache key의 `DisplayBindingRevision`과 target 의미가 바뀐다.
legacy monitor-coded pixels를 scRGB tag surface에 재사용하지 않는다.

자세한 상태 machine은 [color-pipeline.md](color-pipeline.md)를 따른다.

---

## 21. error handling과 logging

### 21.1 context logger

`cmsSetLogErrorHandlerTHR`로 context별 callback을 설정한다. callback은 다음을 하지 않는다.

- throw
- blocking IO
- UI 호출
- profile bytes dump
- full user path 기록
- allocator 재진입을 유발하는 큰 allocation

callback은 bounded error record를 native buffer에 남기고 wrapper가 API return 뒤 해석한다.

### 21.2 stable error taxonomy

```text
ColorError.InvalidProfileStructure
ColorError.ProfileOpenFailed
ColorError.UnsupportedProfileClass
ColorError.UnsupportedColorSpace
ColorError.UnsupportedPCS
ColorError.IntentUnavailable
ColorError.TransformCreationFailed
ColorError.BufferLayoutInvalid
ColorError.ProfileHashMismatch
ColorError.ResourceLimitExceeded
ColorError.Canceled
ColorError.InternalInvariant
```

upstream numeric code/string은 diagnostics에 제한적으로 보존하되 public ABI와 localization key로 쓰지
않는다.

### 21.3 개인정보

telemetry에는 기본적으로 다음만 남긴다.

- profile class/color-space/PCS
- size bucket
- hash의 비가역 short correlation token, 필요한 경우
- transform type
- reason code
- library/package version
- architecture

profile 이름, path, embedded copyright/description tag는 사용자 동의 없는 telemetry에서 제외한다.

---

## 22. security와 fuzzing

### 22.1 threat model

profile은 다음 경로에서 들어올 수 있다.

- imported photo embedded ICC
- user-selected display/output profile
- scanner plugin result
- catalog restore
- network/removable source
- shared project/package

모두 비신뢰 bytes로 취급한다.

### 22.2 fuzz targets

- standalone profile validator
- `cmsOpenProfileFromMemTHR`
- header/tag enumeration wrapper
- required-intent probe
- transform creation matrix
- proof transform creation
- tiny pixel transform with valid bounded buffers
- profile snapshot serialization/deserialization

corpus mutation:

- truncated header/tag table
- huge declared length
- offset wraparound
- overlapping tags
- recursive/complex pipeline tags
- invalid channel count
- malformed curves/CLUT dimensions
- v2/v4 edge cases
- MHC2/private tags
- large but structurally valid files

### 22.3 containment decision

초기 기준은 prevalidation + fuzzed in-process core library다. 보안 검토에서 parser containment이 필요하다고
판단되면 profile inspection을 별도 restricted helper process로 옮기는 spike를 한다. 근거 없이 모든
transform을 IPC로 보내 성능과 복잡도를 늘리지 않는다.

---

## 23. 테스트 매트릭스

### 23.1 unit

- context/logger lifetime
- header/runtime version mismatch detection
- profile bytes/hash binding
- class/color-space/PCS policy
- unsupported intent rejection
- formatter/channel mismatch rejection
- checked stride arithmetic
- alpha copy/opaque output
- transform cache key equality
- active lease eviction safety
- cancellation between row blocks

### 23.2 conformance/golden

- sRGB ↔ linear sRGB
- Display P3 ↔ working
- Adobe RGB ↔ working
- ICC v2/v4 matrix profiles
- CLUT profiles
- printer RGB Lab PCS
- printer RGB XYZ PCS
- relative/perceptual/absolute/saturation where supported
- BPC on/off
- negative and >1 float patches
- soft-proof corpus
- gamut alarm corpus

### 23.3 architecture

- x64 Intel
- x64 AMD
- ARM64 Qualcomm
- Debug/Release
- static/dynamic selected policy
- packaged/unpackaged native DLL load

### 23.4 concurrency

- same transform on 1/2/4/8 workers
- simultaneous different transforms
- cache eviction under active readers
- proof contexts with different alarm codes
- cancellation and shutdown
- repeated display profile changes

### 23.5 comparison

CPU LittleCMS는 다음과 비교한다.

- macOS ColorSync golden output
- Direct2D Color Management `QUALITY_BEST`
- encoded file decoded back through a common reference
- real display/print measurement, 가능한 경우

허용 오차는 transform 종류별로 정의한다. 단일 “pixel diff 1” 규칙을 모든 bit depth와 profile에 쓰지
않는다.

---

## 24. benchmark 시나리오

| ID | 입력 | transform | 목적 |
|---|---|---|---|
| LCM-B01 | 2K RGB float | matrix/shaper | interactive preview threshold |
| LCM-B02 | 6K RGB float | matrix/shaper | full preview/export |
| LCM-B03 | 16-bit scan 대형 | source ICC → working | import throughput |
| LCM-B04 | 6K float | CLUT printer RGB | PRINT throughput |
| LCM-B05 | proxy | proof + gamut check | interactive warning latency |
| LCM-B06 | 39-image batch | mixed outputs | batch scheduler/cache |
| LCM-B07 | dual export | same transform | concurrent reuse |
| LCM-B08 | profile switching | transform creation | UI responsiveness/cache |

기록:

- wall time
- CPU time
- transform creation/execution 분리
- peak committed/private bytes
- cache hit/miss
- worker count
- effective memory bandwidth
- cancellation latency
- output metric/hash

plugin marketing benchmark를 제품 수치로 복사하지 않는다.

---

## 25. 구현 순서

### L0 — dependency/legal pin

- vcpkg exact baseline
- `lcms` port 2.19.1#1 후보 확인
- no optional features
- MIT notice/SBOM
- x64/ARM64 build

### L1 — profile foundation

- immutable snapshot/hash
- structural validator
- context logger
- memory open
- built-in profile assets

### L2 — transform oracle

- float RGB transform
- checked stride wrapper
- cache/lifetime
- CLI golden corpus
- row-level cancellation

### L3 — outputs

- general export profiles
- profile embedding read-back
- PRINT fail-closed
- batch checkpoint identity

### L4 — proof/gamut

- current parity mode
- proof transform spike
- alarm mask collision solution
- ColorSync comparison

### L5 — performance

- app worker pool thresholds
- ARM64/x64 measurements
- D2D `BEST` comparison
- only then optional original SIMD research

각 단계는 앞 단계의 corpus와 failure semantics를 보존한다.

---

## 26. 금지 사항

- vcpkg dependency 이름을 `lcms2`로 잘못 기록하지 않는다.
- exact baseline 없이 “latest 2.19.1”을 따라가지 않는다.
- `LCMS_VERSION`만으로 patch release provenance를 증명하지 않는다.
- `fastfloat` 또는 `threaded` GPL feature를 제품에 켜지 않는다.
- global context와 global alarm code를 제품 상태로 사용하지 않는다.
- mutable profile path에서 render 때마다 다시 연다.
- `size_t` profile length를 무검사 `cmsUInt32Number`로 cast하지 않는다.
- unsupported intent의 implicit fallback을 exact parity라고 부르지 않는다.
- alpha가 자동 복사된다고 가정하지 않는다.
- `cmsDoTransform`이 void라는 이유로 buffer validation을 생략하지 않는다.
- 하나의 transform을 삭제하면서 다른 thread가 실행하게 두지 않는다.
- `cmsFLAGS_HIGHRESPRECALC`나 DeviceLink를 측정 없이 성능 기본값으로 쓰지 않는다.
- LittleCMS transform 가능 여부를 printer/device 정확도의 증거로 쓰지 않는다.
- Advanced Color에서 monitor ICC를 중복 적용하지 않는다.
- GPL plugin benchmark를 base MIT build 성능으로 보고하지 않는다.

---

## 27. 열린 결정

| ID | 질문 | 필요한 증거 |
|---|---|---|
| LCMS-OPEN-01 | static-md 또는 dynamic linkage | package layout, servicing, crash diagnostics, 전체 dependency 정책 |
| LCMS-OPEN-02 | product ICC size limit | 실제 profile corpus와 memory/security budget |
| LCMS-OPEN-03 | built-in P3/Adobe/linear-sRGB profile bytes | ColorSync parity corpus와 asset provenance |
| LCMS-OPEN-04 | general export intent/BPC | macOS output corpus |
| LCMS-OPEN-05 | PRINT intent/BPC | profile corpus와 실제 print workflow |
| LCMS-OPEN-06 | collision-free gamut mask extraction | LittleCMS public API spike와 ColorSync comparison |
| LCMS-OPEN-07 | row chunk/worker threshold | Intel/AMD/Qualcomm benchmark |
| LCMS-OPEN-08 | profile parser helper process 필요 여부 | fuzz/security audit |
| LCMS-OPEN-09 | DeviceLink 가치 | end-to-end batch profile |

---

## 28. 공식 자료

Upstream:

- [Little CMS repository](https://github.com/mm2/Little-CMS)
- [Little CMS 2.19.1 release](https://github.com/mm2/Little-CMS/releases/tag/lcms2.19.1)
- [Little CMS 2.19 release notes](https://www.littlecms.com/tags/lcms2-2.19/)
- [Little CMS MIT license](https://github.com/mm2/Little-CMS/blob/master/LICENSE)
- [Little CMS README and ICC 4.4 conformance statement](https://github.com/mm2/Little-CMS/blob/master/README.md)
- [Little CMS 2.18 Engine API](https://www.littlecms.com/LittleCMS2.18%20API.pdf)
- [Little CMS 2.18 tutorial](https://www.littlecms.com/LittleCMS2.18%20tutorial.pdf)
- [Little CMS plugin page](https://littlecms.com/plugin/)

Package/build:

- [vcpkg `lcms` manifest](https://github.com/microsoft/vcpkg/blob/master/ports/lcms/vcpkg.json)
- [vcpkg `lcms` portfile](https://github.com/microsoft/vcpkg/blob/master/ports/lcms/portfile.cmake)
- [vcpkg `lcms` CMake usage](https://github.com/microsoft/vcpkg/blob/master/ports/lcms/usage)
- [upstream Meson options and plugin license warning](https://github.com/mm2/Little-CMS/blob/lcms2.19.1/meson_options.txt)

공식 자료에서 직접 반영한 API 사실:

- context별 plugin/logger/user data와 `THR` 함수
- memory profile open은 contiguous buffer와 32-bit size를 받음
- core는 ICC v2/v4와 ICC 4.4 구현을 표방
- float RGB/RGBA formatter 제공
- alpha는 기본 복사되지 않으며 `cmsFLAGS_COPY_ALPHA` 필요
- `cmsDoTransform`/`cmsDoTransformLineStride`는 re-entrant이고 같은 transform을 여러 thread에서 사용 가능
- stride execution API는 반환값이 `void`
- proofing과 gamut-check는 별도 flags
- intent 미지원 시 library fallback 가능성이 있어 사전 지원 확인 필요
- 2.19 large-profile 최대는 ICC 32-bit 구조의 제약을 받으며 거대 profile 메모리 사용 경고

---

## 29. 관련 문서

- [전체 색 파이프라인](color-pipeline.md)
- [정밀도와 clipping](../01-render-engine/precision-and-clipping.md)
- [측정·통계](../03-measurement/histogram-and-statistics.md)
- [vcpkg와 CMake](../13-build-and-deps/vcpkg-cmake.md)
- [CPU SIMD](../16-cpu/simd-and-dispatch.md)
- [GPU backend 선택](../12-performance/backend-selection.md)
- [catalog와 storage](../14-persistence/catalog-and-storage.md)

---

## 30. 완료 정의

LittleCMS 통합 완료는 package가 link되는 상태가 아니다. 다음을 모두 증명해야 한다.

- exact source/port/baseline/hash/SBOM
- MIT core만 포함되고 GPL optional plugin 없음
- x64·ARM64 native 실행
- context/profile/transform RAII와 shutdown race 없음
- untrusted profile prevalidation·fuzz
- float32 working transform
- checked stride·buffer bounds
- same-transform concurrent execution
- cancellation/publish atomicity
- macOS ColorSync golden parity
- sRGB/P3/Adobe export profile read-back
- PRINT profile snapshot/hash/fail-closed
- soft-proof/gamut mask semantics
- Advanced Color double-management 방지
- CPU 성능 budget과 D2D fallback 관계

누락된 항목은 “향후 최적화”가 아니라 해당 기능의 미완료 evidence로 기록한다.
