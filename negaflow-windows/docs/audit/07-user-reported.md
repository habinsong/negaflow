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
| A4 | **Native `0xc0000409` 로 프로세스 종료** (`orca computer get-app-state` 와 겹치면 잘 남) | WER param 7 = `FAST_FAIL_FATAL_APP_EXIT`. `Negaflow.Native.dll+0xF4969` 디스어셈블 = CRT `abort()`. 같은 시각에 `0xc0000374` 힙 손상도 있음. `orca` 가 Native 를 직접 찌르는 코드는 없음. HEAD 디코드/프리뷰 raw 는 **프로세스 전역 슬롯 + 잠금 없음**. `ThumbnailService` 동시 3 + 현상 프리뷰가 같은 `develop_preview` 로 들어와 슬롯을 덮어쓰고 복사 중 해제 → UAF | **2026-08-19 코드·단위시험.** 프레임 키 + `mutex` + `shared_ptr<const WorkingImage>` + 바이트 예산. `run_develop` 은 `bad_alloc`/`...` 을 outcome 으로 돌림. `native.preview_raw_store` · `native.preview_proxy_cache` x64 Debug 통과. Shell.UnitTests 1127 통과. **아직 안 한 것:** 이 패치가 들어간 `run-app` x64 Release 실측. |

A4 확인(2026-08-19): `get-app-state` 의 UIA 순회/`--restore-window` 는 썸네일·레이아웃·프리뷰를 한꺼번에 깨우는 방아쇠일 뿐, 고유 원인이 아니다. 같은 `abort` RVA 는 orca 없이 난 dump 도 있다. 호출 스택 전체(누가 `abort` 를 불렀는지)는 Release PDB 미배포 + CDB 부재로 dump 에서 못 뽑았다.

고친 것: `decode.cpp` 상주 캐시와 `preview_raw_store` 를 프레임별로 나누고 잠그고, 꺼낸 쪽이 `shared_ptr` 을 들고 있는 동안 버퍼를 해제하지 않는다. 관리 쪽 `ThumbnailService.developed` 도 `FrameResidency` 한도로 내린다. 공개 `run_develop` 은 `noexcept` 경계에서 예외를 outcome 으로 바꾼다.

검증: x64 Debug `ctest -R "native.preview_raw_store|native.preview_proxy_cache"` 2/2. 동시 프리뷰 4스레드×6라운드 실패 0. `dotnet run` Shell.UnitTests Debug x64 assertions 1127 failures [].
**2026-08-19 `run-app -SkipBuild` x64 Release:** PID **4972** 유지, 창 제목 `negaflow`, WS 1369 MB, 10분 안 WER `0xc0000409` 없음. Develop 단추를 이 실행에서 새로 누르지는 않았다.

A1·A2 스택은 잡았고 고쳤습니다. A4 는 코드·단위시험까지 있고, Develop 단추를 누른
`run-app` Release 재현은 약합니다.

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
| 라이브러리 | `AppWorkflowMenuCommands.swift:8` `CommandMenu(.menuLibrary)` | **2026-08-19.** `AppMenuBarView` 다섯째 메뉴 `라이브러리`. PID 27388: UIA `이미지 가져오기` · `폴더 가져오기` · `라이브러리 새로고침` · `스캐너 불러오기` · `격자` · `비교` · `살펴보기` + 단축키 Ctrl+I / Ctrl+Shift+I / Ctrl+R / Ctrl+Alt+L / G / C / N. 인화에서 `살펴보기` → 라이브러리. `비교` → 빈 비교(`사진 두 장을 선택하세요`). `격자` → 카드 격자 복귀. macOS 는 격자/비교/살펴보기에서 `activeWorkspaceModule = .library` |
| 사진 | `:47` `CommandMenu(.menuPhoto)` | **2026-08-19.** `AppMenuBarView` 여섯째 메뉴 `사진`. PID 8148: UIA 18항목 — 이전/다음 · 선택/해제/제외/제거 · 별점 초기화·별 1–5개 · 가상 사본 · 현상 설정 복사/붙여넣기 · 좌/우 90도 · 좌우/상하 반전. 단축키 `[` `]` P U X Delete 0–5 Ctrl+' Ctrl+Shift+C/V Ctrl+Shift+[/] Ctrl+Alt+H/V. `별 3개` → 카드 별 3. `다음 사진`(] 과 같은 Invoke) → 옆 카드로 선택 이동. 폴더 묶음 GridView 는 그룹을 펴서 옮김 |
| 현상 | `:135` `CommandMenu(.menuDevelop)` | **2026-08-19.** `AppMenuBarView` 일곱째 메뉴 `현상`. PID 29760 UIA: 자동 톤(Ctrl+U) · 자동 화이트 밸런스(Ctrl+Shift+U) · 자동 색상(Ctrl+Shift+B) · 자동 레벨(Ctrl+Shift+L) · 노이즈 감소(Ctrl+Alt+N) · 프로세스(C-41/ECN-2 · E-6 · D-76 · B&W Reversal) · 타깃(MAIN·PRINT·HS·SP·F135·HR·EXPIRED) · 자르기 영역(R) · 베이스 스포이드(W) · GrainMend(자동 Shift+Q · 가이드 Q · 브러시 B · 복제 도장 S) · 모든 보정 초기화(Ctrl+Shift+R) · 좌우 이전/이후(\). Toggle·체크는 지금 사진 값을 따름 |
| 스캐너 | `:250` `CommandMenu(.menuScanner)` | **2026-08-19.** PID 23740 UIA: `스캐너 다시 찾기`(Ctrl+Shift+D) · `스캐너 시뮬레이터`(Ctrl+Alt+D, Toggle) · `프리뷰 스캔`(Ctrl+Alt+P) · `사진 스캔`(Ctrl+Alt+S). 평판일 때만 나오는 `프레임 추가/제거`(Ctrl+Alt+F / Ctrl+Alt+Delete)는 이 장치에서 macOS 처럼 **나오지 않음**. 메뉴에서 시뮬레이터 켜고 끄기 확인 |
| 내보내기 | `:292` `CommandMenu(.menuExport)` | **2026-08-19.** PID 34092 UIA: `빠른 내보내기`(Ctrl+E) · `내보내기`(Ctrl+Shift+E). 잠금은 `canQuickExportSelection` / `canExportSelection`(+이름 규칙) |
| 윈도우 | 표준(AppKit) | **넣지 않음(OS 강제).** Swift 에 `CommandGroup` 정의가 **없습니다** — macOS 의 윈도우 메뉴는 AppKit 이 주는 표준 메뉴입니다. Windows 에는 대응 표준이 없어 지어내지 않습니다(편집 메뉴의 잘라내기/복사/붙여넣기, 파일 메뉴의 New/Open/Close 와 같은 이유) |
| 도움말 | `AppStandardMenuCommands.swift:136` (`after: .help`) | **2026-08-19.** PID 34092 UIA: `단축키`(단축키 없음, 설정의 단축키 탭을 엶) · `빠른 시작`(Ctrl+Shift+H). 빠른 시작 창 560×480, 3단계 문구·문서 버전 확인 |

Parsec macOS 메뉴 줄: `negaflow · 파일 · 편집 · 보기 · 라이브러리 · 사진 · 현상 · 스캐너 · 내보내기 · 윈도우 · 도움말`.

**판정(2026-08-19): 11개 중 10개를 이식했습니다.** 남은 하나인 `윈도우` 는 macOS 에서도
Swift 가 만들지 않는 AppKit 표준 메뉴라 Windows 에 대응이 없습니다 — 지어내지 않습니다.

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
- Parsec macOS `OpticFilm8100_frame_5` 베이스 탭: `base 0.23 0.15 0.07` · 자동 선택. `C:\Users\habin\맥negaflow 스크린샷\현상뷰\현상뷰_우측탭_아이콘6탭바_베이스_자동.png` 와 카드 구조(헤더·읽음·자동/필름/수동) 같음. 프레임이 달라 숫자는 Windows frame_1 과 다를 수밖에 없음.

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
| D1 | **초기화 — 모든 보정 / 사진 각도** | **2026-08-19 붙음.** `DevelopResetCard` + `DevelopInspectorResetter` + 현상 메뉴 |
| D2 | **비교 캡슐** | 토글+분할+Before 소스 2026-08-19. 앱에서 메뉴 클릭 실측은 남음 |
| D3 | **줌 HUD** | 수식+단추+끌기 2026-08-19 (`CanvasHudInteractionState`). 인화 HUD 위치는 남음 |
| D4 | **GrainMend IR 프론트엔드** | 짝짓기+선택 시 자동 정리 2026-08-19. GrainMend 5번째 단추는 Swift 에도 없음 |
| D5 | **undo/redo** | 초기화 undo + 슬라이더 0.7s 묶음 2026-08-19 (`FrameEditHistory`). 결함 undo·히스토리 패널은 남음 |
| D6 | **내보내기 35파일** | 배치·체크포인트·커밋저널·트랜잭션·검증등급·Reveal·가용성·실체화·추적 + UI 7개 |
| D7 | **인화 8파일** | 커스텀 패키지 오버레이·레이아웃 템플릿·아티팩트 배치·캡션 포맷터·설정 이력·사이드바·매니페스트 검사 |

---

## E. 성능

| # | 증상 | 원인 (확정) |
|---|---|---|
| E1 | 사진 바꾸면 수 초 | **2026-08-19.** 디코드 단일 슬롯 + **프리뷰 raw 프록시 2슬롯**(인터랙티브/정착). 프리뷰는 결함·필름베이스를 원본에서 푼 뒤 `displayProxy` 와 같이 Lanczos3 로 상자 맞춤하고 **그 작은 raw 에서 현상**. 내보내기·검출은 원본 해상도. 실측 5088×3401: 상자 1280 두 번째 프리뷰 **43.1 ms · decode runs 0** (첫 549.6 ms 중 decode 187.9). 상자 3600 두 번째 **260.6 ms · decode 0**. 앱 슬라이더 벽시계는 아직 설치본에서 재는 중. |
| E2 | 우측탭 기능 하나 써도 수 초 | E1 과 같은 경로. CLI/시험은 두 번째 호출에서 디코드 0. **앱에서 슬라이더를 두 번 끌어 확인하는 것이 남음.** |
| E3 | GrainMend 자동이 느림 | 형태학+스크래치 각도 GPU 기본 켬. 검출 **4.66s**. 가이드·브러시·복제·IR 즉각은 앱 미측정 |
| E4 | **인화 프리뷰가 깨짐** | **2026-08-19.** `developedImage ?? thumbnail` 순. 현상 미리보기 화소를 기억하고, 칸이 더 크면 `PrintPreviewResolution.renderDimension`(720…2560) 으로 현상본을 올림. 앱: RealScan·OpticFilm8100_frame_1 인화 판에 현상본, 열차 번호 2355 판독. 360 JPEG 확대 아님 |

---

## F. 문자열 오류 — **2026-08-19 아홉 건 고침, 두 건은 오류가 아니었음**

| # | 키 | 앞 | macOS 원문 | 상태 |
|---|---|---|---|---|
| F1 | `libraryTarget` | `타깋` | `타깃` | **고침.** 현상 메뉴 타깃 하위 메뉴 이름으로 앱에 그대로 보였음(UIA) |
| F2 | `libraryLook` | `룹` | `룩` | **고침** |
| F3 | `developFilmStock` | `필름스톡` | `필름 스톡` | **고침** |
| F4 | `developMidtones` | `중간톤` | `중간 톤` | **고침** |
| F5 | `settingsDefaultScanRotationPicker` | 기본 스캔 회전 | 스캔 기본 방향 | **고침(6언어)** |
| F6 | `scannerTruth` | 스캐너 성능 | 스캐너 정보 | **고침(6언어)** |
| F7 | `defaultDefectMicroSpecks` | 미세 반점 기본값 | 미세 입자 기본 검출 | **고침(6언어)** |
| F8 | `defaultDefectMicroSpecksHelp` | "새로 여는 결함 도구가…" | "새 프레임의 시작값이며 자동과 가이드를 따로 기억합니다…" | **고침(6언어)** |
| F9 | 프로세스 메뉴 문구 | `컬러 네거티브` 등 번역 이름 | `C-41/ECN-2` · `E-6` · `D-76` · `B&W Reversal` | **고침**(`developmentProcessName`) |
| ~~F10~~ | `filmLookDigitalOnly` 의 `Digital B&amp;W` | — | — | **오류 아님.** `.resw` 는 XML 이라 `&amp;` 가 정상 이스케이프이고 화면에는 `Digital B&W` 로 나옴 |
| ~~F11~~ | `namedFrameCopyDisplayFormat` `{0} 사본 %d` | — | `%@ 사본 %d` | **오류 아님.** `{0}` 은 macOS `%@` 자리를 대신하는 이름 칸이고 `LibraryWorkspaceCopy.cs:24` 가 이름을 끼움 |

**남은 것:** 685개 resw 항목 전체를 macOS 표와 기계로 대조한 적이 **없습니다.**
`scripts/sync-swift-ui-strings.ps1` 은 저장소 구조가 바뀌기 전 경로
(`<repo>/Sources/negaflowApp/...`)를 보고 있어 지금은 **깨져 있고**, 매핑
(`baseline/swift-ui-string-map.json`)에 92개만 있어 그대로 돌리면 나머지 593개를
지웁니다. 쓰지 마십시오 — 대조기는 따로 만들어야 합니다.

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

**판정(2026-08-19): 프론트엔드에 적용 단추 없음, 백엔드에 일괄 적용 경로 없음.**

### F.1.1 닫음 — 2026-08-20

| 무엇 | Windows | macOS 대응 |
|---|---|---|
| 백엔드 | `Shell.Core/Library/LibraryFolderDevelopment.cs` | `AppModel+LibraryFolderDevelopment.swift` |
| 보이는 타깃 | Main · Noritsu · Sp3000 · F135 · Hr **5개** | `visibleTargets` 와 같은 순서 |
| 적용 | `Apply(host, frames, process, target, progress)` — 프레임마다 `EditRoute` → `Edit(ProfileAfterTargetChange)` | `applyLibraryFolderDevelopment(process:target:frames:progress:)` |
| UI | `LibraryWorkspaceView.xaml` 폴더 머리줄: 프로세스 98×30 · 타깃 84×30 · **적용** 30 높이, 라운딩 8, 진행 문구 | `LibraryFolderBatchPicker` 2개 + `LibraryFolderApplyButton` |
| 자동화 ID | `negaflow.library.folder-develop-apply` | — |

피커는 **초안**입니다(`LibrarySourceRail.folderDrafts`) — macOS 도 `@State` 로 들고 있다가
**적용을 눌러야** 프레임에 씁니다. 고르기만 해서는 사진이 바뀌지 않습니다.

시험: `tests/Shell.UnitTests/LibraryFolderDevelopmentTests.cs`.
**앱에서 눌러 본 실측은 아직입니다** — 폴더 머리줄을 띄우고 확인해야 합니다.

---

## J. 2026-08-20 사용자 보고 — 빠른 동작 알약

> "자동색상/자동레벨/자동톤/자동 화이트 밸런스 ... 버튼 눌렀을때 음영 크기도 이상하고,
> 클릭도 이상하고, 클릭후에 글자는 거의 안보이고 무엇보다 버튼 누르면 앱 강제 종료됨"

### J1 모양 - 세 가지가 전부 같은 원인(WinUI 기본 판형)

macOS `DevelopQuickActionsSection.swift` 의 `QuickTogglePill` 은 `.buttonStyle(.plain)` 에
손수 칠한 바탕만 씁니다:

| macOS | 값 |
|---|---|
| 알약 전체 | `frame(maxWidth: .infinity, minHeight: 32)` + `contentShape(Rectangle())` |
| 켜짐 | `Color.accentColor.opacity(0.2)`, 라운딩 **12** |
| 마우스 올림 | `Color.primary.opacity(0.12)` |
| 글자·아이콘 | 켜짐 `accentColor` / 꺼짐 `Color.primary` |
| 바깥 표면 | `liquidSurface(cornerRadius: 15)` |

Windows 는 기본 `ToggleButton` 판형을 그대로 썼습니다. 그 판형은 **켜지면
ContentPresenter 를 강조색으로 꽉 칠하고 글자색도 바꿉니다.** 거기에 코드가 글자색을
다시 강조색으로 칠했으니 **강조색 바탕 + 강조색 글자** — 그래서 글자가 안 보였습니다.
칠이 테두리·안쪽 여백만큼 작아져 "음영 크기"가 어긋났고, 누를 수 있는 자리도
알약 전체가 아니었습니다.

**고침(2026-08-20):** `src/Shell/Styles/Pills.xaml` 에 판형 셋을 새로 짰습니다 —
`NegaflowPillToggleStyle` · `NegaflowPillButtonStyle` · `NegaflowPillResetButtonStyle`.
바탕은 `Background="Transparent"` 인 격자(전체가 눌립니다), 켜짐 칠은 별도 `Border`
(라운딩 12, `NegaflowAccentSoftBrush` = 강조색 20%), 글자는 `NegaflowAccentBrush`.
**WinUI 의 `ToggleButton` 은 켜짐도 `CommonStates` 한 무리로 다룹니다**(WPF 처럼
`CheckStates` 가 따로 있지 않습니다) — `Checked`/`CheckedPointerOver`/`CheckedPressed`/
`CheckedDisabled` 네 상태에 같은 설정을 답니다.

앱 실측(UIA, 150% 배율이라 물리 화소):

| | 실측 | 논리(1.5로 나눔) | macOS 스크린샷 |
|---|---:|---:|---:|
| 알약 높이 | 48 | **32** | 32 |
| 칸 사이 | 12 | **8** | 8 |
| 줄 사이 | 12 | **8** | 8 |
| 되돌리기 | 36x36 | **24x24** | 24x24 |

`ToggleState` 는 UIA 로 24회 눌러 On/Off 가 번갈아 바뀌는 것까지 확인했습니다.

### J2 강제 종료 - 원인은 **소멸 순서**였습니다

가설로 만든 스트레스 시험(`preview_auto_levels_stress`)은 **10/10 통과** - 재현하지
못했습니다. 가설이 틀렸습니다. 사용자 지적대로 **로그를 붙이고 단추를 여러 번 눌러**
재현했습니다(3번째 클릭에서 `0xC0000005`).

| 단계 | 무엇 |
|---|---|
| 1 | `src/Native/abi/support/crash_log.cpp` - VEH 로 예외 코드·주소·모듈 RVA·스택 RVA 를 `%LOCALAPPDATA%\Negaflow\Logs\native-crash.txt` 에 남김 |
| 2 | `cmake/CompilerWarnings.cmake` - Release 도 `/Zi` `/DEBUG` `/OPT:REF` `/MAP`. (`/OPT:ICF` 는 **켜지 않습니다** - 람다가 접히면 스택이 거짓말을 합니다) |
| 3 | `scripts/symbolize-rva.ps1` - dbghelp `SymFromAddr`+`SymGetLineFromAddr64` 로 RVA 를 함수·줄로 |
| 4 | 확정: `pipeline/develop_export.cpp` 가 `GpuResidentScope` 를 **단계 출력보다 뒤에** 선언 |

C++ 는 선언의 **역순**으로 지웁니다. 상주 범위가 먼저 죽으며 `flush_resident()` 가
**이미 사라진 출력 버퍼**에 내려썼습니다. 출력들을 범위보다 **앞에** 선언해 고쳤습니다.

곁가지로 `core/row_block_pool.cpp` 의 완료 통지를 잠금 **안**으로 옮겼습니다
(`--remaining` 뒤 잠금 밖에서 `notify_all` 하면 기다리는 쪽 스택이 먼저 풀릴 수 있습니다).

**재현으로 확인:** 같은 조작 160회 + UIA 토글 24회, 죽지 않음. `native-crash.txt` 새 줄 없음.

### J2.1 ☠️ 그 고침은 **절반이었습니다** (같은 날 다시 죽음)

현상 좌측탭에서 타깃(MAIN/HS/SP/F135/HR)을 잇달아 누르니 **또 죽었습니다.** 이번에는
`crash_log.cpp` 가 남겼고, `symbolize-rva.ps1` 로 스택 전체를 되돌렸습니다:

```
develop_run_v29_v34.cpp:416
 -> develop_export.cpp:348 -> :299(함수 끝) -> :271
    -> ~GpuResidentScope -> end_resident(gpu_accelerator_resident.cpp:157)
       -> flush_unlocked(:22) -> GpuWorkingImage::download(:402 -> :169)
          -> copy_rows -> parallel_rows.cpp:150 -> row_block_pool.cpp:37 -> memcpy
```

`access write at 0x...` — **해제된 메모리에 쓰기**입니다.

원인: 상주 프레임(`State::ResidentFrame::host`)은 **남의 버퍼를 가리키는 생포인터**입니다.
단계 함수들은 이미지를 **값으로 받아**(`std::move(invert.image)` 등) 다 쓰고 버리는데,
그 버퍼가 사라져도 묶음은 남습니다. 앞선 고침(선언 순서)은 **함수 지역 변수**의 파괴
순서만 바로잡았을 뿐, 단계 **안에서** 죽는 중간 버퍼는 그대로였습니다.

**고침:** `GpuAccelerator::flush_resident_if(host)` — 그 버퍼가 지금 묶여 있을 때만
내리고 묶음을 풉니다(아니면 아무 일도 안 하므로 상주 최적화는 그대로). `develop_export.cpp`
가 이미지를 넘기기 직전 네 자리에서 부릅니다(invert → look → grain → finish).

**재현으로 확인:** 타깃 15회 연속 전환 + 자동 색상/레벨 토글 20회, 죽지 않음.
`native-crash.txt` 새 줄 없음. ctest 102/102 · catalog 747 · shell 1411 · 경고 0.

### J3 남은 것

- 알약 아이콘 3개가 macOS SF Symbol 과 다릅니다 -> [`08`](08-icons-and-chrome.md) 5절
- `negaflow.develop.quick-actions` 자동화 ID 가 `StackPanel` 에 있어 UIA 로 안 잡힙니다
  (컨트롤 뷰에 안 올라오는 요소입니다). 판정에 쓰려면 잡히는 요소로 옮겨야 합니다

---

## K. 2026-08-20 — 현상 좌측탭 프로세스·타깃 (사용자가 두 번 지적)

> "지금 현상 프로세스, 타깃 UI/UX 없는데 그거 제대로 만들고 백엔드 코드 제대로 만들어라"

### K1 앱이 아예 **안 떴습니다** — resw 중첩

띄워서 확인하려는데 창이 열리지 않았습니다. `%LOCALAPPDATA%\Negaflow\Logs\startup-fault.txt` :

```
Microsoft.UI.Xaml.Markup.XamlParseException
Cannot create instance of type 'Negaflow.Shell.Views.PrintWorkspaceView'
System.InvalidOperationException: Missing localized resource: printOutputProcess.Text
```

resw 에는 그 키가 **있었습니다**(6개 언어 모두). 그런데 `makepri dump` 로 세어 보니
PRI 에는 741개 중 **20개가 통째로 빠져** 있었고, 빠진 것이 전부 그날 새로 붙은
`printLayoutTemplate*` · `printOutput*` · `printCprint*` · `printProof*` 였습니다.

원인: 그 20개가 `<data name="printOutputSection.Content" ...>` **안쪽에** 들어가
있었습니다. XML 로는 올바르지만(그래서 파서·정규식 검사는 통과) **MakePri 는 중첩된
`<data>` 를 세지 않습니다.** 형제 자리로 되돌려 고쳤습니다 — 문구는 한 글자도
손대지 않았습니다.

**교훈:** resw 를 손으로 고친 뒤에는 **PRI 에 들어갔는지**까지 봐야 합니다
([`11`](11-ui-verification-protocol.md) 6.5).

### K2 UI 는 있었고, **백엔드가 안 붙어 있었습니다**

앱이 뜬 뒤 UIA 로 재현했습니다.

| 증상 | 원인 | 고침 |
|---|---|---|
| 타깃 막대가 낱개 단추 다섯 개(간격 4 · 파란 배경) | macOS `SegmentedPicker` 와 다른 창작 | `Styles/Segments.xaml` — 트랙 라운딩 11 · 여백 3 · 칸 사이 3 · 칸 높이 28 · 고른 칸 8. 필름 베이스 모드 세 칸도 같은 판형 |
| 타깃을 눌러도 **필름 프로파일이 안 따라옴** | 값을 바꾼 뒤 이 구획을 다시 읽지 않음 | 바꾼 뒤 다시 읽습니다(알림 → 다시 읽기 순서) |
| 카탈로그만 바뀌고 **화면·프리뷰는 옛 값** | `DevelopDefaultsChanged` 를 **아무도 듣지 않았습니다** | `DevelopInspectorSync` 가 받아 프레임을 다시 읽고 인스펙터·프리뷰를 갱신(macOS `applyDevelopTarget` → `developFrame`) |
| 룩 칸이 비어 보임 | 프레임에 룩이 없을 때 아무것도 안 고름 | macOS 처럼 `neutral` 을 보입니다 |

**재현으로 확인(UIA):** MAIN→HS→SP→F135→HR 을 눌러 필름 프로파일이
`MAIN`→`HS`→`SP`→(피커 접힘, 이름만) 로 따라오고, 룩이 `Neutral` 로 보입니다.
메뉴(현상 > 타깃)의 체크도 같이 움직입니다 — 모델이 실제로 바뀐 증거입니다.

---

## G. 다음 순서 (2026-08-20 갱신)

닫힘(다시 하지 말 것): A1·A2·A3 · E1 네이티브 캐시 · C1.1–C1.9 · E4 · B 메뉴 10/11 ·
D1 초기화 · D5 슬라이더 undo · GPU 3.1–3.8 · D2/D3 코드 · D4 짝짓기 · F 9건 · 단축키 열거자 ·
**F.1 폴더별 적용** · **J1 알약 모양** · **J2 자동 레벨 강제 종료** · **다국어 즉시 전환** ·
**K2 현상 좌측 프로세스/타깃(UI+백엔드)** · **K1 resw 중첩** ·
**`native.gpu_film_scan` 원인 확정·해결**([`01`](01-backend-gaps.md) 9.4).

지금 남은 것:

1. **3뷰 좌측 세로 레일·좌측탭·우측탭·상단탭 1:1** — [`02`](02-frontend-gaps.md) 2.3.
   현상 좌측탭은 6탭이 다 있지만 **라이브러리 뷰의 레일은 3개뿐**이고, 인화 뷰의
   사이드바는 아직 없습니다
2. **앱 실측** — 슬라이더 벽시계 · A4 Develop 클릭 · IR 쌍 가져오기 · Before 메뉴 클릭 ·
   F.1 폴더 적용 단추를 앱에서 눌러 보기
4. **05 생산 God object 10개** — 사유를 적거나 나누기 (`LibraryWorkspaceView.xaml` 이
   폴더 머리줄 때문에 504줄로 넘었습니다 — 이 세션이 넘긴 것입니다)
5. **09 설정** — 디스크·메모리캐시·지원번들 섹션
6. **D6 내보내기 배치/저널 · D7 인화 사이드바/템플릿**
7. C7 상단 별점 · 08 아이콘 SVG·알약 아이콘 3 · 필터 캡슐 배치
8. **16** 커브 중간 왕복은 재서 기각. 해상도 접기 금지
    
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


---

## I. 2026-08-20 사용자 보고

| # | 증상 | 원인 (확정) | 상태 |
|---|---|---|---|
| I1 | **설정에서 언어를 바꿔도 안 바뀐다** | ① `AppResources` 의 `ResourceLoader` 가 `static readonly` 라 만들 때의 언어 문맥을 계속 씀 ② 문구를 다시 걸어 주는 길이 아예 없음 ③ `x:Uid` 56곳은 XAML 을 읽을 때 한 번만 풀림 | **2026-08-20 고침.** MRT Core `ResourceContext` 교체 + `LanguageChanged` 로 화면 전체 다시 걸기 + `x:Uid` → 코드. 앱에서 메뉴막대가 그 자리에서 한국어↔English 로 바뀌는 것 확인([`18`](18-localization.md) 1절) |
| I2 | **다국어를 창작하지 말고 macOS 것 그대로** | resw 주석의 원본 심볼로 macOS 표와 전수 대조 → **16건이 손으로 옮기다 달라져 있었음**(`settingsDefaultScanRotationHelp` 5언어 등) | **2026-08-20 고침.** 대조기 `scripts/compare-mac-strings.py`. 지금 다른 것 **0건**, OS 강제 예외 4개만 남김([`18`](18-localization.md) 3·4절) |
| I3 | **UI/UX 를 스크린샷과 대조하지 않았다** | 이번 세션은 메뉴·백엔드만 고치고 `맥negaflow 스크린샷` 50장을 한 장도 열지 않았음 | **미착수.** 다음 세션의 첫 일 |

---

## H. 2026-08-19 — 슬라이더 지연 · 사진 전환 크래시의 원인과 조치

사용자 보고: "현상뷰 우측탭 슬라이더 값 조절하면 수초", "사진 바꾸면 앱 터짐",
"이미지 전환도 느림". **추측 없이 원인을 확정한 뒤 고쳤습니다.**

### H.1 크래시 — 원인 확정 (이벤트 로그 + 디스어셈블)

Windows 이벤트 로그 `Application Error`:

| 시각 | 코드 | 모듈 |
|---|---|---|
| 09:01:08 · 09:06:07 · 10:38:08 | `0xc0000409` | **`Negaflow.Native.dll +0xf4969`** (세 번 다 같은 오프셋) |
| 10:37:53 | `0xc0000374` (힙 손상) | `ntdll.dll` |

`+0xf4969` 를 `dumpbin /disasm` 으로 풀었습니다:

```
sub rsp,28h ; call ... ; mov ecx,16h ; call raise      ← SIGABRT
mov ecx,17h ; call IsProcessorFeaturePresent           ← PF_FASTFAIL_AVAILABLE
mov ecx,7   ; int 29h                                  ← __fastfail(FAST_FAIL_FATAL_APP_EXIT)
```

**CRT `abort()`** 입니다. 곧 `noexcept` 함수에서 예외가 새어 `std::terminate` 로 간 것입니다.

### H.2 진짜 원인 — 프리뷰 프록시 슬롯이 **프로세스 전역 2개**였음

macOS 는 이 두 슬롯을 **`ScanFrame` 에 붙여** 둡니다
(`ScanFrame.swift:176-182` `cachedInteractivePreviewRaw` / `cachedSettledPreviewRaw` /
`cachedInteractivePreviewRawDimension`). Windows 는 `preview_proxy.cpp` 의
**전역 두 개**로 옮겨 놓았고, 거기서 두 가지가 한꺼번에 깨졌습니다.

**① 썸네일이 현상 슬롯을 계속 덮어썼습니다.**
`ThumbnailService.Render`(`ThumbnailService.cs:295`)가 `exporter.Preview(request, 360, 360, …)`
로 **같은 `develop_preview`** 를 부릅니다. `slot_for_box(360,360)` 은 360 < 3600 이라
`g_interactive` — 슬라이더가 쓰는 바로 그 슬롯입니다. `DevelopFrameList.cs:73-80` 이
현상 뷰 새로고침마다 **모든 프레임**에 썸네일을 요청하고 동시 실행이 3개
(`MaximumConcurrentRenders`)이므로, 슬라이더의 다음 요청은 상자가 안 맞아 **매번 미스** →
원본 재디코드 + 원본 해상도 베이스 해석 + Lanczos.
`decode.cpp` 의 디코드 캐시도 **경로 하나짜리 단일 슬롯**이라 같이 날아갔습니다.

**② 그 전역에 잠금이 한 글자도 없었습니다.**
썸네일 스레드의 `slot.image = image`(옛 버퍼 해제 후 재할당)와 프리뷰 스레드의
`image = slot.image`(그 버퍼 읽기)가 겹쳐 **use-after-free**. 이것이 H.1 의 두 코드입니다.
사진을 바꾸는 순간이 썸네일이 한꺼번에 뜨는 때라 경합이 최대였습니다.

`WorkingImage` 는 화소당 `Rgba32F` 16바이트라 5088×3401 한 장이 **277 MB** 입니다.
캐시 히트마다 그것을 통째로 복사하고 있었습니다.

### H.3 조치 (네이티브)

| 파일 | 무엇 |
|---|---|
| `export/support/preview_raw_store.{h,cpp}` (신규) | **프레임 키** 기반 상주 캐시. 뮤텍스 + `shared_ptr<const WorkingImage>`. macOS `markDevelopedResident` 의 **FIFO 재등록** + `trimDeveloped` |
| `export/support/frame_cache_budget.{h,cpp}` (신규) | macOS `FrameCacheBudget` 이식. 비율(16GB 25% → 96GB 35%)과 배분비(190 : 2×170)는 그대로, **한 프레임 비용만 실제 바이트로** — Windows 는 화소당 16바이트라 macOS 추정(8바이트 가정)의 2배이기 때문 |
| `export/support/preview_proxy.cpp` | 전역 2슬롯 제거. macOS `preloadedFullPreviewRaw` 이식 — **정착 raw 가 있으면 인터랙티브를 Lanczos 로 파생**하고 디코드하지 않음(`DevelopFrameRenderer+Input.swift:51-52`) |
| `export/stages/decode.cpp` | 단일 슬롯 → 프레임별 FIFO + 뮤텍스 + `shared_ptr`. 복사는 **잠금 밖에서** |
| `develop_export.cpp` | `run_develop` 에 예외 차단막. 메모리 부족은 **프로세스를 죽일 이유가 아니라 이 렌더가 실패할 이유** → `out_of_memory` outcome |

### H.4 조치 (셸)

| 파일 | 무엇 |
|---|---|
| `Library/Cache/FrameCachePolicy.cs` · `FrameCacheBudget.cs` · `FrameResidency.cs` (신규) | macOS `FrameCachePolicy` · `FrameCacheBudget` · `FrameCacheManager` 이식(선택 프레임 보호 포함) |
| `ThumbnailService.cs` | `developed` 사전에 **축출이 없어** 프레임당 34.6MB 를 영구 보유하던 것을 FIFO 로. `PublishFromDeveloped` 추가 — 866만 화소 축소를 UI 스레드에서 워커로 |
| `DevelopWorkspaceView.xaml.cs` | `RememberDeveloped`/`Publish` 를 **정착 패스에서만**. 앞 판은 슬라이더 한 칸에 **두 번** 34.6MB 복사 + 축소를 UI 스레드에서 함 |
| `DevelopPreviewCanvas.xaml.cs` | 인터랙티브/정착 치수가 달라 매번 새로 만들던 `WriteableBitmap` 을 두 벌 돌려 씀 |
| `PreviewCoordinator.cs` | 화소 버퍼 **두 장 교대** — 배달한 버퍼를 다음 렌더가 덮어써 히스토그램·스포이드가 찢어진 화소를 읽던 것 |

### H.5 Windows 전용 최적화 — 인터랙티브 상자를 실측으로 접음

`--gpu-transfer-bench` 실측(264 MB, RTX 4060 Ti):

| | ms |
|---|---:|
| 업로드 | 8.5 |
| **디스패치** | **0.014** |
| 다운로드 | 58 |

**연산은 공짜이고 왕복 전송이 전부입니다.** 단계마다 왕복하므로 3600 정착 한 장이
GPU 허용 **298 ms**(CPU 전용 453 ms). 단계별: `develop` 113 · `tone_adjust` 75 · `output` 81.

macOS 는 인터랙티브 패스를 캔버스 디바이스 픽셀 그대로 그립니다 — 파이프라인 전체가
CoreImage/Metal 이라 됩니다. Windows 는 아직 대부분 CPU 라 같은 치수(이 화면 150% DPI 에서
3072 = 630만 화소)면 한 칸에 200 ms 가 넘습니다.
그래서 `DevelopPreviewProxy.InteractiveProxyDimension` 에 **실측 처리량 기반 접기**를
넣었습니다. 예산은 macOS `waitForDevelopSettle` 0.14초의 **절반(70 ms)** — 정착 판정이
서기 전에 인터랙티브가 최소 두 장 나와야 따라온다고 느끼기 때문입니다.
하한은 macOS `interactiveMinDimension` 1024, 계단은 macOS 256 그대로.
**화질은 잃지 않습니다** — 손을 멈추면 0.14초 뒤 정착 패스가 3600 으로 다시 그립니다.

### H.6 실측 (실제 5088×3401 OpticFilm 스캔, 사이에 다른 프레임 썸네일 렌더를 낀 앱과 같은 상황)

| | 슬라이더 한 칸 (네이티브 인터랙티브 패스, 1280 상자) |
|---|---:|
| 고치기 전 (= 매번 콜드) | **573.4 ms** |
| 고친 뒤 (캐시 적중) | **45.9 ms** |

앱 작업 집합: **2,054 MB → 1,181 MB**(실행 직후).

### H.7 시험

- `tests/Native.UnitTests/preview_raw_store_tests.cpp` (신규) — ① 다른 프레임 썸네일이
  현상 프록시를 안 밀어냄 ② 새 인터랙티브 상자가 정착본에서 파생(디코드 0회)
  ③ 4스레드 동시 프리뷰가 전부 성공
- `tests/Shell.UnitTests/FrameResidencyTests.cs` (신규) — FIFO 축출 · 재등록 · 선택 프레임
  보호 · macOS 예산 상수 · 인터랙티브 접기

게이트: native **101/101**, catalog **731**, shell **1133**, 경고 0.

### H.8 확인 못 한 것 — 정직하게

- **앱에서 슬라이더 벽시계를 아직 못 쟀습니다.** 네이티브 패스와 UI 스레드 작업은
  각각 쟀지만, 사용자가 끄는 동안의 체감은 앱에서 재야 합니다.
- **invert→tone 왕복은 2026-08-19 에 한 번으로 줄였습니다.** 아직 남은 것은
  `output` BGRA8 내리기와 커브 중간 측정 왕복입니다. 앱 슬라이더 벽시계는
  **못 쟀습니다.**
- 스테이징 읽기를 `MOVNTDQA` 스트리밍 로드로 바꿔 봤으나 **58 → 61 ms 로 더 느렸습니다**
  (이 드라이버의 스테이징은 write-combined 가 아님). 되돌렸습니다 — 가설은 기각입니다.

### H.9 정정 — 인터랙티브 상자 접기는 **되돌렸습니다**

H.5 에 적은 "실측 처리량으로 인터랙티브 상자 접기"를 넣었다가 **제거했습니다.**
속도는 붙었지만 사용자가 곧바로 "프리뷰가 저해상도라 깨져 보인다"고 잡아냈습니다.
**해상도를 깎아 얻는 속도는 답이 아닙니다.** `interactiveProxyDimension` 은 macOS 그대로
(표시 픽셀 → 256 양자화 → 1024…3600)로 되돌렸고, 속도는 파이프라인에서 내야 합니다.

### H.10 "사진이 바로 반영이 안 된다" — 원인 둘, 조치 둘

사용자 보고: 손잡이는 따라오는데 **그림이 안 바뀐다.**

**① 인터랙티브 렌더를 매번 취소하고 버렸습니다.**
`PreviewCoordinator.RequestAsync` 가 새 요청마다 `activeRun.Cancel()` 하고
`RunLoopAsync` 는 취소된 결과를 배달하지 않습니다. 그래서 **계속 끄는 동안에는 어떤 렌더도
완주하지 못해 화면이 한 장도 안 바뀌었습니다** — 손을 멈춰야 비로소 한 장이 나왔습니다.
→ **인터랙티브는 취소하지 않고 끝까지 그려 배달**하고, 곧바로 최신 값으로 다음 장을 그립니다.
정착(3600)은 길고 결과가 이미 지나간 상태이므로 그대로 끊습니다.
시험 `preview_cancels_the_superseded_render` · `preview_delivers_only_the_last_request` 가
**옛 동작을 못 박고 있었습니다** — 계약을 고쳐
`preview_lets_the_interactive_render_finish` · `preview_delivers_every_finished_interactive_render`
로 바꿨습니다.

**② 인터랙티브 결과가 화면에 아예 안 나갔습니다.**
`RenderAsync` 가 결과를 **하나만** 돌려주므로, 손을 멈춰 정착이 성립하면 인터랙티브 그림은
버려지고 정착본이 나올 때까지(3600 에서 약 300 ms) 옛 그림이 남았습니다. macOS 는 인터랙티브
패스가 끝나면 그 자리에서 `frame.developedImage` 를 갈아 끼웁니다
(`AppModel+DevelopRendering.swift:81-84`).
→ 인터랙티브를 **그 자리에서 배달**하고, 정착본이 오면 다시 배달합니다.

### H.11 "다른 사진으로 이동이 느리다"

전환하면 새 사진의 콜드 렌더가 끝날 때까지 캔버스에 **옛 사진**이 남았습니다.
macOS 는 `ScanFrame.developedImage` 가 프레임마다 남아 있어 고르는 즉시 뜹니다.
Windows 는 그 화소를 `ThumbnailService.TryGetDeveloped` 에 **이미 갖고 있으면서 쓰지
않았습니다.**
→ `DevelopWorkspaceView.PresentCachedDeveloped` — 사진을 바꾸는 순간 그 사진의 마지막
현상본을 곧바로 올리고, 없으면 360 썸네일을 올립니다(macOS `thumbnailImage` 폴백).

### H.12 남은 것 — **GPU 왕복이 전부입니다**

`--gpu-transfer-bench` 실측(264 MB, RTX 4060 Ti):

| | ms |
|---|---:|
| 업로드 | 8.5 |
| **디스패치** | **0.014** |
| 다운로드 | 58 |

**연산은 사실상 공짜입니다.** 그런데 단계마다 올렸다 내립니다 — 3600 정착 한 장이
GPU 허용 **298 ms**(CPU 전용 453 ms), 단계별 `develop` 113 · `tone_adjust` 75 · `output` 81.
`gpu_tone_stage.cpp:278` 은 톤 커브가 켜져 있으면 밴드 측정 때문에 **중간에 한 번 더**
내려받습니다.

**2026-08-19 상주 사슬(①의 첫 조각).** macOS `CIImage` 가 마지막에 한 번 평가되는 것과
같게, 프리뷰 `invert`→`tone` 을 `GpuResidentScope` 로 묶었습니다
(`DevelopFrameRenderer.sharedRenderContext`). 커널은 새로 만들지 않았습니다.

| | H.12 직전 (같은 원본, RTX 4060 Ti, 상자 3600) | 지금 Release `nocurve` 두 번째 |
|---|---:|---:|
| `develop` | 113 | **55.5** |
| `tone_adjust` | 75 | **19.3** |
| `output` | 81 | **64.2** |
| 단계 합 | 298 | **153.7** |
| 벽시계 두 번째 | 298 | **182** |

시험 `native.gpu_accelerator` `invert_then_tone_is_one_host_round_trip`:
풀해상도 **올리기 1 · 내리기 1**, CPU 대비 최대 오차 **1.43e-06**. 같은 숫자 두 번.
커브가 켜지면 밴드 측정 때문에 중간 내리기가 남습니다.

**2026-08-19 ② BGRA8 출력.** macOS `createCGImage(.RGBA8)` 대응.
`write_preview` 가 1:1 이면 `try_encode_preview_bgra`. 항등 look/grain/finish 는
낡은 float 호스트를 안 만집니다. Release `nocurve` 두 번째: `output` **78.15 → 7.01 ms**,
`tone_adjust` **18.99 → 0.02**, 단계 합 **167.7 → 65.0**, 벽시계 **196 → 93 ms**.
CLI 작업 집합 봉우리 **557 MB**(앞 판 508). 시험
`invert_then_tone_preview_is_one_bgra_download`: 올리기 1 · 내리기 1 ·
`downloaded_bytes = w*h*4` · 8비트 ≤1 코드. Debug/Release 각 2회 + Debug ctest 101/101.

**아직 남은 것:**
③ 커브 중간 float 왕복. **2026-08-19 실측:** 있는 `GpuMipHalve` 로 측정하면
GPU/CPU **2.55e-04**(허용 1e-5). 기각·되돌림. `GpuAreaAverage` 는 격자 대체 불가.
CLI 커브 켬 두 번째 `tone_adjust` **25.59 ms**(상자 3600, BGRA8 이후 바이너리).
앱 작업 집합 ~1GB/렌더 누수는 **이 세션에서 앱으로 못 쟀다.**
A4 `run-app` x64 Release 실측도 **못 했다**(코드는 들어가 있음).

**기각한 가설:** 스테이징 읽기를 `MOVNTDQA` 스트리밍 로드로 바꿔 봤으나 58 → 61 ms 로
**더 느렸습니다**. 이 드라이버의 스테이징은 write-combined 가 아닙니다. 되돌렸습니다.
