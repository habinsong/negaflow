> # 하드코딩 · 가짜 구현 · 창작 · 병신 백엔드 · 병신 프론트엔드 = 죽음
>
> ** 추측·가설 금지.** "냄새난다" 고 덮지 말고 **냄새의 원인을 찾아 없애십시오.**
> 재현하고, 스택을 잡고, 계측해서 원인을 **확정**한 뒤에 고칩니다.
> 원인을 못 잡았으면 **"못 잡았다" 고 적으십시오** — 추측으로 고친 것은 다음 사람의 함정입니다.
>
> ** 모르면 웹 검색을 적극적으로** 하십시오 — 특히 GPU·최적화·UI/UX 구현. 찾은 것은 출처를 남기십시오.
>
> **백엔드**: macOS Swift 파일을 **먼저 열고** 코드를 1:1 로 그대로 옮깁니다.
> 상수 하나, 임계 하나, 게이트 순서 하나도 지어내지 마십시오.
> 이름이 같다고 "있음" 으로 적지 마십시오 — **함수 안을 읽고** 판정하십시오.
>
> **프론트엔드**: ① computer-use 로 Windows 앱을 **구역별 크롭**해서 보고
> ② **Parsec 으로 macOS negaflow** 를 같은 구역으로 보고
> ③ **스크린샷 50장**(`C:\Users\habin\맥negaflow 스크린샷\`)을 확인한 **뒤에만** 판정합니다. 폴더·파일 전체 목록은 [`11`](11-ui-verification-protocol.md) 1.3절.
> **모양·크기·위치·정렬·색상·내용·텍스트 안 잘림** 일곱 가지를 전부 맞춥니다.
> XAML 에 있다고 "있음" 이 아닙니다 — **화면에 보여야** 있는 것이고,
> **눌러서 값이 안 바뀌면 가짜**입니다.
>
> **화면 도구 — 자세히.** `windows-mcp` / `windows-gui` MCP 는 **절대 금지.** 켜지 말고 호출하지 말고 대용으로도 쓰지 마십시오. Windows 앱·Parsec 맥 화면은 **computer-use 만.** computer-use 도 **꼭 필요할 때만** 씁니다(토큰). **씁니다:** 이 작업에서 화면에 보이는지·눌러서 값이 바뀌는지·잘림/정렬/색을 새로 판정해야 하고 코드·단위시험·스크린샷 50장·기존 로그로는 부족할 때. **쓰지 않습니다:** 백엔드·네이티브·시험만 고칠 때, 스크린샷 폴더+Swift/XAML 으로 충분할 때, 방금 본 화면을 다시 찍을 때, "일단 띄워 보자" 탐색. 쓸 때도 전체를 반복 찍지 말고 **해당 구역만 크롭.** 전문은 [`00`](00-index.md) · [`11`](11-ui-verification-protocol.md).
>
> **저장소**: 본체 `C:\Users\habin\negaflow\`(Apache 2.0) · 스캐너 `C:\Users\habin\negaflow-scanner-sane\`(GPL).
> **두 저장소의 `negaflow-mac\` 은 절대 고치지 마십시오.** 코드 파쿠리·라이선스·특허·저작권 위반 금지.
>
> 규칙 [`00-index.md`](00-index.md) · UI 검증 [`11`](11-ui-verification-protocol.md) · 라이선스 [`12`](12-repos-and-licence.md)

---

---


# 08 — 아이콘과 크롬(바·캡슐) 감사

---

## 1. 아이콘 — macOS 117개 vs Windows 81개

> **전수조사는 [`08a-icon-inventory.md`](08a-icon-inventory.md) 에 있습니다.**
> 이 절은 표본만 본 것이고, 아래 "56개" 는 XAML 만 세서 틀린 값이었습니다 —
> C# 문자열에 PUA 문자로 박아 둔 것까지 세면 **고유 81개 · 사용처 203곳** 입니다.
> 08a 는 그중 뜻이 다른 것과 **아예 빈 네모로 나오는 두 자리**를 자리별로 적었습니다.

| | macOS | Windows |
|---|---:|---:|
| 고유 아이콘 수 | **117** (SF Symbols, `systemName:`/`systemImage:`) | **81** (Segoe `Glyph` + C# PUA 리터럴) |

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
화면에 나오는 것만 추려 `src/Shell/Assets/Icons/*.svg` 로 `PathIcon` 을 만들고
Segoe 글리프를 대체합니다. 옛 84장 영문 스크린샷 목록은 쓰지 마십시오 — 기준은
[`11`](11-ui-verification-protocol.md) 1.3절 50장입니다.

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
| 라이브러리 | 레일 3개만(macOS 는 `WorkflowSidebar`+`sidebarTab` 저장). 폴더 머리줄 프로세스/타깃/적용은 2026-08-20 | 별점·플래그·거부·스캔 2개 **없음** | — | 필터 캡슐 순서/글자 어긋남 | 썸네일 격자 |
| 현상 | `DevelopSourceRail`/`Sidebar`. **프로세스/타깃 UI 없음** | 사진 번호 대신 파일명 | 초기화 있음. 비교 캡슐+분할 2026-08-19. 빠른 동작 알약 2026-08-20 | 줌 HUD 단추+끌기 2026-08-19 | 프리뷰 캐시 있음. 앱 슬라이더 벽시계 남음 |
| 인화 | macOS `PrintWorkspaceSidebar.swift` **없음** | — | 레이아웃 템플릿 **없음** | — | **E4 현상본 프리뷰.** 사이드바·템플릿·줌 HUD 는 남음 |

**스크린샷이 말하는 세로 레일 탭 수**: 라이브러리 3(가져오기·파일트리·컬렉션) ·
현상 6(필름·프리셋·프리셋(디지털)·버전·파일구조·내보내기) · 인화 4.
Windows 는 라이브러리 3개만 냅니다 — [`02`](02-frontend-gaps.md) 2.3.

---

## 4. 크롬 — 2026-08-20 에 맞춘 것

| 표면 | macOS 값 | Windows |
|---|---|---|
| 빠른 동작 알약 | 표면 라운딩 **15**, 안쪽 칠 **12**, 최소 높이 **32**, 칸/줄 사이 **8** | `Styles/Pills.xaml` + `DevelopQuickActionsCard.xaml`. UIA 실측 32/8/8/24 |
| 켜짐 칠 | `Color.accentColor.opacity(0.2)` | `NegaflowAccentSoftBrush`(강조색 20%) |
| 마우스 올림 | `Color.primary.opacity(0.12)` | `NegaflowHoverFillBrush` |
| 되돌리기 | 24×24 원 | `NegaflowPillResetButtonStyle` |
| 폴더 머리줄 | 피커 2 + 적용 단추 | 프로세스 98×30 · 타깃 84×30 · 적용 30, 라운딩 8 |

**강조색은 스크린샷에서 뽑지 않았습니다.** 맥 스크린샷에는 모니터 ICC 프로파일이 박혀 있어
화소값이 장치값입니다([`11`](11-ui-verification-protocol.md) 4.3). Swift 의
`Color.accentColor`(= systemBlue) 를 따라 `#007AFF`(밝은 테마) / `#0A84FF`(어두운 테마)
로 두었습니다 — 이미 `NegaflowRatingFilledBrush` 가 쓰던 값과 같습니다.

---

## 5. 아직 다른 아이콘 — 빠른 동작 알약 3개 (2026-08-20 실측)

| 자리 | macOS SF Symbol | 지금 Windows 글리프 | 판정 |
|---|---|---|---|
| 자동 색상 | `camera.filters` (겹친 원 셋) | `&#xE790;` (Color) | **다름** |
| 자동 레벨 | `chart.bar.xaxis` (축 있는 막대) | `&#xE9D2;` (AreaChart) | **다름** |
| 자동 톤 | `circle.lefthalf.filled` | `&#xE7A1;` | 맞음 |
| 자동 화이트 밸런스 | `thermometer.medium` | `&#xE793;` | **다름** |

1절의 판정 그대로입니다 — Segoe 에 같은 그림이 없습니다. `PathIcon` 으로 그려야 합니다.

자세한 것은 [`02-frontend-gaps.md`](02-frontend-gaps.md) · [`07-user-reported.md`](07-user-reported.md).
