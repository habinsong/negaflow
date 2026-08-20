# Settings 이식 명세

기준일: 2026-08-04  
macOS 기준 커밋: `9be909c`  
소스 근거: `Sources/negaflowApp/Settings`, `Sources/negaflowApp/Shortcuts`,
`Sources/negaflowApp/Services/{Cache,Diagnostics,Storage}`  
공식 근거: [Guidelines for app settings](https://learn.microsoft.com/en-us/windows/apps/design/app-settings/guidelines-for-app-settings),
[Manage app windows](https://learn.microsoft.com/en-us/windows/apps/develop/ui/manage-app-windows),
[NavigationView](https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/navigationview),
[Windows App SDK file management](https://learn.microsoft.com/en-us/windows/apps/develop/files/),
[Theming in Windows apps](https://learn.microsoft.com/en-us/windows/apps/develop/ui/theming),
[Known Folders](https://learn.microsoft.com/en-us/windows/win32/shell/known-folders),
[Store and retrieve app data](https://learn.microsoft.com/en-us/windows/apps/develop/data/store-and-retrieve-app-data),
[MEMORYSTATUSEX](https://learn.microsoft.com/en-us/windows/win32/api/sysinfoapi/ns-sysinfoapi-memorystatusex)

## 1. 목적과 제품 경계

Settings는 보조 화면이지만 다음 제품 계약의 유일한 사용자 제어면이다.

- 앱 언어·테마와 canvas 표시
- 가져오기와 결함 제거 기본값
- scanner capability와 plugin 신뢰 상태
- 원본·cache·export·backup 저장 위치
- quick export와 color management 기본값
- workflow shortcut 재지정
- legal notice와 privacy-safe support bundle

자주 쓰는 현상·스캔·내보내기 명령 자체를 Settings로 이동시키지 않는다. Microsoft의 Settings 지침도
일상 workflow command와 장기 preference를 구분한다. 예를 들어 현재 사진의 exposure는 Develop에,
새 import의 자동 현상 기본값은 Settings에 남는다.

Windows판은 macOS 설정의 값과 상태 의미를 보존하되, macOS 전용 표면은 Windows 네이티브 개념으로
치환한다. 다음은 동등성으로 간주하지 않는다.

- `iCloud` 문자열을 기능 확인 없이 `OneDrive`로 바꾸는 것
- `NSOpenPanel` 동작을 임의 경로 문자열 입력으로 대체하는 것
- scanner 모델명을 보고 지원 capability를 추정하는 것
- `UserDefaults` key를 registry에 일대일로 복사하는 것
- macOS `Command` shortcut을 무조건 Windows `Ctrl`로 문자열 치환하는 것

## 2. 현재 macOS 계약

### 2.1 category 순서

`AppSettingsTab.allCases`의 순서는 제품 정보 구조다.

1. General
2. Interface
3. Workflow
4. Scan
5. Disk
6. Export
7. Shortcuts
8. Legal

선택한 category는 `settings.selectedTab`으로 유지된다. Windows에서도 창을 닫았다 다시 열 때 마지막
category를 복원하되, 저장된 값이 더 이상 존재하지 않으면 `General`로 안전하게 돌아간다.

### 2.2 현재 창

macOS 화면은 760 × 640 point의 별도 `TabView` 창이며 각 pane은 grouped `Form`으로 스크롤된다.
Windows에서는 8개 항목이 수평 tab bar에 과밀해지므로 top tab을 그대로 복제하지 않는다. 항목 순서와
내용은 보존하고, Windows의 많은 category 탐색 관례에 맞춘 왼쪽 `NavigationView`를 사용한다.

이는 기능 축소가 아니라 플랫폼 adaptation이다.

```text
┌──────────────────────────────────────────────────────────────────────┐
│ Negaflow Settings                                      —  □  ×      │
├──────────────────┬───────────────────────────────────────────────────┤
│ General          │ General                                           │
│ Interface        │                                                   │
│ Workflow         │  Language                    [Use system      ▾]  │
│ Scan             │  Appearance                  [Use system      ▾]  │
│ Disk             │  Developer mode                         [off]     │
│ Export           │                                                   │
│ Shortcuts        │ Memory cache                                      │
│ Legal            │  ...                                              │
│                  │                                                   │
└──────────────────┴───────────────────────────────────────────────────┘
```

## 3. Windows 창과 탐색

### 3.1 AppWindow 수명

- Settings는 top-level `AppWindow` 하나만 허용한다.
- 두 번째 열기 명령은 새 창을 만들지 않고 기존 창을 activate한다.
- main window를 닫아 앱이 종료되는 동안 Settings가 orphan window로 남지 않는다.
- destructive maintenance가 진행 중이면 닫기는 가능하되 작업을 취소하거나 중간 상태로 만들지 않는다.
- 창 bounds는 monitor work area 안으로 clamp해 복원한다. 분리된 monitor 좌표를 그대로 믿지 않는다.
- picker·confirmation dialog는 반드시 Settings의 `WindowId`/`HWND`를 owner로 사용한다.

`AppWindow`는 top-level `HWND`와 1:1 대응하는 Windows App SDK abstraction이다. 창 배치에는
`AppWindow`/`OverlappedPresenter`를 사용하고, 파일 선택기 ownership 같은 native interop에서만 실제
handle을 취한다.

### 3.2 초기 크기 후보와 responsive 기준

아래 수치는 prototype에서 100/150/200% scaling과 localization으로 확정할 후보값이다.

| 항목 | 후보 | 이유 |
|---|---:|---|
| 초기 client size | 960 × 680 DIP | macOS 760 × 640 content에 왼쪽 rail을 추가 |
| 최소 client size | 720 × 540 DIP | restore/browser dialog와 긴 localized label의 하한 |
| navigation rail | 176–220 DIP | 8개 category를 잘림 없이 표시 |
| content max width | 900 DIP | 초광폭에서 control과 label이 과도하게 벌어지지 않게 제한 |
| outer content inset | 24 DIP | native page rhythm과 focus visual 공간 확보 |

창은 resize 가능해야 한다. 작은 폭에서는 `NavigationView`를 compact/overlay로 전환하고, category label을
icon-only로 영구 축소하지 않는다. 400% text scaling에서도 모든 기능에 keyboard로 도달할 수 있어야 한다.

### 3.3 탐색 규칙

- 왼쪽 category는 위의 8개 순서를 고정한다.
- main shell의 built-in Settings entry와 app menu/shortcut은 같은 command를 호출한다.
- Settings 내부 `NavigationView.IsSettingsVisible`은 `false`다. 별도 ninth Settings item을 만들지 않는다.
- category 전환은 page state를 잃지 않는다. 저장 가능한 preference는 변경 즉시 반영한다.
- 비동기 작업 상태는 해당 category를 벗어나도 model에 남는다.
- 뒤로 가기는 category history가 아니라 닫기와 다르다. 별도 back stack은 만들지 않는다.

## 4. 시각·control 규칙

### 4.1 기본 구성

Microsoft의 최신 지침은 `SettingsCard`와 `SettingsExpander`를 권장한다. 다만 Negaflow는 모든 행에 icon,
description, 둥근 container를 반복하는 카드 wall을 만들지 않는다.

- section header 아래의 관련 행을 하나의 quiet group으로 묶는다.
- 단일 preference는 `SettingsCard`를 쓰더라도 header icon을 기본으로 생략한다.
- 설명이 필요할 때만 한 줄 secondary text를 둔다.
- 하위 option이 조건부로 나타나는 경우에만 `SettingsExpander`를 쓴다.
- expander nesting은 한 단계까지만 허용한다.
- path, profile name, generation ID는 가운데 생략으로 표시하고 전체 값은 tooltip/accessibility description으로
  제공한다.
- ordinary button은 rest 상태에서 quiet하고, destructive/prominent button은 실제 위험·주 행동에만 쓴다.
- binary preference는 `ToggleSwitch`, 2–5개 상호배타 값은 `RadioButtons` 또는 compact `ComboBox`를 쓴다.
- 선택 상태가 항상 보여야 하는 2–4개 값만 segmented control을 유지한다.

### 4.2 행 geometry

- 일반 control 높이 목표는 약 30–32 DIP다.
- label column 폭을 고정 숫자로 박지 않는다. 같은 group 안에서 측정된 shared column을 사용한다.
- slider는 위 행에 label과 현재 숫자, 아래 행에 full-width track을 둔다.
- 단위 있는 값은 locale-aware 숫자와 고정 semantic unit을 분리한다.
- `...` 또는 `…`를 action label에 붙이지 않는다.
- disabled control은 이유를 바로 아래에 표시한다. hover만으로 설명하지 않는다.
- validation error는 control과 연결된 inline text 및 automation property로 제공한다.

### 4.3 테마

표시 순서와 값은 다음과 같다.

1. Use system setting
2. Dark
3. Light

WinUI의 `RequestedTheme`로 app theme를 적용하되, `Use system setting`은 hard-coded light/dark가 아니라
요청을 제거해 시스템 값을 따르게 한다. `HighContrast`는 사용자 선택 테마보다 우선하는 독립 시스템
상태로 취급한다.

theme 변경 시 다음을 즉시 갱신한다.

- Settings와 main window resource
- canvas 외곽 chrome
- popup, menu, tooltip, dialog
- icon foreground와 focus visual

사진 canvas의 Black/Gray/White background preference는 app theme와 별개다. Dark theme를 골랐다고
canvas background를 자동으로 바꾸지 않는다.

## 5. General

### 5.1 Language

현재 `AppLanguage` 목록과 순서를 그대로 제공하고 `System` 값을 유지한다. 언어 변경은 다음 범위를 즉시
invalidate한다.

- Settings category와 행 label
- main command/menu/tooltip
- workspace copy와 accessibility name
- date, byte count, decimal formatting

현재 창을 재생성해야만 일부 resource가 반영되는 구조는 피한다. unavoidable한 재시작 요구가 확인되면
해당 행에서 명시하고, 저장만 한 뒤 몰래 restart하지 않는다.

### 5.2 Appearance

`System`, `Dark`, `Light` 세 값이다. 선택 즉시 모든 활성 top-level window에 적용한다. 새 창은 현재
preference를 읽고 생성한다. OS accent color는 존중하되 사진 pixel, histogram, clipping color에는 theme
brush를 사용하지 않는다.

### 5.3 Developer mode

- 기본값은 off다.
- 사용자가 명시적으로 켜야 한다.
- production scanner fallback이나 demo data를 암묵 활성화하는 용도로 쓰지 않는다.
- developer-only diagnostic가 원본 안전성, plugin trust, export validation을 우회하지 못한다.
- 켰을 때 무엇이 추가되는지 도움말에 구체적으로 적는다.

### 5.4 Memory cache

현재 의미를 보존한다.

| mode | 표시·동작 |
|---|---|
| Automatic | 계산된 `Cleaned Raw`/`Developed` 상주 frame 상한을 읽기 전용 표시 |
| Manual | 두 frame count slider와 `Reset to Automatic` action 표시 |

현 macOS 계산의 parity 기준:

- frame 추정치: cleaned raw 190 MiB, developed 170 MiB
- 최소: cleaned raw 2, developed 3
- 실용 상한: cleaned raw 64, developed 128
- 8 GiB 이하에서는 최소값 유지
- 자동 예산: 16 GiB에서 25%, 16 GiB 증가마다 2.5%p, 최대 35%
- 수동 slider 상한: 설치 physical memory의 70%
- 자동 분배: cleaned raw 1개당 developed 2개

이 수치는 macOS 구현의 현재 heuristic이지 Windows 실측값이 아니다. Windows port에서는 동일한 값으로
parity baseline을 만든 뒤 x64/ARM64와 unified/discrete GPU별 peak working set을 측정해 별도 decision으로
조정한다.

Windows system input:

- 설치 physical memory: `GlobalMemoryStatusEx`의 `ullTotalPhys`
- 현재 memory pressure 관찰: `ullAvailPhys`, process working set, engine allocation telemetry
- 32-bit scanner plugin의 address-space 제한은 host cache 예산과 분리

UI의 추정치는 upper bound이며 즉시 예약되는 메모리라고 표현하지 않는다. 변경은 cache manager의 새
상한에 즉시 반영하되, frame ownership·진행 중 render를 깨뜨리려고 강제 free하지 않는다.

### 5.5 Support Bundle

기본 파일명은 `negaflow-support-yyyyMMdd-HHmmss.zip`을 유지한다. Windows App SDK 1.8+의
`Microsoft.Windows.Storage.Pickers.FileSavePicker`를 Settings `WindowId`에 연결한다.

현재 privacy contract를 Windows에서도 유지한다.

포함:

- schema version, 생성 시각
- app version, Windows version, architecture, logical processor 수, physical memory
- catalog lifecycle/health의 집계값
- backup generation의 sequence/date/state와 집계값
- cache 크기와 상주 frame count
- scanner가 실제 보고한 capability 요약
- plugin version/protocol/trust 상태와 binary/manifest hash
- 최근 error diagnostic event 최대 100개

제외:

- 원본 image와 thumbnail pixel
- 전체 file/folder path
- source file name, roll/frame 사용자 이름
- EXIF/IPTC/XMP 개인 metadata
- device serial number와 사용자 계정명
- raw command line, environment 전체 dump

위치·plugin ID는 번들마다 새 salt를 써 짧은 SHA-256 식별자로 만든다. 서로 다른 support bundle 사이에서
동일 사용자를 추적할 수 있는 stable hash를 만들지 않는다. export 전에 포함 필드 목록을 사용자에게
보이고, destination에 기존 파일이 있으면 picker의 정상 overwrite confirmation을 따른다.

## 6. Interface

### 6.1 Canvas background

`Black`, `Gray`, `White` 3-way segment를 유지한다.

- main canvas의 작업 배경에만 적용한다.
- export/print pixel에 포함하지 않는다.
- image의 transparent 영역 preview 정책과 혼동하지 않는다.
- high contrast에서도 세 swatch의 이름과 selected state가 읽혀야 한다.

### 6.2 Clipping overlay

- binary toggle, 기본 off
- main preview에서만 즉시 적용
- export pixel과 histogram input을 바꾸지 않음
- preview revision을 증가시켜 오래된 overlay가 새 frame에 적용되지 않게 함
- 지원하지 않는 render backend에서는 숨기지 말고 disabled reason을 표시

### 6.3 Pixel sampler

현재 `PixelSamplerSettingsRow`의 세부 option을 소스 기준으로 그대로 옮긴다. sampler enable/disable은
canvas hit testing과 status display에 즉시 연결한다. 표시 값은 render pipeline의 정의된 sampling stage를
사용해야 하며 monitor-composited screenshot pixel을 읽지 않는다.

## 7. Workflow

### 7.1 Scanner simulator

- 기본 off
- 명시적인 demo/developer 기능
- 실제 scanner 탐색 실패 시 자동으로 켜지지 않음
- 켜진 상태는 UI에 지속적으로 식별 가능
- simulator device와 real plugin device ID namespace를 충돌시키지 않음

### 7.2 Develop imports automatically

- 기본 off를 고정한다.
- 켠 뒤 새로 import/scan된 frame부터 적용한다.
- 이미 catalog에 있는 frame을 retroactive하게 현상하지 않는다.
- foreground import와 folder refresh 모두 같은 persisted preference를 읽는다.
- 실패하면 manual `Develop` 상태를 유지하고 silently original로 export하지 않는다.

### 7.3 default micro-specks

`Auto`와 `Guided`는 독립 toggle이다. 현재 열린 frame의 도구 선택을 바꾸지 않고 새 defect workflow의
시작값에만 적용한다. 두 값을 하나의 tri-state나 master toggle로 합치지 않는다.

## 8. Scan

### 8.1 default rotation

`0°`, `90°`, `180°`, `270°`를 제공하며 현재 기본값은 `180°`다.

- 방향 metadata가 없는 새 scan에만 default로 적용
- scan 원본 file을 물리적으로 덮어쓰지 않음
- plugin이 명시한 applied rotation과 중복 적용하지 않음
- catalog에 저장된 frame별 rotation이 global default보다 우선

### 8.2 Scanner Truth

선택 device의 validated capability만 표시한다.

- supported resolution DPI 목록
- bit depth per channel 목록
- transparency mode
- brightness/contrast range와 step
- infrared availability
- preview, scan area, multi-exposure 등 scanner surface와 공유하는 capability

capability가 아직 없으면 `Waiting for scanner capabilities` 상태를 보인다. 모델명 기반 예상값을 만들지
않는다. brightness/contrast range가 없으면 slider를 숨겨 화면을 깨끗하게 하기보다 unavailable reason을
표시해 “미발견”과 “미지원”을 구분한다.

### 8.3 plugin trust

설치 plugin이 있을 때만 trust section을 표시한다. 각 row에는 최소 다음을 제공한다.

- localized display name과 stable plugin ID의 privacy-safe 축약
- plugin/protocol/schema version
- architecture: x86, x64, ARM64
- publisher/signature 상태
- approved / approval required / identity changed / invalid identity / store unavailable
- executable·manifest identity가 바뀌었을 때 재승인 action

Settings에서 approve해도 plugin process를 host 안에 load하지 않는다. WIA/TWAIN/SANE vendor code는
계속 out-of-process JSON adapter다. 자세한 계약은 [Scanning 이식 명세](scanning.md)와
[scanner plugin architecture](../../10-scanner/plugin-architecture.md)를 따른다.

## 9. Disk

## 9.1 저장 데이터 분류

UI에 보이는 경로는 수명이 다르다. 모두 같은 “폴더”로 취급하지 않는다.

| row | 분류 | 삭제/이동 규칙 |
|---|---|---|
| Root | managed root | 하위 경로 기준점, 변경은 migration이 아니라 이후 write destination 변경 |
| Thumbnails | 재생성 cache | 명시적 clear 가능 |
| Imported Originals | 사용자 원본 destination | 명시적 move/import에만 사용, 자동 삭제 금지 |
| Cleaned Raw | 재생성 가능한 derived cache | recipe/identity와 맞을 때만 사용, 원본 대체 금지 |
| Scan Previews | ephemeral/derived | session과 ownership 확인 후 정리 가능 |
| Export | 사용자 산출물 | cache clear/uninstall에서 삭제 금지 |
| Quick Export | 사용자 산출물 | cache clear/uninstall에서 삭제 금지 |
| Scans | scanner 원본 | cache가 아님, 절대 thumbnail clear 대상이 아님 |

`ScanFrame.rawScanURL`과 third-party source/XMP는 불변이다. Settings의 경로를 바꾸는 것은 기존 원본을
자동 이동하거나 덮어쓸 권한이 아니다. relink/move는 별도 사용자 transaction이어야 한다.

### 9.2 Windows location mode

macOS의 `iCloud`, `Desktop`, `Specific Folder`, `Custom`을 다음처럼 이식한다.

| macOS intent | Windows label | 결정 |
|---|---|---|
| iCloud 또는 Documents fallback | Documents | `FOLDERID_Documents`/`.NET MyDocuments` 아래 `Negaflow` |
| Desktop | Desktop | redirected `FOLDERID_Desktop` 아래 `Negaflow` |
| Specific Folder | Specific Folder | picker로 고른 parent 아래 `Negaflow` |
| Custom | Custom | 각 하위 경로를 개별 선택 |

Windows 기본값은 `Documents`다. Windows Known Folder는 OneDrive나 조직 network로 redirect될 수 있으므로
resolved path와 volume 특성을 검사한다. redirect된 Documents를 사용하더라도 UI에서 “OneDrive backup이
보장됨”이라고 표현하지 않는다.

독립적인 `OneDrive` mode는 1차 범위에서 만들지 않는다. 나중에 추가할 조건:

- 실제 Known Folder/provider를 안정적으로 식별
- Files On-Demand의 placeholder hydration과 offline failure 처리
- large TIFF와 catalog atomic write 동작 실측
- user가 cloud root를 명시 선택
- backup과 sync의 차이를 UI에서 설명

### 9.3 app-owned internal location

unpackaged/self-contained 배포를 기본 후보로 두므로 package identity 유무에 따라 경로가 달라지는 저장소를
핵심 truth로 쓰지 않는다.

```text
%LOCALAPPDATA%\Negaflow\
  Settings\settings-vN.json
  Library\catalog.json
  Library\Defects\
  Backups\
  Cache\
  Diagnostics\
```

사용자에게 보이는 scan originals와 export는 위 internal root에 강제로 넣지 않는다. 내부 catalog에는
원본 identity/bookmark 대체 정보와 사용자 선택 경로만 기록한다.

### 9.4 picker

Windows App SDK 1.8+의 `Microsoft.Windows.Storage.Pickers`를 우선한다.

- `FolderPicker(WindowId)`로 string path 결과를 받는다.
- `FileOpenPicker(WindowId)`는 ICC/ICM과 archive 선택에 사용한다.
- `FileSavePicker(WindowId)`는 support bundle/export destination에 사용한다.
- dialog는 요청한 Settings/App window를 owner로 가진다.
- 취소는 setting 변경이 아니다.
- 선택 직후 존재, directory 여부, write/create 권한, volume identity를 다시 확인한다.
- picker 결과와 실제 use 사이의 reparse-point/TOCTOU 변경을 operation 시점에 다시 방어한다.

legacy `Windows.Storage.Pickers` + `InitializeWithWindow`는 Windows App SDK picker가 필요한 기능을 못
제공할 때만 fallback으로 남긴다.

### 9.5 Custom mode

Root 또는 하위 path 하나를 수동 변경하면 mode는 `Custom`이 된다. 각 row는 다음을 제공한다.

- middle-truncated resolved path
- Change folder
- Open in File Explorer
- accessibility description의 전체 경로
- root volume/availability 오류

`Reset Paths`는 새로운 default path를 선택할 뿐 기존 파일을 지우거나 이동하지 않는다. reset 이후 기존
cleaned-raw directory는 cleanup registry에 보존하되, 파일 identity 검증 없는 broad sweep를 금지한다.

### 9.6 thumbnail cache

- cache size는 background I/O로 계산한다.
- 계산 중, 정상 값, 계산 실패를 구분한다.
- `Clear Thumbnail Cache`는 destructive confirmation 또는 명확한 destructive styling을 사용한다.
- clear 도중 button을 disable하고 중복 task를 만들지 않는다.
- thumbnail만 삭제하며 scan originals, cleaned raw, previews, export, catalog, backup은 삭제하지 않는다.
- 완료 후 size를 다시 측정한다.

### 9.7 backup destination

외부 destination은 folder path만 기억하지 않고 volume identity와 현재 상태를 검사한다.

상태:

- Not configured
- Disconnected
- Same volume
- Read only
- Insufficient capacity
- Ready + volume display name

Ready가 아니면 scheduled/manual external backup을 시작하지 않는다. 현재 volume의 available/total capacity와
last success를 표시한다. removable drive letter가 바뀌어도 다른 volume을 같은 destination으로 오인하지
않도록 volume serial/GUID와 directory identity를 함께 검증한다.

### 9.8 backup schedule

현재 값:

- Manual
- When Quitting
- Daily
- Weekly

Windows에서 `When Quitting`은 강제 종료, crash, power loss에서 보장되지 않는다. 정상 app shutdown에서만
시도하며, OS 종료를 무한 지연하지 않는다. daily/weekly는 app이 실행 중일 때 due state를 확인하는
in-process schedule로 시작한다. Windows Task Scheduler 등록은 별도 opt-in 설계 없이는 추가하지 않는다.

표시할 evidence:

- last attempt
- last success
- last restore drill: Passed/Failed/Never
- 검증한 generation ID

### 9.9 Backup Now / Browse and Restore / Library Archive

세 action은 한 줄에 동일 너비로 배치한다. 좁은 폭에서도 임의 wrap하지 않고 최소 폭을 지키거나 해당
group만 가로 스크롤한다.

- `Backup Now`: library point-in-time snapshot을 만든 뒤 manifest/hash/readback을 검증
- `Browse and Restore`: generation browser를 연다
- `Library Archive`: 사용자 이동 가능한 archive를 생성

maintenance 중에는 세 action을 disable한다. 진행 상태와 실패 이유는 button label만 바꾸지 말고 persistent
status row/`InfoBar`에 남긴다.

### 9.10 restore browser

상태:

- loading
- load failed
- no generations
- list with restorable/non-restorable states
- restore pending
- scheduling/cancel in progress

generation ordering은 wall-clock timestamp가 아니라 monotonic sequence를 우선한다. restore 대상은 isolated
directory에서 열고 schema, catalog, defect recipes, manifest/hash를 검증한다. 미래 catalog version이면 현재
primary를 대체하지 않는다.

선택 후 `Schedule Restore` confirmation을 거쳐 pending marker를 원자적으로 기록한다. running model을 즉시
갈아끼우지 않고 다음 safe startup에서 다음 순서로 실행한다.

1. process lock 확보
2. primary와 pending generation 재검증
3. corrupt primary를 forensic copy로 보존
4. whole catalog/recipe set 교체
5. 새 catalog open/health 확인
6. 성공 후 marker와 staging 정리

cancel은 pending marker만 제거하고 backup generation을 삭제하지 않는다.

## 10. Export

### 10.1 Quick Export

현재 값과 순서를 보존한다.

| setting | values |
|---|---|
| Format | JPEG, PNG |
| DPI | Source, 72, 150, 240, 300, 600 |
| Long edge | Full Size, 1024, 2048, 4096, 6000 px |
| Folder | resolved Quick Export path |

setting은 shortcut/toolbar/Output-tab의 Quick Export가 모두 공유한다. DPI나 long edge를 performance 이유로
몰래 낮추지 않는다. format을 바꾸면 기존 filename extension과 encoder option을 새 format에 맞춰 다시
계산한다.

### 10.2 verification

`Standard`, `Strict` 2-way segment를 유지한다. 정확한 차이는 export transaction 문서에 정의하고 Settings
help에서 요약한다. strict를 선택했다고 unsupported pixel/profile 조합을 자동 변환해 성공시키지 않는다.

### 10.3 color management

노출 항목:

- export color space
- soft proof on/off
- selected ICC/ICM profile
- profile-only / paper + black simulation
- destination gamut warning
- scanner input profile status
- working space: `Linear sRGB (Chromabase)`
- monitor profile
- export profile
- soft-proof summary

ICC/ICM picker 결과는 bytes를 읽은 뒤 Windows Color System/engine parser로 RGB output profile인지 검증한다.
extension만 보고 승인하지 않는다. invalid profile이면 이전 valid setting을 유지하고 inline error를 표시한다.

monitor summary는 `NSScreen.main`을 직역하지 않는다. preview가 표시된 `HMONITOR`의 현재 color profile을
조회하고 window가 monitor를 이동할 때 갱신한다. main display 고정도 금지한다.

soft proof option은 preview에만 적용하며 일반 export pixel에 자동 bake하지 않는다. Print의 output process와
일반 Export의 color transform은 각 manifest에 effective profile/intent를 기록한다.

## 11. Shortcuts

### 11.1 group

현재 7개 group을 유지한다.

- Library
- Photo
- Develop
- View
- Scanner
- Export
- Help

group selector는 한 줄 배치를 유지한다. translated label이 길면 wrap 대신 horizontal scroll을 제공하고
keyboard 방향키로 다음 segment에 이동한다.

### 11.2 recording

각 action row:

- localized action name
- 현재 shortcut chord
- click/focus 후 recording field
- per-action Reset
- invalid/conflict inline error

recording 중에는 다음 key-up까지 명확한 active state를 보인다. `Escape`는 취소다. modifier-only, 빈 key,
reserved system chord, 동일 action signature 충돌은 저장하지 않는다. 실패 시 기존 shortcut을 유지한다.

Windows mapping은 semantic action 기준으로 별도 default table을 확정한다.

- macOS `Command`를 기본적으로 `Ctrl` 후보로 매핑
- macOS `Option`은 `Alt` 후보
- macOS `Control`과 Windows system-reserved chord는 action별 검토
- `Alt+F4`, `Ctrl+Alt+Delete`, Windows key 조합 등 OS 소유 chord는 거부
- keyboard layout에 따라 printable key가 달라질 수 있으므로 physical key와 text input 의미를 혼동하지 않음

저장 payload는 action stable ID → normalized chord다. load 시 unknown action은 보존 가능한 migration payload로
분리하고, invalid 또는 duplicate override는 적용하지 않는다. `Reset All`은 confirmation 뒤 override만 지우고
제품 default table을 수정하지 않는다.

세부 Windows input 규칙은 [입력과 단축키](../input-and-shortcuts.md)를 따른다.

## 12. Legal

현재 분리된 selectable section을 유지한다.

- License
- Trademarks
- Product and project names
- Profiles/data provenance
- Non-affiliation notices

긴 본문은 selectable text여야 하고 screen reader의 reading order가 보이는 순서와 같아야 한다. 외부 link는
정확한 destination을 보이고 browser launch 전에 scheme를 allowlist한다.

Windows판에서 새로 추가할 항목:

- Windows App SDK와 .NET notices
- vcpkg로 포함된 native dependency license/provenance
- scanner plugin은 별도 배포물이며 각 plugin의 license·publisher가 다를 수 있다는 설명
- TWAIN/WIA/SANE 명칭과 vendor 상표 attribution
- Microsoft, scanner maker와 공식 제휴 관계가 없으면 명확한 non-affiliation 문구

법적 문구는 추측으로 작성하지 않고 release candidate의 실제 SBOM/NOTICE와 일치시킨다.

## 13. 설정 저장 모델

### 13.1 단일 schema

Windows판의 preference truth는 package-independent app-owned schema로 둔다.

```text
SettingsDocument
  schemaVersion
  presentation
  workflow
  scanDefaults
  storage
  cacheResidency
  export
  colorManagement
  shortcuts
  backup
  lastSelectedCategory
```

실제 구현 언어와 상관없이 public meaning은 이 구조로 고정한다. C# view model의 property bag, C++ engine
config, registry에 각각 독립 truth를 만들지 않는다.

### 13.2 write

- serialized writer 하나가 변경을 coalesce한다.
- 같은 directory의 temp file에 기록하고 flush한 뒤 atomic replace한다.
- 마지막 known-good copy와 schema version을 유지한다.
- multi-field invariant는 한 transaction으로 저장한다.
- UI thread에서 directory scan, hash, archive I/O를 하지 않는다.
- process 종료 시 pending write를 bounded하게 drain한다.

단순 preference는 변경 즉시 model에 반영하고 짧은 debounce 뒤 저장한다. 경로·backup·restore·plugin approval은
검증 transaction이 성공한 뒤에만 committed setting으로 바뀐다.

### 13.3 read와 migration

1. 파일 크기 upper bound 확인
2. JSON/schema decode
3. enum·수치 범위·path 형식 검증
4. old version을 단계별 migration
5. unknown field 보존 여부 결정
6. cross-field invariant 검증
7. valid snapshot을 model에 한 번에 적용

corrupt settings는 빈 catalog나 default storage를 근거로 파일 정리를 촉발하지 않는다. preference만 안전
default로 복구하고 원본·catalog·cache cleanup을 실행하지 않는다. 사용자에게 recovery 상태와 backup path를
알린다.

### 13.4 roaming 금지

Windows 11에서는 legacy `RoamingSettings`가 더 이상 지원되는 동기화 전략이 아니다. Negaflow 설정에는
machine-specific path, monitor profile, scanner/plugin identity, architecture-specific cache limit가 있으므로
전체 settings roaming도 제품상 부적절하다.

향후 선택적 sync를 만들더라도 language/theme/shortcut 같은 portable preference만 explicit schema로
분리하고 cloud dependency를 core app에 추가하지 않는다.

## 14. async와 오류 상태

Settings에서 비동기인 작업:

- cache size 계산/clear
- support bundle 생성
- scanner capability refresh
- plugin identity/hash 확인
- folder/volume 검사
- backup 생성
- restore generation 조회·검증·예약
- archive 생성
- ICC/ICM validation

공통 계약:

- operation ID와 owner window/category를 기록
- stale completion이 새 selection에 적용되지 않게 revision 확인
- 같은 operation의 중복 실행 방지
- cancel 가능한 작업과 commit-critical 구간을 구분
- 진행 중에는 해당 action만 disable하고 unrelated Settings는 계속 사용 가능
- 성공 toast만 띄우고 기록을 지우지 말고 마지막 결과를 해당 row에 남김
- 오류는 사용자 action, destination, recovery 가능 여부를 설명하되 raw path/개인정보를 telemetry로 보내지 않음

## 15. 접근성·localization

- 모든 category와 control은 이름, role, state, value를 UI Automation에 노출한다.
- path icon-only button에는 `Change folder`, `Open in File Explorer`, `Refresh` 이름을 준다.
- 색만으로 Ready/Failed/Selected를 표현하지 않는다.
- segmented selection과 shortcut recording state를 programmatically 전달한다.
- slider는 범위, step, 현재 값, unit을 노출한다.
- restore generation의 disabled reason을 읽을 수 있어야 한다.
- 200% Windows text scale와 긴 German/French/Korean label에서 truncation이 action을 숨기지 않아야 한다.
- RTL locale에서 navigation과 label/control 흐름을 mirror하되 path와 shortcut chord는 적절한 directional isolate를
  사용한다.
- 날짜·시간은 사용자 locale/time zone, persisted timestamp는 UTC를 사용한다.
- byte count의 display unit과 memory 계산의 binary byte를 구분한다.

## 16. 테스트 계약

### 16.1 unit

- 모든 enum의 unknown/invalid persisted value가 safe default로 복구
- schema migration golden files
- corrupt/truncated/oversized settings 처리
- automatic/manual cache limit 및 8/16/32/64/96/128 GiB 경계
- storage mode와 resolved Known Folder mapping
- custom path 변경 시 mode 전환
- default scan rotation 180°
- auto-develop 기본 off와 기존 frame 불변
- shortcut normalize/conflict/reset/migration
- ICC/ICM invalid profile 거부
- support bundle redaction과 per-bundle salt
- backup schedule/volume/generation state

### 16.2 integration

- Settings 창 single instance와 bounds restore
- picker owner가 올바른 window
- folder 선택 취소 시 model/write 없음
- unplugged external drive가 Ready로 남지 않음
- drive letter 재할당 시 volume identity 불일치 탐지
- backup 중 앱 종료/crash 후 journal recovery
- restore 예약 후 safe restart에서만 적용
- future/corrupt generation이 primary를 대체하지 않음
- cache clear가 scan/export/catalog에 닿지 않음
- theme/language가 열린 모든 window에 반영
- monitor 이동 시 color profile summary 갱신
- scanner plugin identity 변경 시 approval 해제

### 16.3 UI automation

- 8개 category 순서와 마지막 selection 복원
- keyboard-only category/control 탐색
- 100/150/200% display scaling
- 200/400% text scaling
- light/dark/high contrast
- 한국어/영어/일본어/중국어/프랑스어/독일어와 RTL smoke fixture
- 좁은 창에서 shortcut group과 backup action non-wrap/scroll
- loading/empty/error/disabled/pending state screenshot
- screen reader name/state/value snapshot

### 16.4 데이터 안전 fault injection

- settings temp write 후 power-loss simulation
- atomic replace 실패
- destination read-only/full/disconnected
- reparse point가 validation과 write 사이에 교체
- backup manifest/hash mismatch
- pending restore marker 손상
- catalog missing/corrupt/future schema
- support archive publish 중 destination replacement

## 17. 완료 기준

- 8개 category의 값·기본값·조건부 노출·disabled reason이 macOS 소스와 대조됨
- Windows 전용 저장 위치 명칭이 cloud 보장을 과장하지 않음
- 원본, derived cache, ephemeral cache, export, backup이 삭제 정책상 분리됨
- theme/language/shortcut/scanner 변경이 main workflow와 동일 truth를 공유함
- Settings 창이 native keyboard, high contrast, scaling, localization 검증을 통과함
- support bundle에 path/name/image metadata가 포함되지 않음
- backup 생성뿐 아니라 restore drill과 crash-safe restore가 검증됨
- WIA/TWAIN/SANE plugin code가 host process에 link/load되지 않음
- 테스트가 통과하기 전 “Windows Settings parity 완료”라고 표시하지 않음

## 18. 구현 순서

1. `SettingsDocument` schema와 migration fixture 확정
2. package-independent `%LOCALAPPDATA%` root와 atomic store 구현
3. single-instance Settings `AppWindow` + 8개 category shell
4. General/Interface/Workflow의 즉시 반영 preference
5. Scan capability/trust read model
6. Disk Known Folder/picker/volume state와 cache clear
7. backup/archive/restore transaction
8. Export/color profile validation
9. Windows shortcut recorder와 default mapping
10. Legal/SBOM/NOTICE와 privacy-safe support bundle
11. accessibility/localization/scaling 자동화
12. 실제 x64/ARM64, local/OneDrive-redirected/network/removable volume QA

## 19. 남은 의사결정

- Settings를 main window page로 합칠지 별도 `AppWindow`로 둘지 최종 usability prototype 비교
- 초기/최소 window size와 compact breakpoint
- Windows shortcut default chord 전체표와 system-reserved policy
- Documents가 cloud/network redirect된 경우 offline warning 수준
- OneDrive explicit mode를 1차판에서 제외하는 결정의 사용자 검증
- automatic cache heuristic을 Windows 실측 후 유지할지 조정할지
- external backup volume identity의 구체 API와 removable/network share 분기
- unpackaged 설치 제거 시 app-owned data를 유지할지 선택 삭제 UI를 제공할지
- Legal/NOTICE에 들어갈 실제 Windows dependency 목록

