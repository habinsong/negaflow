# 04 — 라이브러리 / 현상 / 인화 세 뷰 전체 1:1

요구: **좌측 세로 레일, 좌측 패널, 상단, 중앙, 하단, 우측 인스펙터 전부.** 기능 하나
빼먹지 말 것. 정렬 옵션, 세부 프레임, 뷰 전부. 디자인·위치·크기·모양·정렬까지.

## 0. 원본 규모

| macOS 폴더 | 파일 수 |
|---|---:|
| `Features/Library` | 101 |
| `Features/Develop` | 67 |
| `Features/Print` | 17 |
| `Features/Canvas` | 22 |
| `Features/Workspace` | 9 |
| **합계** | **216** |

**한 번에 끝낼 수 있는 크기가 아닙니다.** 아래 대조표를 채우는 것이 먼저이고, 표가 채워진
뒤에 항목 단위로 작업합니다.

## 1. 방법 — 대조표를 먼저 만든다

각 표면마다 이 셋을 나란히 놓습니다.

1. **macOS Swift 파일** — 무엇이 있고 무엇을 하는가
2. **macOS 스크린샷** — 크기·색·위치·정렬
3. **Windows 현재** — 있는가 / 모양이 같은가 / 기능이 도는가

판정은 넷 중 하나: `같음` / `모양 다름` / `기능 없음` / `표면 자체 없음`.

**"있음" 으로 적지 마십시오.** 이번 세션에 검출기가 "오케스트레이션은 있음" 으로 적혀
있었지만 실제로는 다른 경로를 쓰고 있었습니다.

## 2. 스크린샷 목록 (`negaflow_mac_screenshot/`, 1343×768)

### 라이브러리 (28장)
`library_overview_grid_100_percent` · `library_all_photos_view_restored` ·
`library_browse_list_mode` · `library_card_size_92_percent` · `library_collections_source` ·
`library_files_source` · `library_photo_selected` · `library_compare*` ·
`library_duplicate_candidates(_closed)` · `library_filter_menu(_all_options)` ·
`library_filters_cleared` · `library_filter_current_roll_on` ·
`library_film_type_bw_negative_filter` · `library_film_type_color_negative_restored` ·
`library_rating_filter_cleared` · `library_search_photo_one` · `library_search_cleared` ·
`library_sort_by_name(_restored)` · `library_sort_by_time` · `library_import_*` (6장) ·
`library_scanner_*` (10장) · `library_after_image_dialog_cancel`

### 현상 (18장)
`develop_overview` · `develop_left_files_tab` · `develop_left_film_tab` ·
`develop_left_output_tab` · `develop_left_presets_tab` · `develop_left_versions_tab` ·
`develop_right_base_panel` · `develop_right_basic_restored` · `develop_right_edit_panel` ·
`develop_right_grainmend_panel` · `develop_right_info_panel` ·
`develop_basic_color_expanded` · `develop_basic_tone_curve_expanded` ·
`develop_edit_crop_enabled` · `develop_edit_rotate_left` · `develop_edit_horizontal_flip` ·
`develop_edit_vertical_flip` · `develop_edit_dodge_tool_restored` ·
`develop_edit_burn_tool` · `develop_edit_*_restored` · `develop_output_quality_tab` ·
`develop_output_source_tab`

### 인화 (16장)
`print_overview` · `print_left_output_tab` · `print_right_content_panel` ·
`print_right_output_panel` · `print_layout_contact_sheet` · `print_layout_gelatin_*` ·
`print_layout_options_restored` · `print_output_advanced_panel` ·
`print_output_cprint_restored` · `print_output_general_mode` ·
`print_portrait_orientation` · `print_landscape_orientation_restored` ·
`print_sheet_gray` · `print_ruler_off` · `print_zoom_in` · `print_filmstrip_card_size_up`

**스크린샷 확대 방법** (레일처럼 작은 부분을 볼 때):

```powershell
Add-Type -AssemblyName System.Drawing
$bmp  = [System.Drawing.Bitmap]::FromFile("<png>")
$crop = $bmp.Clone((New-Object System.Drawing.Rectangle 0,0,120,$bmp.Height), $bmp.PixelFormat)
$out  = New-Object System.Drawing.Bitmap 360, ($bmp.Height*3)
$g = [System.Drawing.Graphics]::FromImage($out); $g.InterpolationMode='NearestNeighbor'
$g.DrawImage($crop, 0, 0, 360, $bmp.Height*3); $g.Dispose(); $out.Save("<out.png>")
```

## 3. 좌측 세로 레일 — 첫 작업

macOS `Features/Workspace/WorkflowSidebar.swift`.

`develop_overview.png` 를 확대해 확인한 macOS 현상 뷰 레일(위→아래 6개):

| # | 아이콘 | 비고 |
|---|---|---|
| 1 | 가방/서류가방 형태 | **선택 상태(파란 라운드 배경)** |
| 2 | 폴더 외곽선 | |
| 3 | 시계 + 반시계 화살표 (히스토리) | |
| 4 | 패널/레이아웃(사각형 둘) | |
| 5 | 원 안에 점 | |
| 6 | 위로 향한 화살표 + 받침 (내보내기) | |

Windows 현재 현상 뷰 레일(같은 자리): 목록형 아이콘(선택) · 폴더 · 시계 · 슬라이더형 ·
카메라 · 격자.

**1·4·5·6 이 다릅니다.** 그리고 Windows 는 사진이 없을 때 레일이 3개로 줄어듭니다 —
macOS 가 그렇게 하는지 확인해야 합니다.

작업:
1. `WorkflowSidebar.swift` 에서 탭 **정의 목록**(개수·순서·아이콘·툴팁·활성 조건)을 뽑는다
2. 세 뷰(라이브러리/현상/인화)가 각각 어떤 목록을 쓰는지 확인한다
3. SF Symbol → Segoe Fluent 대응표를 `docs/implementation/` 에 만든다
   (이미 있는 대응: `scope`→E7A8, `bandage`→E90F, `slider.horizontal.3`→E9E9,
   `eye`→E7B3, `eye.slash`→ED1A, `trash`→E74D, `rectangle.dashed`→E7C4)
4. 선택 상태 표시(파란 라운드 배경)를 macOS 와 같은 크기·반경·색으로

## 4. 표면별 대조표 (채워야 함)

### 4.1 상단 바 — `Workspace/Toolbar/WorkspaceToolbar.swift`, `WorkspaceToolbarButtons.swift`, `RollToolbarStrip.swift`

| 항목 | macOS | Windows | 판정 |
|---|---|---|---|
| 좌측 빠른 내보내기 / 내보내기 | | | |
| 중앙 제목(파일명·선택 수) | | | |
| 별점 · 플래그 · 거부 | | | |
| 우측 뷰 전환(라이브러리/현상/인화) | | | |
| 패널 표시 토글 3종 | | | |
| 외관(밝게/어둡게) | | | |
| 더보기(…) | | | |

### 4.2 라이브러리 좌측 패널 — `Library/Views/SidebarViews.swift`, `LibrarySourceSection.swift`, `LibraryOrganizerSection.swift`, `LibraryFolderTreeView.swift`

| 항목 | macOS | Windows | 판정 |
|---|---|---|---|
| 가져오기(이미지/폴더/스캐너) | | | |
| 폴더 트리 + 펼침 상태 저장 | | `LibraryFolderExpansionStore` 대응 | |
| 컬렉션/조직자 | | | |
| 롤 | | | |
| 소스 드래그앤드롭 | `LibrarySourceDragAndDrop.swift` | | |
| 현상 기본값(프로세스/타깃/필름 프로필/롤) | | | |

### 4.3 라이브러리 중앙 — `Library/Views/Workspace/LibraryWorkspaceView+Grid.swift`, `LibraryBrowserHeader.swift`, `LibraryBrowserFilterBar.swift`

| 항목 | macOS | Windows | 판정 |
|---|---|---|---|
| **정렬 옵션** (이름/시간/입력순 …) | `LibraryPresentation.swift` | | **사용자가 "대충 만들었다"고 지적** |
| 필터 메뉴(전체 옵션) | `library_filter_menu_all_options.png` | | |
| 빠른 필터(현재 롤·필름 종류·별점·오프라인) | `LibraryQuickFilterState.swift` | | |
| 검색 | | | |
| 그리드 / 목록 모드 | `library_browse_list_mode.png` | | |
| 카드 크기 슬라이더(%) | `FilmstripSizing.swift` | | |
| 스택 배지 · 스택 메뉴 | `LibraryStackBadge/Menu.swift` | | |
| 중복 후보 시트 | `Duplicates/*.swift` (4개) | | |
| 컬링 모드 | `LibraryCullingModePicker.swift` | | |
| 비교 뷰 | `LibraryCompareView.swift` | | |
| 서베이 뷰 | `LibrarySurveyView.swift` | | |
| 프레임 컨텍스트 메뉴 | `LibraryFrameContextMenu.swift` | | |
| 이름 바꾸기 시트 | `FrameRenameSheet.swift` | | |

### 4.4 하단 필름스트립 — `Library/Views/Filmstrip/WorkspaceFilmstrip.swift`, `FilmstripScope.swift`, `FrameStepButton.swift`

| 항목 | macOS | Windows | 판정 |
|---|---|---|---|
| 스코프(전체/폴더/롤) | | | |
| 카드 크기 | | | |
| 앞/뒤 이동 버튼 | | | |
| 가로 휠 브리지 | `HorizontalFilmstripWheelBridge.swift` | | |
| 높이 조절 | | | |

### 4.5 현상 좌측 패널 — 탭 5개

스크린샷: `develop_left_files_tab` / `_film_tab` / `_presets_tab` / `_versions_tab` /
`_output_tab`. Windows 대응은 `src/Shell/Views/Develop/Sources|Film|Presets|Versions|Export`.

### 4.6 현상 우측 인스펙터 — `Develop/Inspector/**` (67 파일)

| 탭 | macOS 파일 | Windows | 판정 |
|---|---|---|---|
| 기본(슬라이더) | `DevelopAdjustmentSections.swift` | | |
| 톤 곡선 | `ToneCurveEditor.swift`, `ToneCurvePointEditing.swift`, `ToneCurvePointFields.swift` | | |
| 색상 | `ColorMixerSection.swift` | | |
| 컬러 그레이딩 | `ColorGradingSection.swift` | | |
| 캘리브레이션 | `BaseControlSection.swift` | | |
| 필름 에뮬레이션 | `FilmEmulationSection.swift` | | |
| 흑백 토닝 | `BWToningSection.swift` | | |
| 히스토그램(상호작용) | `Histogram/InteractiveHistogramView.swift` | | |
| 기하(크롭·회전·수평보정) | `Tools/GeometryToolSection.swift`, `Tools/CropAngleDial.swift` | | |
| GrainMend | `Tools/DefectControlsSection.swift` | 03 문서 | |
| 초기화 | `Tools/ResetControlsSection.swift` | | |
| 프리셋 | `UserPresetSection.swift` | | |
| 설정 전송 | `DevelopSettingsTransferSection.swift` | | |
| 정보/메타데이터 | `SourceMetadataInspectorView.swift`, `AppMetadataOverlayEditor.swift`, `RollRecordEditor.swift`, `FilmShotMetadataFields.swift` | | |
| **슬라이더 공통 동작** | `Controls/InspectorSlider.swift`, `ResettableSlider.swift`, `EditableSliderValueText.swift`, `InspectorSliderFocus.swift`, `SliderValueFormatting.swift` | | **값 직접 입력·초점 이동·더블클릭 초기화까지 확인** |
| 키보드 이동 | `DevelopInspectorKeyboardController.swift`, `DevelopInspectorFocusNavigation.swift` | | |

### 4.7 캔버스 — `Features/Canvas/**` (22 파일)

| 항목 | macOS 파일 | Windows | 판정 |
|---|---|---|---|
| 뷰포트(줌·팬) | `CanvasViewportState.swift`, `CanvasScrollPanBridge.swift` | | |
| 비교(전/후 분할) | `CanvasCompareControls.swift`, `CanvasCompareDivider.swift`, `CanvasView+Comparison.swift` | | |
| 줌 HUD | `CanvasHUDLayer.swift`, `CanvasHUDPlacement.swift` | | |
| 도구 HUD | `CanvasToolHUD.swift` | | |
| 크롭 오버레이 | `CropOverlay.swift`, `CropOverlayGeometry.swift`, `CropAccessibilityEditing.swift` | | |
| 픽셀 샘플러 | `PixelSamplerReadoutView.swift`, `PixelSamplerStore.swift` | 있음 | |

### 4.8 인화 — `Features/Print/**` (17 파일)

| 항목 | macOS 파일 | Windows | 판정 |
|---|---|---|---|
| 좌측 사이드바 | `PrintWorkspaceSidebar.swift` | | |
| 캔버스 | `PrintCanvasView.swift`, `PrintPackageCanvasView.swift` | | |
| 커스텀 패키지 오버레이 | `PrintCustomPackageCanvasOverlay.swift` | | |
| 레이아웃 템플릿 | `PrintLayoutTemplateControls.swift`, `PrintLayoutTemplateStore.swift` | | |
| 우측 인스펙터 | `PrintWorkspaceInspector.swift`, `PrintInspectorControls.swift`, `PrintInspectorComponents.swift`, `PrintPackageInspectorControls.swift` | | |
| 내보내기 | `AppModel+PrintExport.swift`, `AppModel+PrintPackageExport.swift`, `PrintPackageExportWriter.swift` | | |
| 캡션 | `PrintPackageCaptionFormatter.swift` | | |
| 눈금자 | `print_ruler_off.png` | | |

## 5. 작업 순서

1. **좌측 세로 레일** — 세 뷰 모두. 가장 눈에 띄고 가장 작음(3절)
2. **라이브러리 중앙의 정렬·필터·뷰 모드** — 사용자가 직접 지적한 곳(4.3)
3. **현상 우측 인스펙터의 슬라이더 공통 동작** — 값 입력·초기화·키보드(4.6 마지막 줄)
4. **상단 바**(4.1)
5. **하단 필름스트립**(4.4)
6. **현상 좌측 탭 5개**(4.5)
7. **캔버스 비교·줌 HUD**(4.7)
8. **인화 전체**(4.8)
9. **라이브러리 나머지**(중복·컬링·비교·서베이·스택)

각 항목이 끝날 때마다 macOS 스크린샷과 Windows 스크린샷을 나란히 붙여 이 문서에 링크합니다.

## 6. God object 주의

`DevelopWorkspaceView.xaml.cs` 4,835줄 · `DevelopWorkspaceView.xaml` 2,508줄 ·
`LibraryWorkspaceView.xaml.cs` 2,835줄 · `LibraryWorkspaceView.xaml` 975줄 이 아직
500줄을 넘습니다. **이 작업으로 더 키우지 말고**, 표면을 하나 손댈 때마다 그 표면을
`UserControl` 로 뽑아내면서 줄이십시오. `DefectLayerSection` 을 그렇게 했고 God object 가
늘지 않았습니다.
