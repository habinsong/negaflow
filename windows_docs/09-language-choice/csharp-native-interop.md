# C# WinUI 셸과 C++ 엔진의 경계

기준일: 2026-08-04  
결정: 좁은 C ABI + source-generated P/Invoke를 기본으로 하고, 패널 연결에만 조건부로 얇은
C++/WinRT 어댑터를 허용한다.

## 1. 경계가 해결해야 하는 문제

Negaflow의 경계는 일반적인 “함수 하나 호출”보다 수명이 길다.

- 수만 장 catalog의 UI 상태는 C#이 소유한다.
- 단일 원본의 decode, effect graph, GPU texture와 tile cache는 C++이 소유한다.
- slider drag 중 여러 render 요청이 들어오고 오래된 결과는 버려야 한다.
- export·defect detection·scanner job은 취소와 진행률이 필요하다.
- window와 GPU device가 사라져도 recipe·selection·catalog는 남아야 한다.
- x64와 ARM64에서 같은 의미를 유지해야 한다.

따라서 ABI 목표는 “모든 C++ API를 C#에 보이게 하기”가 아니라 UI가 필요한 command와 event만
안전하게 전달하는 것이다.

## 2. 왜 C++/WinRT component를 기본으로 하지 않는가

C++/WinRT component를 .NET 앱에서 소비하는 것은 지원되는 방식이지만 단순한 DLL 참조가 아니다.
공식 절차에는 `.winmd`에서 C# projection assembly를 생성하고 NuGet 또는 private projection
형태로 배포하는 단계가 있다. packaged 환경에서는 자연스럽지만 custom component와 unpackaged
배포를 결합하면 activation, registration-free WinRT, architecture별 projection artifact까지
관리해야 한다.

Negaflow 엔진은 WinRT object graph가 아니라 다음 성격을 갖는다.

- opaque engine/session/image handle
- file URL 또는 app-owned asset ID
- immutable parameter snapshot
- async request ID
- 작은 progress/error event
- native-owned D3D/D2D resources

이 표면은 C ABI가 더 작고 CLI·테스트도 같은 방식으로 소비할 수 있다. WinRT projection은
SwapChainPanel 자체처럼 WinUI type을 직접 넘겨야 할 때만 가치가 있다.

## 3. ABI의 기본 형태

실제 이름은 구현 스파이크에서 확정하되 다음 원칙을 바꾸지 않는다.

```c
typedef struct nf_engine_t nf_engine_t;
typedef struct nf_image_session_t nf_image_session_t;
typedef struct nf_canvas_t nf_canvas_t;
typedef struct nf_job_t nf_job_t;

typedef uint64_t nf_request_id_t;
typedef uint32_t nf_status_t;

typedef struct nf_engine_create_options_v1 {
    uint32_t struct_size;
    uint32_t abi_version;
    uint32_t preferred_backend;
    uint32_t flags;
    const uint8_t* app_data_path_utf8;
    uint64_t app_data_path_length;
} nf_engine_create_options_v1;
```

이것은 구현 코드가 아니라 ABI 모양을 설명하는 예시다.

규칙:

1. 모든 export는 `extern "C"`와 하나의 명시적 export macro를 쓴다.
2. calling convention은 `cdecl`로 명시한다.
3. 정수는 고정폭 타입만 쓴다.
4. C/C++ `bool`, `long`, `wchar_t`, `size_t`는 경계에 쓰지 않는다.
5. enum 저장 크기는 `uint32_t` 등으로 고정하고 unknown 값을 거부하거나 보존한다.
6. struct 첫 필드는 `struct_size`, 필요하면 둘째는 `abi_version`이다.
7. 모든 byte/string span은 pointer와 64-bit length를 함께 받는다.
8. C++ exception, RTTI type, STL container, COM smart pointer를 노출하지 않는다.
9. DLL이 할당한 메모리는 DLL이 해제한다. 더 좋은 기본은 caller-provided buffer다.
10. 함수 결과는 status code이며 상세 오류는 요청/event에 귀속한다.

## 4. version negotiation

세 개의 버전을 섞지 않는다.

| 버전 | 의미 | 예 |
|---|---|---|
| ABI major/minor | C symbol·struct 의미 | Shell ↔ Native DLL |
| engine data schema | recipe/preset/cache 형식 | Windows판 내부 persistence |
| product baseline | macOS 기능·수치 기준 | commit + asset hash manifest |

startup 순서:

1. Shell이 예상한 DLL을 app install directory의 절대 경로로 연다.
2. `get_abi_version`과 build info를 읽는다.
3. major가 다르면 실행을 중단하고 복구 가능한 설치 오류를 표시한다.
4. minor는 지원 capability bit와 struct size로 협상한다.
5. required shader/asset manifest hash를 확인한다.
6. engine을 만든 뒤 adapter·backend 진단을 이벤트로 받는다.

새 필드는 struct tail에만 추가한다. 기존 필드 의미를 바꾸거나 enum 숫자를 재사용하지 않는다.
삭제가 필요하면 major를 올리고 Shell·DLL·installer를 원자적으로 갱신한다.

## 5. 문자열과 경로

- ABI 문자열은 length-delimited UTF-8이다.
- embedded NUL의 허용 여부를 함수별로 명시한다. 파일 경로는 거부한다.
- C# 문자열을 호출 범위 밖에서 native가 보관하지 않는다.
- 파일 경로는 UI 표시 문자열과 IO 경로를 구분한다.
- Windows extended-length path, UNC, reparse point, reserved name을 IO 계층에서 검증한다.
- engine이 반환하는 표시 문자열은 caller가 먼저 필요한 byte 수를 묻고 buffer를 제공한다.
- 오류 메시지를 로직 분기에 쓰지 않는다. stable error domain/code를 사용한다.

`PWSTR`/UTF-16을 ABI 기본으로 쓰지 않는 이유는 engine의 JSON, CLI, plugin wire contract가
UTF-8이고 플랫폼 중립 fixture와 직접 비교하기 쉽기 때문이다. Windows API 호출 직전에만
검증된 UTF-16로 변환한다.

## 6. handle과 수명

| 객체 | 생성/소유 | 파괴 | thread 규칙 |
|---|---|---|---|
| engine | Shell 1개 | app shutdown | control API는 serialized |
| image session | engine | tab/selection 해제 후 | immutable snapshot으로 render |
| canvas | panel attachment | window/panel teardown | UI attach, render thread use |
| job | engine | terminal event 회수 후 | cancel은 어느 thread에서나 |
| event batch | caller buffer | 호출 종료 | 복사 없는 작은 POD |

C#은 native pointer를 `IntPtr`로 장기 보관하지 않고 각 handle 종류별 `SafeHandle`을 쓴다.
finalizer는 안전망일 뿐 정상 종료 수단이 아니다. UI view/session이 닫힐 때 명시적으로 dispose한다.

파괴 순서:

```text
새 요청 차단
→ 진행 job cancel
→ terminal 또는 bounded shutdown timeout
→ canvas detach
→ image sessions release
→ event queue drain/close
→ engine release
→ DLL unload는 프로세스 종료에 맡김
```

native worker가 살아 있는 동안 managed delegate나 UI object를 참조하지 않는다.

## 7. command 모델

ABI 호출을 속성 getter/setter 수백 개로 만들지 않는다. 사용자 동작 단위의 immutable command를
보낸다.

### 짧은 동기 호출

- ABI/build/capability query
- handle create/release
- canvas resize·visibility 신호
- job cancellation
- event drain

호출 시간 예산은 일반적으로 1ms 이하다. 디스크·decode·GPU fence 대기는 동기 ABI 호출에서
하지 않는다.

### 비동기 요청

- source probe/decode
- Develop render
- histogram/measurement
- defect detection/clean render
- export/print render
- cache maintenance

각 요청은 다음을 가진다.

- monotonically increasing `request_id`
- owner/session ID
- source revision
- parameter snapshot revision
- priority와 purpose: interactive, thumbnail, export, print
- cancellation token/job handle
- optional deadline 또는 supersession policy

Shell은 완료 이벤트를 적용하기 직전에 owner와 revision이 현재 상태와 같은지 다시 확인한다.
native도 렌더 결과를 canvas/cache에 확정하기 직전에 동일한 검사를 수행한다.

## 8. parameter snapshot

slider 하나씩 ABI를 왕복하며 native mutable state를 바꾸지 않는다.

```text
UI 편집 상태
→ validation된 DevelopSnapshot
→ canonical bytes 또는 versioned POD bundle
→ native request
→ request ID와 snapshot hash
```

요구사항:

- 모든 기본값과 단위가 schema에 있다.
- 누락된 값은 두 언어가 각자 추정하지 않는다.
- NaN/Inf, 범위 밖 수, 잘못된 enum을 ABI 입구에서 거부한다.
- snapshot은 렌더 중 불변이다.
- preset, sidecar, undo entry, export plan이 같은 canonical parameter semantics를 쓴다.
- variable-length curve/LUT/defect recipe는 versioned canonical bytes로 보내되 크기 상한을 둔다.
- secret이나 사용자 원본 pixel을 진단 payload에 넣지 않는다.

JSON은 디버그와 wire fixture에는 좋지만 slider drag마다 parse하는 기본 경로로 쓰지 않는다.
고정 조정값은 POD, 복잡한 recipe는 versioned binary 또는 canonical JSON 중 실제 프로파일 결과로
선택한다.

## 9. event 모델

native thread가 managed callback을 직접 호출하는 방식은 기본에서 제외한다.

이유:

- delegate pinning과 shutdown race
- callback thread에서 UI 접근 위험
- callback 중 native lock 재진입
- managed exception이 ABI를 넘어갈 위험
- 이벤트 폭주가 렌더 thread를 멈출 위험

대신 native에 bounded multi-producer event queue를 두고 Shell이 drain한다.

이벤트 예:

| 종류 | delivery 규칙 |
|---|---|
| job started | 한 번, 드롭 금지 |
| progress | 같은 job의 최신 값으로 coalesce 가능 |
| preview ready | 오래된 request면 드롭 가능 |
| terminal success/cancel/failure | 반드시 한 번, 드롭 금지 |
| device lost/recovered | 순서 보존, 진단 code 포함 |
| memory pressure | rate limit |
| log/trace | 별도 ETW가 기본, UI event queue를 채우지 않음 |

Shell은 짧은 dispatcher timer 또는 native waitable signal을 background task가 기다린 뒤 UI
DispatcherQueue로 전달한다. waitable signal 방식도 shutdown cancellation을 가진다.

queue가 꽉 찰 때:

1. progress를 coalesce한다.
2. 오래된 interactive preview를 supersede한다.
3. 진단성 event를 rate-limit한다.
4. terminal event용 reserved capacity를 유지한다.
5. terminal도 넣을 수 없다면 engine을 정상 상태로 간주하지 않고 명시적 fatal contract error를 낸다.

## 10. 오류 계약

문자열 하나의 `last_error`는 사용하지 않는다. 여러 async 요청과 thread에서 어느 작업의 오류인지
잃기 때문이다.

권장 오류 필드:

- domain: ABI, argument, image IO, color, render, GPU, storage, export, print, plugin
- stable code
- severity: recoverable, job-fatal, engine-fatal
- request/job/session ID
- OS HRESULT 또는 Win32 code — 해당될 때만
- 사용자 표시용 localization key와 안전한 arguments
- 개발 진단용 제한된 UTF-8 detail
- retryability와 recovery action enum

사용자 표시 문장은 C# localization이 소유한다. native detail을 그대로 dialog title로 노출하지 않는다.

## 11. 픽셀과 GPU 리소스는 경계를 건너지 않는다

금지:

- 매 프레임 `float[]` 또는 `byte[]`를 managed heap으로 복사
- `WriteableBitmap`을 고해상도 Develop 캔버스의 중간 저장소로 사용
- GPU texture pointer를 C#이 해석
- C#이 native tile cache eviction을 직접 수행
- engine이 XAML element tree를 소유

허용되는 데이터:

- 작은 thumbnail의 최종 encoded bytes 또는 app-owned file path
- histogram bin처럼 상한이 작은 수치 배열
- eyedropper sample, dimensions, progress, metrics
- export 결과 manifest

Develop canvas는 native GPU texture에서 swap chain으로 직접 present한다.

## 12. SwapChainPanel 연결 스파이크

두 안을 순서대로 검증한다.

### 안 A — C ABI + COM identity

1. C#이 `SwapChainPanel`의 inspectable/COM identity를 안전하게 얻는다.
2. 호출 범위 동안 명시적으로 reference를 유지한다.
3. C ABI attach 함수가 `IUnknown*`를 받고 즉시 필요한 native interface를 query한다.
4. native canvas가 panel과 swap chain lifetime을 관리한다.
5. detach 완료 전 C#이 panel을 파괴하지 않는다.

검증 항목:

- x64·ARM64
- unpackaged self-contained publish
- window close/reopen, tab switch, DPI change
- device lost와 adapter change
- GC stress와 rapid attach/detach
- native/managed reference leak

### 안 B — 얇은 C++/WinRT 어댑터

안 A의 지원 API가 불안정하거나 COM lifetime을 명확히 증명하지 못할 때만 사용한다.

어댑터 책임은 다음뿐이다.

- WinRT `SwapChainPanel` 인수 수신
- `ISwapChainPanelNative` 획득
- canvas handle과 연결/분리

render, image session, event, export API를 WinRT class로 다시 투영하지 않는다. projection assembly와
unpackaged activation을 x64/ARM64 installer에서 함께 검증한다.

## 13. UI thread와 native thread

| 동작 | thread |
|---|---|
| XAML element 생성·변경 | UI thread |
| panel attach/detach와 size signal | UI thread 시작, native 내부 직렬화 |
| decode, render graph 준비 | native worker |
| D3D immediate context 사용 | engine이 정한 한 render queue/thread |
| CPU tile kernel | bounded worker pool |
| event drain | background 또는 UI의 짧은 호출 |
| view model 적용 | UI DispatcherQueue |

D3D11 immediate context를 여러 worker가 동시에 호출하지 않는다. deferred context는 측정으로 이득이
증명되기 전 사용하지 않는다. CPU task가 UI thread pool을 포화하지 않게 native pool을 분리한다.

## 14. DLL 로딩 보안

- C#의 native resolver가 설치 디렉토리의 절대 경로를 계산한다.
- architecture별 payload manifest와 DLL hash를 검사한다.
- 현재 작업 디렉토리, 원본 폴더, plugin 폴더를 DLL search path에 넣지 않는다.
- 종속 DLL은 제한된 default directory에서만 찾는다.
- architecture mismatch는 `BadImageFormatException` 그대로 노출하지 않고 설치 복구 안내로 변환한다.
- plugin process가 사용하는 DLL과 본체 native DLL 디렉토리를 분리한다.
- unsigned replacement와 version mismatch는 startup에서 실패시킨다.

Authenticode 서명 확인을 매 launch마다 모든 파일에 중복 수행할지는 시작 비용을 측정해 결정한다.
installer manifest·secure install ACL·build ID 확인은 최소 기준이다.

## 15. 성능 예산

| 경계 동작 | 목표 |
|---|---|
| slider snapshot submit | UI frame budget을 막지 않음, 일반적으로 1ms 미만 |
| event drain | bounded batch, 한 UI tick에서 무한 루프 금지 |
| histogram copy | 고정 bin 수만 복사 |
| thumbnail 전달 | encoded 또는 shared app cache path, raw 50MP 금지 |
| preview render | 가장 최신 요청 우선, 오래된 요청 조기 취소 |
| export progress | 파일 준비 단계와 파일 완료 단계를 구분 |

ABI 호출 횟수 자체보다 경계를 넘는 데이터량, UI-thread 대기, native lock contention을 계측한다.

## 16. 테스트 매트릭스

### ABI layout

- C++ `sizeof`/`offsetof`와 C# `Unsafe.SizeOf` 비교
- x64·ARM64 구조체 크기와 alignment
- unknown tail field와 더 작은 `struct_size`
- invalid pointer/length 조합, 64-bit overflow
- UTF-8 invalid sequence, embedded NUL, very long path

### lifetime

- dispose 두 번
- request 중 session dispose
- app shutdown 중 export/canvas render
- panel rapid attach/detach
- finalizer만 남은 misuse가 crash 대신 진단되는지
- device lost 후 old handle 거부

### ordering

- request A보다 B가 먼저 완료
- A 완료 직전 selection 변경
- cancel과 success 동시 race
- event queue saturation
- process suspend/resume와 power transition

### 배포

- DLL 없음, 잘못된 version, 잘못된 architecture
- shader/assets 일부 손상
- x64와 ARM64 clean machine
- framework-dependent runtime 없음과 self-contained layout
- upgrade 중 Shell과 Native가 다른 version이 되지 않는지

## 17. 승인 게이트

C ABI 기본안을 채택하려면 첫 캔버스 스파이크에서 다음을 모두 통과해야 한다.

1. 관리 heap으로 원본/프리뷰 픽셀 전체 복사가 없다.
2. rapid slider·resize·selection에서 UI thread stall이 없다.
3. GC stress 뒤 panel·swap chain reference leak이 없다.
4. stale result가 다른 frame에 적용되지 않는다.
5. x64·ARM64 unpackaged 설치에서 같은 ABI tests가 통과한다.
6. CLI가 WinUI dependency 없이 DLL의 수치 경로를 검증한다.
7. native crash와 managed crash가 서로 구분되는 dump/build ID를 남긴다.

패널 연결만 실패하면 안 B로 전환한다. 전체 엔진을 C++/WinRT object model로 넓히는 것은 이
스파이크의 허용된 결론이 아니다.

## 공식 근거

- [Generate a C# projection from a C++/WinRT component](https://learn.microsoft.com/en-us/windows/apps/develop/platform/csharp-winrt/net-projection-from-cppwinrt-component)
- [Create a Windows Runtime component with C++/WinRT](https://learn.microsoft.com/en-us/windows/uwp/winrt-components/create-a-windows-runtime-component-in-cppwinrt)
- [Platform overview for Windows App SDK](https://learn.microsoft.com/en-us/windows/apps/develop/platform/)
- [Native interoperability best practices](https://learn.microsoft.com/en-us/dotnet/standard/native-interop/best-practices)
- [Source-generated P/Invoke](https://learn.microsoft.com/en-us/dotnet/standard/native-interop/pinvoke-source-generation)
- [Swap chains for XAML composition](https://learn.microsoft.com/en-us/windows/uwp/gaming/directx-and-xaml-interop)

