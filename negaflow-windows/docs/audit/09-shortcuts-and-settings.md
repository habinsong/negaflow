> # ⛔ 창작 금지
>
> **macOS Swift 파일을 먼저 열고, 코드를 1:1 로 그대로 옮깁니다.**
> 설명만 보고 다시 쓰지 마십시오. 상수 하나, 임계 하나, 게이트 순서 하나도 지어내지 마십시오.
> 이름이 같다고 "있음" 으로 적지 마십시오 — **함수 안을 읽고** 판정하십시오.
> 전체 규칙은 [`00-index.md`](00-index.md) 맨 위에 있습니다.

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
| 동작(action) 열거자 | **74** | **55** |

### 1.2 macOS 에 있고 Windows 에 **없는 동작 24개**

`WorkflowShortcutActions.swift` ↔ `WorkflowShortcutAction.cs` 를 열거자 단위로 뺀 결과입니다.

| 분류 | 없는 동작 |
|---|---|
| **현상 자동 보정 5** | `autoTone` · `autoWhiteBalance` · `toggleAutoColor` · `toggleAutoLevels` · `toggleNoiseReduction` |
| **도구 6** | `cropTool` · `basePickerTool` · `autoDefectTool` · `guidedDefectTool` · `brushDefectTool` · `cloneStampTool` |
| **현상 타깃 4** | `targetHS` · `targetSP` · `targetF135` · `targetHR` |
| **프로세스 2** | `processBWNegative` · `processBWPositive` |
| **스캐너 4** | `loadScanner` · `toggleScannerSimulator` · `addFlatbedFrame` · `removeFlatbedFrame` |
| **보기 1** | `toggleFullScreen` |
| **도움말 2** | `help` · `openHelp` |

**현상 타깃 4개가 없는 것**은 [`07`](07-user-reported.md) C4(현상 뷰에서 타깃 선택 불가)와
같은 뿌리입니다 — 타깃을 바꾸는 경로가 UI 에도 단축키에도 없습니다.

**결함 도구 4개(자동·가이드·브러시·복제)와 크롭·베이스 피커 단축키가 없습니다.**

### 1.3 없는 구조 — 사용자가 직접 바꾸는 기능

| macOS | 줄 | 하는 일 | Windows |
|---|---:|---|---|
| `ShortcutRecorderField.swift` | **232** | 키를 눌러 **단축키를 직접 녹화**하는 입력 필드 | **없음**(히트 0) |
| `Workflow/WorkflowShortcutRecorder.swift` | 30 | 녹화 상태 기계 | **없음** |
| `Workflow/WorkflowShortcutStore.swift` | 80 | 사용자가 바꾼 단축키 **저장** | **없음** |
| `WorkflowShortcutsSettingsSection.swift` | 109 | 설정의 단축키 탭 화면 | `SettingsRootView.Shortcuts.cs` 343줄 — **대조 안 함** |
| `Workflow/WorkflowShortcutModifiers.swift` | — | 수정자 키 정규화 | `WorkflowShortcut.cs` 70줄에 일부 |

**판정: Windows 단축키는 고정 표(`WorkflowShortcutMap.cs` 180줄)이고,
macOS 처럼 사용자가 녹화해 바꾸고 저장하는 기능이 없습니다.**

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
| | 273 | **`ColorManagementSettingsSection`(166줄)** 색 관리 | **없음** — `ExportColorSpaceComboBox` 하나뿐 |
| **단축키** | 279 | `WorkflowShortcutsSettingsSection`(109줄) + `ShortcutRecorderField`(232줄) **녹화·저장** | `SettingsRootView.Shortcuts.cs` 343줄 — **녹화·저장 없음**(1.3절) |
| **법적 고지** | 285 | `LegalNoticeSettingsSection`(41줄) | **없음** |

**요약: 탭 8개의 이름과 순서는 맞지만, 그 안의 macOS 섹션 11개가 전부 히트 0 입니다.**
가장 큰 구멍은 **디스크 탭**(macOS 715줄 → Windows 토글 1개)과
**색 관리**(166줄 → 없음), **메모리 캐시**(111줄 → 없음)입니다.

### 2.2 탭 **안의 내용은 전부 다시 씀** — 11개 섹션 히트 0

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

### 2.3 설정 버튼을 누르면 앱이 터짐

사용자 보고. 파일은 있습니다:
`SettingsWindow.xaml(.cs)` 60줄 · `SettingsRootView.xaml` 479줄 + `.xaml.cs` 437줄 +
`.ScanTab.cs` 183줄 + `.Shortcuts.cs` 343줄.

**예외 스택을 못 잡았습니다.** 재현 후 스택을 봐야 원인을 말할 수 있습니다.
추측으로 고치지 않습니다.

---

## 3. 할 일

| 순서 | 내용 |
|---|---|
| 1 | **설정 크래시 스택 잡기** — 그다음에야 고칠 수 있음 |
| 2 | 없는 단축키 **24개** 이식 (특히 결함 도구 4 · 타깃 4 · 자동 보정 5) |
| 3 | `ShortcutRecorderField`(232줄) + `WorkflowShortcutStore`(80줄) 이식 — 사용자가 바꿀 수 있게 |
| 4 | **디스크 탭** — `DiskStorageSettingsSection`(317줄) + 백업/복원/보관/캐시 5화면 |
| 5 | **색 관리 탭 내용**(166줄) |
| 6 | `SupportBundleSettingsSection`(61줄) — 진단 |
| 7 | 법적 고지(41줄) · 스캔 저장 위치(89줄) |
| 8 | 탭 아이콘 8개 SF Symbols → SVG ([`08`](08-icons-and-chrome.md)) |
