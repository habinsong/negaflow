# Windows판 기술 결정 등록부

기준일: 2026-08-04  
macOS 기준 커밋: 9be909c  
추가 관찰 범위: 위 커밋 뒤의 현재 워킹트리. 워킹트리에 있는 미커밋 변경은 확정 사양과 구분한다.

이 문서는 Windows판 구현자가 이미 끝난 논의를 다시 시작하지 않도록 현재 결론, 아직 스파이크가
필요한 후보, 명시적으로 제외한 선택지를 한곳에 모은다. 세부 문서와 충돌하면 이 문서의
상태와 갱신일을 먼저 확인한다.

## 상태 표기

| 상태 | 의미 |
|---|---|
| 결정 | 구현 기준으로 사용한다. 바꾸려면 근거와 동등성 영향 분석이 필요하다 |
| 조건부 결정 | 기본안이지만 첫 스파이크의 실패 조건을 만족하면 정해 둔 대안으로 전환한다 |
| 후보 | 측정·실기 검증 전에는 프로덕션 설계에 넣지 않는다 |
| 제외 | 현재 범위에서 사용하지 않는다 |

## D-001 — 제품은 별도 Windows 네이티브 구현이다

상태: 결정

- UI는 WinUI 3와 Windows App SDK의 네이티브 데스크톱 앱으로 다시 작성한다.
- macOS Swift·SwiftUI·Core Image 코드를 공유하기 위한 크로스플랫폼 추상 계층을 만들지 않는다.
- 공유하는 것은 소스 코드가 아니라 파이프라인 순서, 수치 계약, JSON 데이터 자산, 파일 포맷,
  테스트 벡터, 사용자 흐름이다.
- UI/UX 목표는 기능 이름만 같은 수준이 아니라 현재 macOS판의 상태 전이, 비활성 조건,
  오류·복구 경로, 키보드 흐름, 접근성 의미까지 99.9% 동등하게 만드는 것이다.

근거:

- 현재 GUI는 Sources/negaflowApp에 517개 Swift 파일, 75,913줄이다.
- 엔진은 Sources/Chromabase에 147개 Swift 파일, 27,107줄이다.
- 플랫폼별 네이티브 그래픽 API의 성능 모델이 달라 공용 픽셀 추상화는 양쪽의 장점을 잃는다.

## D-002 — 셸은 C#, 엔진은 C++20이다

상태: 결정

구성:

| 계층 | 언어 | 소유 범위 |
|---|---|---|
| Negaflow.Shell | C# / .NET 10 LTS / WinUI 3 | XAML, 뷰모델, 창, 메뉴, 접근성, 현지화, 사용자 상태 |
| Negaflow.Native | C++20 | 색·톤, 결함, 통계, 이미지 IO, 색 관리, GPU, CPU SIMD |
| Negaflow.Cli | C++20 | 헤드리스 수치 검증, 파일 in/out, 진단 |
| Scanner plugins | 구현별 별도 프로세스 | TWAIN, WIA, SANE 등 스캐너 통합 |

C#은 픽셀 루프를 소유하지 않는다. C++은 XAML 상태 트리를 소유하지 않는다.

## D-003 — 셸과 엔진의 기본 ABI는 좁은 C ABI다

상태: 조건부 결정

기본안:

- 네이티브 DLL은 opaque handle, 고정폭 POD, UTF-8, 명시적 버퍼 길이를 쓰는 C ABI를 노출한다.
- C#은 source-generated LibraryImport로 호출한다.
- 픽셀 버퍼, 텍스처 배열, 프레임별 대형 컬렉션은 ABI를 건너지 않는다.
- 렌더 요청은 request ID와 immutable parameter snapshot으로 보낸다.
- 완료·진행률·오류는 bounded event queue로 회수한다.

이 방식을 우선하는 이유:

- C++/WinRT 컴포넌트를 C#에서 소비하려면 winmd와 C#/WinRT projection assembly 관리가 추가된다.
- unpackaged 배포에서 custom WinRT activation과 등록은 패키지 배포보다 까다롭다.
- C ABI는 CLI, 단위 테스트, x64/ARM64 패키징에서 같은 DLL 표면을 쓴다.
- ABI가 작으면 엔진 내부 C++ 타입과 DirectX 객체를 자유롭게 바꿀 수 있다.

예외:

- SwapChainPanel 연결을 C ABI만으로 안정적으로 구현할 수 없는 경우, 패널 연결만 담당하는
  얇은 C++/WinRT 어댑터를 추가할 수 있다.
- 이 예외는 캔버스 스파이크에서 x64와 ARM64, packaged와 unpackaged 배포를 모두 확인한 뒤에만
  채택한다.

세부: ../09-language-choice/csharp-native-interop.md

## D-004 — 지원 CPU 아키텍처는 x64와 순수 ARM64다

상태: 결정

- x64 하나로 Intel과 AMD CPU를 지원한다.
- ARM64는 에뮬레이션 보조 대상이 아니라 첫 CLI부터 빌드·테스트하는 1급 대상이다.
- ARM64EC는 사용하지 않는다. in-process x64 의존성을 허용하지 않기 때문이다.
- x86 본체는 만들지 않는다. 32비트 스캐너 드라이버는 별도 x86 플러그인 프로세스가 담당한다.

중요한 한계:

- Windows on Arm의 x86/x64 앱 에뮬레이션은 사용자 모드 프로그램을 도울 뿐이다.
- 스캐너가 필요한 커널 모드 드라이버는 ARM64 호환 드라이버가 있어야 한다.
- 따라서 x86 TWAIN 플러그인이 실행된다는 사실만으로 ARM64 장치에서 실제 스캔이 된다고
  주장하면 안 된다.

## D-005 — Windows v1의 GPU 기준선은 D3D11 + Direct2D다

상태: 조건부 결정

기준선:

| 항목 | 결정 |
|---|---|
| 장치 | Direct3D 11 |
| 최소 feature level | 11_0 |
| 픽셀·컴퓨트 셰이더 | Shader Model 5.0 |
| 효과 그래프 | Direct2D 1.1+ custom effects |
| 컴퓨트 | 같은 D3D11 장치의 DirectCompute |
| 프레젠테이션 | DXGI flip-model swap chain + SwapChainPanel |
| 소프트웨어 폴백·CI | WARP |

이 결정을 택한 이유:

1. Direct2D와 DirectCompute가 같은 D3D11 장치와 DXGI 리소스를 사용한다.
2. D3D12와 D2D를 잇기 위한 D3D11On12 wrapped-resource 경계가 없다.
3. FL 11_0은 FL 12_0보다 넓은 하드웨어를 포괄하면서 typed UAV, atomics, 32KB group shared,
   1,024-thread group을 제공한다.
4. 현재 파이프라인은 레이트레이싱·mesh shader·work graph가 아니라 이미지 필터와 리덕션이다.
5. 대형 이미지 처리의 병목은 대개 명령 제출보다 메모리 대역폭과 디코드·인코드다.

필수 벤더:

- Intel 내장·Arc
- AMD Radeon
- NVIDIA GeForce/RTX
- Qualcomm Adreno 계열 Windows ARM64
- Microsoft WARP

기존 문서의 D3D12 FL 12_0 + SM 6.0 필수안은 이 결정으로 대체한다. FL 12_0을 요구하면
“범용성 우선”과 충돌하고, D2D와 D3D12 사이의 11on12 동기화·복구 표면이 생긴다.

전환 조건:

- D3D11 기준 구현이 대표 하드웨어에서 성능 예산을 지속적으로 넘고,
- PIX/ETW 계측이 원인을 D3D11 명령 제출 또는 D3D11 고유 제약으로 특정하며,
- D3D12 스파이크가 11on12 비용을 포함하고도 유의미한 순이득을 보일 때만
  D3D12를 별도 tier로 추가한다.

세부: ../12-performance/backend-selection.md

## D-006 — GPU 결과는 벤더와 무관하고 속도만 달라야 한다

상태: 결정

- 기능을 CUDA, vendor extension, 특정 wave width에 게이팅하지 않는다.
- 프리뷰와 내보내기는 같은 수학·파라미터·색관리 경계를 사용한다.
- 측정값이 자동 톤 파라미터를 만든다면, 측정 순서와 정밀도를 결정적으로 고정한다.
- GPU 통계가 벤더 허용 오차를 넘으면 측정만 CPU 결정적 구현으로 내린다.
- 장치 제거, 드라이버 리셋, 메모리 부족 시 사용자 recipe를 유지하고 파생 픽셀만 재생성한다.

## D-007 — CUDA는 v1 우선순위가 아니다

상태: 후보

CUDA를 고려할 수 있는 범위:

- NVIDIA에서만 실행되는 선택적 가속 tier
- 기준 D3D11/CPU 경로와 기능·출력 계약이 완전히 같은 격리된 커널
- 대형 배치에서 인터롭·동기화·배포 비용을 포함해 순이득이 측정된 경우

CUDA를 쓰지 않는 기본 이유:

- Intel·AMD·Qualcomm에서는 사용할 수 없다.
- 셰이더와 테스트 백엔드가 하나 더 생긴다.
- D3D11/CUDA 공유 리소스와 동기화 비용이 발생한다.
- 사진 품질 회귀를 백엔드마다 따로 막아야 한다.

재검토 게이트:

1. 실제 Negaflow 이미지·배치에서 병목이 확인된다.
2. D3D11 최적화와 CPU 경로가 먼저 끝난다.
3. NVIDIA에서 end-to-end 20% 이상 또는 사용자가 체감할 명확한 절대 시간 단축을 보인다.
4. 골든 수치와 메타데이터 산출물이 기준 경로와 같은 허용 오차를 만족한다.
5. CUDA가 없어도 모든 기능이 완전하다.

## D-008 — CPU는 scalar 정답 구현을 먼저 고정하고, 핫 루프만 SIMD화한다

상태: 결정

- 모든 CPU 커널은 scalar 기준 구현과 골든 테스트를 가진다.
- 컴파일러 자동 벡터화를 먼저 확인한다.
- 수치 프로파일링에서 상위 hot loop로 확인된 연속 배열 연산만 Highway 후보로 올린다.
- x64는 안전한 기본 ISA와 AVX2/FMA 런타임 경로를 분리한다.
- ARM64는 NEON 경로를 제공한다.
- AVX-512와 SVE2는 opt-in 후보이며 필수 경로가 아니다.
- morphology deque처럼 데이터 의존 분기가 큰 알고리즘은 SIMD보다 라인·타일 병렬을 먼저 잰다.

Highway는 확정 전제라기보다 hot-loop 구현 후보다. 외부 의존성 없이 같은 성능을 얻는 커널에는
추가하지 않는다.

## D-009 — 원본은 절대 덮어쓰지 않는다

상태: 결정

- ScanFrame.rawScanURL이 가리키는 원본과 가져온 제3자 XMP는 불변이다.
- 결함 recipe, 현상 파라미터, sidecar, cleaned-raw cache, thumbnail은 앱 소유 저장소에 둔다.
- 원본 URL 변경은 명시적 재연결 또는 persistent bookmark 복구의 Windows 등가 흐름만 허용한다.
- 종료 시 원본에 결함 편집을 굽는 경로를 Windows로 옮기지 않는다.
- 필요한 비파괴 결과를 재구성할 수 없으면 export가 명시적으로 실패해야 한다.

현재 macOS 소스에는 종료 시 스캐너 원본을 replaceItemAt으로 교체할 수 있는 경로가 남아 있다.
이는 저장소 운영 규칙의 원본 불변성과 충돌한다. Windows 사양은 더 위험한 현재 구현을 복제하지
않고 명시된 제품 불변식을 따른다.

## D-010 — 스캐너는 항상 별도 프로세스 플러그인이다

상태: 결정

- 본체는 TWAIN, WIA, SANE 또는 벤더 SDK를 링크하지 않는다.
- 플러그인은 별도 저장소·별도 빌드·별도 배포물로 유지할 수 있다.
- 본체와 플러그인은 버전된 JSON/NDJSON 제어 계약과 앱이 지정한 파일 경로로 통신한다.
- 32비트 플러그인은 x64/ARM64 본체와 별도 프로세스로 공존한다.
- capability가 보고하지 않은 기능을 UI에 만들지 않는다.
- 플러그인 없이도 import → develop → export 제품이 완전해야 한다.

라이선스 분리는 설계 의도이며 법률 결론이 아니다. 상업 배포 전 실제 배포물과 통신 구조를
기준으로 별도 검토한다.

## D-011 — 배포 기본안은 아키텍처별 unpackaged self-contained 설치다

상태: 조건부 결정

기본안:

- x64와 ARM64를 별도 산출물로 만든다.
- MSI와 필요 시 bootstrapper로 앱, VC runtime, 필요한 런타임을 설치한다.
- WiX Toolset는 현재 구현 후보이지만, 실제 사용할 major/version의 상업 사용 조건과
  Open Source Maintenance Fee를 승인하기 전에는 필수 도구로 확정하지 않는다.
- Windows App SDK와 .NET은 self-contained로 묶어 런타임 버전 드리프트를 통제한다.
- 본체와 모든 DLL·EXE·installer를 Authenticode 서명한다.
- 플러그인은 사용자별 앱 소유 디렉토리에 별도 설치한다.

이유:

- 외부 프로세스 플러그인, 임의 사용자 파일, 대형 cache, 문제 해결 도구를 Win32 방식으로
  다루기 쉽다.
- shared Windows App SDK servicing 회귀를 앱 릴리스가 통제할 수 있다.
- Store와 MSIX의 제약을 v1의 스캐너 기능에 끌어들이지 않는다.

대가:

- self-contained는 architecture별 payload와 설치 디스크를 늘린다.
- unpackaged self-contained는 shared runtime code page를 쓰지 않아 시작 시간과 메모리가 더 들 수 있다.
- Windows App SDK servicing update는 자동 적용되지 않는다. 앱이 새 runtime을 통합해 다시
  빌드·서명·배포해야 한다.
- 따라서 runtime 고정은 유지보수 책임의 제거가 아니라 Negaflow release pipeline으로의 이전이다.

후속:

- package identity가 필요한 기능이 생기면 packaged-with-external-location을 스파이크한다.
- Store판은 스캐너 플러그인 없는 별도 채널로만 검토한다.
- self-contained의 크기·시작 메모리 비용은 릴리스 스파이크에서 framework-dependent와 비교한다.
- WiX 조건을 승인하지 않으면 MSI upgrade·repair·rollback, bootstrapper, ARM64, signing,
  deterministic build와 enterprise silent deployment가 동등한 installer 대안을 선택한다.

## D-012 — 최소 API OS·시험 OS·지원 OS를 분리한다

상태: 조건부 결정

- 빌드 기준 SDK는 당시 최신 안정 Windows SDK를 사용한다.
- Windows 11 24H2, build 26100은 현재 API·시험 후보이지 영구적인 고객 지원 선언이 아니다.
- TargetPlatformMinVersion, CI baseline image, hardware-lab tested versions, 신규 설치 지원 OS와
  기존 설치 grace period를 별도 축으로 기록한다.
- Windows App SDK가 Windows 10 1809까지 기술적으로 역호환된다는 사실과, Microsoft가
  현재 지원 중인 Windows에서만 지원을 제공한다는 사실을 구분한다.

Windows 10 지원은 무료가 아니다. 별도 설치·색관리·드라이버·하이브리드 GPU·테스트 매트릭스를
추가한다. 실제 사용자 요구가 확인되기 전에는 v1 범위에 넣지 않는다.

2026-08-04 공식 release information 기준:

- Windows 11 24H2 Home/Pro는 2026-10-13 end of updates다.
- 24H2 Enterprise/Education은 2027-10-12까지다.
- 25H2 Home/Pro는 2027-10-12까지다.
- 26H1은 2026년 신형 장치용이며 기존 24H2/25H2 장치의 일반 in-place update로 설계되지 않았다.

따라서 24H2를 API 하한 후보로 유지할 수는 있어도, 첫 Stable 시점에 지원이 끝난 Home/Pro release를
신규 사용자 기본 지원선으로 고정하지 않는다. Beta, RC, Stable 직전에 공식 수명과 실제 driver/API
matrix를 다시 확인한다.

이 결정은 제품 시장 범위에 영향을 주므로 공개 Windows 계획과 출시 시점이 정해질 때 최종 승인한다.

## D-013 — 품질 잠금 전에는 GUI 완성을 성공으로 보지 않는다

상태: 결정

순서:

1. C++ CLI와 scalar 기준 구현
2. macOS 고정 기준선과 수치 conformance
3. D3D11/WARP 결과 동등성
4. WinUI 3 셸과 캔버스
5. Library/Develop/Defects/Export/Print의 행동 동등성
6. 스캐너 플러그인
7. 배포·서명·업데이트

“화면이 뜬다”와 “같은 제품이다”를 분리한다.

## D-014 — macOS 기준선은 움직이는 main이 아니라 manifest로 고정한다

상태: 결정

Windows의 각 마일스톤은 다음을 기록한다:

- macOS commit SHA
- 데이터 자산 hash
- 테스트 벡터 schema version
- 각 파이프라인 단계와 기본값
- 지원 UI surface 목록
- 의도적으로 미이관한 delta

기준선 이후 macOS 변경은 자동으로 Windows 요구가 되지 않는다. delta triage를 거쳐 양쪽의
제품 사양에 반영한다.

generated source/resource 사실과 curated surface/state 의미, stable ID, known delta와 evidence를
어떻게 분리·hash·비교하는지는 [기준선 manifest 명세](../99-plan/baseline-manifest.md)를 따른다.

## D-015 — 서드파티 승인 단위는 실제 배포 artifact다

상태: 결정

- repository의 license 배지나 package metadata만으로 배포 승인을 끝내지 않는다.
- core app, x64·ARM64 installer, 각 scanner plugin, source bundle에 별도 SBOM·notice·provenance를
  만든다.
- LittleCMS core는 MIT 후보지만 GPL-3.0-or-later인 fastfloat/threaded plugin은 코어 배포에서 제외한다.
- SANE는 GPL-2.0-or-later 별도 process·repository·installer·update·source distribution을 유지한다.
- LibRaw는 LGPL-2.1 또는 CDDL-1.0 중 실제 선택 license, linkage, 수정, source 제공을 승인한 뒤
  포함한다.
- TWAIN DSM은 정확한 release, app-local/system 배치와 LGPL 의무를 승인한 뒤 plugin payload에 넣는다.
- WiX는 source license와 별도로 현재 upstream의 OSMF 운영 조건을 확인하고 승인한다.
- Adobe RGB를 포함한 ICC, preset, profile, corpus와 icon/font도 재배포권·provenance를 기록한다.
- 프로세스 분리, dynamic link 또는 build-only 분류는 자동적인 법률 결론이 아니다.

세부: [서드파티 라이선스·SBOM](../13-build-and-deps/third-party-licenses.md)

## D-016 — 지원과 유지보수는 하나의 앱 버전으로 축약하지 않는다

상태: 결정

다음을 독립적으로 version하고 baseline manifest에 기록한다.

- product/spec version
- macOS와 Windows exact source commit
- catalog·sidecar·recipe·algorithm schema
- native ABI와 scanner protocol
- preset/profile/localization asset bundle
- shader source·compiler·bytecode manifest
- toolchain·dependency lock
- Windows App SDK·.NET·OS servicing state
- conformance corpus와 hardware matrix
- installer·update feed·signing policy

self-contained runtime, OS, GPU driver, scanner driver와 signing service는 서로 다른 수명으로 변한다.
한 축의 최신화가 다른 축의 수치·데이터 호환성을 자동 증명하지 않는다.

세부: [장기 유지보수와 동등성 운영](../99-plan/maintenance.md)

## D-017 — 사용자·제품 채널별 primary UI process는 하나다

상태: 조건부 결정

- Windows App SDK WinUI 앱의 기본 multi-instance 동작을 그대로 쓰지 않는다.
- 같은 Windows user, product channel과 install identity 안에는 primary UI process 하나만 둔다.
- 두 번째 launch는 catalog·engine·window를 만들기 전에 기존 primary로 activation을 전달한다.
- Stable, Beta, Internal은 서로 다른 instance key와 app-data root를 사용한다.
- single-instance election과 별개로 실제 library identity의 process lock을 계속 사용한다.
- main window close는 전체 app 종료를 요청하고 Settings/About/Help close는 해당 창만 닫는다.
- tray resident와 login startup은 v1 범위가 아니다.

기본 mechanism은 Windows App SDK `AppInstance.FindOrRegisterForKey`와
`RedirectActivationToAsync`다. 공식 migration 문서의 현재 예제가 x64 target을 명시하므로 x64와
ARM64, unpackaged self-contained artifact에서 모두 통과해야 확정한다. ARM64 또는 deployment
조합에서 실패하면 product semantics를 multi-instance로 낮추지 않고 user-scoped election과
authenticated local activation channel 대안을 검증한다.

정상 close의 catalog read-back 실패를 app 종료 취소로 처리할지는 현재 macOS delegate 동작과 데이터
안전 목표가 어긋나므로 Q-025에서 별도로 결정한다.

세부: [애플리케이션 수명주기·인스턴싱·활성화](../08-ui/application-lifecycle.md)

## 명시적 제외 목록

| 항목 | 상태 | 이유 |
|---|---|---|
| 크로스플랫폼 UI 프레임워크 | 제외 | WinUI 3 네이티브 목표와 충돌 |
| 본체 내 SANE/TWAIN 링크 | 제외 | 라이선스·비트니스·드라이버 격리 경계 훼손 |
| D3D12 FL 12_0 필수 | 제외 | 범용성 감소와 11on12 복잡도 |
| NVIDIA 전용 기능 | 제외 | 기능 동등성 위반 |
| ARM64EC 본체 | 제외 | in-process x64 의존성 없음 |
| x86 본체 | 제외 | 메모리 한계와 유지비. x86은 플러그인만 |
| OpenCV 전체 도입 | 제외 | 범위·의존성·중복 기능 과다 |
| DirectML로 일반 이미지 필터 구현 | 제외 | 비-ML 파이프라인에 부적합 |
| 런타임 HLSL 컴파일 | 제외 | 드라이버·보안·재현성 변동 |
| 원본 in-place bake | 제외 | 원본 불변성 위반 |

## 아직 반드시 스파이크할 항목

1. C# → C ABI로 SwapChainPanel native interface를 안전하게 전달할 수 있는가
2. D2D custom effect pixel chain의 실제 shader-linking과 FP32 중간 정밀도
3. D3D11 compute와 D2D 사이의 동일 texture 전환 비용
4. WARP에서 모든 필수 셰이더·포맷이 실행되는가
5. 50MP·100MP·파노라마에서 타일 크기와 GPU 메모리 예산
6. x64/ARM64 vcpkg 의존성 전체 빌드
7. WinUI 3 ItemsView의 5만 항목 가상화와 선택 동작
8. unpackaged self-contained 설치·업데이트·제거·복구
9. ARM64 장치에서 플러그인 실행과 실제 스캐너 드라이버 가용성
10. 모니터 ICC·Advanced Color·SDR/HDR 혼합 디스플레이
11. WIC float TIFF와 codec/metadata corpus
12. 실제 WIA/TWAIN x64·x86 장치의 capability·ROI·bit depth
13. plugin 디렉토리 owner SID·DACL·reparse-point·TOCTOU 방어
14. LibRaw 선택 license, TWAIN DSM 배치, Adobe RGB 재배포
15. WiX OSMF 승인 또는 동등 installer 대안
16. 출시 시점에 지원 중인 Windows release
17. self-contained와 framework-dependent의 payload·시작·servicing 비교
18. macOS catalog·sidecar의 Windows migration/rollback 정책
19. x64·ARM64 instance election, activation redirection과 정상/세션 종료 state machine

전체 질문과 닫힘 조건은 [열린 질문 등록부](../99-plan/open-questions.md)를 따른다.

## 공식 근거

- [Windows App SDK release channels](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/release-channels)
- [Windows App SDK deployment overview](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/deploy-overview)
- [App instancing with the app lifecycle API](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/applifecycle/applifecycle-instancing)
- [Application lifecycle functionality migration](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/migrate-to-windows-app-sdk/guides/applifecycle)
- [Windows App SDK unpackaged deployment](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/deploy-unpackaged-apps)
- [Windows 11 release information](https://learn.microsoft.com/en-us/windows/release-health/windows11-release-information)
- [.NET support policy](https://dotnet.microsoft.com/en-us/platform/support/policy)
- [Direct2D custom effects](https://learn.microsoft.com/en-us/windows/win32/direct2d/custom-effects)
- [Direct2D effect shader linking](https://learn.microsoft.com/en-us/windows/win32/direct2d/effect-shader-linking)
- [Direct3D 11 compute shader overview](https://learn.microsoft.com/en-us/windows/win32/direct3d11/direct3d-11-advanced-stages-compute-shader)
- [Direct3D hardware feature levels](https://learn.microsoft.com/en-us/windows/win32/direct3d12/hardware-feature-levels)
- [Add Arm support to a Windows app](https://learn.microsoft.com/en-us/windows/arm/add-arm-support)
- [Windows on Arm FAQ](https://learn.microsoft.com/en-us/windows/arm/faq)
- [C++/WinRT component projection for .NET](https://learn.microsoft.com/en-us/windows/apps/develop/platform/csharp-winrt/net-projection-from-cppwinrt-component)
- [WiX Toolset repository and OSMF notice](https://github.com/wixtoolset/wix)
- [LibRaw licensing](https://www.libraw.org/about)
- [TWAIN DSM repository](https://github.com/twain/twain-dsm)
