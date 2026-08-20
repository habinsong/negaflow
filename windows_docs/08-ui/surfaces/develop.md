# Develop surface 이식 명세

기준일: 2026-08-04  
macOS 기준 커밋: `9be909c`  
소스 근거: `Features/Develop`, `Features/Canvas`, `Features/Workspace`, `Chromabase/Adjustments`

## 1. 역할과 동등성 범위

Develop는 한 장의 원본에 비파괴 현상 상태를 적용하고, 중앙 canvas에서 결과를 직접 확인하며,
history·copy/paste·filmstrip을 통해 여러 frame으로 작업을 이어가는 핵심 workspace다. Windows판의
동등성 대상은 inspector 모양만이 아니다.

- raw/developed 비교와 preview 갱신 순서
- film type·preset·base·tone·color·detail·geometry·local adjustment·defect recipe
- 도구 간 상호 배타성, 취소와 frame 전환
- slider keyboard·직접 숫자 입력·double-click reset
- undo boundary와 history snapshot
- stale render가 현재 frame에 적용되지 않는 ownership/revision 검증
- source offline, decode/render 실패, catalog recovery
- 좌우 panel·filmstrip·canvas와의 focus/selection 연동

Windows에서는 WinUI 3 shell과 C++ engine이 같은 `FrameId`, `DevelopRevision`, `SourceRevision`을
공유한다. UI가 값을 바꾸었다는 사실과 engine 결과가 현재 상태에 유효하다는 사실을 분리한다.

## 2. 진입과 기본 상태

진입 조건:

1. Library의 current interaction scope에 active frame이 있다.
2. active frame ID가 catalog에 존재한다.
3. source가 필요한 작업이면 source URL을 다시 해석할 수 있다.

복구 규칙:

- 저장된 active frame이 catalog에 있고 source도 사용 가능할 때만 복구한다.
- frame은 있으나 source가 offline이면 metadata/thumbnail 기반 surface를 표시하되 원본이 필요한
  develop/export 명령은 이유와 함께 disabled한다.
- active frame이 없으면 중앙에 구체적인 Library 이동/import 행동을 제시한다.
- catalog 자체가 blocked면 Develop 빈 상태를 띄우지 않고 shell 전체의 catalog recovery surface를 쓴다.

현재 inspector 기본값:

- 선택 tab: `Basic`
- 펼친 adjustment section: `Tone`
- 한 번에 펼치는 adjustment section: 최대 1개
- displayed image: `showDeveloped`가 true면 developed 우선, false면 raw preview 우선이며 각각 없으면
  다른 쪽을 fallback으로 사용한다.

## 3. 화면 구조

```text
┌───────────────┬──────────────────────────────────────┬───────────────────┐
│ Film sidebar  │ Canvas                               │ Develop inspector │
│               │                                      │ Histogram         │
│ stock/preset  │ image, overlays, active tool         │ 6-tab strip       │
│               │                                      │ tab tools         │
│               │                                      │ adjustment stack  │
├───────────────┴──────────────────────────────────────┴───────────────────┤
│ Filmstrip: current scope / selection / active frame / sort              │
└──────────────────────────────────────────────────────────────────────────┘
```

구조 원칙:

- 좌·우 panel width는 독립 저장하고 중앙 canvas 최소폭을 침범하지 않는다.
- inspector scroll은 canvas zoom/pan과 분리한다.
- histogram, tab strip, 현재 tab 도구, adjustment section 순서를 보존한다.
- Windows에서 모든 영역을 `Card`로 둘러싸지 않는다. 정보 위계를 구분하는 조용한 section surface와
  native separator를 기본으로 하고, 선택 상태가 필요한 segmented control만 track/thumb를 유지한다.
- 좁은 창에서도 도구 버튼 한 줄은 wrap하지 않는다. 필요한 경우 horizontal scroll/flyout으로
  기능을 보존한다.

## 4. inspector tab 계약

선언 순서와 의미:

| tab | tab 전용 내용 | 공통 adjustment sections |
|---|---|---|
| Basic | quick actions | 표시 |
| Base | base estimation/profile controls | 표시 |
| Edit | geometry + local dodge/burn | 표시 |
| Defects | Auto/Guided/Brush/Clone Stamp + defect layer | 표시 |
| Info | source metadata + app metadata overlay + roll record | 숨김 |
| Reset | reset all adjustments + photo angle reset | 표시 |

tab 전환 시 반드시 취소할 active interaction:

- crop
- defect brush
- region defect Auto/Guided
- clone stamp
- base picker
- local adjustment drawing session

`Basic` 이외 tab으로 이동하면 focused slider를 해제한다. 펼친 section에 더 이상 보이지 않는 focused
slider가 있으면 focus를 해제한다. BW가 아닌 film type으로 바뀌었는데 BW Toning이 펼쳐져 있으면
해당 section을 접는다.

WinUI 구현에서는 `TabView`를 그대로 쓰기보다 현재의 밀도 높은 icon tab strip을 `ItemsRepeater` 또는
동등한 단일선 selection control로 구현할 수 있다. 단, UI Automation에는 하나의 selection container와
6개 selection item으로 노출한다.

## 5. histogram

표시 가능한 raw/developed image가 있을 때 inspector 상단에 histogram을 표시한다. Histogram은 다음
계약을 갖는다.

- current displayed image를 source로 삼는다.
- image 또는 frame revision이 바뀌면 이전 sampling 결과를 폐기한다.
- UI thread에서 전체 원본 pixel을 동기 순회하지 않는다.
- histogram interaction으로 parameters가 바뀌면 동일한 develop scheduling 경로를 쓴다.
- raw/developed 전환 직후 이전 histogram이 새 상태로 보이는 것을 허용하지 않는다.
- high contrast에서 RGB 채널을 색만으로 구분하지 않고 label/legend 또는 pattern을 제공한다.

## 6. 공통 slider composite

현재 inspector slider는 `label + editable numeric value + slider`의 하나의 control이다. Windows판도
세 부분을 별개 tab stop으로 무분별하게 늘리지 않고 일관된 composite automation contract를 쓴다.

필수 interaction:

- pointer drag
- track 또는 thumb double-click reset(해당 slider에 reset value가 있을 때)
- 숫자 직접 입력 후 Enter/포커스 이동으로 commit
- `Left/Down` 감소, `Right/Up` 증가
- `Shift`와 arrow로 coarse step
- `Tab`/`Shift+Tab`으로 현재 펼친 section의 보이는 slider 순회
- interaction 시작 전 값을 undo baseline으로 잡고 drag 전체를 한 undo unit으로 commit
- 값 범위 clamp, NaN/Infinity 거부
- 현재 locale의 decimal separator와 부호를 허용하되 persistence/engine ABI는 locale-independent number

macOS 코드의 직접 입력은 dot decimal 중심이므로 Windows판은 `NumberFormatter`에 해당하는
locale-aware parser를 명시적으로 구현하고 `,` decimal locale을 회귀 테스트한다.

접근성:

- localized name, 현재 value, min/max, small/large change
- reset 가능 여부와 reset command
- disabled reason
- 값이 percent인지 signed scalar인지 degree인지 단위 노출
- UIA `RangeValue`를 기본으로 하며 editable field가 별도 노출될 경우 명확한 이름을 갖는다.

## 7. Basic quick actions

| 명령 | 표시/활성 조건 | 결과 |
|---|---|---|
| Auto Tone | displayed image가 있음 | frame tone parameter 계산 및 redevelop |
| Auto White Balance | displayed image가 있음 | warmth/tint 계산, batch-WB sync 조건 적용 |
| Auto Levels | inversion film에서만 표시 | persisted boolean 변경 후 redevelop |
| Auto Neutral Balance | inversion film에서만 표시 | persisted boolean 변경 후 redevelop |
| 개별 reset | 해당 자동 결과가 있음 | 해당 값만 원복 후 redevelop |

명령 중 계산이 비동기라면 `FrameId + request revision`을 완료 직전에 재확인한다. 실행 중 다른 frame으로
이동한 결과를 현재 frame에 적용하면 P0 결함이다.

## 8. adjustment sections

한 번에 하나만 펼치는 accordion이다. header에는 이름, expand/collapse, 해당 section reset을 둔다.
reset은 다른 section과 Geometry/Base를 건드리지 않는다.

### 8.1 Tone

- Exposure
- Contrast
- Highlights
- Shadows
- Whites
- Blacks
- Density

`Exposure`는 engine의 `DevelopToneRange.exposure`를 단일 진실로 쓴다. 나머지 현재 scalar 범위는
`-1...1`이다. Tone reset은 neutral preset을 선택하고 이 section 값만 기본값으로 되돌린다.

### 8.2 Tone Curve

region sliders:

- Highlights
- Lights
- Darks
- Shadows

point curve channel:

- RGB
- Red
- Green
- Blue

curve editor 계약:

- 비어 있는 저장 표현은 endpoint `(0,0)`, `(1,1)`의 identity curve로 해석한다.
- plot 클릭/drag로 point를 추가·이동한다.
- 내부 point를 double-click하면 삭제하며 endpoint는 삭제하지 않는다.
- 내부 x는 양쪽 이웃에서 최소 `0.01` 간격을 둔다.
- arrow nudge `0.01`, Shift nudge `0.05`.
- 이전/다음 point, point 추가/삭제, input/output percent를 키보드와 UIA로 노출한다.
- engine에 보내기 전에 x 정렬, endpoint, finite, channel별 point count/spacing을 검증한다.

### 8.3 Color

- Warmth
- Tint
- Vibrance
- Saturation
- Color Depth

현재 범위는 `-1...1`이다. Warmth/Tint 변경과 reset은 batch white-balance synchronization 설정이
켜진 경우 현재 batch에 동기화한다. 배치 적용 대상은 화면 선택 집합이 아니라 현재 코드의 batch
identity 규칙을 따른다.

### 8.4 Color Mixer

보기 mode:

- Hue
- Saturation
- Luminance
- All

색 band:

- Red, Orange, Yellow, Green, Aqua, Blue, Purple, Magenta

각 band의 H/S/L 값 범위는 `-1...1`이다. `All`은 같은 data를 동시에 보여주는 편집 방식이며 별도
parameter set가 아니다. 색 sample만으로 band를 식별하지 않고 localized 이름을 함께 표시한다.

### 8.5 Color Grading

zone:

- Shadows
- Midtones
- Highlights

각 zone은 hue/saturation color wheel과 luminance를 가진다. 공통 `Blending`, `Balance`를 둔다.
wheel은 pointer capture, keyboard 조정, numeric accessibility value를 모두 지원해야 한다. gamut 밖
표시는 UI preview와 engine result의 색공간을 혼동하지 않는다.

### 8.6 B&W Toning

`bwNegative` 또는 `bwPositive`에서만 사용할 수 있다.

- mode
- strength
- shadow hue
- highlight hue

mode를 `None`으로 바꾸면 toning state를 reset한다. 꺼진 상태에서 켤 때 strength는 현재값과 `0.45`
중 큰 값으로 시작한다. film type이 컬러로 바뀌면 펼친 section을 자동으로 접고, 숨겨진 값을 새
컬러 렌더에 적용하지 않는다.

### 8.7 Calibration

- Red Primary Hue/Saturation
- Green Primary Hue/Saturation
- Blue Primary Hue/Saturation

UI 값은 `CalibrationAdjust`의 실제 channel pair와 일치해야 한다. 단순한 세 개 scalar 요약으로
저장하지 않는다.

### 8.8 Detail / Effects

- Noise Reduction toggle
- Strength (`0.05...1`, enabled일 때만 표시)
- Luminance
- Color
- Dark Tones
- Detail
- Grain Protect
- Grain
- Sharpness
- Clarity
- Halation
- Vignette

Noise Reduction toggle을 켜면 현재 기본 strength `0.7`, 끄면 `0`이다. 세부 NR 값, Grain,
Sharpness, Halation은 현재 `0...1`; Clarity와 Vignette는 `-1...1`이다. UI hidden state가 engine에
임의 default를 덮어쓰지 않는다.

### 8.9 Debug

developer mode에서만 보인다.

- overlay enabled
- pipeline stage picker
- selected stage metrics

일반 release에 debug tab·shader path·내부 filesystem 경로가 노출되지 않아야 한다. debug overlay가
켜진 경우 stage metrics가 없으면 명시적인 unavailable state를 보여주고 stale 수치를 재사용하지 않는다.

## 9. Base tab

Base는 inversion film의 base estimation을 다룬다.

| mode | control | 동작 |
|---|---|---|
| Auto | mode selector | 측정 가능한 frame data에서 자동 추정 |
| Film/Preset | film stock, light source, scanner profile | 등록된 profile ID 사용 |
| Manual | picker, R/G/B slider | 직접 base RGB 설정 |

계약:

- inversion이 필요 없는 film에서는 mode control을 disabled한다.
- Manual로 처음 전환할 때 값이 없으면 `frame.baseRGB`, 그것도 없으면 현재 fallback
  `(0.90, 0.65, 0.45)`를 시작점으로 쓴다. 이 수치는 장치 정확도 증거가 아니라 UI 초기값이다.
- R/G/B는 `0...1`로 clamp하고 변경 즉시 mode를 Manual로 바꾼다.
- picker는 다른 모든 canvas 도구를 끄고, frame 전환·tab 전환·Escape에서 취소한다.
- Film/Preset에서 film stock을 해제하면 mode가 Auto로 돌아간다.
- auto-match scanner profile이 켜졌다면 film stock 변경 후 capability/registry 기준으로 profile ID를
  다시 계산한다.
- scanner profile 목록은 display name과 validation status를 함께 보여준다.
- 실측되지 않은 profile을 validated/device-accurate로 표현하지 않는다.
- 세 picker는 좁은 panel에서도 같은 가용 폭을 공유하고 오른쪽이 잘리지 않는다.

Windows에서는 native `ComboBox`/flyout을 사용한다. section header는 선택 불가능하고 option과 같은
UIA role로 노출하지 않는다.

## 10. Edit: Geometry

명령:

- Crop
- Rotate Left / Rotate Right
- Flip Horizontal / Flip Vertical
- Straighten Angle `-45...45°`
- aspect ratio + lock

aspect 후보:

```text
Original, Custom,
2:3, 3:2, 4:3, 3:4, 4:5, 5:4,
16:9, 9:16, 16:10, 10:16,
65:24, 24:65, 3:1, 1:3, 1:1
```

`Custom`은 `cropAspect = nil`, `Original`은 source orientation을 반영한 원본 종횡비다. Crop을 켜면
defect brush와 region defect를 끈다. Windows 구현은 clone/base/local adjustment까지 포함한 공통
`CanvasToolCoordinator`를 통해 항상 단 하나의 active tool만 허용한다.

각도는 editable `0.1°` 표시와 slider/dial을 제공하고 독립 reset을 둔다. Rotate/flip/crop은
`imageTransform`에 저장되며 Reset All Adjustments 대상이 아니다. 별도 Reset Photo Angle은 rotation과
straighten을 원복하되 crop/flip 범위는 macOS 동작을 소스 테스트로 고정한다.

## 11. Edit: Local Dodge/Burn

mask kind:

- Brush
- Radial
- Linear
- Polygon

mode:

- Dodge
- Burn

새 mask 기본값:

- amount `0.35`
- feather `0.20`
- brush thickness `0.04`

범위와 생성 조건:

| kind | 생성 조건 | 저장 핵심 |
|---|---|---|
| Brush | point 1개 이상 | strokes, thickness `0.005...0.25`, feather × 0.25 |
| Radial | start/end 2개 이상 | center, image-size 보정 radius ≥ 0.005, feather |
| Linear | start/end 거리 > 0.001 | start, end, feather |
| Polygon | point 3개 이상 | points, feather |

좌표는 normalized image space로 저장하고 crop/rotate/flip transform과의 변환을 한 곳에서 정의한다.
viewport pixel 좌표를 sidecar에 저장하지 않는다.

목록 행:

- 순번 + mask kind
- 선택
- enabled visibility
- copy/paste/delete
- 선택 항목 amount/feather 편집

paste는 새 UUID를 발급한다. slider drag 중 매 frame undo를 만들지 않고 시작 baseline부터 종료값까지
한 undo unit으로 등록한다. active drawing frame이 바뀌면 session을 취소한다. polygon의 미완성 point는
persistence하지 않는다.

## 12. Defects tab 연결

상세 계약은 `defects.md`에 둔다. Develop 수준의 공통 규칙은 다음과 같다.

- Auto, Guided, Brush, Clone Stamp는 상호 배타적이다.
- Auto를 켜면 전체 normalized ROI `(0,0,1,1)`로 즉시 region detect를 시작한다.
- Guided는 사용자의 ROI 입력을 기다린다.
- Auto↔Guided 전환 시 기존 region session을 먼저 취소/초기화한다.
- 각 tool에는 자신의 recipe만 reset하는 독립 reset이 있다.
- tool off/cancel과 recipe reset은 다른 동작이다.
- async detection/apply 결과는 frame ID, defect session ID, source/develop revision을 확인한 뒤 commit한다.
- RGB Software Defect Removal을 IR/Digital ICE와 동등하다고 표시하지 않는다.

## 13. Info tab

세 계층을 구분한다.

1. source metadata: EXIF/파일/스캐너가 제공한 읽기 전용 사실
2. app metadata overlay: 사용자가 보완·수정한 비파괴 metadata
3. roll record: 촬영/현상 workflow 기록

source metadata를 수정하거나 원본/third-party XMP에 기록하지 않는다. app-owned catalog/sidecar에만
overlay를 저장하고 source와 overlay의 provenance를 UI에서 구분한다. scanner frame header는 target과
process를, imported source는 가능한 경우 ISO/shutter/aperture/focal length를 요약한다.

## 14. Reset tab

`Reset All Adjustments`가 기본값으로 되돌리는 범위:

- preset와 tone/curve/color/mixer/grading/calibration/BW
- local dodge/burn
- detail/effects/noise reduction

제외:

- Geometry의 `imageTransform`
- Base mode/profile/manual base
- defect recipe
- source/app metadata
- history records

`Reset Photo Angle`은 별도 명령이며 현재 angle/rotation이 중립일 때 disabled다. Windows에서는 reset
범위를 confirmation copy 또는 help text로 명확히 하여 사용자가 원본/geometry까지 지워진다고
오해하지 않게 한다.

## 15. Film sidebar, preset과 film type

왼쪽 film sidebar는 slide와 negative preset 목록을 제공한다.

- 같은 emulation을 다시 선택하면 끈다.
- 처음 켤 때 정의된 기본 intensity를 사용한다.
- 다른 emulation으로 바꾸면 기존 intensity를 유지한다.
- intensity는 `0...1`.
- BW film type에서 BW toning이 활성화되고 컬러 전환 시 UI를 접는다.
- film type 변경은 base/profile/auto correction의 enabled 조건을 즉시 갱신한다.

film stock Dmin profile과 창작 film emulation을 하나의 picker로 합치지 않는다. 전자는 inversion base의
기술 데이터이고 후자는 creative look이다.

## 16. Copy/Paste와 batch sync

Develop settings paste scope:

- Base
- Tone
- Color
- Detail
- Geometry
- All

빈 scope 또는 copied settings가 없으면 Paste를 disabled한다. copied payload는 source frame 객체를
참조하지 않고 값 snapshot과 schema version을 가진다. scope별로 포함/제외되는 field를 테스트 manifest로
고정한다. Defect recipe와 metadata는 일반 Develop paste에 암묵적으로 포함하지 않는다.

Warmth/Tint의 batch sync는 사용자 설정이 활성일 때만 수행한다. 동기 대상과 실패 frame을 표시하고,
부분 실패 시 성공 frame까지 rollback하는지 유지하는지 정책을 명시한다.

## 17. History와 undo

History record는 다음 snapshot을 저장한다.

- `DevelopParameters`
- film type
- image transform
- preset ID

기록 label은 현재 순번 기반 localized 이름이다. 최신 record가 기본 선택이며 Apply는 현재 frame에
snapshot을 적용한 뒤 redevelop한다. snapshot compare 상태가 있었다면 우선 복구하고 서로 다른 frame이면
각 frame을 올바른 revision으로 다시 render한다.

History는 command undo stack과 다르다.

- undo/redo: 짧은 편집 상호작용의 역전
- history: 사용자가 명시적으로 남긴 named checkpoint
- version/virtual copy: 별도 catalog identity

Windows에서 세 개를 같은 stack UI로 합치지 않는다.

## 18. render scheduling과 stale-result 방지

권장 요청 envelope:

```text
DevelopRequest {
  FrameId
  SourceRevision
  DevelopRevision
  TransformRevision
  DefectRecipeRevision
  PreviewClass
  InteractionClass
  CancellationToken
}
```

slider drag 중에는 interactive preview를 coalesce하고 마지막 committed 값은 반드시 full preview를
요청한다. 결과 commit 조건:

```text
result.FrameId == active/requested FrameId
&& result.SourceRevision == frame.SourceRevision
&& result.DevelopRevision == frame.DevelopRevision
&& result.TransformRevision == frame.TransformRevision
&& result.DefectRecipeRevision == frame.DefectRecipeRevision
&& request is not cancelled
```

조건이 맞지 않으면 결과를 cache 후보로 보관할 수는 있어도 visible image/state에 적용하지 않는다.
UI thread에 decode, full histogram, full-resolution develop를 동기 실행하지 않는다.

preview 품질 저하는 명시적 interaction tier에서만 허용하고 release result는 동일 parameter/quality로
재생성한다. GPU vendor에 따라 결과 곡선·색·결함 recipe 의미가 달라지면 안 된다.

## 19. 오류·취소·복구

| 상태 | UI와 행동 |
|---|---|
| source offline | 기존 thumbnail/metadata 표시, Relink 제공, 원본 필요 명령 disabled |
| decode 실패 | frame-specific error + Retry/Relink, 다른 frame 작업은 유지 |
| render 실패 | 마지막 유효 preview를 오류 표식과 함께 유지하거나 명시적으로 비움; raw로 조용히 대체 금지 |
| GPU device lost | pending GPU work cancel, device/cache 재생성, 동일 요청 재시도 또는 CPU fallback 안내 |
| out of memory | preview tier 축소/타일링 재시도, export 품질 저하 금지 |
| cancelled | progress와 transient overlay 제거, committed params는 정책대로 유지 |
| stale result | 조용히 폐기하되 diagnostic counter 기록 |
| sidecar/catalog write 실패 | 저장되지 않음을 즉시 표시, 성공한 것으로 UI를 닫지 않음 |

## 20. 성능 예산과 계측

최종 숫자는 기준 장치 측정 후 잠그되 다음 stage를 독립 계측한다.

- UI input → parameter commit
- request queue wait/coalescing
- source materialization/decode
- CPU preprocess
- GPU upload
- develop kernels
- defect/local mask
- readback 또는 Direct2D presentation
- histogram/overlay
- cache/persistence

최소 class:

- 24 MP interactive slider
- 45–60 MP zoom/pan과 adjustment
- 100+ MP scan tile preview
- x64 Intel/AMD CPU-only 또는 WARP fallback
- ARM64 Qualcomm native
- Intel/AMD/NVIDIA/Qualcomm GPU

평균만 보지 않고 P50/P95/P99, input queue starvation, dropped/coalesced request, peak working set,
dedicated/shared video memory budget를 기록한다. 품질·해상도·ICC를 몰래 낮춰 목표 시간을 만들지 않는다.

## 21. 접근성·키보드·고대비

- tab strip: Selection/SelectionItem
- accordion header: ExpandCollapse + reset Invoke
- slider: RangeValue
- curve point/wheel/canvas overlay: keyboard equivalent와 custom localized value
- active tool: selected/active state, 사용 방법과 Escape 취소 hint
- disabled command: 접근 가능한 설명
- progress/error: polite/assertive live region을 중요도에 맞게 사용
- 색 channel·mask·warning을 색만으로 전달하지 않음
- 200% text scale에서 label/value/control 겹침 없음
- high contrast에서 selection outline과 focus visual 보존
- Narrator scan mode와 app shortcut가 충돌하지 않게 실제 장치에서 확인

## 22. 자동화 ID

stable ID 예:

```text
develop.histogram
develop.tabs.basic
develop.tabs.base
develop.tabs.edit
develop.tabs.defects
develop.tabs.info
develop.tabs.reset
develop.section.tone
develop.slider.exposure
develop.curve.rgb
develop.base.mode
develop.geometry.crop
develop.local.mask.brush
develop.defects.auto
develop.reset.adjustments
```

localized label이나 XAML class 이름을 ID로 사용하지 않는다. frame/list item ID는 stable prefix + catalog
UUID로 구성하고 recycle 시 갱신한다.

## 23. 동등성 acceptance

P0/P1 acceptance:

- 6개 tab의 표시·disabled·취소 규칙이 macOS 기준과 일치
- 모든 section parameter와 reset scope가 round-trip
- slider drag·키보드·직접 입력이 같은 값과 한 undo boundary를 만듦
- curve, color wheel, crop, local mask를 mouse/keyboard/Narrator로 조작 가능
- frame/tab/tool 전환 후 이전 overlay·async 결과가 새 frame에 적용되지 않음
- Base/profile validation state와 inversion 조건 일치
- Reset All이 Geometry/Base/Defect를 건드리지 않음
- offline/render/device-lost/sidecar-failure가 조용한 fallback 없이 복구 가능
- x64/ARM64와 4개 GPU vendor tier에서 동일 fixture의 품질 허용오차 통과
- macOS/Windows golden workflow artifact와 승인된 platform delta가 연결됨

## 24. 구현 순서

1. immutable frame/develop state와 revision request contract
2. raw/developed canvas + histogram read-only
3. Basic scalar sections와 reset/undo
4. Base/profile와 film sidebar
5. curve/mixer/grading/BW/calibration/detail
6. geometry와 transform-aware canvas
7. local adjustments
8. defects integration
9. metadata/history/copy-paste/batch
10. keyboard/UIA/localization/high-contrast
11. cross-vendor performance·quality·recovery gate

UI를 먼저 완성한 뒤 engine을 연결하는 방식은 금지한다. 각 vertical slice는 같은 parameter를
persistence → engine → visible result → export까지 재현해야 한다.
