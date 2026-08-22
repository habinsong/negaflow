> # 하드코딩 · 가짜 구현 · 창작 · 병신 백엔드 · 병신 프론트엔드 = 죽음
>
> **문구는 손으로 옮기지 마십시오.** 이 문서의 대조기로 macOS 표에서 기계로 가져옵니다.
> 손으로 옮기면 오타가 납니다 — 실제로 났습니다(4절).

# 18 — 다국어 (2026-08-20)

사용자 보고: **"설정에서 언어 설정해도 안 바뀜"**, **"창작하지 말고 mac 에 있는 다국어 그대로"**.

---

## 1. 언어가 안 바뀌던 원인 — 셋

| # | 원인 | 조치 |
|---|---|---|
| 1 | `AppResources` 가 `ResourceLoader` 를 `static readonly` 로 **한 번** 만들어 썼습니다. 그 인스턴스는 만들어질 때의 언어 문맥을 들고 있어 `PrimaryLanguageOverride` 를 바꿔도 **다음 실행까지** 옛 언어를 냈습니다 | MRT Core `ResourceManager` + 갈아 끼우는 `ResourceContext` (`QualifierValues["Language"]`). `AppResources.SetLanguage` |
| 2 | 문구를 **다시 걸어 주는 길이 없었습니다.** macOS 는 `model.appLanguage` 가 바뀌면 SwiftUI 가 전부 다시 그립니다 | `AppResources.LanguageChanged` → 셸이 메뉴막대·도구막대·라이브러리·현상·인화를, 설정 창이 자기 자신을 다시 겁니다 |
| 3 | **`x:Uid` 는 XAML 을 읽을 때 한 번만 풀립니다.** 56곳이 언어를 바꿔도 옛 언어로 남았습니다 | DataTemplate 안(코드 필드가 아님) 하나만 빼고 전부 코드에서 거는 문구로 옮겼습니다 |

**앱 실측(2026-08-20, x64 Release, PID 36748, UI Automation):** 설정 → 언어 → English 를
고르면 메뉴막대가 그 자리에서
`negaflow | 파일 | 편집 | 보기 | 라이브러리 | 사진 | 현상 | 스캐너 | 내보내기 | 도움말` →
`negaflow | File | Edit | View | Library | Photo | Develop | Scanner | Export | Help` 로
바뀌고 설정 탭 이름도 `General` 이 됩니다. 한국어로 되돌리면 그대로 돌아옵니다. **재시작 없음.**

---

## 2. 문구 전수 대조기

`resw` 항목의 `<comment>` 에 원본 심볼(`AppLocalizedText.x` · `AppLocalizedPhrase.x`)이
적혀 있습니다. 그 심볼로 macOS 표
(`Localization/Core/Tables/AppLocalizedText+<언어>.swift`,
`Localization/Phrases/Tables/AppLocalizedPhrase+<언어>.swift`)에서 값을 찾아 비교합니다.

```
py stringdiff.py # 다른 것만 보고서로
py stringdiff.py --apply # macOS 값으로 덮어쓰기
```

**2026-08-20 결과: 대조 2,640건 · 다른 것 0건 · OS 강제 예외 24건 · 심볼 못 찾음 180건.**

## 3. OS 가 강제하는 예외 — 4개 키(언어별 24건)

| 키 | macOS | Windows | 왜 |
|---|---|---|---|
| `libraryShowInExplorer` | Finder에서 보기 | 파일 탐색기에서 보기 | Windows 에 Finder 가 없습니다 |
| `developGrainMendCloneSourceHint` | ⌥/Option 클릭 | Alt 클릭 | Windows 자판에 Option 키가 없습니다 |
| `namedFrameCopyDisplayFormat` | `%@ 사본 %d` | `{0} 사본 %d` | .NET 치환기는 `%@` 를 모릅니다(`LibraryWorkspaceCopy.cs:24`) |
| `settingsColorSystemDisplayProfile` | 시스템 ColorSync 디스플레이 프로파일 | 시스템 디스플레이 프로파일 | ColorSync 는 macOS 전용 이름입니다 |

**이 넷 말고는 예외가 없습니다.** 문구를 "다듬는" 예외는 두지 마십시오.

## 4. 고친 16건 — 전부 손으로 옮기다 생긴 것

`settingsDefaultScanRotationHelp`(5언어, 문장 자체가 달랐음) ·
`developAutoTone`(de·fr) · `developAutoWhiteBalance`(fr) ·
`libraryLocateOriginal`(ja·zh) · `importFolder`(ja) · `libraryProcess`(ja) ·
`printPerforation`(fr) · `settingsMicroSpecksHelp`(ko — **"켜고 끔"**, macOS 는 "켜고 끌").

출처 주석이 틀린 것 1건도 바로잡았습니다: `developExportFolderChange` 는
`AppLocalizedPhrase.rename`(이름 바꾸기)이 아니라 `AppLocalizedText.exportChangeFolder`(변경)입니다.

> **교훈:** 문구를 손으로 옮기면 반드시 틀립니다. 대조기를 돌리십시오.

## 5. 남은 것 — 심볼 못 찾음 180건 (아직 안 봤습니다)

`resw` 주석이 가리키는 심볼이 두 표(`AppLocalizedText`·`AppLocalizedPhrase`)에 없는 항목이
180건입니다. 30개 심볼이며 두 갈래로 보입니다:

- `AppLocalization+*.swift` 의 **다른 표**에 있는 것(`columns`·`rows`·`margin`·`template` 등
  인화/내보내기 계열, `AppLocalization+BatchExport.swift` 류)
- macOS 에 아예 없는 것(= 창작 후보) — `commandUndo`·`commandRedo` 처럼 Windows 에만 있는
  자리일 수도 있습니다(편집 메뉴 OS 강제 차이)

**둘을 아직 가르지 않았습니다.** 대조기에 나머지 표를 물려서 갈라야 합니다.


---

## 6. 2026-08-20 갱신 — 문구가 아니라 **스크립트** 가 깨져 있었습니다

사용자가 "빌드 스크립트 에러 존나게 나네. 문자열 싹다 깨지고" 라고 지적한 자리는
resw 가 아니라 **`.ps1` 파일 자체**였습니다.

Windows PowerShell 5.1 은 **BOM 이 없는 파일을 ANSI(이 기계는 cp949)로** 읽습니다.
한글 주석·문자열이 든 스크립트를 BOM 없이 저장하면 화면이 깨질 뿐 아니라, 깨진 바이트가
따옴표·역슬래시로 보여 **파싱이 통째로 무너지기도** 합니다.

`scripts/*.ps1` 중 비아스키가 든 6개(`build-release` · `ci-gate` · `run-app` ·
`symbolize-rva` · `test-managed` · `verify-installer`)에 **UTF-8 BOM** 을 넣었습니다.
아스키만 있는 스크립트는 어떤 코드페이지로 읽어도 같으므로 건드리지 않았습니다.

확인법:

```bash
for f in scripts/*.ps1; do echo "$(head -c 3 "$f" | od -An -tx1 | tr -d '
') $f"; done
# efbbbf = BOM 있음
```

새 `.ps1` 을 만들 때도 같습니다 — 이 세션의 진단용 스크립트도 BOM 이 없어
**출력이 한 줄도 안 나왔습니다**. [`11`](11-ui-verification-protocol.md) 6.4.

## 7. 남은 것 — 5절 그대로

심볼 못 찾음 180건(30개 심볼)은 **아직 안 갈랐습니다.** 이 세션에서도 못 했습니다.


---

## 8. resw 를 손으로 고칠 때의 함정 (2026-08-20)

새 항목 20개가 `<data name="printOutputSection.Content" ...>` **안쪽에** 들어갔습니다.

- XML 로는 올바릅니다 → 파서·정규식 검사 모두 통과합니다.
- 그러나 **MakePri 는 중첩된 `<data>` 를 세지 않습니다** → PRI 에서 20개가 빠집니다.
- 앱은 `AppResources.Get` 에서 던지고, 그 자리가 `PrintWorkspaceView` 생성자라
  `XamlParseException` 으로 **창을 아예 못 엽니다.**

**항목은 반드시 루트의 직계 자식으로 넣으십시오.** 여러 줄짜리 항목
(`<value>`/`<comment>` 가 다음 줄에 있는 것) 바로 뒤에 끼워 넣다가 이렇게 됩니다.

검사와 되돌리는 법은 [`11`](11-ui-verification-protocol.md) 6.5.

### 8.1 같은 날 **또 났습니다** — 그래서 게이트에 넣었습니다

몇 시간 뒤 `libraryClearSearch.Text` 가 `librarySearchPlaceholder.PlaceholderText` 안쪽에
들어가 **앱이 또 안 떴습니다**(`Cannot create instance of LibraryWorkspaceView`).
사람 눈으로 잡을 수 있는 실수가 아닙니다.

`tests/Shell.UnitTests/ResourceFileTests.cs` 를 새로 두어 ci-gate 가 잡습니다:

| 검사 | 왜 |
|---|---|
| 중첩된 `<data>` 0개 | MakePri 가 무시 → 앱이 시작하다 죽음 |
| 이름 중복 0개(대소문자 무시) | MRT 이름은 대소문자를 안 가림 |
| 언어마다 항목 수 동일 | 한 언어에만 있는 문구는 화면에서 빔 |
| 모든 항목에 값이 있음 | 빈 값은 빈 화면 |

**시험이 진짜 잡는지 확인했습니다** — 일부러 한 줄을 중첩시켰더니 shell 시험이 실패했고,
되돌리니 통과했습니다(1,456 assertions).

---

## 9. 2026-08-22 — 전수조사: **문구가 아니라 "다시 거는 길"** 이 빠져 있었습니다

사용자 보고: **"끔/켬, 컬러 네거티브, 어두운 영역·색조·광도·중간톤·밝은 영역 … 하드코딩된 거
싹 다 찾아라. 설정에서 언어 바꾸면 바로바로 되야 한다."**

**대조기 셋을 새로 짜서 `src/Shell` 전체를 훑었습니다.**

| 갈래 | 찾은 것 | 결과 |
|---|---|---|
| ① XAML 에 영어가 박힘 | 6 | 전부 없앰 |
| ② C# 화면 글자에 영어가 박힘 | 6 | 전부 없앰 |
| ③ 언어를 바꿔도 **다시 안 걸리는** 자리 | 36 | 전부 고침 |

사용자가 짚은 문구는 **전부 ③** 이었습니다. `끔`·`켬`·`컬러 네거티브`·`어두운 영역`·`색조`·
`광도`·`중간톤`·`밝은 영역` 은 여섯 resw 에 이미 다 있었고, 값도 macOS 와 같았습니다.
**옛 언어로 남은 이유는 그 컨트롤에 문구를 다시 거는 길이 없었기 때문입니다.**

### 9.1 뿌리 원인 — `Localize()` 사슬은 한 마디만 끊겨도 아래가 통째로 남습니다

앞 판은 다시 거는 길이 사슬 하나뿐이었습니다: 셸 → 도구막대 → 구역 → …. 어느 부모가 자식의
`Localize()` 를 안 부르면 그 아래가 전부 옛 언어로 남습니다. 실제로 그랬습니다:

```
DevelopColorGradingSection.Localize()   // 머리글만 다시 검
  └─ ColorGradingEditor                 // 생성자에서만 걸었음 → 안 바뀜
       어두운 영역 · 중간톤 · 밝은 영역 · 색조 · 채도 · 광도 · 블렌딩 · 균형
```

**부모가 잊어도 되게** 바꿨습니다 — `Localization/LocalizedElement.cs`:

```csharp
LocalizedElement.Track(this, LocalizeControls);
```

화면에 붙어 있는 동안 `AppResources.LanguageChanged` 를 **컨트롤이 스스로** 듣습니다
(`Unloaded` 에서 떼고 `Loaded` 에서 다시 겁니다 — static 이벤트라 계속 걸어 두면 누수).
macOS 에서 SwiftUI 가 `model.appLanguage` 를 관찰해 그 자리에서 다시 그리는 것과 같은 자리입니다.

쓴 곳: `InspectorSlider` · `ColorGradingEditor` · `ColorMixerEditor` · `ToneCurveEditor` ·
`FrameRatingStars` · `FilmstripView` · `QuickStartHelpView` · `AboutNegaflowView` ·
`DiagnosticsReportView` · 별도 창 넷(정보·진단·빠른시작·설정 제목).

### 9.2 **만들 때 정해지는 문구** — 다시 만들어야 바뀝니다

이름표만 다시 걸어서는 안 되는 자리가 따로 있었습니다. 항목을 만들 때 문구가 박히기 때문입니다.

| 자리 | 무엇이 남았나 | 고침 |
|---|---|---|
| 라이브러리 격자·필름스트립 | `사진 %d` · **컬러 네거티브** (변환기는 바인딩 때 한 번만 돎) | `Localize()` 에서 항목을 다시 만듦 |
| 스캔 카드 | 필름 종류·색 방식·스캔 단추 이름 | `LibraryScanPanel.Localize()` 가 `Render()` 도 부름 |
| 색 혼합 밴드 | 빨강·주황·노랑 … | `LocalizeControls` 가 `RebuildBands()` 도 부름 |
| 설정 창 읽기값 | 사진 수·용량·날짜·백업 상태·화면 프로파일 | `OnLanguageResourcesChanged` 가 `UpdateState` 도 부름 |
| 인화 미리보기 | `N페이지` · 용지 크기 요약 | `Localize()` 가 `printPreview.Draw()` 도 부름 |
| 상태줄·도구막대·레일 | 대기/사용 불가 · 켬/끔 · 선택됨 | 각 `Localize()` 에서 마지막 상태로 다시 걸음 |

### 9.3 없앤 하드코딩 12건

- `InspectorSlider`: `"Arrow keys adjust by 0.01. Shift+Arrow… Double-click resets…"` →
  macOS `AppLocalizedPhrase.sliderKeyboardHelp` 를 여섯 언어로 옮겨 `sliderKeyboardHelp.Value`.
  **"Double-click resets the value" 는 macOS 에 없는 창작이라 함께 없앴습니다.**
- `InspectorSlider`: `$"{Label} value"` → 슬라이더 이름 그대로(macOS 는 값 칸에 이름을 안 둡니다).
- `InspectorSlider`: `$"Enter a number from {Min} to {Max}."` (3곳) → 없앴습니다.
  macOS `EditableSliderValueText` 는 빨간 글자와 소리만 냅니다.
- `ToneCurveEditor.xaml`: `AutomationProperties.Name="Point Curve input/output percentage"` →
  `developCurveInput`/`developCurveOutput` + `SetLabeledBy`.
- `DevelopColorGradingSection.xaml` `"Color Grading"` ·
  `DevelopColorMixerSection.xaml` `"Color Mixer"` · `DevelopBaseCard.xaml` `"Film base mode"` →
  구역 제목 리소스.
- `AppMenuBarView.xaml`: `Title="File"`… 9개 → 지웠습니다(`Localize()` 가 넣습니다).

### 9.4 거짓말하던 안내문 하나

`settingsLanguageRestart` — **"새 언어는 Negaflow 를 다시 시작한 뒤 보입니다."**
2026-08-20 에 그 자리에서 바뀌게 고쳤는데 안내문이 남아 있었습니다. macOS 에는 없는 줄입니다.
여섯 resw 에서 뺐습니다. `OnLanguageSelectionChanged` 의 낡은 주석도 고쳤습니다.

### 9.5 시험 — `LocalizedTextTests`

사람 눈으로 못 잡습니다. 새 컨트롤을 붙일 때마다 같은 실수가 납니다. 그래서 게이트에 넣었습니다.

| 검사 | 무엇을 막나 |
|---|---|
| XAML 화면 속성에 리터럴 0건 | `AutomationProperties.Name="Color Grading"` 류 |
| 접근성 이름·도움말·풍선말에 리터럴 0건 | `"Arrow keys adjust by 0.01…"` 류 |
| 생성자에서 문구를 거는 형식은 `LocalizedElement.Track` 이나 `Localize()` 를 가짐 | `ColorGradingEditor` 류 |

번역할 것이 없는 값(`negaflow` · `JPEG` · `sRGB` · 언어 이름 · 글꼴 글리프 · `ISO — · — s · f/— · — mm`)은
**macOS 출처를 적어** 예외로 둡니다 — macOS 도 그 자리에서 번역하지 않습니다.

**시험이 진짜 잡습니다** — 처음 돌렸을 때 `AppMenuBarView` 9건과
`DiagnosticsReportView` 1건을 잡아냈고, 고치니 통과했습니다(1,530 assertions, 실패 0).

### 9.6 아직 안 고친 것 하나 (문구 문제가 아님)

`DevelopWorkspaceView.xaml:162` 의 `ISO — · — s · f/— · — mm` 은 **x:Name 이 없어 영원히
빈 상태로 남습니다.** macOS `WorkspaceInspectorPane.importedMetadata` 는 같은 줄을 실제 EXIF 로
채웁니다. 다국어 문제는 아니지만(단위는 macOS 도 번역하지 않습니다) **값이 안 붙는 자리**입니다.
