# Negaflow Windows 네이티브 이식 설계 자료

> 상태: 구현 전 아키텍처·검증·이행 설계  
> 기준일: 2026-08-04  
> macOS 기준 커밋: 9be909c  
> 추가 관찰 범위: 위 커밋 이후 현재 워킹트리. 미커밋 상태는 확정 제품 사양과 구분한다.

이 디렉토리는 macOS용 Negaflow를 Windows에서 별도 네이티브 제품으로 구현하기 위한 설계
자료다. Windows 구현 코드는 아직 만들지 않는다. 현재 macOS 코드와 테스트를 읽어 제품 계약을
추출하고, Windows 공식 API·배포·라이선스 자료와 대조해 구현 순서와 통과 조건을 고정한다.

## 1. 최상위 제품 목표

Windows판은 다음 네 조건을 동시에 만족해야 한다.

1. WinUI 3와 Windows App SDK를 사용하는 네이티브 Windows 데스크톱 앱이다.
2. macOS판의 기능, 상태 전이, 오류·복구 경로, 키보드 흐름과 접근성 의미를 99.9% 동등하게
   옮긴다.
3. 이미지 품질·정밀도·색 관리·비파괴 저장 계약은 플랫폼에 따라 달라지지 않는다.
4. Intel·AMD·NVIDIA·Qualcomm과 x64·ARM64에서 필수 기능은 같고, 가능한 속도만 달라진다.

픽셀 단위로 macOS 외형을 복제하는 것이 목표는 아니다. Windows에서는 WinUI 3의 네이티브 창,
포커스, 입력, 접근성, 테마와 고DPI 동작을 사용하되 사용자가 같은 작업을 같은 의미로 끝낼 수
있어야 한다.

## 2. 단일 출처와 우선순위

문서가 어긋나 보이면 다음 순서로 판단한다.

1. [기술 결정 등록부](00-overview/decision-register.md)
2. [제품 불변식](99-plan/product-invariants.md)
3. [호환성 매트릭스](00-overview/compatibility-matrix.md)
4. 주제별 상세 문서
5. [열린 질문](99-plan/open-questions.md)

구현 순서와 승인 gate는 [전체 이행 로드맵](99-plan/migration-roadmap.md)이 소유한다. 오래된
메모의 특정 API·버전·커널 수가 위 문서와 충돌하면 오래된 메모를 구현 근거로 사용하지 않는다.

## 3. 현재 결정 요약

### 3.1 제품과 언어 경계

| 계층 | 기준 기술 | 소유 범위 |
|---|---|---|
| Shell | C# · .NET 10 LTS 후보 · WinUI 3 | XAML, 창, 뷰모델, 입력, 접근성, 현지화 |
| Native engine | C++20 | 현상, 측정, 결함, 이미지 I/O, 색 관리, GPU, CPU |
| CLI | C++20 | 헤드리스 수치 적합성, 파일 입출력, 진단 |
| Scanner adapters | 별도 프로세스 | WIA, TWAIN x64/x86, 선택적 SANE·벤더 SDK |

셸과 엔진의 기본 경계는 좁은 C ABI다. C#은 픽셀 루프를 소유하지 않고, C++은 XAML 상태
트리를 소유하지 않는다. SwapChainPanel 연결에만 필요한 경우 얇은 C++/WinRT 어댑터를
스파이크 뒤 허용한다.

UI process는 사용자·제품 채널별 하나를 기본으로 한다. 두 번째 launch는 새 catalog writer나 새
main window를 만들지 않고 primary process로 activation을 전달한다. Windows App SDK `AppInstance`
경로는 x64와 ARM64, unpackaged self-contained artifact에서 모두 검증한 뒤 확정하며, catalog의 실제
process lock은 instance election과 별도로 유지한다.

### 3.2 GPU 기준선

Windows v1 기준선은 다음과 같다.

~~~text
Direct3D 11
feature level 11_0
Shader Model 5.0 / FXC / DXBC
Direct2D 1.1 custom effects
동일 D3D11 장치의 DirectCompute
DXGI flip-model swap chain + SwapChainPanel
WARP conformance·복구 경로
완전한 CPU fallback
~~~

D3D12, Shader Model 6, DirectML, Work Graphs는 필수 경로가 아니다. D3D12는 D3D11 고유 병목이
실제 계측으로 확인되고 전체 파이프라인 이득이 입증될 때만 선택 tier로 검토한다.

CUDA는 완전 제외가 아니라 **NVIDIA 전용 후순위 후보**다. D3D11과 CPU 경로가 먼저 완성되고,
기능 차이 없이 end-to-end 이득과 배포·유지 비용을 함께 통과한 작업에만 붙일 수 있다. CUDA가
없어도 모든 기능과 품질이 완전해야 한다.

세부 결정은 [GPU backend 선택](12-performance/backend-selection.md)과
[GPU 벤더 범용성](12-performance/gpu-vendor-portability.md)을 따른다.

### 3.3 CPU 기준선

| 대상 | 필수 기준선 | 선택 최적화 |
|---|---|---|
| x64 Intel·AMD | MSVC x64 기본/SSE2 범위 | 커널별 AVX2, 별도 FMA gate |
| ARM64 | Armv8.0-A + NEON/Advanced SIMD | 검증된 확장만 후속 |
| 공통 | scalar/reference 의미와 완전한 기능 | 자동 벡터화, 좁은 수동 intrinsics |

Google Highway는 확정 의존성이 아니라 반복되는 다중 ISA 수동 구현이 실제 유지비가 될 때
비교할 후보이다. 먼저 메모리 이동, 타일링, 스레딩, 자동 벡터화를 최적화한다. Intel과 AMD를
제조사 문자열로 분기하지 않는다.

세부는 [CPU SIMD와 런타임 디스패치](16-cpu/simd-and-dispatch.md)를 따른다.

### 3.4 커널 수를 읽는 법

현재 ChromabaseMetalKernels.swift에는 31개의 stitchable custom color kernel이 있다.

- 단일 image 입력: 18개
- 다중 image 입력: 13개
- kernel 내부 임의 좌표·이웃 texel sampling: 0개
- blur, median, box mean 같은 공간 producer 결과가 필요한 combine: 9개

31개 kernel 자체가 현재 좌표의 입력 sample을 결합한다는 사실과 전체 파이프라인이 한 pass라는
주장은 다르다. 공간 producer, 측정, LUT branch, 리샘플링과 인코딩은 별도 graph 단계다.
Direct2D shader linking은 가능한 인접 pixel transform을 런타임이 선택적으로 합치는 최적화이며,
31개 전체의 기계적 단일-pass 변환이나 고정 dispatch 수를 보장하지 않는다.

정본은 [커널 인벤토리](02-shaders/kernel-inventory.md)와
[shader linking 설계](01-render-engine/shader-linking.md)다.

### 3.5 정밀도와 색 관리

- working intermediate는 32-bpc float를 기본으로 한다.
- 음수와 1 초과 extended-linear 값을 중간에서 자르지 않는다.
- preview와 export는 같은 현상 수학과 색 관리 경계를 사용한다.
- monitor ICC, working space, proof profile, output profile의 소유자를 분리한다.
- CPU의 LittleCMS reference와 GPU 경로를 픽셀·색차·경계 fixture로 비교한다.
- printer/paper 정확도는 실제 ICC와 출력 측정 없이 주장하지 않는다.

[정밀도와 clipping](01-render-engine/precision-and-clipping.md),
[색 관리 파이프라인](04-color-management/color-pipeline.md),
[LittleCMS 2](04-color-management/lcms2.md)가 세부 계약을 소유한다.

### 3.6 스캐너 플러그인

코어 앱은 SANE, TWAIN DSM, WIA 구현이나 벤더 SDK를 링크하지 않는다. 모든 scanner adapter는
별도 프로세스이며 versioned JSON/NDJSON 제어 메시지와 앱이 지정한 파일을 통해 통신한다.

- WIA 2.0 COM adapter: Windows 기본 후보
- TWAIN x64 adapter: 별도 프로세스
- TWAIN x86 adapter: 32비트 Data Source용 별도 프로세스
- SANE: GPL 플러그인, 별도 저장소·설치·업데이트·source 제공
- vendor SDK: 재배포권과 비트니스가 승인된 경우만

플러그인이 보고하지 않은 capability는 UI에 표시하지 않는다. USB 발견, driver 설치, device
enumeration, preview 성공, 요청 ROI 적용, IR 성공은 서로 다른 증거다.

세부는 [플러그인 아키텍처](10-scanner/plugin-architecture.md),
[프로토콜 계약](10-scanner/protocol-contract.md),
[보안·수명주기](10-scanner/plugin-security-and-lifecycle.md),
[실기 매트릭스](10-scanner/hardware-validation-matrix.md)를 따른다.

### 3.7 배포 기준선

v1 기본 후보는 architecture별 unpackaged self-contained 앱과 Direct Stable 채널이다.

- x64와 ARM64 설치물 분리
- MSI 또는 bootstrapper 기반 offline-complete 설치
- PE, DLL, plugin과 installer Authenticode 서명
- signed update metadata와 설치 프로그램 단위 update
- binary rollback과 catalog rollback 분리
- Store/MSIX는 전체 scanner·storage gate를 통과한 미래 채널

WiX Toolset는 구현상 후보일 뿐 비용·사용 조건 승인이 끝난 무료 전제로 취급하지 않는다. 현재
upstream이 수익 창출 사용에 Open Source Maintenance Fee를 명시하므로, 도입 전에 승인하거나
동등한 installer 대안을 검증해야 한다.

self-contained 배포는 runtime drift를 통제하지만 payload·시작 메모리를 늘리고 Windows App SDK
servicing을 앱이 직접 흡수해 재배포해야 한다. framework-dependent와 실제 산출물로 비교한 뒤
최종 확정한다.

[배포 채널](11-distribution/deployment-channels.md),
[서명 모델](11-distribution/msix-signing.md),
[업데이트와 롤백](11-distribution/update-and-rollback.md)을 함께 읽는다.

### 3.8 지원 OS

Windows 11 24H2 build 26100은 API·시험 후보일 수 있지만 영구적인 출시 지원 선언이 아니다.
2026-08-04 조사 기준 24H2 Home/Pro end of updates가 2026-10-13이므로 실제 구현 착수와 출시
직전에 지원 중인 소비자 Windows release를 다시 고른다.

최소 API OS, CI 기준 image, hardware lab OS, 고객 지원 OS를 별도 축으로 기록한다. Windows 10은
기술적 실행 가능성과 제품 지원을 구분하며 현재 v1 지원 범위에 자동 포함하지 않는다.

## 4. 문서 지도

| 영역 | 주요 문서 | 역할 |
|---|---|---|
| 00 개요 | [전략](00-overview/strategy.md) · [아키텍처](00-overview/architecture.md) · [호환성](00-overview/compatibility-matrix.md) · [결정 등록부](00-overview/decision-register.md) · [macOS 인벤토리](00-overview/mac-inventory.md) | 제품·경계·지원·상위 결정 |
| 01 렌더 엔진 | [파이프라인](01-render-engine/pipeline-shape.md) · [Direct2D](01-render-engine/direct2d-effects.md) · [ROI](01-render-engine/roi-and-invalidation.md) · [shader linking](01-render-engine/shader-linking.md) · [정밀도](01-render-engine/precision-and-clipping.md) | Core Image 의미를 Windows graph로 번역 |
| 02 셰이더 | [31개 커널](02-shaders/kernel-inventory.md) · [Metal→HLSL](02-shaders/metal-to-hlsl.md) | custom kernel·HLSL 계약 |
| 03 측정 | [히스토그램과 통계](03-measurement/histogram-and-statistics.md) | 자동 보정의 결정적 측정 |
| 04 색 관리 | [색 파이프라인](04-color-management/color-pipeline.md) · [LittleCMS](04-color-management/lcms2.md) | ICC·proof·display·print 경계 |
| 05 이미지 I/O | [WIC](05-image-io/wic.md) · [libtiff](05-image-io/libtiff.md) · [LibRaw](05-image-io/libraw.md) · [export](05-image-io/export-formats.md) | decode·encode·metadata·RAW |
| 06 대형 이미지 | [source·tiling](06-large-images/image-source-tiling.md) | lazy decode·tile cache·OOM |
| 07 동시성 | [멀티스레딩과 export](07-threading/multithreading-export.md) | scheduler·cancel·progress·batch |
| 08 UI | [동등성 계약](08-ui/parity-contract.md) · [셸](08-ui/shell-and-navigation.md) · [앱 수명주기](08-ui/application-lifecycle.md) · [기능 지도](08-ui/feature-map.md) · [입력](08-ui/input-and-shortcuts.md) · [접근성](08-ui/accessibility-localization.md) · [캔버스](08-ui/swapchainpanel-canvas.md) · [화면별 문서](08-ui/surfaces/) | WinUI 3 UI/UX 99.9% 동등성 |
| 09 언어·ABI | [언어 결정](09-language-choice/language-decision.md) · [C#↔C++](09-language-choice/csharp-native-interop.md) | C ABI·ownership·threading |
| 10 스캐너 | [아키텍처](10-scanner/plugin-architecture.md) · [프로토콜](10-scanner/protocol-contract.md) · [보안](10-scanner/plugin-security-and-lifecycle.md) · [WIA/TWAIN](10-scanner/twain-wia.md) · [하드웨어 매트릭스](10-scanner/hardware-validation-matrix.md) | out-of-process adapter |
| 11 배포 | [채널](11-distribution/deployment-channels.md) · [서명](11-distribution/msix-signing.md) · [업데이트](11-distribution/update-and-rollback.md) | installer·trust·rollback |
| 12 성능 | [backend](12-performance/backend-selection.md) · [GPU 범용성](12-performance/gpu-vendor-portability.md) · [GPU 최적화](12-performance/gpu-optimization.md) · [도구](12-performance/profiling-tools.md) · [CI](12-performance/ci-and-testing.md) · [실패 모드](12-performance/known-failure-modes.md) | 성능·수치·vendor matrix |
| 13 빌드·의존성 | [개발 환경](13-build-and-deps/development-environment.md) · [solution 구조](13-build-and-deps/solution-layout.md) · [CMake/vcpkg](13-build-and-deps/vcpkg-cmake.md) · [라이선스/SBOM](13-build-and-deps/third-party-licenses.md) | 재현 빌드·공급망 |
| 14 저장 | [catalog와 storage](14-persistence/catalog-and-storage.md) | 원본 불변·SQLite·cache·migration |
| 15 디지털 필름 | [가상 현상](15-digital-film/virtual-development.md) | digital-source 전용 graph |
| 16 CPU | [Accelerate 대체](16-cpu/accelerate-replacement.md) · [SIMD](16-cpu/simd-and-dispatch.md) | x64·ARM64 CPU 경로 |
| 99 계획 | [제품 불변식](99-plan/product-invariants.md) · [기준선 manifest](99-plan/baseline-manifest.md) · [스파이크](99-plan/spike-checklist.md) · [이행 로드맵](99-plan/migration-roadmap.md) · [열린 질문](99-plan/open-questions.md) · [유지보수](99-plan/maintenance.md) · [문서 감사](99-plan/documentation-audit.md) | 실행 순서·gate·장기 동등성·근거 검증 |

## 5. 권장 읽기 순서

### 제품·아키텍처를 처음 검토할 때

1. [전략](00-overview/strategy.md)
2. [기술 결정 등록부](00-overview/decision-register.md)
3. [시스템 아키텍처](00-overview/architecture.md)
4. [제품 불변식](99-plan/product-invariants.md)
5. [macOS 기준선·동등성 manifest](99-plan/baseline-manifest.md)
6. [전체 이행 로드맵](99-plan/migration-roadmap.md)

### 엔진을 구현할 때

1. [정밀도와 clipping](01-render-engine/precision-and-clipping.md)
2. [31개 커널 인벤토리](02-shaders/kernel-inventory.md)
3. [파이프라인 모양](01-render-engine/pipeline-shape.md)
4. [측정과 통계](03-measurement/histogram-and-statistics.md)
5. [색 관리](04-color-management/color-pipeline.md)
6. [대형 이미지와 타일링](06-large-images/image-source-tiling.md)

### UI를 구현할 때

1. [UI 동등성 계약](08-ui/parity-contract.md)
2. [화면 기능 지도](08-ui/feature-map.md)
3. [셸과 탐색](08-ui/shell-and-navigation.md)
4. [앱 수명주기·인스턴싱·활성화](08-ui/application-lifecycle.md)
5. [캔버스 interop](08-ui/swapchainpanel-canvas.md)
6. [입력·단축키](08-ui/input-and-shortcuts.md)
7. [접근성·현지화](08-ui/accessibility-localization.md)
8. [화면별 acceptance](08-ui/surfaces/)

### 출시 준비를 할 때

1. [서드파티 라이선스](13-build-and-deps/third-party-licenses.md)
2. [배포 채널](11-distribution/deployment-channels.md)
3. [서명 모델](11-distribution/msix-signing.md)
4. [업데이트와 롤백](11-distribution/update-and-rollback.md)
5. [CI와 테스트](12-performance/ci-and-testing.md)
6. [열린 질문](99-plan/open-questions.md)

## 6. 구현 순서

상세 순서는 [전체 이행 로드맵](99-plan/migration-roadmap.md)이 정본이다.

~~~text
M0   기준선·법무·지원 정책
M1   저장소·도구 체인·x64/ARM64
M2   scalar reference와 적합성 corpus
M3   이미지 I/O·색 관리·catalog/영속성
M4   C++ CLI vertical slice
M5   D3D11·Direct2D·WARP vertical slice
M6   전체 Develop·측정·디지털 필름 graph
M7   대형 이미지·tile scheduler·취소
M8   C ABI와 WinUI 3 shell/canvas
M9   Library·Import·catalog UX
M10  Develop UI
M11  Defects
M12  Export
M13  Print
M14  Settings·shortcuts·현지화·접근성
M15  scanner host와 독립 plugin
M16  hardware·성능·호환성 qualification
M17  설치·서명·update·rollback·compliance
M18  Beta·RC·Stable
~~~

품질 잠금 전에 GUI 화면 수를 완료 지표로 사용하지 않는다. scalar와 macOS 기준 결과,
WARP·GPU 결과, 저장 계약이 먼저 통과해야 한다.

## 7. 증거 경계

현재 문서가 가진 증거:

- macOS 저장소의 실제 Swift 코드·테스트·리소스·프로토콜 읽기
- 공식 Microsoft·upstream 문서와 라이선스 원문 조사
- macOS에서 이미 남아 있는 일부 성능·동작 근거의 설계 반영

현재 문서가 아직 가지지 못한 증거:

- Windows x64/ARM64 빌드
- D3D11·Direct2D·WARP 픽셀 결과
- 실제 Intel·AMD·NVIDIA·Qualcomm 성능
- WinUI 3 화면·키보드·Narrator 수동 QA
- WIA/TWAIN/SANE 실제 Windows scanner
- 설치·서명·update·rollback 실기
- Windows 모니터 ICC·HDR·printer 출력 측정

따라서 이 자료는 구현 가능한 설계와 검증 계획이지 Windows판 완성 증명은 아니다. 직접 실행하지
않은 항목은 [열린 질문](99-plan/open-questions.md)과 각 문서의 release gate에 남긴다.

## 8. 시간에 따라 변하는 항목

다음은 구현 시작, Beta, RC, Stable 직전에 각각 다시 확인한다.

- Windows 지원 release와 end of servicing
- Windows App SDK stable branch와 servicing 상태
- .NET LTS/patch 지원 상태
- Visual Studio·MSVC·Windows SDK
- GPU·scanner driver
- NuGet·vcpkg dependency
- signing service와 timestamp policy
- WiX를 포함한 build tool 사용 조건
- TWAIN DSM, LibRaw, ICC profile 재배포 조건

[장기 유지보수](99-plan/maintenance.md)의 baseline manifest와 delta ledger가 이 재검증을 소유한다.

## 9. Git 제외

루트 .gitignore에는 /windows_docs/가 등록되어 있다. 이 자료는 현재 공개 저장소에 추적되지 않는다.
문서를 공개하거나 별도 저장소로 옮길 때는 링크, 비공개 경로, 라이선스 메모와 기준 커밋을 다시
감사한다.
