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


# 03 — 기능 단위 상태

사용자가 2026-08-18 에 직접 짚은 것 + 코드 대조로 확인한 것입니다.
**"확인함"은 파일과 줄 번호를 적었습니다. 못 잡은 것은 못 잡았다고 적었습니다.**

---

## 1. 사용자가 보고한 증상 → 코드에서 확인한 원인

| # | 증상 | 원인 (확인함) | 상태 |
|---|---|---|---|
| 1 | 우측탭 슬라이더가 **1씩** 움직임 | `Views/Controls/InspectorSlider.xaml` 에 `StepFrequency` 미지정 → WinUI 기본 **1**, `SnapsTo` 기본 StepValues. macOS 는 `Slider(value:in:)` 에 `step:` 없음 = 연속 | **고침(0.01)** |
| 2 | 숫자 눌러도 **입력·Enter·ESC 안 됨** | `InspectorSlider.xaml.cs BeginEditing()` 이 TextBox 를 막 `Visible` 로 바꾼 **같은 틱에** `Focus()` 호출 → 배치 전이라 실패 → 포커스가 방금 접은 단추를 떠나 슬라이더로 감. `IsTabStop="False"` 도 겹침 | **고침** |
| 3 | **톤 곡선 작동 안 함** | 네 축이 `InspectorSlider` 라 #1 직격. 범위가 ±작은 값이면 정수 스냅으로 **양 끝만** 잡힘. 점 커브 엔진 자체(`point_curve.cpp`)는 macOS 와 일치 | #1 고침으로 해소 예상, **미검증** |
| 4 | **현상 타깃 MAIN·HS·SP·F135·HR 선택 안 됨** | 타깃 바가 `Views/Library/Defaults/LibraryDevelopDefaultsPanel.xaml.cs:61` 에**만** 있었음 | **2026-08-20 닫음.** 현상 뷰 좌측탭에서 고르면 필름 프로파일·프리뷰·메뉴 체크가 함께 따라온다(UIA 확인). 메뉴 타깃 하위 7개·라이브러리 폴더 머리줄도 그대로 — [`07`](07-user-reported.md) K2 |
| 5 | **필름 프로필·룩 작동 안 함** | `DevelopFilmLookPanel.xaml.cs:74-88` 은 붙어 있음. #1 과 겹칠 가능성(강도 슬라이더) | **원인 미확정** |
| 6 | 오탈자 `타깋` `룹` | `ko-KR/Resources.resw`. macOS 원문은 `타깃`·`룩` | **2026-08-19 고침.** `필름스톡`·`중간톤` 과 설정 5건까지 6언어로 맞춤 — [`07`](07-user-reported.md) F |
| 6.5 | **필름 베이스 수동 — 베이스 스포이드 없음** | macOS `FilmBasePicker.swift`(149줄) + 캔버스 오버레이 + 인스펙터 캡슐이 전부 없었음. 수동 모드에서 베이스를 집을 유일한 수단 | **2026-08-18 이식함**(`d39e55e`). **C1.9** RealScan 리베이트 클릭 → Dmin `0.40 0.13 0.07`, 헤더·현상본 유지. 장면 클릭은 Dmin 유지 |
| 6.6 | **필름 베이스 자동 — 창작 관문** | `connected_component_base` 의 `candidate_peak` 게이트가 macOS 에 없는 것 | **2026-08-18 제거함**(`cfd5e88`). 죽은 코드였음 — 17장 dmin **바이트 동일** |
| 7 | **스캐너에서 DPI·심도·프레임 규격 고르면 앱 종료** | `LibraryScanPanel.xaml` 92·122·135행 셀렉터의 `SelectionChanged` | **종료 지점 미확인** |
| 8 | **스캐너 플러그인 로딩 자체가 안 됨** | `Shell.Core/Scanner/` 20파일 존재. 동작 미확인 | **미확인** |
| 9 | **비교 캡슐** | 캡슐+분할 클립 2026-08-19. Before 소스 메뉴·앱 클릭 실측 남음 | **부분** |
| 10 | **줌 HUD** | 수식+단추+끌기 2026-08-19. 앱 드래그 실측·인화 HUD 는 남음 | **부분** |
| 11 | **좌측 세로 레일이 가짜** | `LibrarySourceRail.cs:74-76` 이 내는 것은 3개(Import·Files·Collections). macOS 는 `WorkflowSidebar` + `WorkspacePresentationStore.sidebarTab` 저장까지 | **없음 확정.** 2026-08-20 사용자가 **3뷰 전부**(라이브러리/현상/인화)의 세로 레일·좌측탭·우측탭·상단탭을 지시 |
| 12 | **내보내기·빠른 내보내기 부실** | macOS Export **41파일 7,034줄** → Windows **6파일**. 배치·체크포인트·저널·트랜잭션·검증등급 전부 없음 | **없음 확정** |
| 13 | **GrainMend IR** | 짝짓기+선택 자동 정리 2026-08-19. Swift 에 5번째 도구 단추 없음 | **부분** |
| 14 | **초기화(모든 보정·사진 각도)** | `DevelopResetCard` + `DevelopInspectorResetter` + 현상 메뉴. 베이스·기하는 유지 | **2026-08-19 붙음** |
| 15 | **인화 프리뷰가 저해상도 썸네일이라 깨짐** | `Views/Print/Preview/PrintPreviewRenderer.cs:323-325` 가 `thumbnails()?.TryGet(frame.Id)` → `DecodeThumbnail(jpeg)` 로 **360px 썸네일**을 그대로 확대. macOS `PrintCanvasView.swift:165-167` 은 `frame.developedImage ?? packagePreview ?? thumbnailImage` 순서로 **현상본이 먼저** | **2026-08-19 고침.** 현상 화소 기억 + 칸이 크면 `PrintPreviewResolution` 으로 현상본 업그레이드. 앱 인화 판에서 현상본 확인 |
| 16 | 프리뷰가 뭘 해도 수 초 | 고치기 전: 매번 디코드. 지금: FIFO + 2슬롯. CLI 1280 두 번째 43.1 ms. **앱 벽시계 미측정** | [`16`](16-preview-handoff.md) |
| 17 | GrainMend 자동이 느림 | 형태학+스크래치 각도 GPU 기본 켬. 검출 17.3s → **4.66s**. 가이드·브러시·복제·IR 즉각은 앱 미측정 | [`15`](15-gpu-handoff.md) 3.2 |
| 17.1 | 현상·보정 단계별 ms | **있음.** `--develop-timing` · `NEGA_TIMING=1` · `stage_timing.cpp` | 닫음 |
| 17.3 | **GPU 착수** | `src/Native/gpu/` — D3D11 컴퓨트, FL 11_0 하한, WARP 폴백, 벤더 중립. 화소별 커널 **11개** + 이웃 원시연산 **4개**(박스·가우시안·3×3 중앙값·가이드필터) 이식, 전부 CPU 동치 `1e-5` 고정. **박스·가우시안·중앙값은 전 조건 비트 단위 일치.** **톤 단계 7/7 완주**(우측 인스펙터 경로 전체) + **`filmScanShrink` 전 사슬**(`apply_film_scan_denoise` 와 직접 대조, CPU 와 같은 512/18 타일로 1.2e-07) | **2026-08-18.** 상세는 [`04`](04-gpu-plan.md) 0절 |
| 17.4 | **GPU 가 아직 아닌 것** | 내장 GPU 실기 · `GpuImagePool` 내장 메모리 · 64³ 큐브는 별건. 커널 3.1–3.8 은 닫음 | [`15`](15-gpu-handoff.md) 4절 |
| 17.5 | **GPU 가 재서 확정한 제약 둘** | ① 러닝 섬을 쓰는 단계는 GPU 도 **CPU 와 같은 타일**로 나눠야 값이 같습니다 — 창 밖을 안 봐도 **누적 이력**이 따라옵니다(전체 한 번에 4.3e-05, 같은 타일 1.2e-07) ② HLSL `pow` 는 `std::pow` 와 **마지막 비트가 같을 수 없고**(D3D11 이 `log2`·`exp2` 에 2^-21 허용), 가이드 필터의 `1/(variance+ε)` 이 그 1 ulp 를 2e-05~6e-05 로 키웁니다 | [`13`](13-performance-playbook.md) 15·16절 |
| 17.2 | **CPU 쪽 안 켠 것** | SIMD 는 `flatbed_frame_*` 만. 스레드 풀은 **있음**(`row_block_pool`). `/GL`·`/LTCG` 없음 | [`13`](13-performance-playbook.md) |

---

## 2. 없는 기능 — 확정 (히트 0)

### 2.1 현상 뷰 우측 인스펙터

| macOS | 줄 | Windows |
|---|---:|---|
| `Tools/ResetControlsSection.swift` | 44 | **있음.** `DevelopResetCard` |
| `DevelopInspectorResetter.swift` | 104 | **있음.** `DevelopInspectorResetter.cs` |
| `DevelopInspectorKeyboardController.swift` | — | **없음** |
| `DevelopInspectorProfileMatcher.swift` | — | **없음** |
| `Histogram/InteractiveHistogramView.swift` | — | 히스토그램은 그림. 상호작용 없음 |
| `Tools/DefectControlsSection.swift` | — | 히트 0 |
| `DevelopHistory` + `DefectHistory` | 228 | `FrameEditHistory` 있음. 이력 **패널**은 없음 |

### 2.2 캔버스

| macOS | 줄 | Windows |
|---|---:|---|
| `CanvasCompareControls.swift` | 197 | `CanvasCompareHud` (2026-08-19). Before 소스 메뉴 남음 |
| `CanvasCompareDivider.swift` | 166 | `CanvasCompareDividerState` (2026-08-19) |
| `CanvasViewportState.swift` | 71 | `CanvasViewportState` (2026-08-19) |
| `CanvasHUDPlacement.swift` | — | `CanvasHudPlacement` + 끌기 상태 |
| `CanvasScrollPanBridge.swift` | — | **없음** |
| `CanvasView+Comparison.swift` | — | **없음** |

### 2.3 라이브러리

`FilmstripScope` · `FrameStepButton` · `FrameRenameSheet` · `LibraryCompareView` ·
`LibraryOrganizerSection` · `LibraryOrganizerNameSheet` ·
`HorizontalFilmstripWheelBridge` — 전부 히트 0.

`LibraryFolderDevelopmentControls` 는 **2026-08-20 에 붙었습니다**
(`LibraryFolderDevelopment.cs` + 폴더 머리줄 프로세스/타깃/적용).

### 2.4 인화

`PrintCustomPackageCanvasOverlay` · `PrintLayoutTemplateControls` · `PrintLayoutTemplateStore` ·
`PrintPackageArtifactLayout` · `PrintPackageCaptionFormatter` · `PrintSettingsHistory` ·
`PrintWorkspaceSidebar` · `RenderManifestArtifactInspector` — 전부 없음.

### 2.5 내보내기

배치 4파일 · 체크포인트 2파일 · 커밋 저널 3파일 · 트랜잭션/쓰기 3파일 · 검증등급 ·
Reveal · 가용성 스토어 · 소스 실체화 · 추적 이벤트 · UI 7파일 — 전부 없음.

---

## 3. 썸네일

| | macOS | Windows |
|---|---|---|
| 크기 | `thumbnailMaxDimension = 360` | `ThumbnailService.MaximumDimension = 360` OK |
| 언제 만드나 | 정착 패스마다 현상 결과로 덮어씀. 인터랙티브는 건너뜀 | 정착에서만 `RememberDeveloped`/`Publish` |
| 네거티브 최초 | 빠른 포지티브 썸네일 → 정착 결과로 교체 | 대응 없음 |
| 인화 뷰에서 | 현상본 우선 | **2026-08-19.** 현상본 먼저. 칸이 크면 `PrintPreviewResolution` |

---

## 4. 창작 (macOS 에 없는데 Windows 가 지어낸 것)

| 항목 | 상태 |
|---|---|
| `DefectOverlayImage` 의 `Opacity="0.75"` | **제거함(2026-08-18).** macOS 는 불투명도를 색마다 넣음 |
| 하단바 `ABI 0.48 · X64` | 제거함(`f5d9a5b`) |
| GrainMend 캡슐 `CornerRadius="999"` | 수정함(`f5d9a5b`, 18/15) |
| `muted_scene_vibrance_table.cpp` 9,003줄 | **창작 아님.** macOS `CIFilter("CIVibrance")` 는 Apple 비공개 커널이라 33³ LUT 로 측정 이식. golden 해시 문서 있음 |

---

## 5. 아직 원인을 못 잡은 것 (정직하게)

1. 스캐너 DPI/심도/프레임규격 종료 — **A2 고침.** 플러그인 로딩 실패는 로그 필요
2. 필름 프로필·룩이 안 먹는 정확한 이유 — 슬라이더 고친 뒤 앱 재확인 안 함
3. 복제 도장 칩 → 캔버스 바 — 클릭 미도달인지 비활성인지 미확정
4. A4 `0xc0000409` 가 패치 들어간 `run-app` Develop 클릭에서 사라졌는지 — 코드는 있음, 그 클릭은 약함

---

## 6. 2026-08-20 갱신

| # | 무엇 | 상태 |
|---|---|---|
| 18 | **다국어가 설정에서 안 바뀜** | **고침.** 원인 셋(정적 `ResourceLoader` · 다시 칠할 길 없음 · `x:Uid` 는 한 번만 풀림). macOS 표 전수 대조 2,670건 중 다른 것 0 — [`18`](18-localization.md) |
| 19 | **폴더별 현상 프로세스·타깃·적용** | **붙음.** [`07`](07-user-reported.md) F.1.1. 앱 실측은 아직 |
| 20 | **자동 색상/레벨/톤/화이트 밸런스 알약 모양·클릭·글자** | **고침.** WinUI 기본 `ToggleButton` 판형이 원인 — [`07`](07-user-reported.md) J1 |
| 21 | **자동 레벨을 여러 번 누르면 앱 강제 종료** | **고침.** `develop_export.cpp` 소멸 순서 — [`07`](07-user-reported.md) J2 |
| 22 | **PowerShell 스크립트 문자열이 전부 깨짐** | **고침.** Windows PowerShell 5.1 은 BOM 없는 파일을 ANSI(cp949)로 읽습니다. 한글이 든 `.ps1` 6개에 UTF-8 BOM — [`11`](11-ui-verification-protocol.md) 4절 |

| 23 | **현상 좌측탭 프로세스·타깃이 화면에만 있고 안 붙음** | **고침.** `DevelopDefaultsChanged` 를 아무도 듣지 않았다 — [`07`](07-user-reported.md) K2 |
| 24 | **앱이 아예 안 뜸(XamlParseException)** | **고침.** resw 새 항목 20개가 다른 `<data>` 안에 들어가 MakePri 가 통째로 무시했다 — [`07`](07-user-reported.md) K1 |
| 25 | **타깃을 잇달아 바꾸면 앱 강제 종료** | **고침.** 상주 프레임이 사라진 버퍼를 가리켰다 — [`07`](07-user-reported.md) J2.1 |
| 26 | **`native.gpu_film_scan` 이 가끔 SegFault** | **원인 확정·닫음.** GPU 가 아니라 `row_block_pool` 의 완료 통지였다(호출부 스택의 계수기를 워커가 늦게 만짐). 27회 중 3회 → **292회 연속 통과** — [`01`](01-backend-gaps.md) 9.4 |

기준선(2026-08-20 x64-release, 마지막 게이트): native **102/102** · catalog **747** ·
shell **1411** · 경고 0.
