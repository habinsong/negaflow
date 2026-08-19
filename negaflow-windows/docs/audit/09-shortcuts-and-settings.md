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


# 09 — 단축키와 설정 화면

macOS `Shortcuts/` 9파일 1,198줄 · `Settings/` 16파일 1,877줄 을
Windows 대응과 **함수·열거자 단위**로 대조했습니다.

---

## 1. 단축키

### 1.1 규모

| | macOS | Windows |
|---|---:|---:|
| 파일 | 9 | 5 |
| 줄 | **1,198** | 947 |
| 동작(action) 열거자 | **66** | **68** (2026-08-19 실측 — 없는 것 0) |

### 1.2 macOS 에 있고 Windows 에 없는 동작 — **0개** (2026-08-19 재집계)

앞 판의 "74 vs 55 · 없는 것 24개" 와 "66 vs 64 · 없는 것 4개" 는 **둘 다 낡았습니다.**
두 열거자: Swift 66 ↔ C# 68.

| 분류 | 없는 동작 | 왜 |
|---|---|---|
| — | **없음(2026-08-19)** | 스캐너 넷과 `openHelp` 까지 붙였습니다 |

Windows 에만 있는 둘은 `Undo` · `Redo` 입니다(66 + 2 = 68) — macOS 는 표준 편집 메뉴의
`.undoRedo` 를 갈아 끼우므로 열거자에 없습니다(OS 강제 차이).

**닫힌 것**(앞 판이 "없음" 으로 적었던 20개): 현상 자동 보정 5 · `cropTool` ·
`basePickerTool` · 결함 도구 4(2026-08-19, shift+Q / Q / B / S) · 현상 타깃 4 ·
프로세스 2 · `loadScanner` · `toggleFullScreen`.

**남은 진짜 결손은 단축키 표가 아니라 [`09`](09-shortcuts-and-settings.md) 1.3 의
녹화·저장 기능입니다.**

### 1.3 없는 구조 — 사용자가 직접 바꾸는 기능

| macOS | 줄 | 하는 일 | Windows |
|---|---:|---|---|
| `ShortcutRecorderField.swift` | **232** | 키를 눌러 녹화 | `SettingsRootView.Shortcuts.cs` `recordingAction` + `OnShortcutRecorderKeyDown` |
| `WorkflowShortcutRecorder.swift` | 30 | 녹화 상태 | 같은 파일의 `recordingAction`/`rejectedAction` |
| `WorkflowShortcutStore.swift` | 80 | 바꾼 단축키 저장 | `WorkflowShortcutMap` — 기본값과 같아지면 덮어쓰기에서 지움 |
| `WorkflowShortcutsSettingsSection.swift` | 109 | 단축키 탭 | `SettingsRootView.Shortcuts.cs` |
| `WorkflowShortcutModifiers.swift` | — | 수정자 정규화 | `WorkflowShortcut.cs` |

**판정: 녹화·저장은 설정 탭에 있습니다.** 232줄 필드와 픽셀 단위 대조는 안 했습니다.

---

## 2. 설정 화면

### 2.1 탭 8개 — 이름은 같음

| macOS `AppSettingsTab` | 아이콘 | Windows `SettingsCategory` |
|---|---|---|
| `general` | `gearshape` | `General` ✔ |
| `interface` | `sidebar.left` | `Interface` ✔ |
| `workflow` | `rectangle.stack` | `Workflow` ✔ |
| `scan` | `scanner` | `Scan` ✔ |
| `disk` | `externaldrive` | `Disk` ✔ |
| `export` | `square.and.arrow.up` | `Export` ✔ |
| `shortcuts` | `keyboard` | `Shortcuts` ✔ |
| `legal` | `doc.text.magnifyingglass` | `Legal` ✔ |

**탭 이름과 순서는 맞습니다. 아이콘은 SF Symbols 라 Segoe 로는 같은 그림이 안 나옵니다**
([`08`](08-icons-and-chrome.md)).

### 2.1.1 탭 8개 — macOS 가 실제로 내는 것 전부 (`AppSettingsView.swift`)

| 탭 | 줄 | macOS 내용 | Windows |
|---|---:|---|---|
| **일반** | 89 | `settingsLanguagePicker` 언어 | `LanguageComboBox` ✔ |
| | 99 | `settingsAppearancePicker` 모양(시스템/어둡게/밝게) | `AppearanceComboBox` ✔ |
| | 109 | `developerMode` 토글 | `DeveloperModeToggle` ✔ (켜도 나오는 게 없음 — [`10`](10-cache-and-optimization.md) 3절) |
| | 115 | **`MemoryCacheSettingsSection`(111줄)** — 자동/수동 · 결함제거원본 슬라이더 · 현상결과 슬라이더 · 자동복귀 단추 · 도움말 3줄 | **없음** |
| | 116 | **`SupportBundleSettingsSection`(61줄)** — 지원 번들(진단) | **없음** |
| **인터페이스** | 123 | `settingsCanvasBackgroundPicker` 배경(검정/회색/흰색) | `CanvasBackgroundComboBox` ✔ (그러나 macOS 는 **캔버스 우클릭**에도 있음) |
| | 133 | 토글 — 클리핑 오버레이 | `ClippingOverlayToggle` ✔ |
| | — | `PixelSamplerSettingsRow`(24줄) | `PixelSamplerToggle` (별도 행 구조 아님) |
| **워크플로** | 152 | 토글 — 스캐너 시뮬레이터 | `ScannerSimulatorToggle` ✔ |
| | 159 | 토글 — 현상 임포트 | `DevelopImportsToggle` ✔ |
| | 165-172 | 미세 입자 섹션 — 자동/가이드 토글 2 | `AutoDefectMicroSpecksToggle` · `GuidedDefectMicroSpecksToggle` ✔ |
| **스캔** | 185-188 | 스캔 기본 방향 | `ScanRotationComboBox` ✔ |
| | 203 | `ScannerTruthSettingsSection` 스캐너 정보 | `ScannerTruthRows` ✔ |
| | — | **`ScanStorageLocationView`(89줄)** 스캔 저장 위치 | **없음** |
| **디스크** | 209 | **`DiskStorageSettingsSection`(317줄)** — 저장 위치 Picker · 루트/썸네일/내보내기 폴더 3 · 경로 초기화 단추 · **썸네일 캐시 크기 + 비우기** · **라이브러리 백업(지금 백업/찾아보기)** · `LibraryArchiveButton`(36줄) | **`ImageHashToggle` 하나** |
| | — | `LibraryBackupScheduleView`(63줄) 백업 일정 | **없음** |
| | — | `LibraryRestoreBrowser`(158줄) 복원 브라우저 | **없음** |
| | — | `ExternalBackupDestinationView`(130줄) 외장 백업 대상 | **없음** |
| **내보내기** | 215-239 | 빠른 내보내기 — 형식 · DPI · 크기 | `SourceDpiItem` · `FullSizeItem` 등 부분 |
| | 259 | **`settingsExportVerification` 내보내기 검증 등급** | **없음** (`ExportVerificationLevel` 히트 0) |
| | 273 | **`ColorManagementSettingsSection`(166줄)** 색 관리 | **있음(2026-08-20 정정)** — 색공간 · 소프트 프루프(프로파일 고르기·초기화·오류) · 프루프 시뮬레이션 · 색영역 경고 · 값 줄 다섯. 빠져 있던 **모니터 줄**은 2026-08-20 에 붙였습니다 |
| **단축키** | 279 | `WorkflowShortcutsSettingsSection`(109줄) + `ShortcutRecorderField`(232줄) **녹화·저장** | `SettingsRootView.Shortcuts.cs` 343줄 — **녹화·저장 없음**(1.3절) |
| **법적 고지** | 285 | `LegalNoticeSettingsSection`(41줄) | **있음(2026-08-20 정정)** — 다섯 절(오픈소스 라이선스·상표·이름·프로파일·제휴) 전부. 앱에서 확인 |

**요약: 탭 8개의 이름과 순서는 맞습니다.** 픽셀 샘플러 토글은 있고, 도움말을
macOS 처럼 **켜져 있을 때만** 내도록 2026-08-20 에 맞췄습니다(`if store.isEnabled`).
남은 큰 구멍은 **디스크 탭**(저장 위치·백업·복원·보관), **메모리 캐시 섹션**,
**지원 번들**, **스캔 저장 위치**입니다.

### 2.2 탭 안의 섹션 — ☠️ "11개 히트 0" 은 **틀렸습니다**(2026-08-20 정정)

타입 이름으로 찾아 낸 판정이었습니다. 화면을 열어 보니 **법적 고지**와 **색 관리**는
이미 있습니다(위 표 참조). 아래 표에서 그 둘은 무효입니다.

| macOS 섹션 | 줄 | Windows |
|---|---:|---|
| `DiskStorageSettingsSection.swift` | **317** | **히트 0** |
| `ColorManagementSettingsSection.swift` | **166** | **히트 0** |
| `LibraryRestoreBrowser.swift` | 158 | **히트 0** |
| `ExternalBackupDestinationView.swift` | 130 | **히트 0** |
| `MemoryCacheSettingsSection.swift` | 111 | **히트 0** |
| `ScanStorageLocationView.swift` | 89 | **히트 0** |
| `LibraryBackupScheduleView.swift` | 63 | **히트 0** |
| `SupportBundleSettingsSection.swift` | 61 | **히트 0** |
| `LegalNoticeSettingsSection.swift` | 41 | **히트 0** |
| `LibraryArchiveButton.swift` | 36 | **히트 0** |
| `PixelSamplerSettingsRow.swift` | 24 | **히트 0** |

Windows `SettingsRootView.xaml` 이 실제로 내는 요소(83개) 중 **탭 단추 16개를 뺀 내용**:

| 탭 | Windows 가 내는 것 | macOS 가 내는 것 |
|---|---|---|
| 일반 | 언어 · 모양(시스템/어둡게/밝게) · 개발자 모드 | + 화면 표시 설정 전반 |
| 인터페이스 | 클리핑 오버레이 토글 · 픽셀 샘플러 토글 | `PixelSamplerSettingsRow.swift` 별도 행 · 사이드바 설정 |
| 워크플로 | 스캐너 시뮬레이터 · 현상 임포트 · 미세입자 자동/가이드 | + 워크플로 전반 |
| 스캔 | 스캔 회전 4종 · 스캐너 정보 표 | + **`ScanStorageLocationView`(89줄) 저장 위치** |
| 디스크 | **이미지 해시 토글 하나** | **`DiskStorageSettingsSection`(317줄)** — 저장소 용량·정리·캐시. + 외장 백업 대상(130줄) · 백업 일정(63줄) · 복원 브라우저(158줄) · 라이브러리 보관(36줄) · **메모리 캐시(111줄)** |
| 내보내기 | DPI · 색공간 | + 인코딩·메타데이터 정책 |
| 단축키 | 고정 표 표시 | **녹화·저장(342줄)** |
| 법적 고지 | — | `LegalNoticeSettingsSection`(41줄) |

**가장 큰 구멍은 디스크 탭입니다.** macOS 는 저장소 관리 5개 화면 715줄인데
Windows 는 **토글 하나**입니다. 백업·복원·보관·캐시 관리가 통째로 없습니다.

**색 관리(`ColorManagementSettingsSection` 166줄)는 탭 어디에도 없습니다.**

**지원 번들(`SupportBundleSettingsSection` 61줄)도 없습니다** — [`07`](07-user-reported.md) C9
진단 기능 미구현과 같은 자리입니다.

### 2.3 설정 버튼을 누르면 앱이 터짐 — **고침**

[`07`](07-user-reported.md) A1. `developAutoDefect.Text` 없음 → 기존 GrainMend 키로 붙임.
같은 클릭으로 설정 창 확인.

---

## 3. 할 일

| 순서 | 내용 | 상태 |
|---|---|---|
| 1 | 설정 크래시 | **닫음** A1 |
| 2 | 단축키 열거자 | **닫음.** 66 vs 68, 없는 것 0 |
| 3 | 녹화·저장 | 설정 탭에 있음. 픽셀 대조는 남음 |
| 4 | 디스크 탭 5화면 | **없음** |
| 5 | 색 관리 섹션 | ComboBox 하나. 166줄 섹션 없음 |
| 6 | 지원 번들 | **없음** |
| 7 | 법적 고지 · 스캔 저장 위치 | **없음** |
| 8 | 탭 아이콘 SVG | [`08`](08-icons-and-chrome.md) |
