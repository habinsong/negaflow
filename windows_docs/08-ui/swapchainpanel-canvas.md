# WinUI 3 `SwapChainPanel` 캔버스 인터롭

조사 기준일: 2026-08-04  
대상 기준: Windows 11, Windows App SDK stable 2.3.1, C#/.NET 10 셸 + C++20 D3D11 엔진  
역할: [Canvas 제품 표면 명세](surfaces/canvas.md)를 실제 WinUI·DXGI presentation으로 연결

## 결론

Negaflow의 사진 캔버스는 WinUI `Image`에 CPU bitmap을 반복 복사하지 않고, native D3D11 엔진이
`SwapChainPanel`에 composition swap chain을 연결해 직접 표시합니다.

```text
C# WinUI 3
  CanvasHost/Grid
    ├── SwapChainPanel          사진 pixel presentation
    ├── XAML interaction layer  focus, pointer, keyboard, accessibility
    └── XAML HUD/overlays       상태·도구·진행률
            │
            │ attach token + logical size/scale + immutable commands
            ▼
C++20 native engine
  D3D11/DXGI/Direct2D device
    → render graph
    → color-managed presentation surface
    → composition swap chain
    → Present
```

v1 기준:

- `IDXGIFactory2::CreateSwapChainForComposition`
- `DXGI_SWAP_EFFECT_FLIP_SEQUENTIAL`
- `DXGI_SCALING_STRETCH`
- double buffering을 출발점으로 측정
- panel과 swap chain 크기를 effective device pixels에 맞춤
- opaque canvas는 `DXGI_ALPHA_MODE_IGNORE`
- legacy SDR와 Advanced Color scRGB를 명시적으로 분리
- D3D11 immediate context와 `Present`는 native render queue가 직렬 소유
- panel attach/detach는 UI thread에서 수행
- 최대 네 개 권고 때문에 주 window당 한 panel, 비교는 같은 panel 안에서 합성
- Win2D/Vortice를 이 한 연결을 위해 의존성으로 추가하지 않음

이 문서는 API 호출 성공을 visual/color parity로 간주하지 않습니다. 100/125/150/200% DPI, 다중 모니터,
Advanced Color, device removal, window hide/show와 실제 WinUI click-through를 별도 검증합니다.

---

## 1. 왜 `SwapChainPanel`인가

사진 캔버스는 다음을 동시에 요구합니다.

- slider/brush/pan/zoom에 대한 낮은 input-to-present latency
- 16-bit/float 현상 결과의 GPU-resident 표시
- Direct2D/DirectCompute graph와의 resource 연계
- XAML toolbar/HUD/접근성 overlay
- 큰 이미지 tile의 부분 갱신
- display profile·Advanced Color 변화 대응

`SwapChainPanel`은 WinUI visual tree 안에 위치하면서 앱이 `IDXGISwapChain1` presentation을 직접
소유할 수 있습니다. XAML refresh timer와 독립적으로 update할 수 있고 XAML element를 그 위에
합성할 수 있습니다.

다른 후보:

| 후보 | 판단 |
|---|---|
| WinUI `Image` + `SoftwareBitmapSource` | thumbnail/정적 작은 preview에는 가능, interactive full canvas 기준 아님 |
| `SurfaceImageSource` | XAML cadence와 공유 surface update에 적합하지만 main low-latency canvas를 둘로 나누지 않음 |
| `VirtualSurfaceImageSource` | 큰 문서 viewport 후보지만 Negaflow engine tile/cache와 별 presentation path가 됨 |
| Win2D `CanvasControl` | wrapper 의존과 resource model이 추가됨; raw D2D/D3D 제어를 이미 필요로 함 |
| DirectComposition HWND tree | XAML integration·input·accessibility glue가 늘어남 |

v1은 `SwapChainPanel` 하나로 시작하고, thumbnail은 XAML image source 경로를 별도로 유지합니다.

---

## 2. 공식 제약

Microsoft의 DirectX/XAML interop 지침에서 다음을 지킵니다.

### 2.1 instance 수

앱당 `SwapChainPanel` instance는 네 개 이하를 권고합니다. Negaflow 정책:

- main window canvas: 한 개
- auxiliary/compare를 새 panel로 늘리지 않음
- Raw/Developed split은 한 swap chain back buffer 안에서 두 source를 clip/composite
- Print preview는 같은 workspace canvas를 재사용하거나 정적 preview surface 사용
- hidden workspace가 panel을 계속 보유하지 않게 수명 측정

여러 window 기능이 생기면 네 개 한계를 product navigation과 함께 재설계합니다. panel을 화면마다
무심코 생성하는 navigation cache를 금지합니다.

### 2.2 creation API

composition swap chain은 `IDXGIFactory2::CreateSwapChainForComposition`으로 만듭니다.

공식 필수값:

- `SwapEffect = DXGI_SWAP_EFFECT_FLIP_SEQUENTIAL`
- `Scaling = DXGI_SCALING_STRETCH`

`CreateSwapChainForHwnd`나 legacy `CreateSwapChain`으로 만들고 panel에 연결하지 않습니다.

### 2.3 크기

back buffer width/height는 panel의 현재 effective device-pixel 크기와 맞춥니다. 다르면 compositor가
stretch해 사진이 흐려지고 hit-test와 pixel sampler가 어긋날 수 있습니다.

### 2.4 지원되지 않는 호출

composition swap chain에는 다음 HWND/full-screen 중심 호출이 유효하지 않습니다.

- `SetFullscreenState`
- `ResizeTarget`
- `GetContainingOutput`
- `GetHwnd`
- `GetCoreWindow`

현재 monitor는 window bounds와 DXGI output bounds의 교차로 다시 결정합니다. stale
`GetContainingOutput`을 색 관리 source로 쓰지 않습니다.

---

## 3. baseline descriptor

SDR 호환 경로의 출발점:

```cpp
DXGI_SWAP_CHAIN_DESC1 desc{};
desc.Width       = pixelWidth;
desc.Height      = pixelHeight;
desc.Format      = DXGI_FORMAT_B8G8R8A8_UNORM;
desc.Stereo      = FALSE;
desc.SampleDesc  = { 1, 0 };
desc.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
desc.BufferCount = 2;
desc.Scaling     = DXGI_SCALING_STRETCH;
desc.SwapEffect  = DXGI_SWAP_EFFECT_FLIP_SEQUENTIAL;
desc.AlphaMode   = DXGI_ALPHA_MODE_IGNORE;
desc.Flags       = candidateFlags;
```

Advanced Color 후보:

```text
Format     = DXGI_FORMAT_R16G16B16A16_FLOAT
ColorSpace = DXGI_COLOR_SPACE_RGB_FULL_G10_NONE_P709
```

실제 생성 전 확인:

- D3D11 device에 `D3D11_CREATE_DEVICE_BGRA_SUPPORT`
- required format render-target/shader-resource support
- `CheckColorSpaceSupport`
- display pipeline mode
- width/height가 0이 아니고 API 범위 안
- byte/budget preflight

### 3.1 alpha

사진 canvas는 불투명 배경색까지 native가 그립니다. `DXGI_ALPHA_MODE_IGNORE`를 사용해 panel 뒤 backdrop과
사진 색이 섞이지 않게 합니다.

투명 canvas가 제품 요구가 되기 전 `PREMULTIPLIED`를 쓰지 않습니다. alpha mode를 바꾸면:

- clear color
- Direct2D target alpha mode
- XAML composition
- display color transform
- performance

를 함께 검증해야 합니다.

### 3.2 multisampling

flip-model swap-chain back buffer는 sample count 1로 둡니다. vector overlay에 MSAA가 필요하면 별도
offscreen resource에서 resolve합니다. 사진 pixel presentation을 위해 swap chain 자체를 multisample로
만들지 않습니다.

### 3.3 buffer count

2를 출발점으로 합니다. 3이 throughput을 개선하는지보다 interaction latency와 memory를 우선합니다.
FP16 4K buffer 한 장은 약 63.3 MiB이므로 buffer 하나 증가도 작지 않습니다.

정확한 default는 다음에서 측정합니다.

- 60/120/144 Hz
- integrated/discrete/Qualcomm GPU
- slider 연속 변경
- export 동시 실행
- resize/monitor 이동

---

## 4. panel 연결 경계

### 4.1 native interface

WinUI 3에서는 `microsoft.ui.xaml.media.dxinterop.h`의
`Microsoft::UI::Xaml::Media::DXInterop::ISwapChainPanelNative`를 사용합니다. UWP의
`windows.ui.xaml.media.dxinterop.h` 타입을 섞지 않습니다.

```cpp
auto panelNative = panel.as<
    Microsoft::UI::Xaml::Media::DXInterop::ISwapChainPanelNative>();
check_hresult(panelNative->SetSwapChain(swapChain.get()));
```

### 4.2 C# ↔ C++ 연결 선택

전체 engine ABI는 `LibraryImport` + opaque `SafeHandle`을 유지합니다. panel 하나를 넘기는 경로만
다음 두 후보를 spike합니다.

1. **C ABI interop**
   - C#이 지원되는 CsWinRT interop API로 panel ABI pointer를 얻음
   - native attach 함수가 즉시 `QueryInterface`하고 필요한 COM reference만 보유
   - pointer lifetime/add-ref/release를 stress test
2. **얇은 C++/WinRT adapter**
   - projected `SwapChainPanel`만 받고 `ISwapChainPanelNative` 연결
   - pixel engine object graph는 노출하지 않음
   - `.winmd`/projection은 이 adapter 표면에만 제한

사설 reflection이나 버전별 CsWinRT 내부 API에 의존하지 않습니다. Vortice를 `SetSwapChain` 한 번 때문에
추가하지 않습니다. public ABI 경로가 안정적이지 않으면 두 번째 후보가 더 작은 안전 경계입니다.

### 4.3 attach token

UI object pointer를 engine의 일반 canvas handle로 사용하지 않습니다.

```text
CanvasAttachToken
  host/window generation
  panel generation
  native canvas handle
  attached flag
```

attach 요청은 UI thread에서 시작하고, native는 다음을 검증합니다.

- panel pointer non-null/QI 성공
- canvas handle 유효
- 이전 panel generation과 중복 attach 아님
- swap chain/device generation 일치

### 4.4 detach

navigation, window close, device rebuild 전에 UI thread에서:

1. 새 render request 차단
2. pointer/input capture 해제
3. render queue에 canvas suspend barrier
4. in-flight present 완료 또는 generation 폐기
5. `SetSwapChain(nullptr)`
6. panel COM reference release
7. back-buffer dependent resources release

GC/finalizer에 detach를 맡기지 않습니다. `SafeHandle` finalizer는 최후의 native cleanup일 뿐 UI-thread
`SetSwapChain` 호출을 대신하지 않습니다.

---

## 5. size와 DPI

### 5.1 effective pixel 계산

panel layout은 effective pixels이고 swap-chain buffer는 device pixels입니다.

```text
pixelWidth  = ceil(max(0, ActualWidth)  × CompositionScaleX)
pixelHeight = ceil(max(0, ActualHeight) × CompositionScaleY)
```

반올림 규칙은 한 함수로 고정합니다. width/height가 0이거나 non-finite면 `ResizeBuffers`하지 않고
suspended 상태로 둡니다.

### 5.2 event 입력

- `SizeChanged`
- `CompositionScaleChanged`
- window DPI/display 이동
- visibility/navigation
- display rotation/Advanced Color change

각 event에서 바로 GPU를 여러 번 resize하지 않습니다. 최신 `(logicalSize, compositionScale,
displayBindingRevision)`만 coalesce해 render queue에 보냅니다.

### 5.3 `ResizeBuffers` 순서

1. present/render 중지와 generation barrier
2. back-buffer를 참조하는 D2D bitmap/RTV/SRV release
3. context에서 target/unneeded bindings 해제
4. 0×0 검사
5. 기존 creation flags와 일치하는 flags로 `ResizeBuffers`
6. current back buffer view와 Direct2D target 재생성
7. viewport/device-pixel transform 갱신
8. current frame/revision 재렌더

back-buffer reference가 하나라도 남으면 resize가 실패할 수 있습니다. 실패를 무시하고 stretch 상태로
계속 쓰지 않습니다.

### 5.4 resize storm

창을 드래그하는 동안 수십 번 event가 발생할 수 있습니다.

- UI layout은 계속 반응
- native는 latest request만 유지
- 작은 크기 변화에 old buffer를 stretch할지 여부는 짧은 live-resize 동안만 허용 가능
- drag 종료 후 exact pixel size로 반드시 settle
- resize 중 current image가 blank/flicker되지 않게 마지막 valid frame 유지 후보

제품 gate는 “resize 호출 수 감소”뿐 아니라 text/HUD와 image hit-test가 최종적으로 정확히 맞는지입니다.

---

## 6. presentation thread

### 6.1 owner

D3D11 immediate context와 swap-chain `Present`는 native render queue가 소유합니다. UI thread는 attach,
size, visibility 같은 작은 command만 보냅니다.

```text
UI command
→ render request snapshot
→ native render queue
→ wait/admit
→ draw current revision
→ Present
→ small completion event
→ UI DispatcherQueue
```

### 6.2 demand-driven render

Negaflow는 게임처럼 항상 60/144 FPS로 전체 canvas를 다시 그릴 필요가 없습니다.

render trigger:

- new develop tile/revision
- pan/zoom/compare divider/tool overlay change
- exposure of invalidated area
- resize/display binding change
- device recovery

idle일 때 present loop를 돌리지 않습니다. brush/drag 중에는 display cadence에 맞춰 latest state만 render하고
중간 input event를 모두 frame으로 만들지 않습니다.

### 6.3 frame latency waitable object

`DXGI_SWAP_CHAIN_FLAG_FRAME_LATENCY_WAITABLE_OBJECT`와
`IDXGISwapChain2::GetFrameLatencyWaitableObject`는 latency/power 후보입니다.

규칙:

- flag는 creation 때 결정하며 `ResizeBuffers`에서 다르게 바꿀 수 없음
- 사용 시 per-swap-chain `SetMaximumFrameLatency`
- render 전에 wait하며 첫 frame도 포함
- handle은 사용 후 `CloseHandle`
- UI thread가 기다리지 않음
- timeout/device-lost/window hidden 경로 포함

maximum latency 1과 2를 측정합니다. 1은 낮은 latency, 2는 CPU/GPU overlap에 유리할 수 있습니다.
사진 app에서 idle/demand-driven scheduler와 결합했을 때 실제 이득을 확인한 뒤 기본을 정합니다.

### 6.4 `Present`

composition swap chain의 기본은 synchronized present 후보입니다. tearing flag를 낮은 latency라는 이유로
바로 켜지 않습니다.

- 사진 pan/brush에서 tearing보다 안정된 화면 우선
- `Present` HRESULT 확인
- occluded/hidden 상태에서 불필요 present 중지
- `DEVICE_REMOVED/RESET`이면 generation recovery
- present 성공을 correct-color frame 적용 성공과 동일시하지 않음

---

## 7. resource ownership

### 7.1 device chain

```text
IDXGIAdapter
→ ID3D11Device / ID3D11DeviceContext
→ IDXGIDevice
→ ID2D1Device
→ ID2D1DeviceContext
→ swap chain back buffer
→ ID2D1Bitmap1 target / RTV
```

factory/device/context를 frame마다 만들지 않습니다. device와 kernel/effect cache는 장기 재사용하고
device generation으로 무효화합니다.

### 7.2 Shell에 넘기지 않는 것

- `ID3D11Texture2D*`
- `ID2D1Image*`
- back-buffer pointer
- raw mapped pixel pointer
- fence/query pointer

C#은 opaque canvas/job handles와 small state만 가집니다.

### 7.3 target 규칙

같은 Direct2D bitmap/command list를 여러 device context에서 동시에 target으로 쓰지 않습니다.

- preview render pass owner 하나
- export target 별도
- source와 target binding hazard 해제
- `BeginDraw`/`EndDraw` 오류 확인
- target을 바꾸기 전 state reset

### 7.4 back-buffer 수명

각 buffer index에 대한 view는 swap-chain generation에 종속됩니다. resize/device loss 뒤 old view를 cache에서
찾아 쓰지 않습니다.

`GetCurrentBackBufferIndex` 사용 여부는 swap-chain interface와 buffer strategy에 맞추되, index만 cache key로
쓰지 않고 generation을 포함합니다.

---

## 8. 색 관리와 surface mode

단일 “고급 색 켜짐” bool로 처리하지 않습니다. [색 관리 문서](../04-color-management/color-pipeline.md)의
세 상태를 그대로 사용합니다.

```text
LegacySdrExplicitIcc
AdvancedColorScRgb
ConservativeSrgbFallback
```

### 8.1 legacy SDR

```text
working image
→ display range mapping/soft proof
→ current monitor ICC transform
→ BGRA8 display-coded surface
→ DWM
```

- XAML UI에는 사진 monitor transform을 적용하지 않음
- display profile 없음은 documented sRGB assumption으로 처리 가능
- monitor 이동 시 `DisplayBindingRevision` 증가
- 이전 monitor transform 결과를 새 monitor에 적용하지 않음

### 8.2 Advanced Color

```text
working image
→ product mapping/soft proof
→ FP16 scRGB
→ SetColorSpace1(RGB_FULL_G10_NONE_P709)
→ DWM/Windows display transform
```

- `DXGI_FORMAT_R16G16B16A16_FLOAT`
- `CheckColorSpaceSupport` 성공 뒤 `SetColorSpace1`
- monitor ICC를 앱이 다시 적용하지 않음
- HDR SDR-white scaling은 presentation transform에만
- standard SDR display에서 out-of-[0,1] 값이 clip될 수 있음을 고려

### 8.3 상태 관측

Windows App SDK 2.x의 `Microsoft.Graphics.Display.DisplayInformation`은 color profile과 Advanced Color
변화 event를 제공하는 후보입니다. DXGI output 정보와 결합해 실제 desktop WinUI window에서 검증합니다.

- `AdvancedColorInfoChanged`
- `ColorProfileChanged`
- window/output binding
- `IDXGIFactory1::IsCurrent`
- `IDXGIOutput6::GetDesc1`
- swap-chain color-space support

한 API가 알려주는 capability와 현재 active mode를 혼동하지 않습니다.

### 8.4 mode 전환

format이 BGRA8↔FP16으로 바뀌면 `ResizeBuffers`만으로 억지 전환하지 않고 새 immutable presentation
configuration과 필요시 새 swap chain을 만듭니다.

1. old presentation suspend
2. display revision 고정
3. 새 format/color-space support 확인
4. 새 chain/resources 생성
5. panel에 새 chain 연결
6. current image 재렌더
7. old chain release

중간 black flash와 잘못된 monitor profile frame을 실기 검증합니다.

---

## 9. viewport와 tile 표시

제품 동작은 [Canvas 표면 명세](surfaces/canvas.md), 좌표/타일은
[대용량 이미지 문서](../06-large-images/image-source-tiling.md)가 기준입니다.

Swap chain은 전체 source 이미지 크기가 아니라 panel device-pixel 크기입니다.

```text
source/develop tiles
→ current viewport transform
→ panel-sized back buffer
```

- 100MP image를 100MP swap-chain buffer로 만들지 않음
- viewport에 필요한 mip/tile만 request
- visible core와 tool halo 우선
- missing tile은 이전 lower mip로 임시 표시 가능
- lower mip를 final pixel sampler/export 결과로 사용하지 않음
- tile arrival마다 전체 graph를 재생성하지 않고 invalidated region/coalesced frame

Direct2D `ID2D1ImageSourceFromWic` on-demand cache는 source 표시 가속 후보이고, developed tile cache와 같은
것이 아닙니다.

---

## 10. input 계층

### 10.1 왜 XAML overlay인가

`SwapChainPanel`은 일반 focusable form control처럼 모든 keyboard/accessibility를 해결하지 않습니다.
focusable XAML interaction layer를 panel 위에 두고 다음을 담당합니다.

- pointer pressed/moved/released/cancelled
- pointer capture
- wheel/pinch/key routing
- AutomationPeer와 accessible name/help/state
- cursor와 tool hint
- progress/error live region

사진 pixel과 high-frequency brush preview는 native가 그릴 수 있지만 semantic controls는 XAML로 유지합니다.

### 10.2 좌표 전달

Shell은 raw screen coordinate를 그대로 넘기지 않고 다음 small payload를 만듭니다.

```text
pointer ID/device kind/buttons/modifiers/pressure
panel effective coordinate
panel logical size + composition scale revision
timestamp
active tool/session/revision
```

native geometry가 effective→device→display normalized→source pixel을 같은 transform으로 계산합니다.

### 10.3 coalescing

pointer move가 render queue를 무한히 채우지 않게 합니다.

- stroke sample 자체는 필요한 밀도로 보존
- visual preview는 latest/coalesced
- pointer down/up/cancel은 drop 금지
- revision/tool session mismatch sample 거부
- pen pressure 0/NaN/range 검증

### 10.4 independent input source

UWP 문서의 `CreateCoreIndependentInputSource`를 WinUI 3에서 그대로 사용할 수 있다고 가정하지 않습니다.
그 경로는 normal XAML pointer event를 redirect하고 focus/accessibility 모델을 복잡하게 만듭니다. 먼저 XAML
pointer path의 latency를 측정하고, 부족할 때 Windows App SDK 현재 API로 별도 spike합니다.

---

## 11. XAML overlay와 native overlay 경계

### XAML이 소유

- compare/zoom HUD controls
- tool instructions
- progress/error/status
- buttons, menus, tooltips
- focus visual
- accessible hit targets

### native가 소유

- photo pixels
- soft-proof/gamut/clipping masks
- brush/clone/crop geometry와 image-aligned preview
- compare split clip과 divider 아래 image composition
- pixel-accurate sampling marker 후보

### 선택 기준

image transform과 exact pixel alignment가 필요하면 native, semantic interaction과 accessibility가 중요하면
XAML입니다. 같은 overlay를 두 계층에서 중복 그리지 않습니다.

XAML HUD background는 canvas 위 가독성을 확보하되 Acrylic/Backdrop이 사진 pixel을 sampling할 것이라고
가정하지 않습니다. 명시적 opaque/translucent fill을 사용하고 actual composition 결과를 확인합니다.

---

## 12. visibility와 전원

### hidden/minimized

- 새 present 중지
- background develop/export는 별 job policy에 따름
- viewport prefetch 중지
- 재생성 가능한 display cache eviction 허용
- swap chain을 즉시 폐기할지는 hide duration/memory 측정 후

### visible 복귀

- panel generation·size·scale·display binding 재확인
- device removed 여부 확인
- current frame/revision 요청
- 이전 stale back buffer만 보여준 채 완료 상태로 두지 않음

### suspend/resume·sleep

desktop app이라 UWP lifecycle을 그대로 복제하지 않습니다. system sleep/display power 변화, session unlock,
GPU device reset에서 동일 recovery path를 실행합니다.

---

## 13. device lost

감지 후보:

- `Present`의 `DXGI_ERROR_DEVICE_REMOVED/RESET`
- `EndDraw`의 `D2DERR_RECREATE_TARGET`
- resource creation failure
- explicit adapter/display invalidation

복구:

1. `GetDeviceRemovedReason` 기록
2. render admission 중지
3. device generation 증가
4. panel에서 old swap chain detach
5. all device-dependent caches/resources release
6. preferred hardware adapter 재생성
7. 실패 시 WARP 또는 CPU presentation fallback
8. 새 swap chain attach
9. current owner/frame/revision 재요청

GPU texture는 truth가 아닙니다. source+recipe가 truth이므로 old texture를 파일로 몰래 persist하거나 current로
간주하지 않습니다.

반복 `DEVICE_HUNG`·`INVALID_CALL`은 단순 driver 문제로 숨기지 않고 debug layer/PIX 재현 대상으로
분류합니다.

---

## 14. 오류 상태

| 실패 | UI 동작 | native 동작 |
|---|---|---|
| panel attach 실패 | canvas unavailable 메시지, retry | pointer/QI HRESULT 보존 |
| swap chain 생성 실패 | CPU/WARP fallback 후보 | descriptor/capability 로그 |
| resize 실패 | 마지막 valid frame 또는 error | old/new generation 혼합 금지 |
| color-space 실패 | conservative sRGB 표시 | wide-gamut 성공 표기 금지 |
| device removed | 복구 중 상태 | 전체 dependent resource 재생성 |
| source render 실패 | 원본/thumbnail을 완성 결과처럼 표시 금지 | causal job error |
| stale revision | 사용자 오류 없음 | 결과 폐기 |

error overlay 자체가 XAML이므로 native canvas가 실패해도 사용자가 복구 명령을 사용할 수 있어야 합니다.

---

## 15. 접근성

native pixels는 UI Automation tree를 만들지 않습니다. XAML layer가 semantic surface를 제공합니다.

- 현재 사진 이름과 mode
- zoom percent
- compare mode/fraction
- active tool와 instruction
- rendering/progress/error state
- keyboard command와 focus order
- high contrast에서 tool handle/selection 경계

histogram/사진 content 자체를 장황한 자동 설명으로 만들 필요는 없지만, tool을 완료·취소하고 workspace를
빠져나갈 수 있어야 합니다.

text scale이 커져 HUD가 canvas를 가리면 compact/wrap/scroll 정책을 제품 표면 문서대로 적용합니다.
native overlay의 선 굵기와 hit target은 DPI/text scale/high contrast에서 별도로 검증합니다.

---

## 16. 테스트

### 16.1 ABI/lifetime

- attach/detach 1,000회
- navigation cache on/off
- GC compact/full collection 중 panel 유지
- window close와 in-flight present race
- wrong/null pointer 거부
- duplicate/stale panel generation
- device lost 중 detach/reattach
- `SetSwapChain(nullptr)` 후 native reference leak 없음

### 16.2 size/DPI

- 100/125/150/175/200/300%
- 홀수 fractional layout size
- 최소 1×1과 0×0
- live resize와 maximize/restore
- 모니터 사이 이동
- 서로 다른 DPI 모니터에 걸친 창
- display rotation

검사:

- exact buffer dimensions
- 사진 aspect와 pixel sharpness
- pointer hit-test/sample coordinate
- HUD/overlay alignment
- resize 후 stale frame 없음

### 16.3 color

- legacy sRGB
- calibrated wide-gamut legacy SDR
- Advanced Color SDR
- HDR on/off
- FP16/scRGB 지원·거부
- monitor profile change
- window monitor 이동
- soft proof/gamut/clipping overlay

colorimeter/측정 profile 없이 device-accurate라고 부르지 않습니다. automated numeric surface readback과 실제
monitor validation을 분리합니다.

### 16.4 interaction

- zoom/pan/compare divider
- crop
- defect brush/region/clone
- base picker
- local adjustments
- mouse/touchpad/pen/keyboard
- pointer cancel/capture lost
- slider drag 중 latest revision

각 gesture당 undo unit 하나와 tool session ownership을 확인합니다.

### 16.5 performance

- first visible frame
- slider input-to-present p50/p95/p99
- 100% pan missing tile rate
- idle GPU/CPU/power
- BGRA8 vs FP16 memory/bandwidth
- double vs triple buffering
- latency 1 vs 2
- export 동시 실행
- Intel/AMD/NVIDIA/Qualcomm/WARP

---

## 17. spike 순서

### SCP-01 — 최소 attach

- Windows App SDK 2.3.1 stable exact pin
- C# `SwapChainPanel`
- C++ D3D11 composition swap chain
- solid-color present
- attach/detach/resize

완료: 100/150/200%에서 exact pixel size, leak/debug-layer 오류 없음.

### SCP-02 — native engine bridge

- C ABI pointer 경로와 thin C++/WinRT adapter 비교
- GC/lifetime stress
- opaque SafeHandle ownership

완료: private CsWinRT API나 추가 graphics wrapper dependency 없이 안정적 연결 하나 선택.

### SCP-03 — photo surface

- developed texture
- viewport/tile
- Raw/Developed split
- XAML HUD overlay

완료: 제품 Canvas 표면의 기본 input/geometry parity.

### SCP-04 — display color

- legacy monitor ICC
- BGRA8 fallback
- FP16 scRGB Advanced Color
- display movement/mode change

완료: double color management와 stale-profile frame 없음.

### SCP-05 — recovery/performance

- forced TDR/device removal
- memory pressure
- waitable swap chain 후보
- interactive+export contention

완료: recovery와 latency gate를 통과한 descriptor/scheduler 값을 decision register에 고정.

---

## 18. 금지 사항

- full-resolution CPU bitmap을 매 frame XAML `Image`로 복사
- UWP `Windows.UI.Xaml` native interface와 WinUI 3 `Microsoft.UI.Xaml` interface 혼용
- `CreateSwapChainForHwnd` chain을 panel에 연결
- composition chain에서 `DXGI_SCALING_STRETCH` 외 값을 임의 사용
- panel logical px를 buffer device px로 사용
- layout event마다 즉시 `ResizeBuffers`
- back-buffer reference를 남긴 채 resize
- UI thread에서 `Present`/GPU wait
- worker 여러 개가 같은 immediate context/swap chain 호출
- hidden panel에서 idle render loop 유지
- Raw/Developed 비교를 panel 두 개로 구현
- XAML UI까지 monitor ICC 변환
- Advanced Color와 manual display ICC를 동시에 적용
- 색공간 설정 실패를 wide-gamut 성공으로 표시
- panel lifecycle을 GC/finalizer에 맡김
- device lost 뒤 old-generation texture 재사용
- `SetSwapChain` 하나를 위해 Vortice/Win2D 같은 dependency 추가

---

## 19. 미결정 항목

- C ABI ABI-pointer 경로와 thin C++/WinRT adapter 중 실제 선택
- `FRAME_LATENCY_WAITABLE_OBJECT`의 composition chain/장치별 이득
- maximum frame latency 1 또는 2
- buffer count 2 또는 3
- live-resize 중 임시 stretch 정책
- Advanced Color SDR 판정의 최종 API 조합
- legacy SDR monitor-coded BGRA8 surface의 exact format/tag
- WinUI 3 pointer path가 pen/brush latency gate를 만족하는지
- panel을 hidden workspace에서 유지할 시간·memory threshold

미결정 항목을 구현자가 임의 상수로 굳히지 않고 spike 결과와 driver/OS 정보로 결정합니다.

---

## 공식 출처

- [SwapChainPanel class](https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.ui.xaml.controls.swapchainpanel)
- [WinUI 3 native DX interop header](https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/win32/microsoft.ui.xaml.media.dxinterop/)
- [ISwapChainPanelNative](https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/win32/microsoft.ui.xaml.media.dxinterop/nn-microsoft-ui-xaml-media-dxinterop-iswapchainpanelnative)
- [IDXGIFactory2::CreateSwapChainForComposition](https://learn.microsoft.com/en-us/windows/win32/api/dxgi1_2/nf-dxgi1_2-idxgifactory2-createswapchainforcomposition)
- [DirectX and XAML interop](https://learn.microsoft.com/en-us/windows/uwp/gaming/directx-and-xaml-interop)
- [For best performance, use DXGI flip model](https://learn.microsoft.com/en-us/windows/win32/direct3ddxgi/for-best-performance--use-dxgi-flip-model)
- [Reduce latency with DXGI 1.3 swap chains](https://learn.microsoft.com/en-us/windows/uwp/gaming/reduce-latency-with-dxgi-1-3-swap-chains)
- [IDXGISwapChain2::GetFrameLatencyWaitableObject](https://learn.microsoft.com/en-us/windows/win32/api/dxgi1_3/nf-dxgi1_3-idxgiswapchain2-getframelatencywaitableobject)
- [SwapChainPanel.CompositionScaleX](https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.ui.xaml.controls.swapchainpanel.compositionscalex)
- [Use DirectX with Advanced Color](https://learn.microsoft.com/en-us/windows/win32/direct3darticles/high-dynamic-range)
- [Microsoft.Graphics.Display.DisplayInformation](https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.graphics.display.displayinformation)
- [Windows App SDK release channels](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/stable-channel)
- [Windows App SDK 2.0 release notes](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/release-notes/windows-app-sdk-2-0)

## 연결 문서

- [Canvas 제품 표면](surfaces/canvas.md)
- [WinUI 3 선택과 버전](winui3.md)
- [UI parity 계약](parity-contract.md)
- [색 관리](../04-color-management/color-pipeline.md)
- [대용량 이미지 타일링](../06-large-images/image-source-tiling.md)
- [멀티스레드 렌더·내보내기](../07-threading/multithreading-export.md)
- [실행 백엔드 선택](../12-performance/backend-selection.md)
- [C# native interop](../09-language-choice/csharp-native-interop.md)
