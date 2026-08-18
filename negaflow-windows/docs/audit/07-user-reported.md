> # ☠️ 하드코딩 · 가짜 구현 · 창작 · 병신 백엔드 · 병신 프론트엔드 = 죽음 ☠️
>
> **🔬 추측·가설 금지.** "냄새난다" 고 덮지 말고 **냄새의 원인을 찾아 없애십시오.**
> 재현하고, 스택을 잡고, 계측해서 원인을 **확정**한 뒤에 고칩니다.
> 원인을 못 잡았으면 **"못 잡았다" 고 적으십시오** — 추측으로 고친 것은 다음 사람의 함정입니다.
>
> **🌐 모르면 웹 검색을 적극적으로** 하십시오 — 특히 GPU·최적화·UI/UX 구현. 찾은 것은 출처를 남기십시오.
>
> **백엔드**: macOS Swift 파일을 **먼저 열고** 코드를 1:1 로 그대로 옮깁니다.
> 상수 하나, 임계 하나, 게이트 순서 하나도 지어내지 마십시오.
> 이름이 같다고 "있음" 으로 적지 마십시오 — **함수 안을 읽고** 판정하십시오.
>
> **프론트엔드**: ① computer-use 로 Windows 앱을 **구역별 크롭**해서 보고
> ② **Parsec 으로 macOS negaflow** 를 같은 구역으로 보고
> ③ **스크린샷 84장**(`negaflow_mac_screenshot/`)을 확인한 **뒤에만** 판정합니다.
> **모양·크기·위치·정렬·색상·내용·텍스트 안 잘림** 일곱 가지를 전부 맞춥니다.
> XAML 에 있다고 "있음" 이 아닙니다 — **화면에 보여야** 있는 것이고,
> **눌러서 값이 안 바뀌면 가짜**입니다.
>
> **저장소**: 본체 `C:\Users\habin\negaflow\`(Apache 2.0) · 스캐너 `C:\Users\habin\negaflow-scanner-sane\`(GPL).
> **두 저장소의 `negaflow-mac\` 은 절대 고치지 마십시오.** 코드 파쿠리·라이선스·특허·저작권 위반 금지.
>
> 규칙 [`00-index.md`](00-index.md) · UI 검증 [`11`](11-ui-verification-protocol.md) · 라이선스 [`12`](12-repos-and-licence.md)

---

---


# 07 — 사용자 실사용 보고 (2026-08-18)

사용자가 앱을 직접 쓰면서 보고한 것 전부입니다. **하나도 빼지 않았습니다.**
각 항목마다 코드에서 확인한 것과 **아직 확인 못 한 것**을 나눠 적었습니다.

---

## A. 앱이 터지는 것 (최우선)

| # | 증상 | 확인한 것 | 상태 |
|---|---|---|---|
| A1 | **설정 버튼 누르면 앱 터짐** | 작업 옵션 → 설정 클릭으로 재현. `ResourceLoader.GetString` `COMException 0x80073B17` (`developAutoDefect.Text` 없음) → `XamlParseException` / WER `802b000a` | **2026-08-18 고침.** 스위치는 `developGrainMendAuto.Content` / `developGrainMendGuided.Content`. `TryResource` 가 `COMException` 도 잡음. `AppResources.Get` 은 `0x80073B17` 을 `InvalidOperationException` 으로 바꿈. 같은 클릭으로 창 제목 `설정`, UIA `일반` 확인. |
    
A1 재현(2026-08-18 04:50, 04:59): 작업 옵션 → 설정 클릭. 프로세스 종료. Application Error `Microsoft.UI.Xaml.dll` / `0xc000027b`, WER `combase.dll` / `802b000a` (`E_XAMLPARSEFAILED`).

스택(파일로 잡은 관리 예외): `SettingsRootView.ctor` → `LocalizeScanTab` → `SetSwitchHeader("developAutoDefect")` → `AppResources.Get` → `ResourceLoader.GetString` `COMException 0x80073B17` NamedResource 없음. `TryResource` 는 `InvalidOperationException` 만 잡고 있어 창 생성이 `XamlParseException` 으로 깨졌다.

고친 것: 스위치를 macOS `autoDefect`/`guidedDefect` 에 해당하는 기존 키 `developGrainMendAuto.Content` / `developGrainMendGuided.Content` 로 붙임. `TryResource` 가 `COMException` 도 잡음. `AppResources.Get` 은 `0x80073B17` 을 `InvalidOperationException` 으로 바꿈.

검증(2026-08-18 05:16): 같은 경로로 설정 클릭. `Negaflow.Shell` PID 23648 유지, 창 제목 `설정`, UIA `settings.category.general` = `일반`. 그 클릭 구간에 Application Error 없음.
| A2 | **스캐너에서 DPI·심도·프레임 규격 고르면 앱 종료** | 시뮬레이터 켠 뒤 프레임 규격을 다른 항목으로 고르면 종료. Application Error `Microsoft.UI.Xaml.dll` `0xc000027b`, WER `8000ffff`. `UpdateOptions` → `Render` → `FillTagged` 가 열린 ComboBox 에서 `Items.Clear()` | **2026-08-18 고침.** 목록이 같을 때는 지우지 않고 선택만 바꾼다. 같은 경로로 해상도/심도/프레임 규격 변경 후 프로세스 1개 유지, 프레임 규격 선택값 `35 mm · 24 × 18`. |
| A3 | **현상 워크스페이스를 열면 앱 종료** | 2026-08-19 `run-app` x64 Release. WER `802b000a` / `XamlParseException` `Cannot create instance of DevelopWorkspaceView`. First-chance: `Missing localized resource: developReset.Value`. `DevelopBaseCard.Localize` 가 스포이드 리셋에 `AppLocalizedPhrase.reset` 을 쓰는데 6언어 resw 에 키가 없음 | **2026-08-19 고침.** `developReset.Value` = Reset/초기화/リセット/Zurücksetzen/Réinitialiser/重置. 같은 경로로 `Negaflow.Shell` PID 유지, 현상 화면·노출 0.80 입력 확인. |

**둘 다 재현 후 예외 스택을 잡아야 합니다.** 추측으로 고치지 않습니다.

---

## A.1 함정 — 새 문서가 커밋되지 않습니다

`.gitignore:112` 에 `/negaflow-windows/docs/` 가 있습니다. `docs/plan/`·`docs/progress/` 의
기존 파일은 무시 규칙보다 먼저 추적돼 살아남았지만, **새로 만든 문서는 조용히 빠집니다.**
이 감사 문서도 `git add -f` 로 넣어야 했습니다.

**고칠 것**: 규칙을 좁히거나(`/negaflow-windows/docs/generated/` 등) 예외를 두어야 합니다.
지금 상태로는 핸드오프를 써도 저장소에 남지 않습니다.

---

## B. 메뉴막대

macOS `App/AppMenuCommands.swift` · `AppStandardMenuCommands.swift` · `AppWorkflowMenuCommands.swift`
세 파일이 메뉴막대를 냅니다. Windows 는 시스템 앱 메뉴가 없어서 **창 안 `MenuBar`** 가
그 자리입니다(OS 강제 차이).

| macOS 메뉴 | 정의 위치 | Windows |
|---|---|---|
| negaflow에 관하여 / 설정 | `AppStandardMenuCommands.swift:10` (`.appInfo`) | **2026-08-19.** `AppMenuBarView` 첫 메뉴 `negaflow`. 앱 PID 28956: UIA `negaflow에 관하여` / `설정`. About 창 제목·니엡스 문구·`버전 1.0.0.0`·Copyright. 물리 690×495 = 460×330@1.5. **설정 클릭:** 설정 창 제목 `설정`, 물리 1140×960 = 760×640@1.5, 탭 일반·인터페이스·워크플로우·스캔·디스크·내보내기·단축키·법적 고지 |
| 파일 | `:16` (`after: .newItem`), `:38` (`after: .importExport`) | **2026-08-19.** `AppMenuBarView` 둘째 메뉴 `파일`. PID 31928: UIA `이미지 가져오기` · `폴더 가져오기` · `라이브러리 새로고침` · `스캐너 불러오기` · `빠른 내보내기` · `내보내기`. 인화에서 `스캐너 불러오기` → 라이브러리 + 스캔 패널(Plustek OpticFilm 8100 · 프리뷰/스캔). 시스템 New/Open/Close 없음(OS 강제). 인화 모듈 빠른 내보내기는 아직 현상 경로 |
| 편집 | `:54` (`replacing: .undoRedo`), `:66` (`.pasteboard`), `:78` (`.textEditing`) | **2026-08-19.** `AppMenuBarView` 셋째 메뉴 `편집`. PID 29540: UIA `되돌리기` · `다시 실행` · `현상 설정 복사` · `현상 설정 붙여넣기` · `선택` · `제외` · `negaflow에서 제거` + 단축키 표시(Ctrl+Z 등). `제외` → 카드 빨간 깃발, `되돌리기` → 깃발 사라짐. 메뉴 클릭이 GridView 선택을 비워도 catalog `ActiveFrameId` 로 명령을 건다. 시스템 잘라내기/복사/붙여넣기 없음(OS 강제) |
| 보기 | `:95` (`after: .sidebar`), `:112` (`after: .toolbar`) | **2026-08-19.** `AppMenuBarView` 넷째 메뉴 `보기`. PID 31828: UIA `사이드바 보기/숨기기` · `필름스트립 보기/숨기기` · `인스펙터 보기/숨기기` · `전체 화면 시작` · `라이브러리` · `현상` · `인화`. `현상` → 현상 작업공간. 사이드바 숨김(현상 왼쪽 패널 없음) → 인스펙터 숨김(히스토그램 트리 0). 전체 화면은 `AppWindow` FullScreen presenter, 단축키 Ctrl+Alt+Shift+F(macOS ⌃⌘F 의 control→Alt+Shift). 라이브러리 화면의 가져오기 칸은 `IsSidebarVisible` 을 안 씀 |
| 라이브러리 | `AppWorkflowMenuCommands.swift:8` `CommandMenu(.menuLibrary)` | **없음** |
| 사진 | `:47` `CommandMenu(.menuPhoto)` | **없음** |
| 현상 | `:135` `CommandMenu(.menuDevelop)` | **없음** |
| 스캐너 | `:250` `CommandMenu(.menuScanner)` | **없음** |
| 내보내기 | `:292` `CommandMenu(.menuExport)` | **없음** |
| 윈도우 | 표준 | **없음** |
| 도움말 | `AppStandardMenuCommands.swift:136` (`after: .help`) | **없음** |

Parsec macOS 메뉴 줄: `negaflow · 파일 · 편집 · 보기 · 라이브러리 · 사진 · 현상 · 스캐너 · 내보내기 · 윈도우 · 도움말`.

**판정: 앱·파일·편집·보기 메뉴를 이식함. 나머지 7개는 없습니다.**

---

## C. 창작 판정 — macOS 와 다른 것

| # | 항목 | macOS | Windows | 판정 |
|---|---|---|---|---|
| C1 | **필름 베이스 자동/필름/수동** | `BaseControlSection.swift:20` `[.auto, .preset, .manual]`. 엔진은 `FilmBaseEstimator`(659줄) + `FilmBaseSampleGrid` + `FilmBaseStatistics` + `FilmBaseMeasurementDiagnostics` | `auto_negative_base_resolver.cpp` 1파일 + `film_stock_base_resolver.cpp`. **2026-08-18 함수 단위로 전수 대조함** — 아래 C1.1 | **대부분 일치. 창작 1건 제거함** |
| C2 | **노이즈 감소(디테일 및 효과)** | 슬라이더 5개(`strength` **0.05…1** · luma · chroma · darkTone · detail). 엔진은 `ScannerNoiseReduction.swift` + `+Color` + `+Guided` **3파일** + `Profiles/Noise` 4파일 | 슬라이더 5개 이름은 같음(`DevelopDetailSection.xaml:59-63`). **엔진 `ScannerNoiseReduction*` 히트 0**, 대신 `film_scan_denoise.cpp` 802줄. `strength` 의 `ResetValue="0"` 은 macOS 최소 **0.05** 보다 낮음 | **백엔드 창작.** UI 만 같고 엔진이 다름 |
| C3 | **좌우 뒤집기 없음** | `GeometryToolSection.swift:144` `flipHorizontal`, `:147` `flipVertical` | `DevelopGeometryCard.xaml:39` `FlipHorizontalButton`, `:40` `FlipVerticalButton` — **XAML 에는 있음** | **화면에 안 보임.** 카드가 접혀 있거나 글리프(`E7B7`/`E7B8`)가 안 그려질 가능성. **원인 미확정** |
| C4 | **각도 조절 UI 창작** | `angleDial`(`CropAngleDial`) + `angleRow`(값 + 리셋 + 슬라이더), `setStraighten` | `CropAngleDialControl` + `StraightenAngleControl`(=`InspectorSlider`) — 구조는 같음 | **눈금이 정수였음.** `InspectorSlider` 의 `StepFrequency` 미지정 → 각도가 1도 단위로만 움직임. **2026-08-18 0.01 로 고침**. 배치·모양 차이는 별도 확인 필요 |
| C5 | **컬렉션 창작** | `Features/Library/Model/Collections/` + `LibraryOrganizerSection.swift` + `LibraryOrganizerNameSheet.swift` + `LibraryOrganizerProjection.swift` | `LibraryOrganizer*` **히트 0**. 레일에 `CollectionsRailButton` 만 있음 | **UI 만 있고 뒤가 없음** |
| C6 | **스캔·스캐너 시뮬레이터** | `Features/Scanning/` 21파일 4,446줄 + `ScannerKit/` 50파일 | `Shell.Core/Scanner/` 20파일 + `Views/Library/Scanner/` 5파일 999줄 | **동작 안 함(사용자 보고).** 플러그인 로딩 자체가 안 됨 |

---

## C1.1 필름 베이스 — 함수 단위 전수 대조 (2026-08-18)

macOS `Film/` 4파일 + `ChromabaseEngine+NegativePipeline.resolveFilmBase` +
`NegativeInversion` 을 Windows 와 **함수·상수 단위**로 전부 댔습니다.

### 일치하는 것 (창작 아님 — 이전 판정을 바로잡습니다)

| macOS | Windows | 결과 |
|---|---|---|
| `isFilmBaseCandidate` | `is_component_candidate` | luma 0.012~0.85(컬러)/0.92(B&W), `r≥g-0.01`, `g≥b-0.01`, `r−b ≥ max(0.004, 0.10·peak)`, B&W 허용오차 `0.12·peak + 0.01` — **전부 동일** |
| `candidateLumaFloor` = peak × 0.10, peak = 후보 luma p99 | `floor = percentile(candidate_lumas, 0.99) * 0.10` | 동일 |
| `nonFilmLuma 0.88` + Chebyshev 반경 2 팽창 | 동일 | 동일 |
| `brighterNeighborRatio 1.15`, `neighborRadius 2` | 동일 | 동일 |
| `coherentCount = max(24, count×0.004)` | `max(24, count*4/1000)` | 동일 |
| 강등 규칙 `demoteMinLuma 0.60` · `0.12…0.87` · `demoteRBRatio 0.75` | 동일 | 동일 |
| 형제 병합 `p75 ≥ best×0.90 && ≤ best/0.90` | 동일 | 동일 |
| 상위 절반 선택 `max(count/2, min(count,24))` | 동일 | 동일 |
| `FilmBaseStatistics.coherentCluster` MAD×1.4826×3, 채널 median | `coherent_measurement` | 동일 |
| `clampedDmin` `[1e-3, 1.0]` | `minimum_manual_dmin 1e-3` / `maximum_manual_dmin 1.0` | 동일 |
| `estimateFallbackBaseFromScene` (64~320, edge 0.06, p99 peak, floor `max(0.02, peak×0.45)`, p90) | `scene_edge_fallback_base` | **줄 단위로 동일** |
| `LightSourceProfileRegistry` 게인 5종 | `light_gain()` | `0.98/1.00/1.04`·`1.06/1.00/0.92`·`1.09/1.00/0.88`·`0.97/1.03/1.00` — 동일. B&W 는 1.0 (macOS `neutralBase` 가드와 같음) |
| `presetStats` — 스케일은 실측, 채널 **비율**은 프리셋 | `use_preset_response` 분기 | 동일 |
| `sampleStats` (auto 실측 Dmax) — gate 1.12, darkCut 0.15, baseRatio 1.5/0.55, p0.002, floor `10^-1.8`, `max(0.4, …)`, 기하평균, `(x−0.42)/0.20` smoothstep | `scene_density_range` | **전부 동일** |
| `estimate` 체인 순서 (성분 → 경계 → 분산 → 스트립) | `resolve_auto_negative_base` | 동일 |
| 다운샘플 | macOS CoreImage affine 축소(면적 평균) ↔ Windows `downsample_for_statistics`(밉맵) | 같은 성질 |

**`applySceneRanged` 는 이름만 없고 이식돼 있습니다** — Windows 는 `develop_manual_negative`
안에서 `use_preset_response == false` 일 때 `scene_density_range` 를 씁니다. 이름으로
찾았을 때 "히트 0" 이던 것을 **없다고 적었던 것은 틀렸습니다.**

### 창작 1건 — **제거함**

`connected_component_base` 에 macOS 에 없는 관문이 있었습니다(`d4a3fcb`):

```cpp
const double candidate_peak = floor * 10.0;
if (selected_index == 0U && candidate_peak > 0.0 && selected_p75 < candidate_peak * 0.5) {
    return std::nullopt;   // ← macOS 에 이런 판정이 없습니다
}
```

그 커밋 메시지는 *"macOS 의 첫 단계는 증거가 약하면 nil 을 낸다"* 고 적었지만,
macOS `connectedBaseComponent` 가 nil 을 내는 조건은 **① 셀 0개 ② 성분이 하나도
`coherentCount` 를 못 넘음 ③ `coherentCluster` 가 nil** 뿐입니다. p75 를 후보 봉우리와
견주는 관문은 **없습니다.**

**계측기로 확인한 것** (`--auto-base-probe` 를 이번에 붙였습니다):

- 8100 golden frame_1 — 성분 **8개**, 1위 `cells=891 p75=0.118606`, 후보 봉우리 `0.116775`.
  관문 조건 `0.1186 < 0.0584` 은 **거짓** → 발동조차 하지 않음.
  결과 `connected_component` **0.190995 / 0.093966 / 0.0710797**,
  macOS **0.1913 / 0.0939 / 0.0711** — 일치.
- 커밋이 말한 "단일 성분 p75 0.0168" 은 지금 `#7 cells=15093 p75=0.016479` 로 **8개 중 꼴찌**입니다.
  그 사이 다른 커밋이 진짜 원인을 고쳤고 관문은 **죽은 코드**로 남아 있었습니다.
- **실측 코퍼스 17장**(사용자 스캔 15 + golden 8100 + V700) 전부 `connected_component` 로
  답하며, **관문 제거 전후 값이 바이트까지 동일**합니다.

로컬 게이트: native 71/71, catalog 721, shell **1065** assertions, 경고 0.

### 계측기

```bash
negaflow-cli --auto-base-probe <source.tiff> [color|bw]
NEGA_DEBUG=1 negaflow-cli --auto-base-probe <source.tiff>   # 성분 목록까지
```

### C1.2 필름 베이스 **UI/UX** 대조 — `BaseControlSection.swift` ↔ `DevelopBaseCard.xaml`

| # | macOS | Windows | 판정 |
|---|---|---|---|
| 1 | 헤더 아이콘 `circle.lefthalf.filled` (반원 채운 원) | Segoe 글리프 `E706`(= 밝기) 이었음 | **2026-08-18 고침** — Segoe 에 같은 그림이 없어 `Viewbox`+`Ellipse`+`Path` 로 반원 채운 원을 직접 그림 |
| 2 | 헤더 `trailing: baseReadout` — `baseReadoutFormat` 으로 R/G/B 표시 | `ManualBaseValueText` | **2026-08-19** `developBaseReadoutFormat` + 마지막 미리보기 `AppliedDmin`. 앱 UIA `base 0.22 0.13 0.07` (OpticFilm8100_frame_1). 카탈로그 `frame.baseRGB` 영속은 아직 없음 |
| 3 | **`SegmentedPicker`** — 자동/필름/수동이 **붙어 있는 한 덩어리** | `RadioButton` 3개가 간격 4로 떨어져 있었음 | **2026-08-18 고침** — 테두리 하나 안에 붙인 한 덩어리로. `NegaflowSegmentStyle`(라디오 글리프 제거, Checked → `NegaflowSelectionBrush`) 신설 |
| 4 | `.disabled(!frame.filmType.requiresInversion)` — `FilmType.swift:23` 은 `colorNegative`·`bwNegative` 만 true | `DevelopBaseEditor.CanEdit` = `ColorNegative or BlackAndWhiteNegative`, `DevelopBaseCard.xaml.cs:141-144` 에서 세 모드 단추에 적용 | **일치 확인함(2026-08-18)** |
| 5 | preset: 필름스톡 · 광원 · 프로파일 **3줄**, 각 줄이 `basePresetPickerRow`, `.frame(maxWidth: basePresetPickerWidth)` = **276** (`BaseControlSection.swift:21,140`) | `FilmStockSelector`·`LightSourceSelector`·`ScannerProfileSelector` 3줄, **폭 지정 없음 = stretch** | **2026-08-19** 라벨 폭 86 + ComboBox `MaxWidth=276` + 줄 최소 높이 26. **C1.8** 넓은 패널(persist 560)에서 시각 베젤 **276 DIP**. 좁은 패널에서는 남은 폭(257 DIP). XAML 추가 수정 없음 |
| 6 | manual: **`InspectorActionPill(pickBase)`** — 스포이드 토글 + `reset` 버튼, `isActive` 시 강조, `.snappy(0.18)` 애니메이션 | **2026-08-18 이식함** — `BasePickerPill`(본문 MinHeight 31 · Padding 7,0,0,0 · 리셋 23×23 · Margin 0,0,3,0 · CornerRadius 16), 수동 모드에서만 보임 | **고침** |
| 7 | manual: `InspectorSlider(baseRed/Green/Blue, range: 0...1, doubleClickResetValue: nil)` | 3개, `CanReset="False"` | **2026-08-18 고침** — `ConfigureRanges()` 가 macOS 와 같은 `0…1` 을 줌 (`49dab68`) |

### C1.3 베이스 스포이드 — **2026-08-18 이식함** (`d39e55e`)

앞 판에 *"엔진·캔버스·인스펙터 전부 없음"* 으로 적혀 있던 항목입니다. 이제 끝에서 끝까지 있습니다.

**왜 중요했나** — `FilmBasePicker.swift` 주석 원문:

> 평판 프리뷰는 필름 밖(투과 광원 창 바깥의 검정 띠, 빈 베드)까지 담기 때문에, 클릭이 조금만
> 빗나가도 필름이 아닌 픽셀이 Dmin 으로 앉아 현상 결과가 통째로 검게 죽었다(실측: 검정 띠 클릭
> → base 0.004 → 반전 전 구간 클리핑).

| macOS | 줄 | Windows |
|---|---:|---|
| `Chromabase/Film/FilmBasePicker.swift` | 149 | `imaging/film_base_picker.cpp` (268) |
| `CanvasView+HUDTools.swift:99` `basePickerOverlay` | 30 | `DevelopPreviewCanvas.xaml` `BasePickerPrompt` + `ShowBasePickerPrompt(bool)` |
| `CanvasView+HUDTools.swift:130` `handleBasePick` | 10 | `DevelopWorkspaceView.xaml.cs` `TryHandleBasePick(args)` |
| `BaseControlSection.swift:68` `InspectorActionPill` | — | `DevelopBaseCard.xaml` `BasePickerPill` |
| — | — | ABI `nf_pick_film_base_v1` · Interop `FilmBasePick.Sample` |

**이식한 알고리즘** (macOS 상수 그대로):

| 단계 | 값 |
|---|---|
| 1차 스냅 | 로컬 창 = 짧은 변 × **0.12**, 최소 **48**, 잘린 창이 **32×32** 이상일 때만 → 베이스 연결 성분 |
| 2차 폴백 | 영역 = 짧은 변 × **0.01**(최소 3px) 의 **채널 중앙값**(평균 아님 — 엣지 마킹·먼지에 끌립니다) |
| 타당성 | `is_component_candidate` **그리고** luma ≥ 스캔 전체 기준(후보 luma p99) × **0.5** |
| 실패 시 | **Dmin 을 바꾸지 않습니다** — 위 주석의 "검게 죽는" 자리 |

**좌표계 차이 1건**: macOS 는 y 를 뒤집습니다(Core Image 는 y-up). Windows 는 y-down 이라
뒤집지 않습니다. **이것은 창작이 아니라 좌표계가 달라서 필요한 것이고, 코드에 주석으로 적었습니다.**

**공통 코드 추출**: macOS 는 추정기와 피커가 같은 모듈의 함수를 씁니다. Windows 도 같게 하려고
`film_base_sampling.h/.cpp` 를 새로 만들어 `SampleGrid`·`percentile`·`median`·`upper_median`·
`is_component_candidate`·`coherent_measurement`·`connected_component_base` 등을 옮겼습니다.
**코드를 다시 쓰지 않고 그대로 잘라 옮겼고**, 실측 코퍼스 17장의 dmin 이
**리팩터 전후 바이트까지 동일**한 것으로 확인했습니다. `auto_negative_base_resolver.cpp` 908 → **546줄**.

**시험**: `native.film_base_picker` **7개** — 띠 채택 · 빗나간 클릭 스냅 · **검정 띠 거절** ·
장면 거절 · 잘못된 입력 · 중립 베이스 · 상태 이름.

**문자열**: macOS 원문 그대로 6개 언어(`developPickBase.Text`, `developPickBaseHelp.Value`,
`developBasePickerPrompt.Text`, `developBasePickNotFilmBase.Text`, `developBasePickFailed.Text`).

**아직 확인 못 한 것: 앱 화면에서 실제로 집어 본 적이 없습니다.** 시험 통과 ≠ 앱 동작입니다.

### C1.4 2026-08-19 — 5함수 전수 대조 + strip_fallback / readout / 피커

macOS `FilmBaseEstimator.swift` 전량 · `FilmBaseStatistics.coherentCluster` ·
`FilmBaseMeasurementBuilder.build` · `BaseControlSection.swift` 를 Windows
`auto_negative_base_{exclusion,candidates,fallback,resolver}.cpp` ·
`film_base_sampling.cpp` · `DevelopBaseCard` 와 다시 댔습니다.

**4함수는 상수·게이트가 같았습니다** (`non_film_exclusion` /
`continuous_border_base` / `distributed_base` / `connected_component_base` 의
이미 이식된 경로). `brightest_coherent_mode` 는 성분 강등 안의 `medianRB` 로
이미 있습니다.

**확정 공백 3건 중 이번에 옮긴 것:**

| 공백 | 한 일 | 검증 |
|---|---|---|
| `strip_fallback_base` 가 채널 독립 중앙값+clamp | 걸러 낸 스트립 평균을 `coherent_measurement` 에 넘김. `brightStrips` 의 luma≥0.97 을 **집합에서도** 뺌(이전엔 밝기 기준에만 씀) | `native.manual_negative_developer` 통과. 기존 masked-strip 평균 시험 유지. 새 시험: 준클리핑 오른쪽 스트립을 빼면 (0.69, 0.49, 0.29). 네 스트립 이하에서는 macOS 도 `max(4,n/4)` 바닥 때문에 MAD 이상치를 다시 전부 씀 — 그 경로의 수치 차이는 클리핑 컷 |
| 헤더가 `"Auto"` / 필름 이름 / `F3 / F3 / F3` / `"not set"` 영어를 지음 | `developBaseReadoutFormat` 6언어(`base %.2f %.2f %.2f` / Basis / ベース / 片基). 미리보기 `AppliedDmin` 을 `LastAppliedBase` 로 표시 | `run-app` x64 Release PID 29336. UIA `184 텍스트 base 0.22 0.13 0.07`. Shell 1072 assertions |
| 프리셋 ComboBox stretch | 라벨 86 + `MaxWidth` 276 + 줄 최소 26 | **C1.8** 넓은 패널 시각 베젤 276 DIP. 좁으면 남은 폭 |

**아직 남은 것**

| 항목 | 내용 |
|---|---|
| **sidecar `confidence` JSON** | **2026-08-19 이식함**(C1.6). 앱 내보내기 `OpticFilm8100_frame_1.tiff.negaflow.json` 에 `confidence=0.7291067` · `confidenceBasis=measuredEvidenceScoreV1` · `method=connectedComponent` |
| **`frame.baseRGB` 카탈로그 영속** | **2026-08-19 이식함.** `params` 형제 `baseRGB` 세 채널. 미리보기 후 `AppliedBaseWriter`. 프레임 전환 시 카탈로그에서 복원. relink 는 키를 지움 |
| **피커 폭 픽셀 자** | **2026-08-19 C1.8 닫음.** 넓은 패널 시각 베젤 276 DIP. UIA 는 284(히트 8 DIP) |
| **스포이드로 미노광 베이스를 집어 Dmin 이 바뀜** | **2026-08-19 C1.9.** RealScan.tiff 왼쪽 리베이트 클릭 → 슬라이더·헤더 `0.40 0.13 0.07`, 캔버스는 현상본 유지 |

### C1.5 2026-08-19 — `FilmBaseMeasurementDiagnostics` 1:1

macOS `Film/FilmBaseMeasurementDiagnostics.swift`(186) · `FilmBaseMeasurementBuilder.build` ·
`FilmBaseStatistics.coherentCluster` 를
`film_base_measurement.h/.cpp` 로 옮기고, 자동 베이스 네 실측 경로가 같은 빌더를 거칩니다.

| 항목 | Windows | 근거 |
|---|---|---|
| Method 4 | `connectedComponent` / `continuousBorder` / `distributedMask` / `stripFallback` (Codable raw 동일) | 헤더 enum + `film_base_measurement_method_name` |
| Anomaly 8 · 같은 순서 · 같은 임계 | fallbackEstimate, 32, 0.02, 0.65, 0.04, 0.015, 0.01, 0.10 | `film_base_measurement.cpp` 202–226행 = Swift 123–131행 |
| EvidenceComponents 7항 최솟값 = `evidenceScore` | 64 / 0.02 / spatial / 0.08 / 0.03 / 0.05 / inlier. `isCalibratedProbability=false` | Swift 113–121, 148–149 |
| `coherentCluster` | MAD×1.4826×3, 바닥 1e-4, 유지 `max(4,n/4)` 아니면 원본. RGB **비클램프** | Swift `FilmBaseStatistics` 9–26. 피커만 `clamp_rgb` |
| 배선 | connected / border / distributed / strip → `diagnostics` 복사. `scene_edge`·상수 fallback·수동·스포이드는 `nullopt` | macOS 도 추정/수동에는 measurement 없음 |

검증:

- `native.film_base_measurement_diagnostics` · `native.film_base_picker` · `native.manual_negative_developer` x64-release 통과.
- `negaflow-cli --auto-base-probe` `frame1.tiff` 5088×3401 color: `source=connected_component` `method=connectedComponent` `dmin=[0.22128,0.13298,0.0710158]` `evidenceScore=0.729107` `sampledPixelCount=43776` `anomalies=[]` 49726 µs.
- `run-app` x64 Release `-SkipBuild` PID 6840. 자동 모드 정착 후 UIA `base 0.22 0.13 0.07` — 프로브와 소수 둘째 자리 일치. 미리보기 대비가 수동 0.90/0.65/0.45 때보다 살아남.
- 수동 → 스포이드 알약 → 프롬프트 `미노광 필름 베이스(사진 사이/가장자리)를 클릭하세요 · Esc 취소`. 캔버스 UIA 클릭 후 프롬프트 사라짐, 슬라이더 0.90/0.65/0.45 유지. 거부 문구는 이 화면에서 확인 못 함.
- Parsec macOS `OpticFilm8100_frame_5` 베이스 탭: `base 0.23 0.15 0.07` · 자동 선택. 폴더 `develop_right_base_panel.png` 와 카드 구조(헤더·읽음·자동/필름/수동) 같음. 프레임이 달라 숫자는 Windows frame_1 과 다를 수밖에 없음.

### C1.6 2026-08-19 — sidecar `FilmBaseDiagnostics`

macOS `Sidecar.FilmBaseDiagnostics.init` · `ExportFrameWriter+Sidecars` 를
`FilmBaseSidecar` + `ExportSidecarWriter.BuildJson` 에 옮겼습니다.

| 항목 | Windows | 근거 |
|---|---|---|
| `confidence` | `measurement?.evidenceScore` | Swift 90행 |
| `confidenceBasis` | 실측이면 `measuredEvidenceScoreV1`, 아니면 null | Swift 91행 |
| `confidenceIsCalibratedProbability` | `measurement?.isCalibratedProbability` | Swift 92행 |
| `measurement` | Codable 키 그대로 중첩. 수동·스포이드·상수 폴백은 null | Swift 89행, 시험 `testSidecarCarriesMeasuredEvidenceAndDoesNotInventManualConfidence` |
| `source` | connected/distributed → `auto`, border/strip → `border`, 수동·프리셋 폴백 → `manual` | `FilmBaseEstimator` + `FilmBase.Source` |
| `dmin` | `-log10(max(rgb, 1e-6))`. `dmax`/`densityRange` 는 null | Swift 86–88행 |
| `baseSample` | r/g/b/source. XMP `negaflow:BaseSample*` | `Sidecar+XMP.swift` 104–108행 |
| 배선 | invert 가 진단을 outcome 에 복사. 결과 v4(344바이트)로 ABI. 광원 게인이 1이 아니면 macOS `applyLightSourceGain` 처럼 진단만 뺌 | `invert.cpp` · `develop_result_v4` |

검증:

- `FilmBaseSidecarTests` + 기존 sidecar 시험 포함 Shell.UnitTests **1093 assertions**.
- `run-app` x64 Release PID 31912. 자동 `base 0.22 0.13 0.07` 뒤 소스 탭에서 사이드카 켜고 내보내기.
- `OpticFilm8100_frame_1.tiff.negaflow.json` (2794바이트): `method=connectedComponent` `sampledPixelCount=43776` `confidence=0.7291067194749321` `confidenceBasis=measuredEvidenceScoreV1` `anomalies=[]`. 프로브와 같은 실측.
- 키 대조(앱 JSON ↔ Swift Codable): `rgb`/`source`/`dmin`/`dmax`/`densityRange`/`confidence`/`confidenceBasis`/`confidenceIsCalibratedProbability`/`measurement` + measurement 의 `schemaVersion`/`method`/`sampledPixelCount`/`candidateCount`/`selectedSampleCount`/`retainedSampleCount`/`sampleCoverage`/`spatialCoverage`/`medianLuma`/`lumaMAD`/`channelMAD`/`chromaticityMAD`/`clippedFraction`/`outlierFraction`/`evidenceComponents`(7항)/`evidenceScore`/`isCalibratedProbability`/`anomalies`. 수동은 confidence·basis·measurement 가 null.

### C1.7 2026-08-19 — `frame.baseRGB` 카탈로그 영속

macOS `ScanFrame.baseRGB` · `LibraryFrameRecord.baseRGB` · `applyBaseCache` (`result.base?.rgb`) 를
Windows `LibraryFrameSnapshot.AppliedBase` + `AppliedBaseWriter` 로 옮겼습니다.

| 항목 | Windows | 근거 |
|---|---|---|
| 자리 | frame record `baseRGB` — **params 형제** | Swift `LibraryFrameRecord.baseRGB` |
| 쓰기 | 미리보기 성공 후 `RememberAppliedBase` → `EditFrameRecord` | `AppModel+DevelopRendering.applyBaseCache` |
| 읽기 | 없으면 legacy null. 있으면 유한 3채널 | `makeFrame` `count == 3` |
| 프레임 전환 | 그 프레임의 `AppliedBase` 를 읽음 | ScanFrame 이 값을 들고 있음 |
| relink | `baseRGB` 키 삭제 | `AppModel+SourceRelink` `frame.baseRGB = nil` |

프리뷰 프록시 슬롯은 `light_gain` 을 키에 넣습니다. white-led 뒤 warm-led 는 슬롯 미스 + applied dmin 변경 (`native.preview_proxy_cache`).

### C1.8 2026-08-19 — 넓은 인스펙터에서 필름 모드 피커 276

macOS `BaseControlSection.swift:21,136-141` 은 고정 폭이 아니라 **상한 276** 입니다.
주석 원문: 패널을 좁히면 세 컨트롤이 남은 폭을 나눠 줄어들고, 고정 폭이면 오른쪽이 잘립니다.

**Windows x64 Release PID 7328**, `GetDpiForWindow=144`, persist `inspectorWidth=560`
(패널 상한 `ShellLayoutMetrics.PanelMaximumWidth`). 현상 → 베이스 → 필름.

| 측정 | 값 |
|---|---|
| 라벨 `FilmStockLabel` UIA | **86.00 DIP** (129 px) |
| 세 ComboBox UIA | 426 px = **284.00 DIP** |
| 스크린샷 베젤 스캔 | 채움이 UIA 안쪽으로 ~2/~3 px → **414 px = 276 DIP** |
| 베이스 카드 그룹 | 532 DIP (= 560 − leading 8 − trailing 20) |
| 피커 오른쪽 ~ 창 오른쪽 | 102 DIP (남은 칸을 채우지 않음) |
| 이전 좁은 패널 | 386 px = **257.3 DIP** (86+12+276=374 보다 좁아서 줄어듦) |

UIA 284 는 ComboBox 히트/포커스 패딩 약 8 DIP 입니다. 보이는 베젤은 276 에서 멈춥니다.
`MaxWidth=276` + `Stretch` 가 넓은 패널에서 상한을 지킵니다. XAML 을 더 고치지 않았습니다.

**Parsec macOS** `OpticFilm8100_frame_5` 현상 → 베이스 → 필름: 필름 스톡·광원·프로파일 3줄,
선택 안 함/없음. 그 인스펙터는 374 보다 좁아 피커 시각 폭 **≈201 DIP**(줄여 쓰는 경로).
Swift 주석과 같습니다.

### C1.9 2026-08-19 — RealScan 리베이트 스포이드가 Dmin 을 바꾼다

macOS `handleBasePick` 은 표시 좌표를 raw 로 되돌린 뒤 `pickFilmBase` 를 `Task.detached` 로
샘플하고, `basePickerMode = false` 가 `selectCompareMode(.developed)` 를 겁니다.

**앱에서 안 바뀌던 원인 두 가지(추측이 아니라 재현으로 확정):**

1. **WIC COM 아파트.** `nf_pick_film_base_v1` 디코더는 `COINIT_MULTITHREADED` 를 요구합니다.
   WinUI 스레드는 STA 라서 UI 에서 직접 열면 `RPC_E_CHANGED_MODE` 로 디코드가 실패하고
   Dmin 이 그대로입니다. macOS 와 같이 워커에서 샘플합니다.
2. **현상본에서는 주황 리베이트가 안 보입니다.** 스포이드를 켜면
   `selectCompareMode(.raw)` 와 같이 `FilmPolarity.Positive` 로 반전 전 원본을 그립니다.
   장면 클릭은 여전히 `NotFilmBase` 로 Dmin 을 유지합니다(macOS `isPlausibleBase`).

**집기 직후 빈 캔버스** — 피커를 끄는 `onChange` 가 현상 미리보기를 한 번 더 요청해, 취소된
렌더가 `Completed`+빈 화소로 배달되면 `ShowEmpty`("이미지를 가져오세요") 가 났습니다.
집기 중에는 그 요청을 건너뛰고, 실패 렌더는 `Faulted`/`Cancelled` 로 두며, 이미 그림이
있으면 지우지 않습니다. `OperationCanceledException` 이 pending 을 지워 마지막 요청이
사라지던 경로도 막았습니다.

**Windows x64 Release PID 28372** (`run-app`), `GetDpiForWindow` 이전 실측 144.
RealScan.tiff · 수동 · 스포이드 켬 → 원본(주황 리베이트) · 왼쪽 띠 클릭.

| 단계 | UIA / 화면 |
|---|---|
| 리셋 | 슬라이더·헤더 `0.25 0.25 0.25`, 캔버스 현상본 |
| 스포이드 켬 | 프롬프트 `미노광 필름 베이스(사진 사이/가장자리)를 클릭하세요 · Esc 취소`. 원본 주황 |
| 장면/캔버스 밖 클릭 | Dmin `0.25` 유지. 캔버스는 현상본(비지 않음) |
| 왼쪽 리베이트 | 슬라이더 `+0.40 / +0.13 / +0.07`. 헤더 `base 0.40 0.13 0.07`. 캔버스 현상본(올리브 숲, 주황 원본 아님) |

CLI `--pick-film-base` 와 엔진 게이트는 같음: 가장자리 0.02–0.05 채택, 0.10·중앙 거부.
`native.film_base_picker` x64-release 통과. Shell 1099 assertions.

### 앞 판에서 바로잡은 것

| 앞 판 서술 | 실제 |
|---|---|
| `Film/FilmBaseStatistics.swift` **없음** | **이름만 없고 이식돼 있었음** — `coherentCluster`/`median`/`percentile` 셋 다 있음 |
| `Film/FilmBaseSampleGrid.swift` **없음** | **이름만 없고 이식돼 있었음** — `SampleGrid`·`make_sample_grid` |

**둘 다 파일명으로 찾아 "없음" 으로 적은 것입니다.** `applySceneRanged` 때와 같은 실수입니다 —
**이름이 같다고 있는 것이 아니듯, 이름이 없다고 없는 것도 아닙니다. 함수 안을 읽어야 합니다.**

### 계측기

```bash
negaflow-cli --auto-base-probe <source.tiff> [color|bw]
```

```bash
NEGA_DEBUG=1 negaflow-cli --auto-base-probe <source.tiff>
```

---

## C.1 추가 보고 (2026-08-18 후속)

| # | 증상 | 확인한 것 | 상태 |
|---|---|---|---|
| C7 | **상단탭에 필름명만 나오고 별 5개·플래그·거부 UI 없음** | `Rating`·`Flag`·`Reject` 히트는 라이브러리 쪽뿐. macOS 는 상단바에 별점·플래그·거부가 있고 상단 중앙은 **사진 번호**(`AppModel+PhotoNumbering.swift`, Windows 히트 2) | **없음 확정** |
| C8 | **상단탭 가운데 정렬이 안 맞음** | 중앙 요소가 가운데로 정렬되지 않음 | **미수정** |
| C9 | **진단 기능 미구현** | macOS `Services/Diagnostics/` **7파일**. Windows 는 `tests/Shell.UnitTests` 안의 진단 명령(`--defect-tools` 등)만 있고 **앱 안의 진단 화면 없음**. `AppModel+SupportBundle.swift`(지원 번들) 도 히트 0 | **없음 확정** |
| C10 | **모든 UI/UX 가 창작, 아이콘 없는 것도 있음** | 아이콘 macOS 117 vs Windows 56 — [`08-icons-and-chrome.md`](08-icons-and-chrome.md) | **확정** |
| C11 | **인화뷰 우측탭 전부 창작** | macOS 는 `PrintWorkspaceInspector.swift` + `PrintInspectorComponents.swift` + `PrintInspectorControls.swift` + `PrintPackageInspectorControls.swift` + `PrintLayoutTemplateControls.swift` **5파일**. Windows 는 `Views/Print/Settings/PrintInspectorBinder.cs` + `PrintInspectorSurface.cs` **2파일**뿐이고 `PrintLayoutTemplateControls`·`PrintPackageInspectorControls` 히트 **0** | **확정** |
| C12 | **인화 출력(내보내기·빠른내보내기) 백엔드·UI 틀림** | macOS 는 `AppModel+PrintExport.swift` + `AppModel+PrintPackageExport.swift` + `PrintPackageExportWriter.swift` + `PrintPackageArtifactLayout.swift` + `Chromabase/Export/PrintPackageRenderer.swift`. Windows 는 `Views/Print/Export/PrintExportWorkflow.cs` 하나. `PrintPackageRenderer` 히트 **0**, `PrintPackageArtifactLayout` 히트 **0** | **확정** |
| C13 | **자동 색상·자동 레벨·자동 톤·자동 화이트밸런스 버튼 모양 창작** | macOS `DevelopQuickActionsSection.swift`(158줄): 아이콘 `camera.filters`(자동 색상) · `chart.bar.xaxis`(자동 레벨, **토글**) · `circle.lefthalf.filled`(자동 톤) · `thermometer.medium`(자동 화이트밸런스), 각각 `Label(title, systemImage:)` + `minHeight: 32` + `.buttonStyle(.plain)` + `maxWidth: .infinity`. 맨 위에 `arrow.counterclockwise.circle` **모든 보정 초기화**(`role: .destructive`). Windows 는 GrainMend 카드 아래 텍스트만 있는 사각 단추 4개이고 **아이콘 없음**, 자동 레벨의 **토글 성격 없음**, 초기화 단추 **없음** | **확정** |

---

## D. 없는 것 (히트 0 확정)

| # | 항목 | macOS |
|---|---|---|
| D1 | **초기화 — 모든 보정 / 사진 각도** | `Tools/ResetControlsSection.swift:14,23` (`onResetAllAdjustments`, `onResetPhotoAngle`) + `DevelopInspectorResetter.swift`(104줄). Windows `ResetAllAdjustments`·`ResetControlsSection`·`InspectorResetter`·`ResetAngle` **전부 0** |
| D2 | **비교 캡슐 원본/현상본/좌우분할/상하분할** | `CanvasCompareControls.swift`(197줄) + `CanvasCompareDivider.swift`(166줄) + `CanvasView+Comparison.swift`. Windows `CompareDivider`·`compareMode`·`SplitHorizontal`·`NeutralPreview` **전부 0** |
| D3 | **줌 HUD** | `CanvasViewportState.swift`(71줄). Windows `ZoomLevel`·`ZoomIn`·`ZoomOut`·`FitToWindow` **전부 0** |
| D4 | **GrainMend IR 프론트엔드** | Windows `DevelopGrainMendPanel.xaml` 도구 단추 4개(자동·가이드·브러시·복제). **IR 없음**. 엔진 1,570줄은 있음 |
| D5 | **undo/redo** | `DevelopHistory.swift` + `AppModel+DefectHistory.swift`(228줄). Windows 는 라이브러리 undo 만 있고 현상·결함 undo **없음** |
| D6 | **내보내기 35파일** | 배치·체크포인트·커밋저널·트랜잭션·검증등급·Reveal·가용성·실체화·추적 + UI 7개 |
| D7 | **인화 8파일** | 커스텀 패키지 오버레이·레이아웃 템플릿·아티팩트 배치·캡션 포맷터·설정 이력·사이드바·매니페스트 검사 |

---

## E. 성능

| # | 증상 | 원인 (확정) |
|---|---|---|
| E1 | 사진 바꾸면 수 초 | **2026-08-19.** 디코드 단일 슬롯 + **프리뷰 raw 프록시 2슬롯**(인터랙티브/정착). 프리뷰는 결함·필름베이스를 원본에서 푼 뒤 `displayProxy` 와 같이 Lanczos3 로 상자 맞춤하고 **그 작은 raw 에서 현상**. 내보내기·검출은 원본 해상도. 실측 5088×3401: 상자 1280 두 번째 프리뷰 **43.1 ms · decode runs 0** (첫 549.6 ms 중 decode 187.9). 상자 3600 두 번째 **260.6 ms · decode 0**. 앱 슬라이더 벽시계는 아직 설치본에서 재는 중. |
| E2 | 우측탭 기능 하나 써도 수 초 | E1 과 같은 경로. CLI/시험은 두 번째 호출에서 디코드 0. **앱에서 슬라이더를 두 번 끌어 확인하는 것이 남음.** |
| E3 | GrainMend 자동·가이드·브러시·복제 전부 느림 | 위 + **GPU 코드 0줄** |
| E4 | **인화 프리뷰가 깨짐** | **2026-08-19.** `developedImage ?? thumbnail` 순. 현상 미리보기 화소를 기억하고, 칸이 더 크면 `PrintPreviewResolution.renderDimension`(720…2560) 으로 현상본을 올림. 앱: RealScan·OpticFilm8100_frame_1 인화 판에 현상본, 열차 번호 2355 판독. 360 JPEG 확대 아님 |

---

## F. 문자열 오류 (macOS 원문 대조 13건 중 실오류 11건)

`타깋`→`타깃` · `룹`→`룩` · `필름스톡`→`필름 스톡` · `중간톤`→`중간 톤` ·
`Digital B&amp;W` 이스케이프 노출 · `{0} 사본 %d` 형식지정자 혼용 ·
`기본 스캔 회전`/`스캐너 성능`/`미세 반점 기본값` + 도움말 2건 macOS 원문과 다름.

---

## F.1 라이브러리 — 폴더별 현상 컨트롤

macOS `Features/Library/Views/LibraryFolderDevelopmentControls.swift` **224줄**:

| 줄 | 요소 |
|---:|---|
| 31 | `LibraryFolderBatchPicker` — **프로세스** |
| 40 | `LibraryFolderBatchPicker` — **타깃** |
| 49 | `LibraryFolderApplyButton` — **적용** |
| 56 | `model.applyLibraryFolderDevelopment(process:target:frames:progress:)` |

백엔드는 `Features/Library/Model/AppModel+LibraryFolderDevelopment.swift` 입니다.

Windows `Views/Library/Defaults/LibraryDevelopDefaultsPanel.xaml` 의 요소 전부:

```
DevelopDefaultsText  DevelopProcessLabel  DevelopProcessSelector
DevelopTargetLabel   DevelopTargetBar
DevelopFilmProfileLabel  DevelopFilmProfileSelector
DevelopLookLabel         DevelopLookSelector
```

**적용 단추가 없습니다.** `ApplyButton`·`applyLibraryFolder`·`ApplyToFolder` 히트 0
(있는 `*ApplyButton` 은 크롭과 브러시 것뿐). 그리고 이것은 **폴더별**이 아니라
"라이브러리 기본값" 패널입니다 — macOS 는 폴더를 골라 그 안의 프레임에 **일괄 적용**합니다.

**판정: 프론트엔드에 적용 단추 없음, 백엔드에 일괄 적용 경로 없음. 그래서 작동하지 않습니다.**

---

## G. 다음 순서 (사용자 요구 반영)

1. **A1·A2 크래시** — 스택부터. **A3(2026-08-19) `developReset.Value` 도 닫음.**
2. **E1 프리뷰 프록시 캐시 + 2단 렌더** — 네이티브 2슬롯+Lanczos 현상 붙임. 5088×3401 상자 1280 두 번째 **43.1 ms · decode 0**. 앱에서 노출 0→0.80 과 히스토그램 갱신 확인. **FrameCacheManager FIFO 는 10번.**
3. **C1 필름 베이스** — C1.1~C1.9. RealScan 리베이트 집기 `0.40 0.13 0.07` + 현상본 유지.
4. **E4 인화 프리뷰** — **닫음.** 현상본 먼저, 칸이 크면 표시 크기 현상. 다음: B 메뉴막대
5. **B 메뉴막대** — 앱·파일·편집·보기 이식함. 다음: 라이브러리 메뉴
6. **D1 초기화 · D5 undo**
7. **GPU** ([`04`](04-gpu-plan.md))
8. **D2·D3 비교 캡슐·줌 HUD**
9. **D4 IR 프론트 · D6 내보내기 · D7 인화**
10. **F 문자열**
    
---

## C.2 추가 보고 — 여러 인스턴스 (2026-08-18)

| # | 증상 | 확인한 것 | 상태 |
|---|---|---|---|
| C14 | **앱을 동시에 여러 개 띄우면 고장난다** | Windows App SDK 기본은 multi-instance. OnLaunched 가 실행마다 새 MainWindow + 새 LibraryHostService 를 열었다. macOS 는 앱 프로세스 하나. | **2026-08-18 막음.** 로컬 뮤텍스가 COM 보다 앞에서 선출. 패키지된 두 번째 실행은 AppInstance 키 negaflow.primary 로 넘김. 패키지 없이 exe 직접 실행은 Application.Start 가 REGDB_E_CLASSNOTREG 로 죽으므로 창을 열지 않음. 실측 06:21 AUMID 동시 2회 프로세스 1개, 크래시 0. |

실측 (등록은 그대로 두고 AUMID 만 다시 실행):

- 첫 실행: `Negaflow.Shell` PID **20384**, 시작 04:39:08
- 같은 AUMID 재실행 1회: 프로세스 **1개**, PID **20384** 유지
- 같은 AUMID 재실행 2회: 프로세스 **1개**, PID **20384** 유지
- 새 Application Error / .NET Runtime 이벤트: **없음**

주의: `scripts/run-app.ps1 -SkipBuild` 는 `Add-AppxPackage -Register -ForceApplicationShutdown` 이라 패키지를 다시 등록하면서 기존 프로세스를 죽인다. 그것은 설치 경로이지 두 번째 실행이 아니다.

