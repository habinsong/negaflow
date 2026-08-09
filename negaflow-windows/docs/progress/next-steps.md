# 다음에 어디서부터 이어서 할 것인가

기준일: 2026-08-09 (ABI 0.6 Auto base v2와 WinUI 캔버스 상태 반영)

이 문서는 작업을 한동안 놓았다가 돌아왔을 때 가장 먼저 읽는 곳입니다. 이미 결정된 것을 다시
논쟁하지 않고, 다음 한 걸음을 바로 시작하기 위한 기록입니다.

## 지금 상태

전체 M0~M18 로드맵의 약 16%, 기반 구간 M0~M3 는 약 50% 입니다. 산정 근거는
`overall-roadmap.md`, 항목별 증거는 `../STATUS.md` 에 있습니다.

동작하는 것은 **CLI 수직 경로와 첫 WinUI 관통 경로**입니다. TIFF 디코드 → 스캐너 색상 → 수동
Dmin 현상 → 톤·포인트 커브·Color Mixer·Color Grading·Primary Calibration → 명시적 film-scan
Film Look → 검증된 PNG16/TIFF16 게시까지 한 장이 끝까지 갑니다. WinUI 에서는 Import → 필름 base
설정 → 노출 조정 → 같은 파이프라인의 미리보기 → Export 가 카탈로그와 C ABI 를 거쳐 동작합니다.

- 2026-08-09 x64 Release 재검증: native CTest 30/30, Catalog 303, Shell 200, Interop 44 assertion 통과
- Windows CI 가 PR 마다 돌고 벽시계 약 2분 30초
- 네이티브 엔진의 제3자 runtime dependency 0개 (Windows 기본 DLL 5개만)
- **카탈로그가 SQLite 로 디스크에 남습니다.** frame 5만 개 기준 쓰기 527ms, 읽기 255ms

**앱의 첫 관통 경로는 존재하지만 제품 UI는 아직 초기 단계입니다.** 현재 Develop 패널은 배관을
검증하려고 만든 임시 표면이며, macOS Negaflow 의 UI/UX를 동일하게 옮긴 정식 Develop inspector,
필름 base picker, 취소·진행률과 나머지 제품 surface가 남아 있습니다. GPU 경로는 착수 전입니다.

**한 가지 사실이 바뀌었습니다.** 제품 payload 에 제3자 native 바이너리(`e_sqlite3.dll`)가
처음 들어왔습니다. 네이티브 엔진의 0개는 그대로지만 두 문장은 이제 다른 뜻입니다. ADR-0025.

## 닫힌 결정 — 다시 열지 마십시오

| 결정 | 내용 |
|---|---|
| ADR-0004 | 이미지·색상은 OS API 우선. **유효합니다.** |
| ADR-0017 | Windows `src`/`tests` 만 1차 native source, vendoring 금지 |
| ADR-0021 | macOS golden 은 test-only 관측. 관측 float 총량 512 상한 |
| ADR-0022 | 미사용 WebView2 페이로드 미배포 |
| ADR-0024 | ColorSync 의 섀도우 toe 를 재현하지 않음 |
| ADR-0025 | catalog SQLite 는 관리 계층에서 열고 native SQLite 를 따로 고정. "의존성 0개" 는 네이티브 엔진에만 적용 |

**LittleCMS 검토는 폐기됐습니다.** 색 차이의 원인이 Windows CMS 선택이 아니라 ColorSync 가 ICC
사양에서 벗어나 있다는 사실이므로, Windows 에서 CMS 를 교체해도 macOS 와 같아지지 않습니다.
`overall-roadmap.md` 의 해당 항목은 이 사안에 한해 무효입니다.

---

## 1. SQLite 영속성 — 첫 왕복은 끝났습니다

**종료 조건("앱을 껐다 켜도 카탈로그가 남고 source 종류와 stage 순서가 바뀌지 않는다")을
충족했습니다.** ADR-0025, `verification/2026-08-07-sqlite-catalog-store.md`.

들어간 것:

- `SqliteCatalogStore` — `catalog_metadata` + entity table 9개, 물리 `user_version` 과 논리
  `catalog_version` 분리, 단일 `BEGIN IMMEDIATE` transaction, commit 후 `integrity_check`
- missing / corrupt / 미래 물리 version / 외부 논리 version / malformed payload 를 각각 다른
  값으로 거부. 어느 것도 빈 라이브러리가 아니고 부분 snapshot 도 없음
- `Pooling=False`. 켜 두면 backup 교체와 pending restore 가 남은 핸들에 막힙니다
- 재정렬 시 position relocation. 이것이 없으면 frame 3개 재정렬만으로 쓰기가 실패합니다
- `CatalogSession` — 유일한 공개 입구. store 는 `internal` 이라 lock 을 우회할 수 없습니다

**계획과 달랐던 것 두 가지.** 첫째, 편의 package `Microsoft.Data.Sqlite` 를 쓸 수 없었습니다.
native SQLite 하한이 CVE-2025-6965 대상이라 restore 가 NU1903 으로 실패합니다.
`Microsoft.Data.Sqlite.Core` + `SQLitePCLRaw.config.e_sqlite3` + `SourceGear.sqlite3` 로 나눠
참조합니다. 둘째, 고지는 "MIT 한 절" 이 아니라 MIT 1건 + Apache-2.0 4건입니다.

### 다음 행동: 나머지 수명주기

`windows_docs/14-persistence/catalog-and-storage.md` 가 소유하는 것 중 아직 없는 것입니다.
**순서를 지키십시오.** 아래는 뒤가 앞을 필요로 합니다.

1. ~~`CatalogProcessLock` 과 store 를 하나의 open 경로로 묶기.~~ **완료.** `CatalogSession` 이
   유일한 공개 입구이고 store 는 `internal` 입니다. lock 을 못 잡으면 세션이 만들어지지 않습니다.
2. **backup 세대와 commit verifier.** 직전 primary 를 보존한 뒤 write/readback/rollback.
   `CatalogRecovery.IsValidCatalogSource` 가 이미 있으니 손상 primary 가 유효 backup 을 덮는 것은
   막을 수 있습니다.
3. **pending restore.** 다음 safe startup 에서만 적용합니다.
4. **defect sidecar.** revision-aware writer, temp → flush → atomic replace. catalog 가 defect
   edit 을 선언했는데 sidecar 가 없으면 library open 을 차단합니다.

**셸을 붙일 때 쓸 것:** `CatalogSession.Open(roots)` → `ReadOrCreate()` → `Write(snapshot)` →
`Dispose()`. `ReadOrCreate` 가 없는 카탈로그를 만드는 유일한 자리이며, 손상이나 알 수 없는
version 은 거기서도 실패합니다. **어디서도 `NotFound` 를 빈 라이브러리로 바꾸지 마십시오.**

legacy JSON → SQLite migration 은 **하지 않습니다.** Windows 에는 옮겨올 legacy 파일이 없습니다.
macOS catalog 를 여는 것은 결정 4에서 이미 배제했습니다.

**종료 조건: 쓰기 도중 프로세스를 죽여도 다음 실행에서 카탈로그가 열리고, 무엇이 손실됐는지
말할 수 있다.**

---

## 2. 세로 슬라이스 — 첫 관통 완료, 정식 UI/UX 이식이 다음입니다

`카탈로그 → C ABI → WinUI 셸` 첫 관통은 완료됐습니다. 이제 임시 Develop 표면을 macOS Negaflow의
실제 UI/UX와 동일하게 이식하는 것이 최우선입니다. 배관은 유지하되 표면을 창작하지 않습니다.

### 진행 상황

`nf_develop_export_v1` 과 `nf_develop_preview_v1` 을 포함한 현재 ABI 는 **0.5**입니다. 게시와
미리보기는 같은 요청 구조와 파이프라인을 사용하며, 관리 쪽 `NativeDevelopExporter`가 감쌉니다.
실패는 **거부한 단계 + 그 단계 자신의 상태 이름**으로 돌아오므로, 없는 파일
(`observe_source_before`) 과 잘못된 요청 (`request_validation`) 이 구별됩니다.

완료된 셸 관통 경로는 다음과 같습니다.

1. `CatalogSession` 으로 카탈로그를 열고 frame 목록을 Library/Develop 에 표시합니다.
2. Windows App SDK file picker 로 TIFF 를 import 하고 필름 base와 노출을 저장합니다.
3. `PreviewCoordinator` 가 겹친 요청 중 마지막 상태를 보존해 ABI 0.6 미리보기를 캔버스에 그립니다.
4. Export 버튼이 `NativeDevelopExporter.Run` 을 호출하고 검증된 결과 파일을 씁니다.

**스레딩을 여기서 틀리면 안 됩니다.** `NativeDevelopExporter.Run` 은 현상 전체 동안 블로킹하며,
일부러 async 래퍼를 두지 않았습니다. UI 스레드에서 부르면 앱이 굳습니다. 백그라운드로 보내기
**전에** `DispatcherQueue` 를 캡처하고, 결과는 `TryEnqueue` 로 되돌리십시오. 아래 함정 절을
그대로 따르면 됩니다.

취소와 진행률은 아직 ABI 에 없습니다. 실제 스캔 해상도에서 바로 드러날 문제이므로 정식 UI 이식과
대형 이미지 경로에서 함께 설계해야 합니다.

다음 목표는 기능 수를 늘리는 것이 아니라, 이미 뚫린 경로를 macOS 제품과 동일한 UI/UX에 연결하는
것입니다. 화면 구조·치수·간격·컨트롤 순서·상태 전이·키보드·접근성 의미를 고정 기준에서 추출하고
WinUI 3 로 그대로 구현합니다. 운영체제가 강제하는 차이만 별도 delta 로 기록합니다.

### UI 는 창작하지 않습니다 — macOS 를 그대로 이식합니다

**현재 Develop 패널의 XAML 은 배관을 돌려 보려고 임시로 만든 것이며 버릴 것입니다.** Import 버튼,
필름 base 슬라이더 3개, 노출 슬라이더, Export 버튼, 상태 문구는 전부 macOS 에 대응물이 있거나
아예 다른 형태입니다.

이식 대상은 `negaflow-mac/Sources/negaflowApp/Features/Develop/Inspector/` 이며 순서는
`DevelopAdjustmentSections.swift` 가 정의합니다.

1. `basicToneSection`
2. `toneCurveSection` — `ToneCurveEditor.swift`
3. `colorSection`
4. `colorMixerSection` — `ColorMixerSection.swift`
5. `colorGradingSection` — `ColorGradingSection.swift`
6. `bwToningSection` — 흑백일 때만
7. `calibrationSection`
8. `detailSection`

필름 base 는 `BaseControlSection.swift` 가 소유합니다. 제가 만든 raw 슬라이더 3개가 아닙니다.
`FilmEmulationSection.swift`, `DevelopQuickActionsSection.swift`, `InteractiveHistogramView.swift`,
`InspectorSlider.swift`/`ResettableSlider.swift`/`EditableSliderValueText.swift` 같은 공통 컨트롤도
그쪽 구조를 따릅니다.

치수는 `baseline/swift-ui-metrics.json` 처럼 macOS 소스에서 가져옵니다. **판단으로 정하지
마십시오.** macOS 에 대응물이 없는 것이 필요하면 지어내지 말고 물어보십시오.

**배관은 이식 대상이 아닙니다.** C ABI, coordinator, 스레딩, 카탈로그는 Windows 쪽 설계입니다.
바뀌는 것은 표면뿐입니다.

### 왜 이것이 파이프라인 확장보다 먼저인가

지금까지 28단계를 CLI 로만 검증했습니다. CLI 검증은 앱에서 가장 위험한 것들을 **전부 우회합니다** —
UI 스레딩, 취소, 객체 수명, 사용자 조작 중 메모리 압박, C ABI 경계의 예외 전파.

구성요소를 격리해 만들면 통합 리스크가 프로젝트 끝으로 밀립니다. 데이터 계약과 지연·출력 형식이
뒤늦게 깨지고, 그때는 이미 각 구성요소를 최적화해 둔 뒤라 재작업 비용이 큽니다. 얇더라도 끝까지
한 번 뚫어 두면 구조와 패턴이 자리를 잡고 기본이 동작한다는 것이 증명됩니다.

첫 앱 경로가 동작해도 M9~M14 제품 표면 대부분은 남아 있습니다. UI 와 장치 연동처럼 검증이 어렵고
되돌리기 비싼 작업이 뒤에 몰려 있으므로, 임시 화면을 제품 완성으로 세지 않습니다.

### 미리 알아 둘 함정

WinUI 3 는 **STA** UI 모델입니다. 모든 UI 요소는 그것을 만든 스레드가 소유하고 그 스레드의
`DispatcherQueue` 에 묶입니다.

- 백그라운드 스레드에서 컨트롤을 건드리면 **예외가 납니다.**
- UWP 의 ASTA 와 달리 **reentrancy 보호가 없습니다.** 메시지를 펌프하는 async 코드에서 XAML
  컨트롤로 재진입하는 경로를 주의해야 합니다.
- 결과를 UI 로 돌릴 때는 `DispatcherQueue.TryEnqueue` 를 씁니다. 백그라운드 작업에 들어가기
  **전에** `DispatcherQueue` 를 캡처해 두는 편이 깔끔합니다. `HasThreadAccess` 로 확인할 수 있습니다.
- C++/WinRT 쪽 수명은 `winrt::implements` 파생과 `[this, self=get_strong()]` 캡처로 잡습니다.

이 함정들은 CLI 에서 절대 드러나지 않습니다. 세로 슬라이스를 미루면 이것들을 M9 이후에 한꺼번에
만나게 됩니다.

**첫 관통 종료 조건은 충족했습니다.** 실행 중인 앱에서 Import → base 설정 → 노출 → Export 를
UI Automation 으로 조작해 `Exported 631×403 in 101 ms`를 확인했습니다. 이후 ABI 0.5
`nf_develop_preview_v1`, 이어 Auto/Manual을 명시하는 ABI 0.6 v2와 WinUI 캔버스 렌더가 추가됐습니다. 관통 근거는
`verification/2026-08-07-vertical-slice.md`, 미리보기 구현·테스트 근거는 `bb8d248`와 `98df788`입니다.

**공통 slider/value control의 현재 연결은 Exposure와 수동 Base R/G/B입니다.** 고정 baseline의
inspector 구조와 `baseline/swift-ui-metrics.json`을 기준으로 label·편집값·slider·keyboard nudge를
재사용 control로 묶었습니다. Exposure만 double-click reset을 제공하며 수동 Base는 reset하지 않습니다.
구현과 x64 증거는 `implementation/develop-inspector-slider.md`에 기록했습니다.

**Base recipe의 Catalog persistence 경계와 첫 Auto v2 경로가 완료했습니다.** `baseEstimationMode`, film stock,
light source, scanner profile ID는 수동 Dmin과 독립적으로 보존됩니다. Auto는 ABI 0.6의 별도 request로
decode 후 linear working image edge를 측정해 scene-ranged inversion에 전달하며, Preview와 Export가 같은
resolver 결과를 사용합니다. v1 수동 ABI는 유지합니다. 이 resolver는 macOS의 scene-edge fallback만 이식한
`FilmBaseEstimator` sampled-grid fallback과 chromogenic B&W 재시도, bundled film-stock/light-source resolver,
Film mode picker, ABI 0.10 preview/export 연결은 구현되었습니다. 다음 한 걸음은 scanner-profile grade와
제조사별 Film picker presentation, canvas base picker/reset입니다. Basic Tone과 Parametric Tone Curve의 네 slider는
Inspector에 Point Curve `ToneCurveEditor`와 Color Mixer HSL 8밴드까지 연결되었습니다. rendered/UIA 검증은 아직 별도 작업입니다. 취소·진행률과
대형 이미지 스케줄링은 그 다음 필수 경로입니다.

---

## 3. GPU 스파이크 — 버릴 코드로

M5 전체가 아니라 **스테이지 하나만** D3D11 로 던져 보고, FP32 결과가 기존 scalar golden 의
허용오차 안에 드는지 확인하는 정도입니다.

현재 모든 수치 계약이 CPU scalar 기준으로 고정돼 있습니다. macOS 는 Core Image(GPU)로 돌고
Windows 는 scalar 로 맞췄으며 앞으로 D3D11/WARP 가 들어옵니다. 세 구현이 서로 허용오차 안에
있어야 하는데, GPU 는 결합 순서와 정밀도가 CPU 와 미묘하게 달라 지금 잡아 둔 2.1e-3 / 4.0e-4 가
유지될 보장이 없습니다.

20단계를 scalar 가정 위에 다 쌓은 뒤 알면 golden 체계를 다시 설계해야 합니다. 세로 슬라이스
작업 중 어디쯤에서 하루 던져 보는 것으로 충분합니다.

**중요: golden 허용오차를 조이지 마십시오.** 세 구현은 각각 **하나의 기준(Core Image)** 과
비교돼야 합니다. 서로 사슬처럼 비교하면 오차가 누적됩니다.

---

## 4. 그 외 (순서 무관)

- 독립 Deflate 검증기를 구현하거나 dependency gate 를 열 근거를 확보합니다. 현재 Deflate 는
  fail-closed 로 격리돼 있습니다.
- 스캐너 호스트(M15): 플러그인은 이미 있으므로 **프로토콜 v2 클라이언트 구현 + 실제 장치 검증**
  입니다. 자세한 내용은 아래 결정 11번을 보십시오.
- 최종 working buffer 와 출력을 downstream row/tile 소비자로 넘기고 전체 process budget 을
  적용합니다. (M7, 현재 6%)
- WinUI 셸의 축소 폭·DPI·High Contrast·keyboard matrix 를 검증합니다.
- 나머지 Develop 후처리 단계를 macOS 실행 순서대로 이식합니다.

---

## 하지 않기로 한 것

**다점 TRC 프로파일의 ColorSync 측정.** 한때 다음 작업 1순위로 적었으나 철회합니다.

ADR-0024 가 이미 "재현하지 않는다" 로 결정했으므로, 측정 결과가 어느 쪽이든 **지금 하는 행동이
바뀌지 않습니다.** 차이의 크기도 8비트 코드 255단계 중 2~6, 그것도 하이라이트에 한정됩니다.
행동을 바꾸지 않는 측정에 macOS 세션과 CI 시간을 쓰는 것은 비용 대비 효과가 맞지 않습니다.

ADR-0024 의 재검토 조건이 실제로 발생하면 그때 합니다. 그 조건과 재현 방법은 ADR 에 이미 적혀
있으므로 다시 조사할 필요가 없습니다.

## 남은 판단 — 전부 결정했습니다

앞으로 막힐 만한 갈림길을 미리 정해 둡니다. **다시 조사하거나 논쟁하지 마십시오.** 각 항목의
"뒤집는 조건" 이 실제로 발생했을 때만 다시 엽니다. 실행 시점에 결정 기록(ADR)으로 옮겨 적으면
됩니다.

### 1. SQLite 라이브러리 → 실행됨. ADR-0025 로 옮겨 적었습니다

`Microsoft.Data.Sqlite.Core` 10.0.10 (MIT) + `SQLitePCLRaw.config.e_sqlite3` 3.0.5 +
`SourceGear.sqlite3` 3.53.4 (Apache-2.0) 입니다.

**여기 적혀 있던 "`Microsoft.Data.Sqlite`" 는 실행해 보니 쓸 수 없었습니다.** 그 편의 package 는
native SQLite 하한을 `SQLitePCLRaw.lib.e_sqlite3` 2.1.11 로 끌어오는데, 이것이 CVE-2025-6965
(CVSS 7.2) 대상이고 2.x 에 수정 릴리스가 없습니다. restore 가 NU1903 으로 실패합니다.
SQLitePCLRaw 3.0 이 권하는 대로 native 를 분리해 참조하면 취약 package 가 사라지고, 다음 SQLite
권고에는 `SourceGear.sqlite3` 한 줄만 올리면 됩니다.

`winsqlite3.dll` 배제와 네이티브 vendoring 배제는 원래 판단대로입니다.

**뒤집는 조건:** 카탈로그를 네이티브로 옮기기로 결정하는 경우.

### 2. ORM → 쓰지 않습니다. ADO.NET 을 직접 씁니다

EF Core 도 Dapper 도 넣지 않습니다. 카탈로그 스키마는 우리가 소유하고 규모가 작으며, 이 저장소는
모든 경계를 명시적 계약으로 손으로 쓰는 방식으로 일관돼 있습니다. EF Core 는 패키지 다발과
마이그레이션 기구, 시작 비용을 함께 들여옵니다. 데스크톱 단일 사용자 카탈로그에 그 값을 치를
이유가 없습니다.

SQL 은 손으로 씁니다. 스키마 버전은 `PRAGMA user_version` 으로 관리합니다. **실행 결과 이 판단은
유지됩니다.** store 전체가 파일 하나이고, table 이름은 enum 에서만 나오며, 호출자 문자열이 SQL 로
흘러가지 않습니다.

**뒤집는 조건:** 스키마가 20개 테이블을 넘고 관계 매핑 유지 비용이 실제로 문제가 되는 경우.

### 3. "제3자 의존성 0개" 의 범위 → 네이티브 엔진에만 적용

`Negaflow.Native.dll` 과 `negaflow-cli.exe` 는 Windows 기본 DLL 외에 아무것도 링크하지 않습니다.
이 기준은 유지합니다.

**관리 계층에는 적용되지 않습니다.** 셸은 이미 WinUI 와 Windows App SDK 위에서 돕니다. 관리 코드에
MIT 패키지를 더해도 네이티브 엔진의 0개는 그대로입니다.

ADR-0025 에 명시했습니다.

**다만 실행하면서 한 가지가 드러났습니다.** 이 결정으로 배포 payload 에 제3자 **native** 바이너리
(`e_sqlite3.dll`) 가 처음 들어옵니다. "네이티브 엔진의 제3자 0개" 와 "제품 payload 의 제3자 0개"
는 이제 다른 문장이며, 두 번째는 더 이상 참이 아닙니다. `THIRD-PARTY-NOTICES.md` 가 이를 구분해
적고 있으니 SBOM 을 만들 때 흐리지 마십시오.

### 4. 카탈로그 스키마를 macOS 와 공유하는가 → 공유하지 않습니다

같은 `.sqlite` 파일을 두 플랫폼이 번갈아 여는 것은 제품 요구가 아닙니다. 스키마를 묶으면 양쪽 진화가
서로를 막습니다.

**호환은 recipe payload 수준에서만 유지합니다.** 그 경계는 이미 `Catalog.Core/Recipes` 의 develop
route projection 으로 구현돼 있고 legacy marker 와 강도 기본값까지 보존합니다. 라이브러리를 옮겨야
하는 상황이 생기면 DB 를 공유하는 대신 recipe 를 내보내고 들여옵니다.

**뒤집는 조건:** 한 라이브러리를 두 플랫폼에서 번갈아 쓰는 것이 명시적 제품 요구가 되는 경우.

### 5. Windows 가 macOS 와 같은 그림을 내야 하는가 → 필수 아닙니다

ADR-0024 를 유지합니다. 측정된 차이는 8비트 코드 2~6 이며 하이라이트에 한정됩니다. 플랫폼 차이로
문서화하고 넘어갑니다.

**뒤집는 조건:** ADR-0024 의 재검토 조건. 그 안에 재현 방법까지 적혀 있으므로 재조사는 필요 없습니다.

### 6. GPU 처리 경로 → D3D11 compute shader

Win2D 는 채택하지 않습니다. Win2D 는 XAML 과 잘 붙는 2D 캔버스 드로잉 라이브러리이고, 우리가 필요한
것은 FP32 색 파이프라인입니다. WinUI 3 지원도 여전히 작업 중 상태이며 서드파티 포크가 도는 상황이라
제품 기반으로 삼기에 이릅니다.

처리는 XAML 과 무관한 headless 경로로 둡니다. 그래야 CLI 와 셸이 같은 엔진을 공유합니다.

**뒤집는 조건:** compute 로 구현하기 어려운 효과가 나타나고 Direct2D 내장 효과가 그것을 정확히
제공하는 경우.

### 7. 화면 표시 → 처음에는 일반 비트맵. `SwapChainPanel` 은 나중에

세로 슬라이스에서는 결과를 sRGB8 비트맵으로 바꿔 `Image` 컨트롤에 얹는 것으로 충분합니다.
`SwapChainPanel` 은 DXGI·Direct2D·Direct3D 를 모두 알아야 하고 저지연 실시간 갱신이 필요할 때
쓰는 물건입니다. 지금 도입하면 통합 리스크만 키웁니다.

**뒤집는 조건:** 실시간 조정 중 프레임 지연이 실제로 문제가 되는 경우.

### 8. 배포 형식 → MSIX + `.appinstaller` 직접 배포

MSIX 가 WinUI 3 의 권장 경로입니다. 설치 경험이 하나로 끝나고, 제거하면 남는 것이 없으며, 차등
업데이트로 바뀐 블록만 내려받습니다. package identity 가 필요한 API 도 이때 열립니다.

현재는 `WindowsPackageType=None` 인 미패키지 구성입니다. M17 에서 바꿉니다. 미패키지 상태에서는
푸시 알림, 매니페스트 기반 백그라운드 작업, MSIX 자동 업데이트를 쓸 수 없습니다.

**뒤집는 조건:** MSIX 를 못 쓰는 기업 배포 요구가 생기는 경우. 그때는 WiX 또는 Inno Setup 이고
업데이트는 직접 구현해야 합니다.

### 9. 업데이트 → `.appinstaller` 자동 업데이트

8번의 결과입니다. 별도 업데이터를 만들지 않습니다.

### 10. 코드 서명 → Azure Trusted Signing 우선

2026년 기준 Basic 등급 월 $9.99, 서명 5,000건까지입니다. Microsoft 자체 CA 라 **SmartScreen 평판이
즉시 붙습니다.** 전통적 인증서는 평판을 쌓는 동안 사용자에게 경고가 뜨는데, 1인 프로젝트에는 이
차이가 큽니다. 인증서는 3일짜리 단기이며 자동 갱신되므로 하드웨어 토큰 관리가 없습니다.

**대한민국은 자격 국가 목록에 포함됩니다.** 다만 자료마다 "조직" 기준과 "개인" 공개 미리보기가
구분돼 있으므로, M17 착수 시점에 **개인 자격으로 등록 가능한지 먼저 확인**하십시오. 등록이 막히면
대안은 일반 CA 의 코드 서명 인증서이며, 전 세계에서 발급받을 수 있고 소유권이 본인에게 있습니다.
대신 평판을 처음부터 쌓아야 합니다.

**뒤집는 조건:** 개인 자격 등록 불가, 또는 Windows 외 플랫폼 서명이 필요해지는 경우.

### 11. 스캐너 연결 → 기존 SANE 플러그인을 그대로 씁니다

**이미 만들어져 있습니다.** [`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane)
저장소의 `windows/` 에 C++20 MSVC 구현이 있고 활발히 개발 중입니다. 새로 만들 것이 없습니다.

- 프로토콜은 **v2, 줄 단위 JSON**. `detect` / `capabilities` / `scan` 서브커맨드.
- **별도 실행 파일, 별도 프로세스.** macOS 와 같은 경계이며 ADR-0006 그대로입니다.
- backend 16개 분기 구현: `genesys`(Plustek OpticFilm), `epson2`, `coolscan`, `pieusb`.
- vcpkg static CRT 로 빌드. 의존성은 libtiff 와 RapidJSON.

TWAIN 과 WIA 는 검토할 필요가 없습니다. 참고로 WIA 는 600dpi 상한이 있어 애초에 필름 스캔에 쓸 수
없고, TWAIN 은 이미 동작하는 경로를 두고 새 드라이버 계층을 만드는 일이 됩니다.

**라이선스 경계가 이 구조의 핵심입니다.** 플러그인은 GPL-2.0-or-later 이고 negaflow 본체는
Apache-2.0 입니다. 그래서 별도 저장소, 별도 프로세스, JSON 경계입니다. `verify-provenance.py` 가
본체에 SANE 구현 마커(`sanei_`, `libsane`, `sane-backends`)가 들어오는 것과 릴리스 스크립트가
플러그인을 번들하는 것을 **자동으로 막습니다.** 이 경계를 흐리면 본체의 라이선스가 오염됩니다.
어떤 이유로도 SANE 코드를 `negaflow-windows` 안으로 들이지 마십시오.

**Windows 쪽에서 할 일은 플러그인을 만드는 것이 아니라 그 프로토콜의 클라이언트가 되는 것입니다.**
macOS 앱에 이미 호스트 구현이 있으므로 계약은 정해져 있습니다.

**알려진 위험:** 플러그인 Windows 빌드는 2026-08 기준 **실제 장치 검증이 0회** 입니다. 실행은 되지만
진짜 스캐너로 확인된 적이 없습니다. 그 외 read-path 핸들 검증 미완, macOS 와의 CRLF 처리 차이,
GUI 호스트에서 콘솔 기반 취소가 안 될 때 강제 종료로 대체되는 문제가 남아 있습니다. 설치·배포
스크립트는 그 저장소의 M7 예정입니다.

M15 에 착수할 때는 **플러그인 구현이 아니라 실제 장치 검증부터** 시작하십시오. 그것이 이 경로에
남은 유일한 큰 미지수입니다.

**뒤집는 조건:** 없습니다. 이 구조는 라이선스 격리 때문에라도 유지해야 합니다.

### 12. SQLite 재저장 비용 → 지금은 최적화하지 않습니다

무변경 재저장이 frame 5만 개에서 343ms 입니다. 이 store 의 비용은 **바뀐 양이 아니라 catalog 전체
크기에 비례**합니다. row 하나를 고쳐도 5만 건의 upsert 가 돌고 `integrity_check` 가 파일 전체를
훑습니다. `WHERE` 가드는 디스크 페이지 쓰기만 막고 statement 실행은 막지 못합니다.

**지금은 최적화하지 않습니다.** 목표 규모에서 1초 미만이고, 조기 최적화는 아직 없는 호출 패턴을
가정하게 만듭니다.

**뒤집는 조건:** 목표 규모가 5만을 크게 넘거나, 편집 한 번의 저장 지연이 UI 에서 감지되는 경우.
그때 손댈 곳은 두 군데입니다. (1) 호출자가 dirty 집합을 넘겨 바뀐 row 만 upsert 하는 것,
(2) `integrity_check` 를 매 쓰기가 아니라 열기와 backup 생성에서만 돌리는 것. 측정값은
`verification/2026-08-07-sqlite-catalog-store.md` 에 있습니다.

### 결정하지 않은 채 남기는 것

없습니다. 위 12개로 M4~M17 의 주요 갈림길은 전부 정해졌습니다. 새 갈림길이 나타나면 그때 이
문서에 같은 형식으로 추가하십시오 — **결정, 이유, 뒤집는 조건.** 12번이 실행 중에 그렇게 추가된
첫 항목입니다.

## 재개하는 방법

```powershell
# Windows 전체 게이트 (네이티브 + 관리)
.\negaflow-windows\scripts\ci-gate.ps1 -Preset x64-release
```

```bash
# 저장소 전체 provenance·라이선스 게이트
py negaflow-mac/scripts/ci/verify-provenance.py
```

macOS 쪽 짝은 `negaflow-mac/scripts/ci-gate.sh` 입니다. 두 입구는 분리돼 있으니 한쪽만 고치면 갈라집니다.
