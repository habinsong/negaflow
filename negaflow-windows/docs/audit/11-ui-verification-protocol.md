> # ☠️ 하드코딩 · 가짜 구현 · 창작 · 병신 백엔드 · 병신 프론트엔드 = 죽음 ☠️
>
> **🔬 추측·가설 금지.** 재현하고 스택을 잡고 계측해서 **원인을 확정**한 뒤 고칩니다.
> **🌐 모르면 웹 검색을 적극적으로** 하십시오 — WinUI 3 속성 하나를 몰라서
> 슬라이더가 정수로 스냅됐습니다(`Slider.StepFrequency` 기본값 **1**).
>
> **저장소**: 본체 `C:\Users\habin\negaflow\`(Apache 2.0) · 스캐너 `C:\Users\habin\negaflow-scanner-sane\`(GPL).
> **두 저장소의 `negaflow-mac\` 은 절대 고치지 마십시오.** ([`12`](12-repos-and-licence.md))

---

> # ⛔⛔⛔ 창작 금지 · 가짜 UI 금지 ⛔⛔⛔
>
> # **눈으로 보지 않은 UI 는 "됐다" 고 적지 마십시오.**
>
> # 프론트엔드는 **반드시** 이 세 가지를 다 하고 나서 판정합니다
>
> | # | 무엇 | 어떻게 |
> |---|---|---|
> | **1** | **Windows 앱을 computer-use 로 직접 본다** | 화면을 띄우고 **구역별로 크롭**해서 확대해 본다 |
> | **2** | **Parsec 으로 macOS negaflow 를 직접 본다** | 같은 화면을 열고 **같은 구역을 크롭**해서 나란히 댄다 |
> | **3** | **스크린샷 폴더 84장을 확인한다** | `negaflow_mac_screenshot/` — 라이브러리 43 · 현상 24 · 인화 17 |
>
> ## 일곱 가지를 전부 맞춥니다
>
> # **모양 · 크기 · 위치 · 정렬 · 색상 · 내용 · 텍스트 안 잘림**
>
> - **모양** — 모서리 반경, 테두리, 아이콘 그림 자체
> - **크기** — 폭·높이·패딩·간격을 **수치로**
> - **위치** — 무엇의 왼쪽/오른쪽/위/아래, 몇 px 떨어져 있는지
> - **정렬** — 가운데/왼쪽/오른쪽, 세로 가운데 맞춤
> - **색상** — 배경·글자·선택 표시·비활성
> - **내용** — 요소 개수와 **순서**. 하나라도 빠지면 안 됨
> - **텍스트 안 잘림** — 잘리거나 `…` 로 줄면 **틀린 것**
>
> ## 하지 말 것
>
> - **"비슷하다" 로 넘기기 금지.** 크롭해서 겹쳐 보십시오.
> - **XAML 에 요소가 있다고 "있음" 으로 적기 금지.** 화면에 **보여야** 있는 것입니다.
> - **백엔드 없는 껍데기 UI 금지.** 눌러서 값이 바뀌지 않으면 그것은 **가짜**입니다.
> - **Segoe 글리프로 대충 때우기 금지.** SF Symbols 와 그림이 다르면 SVG 로 그리십시오.
>
> ## 왜
>
> **가짜 UI 와 창작 때문에 이 이식은 이미 30회 넘게 되돌렸습니다.**
> 사용자가 앱을 열 때마다 새 가짜가 나옵니다 — 타깃 선택 불가, 슬라이더 정수 스냅,
> 값 입력 불가, 비교 캡슐 없음, 줌 HUD 없음, 초기화 없음, IR 단추 없음,
> 메뉴막대 11개 전무, 아이콘 절반, 오탈자, 저해상도 썸네일 확대.
>
> **전부 "코드에 있으니 됐다" 고 판정한 것들입니다.**

---

# 11 — 프론트엔드 검증 절차

---

## 1. 세 가지 근거를 **다** 씁니다

### 1.1 Windows 앱 — computer-use

```
1. 앱을 띄운다        scripts\run-app.ps1 -Architecture x64 -Configuration Release
2. request_access     negaflow.shell.exe  ← 창을 소유한 프로세스 이름
3. screenshot         전체 화면
4. zoom               구역별로 크롭해서 확대   ← 여기서 판정
```

**`zoom` 없이 전체 스크린샷만 보고 판정하지 마십시오.** 1456×819 로 줄어든 그림에서는
2px 차이도, 잘린 글자도, 정렬 어긋남도 보이지 않습니다.

### 1.2 macOS negaflow — Parsec

**같은 화면을 macOS 에서 열고 같은 구역을 크롭합니다.** 스크린샷 폴더에 없는 상태
(호버, 드래그 중, 메뉴 열림, 비활성, 오류 표시)는 **Parsec 으로만 확인할 수 있습니다.**

### 1.3 스크린샷 폴더 — `negaflow_mac_screenshot/` **84장**

| 뷰 | 장수 | 파일 |
|---|---:|---|
| **라이브러리** | **43** | `library_overview_grid_100_percent` · `library_browse_list_mode` · `library_card_size_92_percent` · `library_photo_selected` · `library_files_source` · `library_collections_source` · `library_filter_menu` · `library_filter_menu_all_options` · `library_filter_current_roll_on` · `library_filter_selected_on` · `library_filter_rating_four_plus` · `library_filters_cleared` · `library_rating_filter_cleared` · `library_film_type_bw_negative_filter` · `library_film_type_color_negative_restored` · `library_sort_by_name` · `library_sort_by_time` · `library_sort_by_name_restored` · `library_search_photo_one` · `library_search_cleared` · `library_duplicate_candidates`(+`_closed`) · `library_import_methods` · `library_import_image_dialog`(+`_cancelled`) · `library_import_folder_dialog`(+`_cancelled`) · `library_import_scanner` · `library_import_tab_after_scanner` · `library_after_image_dialog_cancel` · `library_all_photos_view_restored` · **스캐너 12장** (`library_scanner_*`) |
| **현상** | **24** | `develop_overview` · **좌측탭 5** (`develop_left_files/film/output/presets/versions_tab`) · **우측탭 5** (`develop_right_base/edit/grainmend/info_panel`, `develop_right_basic_restored`) · **기본 2** (`develop_basic_color_expanded`, `develop_basic_tone_curve_expanded`) · **편집 9** (`develop_edit_crop_enabled` · `_rotate_left` · `_horizontal_flip` · `_vertical_flip` · `_flips_restored` · `_rotation_restored` · `_dodge_tool_restored` · `_burn_tool` · `_final_restored`) · **출력 2** (`develop_output_quality_tab`, `develop_output_source_tab`) |
| **인화** | **17** | `print_overview` · `print_left_output_tab` · `print_right_content_panel` · `print_right_output_panel` · `print_output_general_mode` · `print_output_advanced_panel` · `print_output_cprint_restored` · `print_layout_contact_sheet` · `print_layout_gelatin_final`(+`_restored`) · `print_layout_options_restored` · `print_portrait_orientation` · `print_landscape_orientation_restored` · `print_sheet_gray` · `print_ruler_off` · `print_zoom_in` · `print_filmstrip_card_size_up` |

**폴더에 없는 것**: 설정 화면 · 스캐너 시뮬레이터 진행 화면 · 캔버스 HUD(검토 캡슐·브러시 바·
복제 바·비교 캡슐·줌) · 메뉴막대. **이것들은 Parsec 으로 직접 확인해야 합니다.**

---

## 2. 구역별 크롭 목록 — 이 순서로 확인합니다

### 2.1 라이브러리 뷰

| # | 구역 | 기준 스크린샷 |
|---|---|---|
| 1 | 상단 바 — 별점 5 · 플래그 · 거부 · `프리뷰 스캔` · `사진 스캔` · 중앙 **사진 번호** · 뷰 전환 | `library_overview_grid_100_percent` |
| 2 | 좌측 세로 레일 — 아이콘 그림·선택 표시·탭 개수 | `library_files_source` · `library_collections_source` |
| 3 | 좌측 패널 — 폴더 트리 · **폴더별 현상(프로세스·타깃·적용)** | `library_files_source` |
| 4 | 하단 필터 캡슐 — **순서**·간격·모서리·글자 잘림 | `library_filter_menu_all_options` · `library_filters_cleared` |
| 5 | 정렬 — 기준 목록 + **오름/내림 토글** | `library_sort_by_name` · `library_sort_by_time` |
| 6 | 카드 크기 슬라이더 · 그리드/목록 전환 | `library_card_size_92_percent` · `library_browse_list_mode` |
| 7 | 스캐너 패널 — 장치·필름·해상도·색모드·심도·프레임 규격 | `library_scanner_*` **12장** |
| 8 | 썸네일 카드 — 별점·플래그·스택 배지·파일명 | `library_photo_selected` |

### 2.2 현상 뷰

| # | 구역 | 기준 스크린샷 |
|---|---|---|
| 1 | 상단 바 | `develop_overview` |
| 2 | 좌측탭 5개 — 파일·필름·출력·프리셋·버전 | `develop_left_*_tab` **5장** |
| 3 | 우측탭 — 베이스·편집·GrainMend·정보·기본 | `develop_right_*_panel` **5장** |
| 4 | 기본 톤 섹션 펼침 | `develop_basic_color_expanded` |
| 5 | 톤 곡선 펼침 — 점 편집기 + 네 축 슬라이더 | `develop_basic_tone_curve_expanded` |
| 6 | 편집(기하) — 회전 2 · **좌우/상하 뒤집기 2** · 각도 다이얼 · 크롭 | `develop_edit_*` **9장** |
| 7 | 닷지/번 도구 | `develop_edit_dodge_tool_restored` · `develop_edit_burn_tool` |
| 8 | 출력 탭 — 품질·소스 | `develop_output_quality_tab` · `develop_output_source_tab` |
| 9 | **캔버스 HUD** — 비교 캡슐·줌·검토 캡슐·브러시 바·복제 바 | **폴더에 없음 → Parsec** |
| 10 | **캔버스 우클릭** — 배경 검정/회색/흰색 | **폴더에 없음 → Parsec** |

### 2.3 인화 뷰

| # | 구역 | 기준 스크린샷 |
|---|---|---|
| 1 | 전체 배치 | `print_overview` |
| 2 | 좌측탭 — 출력 | `print_left_output_tab` |
| 3 | 우측탭 — 내용 · 출력 | `print_right_content_panel` · `print_right_output_panel` |
| 4 | 출력 모드 — 일반 · 고급 · C프린트 | `print_output_*` **3장** |
| 5 | 레이아웃 — 콘택트 시트 · 젤라틴 · 옵션 | `print_layout_*` **4장** |
| 6 | 방향 — 세로/가로 | `print_portrait_orientation` · `print_landscape_orientation_restored` |
| 7 | 시트 배경 · 눈금자 · 줌 | `print_sheet_gray` · `print_ruler_off` · `print_zoom_in` |
| 8 | 하단 필름스트립 카드 크기 | `print_filmstrip_card_size_up` |
| 9 | **중앙 프리뷰 화질** — **E4 현상본.** 줌 HUD·패키지 셀 업그레이드 앱 실측은 남음 | `print_overview` ([`07`](07-user-reported.md) E4) |

---

## 3. 판정표 — 구역 하나마다 이렇게 적습니다

```
구역: 라이브러리 하단 필터 캡슐
기준: negaflow_mac_screenshot/library_filter_menu_all_options.png  +  Parsec 실화면
Windows: computer-use zoom [x0,y0,x1,y1]

  모양   ☐ 맞음  ☒ 다름 — 모서리 13 vs macOS ○○
  크기   ☐ 맞음  ☒ 다름 — 높이 26 vs ○○
  위치   ☐ 맞음  ☒ 다름 — 뷰모드 바와 분리돼 다른 줄에 있음
  정렬   ☐ 맞음  ☒ 다름
  색상   ☐ 맞음  ☐ 다름
  내용   ☐ 맞음  ☒ 다름 — 순서가 macOS 와 다름
  잘림   ☒ 잘림 — 글자가 잘려 보임

판정: 다름 (7개 중 5개 불일치)
```

**7개 중 하나라도 "다름" 이면 그 구역은 "다름" 입니다. "대체로 맞음" 은 없습니다.**

---

## 4. 백엔드 연결 확인 — 눌러 보십시오

**보이는 것만으로는 부족합니다.** 구역마다 이것도 확인합니다.

| 확인 | 통과 조건 |
|---|---|
| 눌러서 값이 바뀌는가 | 화면 표시가 실제로 변함 |
| 그 값이 사진에 반영되는가 | 프리뷰가 바뀜 |
| 저장되는가 | 사진을 바꿨다 돌아와도 유지 |
| 비활성 조건이 macOS 와 같은가 | 같은 상황에서 같이 꺼짐 |

**하나라도 안 되면 그 UI 는 가짜입니다.** 문서에 "가짜" 로 적고, 고칠 때까지
**비활성으로 두십시오** — 되는 것처럼 보이게 두지 마십시오.

---

## 5. 이 절차를 안 지켜서 놓친 것들 (실제 사례)

| 무엇 | 코드에는 | 화면에는 |
|---|---|---|
| 우측 슬라이더 | `SmallChange="0.01"` 있음 | `StepFrequency` 없어 **정수로만 움직임** |
| 슬라이더 값 입력 | `TextBox` + `KeyDown` 있음 | **포커스가 안 가서 입력 불가** |
| 좌우 뒤집기 | `FlipHorizontalButton` 있음 | **사용자는 안 보인다고 함** |
| 현상 타깃 | `DevelopTargets.Visible` 있음 | **현상 뷰에 설정 경로 없음** |
| 인화 프리뷰 | 렌더러 있음 | **E4 현상본.** 단일 이미지 앱 확인. 패키지·줌은 남음 |
| GrainMend IR | 엔진 1,570줄 있음 | **단추가 없음** |
| 폴더별 현상 | 프로세스·타깃 있음 | **적용 단추가 없음** |

**전부 "코드에 있으니 됐다" 로 판정했다가 사용자가 앱을 열어서 잡은 것입니다.**
