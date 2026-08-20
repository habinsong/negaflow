# CMake와 vcpkg 의존성 정책

기준일: 2026-08-04  
상태: native build 기준 확정, 개별 third-party 채택은 스파이크·라이선스 검토 필요

## 1. 역할 분리

| 도구 | 소유 범위 |
|---|---|
| CMake | C++ engine DLL, CLI, native tests, HLSL custom commands |
| vcpkg manifest | C/C++ third-party dependency와 version baseline |
| MSBuild/dotnet | C# WinUI shell, Interop, managed tests, publish |
| NuGet | Windows App SDK와 managed packages |

Windows App SDK를 vcpkg로 설치하거나 native codec을 NuGet에 숨기지 않는다. 각 package manager가
소유하는 dependency graph를 명확히 분리한다.

## 2. manifest mode만 사용한다

필수 파일:

- `vcpkg.json`
- `vcpkg-configuration.json`
- 특정 vcpkg commit 또는 registry baseline
- `CMakePresets.json`

금지:

- `vcpkg integrate install`에만 의존
- 개발자 PC의 classic-mode package를 암묵적으로 사용
- floating registry head
- x64에서만 restore하고 ARM64는 나중에 시도
- CI cache를 dependency lock으로 오인

`CMAKE_TOOLCHAIN_FILE`은 첫 `project()` 평가 전에 정해져야 한다. preset이 이를 소유하고 개발자가
매번 긴 command를 재입력하지 않게 한다.

## 3. 최소 dependency 후보

### v1 우선 평가

| dependency | 용도 | 상태 | 확인할 것 |
|---|---|---|---|
| `lcms` | LittleCMS 2 ICC transform, proof/output profile | 기준 후보 | x64/ARM64, float format, `THR` context/cache, core MIT; GPL optional features 금지 |
| `tiff` | TIFF/BigTIFF decode/encode | 강한 후보 | tiles/strips, 16-bit, ICC/EXIF, compression, x64/ARM64 |
| `sqlite3` | catalog·transaction persistence | 강한 후보 | serialized access, WAL/recovery, public-domain status |
| test framework 하나 | native unit/conformance | 필요 | GoogleTest 또는 Catch2 중 하나만 선택 |

### 측정 후 후보

| dependency | 언제 검토 | 기본 경로 |
|---|---|---|
| `libjpeg-turbo` | WIC JPEG batch throughput·metadata contract가 부족할 때 | WIC |
| `libpng` | WIC PNG 16-bit/ICC 계약이 부족할 때 | WIC |
| `libdeflate` | TIFF Deflate가 실제 export 병목일 때 | libtiff 기본 codec |
| `highway` | scalar/autovec 뒤 hot loop의 x64/ARM64 dispatch가 필요할 때 | compiler + 좁은 intrinsics |
| `libraw` | 카메라 RAW를 제품 범위로 승인할 때 | v1에서는 import format 제한 가능 |
| JSON parser | scanner protocol/parser corpus가 표준 대안보다 필요할 때 | 작은 audited parser 후보 비교 |

“빠를 것 같다”는 이유로 후보를 미리 manifest에 넣지 않는다. dependency를 추가하면 binary,
보안 패치, ARM64, 라이선스, symbol, installer와 fuzzing surface가 늘어난다.

### OS 제공 API

vcpkg dependency가 아니다.

- Direct3D 11, DXGI, Direct2D, DirectWrite
- Windows Imaging Component
- Windows Color System API — display profile 연결과 Advanced Color 상태에 사용하되 핵심 CPU ICC 구현은 LittleCMS 2
- Windows printing APIs
- Win32 process, file, synchronization, ETW
- Windows App SDK/WinUI 3 — NuGet

## 4. 의도적으로 넣지 않는 대형 의존성

| 항목 | 이유 |
|---|---|
| OpenCV 전체 | image graph·UI·codec 중복, 큰 dependency surface |
| OpenColorIO | 영화/VFX config 중심. Negaflow ICC 제품 계약과 범위가 다름 |
| Qt/Skia/Avalonia | WinUI 3 네이티브 목표와 충돌 |
| DirectML/ONNX Runtime | 현재 파이프라인은 ML inference가 아님 |
| CUDA toolkit 기본 설치 | NVIDIA 전용 후보가 core build를 지배하면 안 됨 |
| 전체 Boost | 단일 유틸리티를 위해 광범위한 dependency 금지 |
| runtime HLSL compiler | 재현성·보안·배포 surface 증가 |

필요한 작은 구성 요소가 생기면 표 전체를 뒤집지 않고 operation별로 다시 검토한다.

## 5. architecture와 triplet

필수 native target:

```text
x64-windows
arm64-windows
```

32-bit는 scanner plugin 별도 저장소/빌드에서만:

```text
x86-windows
```

third-party linkage 후보:

- permissive/license-cleared library는 `static-md`로 DLL 수를 줄이는 방안을 평가
- CRT는 제품 배포 정책과 맞추고 module마다 `/MT`와 `/MD`를 섞지 않음
- CDDL/LGPL 등 조건이 있는 library는 static/dynamic 형태를 법률·배포 검토 없이 결정하지 않음
- debug와 release CRT/dependency를 혼합하지 않음

x64가 성공했다는 이유로 ARM64 port가 존재한다고 말하지 않는다. 모든 직접·전이 dependency가
ARM64로 restore/build/link/run되어야 한다.

## 6. manifest 예시의 성격

아래는 실제 버전을 확정하는 production manifest가 아니라 구조 예시다.

```json
{
  "name": "negaflow-native",
  "version-string": "0.0.0",
  "builtin-baseline": "<verified-vcpkg-commit>",
  "dependencies": [
    {
      "name": "lcms",
      "default-features": false
    },
    "tiff",
    "sqlite3"
  ]
}
```

실제 파일에서는 placeholder를 쓰지 않는다. baseline SHA와 필요한 feature를 검증 후 정확히
기록한다. `overrides`는 이유·upstream issue·제거 조건이 있는 경우만 사용한다. 현재 `lcms` port의
`fastfloat`와 `threaded` feature는 GPL-3.0-or-later로 선언돼 있으므로 제품 manifest에서 켜지
않는다. CMake 소비 target은 현재 port usage 기준 `lcms2::lcms2`다.

## 7. CMake target 구조

권장 원칙:

- directory global include/link option 최소화
- 모든 library가 `target_*` API로 dependency를 선언
- public C ABI header 외에는 install/export 금지
- warning, sanitizer, optimization을 interface target으로 좁게 적용
- generated shader와 asset manifest를 명시적 target dependency로 연결
- test executable은 production DLL의 private object를 임의 복제하지 않음

개념적 target:

```text
negaflow_core
negaflow_imageio
negaflow_color
negaflow_develop
negaflow_measurement
negaflow_defects
negaflow_render_cpu
negaflow_render_d3d11
negaflow_export
negaflow_native          # shared DLL, C ABI
negaflow_cli
negaflow_native_tests
negaflow_conformance_tests
```

파일 하나마다 library를 만들지 않는다. 위 경계는 책임·테스트·의존성이 실제로 다를 때만 유지한다.

## 8. compiler 기준

### 필수 설정

- C++20
- 표준 준수 mode
- source encoding UTF-8
- warnings high, 새 코드의 warning 0
- signed/unsigned, narrowing, conversion 위험을 좁은 정책으로 검사
- exception/RTTI는 module별 필요성을 결정하되 C ABI 밖으로 절대 전파하지 않음
- release symbols 생성
- deterministic/reproducible build 옵션 검토
- control-flow/security compiler/linker 옵션을 release에서 유지

### 부동소수

- 전역 fast-math 금지
- scalar truth와 GPU contract를 먼저 고정
- FMA/reciprocal approximation은 operation별 골든 승인
- x64와 ARM64가 다른 기본 compiler transform을 만드는지 보고
- NaN/Inf/denormal 정책을 stage tests로 확인

### CPU ISA

- base DLL이 AVX2 instruction을 startup/static initializer에 포함하지 않음
- AVX2/FMA translation unit 또는 Highway target을 runtime dispatch 뒤 호출
- ARM64는 NEON을 기본 architecture 기능으로 활용하되 scalar truth 유지
- AVX-512/SVE2는 별도 후보이고 필수 binary 계약이 아님

## 9. HLSL 빌드

v1 기준은 FXC가 만드는 SM5 DXBC다.

```text
shaders/d2d/*.hlsl      → ps_5_0/필요 profile → embedded 또는 signed asset blob
shaders/compute/*.hlsl  → cs_5_0              → asset blob
```

규칙:

- runtime compile 금지
- Debug/Release flags를 manifest에 기록
- warnings를 오류로 처리
- entry point와 target profile 명시
- 모든 include를 build dependency로 명시
- source hash, compiler version, flags, blob hash 기록
- shader ID와 constant-buffer layout test
- C++과 HLSL 공유 struct는 size/offset을 generated assertion으로 검증
- WARP에서 모든 production blob을 load/execute

FXC가 Make/Ninja depfile을 자동으로 제공한다고 가정하지 않는다. include 목록을 manifest/compiler
wrapper가 명시적으로 수집하거나 build generator에 직접 열거한다. `.hlsli` 변경이 incremental
build에서 누락되는지 전용 테스트를 둔다.

DXC는 D3D12/SM6 선택 backend가 승인될 때 그 backend의 별도 shader tree에 추가한다. D2D용
DXBC와 SM6 DXIL을 같은 파일·매크로 조합으로 억지로 공용화하지 않는다.

## 10. binary cache와 offline build

vcpkg binary cache는 속도 도구이며 신뢰의 근거가 아니다.

- cache key에 vcpkg baseline, triplet, compiler, options, port patches 포함
- cache miss에서도 인터넷 허용 범위와 source hash 검증
- release CI는 clean restore를 정기적으로 수행
- 내부 cache가 손상되면 재생성 가능
- build artifact와 source archive provenance 보관
- dependency source URL이 사라져도 라이선스가 허용하는 보존 전략 마련

air-gapped release가 요구되면 승인된 source mirror와 NuGet/vcpkg feed를 만들고 checksum·license를
동시에 보관한다.

## 11. 공급망·라이선스

각 직접·전이 dependency는 다음 manifest를 가진다.

```text
name / version / source URL / source commit
license expression + 실제 license files
linkage form
modified patches
runtime files
copyright notices
known CVEs / review date
x64 and ARM64 artifact hashes
```

원칙:

- GPL code를 앱 본체에 링크하지 않음
- SANE는 별도 프로세스·별도 배포 경계 유지
- LittleCMS core MIT만 사용하고 vcpkg `lcms[fastfloat]`, `lcms[threaded]`는 법률·제품 결정 없이 사용하지 않음
- 라이선스 선택지가 있는 library는 실제 선택과 build flags를 기록
- “MIT로 알고 있음” 대신 release source와 license file 확인
- vcpkg port metadata만 법률 근거로 삼지 않음
- NOTICE/SBOM을 installer payload와 릴리스 artifact에 포함
- dependency update가 license를 바꿨는지 자동 diff

LibRaw는 제품 RAW 지원 범위와 실제 선택 라이선스, 링크 방식, source 제공 의무를 별도 법률
검토한 뒤에만 채택한다. 과거 버전을 고정하는 것만으로 향후 유지보수 문제가 사라지지 않는다.
2026-08-04 기준 upstream은 0.22.2이고 현재 vcpkg port는 0.22.1이므로, release 후보에서는
공식 0.22.2 source/hash 기반 overlay 또는 vcpkg port 갱신을 기다린다. 초기 build는 OpenMP를
끄고 `libraw::raw_r` target을 사용한다. 자세한 품질·라이선스 gate는
[../05-image-io/libraw.md](../05-image-io/libraw.md)를 따른다.

## 12. JSON dependency 판단

scanner plugin은 외부 입력을 파싱하므로 편의보다 검증성이 중요하다.

평가 기준:

- UTF-8 strictness와 duplicate key 정책
- integer/float overflow
- 최대 nesting·message size 제한
- SAX/DOM memory upper bound
- x64/ARM64 MSVC 지원
- fuzz corpus와 보안 이력
- canonical output 필요 여부
- MIT/BSD 등 배포 가능한 라이선스

wire schema validation을 parser library에 맡기지 않는다. parse 뒤 protocol version, required keys,
unknown-field policy, bounds와 state machine을 별도로 검사한다.

## 13. update 절차

dependency 하나씩 갱신한다.

1. upstream release/security/license 확인
2. vcpkg baseline 또는 override 변경
3. x64 Debug/Release, ARM64 Release restore/build
4. native unit/fuzz/conformance
5. WARP와 hardware smoke
6. TIFF/ICC/catalog round trip fixture
7. binary size, startup, throughput, memory 비교
8. SBOM/NOTICE/license diff
9. installer clean/upgrade test

여러 codec·compiler·Windows App SDK를 한 변경에 묶으면 회귀 원인을 잃는다.

## 14. 첫 스파이크 체크리스트

- [ ] pinned vcpkg가 offline cache 없이 x64 restore/build
- [ ] 같은 baseline이 ARM64 restore/build
- [ ] `lcms`, `tiff`, `sqlite3` minimal smoke가 실제 ARM64에서 실행
- [ ] shipping dependency tree에 LittleCMS GPL `fastfloat`/`threaded` plugin이 없음
- [ ] Debug/Release DLL runtime 혼합이 없음
- [ ] native DLL의 export symbol allowlist 통과
- [ ] FXC include 변경 시 모든 관련 blob 재빌드
- [ ] WARP가 모든 shader blob load/execute
- [ ] dependency license/SBOM 생성
- [ ] clean machine에서 staged payload만으로 CLI 실행
- [ ] WinUI publish가 오래된 native DLL을 수집하지 않음

## 공식 근거

- [vcpkg manifest mode](https://learn.microsoft.com/en-us/vcpkg/consume/manifest-mode)
- [vcpkg CMake integration](https://learn.microsoft.com/en-us/vcpkg/users/buildsystems/cmake-integration)
- [vcpkg versioning](https://learn.microsoft.com/en-us/vcpkg/users/versioning)
- [CMake presets](https://cmake.org/cmake/help/latest/manual/cmake-presets.7.html)
- [Use FXC to compile shaders](https://learn.microsoft.com/en-us/windows/win32/direct3dtools/dx-graphics-tools-fxc-using)
- [Microsoft C++ compiler options](https://learn.microsoft.com/en-us/cpp/build/reference/compiler-options)
