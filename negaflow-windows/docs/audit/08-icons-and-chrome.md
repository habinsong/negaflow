> # ⛔ 창작 금지
>
> **macOS Swift 파일을 먼저 열고, 코드를 1:1 로 그대로 옮깁니다.**
> 설명만 보고 다시 쓰지 마십시오. 상수 하나, 임계 하나, 게이트 순서 하나도 지어내지 마십시오.
> 이름이 같다고 "있음" 으로 적지 마십시오 — **함수 안을 읽고** 판정하십시오.
> 전체 규칙은 [`00-index.md`](00-index.md) 맨 위에 있습니다.

---

# 08 — 아이콘과 크롬(바·캡슐) 감사

---

## 1. 아이콘 — macOS 117개 vs Windows 56개

| | macOS | Windows |
|---|---:|---:|
| 고유 아이콘 수 | **117** (SF Symbols, `systemName:`/`systemImage:`) | **56** (Segoe MDL2 `Glyph="&#x…;"`) |

**macOS 의 절반도 안 됩니다.** 그리고 SF Symbols 와 Segoe MDL2 는 **모양이 다른 글꼴**이라,
같은 개념이라도 그림이 같지 않습니다.

macOS 가 쓰는 것 중 Segoe 에 **대응이 없는** 것들(모양이 같은 글리프가 존재하지 않음):

| SF Symbol | 쓰이는 곳 |
|---|---|
| `bandage` | 결함 제거 단추 |
| `scope` | GrainMend 검토 캡슐 |
| `camera.aperture` · `camera.filters` · `camera.macro` · `camera.metering.unknown` | 촬영 메타데이터 |
| `rectangle.on.rectangle` | 복제 도장 |
| `paintbrush.pointed.fill` | 결함 탭 |
| `crop.rotate` | 기하 카드 |
| `circle.hexagongrid.fill` | 컬러 |
| `checkmark.seal` · `checkmark.shield` | 검증 상태 |
| `bolt.badge.checkmark` | 자동 |
| `chart.bar.xaxis` | 히스토그램 |
| `arrow.up.left.and.arrow.down.right` | 맞춤 |
| `cable.connector` | 스캐너 연결 |

**판정: 아이콘은 1:1 이 불가능한 자리입니다.** macOS 와 같은 그림을 내려면
**SVG/Path 로 직접 그려 리소스로 넣어야** 합니다. 지금은 Segoe 에서 "비슷해 보이는 것"을
골라 쓴 상태이고, 이것이 사용자가 말한 "아이콘 싹다 창작"입니다.

**할 일**: macOS 화면 캡처 62장과 SF Symbols 목록을 기준으로,
쓰이는 117개 중 실제로 화면에 나오는 것만 추려 `src/Shell/Assets/Icons/*.svg` 로
`PathIcon` 을 만들고 Segoe 글리프를 대체합니다.

---

## 2. 라이브러리 하단 캡슐 — 순서·위치·글자

사용자 보고: `"전체|필름종류|오프라인|전체"` — **위치·순서가 안 맞고 글자가 깨짐.**

Windows 가 내는 것(`LibraryWorkspaceView.xaml`):

| 줄 | 요소 |
|---:|---|
| 325 | `CurrentRollFilterToggle` |
| 326 | `PickedFilterToggle` |
| 327 | `RejectedFilterToggle` |
| 328 | `OfflineFilterToggle` |
| 329 | `InfraredFilterToggle` |
| 330 | `DefectRecipeFilterToggle` |
| 331 | `UnvalidatedProfileFilterToggle` |
| 332 | `MetadataUnknownFilterToggle` |
| 448 | `FilmTypeModeButton` (DropDownButton) |
| 458 | `OfflineModeButton` |

**빠른 필터 8개**와 **뷰 모드 바의 필름종류/오프라인**이 **다른 줄에 흩어져** 있고,
macOS `LibraryBrowserFilterBar.swift` 의 배치와 대조하지 않았습니다.

macOS 대응 파일 `LibraryBrowserFilterBar.swift` · `LibraryBrowserHeader.swift` 는
Windows 히트가 각각 **3건 · 1건** 뿐입니다 — 사실상 이식하지 않았습니다.

**할 일**: `LibraryBrowserFilterBar.swift` 를 열어 요소 순서·간격·캡슐 모양·글자 크기를
줄 단위로 옮기고, 잘리는 글자는 `TextTrimming`/폭을 macOS 수치로 맞춥니다.

---

## 3. 각 뷰의 바 — 대조 안 된 표면

| 뷰 | 좌측탭 | 상단탭 | 우측탭 | 하단탭/바 | 중앙 프리뷰 |
|---|---|---|---|---|---|
| 라이브러리 | 레일 3개만(macOS 는 `WorkflowSidebar`+`sidebarTab` 저장) | 별점·플래그·거부·스캔 2개 **없음** | — | 필터 캡슐 순서/글자 어긋남 | 썸네일 격자 |
| 현상 | `DevelopSourceRail`/`Sidebar` | 사진 번호 대신 파일명 | 초기화·비교·줌 **없음** | 줌 HUD **없음** | **매번 디코드(2,695 ms)** |
| 인화 | macOS `PrintWorkspaceSidebar.swift` **없음** | — | 레이아웃 템플릿 **없음** | — | **360px 썸네일 확대 → 깨짐** |

자세한 것은 [`02-frontend-gaps.md`](02-frontend-gaps.md) · [`07-user-reported.md`](07-user-reported.md).
