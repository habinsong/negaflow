# 03 — GrainMend 화면 1:1

macOS 원본: `Sources/negaflowApp/Features/Defects/` (46개 파일, 6,417줄).

## 0. 스크린샷 상황

`negaflow_mac_screenshot/` 에 있는 것:

| 파일 | 담긴 것 |
|---|---|
| `develop_right_grainmend_panel.png` | **인스펙터 카드만** — 제목 + 도구 4개(자동/가이드/브러시/복제 도장) + 각 도구의 ↺ |

**검출 중에만 뜨는 캔버스 캡슐·종류별 칩·브러시 바·복제 바는 어느 스크린샷에도 없습니다.**
그 부분은 Swift 코드만으로 옮기고, 옮긴 뒤 **사용자에게 화면을 보여 확인받습니다.**
(이번 세션에 캡슐을 코드만 보고 만들어 모양이 어긋났습니다.)

## 1. 인스펙터 카드 — 맞음

스크린샷과 대조 완료. 도구 4개 + ↺, 검토 줄 없음. Windows 도 같습니다(`a611ebf` 에서
민감도·미세입자·제거·취소를 카드에서 캔버스 캡슐로 옮김).

## 2. 캔버스 캡슐 — `RegionDefectOverlay.swift` (302줄)

### 2.1 배치

```
ZStack {
  RegionPreviewCanvas(...)          // 분류색 점
  RegionROIGestureLayer(...)        // ROI 드래그 + 탭 토글
  VStack {
    controlBar                       // 위 가운데
    Spacer()
    if defectActive && !isDetecting && !preview.isEmpty { classChipsBar }   // 아래 가운데
  }.padding(.vertical, 12)
}
```

### 2.2 컨트롤 바 (`HStack(spacing: 10)`, `padding(.horizontal 12, .vertical 8)`, 캡슐)

순서대로:

| 요소 | macOS | Windows 현재 | 할 일 |
|---|---|---|---|
| scope 아이콘 | `Image(systemName:"scope").foregroundStyle(.red)` | FontIcon E7A8 빨강 | **모양 확인 — 지금 빨간 덩어리로 보임** |
| 검출 중 | `ProgressView().controlSize(.small)` + `detectingDefectsStatus` | ProgressRing 16 + 문구 | 됨 |
| 검출 후 요약 | `detectSummary` (`.caption`, secondary) | TextBlock 12 | 됨 |
| 구분선 | `Divider().frame(height:16)` | Border 1×16 | 됨 |
| 민감도 | `slider.horizontal.3` 아이콘(.caption2) + `Slider(width:110)` | FontIcon E9E9 + Slider 110 | 됨 |
| 미세 입자 | `Toggle(...).toggleStyle(.checkbox).font(.caption)` | CheckBox | 됨 |
| 구분선 | 〃 | 〃 | 됨 |
| 취소 | `Button { Image(systemName:"xmark") }` | Button + FontIcon E711 | 됨 |
| 제거 | `Button { Label(removeDefects, systemImage:"bandage") }.buttonStyle(.borderedProminent)` + `keyboardShortcut(.defaultAction)` | AccentButton + E90F + 문구 | **모양 깨짐 — 오른쪽이 잘려 보임** |
| 대기 중(검출 전) | 도움말 문구 + 미세입자 + (가능하면)되돌리기 | 도움말 + 미세입자 | **되돌리기 없음** |

`detectSummary` 규칙(macOS 그대로, Windows 구현됨):

```
automaticFalsePositiveRisk → automaticDefectFalsePositiveRiskStatus   ← Windows 에 아직 없음(01/2.4)
total == 0                 → noDefectsStatus                          "결함 없음"
excluded > 0               → defectsCountExcludedFormat                "결함 %d개 (제외 %d)"
그 외                       → defectsCountFormat                       "결함 %d개"
```

### 2.3 종류별 칩 (`DefectClassChip`) — 구현됨, 모양 확인 필요

macOS 사양:

```
HStack(spacing: 5) {
  Circle().fill(allExcluded ? .secondary.opacity(0.4) : classColor).frame(7×7)
  Text(name).font(.caption.weight(.medium)).strikethrough(allExcluded)
  Text(count).font(.caption.monospacedDigit().weight(.semibold))
  Text("\(Int((meanConfidence*100).rounded()))%").font(.caption2.monospacedDigit()).secondary
}
.foregroundStyle(allExcluded ? .secondary : .primary)
.padding(.horizontal 9, .vertical 5)
.background(Capsule().fill(.primary.opacity(hovered ? 0.10 : 0.05)))
.overlay(Capsule().strokeBorder(.primary.opacity(0.10)))
```

바 전체: `HStack(spacing:6)`, `padding(.horizontal 10, .vertical 6)`, 캡슐, `.fixedSize()`.

Windows: `DevelopGrainMendHud.xaml` 의 `GrainMendClassChipTemplate`. **글자가 아래로 잘려
보인다는 보고가 있어 실제 해상도에서 확인 필요.** 호버 상태(0.05 → 0.10)도 아직 없습니다.

분류색(`DefectClassPalette`, macOS `DefectClass.overlayColor` 그대로):

| 분류 | SwiftUI | RGB |
|---|---|---|
| 먼지 | `.orange` | 255,149,0 |
| 핀홀 | `.yellow` | 255,204,0 |
| 가로 스크래치 | `.red` | 255,59,48 |
| 세로 스크래치 | `.pink` | 255,45,85 |
| 대각 스크래치 | `.purple` | 175,82,222 |
| 유제 손상 | `.cyan` | 50,173,230 |
| 미세 입자 | `.mint` | 0,199,190 |

점 불투명도 = `0.35 + 0.5 × confidence`.

### 2.4 미리보기 점 캔버스

macOS `RegionPreviewCanvas`: 컴포넌트마다 점을 3×3 사각형으로. 예산 24,000점, 컴포넌트당
최대 800점, 등간격 샘플링. Windows 구현됨(`DefectMaskOverlayRenderer.RenderPreview`).

**주의**: 미세 입자가 197개 나오기 시작하면 점 예산이 컴포넌트당 24000/227 ≈ 105점으로
줄어듭니다. macOS 와 같은 식이므로 그대로 두면 됩니다.

## 3. 브러시 — `BrushControlBar.swift` (43줄) + `BrushOverlay.swift` + `DefectBrush.swift`

### 3.1 macOS 모델 (Windows 와 **다름**)

macOS 는 획을 **모았다가** "결함 제거"로 한 번에 적용합니다:

- `brushStrokes` 에 쌓임 → 컨트롤 바의 되돌리기/지우기로 조작 → `onApply` 로 확정
- Windows 는 포인터를 뗄 때마다 `AddBrushStroke` 로 **즉시 recipe 에 커밋**합니다.

**이것을 macOS 모델로 바꿔야 컨트롤 바의 되돌리기·지우기 버튼이 의미를 가집니다.**

### 3.2 컨트롤 바 사양

`HStack(spacing:10)`, `padding(.horizontal 12, .vertical 8)`, 캡슐:

| 요소 | 사양 |
|---|---|
| 아이콘 | `paintbrush.pointed.fill`, 빨강 |
| 굵기 | `lineweight` 아이콘(.caption2) + `Slider(0.004...0.06, width:110)` |
| 구분선 | 16 |
| 되돌리기 | `arrow.uturn.backward`, `undoLastStroke`, 획 없으면 비활성 |
| 지우기 | `trash`, `clearPaintedStrokes`, 획 없으면 비활성 |
| 전체 초기화 | `eraser.fill`, `resetAppliedDefects`, 적용된 결함 없으면 비활성 |
| 제거 | `Label(removeDefects, systemImage:"bandage")`, borderedProminent, `keyboardShortcut(.defaultAction)`, 획 없으면 비활성 |

Windows 현재: **아무것도 없습니다.** 굵기는 `DevelopPanelState.DefaultBrushThickness = 0.01`
로 고정입니다.

## 4. 복제 도장 — `CloneStampOverlay.swift` (285줄)

### 4.1 컨트롤 바

| 요소 | 사양 |
|---|---|
| 아이콘 | `rectangle.on.rectangle`, 빨강 |
| 소스 미지정 시 | `cloneStampSourceHint` "⌥ 클릭으로 복제 소스 지정" + 구분선 |
| 크기 | `cloneStampSize` "크기"(.caption2) + `Slider(4...512, width:96)` + `"\(Int)px"`(.caption2 monospaced, width 42, trailing) |
| 구분선 | 16 |
| 경도 | `cloneStampHardness` "경도"(.caption2) + `Slider(0...1, width:80)` + `"\(Int(h*100))%"`(width 34, trailing) |
| 구분선 | 16 |
| 되돌리기 | `arrow.uturn.backward`, `undoDefectRemovalHelp` |

배치: `ZStack(alignment:.top)`, 컨트롤 바에 `.padding(.top, 12)`.

Windows: 없음. 지름 48px·경도 기본값 고정.

### 4.2 커서/미리보기 (전부 없음)

- ⌥ 유지 중: 브러시 원 대신 **십자 커서만**. 소스에도 십자.
- 소스 지정 후: 커서 원 안에 **복제될 소스 픽셀을 실제로 보여줌**
- 드래그 중: 스트로크 모양으로 클리핑해 소스 창 픽셀을 미리 그림, 십자가 샘플 위치를 따라감
- 원 테두리: 검정 0.55 두께 2.5 위에 흰색 0.9 두께 1
- 십자: 팔 7, 검정 0.65 두께 3 위에 흰색 0.95 두께 1.2
- 지름 = `max(3, sizePx × pxToScreenScale)`

## 5. undo — `AppModel+DefectHistory.swift` (163줄)

Windows 에 스택이 없습니다. macOS 는 브러시·가이드·복제가 **한 히스토리를 공유**합니다
(`defectEdits` 통합). 캡슐의 되돌리기 버튼이 이것을 씁니다.

## 6. 레이어 목록 — 이식됨

`DefectLayerSection.swift`(179줄) → `Views/Controls/DefectLayerSection.xaml`. 강도 슬라이더는
macOS 와 같이 **끄는 동안 저장하지 않습니다**(재해싱 비용).

## 7. 작업 순서

1. 캡슐·칩을 **실제 해상도 스크린샷으로 확인**하고 어긋난 것만 고침(잘림·버튼 모양·호버)
2. 위험 경고 문구 연결(01/2.4 가 끝난 뒤)
3. 브러시를 macOS 의 "모았다가 적용" 모델로 바꾸고 컨트롤 바 추가
4. 복제 도장 컨트롤 바 + 십자/미리보기 커서
5. undo 스택
6. 사용자에게 화면 확인
