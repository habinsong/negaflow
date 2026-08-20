# Canvas surface와 DirectX presentation 이식 명세

기준일: 2026-08-04  
macOS 기준 커밋: `9be909c`  
소스 근거: `Features/Canvas`, `Features/Develop/LocalAdjustments`, `Features/Defects`  
공식 근거: [SwapChainPanel](https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.ui.xaml.controls.swapchainpanel),
[ISwapChainPanelNative::SetSwapChain](https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/win32/microsoft.ui.xaml.media.dxinterop/nf-microsoft-ui-xaml-media-dxinterop-iswapchainpanelnative-setswapchain),
[Composition native interop](https://learn.microsoft.com/en-us/windows/uwp/composition/composition-native-interop),
[Direct2D color management](https://learn.microsoft.com/en-us/windows/win32/direct2d/color-management)

## 1. 역할

Canvas는 engine 결과를 보여주는 passive image view가 아니다. 다음 기능이 동일한 image geometry와
revision state를 공유한다.

- raw/developed/debug preview presentation
- fit/actual-size/zoom/pan
- raw/developed/split before-after 비교
- clipping·destination-gamut warning·debug overlay
- crop, defect brush, region detect, clone stamp, base picker, local adjustment
- flatbed preview scan-area overlay
- pixel sampler
- mouse, precision touchpad, pen, keyboard, Narrator interaction

따라서 Windows판은 `Image`에 bitmap을 계속 복사하는 구조보다 DirectX texture를 직접 present하는
native canvas가 기본이다. WinUI controls는 명령·접근성·overlay chrome을 맡고 C++ engine은 texture와
render graph를 소유한다.

## 2. 권장 presentation 구조

```text
C# WinUI 3 CanvasHost
├─ focusable interaction/accessibility layer
├─ SwapChainPanel
│  └─ DXGI swap chain (D3D11 device)
├─ lightweight XAML chrome
│  ├─ compare/zoom HUD
│  ├─ labels and prompts
│  └─ progress/error/live regions
└─ input router
   └─ normalized DisplayPoint / ToolCommand → native engine

C++ CanvasPresenter
├─ D3D11 device/context
├─ developed/raw/before/overlay textures
├─ Direct2D device context for vector/text where appropriate
├─ present scheduler
└─ device-lost/resource-lifetime handling
```

`SwapChainPanel`과 swap chain을 잇는 `ISwapChainPanelNative::SetSwapChain`은 작은 C++/WinRT 또는
native interop adapter가 담당한다. 이것은 전체 engine을 WinRT component로 바꾸는 근거가 아니다.
사진 engine의 C ABI는 그대로 유지하고 panel attach/detach만 얇게 둔다.

공식 API 계약상:

- `SetSwapChain`은 해당 panel의 UI thread에서 호출한다.
- panel이 사라지거나 device를 재생성할 때 `SetSwapChain(nullptr)`로 참조를 즉시 끊는다.
- `CompositionScaleX/Y` 변화에 맞춰 실제 pixel size를 다시 계산하고 render target을 재생성한다.
- `SwapChainPanel`은 자체 focusable `Control`이 아니므로, key event를 받을 focusable sibling/overlay를 둔다.
- WinUI 3 `SwapChainPanel`은 transparency와 backdrop/acrylic sampling 제약이 있으므로 canvas 위/뒤에
  Acrylic 효과를 기대하지 않는다. Canvas 배경은 명시적인 opaque color로 그린다.

대안인 `Microsoft.UI.Composition` drawing surface는 작은 HUD/thumbnail에는 유용하지만 첫 구현에서
두 presentation path를 만들지 않는다. SwapChainPanel spike가 DPI, input, device-lost 요구를 충족하면
단일 경로로 고정한다.

## 3. device와 resource ownership

Canvas는 가능하면 develop compute와 같은 D3D11 device를 공유한다.

```text
one adapter selection
→ one D3D11 device
→ compute textures
→ Direct2D interop/color transform
→ swap-chain back buffer
→ Present
```

목표는 GPU readback/upload 왕복을 제거하는 것이다. 단, 다음 경계를 명확히 한다.

- engine texture는 native reference-counted handle로 소유
- C#은 raw pointer lifetime을 소유하지 않고 opaque surface token만 보유
- visible frame/revision이 바뀌면 presenter가 old token을 release queue로 이동
- GPU command 완료 전 texture를 재사용하지 않음
- UI resize와 render completion이 동시에 와도 swap-chain resource를 이중 해제하지 않음
- device lost 시 모든 dependent Direct2D/compute/presentation object를 순서대로 재생성

WARP와 CPU result도 마지막에는 같은 present path로 들어온다. CPU buffer는 staged upload를 쓰되
지원되는 경우 dirty tile만 갱신한다.

## 4. 좌표계 계약

적어도 다음 좌표계를 구분한다.

| 좌표계 | 방향/단위 | 용도 |
|---|---|---|
| source pixel | source orientation, integer pixel | sampler, raw recipe provenance |
| base normalized | 변형 전 `0...1`, engine 정의 | persistent masks/base pick |
| display normalized | rotate/flip/straighten 후 `0...1`, y-down | UI overlay |
| image-frame effective px | WinUI layout px | hit test/HUD |
| device pixel | DPI scale 반영 | swap-chain render target |

한 곳의 `ImageGeometryTransform`만 모든 변환을 제공한다.

```text
SourcePixel ↔ BaseUnit ↔ DisplayUnit ↔ ImageFrameEffectivePx ↔ DevicePx
```

crop은 현재 engine에서 rotate/flip/straighten 후 마지막에 적용되며 저장 좌표는 y-up normalized다.
UI crop selection은 y-down이므로 변환 때 y를 뒤집는다. local/defect/base sampler가 각자 다른 수식으로
좌표를 바꾸지 않는다.

모든 입력에서 검사:

- finite
- width/height > 0
- normalized clamp
- orientation/flip/rotation/straighten/crop revision 일치
- source dimension 일치

## 5. 표시 이미지 선택

우선순위:

1. debug overlay가 활성이고 해당 stage image가 있으면 debug preview
2. Raw mode: raw preview → developed → thumbnail
3. Developed/split mode: developed → raw preview → thumbnail

fallback은 loading continuity용일 뿐 결과 위조가 아니다. fallback을 표시할 때 현재 이미지 class를
상태로 유지하고, export가 thumbnail/raw fallback을 final developed result로 쓰지 못하게 한다.

`displayPixelSize`처럼 안정화된 layout aspect를 사용한다. interactive proxy와 settled proxy의 반올림
차이가 canvas frame을 흔들거나 새 render를 무한 요청하게 하지 않는다. 표시 target pixel 변경은
render scheduling에 직접 재귀 연결하지 않고 coalesced model state로 전달한다.

## 6. viewport

현재 viewport state:

- fit-relative scale 기본 `1.0`
- 내부 허용 `0.2...12.0`
- HUD 직접 입력 `5...1600%`를 받은 뒤 viewport 범위로 clamp
- zoom button step `×1.25`, `÷1.25`
- `+`, `=`, `-` keyboard
- double-click image: fit/reset
- Fit: scale 1, offset 0
- Actual Size: source/display pixel과 DPI를 사용해 1 image pixel = 1 device pixel 후보 계산
- pan offset은 image가 canvas에서 빠져나가 빈 공간만 남지 않도록 clamp

Windows 번역:

- mouse wheel 기본 동작을 pan/zoom 중 무엇으로 할지 Windows 관례와 기존 shortcut manifest를 함께
  확정한다. `Ctrl+wheel` zoom 후보를 별도 테스트한다.
- precision touchpad pinch는 pointer centroid를 anchor로 확대해야 한다. 현재 macOS center zoom과
  차이가 생기면 승인된 platform delta로 기록한다.
- Space+drag pan이 현재 shortcut에 있는지 확인 전 추가하지 않는다.
- pen barrel/touch가 crop/brush와 충돌하지 않도록 input device type을 전달한다.
- viewport는 frame의 content transform이 바뀌면 crop session 중이 아닌 경우 fit으로 reset한다.

`CompositionScaleChanged`, panel size, window monitor 이동, display rotation/HDR change를 독립 event로
받아 back buffer 크기와 viewport를 재계산한다. effective px를 device px로 오인하면 125/150%에서
blurry 또는 offset hit-testing이 생긴다.

## 7. pan과 active tool arbitration

일반 pan은 다음 도구가 꺼졌을 때만 시작한다.

- crop
- defect brush
- region defect
- base picker
- local adjustment drawing

현재 macOS guard에는 clone stamp가 일부 경로에서 명시되지 않아 overlay가 event를 소비하는 구조다.
Windows에서는 암묵적 event ordering 대신 `CanvasToolCoordinator`가 pan 허용 여부를 명시한다.

```text
None → pan/zoom/select allowed
Crop → crop events only, zoom allowed by policy
DefectBrush → brush events
RegionDefect → ROI/control events
CloneStamp → source/destination events
BasePicker → single sample event
LocalAdjustment → mask-kind events
```

동시에 두 tool state가 true가 되면 assert/telemetry를 남기고 마지막 명령을 단일 active tool로
정규화한다. tool cancellation과 recipe reset은 분리한다.

## 8. movable HUD

두 HUD:

- compare HUD: raw/developed/vertical split/horizontal split
- zoom HUD: out/in/percent/fit/actual size

기본 위치는 canvas 상단 양쪽이며 사용자가 drag할 수 있다. 규칙:

- canvas bounds 안으로 clamp
- 두 HUD가 겹치면 가장 가까운 유효 side로 밀기
- resize/DPI/text scale/localization 후 실제 measured size로 다시 배치
- drag 중 다른 HUD가 jump하지 않음
- hidden HUD의 이전 size가 visible HUD placement를 부당하게 막지 않음
- 위치를 세션만 기억하는지 workspace에 저장할지 delta register에서 결정

Windows에서는 drag handle을 별도 시각 장식으로 과장하지 않더라도 tooltip/accessible help로 이동
가능성을 노출한다. HUD background는 canvas 위 가독성을 확보하되 Acrylic/Backdrop dependency를 쓰지
않는다.

## 9. Raw / Developed / Before-After 비교

mode:

- Raw
- Developed
- Split Vertical: 왼쪽 Before, 오른쪽 Current
- Split Horizontal: 위 Before, 아래 Current

Before source:

- Main target
- Unedited: main target, profile/creative adjustments 없는 neutral develop
- Raw: inversion 전 scan/import
- 다른 catalog frame 또는 virtual copy

기본 Before는 `Unedited`이며 selection을 저장한다. 저장된 frame ID가 더 이상 존재하지 않으면
Unedited로 복구한다.

비교 가능 조건은 Before image와 현재 developed image가 둘 다 있는 경우다. split에 들어갈 때만 필요한
neutral/main/other-frame preview를 lazy 요청한다. 비교가 꺼진 상태에서 매 adjustment마다 추가 pass를
돌리지 않는다.

stale 판단:

- Main preview: transform와 develop revision
- Unedited preview: transform와 base key
- other frame: frame identity, developed availability와 revision

현재 frame의 develop target이 already Main이면 Main before는 현재 developed result를 우선할 수 있다.
다른 target이면 별도 main preview가 필요하다.

## 10. split divider

- vertical/horizontal fraction을 각각 따로 기억
- 초기 `0.5`
- 허용 `0.02...0.98`
- 보이는 line은 1 device pixel 후보
- pointer grab target은 18 effective px
- keyboard/UIA increment는 `0.05`
- grab의 가장자리를 잡아도 divider가 pointer로 순간 이동하지 않도록 grab offset 유지
- vertical cursor는 EW resize, horizontal은 NS resize

After 위에 soft-proof/clipping overlay를 합성하고 Before에는 적용하지 않는 현재 의미를 보존한다.
divider/label은 zoom/pan된 image frame을 따라가며 image 밖에 떠 있지 않는다.

## 11. crop overlay

Crop 진입:

1. 기존 engine crop을 `preCropRect`로 저장한다.
2. 기존 crop을 display selection으로 변환한다.
3. engine crop을 임시 해제해 원본 전체를 보여준다.
4. fast transform preview를 갱신한다.

이 설계 덕분에 기존 crop 바깥으로 handle을 다시 넓힐 수 있다.

interaction:

- 빈 image 영역 drag로 새 rect
- selection drag로 이동
- 8개 handle resize
- rule-of-thirds grid
- outside dimming
- Apply / Full / Cancel action bar
- aspect lock
- arrow로 `0.005`, Shift+arrow로 `0.02` 이동
- accessibility move action `0.01`, adjustable resize `0.02`
- 최소 crop size 현재 move clamp 기준 `0.035`

Apply는 현재 selection을 absolute crop으로 저장하고 session baseline을 비운 뒤 tool을 닫고 viewport를
fit으로 돌린다. 중첩 crop으로 곱하지 않는다. Full은 selection과 restore baseline을 full로 만들지만
최종 commit은 Apply에서 일어난다. Cancel/Escape/tab 전환은 기존 crop을 정확히 복원한다.

Windows에서는 handle visual 크기와 pointer hit target을 분리한다. touch/pen에서 최소 hit target을
확대해도 실제 crop geometry는 바뀌지 않는다. `Enter`는 Crop Apply에만 연결하여 defect apply와
중복 실행하지 않는다.

## 12. base picker

- 진입 시 Raw mode로 전환해 orange mask/base를 보기 쉽게 한다.
- click/tap display unit point를 inverse transform하여 base/source unit point로 바꾼다.
- straighten 역변환에는 source pixel size가 필요하다.
- sample 성공/실패 뒤 tool을 닫는다.
- 종료할 때 Raw mode였다면 Developed로 복귀한다.
- Escape는 sample 없이 닫는다.

picker prompt와 eyedropper cursor를 제공한다. source sample이 없거나 decode cache가 준비되지 않았다면
가짜 RGB를 반환하지 않고 loading 또는 명시적 실패를 보여준다.

## 13. defect/local adjustment overlay

overlay의 세부 data contract는 `defects.md`와 `develop.md`를 따른다. Canvas 공통 요구:

- draft와 applied recipe를 다른 layer/state로 표시
- pointer capture가 빠져도 stroke/session을 정상 종료 또는 취소
- display point를 persistent base normalized point로 바꿈
- zoom과 DPI에 관계없이 brush의 photo-relative/physical 의미 유지
- transform/revision이 바뀌면 stale draft 처리 정책 실행
- busy removal 중 Escape가 이미 실행 중인 engine operation을 무리하게 중단하지 않음
- mask preview는 `defectMaskPreviewID`가 현재 recipe/session과 일치할 때만 표시
- overlay가 XAML element 수천 개로 늘지 않도록 GPU/vector batch로 그림

## 14. flatbed scan-area overlay

다음 조건에서만 표시한다.

- frame이 preview scan
- current flatbed preview frame ID와 동일
- flatbed region workflow 사용
- crop/brush/region/clone/base picker가 모두 꺼짐

scanner plugin이 보고한 capability와 실제 preview geometry만 사용한다. 모델명으로 scan area를 추정하거나
USB 발견만으로 overlay를 만들지 않는다. display ROI → requested full-scan ROI → plugin이 적용했다고
응답한 ROI → manifest ROI의 chain을 유지한다.

## 15. pixel sampler

enable 시 현재 actionable frame의 develop를 요청하여 working base를 준비한다. hover가 image frame 안에
있을 때만 readout을 갱신한다.

표시 가능한 sample:

- source coordinate
- Original
- Working
- Proof: soft proof가 켜졌을 때

display unit point는 transform inverse로 source/base point가 되고 실제 source dimension으로 integer
coordinate를 계산한다. Original, Working, Proof의 color space label을 함께 표시하며 숫자만 나란히 두고
동일 공간이라고 암시하지 않는다.

성능:

- pointer move마다 GPU readback 금지
- CPU sample cache 또는 작은 asynchronous readback ring 사용
- 60/120Hz pointer event를 coalesce
- frame/tool exit 시 readout clear
- sampler off 시 working-base cache release

## 16. clipping, soft proof와 color management

Clipping overlay는 해당 frame의 현재 clipping image가 있을 때 Developed/After 위에 표시한다.

Destination gamut warning은 모두 참일 때만 보인다.

- soft proof enabled
- destination gamut warning enabled
- warning available
- frame overlay revision == current soft-proof configuration revision

stale overlay를 새 profile 결과 위에 표시하면 안 된다. overlay는 accessibility tree에서 decorative로
숨기되, 활성 상태와 의미는 별도 control/status로 노출한다.

Direct2D color management effect는 ICC v4.3의 일부를 지원하지만 channel/color-space 제약이 있으므로
그 자체가 macOS ColorSync parity 증거는 아니다. `D2D1_COLORMANAGEMENT_QUALITY_BEST`는 float precision
buffer와 feature support를 확인한 뒤 사용한다. 지원되지 않으면 임의의 색 transform으로 대체하지 않고
engine의 검증된 CPU color-management path 또는 명시된 fallback을 쓴다.

Canvas swap-chain color space, monitor ICC, proof profile, rendering intent, HDR/SDR white level을 manifest로
기록한다. screenshot pixel은 compositor/color management를 거치므로 engine buffer golden과 별도다.

## 17. debug preview

debug overlay가 켜지고 선택 stage image가 있을 때:

- normal comparison controls를 숨긴다.
- stage badge를 표시한다.
- image double-click fit은 유지한다.
- debug image가 없는 stage는 이전 stage image를 재사용하지 않는다.
- 일반 release와 telemetry에 raw filesystem/source data가 불필요하게 노출되지 않는다.

## 18. input과 focus

우선순위:

```text
modal/flyout
→ active canvas tool
→ compare divider/HUD
→ viewport pan/zoom
→ shell shortcut
```

필수 키:

- `Enter`: 현재 적용 가능한 visible tool action 하나
- `Escape`: active tool 취소/정리
- `+`, `=`, `-`: zoom
- workflow-configured Before/After shortcut
- undo: 현재 focus context가 text input이 아니면 defect/develop command router

IME composing 중 key를 shortcut으로 가로채지 않는다. `SwapChainPanel` 대신 focusable host가 key event를
받고 pointer capture/lost-capture/deactivation을 coordinator에 전달한다.

## 19. resize와 lifecycle

처리할 event:

- XAML arrange size 변경
- DPI/composition scale 변경
- monitor 이동
- window minimize/restore
- device removed/reset
- frame selection/source revision 변경
- app suspend/close

0×0 또는 minimized size로 swap-chain buffer를 만들지 않는다. resize storm을 coalesce하고 마지막 size는
반드시 present한다. panel detach 순서:

1. 새 present 요청 차단
2. outstanding work 취소/flush 정책 실행
3. UI thread에서 `SetSwapChain(nullptr)`
4. swap-chain views/resources release
5. shared device는 다른 consumer가 없을 때 release

device lost 복구 후 동일 visible request를 재생성하되 이전 device의 token을 새 presenter에 전달하지 않는다.

## 20. 성능·품질 예산

계측 지점:

- engine result ready → compositor present
- texture handoff / copy count
- present queue latency
- resize latency
- zoom/pan input-to-photon
- overlay draw CPU/GPU time
- pixel sampler latency
- peak dedicated/shared VRAM
- device-lost recovery time

기본 목표 원칙:

- zero-copy 또는 one-copy presentation을 증명
- pan/zoom 중 UI thread long task 없음
- interactive proxy를 화면 device pixel보다 작게 만들어 업스케일 blur를 만들지 않음
- settled preview swap 때 texture/edge sharpness가 눈에 띄게 변하지 않음
- exact export는 canvas proxy와 분리
- Intel/AMD/NVIDIA/Qualcomm에서 같은 color/overlay semantics
- WARP/CPU fallback에서도 기능 누락 없음

## 21. 오류 상태

| 상태 | 표현/복구 |
|---|---|
| image 없음 | actionable empty/offline/loading 상태, 빈 검정 surface로 성공처럼 보이지 않음 |
| swap-chain attach 실패 | HRESULT 기록, canvas-level retry/diagnostic, app 전체 crash 금지 |
| device lost | 마지막 safe UI chrome + recovering state, resource 재생성 |
| unsupported color precision | 검증된 fallback 또는 정확한 제한 안내 |
| compare before stale/missing | loading/disabled, unrelated raw로 조용히 대체해 비교 의미 왜곡 금지 |
| overlay stale | overlay 숨김 + 재요청, 이전 warning 표시 금지 |
| source offline | cached thumbnail 가능, edit/export 제한과 Relink |

## 22. 접근성

GPU image 자체는 semantic tree가 아니므로 별도 accessible host가 다음을 제공한다.

- 현재 frame 이름과 Raw/Developed/Compare mode
- zoom percent와 fit/actual size commands
- compare before source와 divider percent
- active tool 이름, prompt, apply/cancel
- crop rect x/y/width/height percent와 move/resize actions
- sample readout text
- render/progress/error live status

custom curve/mask와 마찬가지로 시각 overlay만 제공하고 keyboard/UIA equivalent가 없으면 parity 실패다.
고대비에서는 dimming, divider, crop outline, mask preview가 구분되고 focus indicator가 canvas 위에서
사라지지 않아야 한다.

## 23. 테스트 매트릭스

자동화:

- coordinate round-trip property tests
- crop enter/apply/full/cancel/transform tests
- zoom/pan clamp at every DPI
- compare source fallback/stale revision tests
- divider pointer offset and UIA step
- tool mutual exclusion and Escape cleanup
- sampler transform/color-space tests
- device-lost lifecycle and `SetSwapChain(nullptr)`
- stale texture/session rejection

실제 UI/GPU:

- 100/125/150/200% DPI와 monitor 이동
- SDR, wide-gamut, HDR 가능 monitor를 분리 기록
- Intel iGPU, AMD, NVIDIA, Qualcomm ARM64, WARP
- mouse, precision touchpad, pen, keyboard, Narrator
- 24/60/100+ MP, portrait/landscape/extreme panorama
- panel resize/filmstrip resize 중 active render
- Compare + soft proof + clipping + zoom 조합

## 24. acceptance

- raw/developed/debug/compare가 올바른 revision texture를 표시
- fit/actual/zoom/pan과 HUD가 모든 DPI에서 일치
- split divider와 Before source가 pointer/keyboard/UIA로 동작
- crop 취소가 기존 crop을 bit-equivalent하게 복원
- 모든 tool이 상호 배타적이고 draft가 frame 사이로 새지 않음
- pixel sampler의 source coordinate와 transform 역변환이 fixture와 일치
- GPU presentation에 불필요한 full-frame readback이 없음
- device lost 후 app 재시작 없이 같은 frame을 복구 가능
- soft-proof/clipping overlay가 stale configuration에서 보이지 않음
- macOS와 Windows의 engine-buffer 및 visible-surface 비교 artifact가 연결됨
