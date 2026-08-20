# Print workspace 이식 명세

기준일: 2026-08-04  
macOS 기준 커밋: `9be909c`  
소스 근거: `Features/Print`, `Features/Export`, `Chromabase/Export/Print*`  
공식 근거: [Print from your app](https://learn.microsoft.com/en-us/windows/apps/develop/devices-sensors/print-from-your-app),
[Customize the print preview UI](https://learn.microsoft.com/en-us/windows/uwp/devices-sensors/customize-the-print-preview-ui),
[IPrintManagerInterop::GetForWindow](https://learn.microsoft.com/en-us/windows/win32/api/printmanagerinterop/nf-printmanagerinterop-iprintmanagerinterop-getforwindow),
[Windows Color System profile management](https://learn.microsoft.com/en-us/windows/win32/wcs/profile-management-functions),
[Windows Color System API](https://learn.microsoft.com/en-us/windows/win32/api/_wcs/)

## 1. 제품 경계

현재 macOS `Print`는 운영체제 spooler에 직접 job을 보내는 기능이 아니다. 선택한 사진을 실제 종이
치수와 DPI로 합성해 JPEG·PNG·TIFF 산출물로 내보내는 전문 layout workspace다. Windows 1차판은 이
범위를 그대로 이식한다.

```text
필수 1차 범위
  사진 선택 → 지면/패키지 구성 → 색관리 preview → 파일 export

독립적인 후속 범위
  구성된 page → Windows print dialog → 실제 printer spooler
```

직접 인쇄를 1차 범위에 섞지 않는 이유:

- 현재 제품의 동등성 기준은 file export까지다.
- printer media, printable area, driver color management, spooler cancel은 별도 상태 공간이다.
- 정확한 printer ICC와 이미 색변환된 raster를 driver가 다시 변환하는 double-management 위험이 있다.
- Microsoft가 현재 안내하는 WinUI 경로는 `PrintManagerInterop` + `PrintDocument`이며, page 설정이
  바뀔 때마다 `Paginate`가 다시 호출된다. 기존 deterministic raster transaction과 수명주기가 다르다.
- 지원 중단 가능성이 명시된 `StartXpsPrintJob`을 새 제품의 기반으로 삼지 않는다.

따라서 UI에 `Print`라는 이름이 있어도 1차 기능의 주 행동은 `Export`다. 직접 인쇄를 추가할 때는
`Direct print` feature flag와 별도 설계·검증 gate를 둔다.

## 2. 화면 구조

```text
┌──────────────────┬──────────────────────────────────┬──────────────────────┐
│ Files / Export   │ paper canvas                     │ Print inspector      │
│                  │                                  │ Layout / Content /   │
│ library source   │ single page or vertical pages    │ Output               │
│ export settings  │ package pages + page selector    │                      │
├──────────────────┴──────────────────────────────────┴──────────────────────┤
│ optional filmstrip / shared workspace status                              │
└────────────────────────────────────────────────────────────────────────────┘
```

좌측 sidebar:

- `Files`: 현재 Library source tree와 selection context
- `Export`: 일반/Quick Export 설정과 batch/package progress
- 현재 active frame의 compact display name

우측 inspector:

- 상단 현재 frame 이름
- `Layout`, `Content`, `Output` tab
- single-image 계열에서는 의미 없는 `Content` tab을 숨김
- package 계열에서는 세 tab을 모두 노출

중앙 canvas:

- 단일 선택: 한 장의 종이와 이미지
- 다중 선택 + individual-page layout: 사진마다 한 장, 세로 lazy stack
- package layout: page 단위 합성 preview와 `current / total` navigation
- background context menu, zoom HUD, ruler를 shared canvas 규칙과 일치시킴

화면을 카드 모음처럼 만들지 않는다. inspector의 ordinary input/action은 rest 상태에서 조용하게 두고,
선택 상태가 필요한 segmented control만 track/thumb를 유지한다. control 높이는 약 30 DIP, 설명·값은
`Callout` 계열을 기본으로 한다. label에 `...` 또는 `…`를 붙이지 않는다.

## 3. layout mode 계약

표시 순서와 의미는 다음을 보존한다.

| mode | source 소비 | page 구성 | 표현 변환 |
|---|---:|---|---|
| Single Image | page당 1장 | 선택 수만큼 page | standard |
| Contact Sheet | grid | rows × columns로 pagination | standard |
| Picture Package | template slot | template capacity로 pagination | standard |
| Custom Package | 사용자 cell | item의 `pageIndex` | standard |
| Cyanotype | page당 1장 | 선택 수만큼 page | blue false-color monochrome |
| Glass Plate | page당 1장 | 선택 수만큼 page | monochrome invert |
| Gelatin | page당 1장 | 선택 수만큼 page | monochrome |

`Cyanotype`, `Glass Plate`, `Gelatin`은 측정 기반 재료·공정 simulation이라고 표현하지 않는다. 현재
구현은 고정된 시각 표현이며 export와 preview에 동일하게 적용하는 presentation style이다.

mode 변경 시:

1. 현재 mode별 sheet color를 복원한다.
2. contact geometry를 현재 종이·방향·margin에 맞게 normalize한다.
3. package preview revision을 올리고 stale page를 폐기한다.
4. individual-page mode로 이동하면 `Content` tab을 닫고 `Layout`으로 이동한다.
5. canvas zoom/pan을 fit 상태로 되돌린다.

## 4. 용지와 단일 이미지 composition

### 4.1 paper size

정확히 지원할 목록:

- Photo ratio: 긴 변 254 mm, active photo 비율 사용; 비율이 없으면 3:2
- 3.5 × 5, 4 × 6, 5 × 7, 8 × 10, 10 × 12, 11 × 14, 12 × 18 in
- 16 × 20, 20 × 24, 20 × 30, 24 × 36 in
- Letter 8.5 × 11 in, Tabloid 11 × 17 in, A3+ 13 × 19 in
- A6, A5, A4, A3, A2, A1
- B6, B5, B4, B3, B2, B1

치수 truth는 localized label이 아니라 engine의 mm 값이다. Windows locale에 따라 label의 소수점과
단위 표시만 바꾸되 stored value와 pixel 계산은 바꾸지 않는다.

### 4.2 orientation

- `Automatic`: single page에서는 source aspect, contact sheet에서는 columns ≥ rows 여부로 결정
- `Portrait`
- `Landscape`

`Automatic`은 printer driver의 자동 방향과 다른 Negaflow composition 규칙이다. 직접 인쇄 기능을
추가해도 driver가 다시 회전하지 못하도록 page orientation과 raster orientation을 일치시킨다.

### 4.3 geometry

```text
pixelsPerMM = dpi / 25.4
canvasPixels = round(pageMM * pixelsPerMM)
contentRect = canvasRect inset marginMM * pixelsPerMM
imageRect = aspect-fit(source, contentRect)
```

유효 범위:

- margin: 0–50 mm
- DPI: 72–600
- content width/height: 각각 1 pixel 초과
- 모든 source/page 수치: finite, positive, overflow-safe

preview는 DIP에 맞춘 축소 표현이지만 layout truth는 동일한 mm → pixel 함수에서 얻는다. WinUI
`ActualWidth`를 final export 계산에 사용하지 않는다.

### 4.4 35 mm perforation

single-image composition에서 `None` 또는 `35 mm`를 선택한다. 35 mm 경로는 현재 다음 고정 geometry를
재현한다.

- 물리 strip: frame pitch 38 mm × film width 35 mm
- image gate: 24 × 36 mm
- KS-1870 perforation pitch: 4.75 mm
- 한 rail당 8개, 양쪽 합계 16개
- hole: 2.79 × 1.98 mm, orientation에 따라 회전
- rail center offset: 2.75 mm
- corner radius: film scale 기준 0.51 mm

package mode에서는 perforation을 강제로 `None`으로 만든다. 저장된 inspector 값과 실제 package recipe의
effective value를 구분해 manifest에 기록한다.

## 5. 지면·ruler·surface preview

Layout controls:

- layout mode + paper size를 같은 행의 동일 너비 field로 배치
- orientation 3-way segment
- margin slider + 직접 숫자 입력
- ruler on/off segment; on일 때 inch/cm 선택
- sheet color: black/gray/white segment
- surface: glossy/matte/lustre/silk popup
- layout template apply/save/delete

ruler는 preview guide이며 export raster에 들어가지 않는다. tick은 실제 page points/mm와 연결하고, zoom
변화가 있어도 수치 의미는 유지한다.

paper surface overlay도 preview affordance다. 측정된 BRDF나 조명 환경을 재현하지 않으므로
`glossy/matte/lustre/silk appearance preview`로만 설명한다. surface 선택은 현재 recipe identity에는
포함되지만 표준 export의 pixel 변환 근거로 사용하지 않는다.

black/gray/white sheet color는 실제 composite background이며 export에 포함된다. ICC paper-white
simulation과 흰 sheet background가 동시에 활성화되면 preview paper white는 simulation 값을 쓰되,
export에서 시뮬레이션 색을 bake하는지 여부는 output process 규칙을 따른다.

## 6. Contact Sheet

기본값:

- 7 rows × 6 columns
- horizontal/vertical spacing 2 mm
- Fit
- rotate to fit off
- repeat one photo per page off
- normalize orientation off
- background black
- caption none

범위:

- rows/columns: 각각 1–12
- spacing: 각각 0–25 mm, 0.5 mm step
- per-image caption height: 0–20 mm

geometry normalization:

- 최소 image cell width/height는 0.5 mm로 둔다.
- per-image caption을 쓰면 cell height에서 caption height와 최소 image height를 확보한다.
- paper·orientation·rows·columns가 바뀌면 허용 가능한 최대 margin과 spacing을 다시 계산한다.
- 값이 범위를 벗어나면 clamp하고 preview와 persisted setting을 동일하게 갱신한다.
- UI에서 valid로 보여도 engine이 다시 검증한다.

source pagination:

- 기본: grid capacity만큼 순서대로 소비
- `repeat one photo per page`: 첫 source를 각 cell에 반복한 page 구성
- 해당 반복 option은 다음 앱 실행 시 강제로 off로 시작한다. 이전 선택이 사라진 듯 보이는 상태를 막는다.
- `normalize orientation`: frame metadata 자체를 변경하지 않고 sheet 배치에서만 quarter-turn을 적용

39장 검증은 기본 7 × 6에서는 1 page지만, 6 × 5에서는 2 page가 되어야 한다. 이 두 경우를 모두
performance/semantic fixture로 둔다.

## 7. Picture Package

template:

- `One Large + Two Small`: page당 3 slot
- `Two Up`: page당 2 slot
- `Four Up`: page당 4 slot

공통 설정:

- horizontal/vertical spacing
- Fit/Fill
- rotate to fit
- normalize orientation
- caption/crop marks

slot rectangle은 normalized constant에서 계산하고, DPI는 rasterization 단계에만 적용한다. source가 slot
수보다 많으면 다음 page로 이동한다. source가 부족하면 빈 slot을 그리지 않고 지면 background를 유지한다.

## 8. Custom Package

제한:

- custom item 최대 128개
- page 최대 32개, index 0–31
- custom caption 최대 32개
- caption text 최대 UTF-8 512 bytes
- font family name 최대 UTF-8 256 bytes
- page index 집합은 0부터 최고 page까지 연속
- normalized rect는 각 성분 finite, width/height > 0, page 경계 내부
- z-index는 음수 금지

item별 편집:

- source photo
- 1-based 표시 page 번호
- Fit/Fill
- rotate to fit
- X/Y/Width/Height normalized value
- send backward / bring forward
- duplicate / delete

canvas interaction:

- pointer drag로 이동
- corner/edge handle로 resize
- keyboard arrow 1-step, Shift+arrow coarse-step
- page boundary clamp
- selected cell의 z-order와 inspector index를 혼동하지 않음
- drag 도중 preview-only state, pointer release에서 하나의 undo/persistence transaction
- Escape는 drag 전 geometry 복원

여러 사진을 선택한 뒤 기본 1-cell package를 처음 열면 정사각에 가까운 grid로 자동 배치한다. 이미 사용자가
수정한 package에는 이 초기화가 개입하지 않는다.

coordinate 계약:

- persisted package rect: content rect 기준, normalized, 좌하단 원점
- persisted custom caption rect: 전체 paper 기준, normalized, 좌하단 원점
- WinUI pointer coordinate: canvas 기준, 좌상단 원점
- export raster: pixel 기준, 좌상단 또는 shader texture convention을 한 번 명시적으로 정규화

변환은 공유 geometry module 한 곳에서 수행하며 UI와 exporter가 서로 다른 y-flip 구현을 갖지 않는다.

## 9. Content와 caption

package Content tab:

- non-custom: Fit/Fill, rotate to fit
- caption: None, File name, Frame number, Sequence number, Rating, Custom text
- font family
- alignment: Left/Center/Right
- custom text mode: 여러 caption의 text/rect/alignment
- crop marks on/off

caption truth:

- file name은 source URL의 last path component
- frame number는 catalog frame number
- sequence는 선택 순서 기준 1부터 시작
- rating은 current snapshot 값
- custom caption은 recipe에 저장된 text

macOS의 기본 `Helvetica`를 Windows에서 존재한다고 가정하지 않는다. persisted value는 family name으로
유지하되 다음 순서로 resolve한다.

1. recipe family가 설치되어 있으면 사용
2. 없으면 app-defined portable fallback인 `Arial` 또는 `Segoe UI` 중 metrics fixture가 승인한 family 사용
3. 실제 resolved family를 manifest에 기록하고 UI에 대체 사실 표시

font enumeration은 background에서 하고 UI thread에 family list snapshot만 전달한다. font가 export 중
설치/삭제되어도 시작 시점의 resolved font identity를 고정한다.

crop mark length model의 유효 범위는 1–10 mm다. 현재 UI는 on/off만 노출하더라도 engine과 template는
length를 보존한다. marks는 image content가 아니라 page foreground로 render하며 dark sheet에는 light
foreground를 쓴다.

## 10. Output process와 색관리

### 10.1 Standard

- 일반 printer output profile을 사용
- `developTarget == print`인 source가 하나라도 있으면 valid RGB printer-class ICC가 필수
- profile이 없거나 파싱되지 않으면 export action을 disable하고 이유 표시
- Raw Scan TIFF에는 print composition/profile을 적용하지 않고 일반 raw export 경로로 보냄

### 10.2 C-Print

special delivery workflow:

- lab name
- paper name
- paper surface
- proof ICC profile (`.icc`, `.icm`)
- preview on/off
- advanced: delivery color space, paper simulation, gamut warning

안전한 persistence:

- lab, paper, surface, valid proof profile은 기억 가능
- output process 자체는 앱 재시작마다 `Standard`
- invalid/stale profile bytes는 복원하지 않음
- profile이 없으면 proof preview를 on으로 만들 수 없음
- C-Print가 활성화된 export recipe에는 lab/paper/surface/profile SHA-256을 기록

`C-Print`를 특정 lab/paper의 측정 정확도라고 광고하려면 실제 제공 profile과 출력 측정이 있어야 한다.
generic surface overlay 또는 profile 이름만으로 device-accurate라고 표현하지 않는다.

### 10.3 Windows color pipeline

Windows engine은 다음을 분리한다.

```text
working image
  ├─ display branch: display profile + optional proof + gamut overlay
  └─ export branch: exact selected output ICC + encoder embed
```

- WCS/ICM으로 ICC를 open하고 RGB printer/output class·PCS·tag 구조를 검증한다.
- profile bytes와 SHA-256을 snapshot에 복사한다. 경로만 저장하지 않는다.
- WCS가 profile을 열 수 있다는 사실과 macOS ColorSync와 픽셀 결과가 같다는 사실은 다르다.
- ColorSync golden fixture와 Windows output을 ΔE/round-trip 기준으로 비교해 rendering intent,
  black-point compensation, alpha 처리 계약을 확정한다.
- printer driver color management와 app color management 중 정확히 하나만 최종 변환을 소유한다.

## 11. Preview pipeline

preview는 page geometry와 source develop revision에 대한 lightweight proxy다.

cache key 최소 구성:

- ordered source IDs + source revisions
- develop revisions + defect recipe revisions
- layout mode + composition settings hash
- package settings hash
- display/proof profile hash + proof options
- page index + scale bucket

규칙:

- visible page와 인접 page를 우선 준비한다.
- 여러 individual pages는 `ItemsRepeater`/가상화된 list를 사용한다.
- package page는 필요한 source만 준비하며 같은 source proxy를 page 간 공유한다.
- preview가 없을 때 thumbnail을 layout용 placeholder로 쓸 수 있지만 final export에는 절대 사용하지 않는다.
- completion 직전 `WorkspaceId`, ordered source IDs, revision, page key를 다시 비교한다.
- stale completion은 cache에 넣지 않거나 현재 UI에 적용하지 않는다.
- layout edit 중에는 저해상도 interactive preview, settle 뒤 full preview를 생성한다.

canvas zoom HUD는 shared canvas와 동일한 20–1200% internal clamp를 쓰고, fit과 actual size 행동을 제공한다.
여러 individual pages를 세로 scroll할 때 drag-pan을 비활성화하여 gesture 충돌을 막는다.

## 12. Export transaction

Print export도 [Export surface 명세](./export.md)의 immutable snapshot과 transaction을 그대로 사용한다.

package 시작 순서:

1. selection·format·settings·naming·profile 검증
2. expected page count 계산, 1–32 확인
3. 모든 output path를 충돌 없이 reserve
4. preview task cancel
5. source materialization과 original identity capture
6. frame ownership/revision을 확인하며 immutable snapshot 생성
7. page별 필요한 source proxy를 final resolution으로 준비
8. app-owned staging directory에 page raster encode
9. file/header/profile/source identity read-back validation
10. 모든 page가 검증된 뒤 journal state를 publish-ready로 전환
11. page set을 final path로 publish
12. contributor event를 catalog transaction으로 commit
13. journal과 owned staging cleanup

부분 성공을 성공으로 표시하지 않는다. page 1이 final path에 있고 page 2가 실패한 상태에서는 전체 package
transaction을 복구 또는 rollback 대상으로 남긴다.

page name은 base name 뒤에 deterministic page suffix를 붙인다. 기존 output과 source path는 덮어쓰지
않고 unique artifact set 전체를 미리 예약한다.

## 13. 메모리·성능 정책

page source 준비는 무제한 병렬화하지 않는다.

- 1차 기본: page 단위 직렬, 한 page 안 source preparation 최대 2개
- source proxy는 slot에 필요한 최대 raster size까지만 decode/develop
- 같은 source가 여러 slot에 반복되면 한 번 준비하고 재사용
- source byte estimate는 pixel dimensions × format bytes-per-pixel을 overflow-safe 계산
- page별 source raster budget과 final page budget을 별도로 검사
- final canvas가 GPU texture limit을 넘으면 CPU tiled composite + streaming encoder 사용
- GPU readback은 tile/ring staging으로 겹치되 output order를 고정
- memory pressure가 높으면 concurrency를 1로 내리고 preview cache부터 회수
- DPI·quality·bit depth·ICC를 낮춰 성능 수치를 만들지 않음

필수 성능 시나리오:

| fixture | 경로 | 관찰값 |
|---|---|---|
| 39 loaded photos | Single Image | first-page 준비, 39-page export, progress |
| 39 loaded photos | 7 × 6 Contact Sheet | 1-page composite, peak memory |
| 39 loaded photos | 6 × 5 Contact Sheet | 2-page pagination, transaction |
| 39 virtual sources | Picture Package | scheduling/metadata overhead |
| one source repeated | Contact Sheet repeat | source reuse, no redundant develop |
| A1 600 DPI | single/package | texture limit, tiled fallback |
| 32 custom pages | Custom Package | page cap, cancel/recovery |

모든 시나리오는 일반 Export와 Quick Export, 좌측 Output tab과 toolbar/command 경로를 각각 확인한다.
first-file preparation과 encoder 처리 시간을 따로 계측한다. 0% 원형 spinner만 보이지 않도록 다음 phase를
텍스트와 determinate progress로 표시한다.

```text
Preparing sources 3 / 39
Rendering page 1 / 2
Encoding page 1 / 2
Verifying outputs 1 / 2
Publishing package
```

## 14. 취소·실패·복구

취소 point:

- source materialization 전후
- 각 source develop tile 사이
- page render tile 사이
- encoder frame/page 사이
- publish 직전

publish 이후 cancel은 destructive rollback을 즉시 시도하지 않는다. journal state를 기준으로 완료 또는
복구 가능한 상태를 판정한다.

구체적인 오류 surface:

- source offline/changed
- cleaned raw/defect result unavailable
- invalid layout or page cap exceeded
- invalid/missing output ICC
- unsupported encoder pixel format/profile embed
- raster memory budget exceeded
- destination unavailable/collision
- staged output validation failed
- publish/rollback/catalog commit failed

상태 메시지는 실패한 source/page와 재시도 가능 여부를 포함하고, 다음 실행 가능한 행동(`Relink`,
`Choose profile`, `Reduce paper/DPI`, `Retry failed export`, `Open folder`)을 제시한다.

## 15. 직접 인쇄 후속 설계

직접 인쇄를 승인한 뒤의 Windows-native 경로:

1. 현재 window의 HWND를 `WindowNative.GetWindowHandle`로 얻음
2. `PrintManagerInterop.GetForWindow(HWND)`로 window-scoped manager 등록
3. `Microsoft.UI.Xaml.Printing.PrintDocument`의 `Paginate`, `GetPreviewPage`, `AddPages` 연결
4. `PrintManagerInterop.ShowPrintUIForWindowAsync(HWND)`로 system print UI 표시
5. `PrintTask.Completed`에서 failed/canceled/submitted 상태 처리
6. page를 떠날 때 모든 event handler 해제

Microsoft 공식 문서상 등록은 현재 표시된 page/window마다 해야 하며 해제하지 않고 돌아오면 예외가 날 수
있다. `ShowPrintUIForWindowAsync` 전 `IsSupported`를 확인하고 예외를 사용자에게 표시한다.

driver 설정 변경으로 `Paginate`가 반복 호출되므로:

- page description/media/printable area를 새 snapshot으로 만든다.
- layout hash가 같으면 이미 만든 raster를 재사용한다.
- UIElement tree를 final color rasterizer의 truth로 사용하지 않는다.
- printer option은 `StandardPrintTaskOptions`의 media size/type, orientation, quality 등 지원 capability만
  노출한다.
- spooler에 넘긴 뒤의 완료는 물리 출력 완료와 같다고 표현하지 않는다.

Print Support App은 printer 제조사/virtual-printer 통합용이다. Negaflow 자체의 일반 direct-print
client를 만들기 위해 PSA나 custom driver를 개발하지 않는다.

## 16. 접근성·입력·localization

- inspector tab은 이름+아이콘, selected state, 위치 정보를 노출
- segmented option은 group label과 option selected state 제공
- slider는 label, 값, 단위, min/max와 keyboard increment 제공
- editable number는 locale decimal separator를 받되 저장은 invariant number
- custom cell/caption accordion은 expanded/collapsed 상태 제공
- canvas cell은 `Cell N, Page M, Source name, selected`로 automation peer 제공
- drag/resize의 모든 행동을 keyboard와 inspector numeric fields로도 수행 가능
- zoom과 page navigation은 focus가 보이고 accelerator와 충돌하지 않음
- black/gray/white sheet나 gamut overlay만으로 상태를 전달하지 않음
- long localized label에서도 paired rows는 실제 50/50 column을 유지하고, 필요한 경우 label wrap/tooltip을
  사용하되 control을 다음 행으로 임의 밀지 않음
- button row는 좁은 폭에서도 wrap하지 않고 horizontal scroll/flyout으로 보존

font, inch/mm, paper name은 번역 가능하지만 format 이름, ICC, DPI, 파일 경로와 profile 이름은 기술 문자열로
취급한다.

## 17. 저장과 recipe identity

workspace preference:

- paper size, orientation, margin
- perforation, layout mode, mode별 sheet color
- package settings, paper surface
- ruler visibility/unit
- C-Print lab/paper/profile/options

session-only 또는 startup reset:

- output process → Standard
- repeat one photo → off
- selected inspector tab
- selected custom item/caption/page
- zoom/pan
- in-flight preview/export state

recipe identity 최소 구성:

- complete export settings
- effective composition and package settings
- resolved layout/presentation mode
- output profile SHA-256
- C-Print lab/paper/surface/proof profile SHA-256
- resolved font identity
- renderer/schema versions

JSON decode 후 모든 범위·rect·page contiguity를 재검증한다. invalid persisted value는 부분 적용하지 않고
안전한 default와 복구 알림을 사용한다.

## 18. parity 검증 표

| 항목 | semantic fixture | visual/interaction fixture |
|---|---|---|
| paper | 모든 size의 mm/pixel, 3 orientation | label·aspect·margin |
| perforation | 16 holes, gate/strip geometry | landscape/portrait overlay |
| presentation | pixel golden, preview/export 동일 | cyanotype/glass/gelatin 표시 |
| contact | page count, grid/spacing/caption | 39장 7×6/6×5 |
| picture | slot geometry, pagination | 세 template |
| custom | rect/y-flip/z/page validation | drag/resize/keyboard/undo |
| caption | text source/font fallback/alignment | dark/light sheet 대비 |
| proof | profile validation/hash/transform | paper simulation/gamut overlay |
| transaction | stage/verify/publish/recovery | progress/cancel/retry |
| accessibility | automation tree/action | 100/150/200% text scale |

화면 캡처는 최소 1280×720, 1440×900, 1920×1080, 4K 150/200% scaling에서 비교한다. 실제 equal
segmentation, 한 줄 action row, ruler alignment, custom handle hit target, page virtualization을 pixel과
Computer Use로 확인한다.

## 19. 구현 완료 gate

- [ ] macOS 모든 layout mode와 paper size가 Windows recipe/schema에 매핑됨
- [ ] mm geometry와 orientation golden tests 통과
- [ ] preview와 export가 같은 layout truth 사용
- [ ] custom package coordinate/y-flip/z-order fixture 통과
- [ ] caption/font fallback이 deterministic하고 manifest에 기록됨
- [ ] print-target export가 exact validated ICC 없이는 시작되지 않음
- [ ] WCS와 ColorSync color fixture 허용 오차 통과
- [ ] package 32-page/resource caps와 malicious JSON 검증 통과
- [ ] 39장 single/contact/picture scenario에서 품질 저하 없이 목표 성능 충족
- [ ] failure injection 후 partial output을 성공으로 보고하지 않음
- [ ] crash recovery가 app-owned staging만 처리함
- [ ] keyboard·Narrator·high contrast·text scaling 검증
- [ ] 직접 인쇄는 별도 승인 전 제품 UI에 노출하지 않음

## 20. 남은 조사

- 실제 Windows encoder별 ICC embedding/read-back byte 동등성
- WCS transform과 ColorSync golden의 허용 ΔE 기준
- DirectWrite font fallback이 page break/line metrics에 미치는 차이
- GPU texture cap을 넘는 A1/B1 600-DPI composite의 tile seam 검증
- system print dialog에 넘길 때 app-managed ICC와 driver-managed color의 사용자 선택 모델
- IPP/class driver, vendor V3/V4 driver별 printable-area와 borderless 실물 검증
- 39장 실제 사진·대형 virtual batch의 x64/ARM64 peak working set과 first-progress latency
