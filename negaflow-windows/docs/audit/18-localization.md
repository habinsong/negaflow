> # ☠️ 하드코딩 · 가짜 구현 · 창작 · 병신 백엔드 · 병신 프론트엔드 = 죽음 ☠️
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
py stringdiff.py           # 다른 것만 보고서로
py stringdiff.py --apply   # macOS 값으로 덮어쓰기
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
