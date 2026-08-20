# CPU SIMD와 런타임 디스패치 설계

기준일: 2026-08-04  
대상: 지원 중인 Windows 11 release, C++20 네이티브 엔진, x64 Intel/AMD, ARM64  
상태: v1 기준선과 검증 계약 결정, 개별 커널 최적화는 Windows 실측 뒤 승인  
실기 검증: 아직 없음

관련 문서:

- [Accelerate 대체](accelerate-replacement.md)
- [멀티스레드 렌더·내보내기](../07-threading/multithreading-export.md)
- [backend 선택](../12-performance/backend-selection.md)
- [GPU 범용성](../12-performance/gpu-vendor-portability.md)
- [계측과 프로파일링](../12-performance/profiling-tools.md)
- [CI와 테스트](../12-performance/ci-and-testing.md)
- [CMake와 vcpkg](../13-build-and-deps/vcpkg-cmake.md)

## 1. 결론

Negaflow Windows의 CPU 경로는 특정 CPU 제조사나 한 SIMD 라이브러리를 전제로 하지 않는다.
제품에 반드시 존재하는 기준 경로는 다음 두 개다.

```text
x64     : Windows x64 기본 ISA인 SSE2를 넘지 않는 native baseline
ARM64   : Windows ARM64 ABI 기본 ISA인 Armv8.0-A + NEON/Advanced SIMD baseline
공통    : 의미상 scalar/reference kernel과 동일한 결과 계약
```

여기서 `scalar/reference`는 반드시 “벡터 명령이 하나도 없는 별도 실행 파일”을 뜻하지 않는다. Release
컴파일러가 안전한 기본 ISA 안에서 자동 벡터화할 수 있다. 이 이름은 **정확성의 기준 구현이며 상위 ISA를
요구하지 않는 경로**라는 뜻이다. 필요한 테스트 구성에서는 자동 벡터화를 끈 진짜 scalar build도 만든다.

v1 최적화 정책은 다음과 같다.

1. 먼저 알고리즘, 메모리 이동, 타일 크기, 스레드 수를 고친다.
2. 기본 C++ 루프의 Release 자동 벡터화 결과를 확인한다.
3. ETW/WPA와 microbenchmark에서 반복적으로 큰 비중을 차지한 작은 커널만 수동 SIMD화한다.
4. x64 상위 경로는 커널별 `AVX2`와 `AVX2+FMA` 요구를 구분한다.
5. ARM64에서는 NEON이 기본이므로 별도 “NEON 지원 여부” 디스패치를 만들지 않는다.
6. AVX-512, AVX10, ARM SVE/SVE2는 v1 출하 티어가 아니다.
7. CUDA는 NVIDIA 전용 선택적 GPU backend이며 CPU ISA 디스패치와 섞지 않는다.

Google Highway는 유력한 후보지만 **지금 채택을 확정하지 않는다**. 수동 intrinsics가 여러 아키텍처와 여러
커널에 반복되어 유지보수 비용이 실제로 생긴 뒤, 자체 dispatch 대비 속도·코드 크기·MSVC/ARM64 빌드·라이선스
고지를 비교하는 spike를 통과해야 도입할 수 있다.

## 2. 왜 기존 문서 결정을 수정하는가

기존 초안에는 다음과 같은 과도한 결정이 있었다.

- x64 전체 기준선을 `SSE4.2` 또는 `x86-64-v2`로 올림
- benchmark 없이 Google Highway를 필수 의존성으로 확정
- `AVX2`와 `FMA`를 하나의 CPU capability처럼 취급
- AVX-512/AVX10과 특정 출시 예정 CPU의 시장 상황을 제품 계약으로 사용
- ARM64 Debug CI가 필요 없다고 단정
- JPEG/Deflate codec 구현을 SIMD 문서에서 미리 확정

이 방식은 Negaflow의 “Intel/AMD/ARM64 범용성 우선”과 맞지 않는다. Microsoft 문서상 MSVC x64의 `/arch`
기본값은 `SSE2`다. SSE4.2를 프로세스 전체 기준으로 올릴 기능적 이유가 현재 없다. 또한 AVX2와 FMA는
CPUID에서 서로 다른 기능 비트이며, 부동소수 FMA contraction은 단순 성능 차이가 아니라 결과 반올림을
바꿀 수 있다.

codec 선택은 WIC/libtiff/LibRaw 문서와 dependency 검증이 소유한다. 이 문서는 **Negaflow가 직접 소유하는
CPU pixel/statistics kernel**의 ISA와 dispatch만 다룬다. codec 내부 SIMD는 해당 라이브러리의 검증된 runtime
dispatch에 맡기고 앱에서 중복 구현하지 않는다.

## 3. 지원 매트릭스

### 3.1 출하 아키텍처

| 프로세스 | 사용자 CPU | 출하 상태 | 필수 ISA | 선택적 ISA |
|---|---|---:|---|---|
| x64 | Intel | v1 필수 | SSE2 이하 기본 생성 | AVX2, AVX2+FMA를 커널별 선택 |
| x64 | AMD | v1 필수 | SSE2 이하 기본 생성 | AVX2, AVX2+FMA를 커널별 선택 |
| ARM64 | Qualcomm 및 호환 Windows ARM64 | v1 필수 | Armv8.0-A, FP, NEON | 향후 검증된 Arm 확장 |
| x86 | scanner adapter만 가능 | 본체 비지원 | plugin별 | 본체 ISA 계약과 분리 |
| ARM64EC | 본체 비채택 | 비지원 | 해당 없음 | 재평가 조건이 생길 때만 |

Intel과 AMD는 vendor ID로 다른 pixel path를 고르지 않는다. 동일한 ISA와 결과 계약이면 동일 경로를 쓴다.
제조사 분기는 공개된 processor erratum 또는 반복 가능한 성능/정확성 문제가 있고, model-family 범위와 테스트가
함께 있을 때만 예외로 허용한다.

### 3.2 x64 기준선

MSVC의 x64 `/arch` 기본 코드는 `SSE2`다. 따라서 본체와 baseline object는 다음 원칙을 따른다.

```text
/arch:SSE2 또는 x64 compiler default
상위 ISA intrinsic/header가 baseline public header로 새지 않음
baseline static initializer가 상위 ISA 코드를 호출하지 않음
baseline 경로만으로 앱 시작, import, develop, export, recovery 가능
```

Windows 11을 지원한다고 해서 SSE4.2를 앱 전체 최소 ISA로 올리지 않는다. OS 지원 CPU 목록과 앱의 명시적
ISA 요구는 별개의 계약이다. 기준선 상향이 필요한 날에는 다음을 모두 제시해야 한다.

- 실제 사용자 하드웨어 coverage
- baseline 대비 binary size와 성능
- unsupported CPU의 명확한 installer/runtime 처리
- Intel/AMD 양쪽 physical test
- 복구·업데이트 executable까지 같은 기준을 만족한다는 증거

### 3.3 ARM64 기준선

Microsoft의 Windows ARM64 ABI는 Armv8 이상과 hardware floating point, NEON/Advanced SIMD가 존재한다고
가정한다. MSVC `/arch`를 지정하지 않으면 ARM64의 기본은 `armv8.0`이다.

따라서 ARM64 native build에서는 NEON을 optional feature처럼 매번 조회하지 않는다. NEON을 사용하는
baseline loop가 ARM64의 정상 경로다. 다만 다음은 별개다.

- crypto, CRC, dot-product, FP16, BF16, SVE 같은 **선택적 확장**
- 새 Windows SDK에 추가된 processor-feature 상수
- compiler가 실제로 해당 intrinsic/codegen을 지원하는지
- 앱이 그 확장으로 얻는 실측 이득과 결과 동등성

선택적 확장을 도입할 때만 `IsProcessorFeaturePresent`와 해당 compiler/SDK contract를 사용한다. 하드웨어가
명령을 가진다는 사실만으로 현재 compiler가 안전하게 코드를 만들거나 앱의 모든 대상 OS가 feature flag를
이해한다고 가정하지 않는다.

### 3.4 ARM64EC를 쓰지 않는 이유

ARM64EC는 같은 프로세스에서 ARM64EC 코드와 emulated x64 코드를 상호 운용해야 할 때 가치가 있다.
Negaflow는 scanner integration을 out-of-process JSON plugin으로 격리한다. 따라서 x64 또는 x86 scanner
adapter를 ARM64 UI/engine 프로세스 안에 로드할 필요가 없다.

```text
ARM64 Negaflow.exe / native engine
        │ versioned JSON + artifact handles
        ├── ARM64 scanner plugin process
        ├── x64 scanner plugin process under Windows emulation, 필요 시
        └── x86 scanner adapter process, 계약상 허용될 때만
```

이 경계 덕분에 본체는 pure ARM64로 빌드할 수 있다. ARM64EC는 in-process x64 SDK가 제품 요구가 되는 등
경계가 실제로 바뀔 때만 재평가한다.

## 4. ISA 티어 모델

### 4.1 티어는 앱 전체가 아니라 커널별이다

하나의 global `bestIsa`를 정해 모든 연산에 강제하지 않는다. 어떤 ISA가 최선인지는 데이터 형식과 커널에
따라 다르다.

예:

- byte packing은 AVX2 integer가 이득일 수 있음
- 작은 3×3 color matrix는 호출/정렬 비용 때문에 baseline이 빠를 수 있음
- threshold decision은 FMA contraction을 금지해야 할 수 있음
- branch-heavy deque morphology는 SIMD보다 line parallelism이 중요할 수 있음
- codec은 자체 dispatch가 이미 존재함

따라서 function table은 kernel family별 entry를 가진다.

```text
CpuKernelTable
  convertPlanarToInterleaved
  convertInterleavedToPlanar
  applyPointCurve
  applyThreeChannelLut
  accumulateHistogramPartial
  mergeHistogram
  boxMeanRow
  packExportPixels
  checksumBlock       // 필요할 때만
```

각 entry는 같은 ABI와 의미 계약을 지키면서 서로 다른 tier를 선택할 수 있다.

### 4.2 v1 x64 티어

| 내부 tier | 요구 capability | 허용 용도 | v1 상태 |
|---|---|---|---|
| `x64_baseline` | SSE2 | 모든 기능, reference/fallback | 필수 |
| `x64_avx2_integer` | AVX usable + AVX2 | packing, byte/int LUT, integer shuffle 등 | 계측된 커널만 |
| `x64_avx2_float` | AVX usable + AVX2, FMA 명령 없음이 검증됨 | float vector math | 필요가 입증될 때 |
| `x64_avx2_fma` | AVX usable + AVX2 + FMA | contraction 허용 커널 | 결과 계약 통과 시 |
| `x64_avx512_*` | 세부 subfeature + OS state | 없음 | v1 미출하 |
| `x64_avx10_*` | 세부 version/width + OS state | 없음 | v1 미출하 |

`AVX2`와 `FMA`는 detection 단계에서 반드시 분리한다. MSVC의 `/arch:AVX2`가 floating code에 FMA를
사용할 수 있으므로, 단순히 source에서 FMA intrinsic을 쓰지 않았다는 사실만으로 `x64_avx2_float`를
“FMA 불필요”라고 부르지 않는다. 다음 중 하나로 증명해야 한다.

- 해당 번역 단위가 integer-only여서 FMA codegen 대상이 아님
- compiler flags와 contraction policy를 고정하고 disassembly에서 FMA instruction 부재 확인
- 별도 compiler/target attribute 전략을 채택하고 지원 toolchain matrix에서 검증

증명하지 못하면 v1 상위 floating tier 이름은 `x64_avx2_fma`로 두고 두 feature가 모두 있는 CPU에서만 쓴다.

### 4.3 AVX-512와 AVX10

v1에서 제외하는 이유는 “쓸모없어서”가 아니다. 다음 복잡도를 현재 병목 증거가 정당화하지 못하기 때문이다.

- 여러 AVX-512 subfeature 조합
- XCR0의 추가 register-state 확인
- heterogeneous core와 VM/firmware 노출 차이
- vector width에 따른 clock, power, memory-bandwidth tradeoff
- code size와 instruction-cache 증가
- physical vendor/CPU matrix 확대
- 작은 타일에서 더 넓은 벡터가 오히려 손해인 구간

향후 추가 기준:

1. shipping workload에서 해당 커널이 CPU critical path의 유의미한 비율일 것
2. AVX2 대비 wall-clock과 energy 또는 throughput 이득이 반복될 것
3. Intel과 AMD 중 지원하는 실제 대상에서 physical test할 것
4. unsupported core/VM에서 baseline fallback이 증명될 것
5. numeric/decision equivalence와 downclock 영향을 함께 측정할 것

CPU 출시 전망이나 마케팅 이름만으로 tier를 추가하지 않는다.

### 4.4 ARM 선택적 확장

ARM64 v1은 NEON baseline 하나로 시작한다. SVE/SVE2나 dot-product 같은 확장은 다음 조건이 모두 충족될 때
독립 tier로 추가한다.

- minimum Windows SDK와 OS feature-query contract가 고정됨
- MSVC 또는 채택된 clang-cl에서 codegen과 unwind/PDB가 지원됨
- physical Windows ARM64 device에서 실행됨
- vector-length agnostic tail/alignment code가 검증됨
- NEON 대비 shipping workload 이득이 있음
- ARM64 baseline binary로의 명령 누출이 없음

Windows SDK 26100은 Windows 11 24H2 API 세대에서 SVE와 여러 최신 ARM feature query 상수를 추가했지만, 이는
Negaflow가 해당 명령을 사용해야 한다는 뜻이 아니다. SDK의 조회 가능성, CPU 지원, compiler 지원, 제품
필요성을 각각 따로 확인한다.

## 5. runtime capability 탐지

### 5.1 탐지 결과와 kernel 선택을 분리한다

```text
DetectCpuCapabilities()  -> immutable facts
ValidateOsVectorState()  -> usable facts
SelectKernelTable()      -> policy + benchmark-approved entries
PublishKernelTableOnce() -> immutable process-lifetime table
```

hardware feature가 있다고 보고된 것과 앱이 해당 명령을 안전하게 실행할 수 있다는 것은 같지 않다. 특히
AVX 계열은 CPU feature뿐 아니라 OS가 extended register state를 저장·복원하도록 활성화했는지 확인해야 한다.

### 5.2 x64 탐지

MSVC에서는 `<intrin.h>`의 `__cpuid`/`__cpuidex`와 `_xgetbv`를 사용한다. 정확한 leaf/subleaf/bit는 Intel과
AMD의 현행 architecture manual을 기준으로 구현 시점에 상수와 테스트를 고정한다.

개념 순서:

```text
1. CPUID maximum leaf 확인
2. CPUID.1에서 OSXSAVE, AVX, FMA 등 개별 bit 확인
3. OSXSAVE가 있을 때만 XGETBV(XCR0) 실행
4. XMM/YMM state가 OS에 활성화됐는지 확인
5. CPUID.7 subleaf 0에서 AVX2와 추가 feature 확인
6. hardware bit AND OS-state 결과를 usable capability로 저장
7. compiler가 생성한 tier의 실제 요구 feature set과 대조
```

금지:

- CPUID의 AVX2 bit 하나만 보고 AVX2 code 호출
- CPU vendor string으로 feature 추정
- OS version 문자열로 ISA 추정
- 예외를 잡아 illegal instruction을 capability probe로 사용
- AVX2가 있으면 FMA도 있다고 간주
- VM에서 host CPU spec만 보고 guest 노출을 추정

`IsProcessorFeaturePresent(PF_AVX2_INSTRUCTIONS_AVAILABLE)`는 Windows가 제공하는 유용한 high-level
신호지만, Negaflow의 tier가 요구하는 세부 feature와 XCR0 정책을 문서화하기 위해 자체 capability record를
유지한다. 두 경로가 불일치하면 더 보수적인 결과를 사용하고 telemetry에는 개인정보 없는 feature mask와
fallback reason을 기록한다.

### 5.3 ARM64 탐지

Windows ARM64의 Armv8/FP/NEON은 ABI baseline이다. 따라서 앱 시작 때 NEON 여부가 false면 “scalar로 조용히
계속”하는 대신 지원 환경 위반으로 취급해야 한다. 정상 Windows ARM64 장치에서는 발생하지 않아야 하며,
오류 보고에 OS build, process architecture, feature query 결과만 남긴다.

선택적 확장은 `IsProcessorFeaturePresent`의 해당 `PF_ARM_*` 상수를 사용하되 다음을 지킨다.

- app의 minimum Windows SDK에서 상수가 존재하는지 compile-time guard
- minimum OS보다 새 feature라면 runtime API/constant contract 검증
- false는 “없음” 또는 HAL이 탐지하지 못함을 모두 뜻하므로 baseline으로 fallback
- feature group을 한 상수로 뭉뚱그리지 않음
- processor name이나 Qualcomm product name으로 추정하지 않음

### 5.4 초기화와 불변성

dispatch 초기화는 process당 한 번, pixel worker 시작 전에 수행한다.

```text
startup
  load internal test override, production에서는 없음
  detect features
  validate OS state
  select table
  emit one CpuDispatchSelected event
  publish const table
  start workers
```

작업 중 table을 바꾸지 않는다. thread마다 다시 CPUID를 호출하지 않는다. heterogeneous core에서 “현재 core가
지원하니 실행”하는 식의 per-thread 즉흥 선택도 금지한다. Windows가 process에 안전하게 노출한 공통 usable
feature만 사용한다.

## 6. 테스트용 강제 모드

release 내부 API 또는 CLI self-test에는 다음 모드가 필요하다. 일반 사용자 설정으로 노출하지 않는다.

| 모드 | 의미 | unsupported 요청 |
|---|---|---|
| `auto` | runtime policy가 entry별 최적 tier 선택 | 해당 없음 |
| `baseline` | 모든 entry를 architecture baseline으로 고정 | 항상 가능해야 함 |
| `scalar-test` | 가능한 kernel을 자동 벡터화 금지 reference build로 고정 | test artifact에서만 |
| `avx2` | AVX2 비-FMA 계약 entry만 강제 | 명시적 실패 또는 baseline fallback을 테스트별 선택 |
| `avx2-fma` | FMA 허용 entry까지 강제 | capability가 없으면 실행 금지, 명확히 실패 |
| `neon` | ARM64 baseline table 확인 | x64에서는 명확히 거부 |

강제 unsupported mode가 SIGILL/illegal instruction까지 진행해서는 안 된다. 다음 두 동작 중 무엇인지 test
case가 명시해야 한다.

- strict mode: `UnsupportedCpuTier`로 시작/테스트 실패
- fallback test: 명시적 reason을 남기고 baseline으로 이동

조용히 다른 tier를 실행한 뒤 “강제 테스트 통과”라고 보고하는 것은 금지한다.

## 7. 번역 단위와 링크 경계

### 7.1 기본 구조

상위 ISA 코드는 별도 source/target/object library로 분리한다.

```text
engine/cpu/
  cpu_capabilities.cpp           baseline only
  cpu_dispatch.cpp               baseline only
  kernels_reference.cpp          scalar/reference semantics
  kernels_x64_baseline.cpp       /arch:SSE2
  kernels_x64_avx2_integer.cpp   isolated AVX2 requirement
  kernels_x64_avx2_fma.cpp       isolated AVX2 + FMA requirement
  kernels_arm64_neon.cpp         /arch:armv8.0
  cpu_kernel_abi.h               plain scalar types/pointers only
```

이 경로는 설계 예시이며 구현 시 실제 CMake target 구조에 맞춘다. 중요한 것은 파일명이 아니라 다음 경계다.

- public ABI에는 `__m256`, NEON vector type, Highway target type를 노출하지 않음
- function parameter는 pointer, dimensions, strides, small plain structs만 사용
- 상위 ISA 함수는 baseline TU에서 inline되지 않는 외부 symbol을 통해 호출
- ISA-specific template와 inline helper를 common header에 두지 않음
- namespace/static initializer에서 SIMD vector를 만들지 않음
- LTO가 상위 명령을 baseline caller로 이동시키지 않는지 검증

### 7.2 왜 분리가 필요한가

일부 TU만 `/arch:AVX2`로 컴파일해도 공유 inline/template가 COMDAT/ODR 병합되거나 LTO에서 이동하면 상위
명령이 예상하지 않은 함수로 샐 수 있다. 결과는 정상 dispatch 이전의 startup crash 또는 baseline 경로의
illegal instruction이다.

따라서 “dispatch if문이 있다”는 것만으로 안전하다고 판단하지 않는다. binary artifact를 검사한다.

### 7.3 binary 검증

CI에서 최소한 다음을 한다.

- PE/COFF symbol과 section map 보존
- baseline object/disassembly에 YMM/ZMM/FMA instruction이 없는지 검사
- AVX2 object가 의도한 symbol만 export하는지 검사
- startup/static initializer call graph에 upper-tier symbol이 없는지 확인
- forced baseline으로 모든 core scenario 실행
- AVX2 미지원 VM 또는 emulator에서 baseline startup/export smoke

단순 byte grep은 instruction boundary를 오인할 수 있으므로 disassembler가 해석한 명령을 검사한다. 검사
도구와 version을 CI image에 고정한다.

## 8. 부동소수점 의미 계약

### 8.1 전역 fast-math 금지

색 처리와 자동 판정은 작은 반올림 차이가 결과를 바꿀 수 있다. engine 전체에 `/fp:fast`, reassociation,
unsafe-math 같은 옵션을 켜지 않는다. 필요하면 커널별로 결과 계약을 분류하고 가장 좁은 TU에서만 허용한다.

### 8.2 FMA는 별도 의미 선택이다

`a * b + c`를 FMA 한 번으로 계산하면 중간 반올림이 한 번 줄어든다. 더 정확할 수도 있지만 baseline과
bitwise 동일하지 않을 수 있다. 따라서 다음 분류를 사용한다.

| 연산 유형 | 허용 기준 |
|---|---|
| display/export color transform | 지정 tolerance와 perceptual metric 통과 시 가능 |
| LUT interpolation | endpoint, monotonicity, max error 통과 시 가능 |
| histogram bin 결정 | 같은 bin을 보장하지 못하면 금지 |
| threshold/auto-tone decision | decision parity를 보장하지 못하면 금지 |
| connected-component label/merge | exact result와 stable ID 필요 |
| checksum/provenance | bit exact, FMA 무관한 integer path |

“화면으로 차이가 안 보인다”는 자동 보정이나 component decision의 동등성 근거가 아니다.

### 8.3 NaN, Inf, denormal, rounding

모든 SIMD kernel contract는 다음을 정한다.

- NaN 입력을 보존, 0으로 치환, 또는 visible error 중 어느 것으로 처리하는가
- positive/negative infinity를 clamp하기 전 어느 stage에서 거부하는가
- negative zero가 serialization/decision에 영향을 주는가
- denormal을 flush-to-zero할 수 있는가
- float-to-integer rounding이 nearest-even, truncate 등 무엇인가
- saturating pack의 범위와 alpha 처리
- out-of-range linear values를 color pipeline 어느 경계에서 clamp하는가

worker thread가 MXCSR/FPCR을 임의로 바꾸지 않는다. 외부 codec/plugin이 FP control state를 바꿀 가능성이
있으면 job 경계에서 검증하거나 소유 process를 분리한다. thread별 상태 차이로 같은 사진의 결과가 달라져서는
안 된다.

### 8.4 동등성 등급

| 등급 | 대상 | 요구 |
|---|---|---|
| E0 exact bytes | masks, labels, histogram counts, metadata, packed integer | byte-for-byte 동일 |
| E1 exact decision | percentiles, auto parameters, branch/threshold 결과 | 최종 결정 동일 |
| E2 bounded numeric | float intermediate, color matrix, resize intermediate | per-channel error bound |
| E3 perceptual + numeric | final display/export image | numeric bound + perceptual metric + visual spot check |

각 kernel entry는 등급을 선언한다. tolerance는 구현 편의를 위해 나중에 넓히지 않고 macOS reference와 제품
품질 요구에서 먼저 정한다.

## 9. 커널별 우선순위

### 9.1 수동 SIMD 후보

다음은 연속 메모리와 반복적인 동일 연산이 있어 후보가 될 수 있다. 후보라는 말은 구현 확정이 아니다.

- planar/interleaved 변환
- 8/16-bit unpack과 float normalize
- pointwise exposure/contrast/curve
- 3-channel matrix와 국소 LUT
- alpha premultiply/unpremultiply, 정확성 계약이 허용할 때
- histogram partial accumulation의 일부
- export pack과 saturating conversion
- checksum/hash library가 자체 acceleration을 제공하지 않는 부분

승격 조건:

```text
shipping-size fixture에서 stage CPU 시간 >= 합의된 비중
baseline보다 end-to-end 이득
memory traffic 증가 없음 또는 이득으로 상쇄
x64 Intel + AMD + ARM64 결과 계약 통과
small ROI crossover threshold 존재
```

### 9.2 SIMD보다 알고리즘/스레딩이 먼저인 커널

현재 macOS 코드 근거상 다음은 곧바로 wide-vector intrinsics로 옮기지 않는다.

#### morphology min/max

`DefectMorphology.swift`의 `separableExtreme`는 monotonic deque를 쓰는 데이터 의존적 알고리즘이다.
분기와 deque head/tail 변화 때문에 직접 SIMD화보다 행/열 단위 병렬화와 cache layout을 먼저 측정한다.

#### box mean

rolling integral/row sum은 누적 의존성이 있고 큰 이미지에서 memory bandwidth와 accumulator 정밀도가 중요하다.
누산은 `double` 계약을 유지한다. float32로 낮춰 SIMD lane 수를 늘리지 않는다.

#### connected components와 defect classification

tile별 후보 생성은 병렬화할 수 있지만 component merge, label, stable ordering은 deterministic해야 한다.
completion order가 결과 ID나 threshold decision에 스며들면 안 된다.

#### histogram과 auto tone

thread-local histogram은 유용하지만 shared atomic bin update를 넓은 SIMD로 밀어 넣는다고 자동으로 빨라지지
않는다. partial histogram, cache footprint, merge 순서를 먼저 설계하고 E0/E1 동등성을 지킨다.

### 9.3 작은 ROI

dispatch call, alignment check, prologue/epilogue, tail 처리 비용 때문에 작은 crop/thumbnail/tile에서는 baseline이
더 빠를 수 있다. entry마다 benchmark-derived crossover를 둘 수 있지만 다음을 지킨다.

- magic pixel count를 추측으로 고정하지 않음
- width뿐 아니라 stride, channel count, format을 고려
- threshold 주변 benchmark를 반복
- CPU model별 table을 거대하게 만들지 않음
- threshold가 없어도 correctness는 같음

### 9.4 codec SIMD

WIC, libjpeg-turbo, libdeflate, zlib-ng, libtiff, LibRaw 등은 각자 CPU dispatch와 build 옵션을 가질 수 있다.
어떤 codec을 채택할지는 해당 I/O/의존성 문서에서 결정한다.

Negaflow 원칙:

- codec의 공식 runtime dispatch를 우선
- codec source를 vendor별로 임의 패치하지 않음
- app global `/arch:AVX2`가 dependency baseline을 오염시키지 않음
- dependency가 ARM64 native인지 physical smoke test
- active codec/version/features를 diagnostics에 기록
- codec 내부 SIMD 속도를 Negaflow 자체 kernel 성과로 중복 계산하지 않음

## 10. 메모리 계약

SIMD crash와 조용한 손상의 대부분은 ISA보다 buffer 계약에서 생긴다.

### 10.1 dimensions와 stride

entry 호출 전에 다음을 checked arithmetic으로 검증한다.

```text
width > 0, height > 0
channels와 bytesPerChannel이 지원 범위
rowBytes >= minimumRowBytes
height * rowBytes overflow 없음
ROI가 image bounds와 교차하고 정규화됨
input/output byte span이 계산 크기 이상
negative stride 지원 여부가 명시됨
```

WIC/Direct2D/codec에서 받은 stride를 `width * pixelSize`라고 추정하지 않는다.

### 10.2 alignment

기본 entry는 unaligned pointer에서도 안전해야 한다. aligned load/store는 다음일 때만 별도 fast path로 쓴다.

- allocator와 row stride가 필요한 alignment를 보장
- ROI offset 뒤에도 alignment가 유지
- assertion뿐 아니라 release validation이 있음
- 이득이 실제 측정됨

ARM64 Windows가 일반 메모리의 일부 misaligned access를 처리해도 alignment 비용이 항상 0이라는 뜻은 아니다.
반대로 alignment를 위해 큰 copy를 추가하면 전체 성능이 나빠질 수 있다.

### 10.3 tail

width가 vector lane 수의 배수가 아니어도 정확해야 한다.

허용 전략:

- full-vector loop + scalar tail
- 안전한 masked load/store가 target에 있을 때 mask
- allocator가 contract로 보장한 padding, 읽기/쓰기 범위를 별도 검증했을 때만 padded access

금지:

- allocation 밖 over-read가 “보통 page 안”이라며 허용
- output row padding에 무단 쓰기
- 다음 row를 현재 row tail로 읽기
- 마지막 pixel을 복제해 decision kernel에 포함

### 10.4 overlap과 aliasing

각 entry는 in-place, partial overlap, no-overlap 중 하나를 선언한다. `restrict`와 compiler alias assumption은
caller가 실제로 보장할 때만 쓴다. preview surface와 cache buffer가 같은 allocation의 view일 수 있으므로 주소
범위를 확인하지 않고 no-alias로 간주하지 않는다.

### 10.5 scratch와 allocation

hot loop에서 heap allocation하지 않는다. scratch는 job/tile scheduler가 byte budget 안에서 빌리고 worker-local로
재사용한다. SIMD alignment를 이유로 전체 55MP frame의 중복 float buffer를 만들지 않는다.

## 11. SIMD와 멀티스레딩의 상호작용

SIMD speedup과 thread speedup을 곱셈으로 가정하지 않는다. image pipeline은 memory bandwidth에 먼저 닿을 수
있다.

검증 matrix:

```text
baseline  × 1, 2, 4, N workers
AVX2      × 1, 2, 4, N workers
NEON      × 1, 2, 4, N workers
small / medium / 55MP / virtual batch
interactive preview / single export / batch export
```

관찰할 값:

- wall-clock과 CPU time
- memory bandwidth, cache misses, page faults
- peak committed bytes
- package power/thermal throttling이 가능한 장치에서는 장기 throughput
- UI input-to-present latency
- first-file preparation과 steady-state throughput
- worker idle/queue wait

한 커널을 AVX2화한 뒤 worker 수를 그대로 두면 memory bandwidth 포화가 빨라져 전체 batch throughput이
나빠질 수 있다. scheduler는 active backend와 job의 byte pressure를 알고 concurrency를 조절하되 CPU model별
복잡한 autotuner를 v1에 넣지 않는다. 소수의 검증된 policy만 둔다.

managed `.NET ThreadPool`, native CPU workers, codec threads, GPU driver threads를 모두 합쳐 logical core 수보다
훨씬 많은 runnable thread를 만들지 않는다. 외부 library가 내부 thread를 만드는지 dependency별로 확인한다.

## 12. Highway 도입 게이트

### 12.1 현재 상태

Highway는 C++17 portable SIMD와 static/dynamic dispatch를 제공하고 x86, Arm 등 여러 target을 지원한다.
공식 repository는 Apache-2.0/BSD-3 이중 라이선스를 밝힌다. runtime dispatch, tail 처리, 여러 ISA에서 같은
kernel source를 유지하는 데 장점이 있다.

하지만 다음 이유로 v1 필수 의존성을 지금 확정하지 않는다.

- 현재 수동 SIMD 대상 커널 수가 아직 실측되지 않음
- MSVC에서 target별 compile flag와 Highway macro contract를 정확히 맞춰야 함
- upstream 문서도 MSVC AVX2 codegen에 별도 `/arch:AVX2` 주의를 설명함
- dynamic dispatch의 첫 호출 탐지와 target TU include pattern을 제대로 따라야 함
- dependency 자체의 ARM64/MSVC/Windows test matrix를 Negaflow가 재검증해야 함
- binary size와 build time 증가를 아직 측정하지 않음
- 직접 소유하는 narrow function table이면 충분할 가능성이 있음

### 12.2 도입 조건

다음 중 적어도 하나가 생겨야 spike를 연다.

- 동일한 pixel kernel을 x64 baseline, AVX2, ARM64 NEON으로 세 번 유지하게 됨
- manual dispatch boilerplate가 세 kernel family 이상 반복됨
- tail/mask/alignment 버그가 자체 abstraction에서 반복됨
- SVE 같은 scalable vector target이 실제 Windows 제품 범위에 들어옴

spike acceptance:

| 항목 | 통과 조건 |
|---|---|
| correctness | reference와 E0–E3 계약 통과 |
| x64 | Intel/AMD physical AVX2 및 baseline fallback |
| ARM64 | native Windows ARM64 build/run |
| MSVC | supported VS toolset에서 Release/Debug |
| dispatch | unsupported forced tier가 crash 없이 거부 |
| binary | baseline ISA 누출 없음 |
| performance | 자체 intrinsics/auto-vectorization 대비 의미 있는 결과 |
| size | installer와 loaded code 증가 기록 |
| license | exact version, license texts, notice/SBOM 처리 |
| update | pinned version과 upgrade regression 절차 |

통과하지 못하면 compiler auto-vectorization + 좁은 manual intrinsics를 유지한다.

## 13. build 설정

### 13.1 target별 flags

개념적 CMake 구성:

```text
negaflow_cpu_baseline_x64     /arch:SSE2
negaflow_cpu_avx2_integer     isolated flags/intrinsics
negaflow_cpu_avx2_fma         /arch:AVX2 + explicit semantic contract
negaflow_cpu_arm64            /arch:armv8.0
```

실제 flag는 현재 MSVC/clang-cl 공식 문서를 보고 pinned toolchain에서 검증한다. `CMAKE_CXX_FLAGS` 전역에
`/arch:AVX2`를 넣지 않는다. vcpkg dependency까지 상위 ISA로 재빌드하지 않는다.

### 13.2 compiler와 LTO

- v1 기준 compiler는 MSVC이며 clang-cl은 measured need가 있을 때 추가
- compiler minor update도 codegen/dispatch regression 대상
- LTCG/LTO는 binary 검사와 physical fallback 테스트를 통과한 뒤에만 ISA target에 사용
- PGO는 workload corpus와 privacy/provenance가 고정된 뒤 별도 결정
- Debug도 모든 architecture에서 빌드·실행하며 Release만으로 ARM64를 대표하지 않음

### 13.3 source hygiene

- intrinsics include는 ISA-specific `.cpp`에 제한
- common headers는 fixed-width integer와 plain C ABI 중심
- compile definition 이름에 실제 요구 feature set을 반영
- `NDEBUG`에 따라 dispatch semantics가 바뀌지 않음
- test override가 production user-controlled environment로 남지 않음

## 14. 관측 가능성

지원 요청과 benchmark가 실제 실행 경로를 알 수 있어야 한다.

startup 또는 첫 engine 초기화 event:

```text
processArchitecture = x64 | arm64
compiler/toolset
baselineIsa
detectedFeatureMask
osUsableFeatureMask
selectedKernelTableVersion
selectionReason
overrideMode = none | internal-test
```

operation report에는 전 feature mask를 매번 복제하지 않고 다음만 둔다.

```text
cpuBackend = baseline | avx2 | mixed | neon
kernelTierSummary
workerCount
tileGeometry
fallbackReason, 있을 때
```

CPU vendor/model 문자열은 support bundle에서 꼭 필요하고 privacy review를 통과할 때만 넣는다. correctness는
vendor string이 아니라 capability와 artifact identity로 설명한다.

사용자 UI에는 “AVX2 가속” 같은 기술 배지를 기본 노출하지 않는다. 기능과 결과는 CPU에 관계없이 같아야 한다.
진단 export에서만 확인 가능하게 한다.

## 15. 테스트 전략

### 15.1 unit/contract

모든 optimized entry에 같은 typed test suite를 재사용한다.

- empty/invalid dimensions rejection
- 1×1, narrow row, odd width/height
- vector width `N-1`, `N`, `N+1`, `2N-1`, `2N`, `2N+1`
- arbitrary stride와 padded rows
- deliberately unaligned ROI offsets
- in-place/no-overlap contract
- min/max integer, signed/unsigned boundary
- `0`, `-0`, subnormal, NaN, ±Inf, out-of-range float
- alpha 0/partial/1
- cancellation boundary는 kernel 밖 scheduler contract로 검증

### 15.2 differential

같은 input을 다음 경로로 실행한다.

```text
scalar-test reference
architecture baseline
auto-selected table
각 supported forced tier
GPU/WARP equivalent가 있는 경우 해당 backend
```

E0는 exact bytes, E1은 exact decision, E2/E3는 사전 정의된 error budget으로 비교한다. 실패 시 maximum error만
보지 말고 pixel coordinate, channel, stage, tier, input classification을 남긴다.

### 15.3 randomized와 guard pages

- seeded randomized dimensions/strides/ROI
- buffer 앞뒤 guard page 또는 sanitizer-compatible red zone
- tail 직후 canary
- overflow dimensions fuzz
- alias/overlap invalid input fuzz
- repeated initialization/race test

테스트 corpus에 사용자의 실제 스캔을 무단 포함하지 않는다. 합성/허가된 fixture와 hash/provenance manifest를
쓴다.

### 15.4 physical matrix

| 환경 | Debug | Release | forced baseline | 상위 tier | 장시간 perf |
|---|---:|---:|---:|---:|---:|
| x64 Intel baseline-capable | 필수 | 필수 | 필수 | 지원 시 | 표본 |
| x64 Intel AVX2/FMA | 필수 | 필수 | 필수 | 필수 | 필수 |
| x64 AMD AVX2/FMA | 필수 | 필수 | 필수 | 필수 | 필수 |
| Windows ARM64 Qualcomm | 필수 | 필수 | NEON baseline | 선택 확장 없음 | 필수 |
| x64 VM with masked features | smoke | 필수 | 필수 | 거부 확인 | 선택 |

GitHub hosted ARM64 runner나 x64 VM의 compile/test는 중요하지만 physical Intel/AMD/Qualcomm 성능과 thermal
behavior를 대체하지 않는다. emulator에서 ARM64 build가 실행된 사실도 native 장치 성능 증거가 아니다.

### 15.5 성능 시나리오

- 작은 thumbnail/preview ROI
- 한 장의 full-resolution develop
- 55MP class scan 단일 export
- 여러 장 virtual batch
- defect removal off/on
- histogram/auto-tone on/off
- warm cache/cold cache 구분
- first-file preparation과 steady-state 분리
- power mode와 plugged/battery 상태 기록

속도를 위해 output dimensions, bit depth, JPEG/TIFF quality, ICC 적용을 낮추지 않는다.

## 16. 실패와 fallback

### 16.1 탐지 실패

capability query가 애매하면 상위 tier를 비활성화하고 baseline을 사용한다. baseline 자체가 지원 환경에서 실행되지
않으면 visible unsupported-platform 오류다. 시작 crash로 만들지 않는다.

### 16.2 optimized kernel 실패

production에서 access violation/illegal instruction을 잡아 같은 process 안에서 baseline으로 재시도하는 구조는
안전하지 않다. process state가 이미 손상됐을 수 있다.

- CI/physical lab에서 제거
- crash dump에 selected tier와 table version 기록
- 다음 안전 실행에서 support-controlled baseline mode를 사용할 수 있게 설계
- update로 offending tier를 policy에서 비활성화할 수 있는 signed configuration 가능성 검토

원격 설정으로 임의 native code나 unsigned feature policy를 주입하지 않는다.

### 16.3 numeric mismatch

optimized result가 계약을 벗어나면 해당 entry만 baseline으로 되돌린다. 전체 AVX2를 끄기 전에 kernel-level
원인을 좁힌다. 다만 decision mismatch가 catalog/export 결과에 영향을 줬다면 cache generation과 결과 artifact를
구분해 무효화한다.

## 17. 구현 순서

### 단계 0 — reference 고정

- macOS kernel 의미와 tests inventory
- Windows C++ scalar/reference
- input validation과 E0–E3 분류
- x64/ARM64 Debug/Release differential CI

완료 조건: SIMD 없이 제품 핵심 workflow가 정확하고 bounded memory로 작동.

### 단계 1 — 자동 벡터화 확인

- Release compiler optimization report
- disassembly와 ETW/WPA profile
- algorithm/memory/tile/thread 개선 우선
- kernel별 crossover 측정

완료 조건: 수동 SIMD 후보가 추측이 아니라 trace로 특정됨.

### 단계 2 — 좁은 수동 SIMD

- 가장 큰 pointwise/packing kernel 하나 선택
- x64 AVX2 계열과 ARM64 NEON 비교
- 별도 TU/function table
- differential, guard-page, binary leak test
- physical matrix

완료 조건: end-to-end 이득과 결과 계약이 둘 다 통과.

### 단계 3 — 반복 여부 판단

- 두 번째/세 번째 kernel까지 같은 boilerplate가 반복되는지 측정
- Highway spike 조건 평가
- binary size/build time/maintenance 비교

완료 조건: dependency 도입 또는 자체 좁은 dispatch 유지 결정을 ADR에 기록.

### 단계 4 — 미래 ISA

AVX-512/AVX10/SVE는 새 문서와 별도 acceptance matrix 없이 기존 tier에 슬쩍 추가하지 않는다.

## 18. 금지 목록

- 앱 전체 또는 모든 dependency에 `/arch:AVX2` 적용
- SSE4.2를 근거 없이 x64 minimum으로 지정
- Intel/AMD vendor ID만으로 kernel 선택
- CPUID만 확인하고 XGETBV/OS state를 생략
- AVX2와 FMA capability를 같은 것으로 취급
- global fast-math로 성능 확보
- threshold/histogram 결과 차이를 시각적으로 안 보인다는 이유로 허용
- 상위 ISA intrinsic/template를 baseline header에 배치
- tail에서 allocation 밖 read/write
- ARM64를 x64 emulation 실행 성공으로만 검증
- ARM64 Debug test 생략
- codec 내부 dispatch를 앱에서 중복 작성
- GPU/CUDA availability를 CPU baseline의 전제조건으로 사용
- benchmark 없이 Highway, oneTBB, IPP, OpenCV 같은 dependency 추가
- 출시 예정 CPU와 시장 점유율 추측을 지원 계약으로 사용

## 19. 완료 체크리스트

### architecture

- [ ] x64 baseline이 SSE2/default 이하로 독립 실행됨
- [ ] ARM64 native baseline이 Armv8.0/NEON으로 독립 실행됨
- [ ] ARM64EC가 본체 dependency가 아님
- [ ] scanner x64/x86 adapter는 out-of-process임

### dispatch

- [ ] feature detection과 policy selection이 분리됨
- [ ] AVX2, FMA, OS vector state가 각각 기록됨
- [ ] process당 한 번 immutable table이 게시됨
- [ ] forced unsupported tier가 crash 없이 거부됨
- [ ] entry별 active tier를 진단할 수 있음

### correctness

- [ ] 각 kernel의 E0–E3 등급이 선언됨
- [ ] scalar-test/baseline/optimized differential가 통과함
- [ ] NaN/Inf/denormal/rounding 정책이 있음
- [ ] decision-producing kernel이 exact decision을 지킴
- [ ] odd stride, unaligned ROI, tail, guard-page test가 통과함

### binary safety

- [ ] ISA별 TU/target이 분리됨
- [ ] public ABI에 target vector type이 없음
- [ ] baseline disassembly에 상위 명령이 없음
- [ ] static initializer/startup에 상위 tier 누출이 없음
- [ ] LTO/Release에서도 fallback hardware smoke가 통과함

### performance

- [ ] 최적화 전 ETW/WPA baseline이 있음
- [ ] Intel, AMD, ARM64 physical result가 있음
- [ ] small ROI와 55MP crossover를 측정함
- [ ] SIMD×worker matrix로 oversubscription/bandwidth를 확인함
- [ ] 품질·크기·bit depth·ICC를 낮추지 않고 비교함

## 20. 공식 근거

Microsoft:

- [`/arch` (x64)](https://learn.microsoft.com/en-us/cpp/build/reference/arch-x64?view=msvc-170) — x64 기본 `SSE2`, 상위 codegen 옵션
- [`/arch` (ARM64)](https://learn.microsoft.com/en-us/cpp/build/reference/arch-arm64?view=msvc-170) — 기본 `armv8.0`, Arm architecture extension 지정
- [Windows ARM64 ABI conventions](https://learn.microsoft.com/en-us/cpp/build/arm64-windows-abi-conventions?view=msvc-170) — Armv8, floating point, NEON baseline
- [`__cpuid`, `__cpuidex`](https://learn.microsoft.com/en-us/cpp/intrinsics/cpuid-cpuidex?view=msvc-170) — x86/x64 feature query intrinsics
- [`_xgetbv`](https://learn.microsoft.com/en-us/cpp/intrinsics/xgetbv?view=msvc-170) — extended control register query
- [`IsProcessorFeaturePresent`](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-isprocessorfeaturepresent) — Windows processor feature query와 SDK/OS별 ARM feature support
- [MSVC compiler intrinsics](https://learn.microsoft.com/en-us/cpp/intrinsics/compiler-intrinsics?view=msvc-170) — architecture별 intrinsic과 portability 주의
- [ARM64EC ABI](https://learn.microsoft.com/en-us/cpp/build/arm64ec-windows-abi-conventions?view=msvc-170) — ARM64EC/x64 interoperability 경계

후보 라이브러리:

- [Google Highway repository](https://github.com/google/highway) — portable SIMD, runtime dispatch, target 목록, MSVC 주의, Apache-2.0/BSD-3

프로세서 feature bit의 leaf/subleaf 의미는 구현 시점에 Microsoft 문서와 함께 Intel/AMD의 공식 architecture
manual을 pin한다. 이 문서는 특정 CPU 세대의 시장 전망이나 비공식 benchmark를 제품 지원 근거로 사용하지
않는다.
