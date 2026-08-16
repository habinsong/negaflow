# REQUEST-5 golden — Windows에서 재현한 범위

기준일: 2026-08-16

## 실행한 항목

macOS에서 확정해 저장소에 올린 `docs/verification/macos-golden/REQUEST-5.md`와 golden
자산을 Windows x64 Debug에서 직접 사용했다. macOS 앱을 Windows에서 빌드하거나 실행하지는
않았다.

| 요청 항목 | Windows 결과 | 근거 |
| --- | --- | --- |
| 1. scanner target | 부분 | GT-X900 원본 TIFF가 저장소에 없어 실제 재렌더는 못 했다. HS/SP 어깨 끝점은 일반 보간으로 고쳤고 `native.scanner_target_grade`를 실행했다. |
| 6. metadata policy | 실제 source 정책 회귀 | macOS `policy-all.tif`를 source로 네 Windows TIFF를 다시 만들고 root IFD의 Artist/Copyright·EXIF·IPTC·GPS 보존/제거를 `native.task6_metadata_golden`에서 확인했다. IPTC IIM/XMP 바이트열과 파일별 태그 순서의 동일성은 주장하지 않는다. |
| 7. Core Image filters | 경계 포함 회귀 상한 | clarity 양수 3·음수 2(반경 7·10), 출력 선명화 3 RGBAf fixture를 `native.texture_stage`에 연결했다. 최악 절대 차이는 0.008 이하이다. 반경 1.0·1.3·2.4 단독 blur는 현재 공개 stage 출력과 1:1 비교하지 않는다. |
| 8. Digital Film Look | 회귀 상한 | Portra 400, Velvia 50, Tri-X 400 각 0.5/1.0의 RGBAf 6장을 `native.working_film_look`에 연결했다. 관측 최댓값은 0.004713 미만이며 검증 상한은 0.005이다. |
| 9. 실입력 B&W/슬라이드 | 중앙값 회귀 범위 통과 | 15개 1768×2906 RGB16 TIFF를 실제 ABI v32 export로 다시 만들고 WIC로 golden과 비교했다. color-positive는 32, B&W는 64 RGB16 코드의 채널 중앙값 한계를 자동 검증한다. |
| CIVibrance | 전 slider 범위 회귀 | 33³ 표의 음수/양수 plane을 사용해 macOS f32 17장을 `native.color_model`에서 확인했다. |

## Task 9 수치

색상 양화 8개는 RGB16 채널 중앙값 차이가 -7부터 +19 코드였고, 테스트는 절대값 32 코드
이하를 요구한다. 기본 sRGB는 최대 절대 차이도 채널당 1 코드였다. scanner-profile/타겟
경로에는 국소 최대 차이(최대 1,561 코드)가 남아 있으므로 중앙값 통과를 pixel-exact 동등성으로
해석하지 않는다.

B&W 음화 7개는 Windows 자동 base가 중립 fallback을 측정값처럼 취급해 크로모제닉 재시도를
건너뛰던 제어 흐름을 고쳤습니다. 기본 case에서 Windows Dmin은
`(0.143874, 0.296173, 0.432927)`로, macOS manifest의 `(0.144379, 0.296712, 0.433473)`에
수렴합니다. 7개 중앙값 차이는 0부터 −56 RGB16 코드이며 B&W 회귀 한계는 64 코드입니다.
Noritsu case의 국소 최대 차이 1,093 코드는 남으므로 이 통과를 pixel-exact 동등성으로
해석하지 않습니다.

## 실행 명령

```powershell
cmake --preset x64-debug
cmake --build --preset x64-debug --target negaflow_task6_metadata_golden_tests negaflow_texture_stage_tests negaflow_color_model_tests negaflow_scanner_profile_grade_tests negaflow_working_film_look_tests negaflow_task9_bw_slide_golden_tests negaflow_wic_tiff_export_tests negaflow_manual_negative_developer_tests
ctest --preset x64-debug -R '^(native\.task6_metadata_golden|native\.texture_stage|native\.color_model|native\.scanner_profile_grade|native\.working_film_look|native\.wic_tiff_export|native\.manual_negative_developer)$' --output-on-failure
ctest --preset x64-debug -R '^native\.task9_bw_slide_golden$' --output-on-failure
ctest --preset x64-debug -R '^(native\.working_to_srgb16|native\.wic_png_export|native\.wic_tiff_export|native\.scanner_to_working|native\.scanner_target_grade|native\.develop_export_abi)$' --output-on-failure
./scripts/test-managed.ps1 -Preset x64-debug
./scripts/ci-gate.ps1 -Preset x64-release
```

새 Task6/Texture/auto-base CTest는 3/3 통과했다. Task 9는 1/1, 기존 출력 경로 CTest는 6/6
통과했다. Debug Task 9 전체 재검증은 대형 TIFF 15개를 다시 써서 121.46초가 걸렸다.
최종 x64 Release gate는 native 71/71, Catalog 721 assertion, Shell 905 assertion을 모두
통과했다.

## 남은 경계

- GT-X900 Task 1 원본이 저장소에 들어오면 동일 Windows ABI 경로에서 실제 출력 비교를 추가한다.
- B&W Task 9의 중앙값 base 회귀는 닫혔지만, Noritsu의 국소 최대 차이 1,093 RGB16 코드는 남아 있다.
- 순수 ARM64 Windows 장비에서의 실행은 이 기록의 범위가 아니다.
