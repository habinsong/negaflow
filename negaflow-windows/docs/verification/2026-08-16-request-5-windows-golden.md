# REQUEST-5 golden — Windows에서 재현한 범위

기준일: 2026-08-16

## 실행한 항목

macOS에서 확정해 저장소에 올린 `docs/verification/macos-golden/REQUEST-5.md`와 golden
자산을 Windows x64 Debug에서 직접 사용했다. macOS 앱을 Windows에서 빌드하거나 실행하지는
않았다.

| 요청 항목 | Windows 결과 | 근거 |
| --- | --- | --- |
| 1. scanner target | 부분 | GT-X900 원본 TIFF가 저장소에 없어 실제 재렌더는 못 했다. HS/SP 어깨 끝점은 일반 보간으로 고쳤고 `native.scanner_target_grade`를 실행했다. |
| 6. metadata policy | 정책 구성 확인 | WIC TIFF 왕복과 `native.wic_tiff_export`에서 TIFF·EXIF·IPTC·GPS의 네 정책 구성을 확인했다. macOS `tiff-tags.json`의 IPTC IIM/XMP 바이트열과 파일별 태그 순서가 같다는 주장은 하지 않는다. |
| 7. Core Image filters | 경계 포함 회귀 상한 | Task 7의 RGBAf fixture 10개를 `native.texture_stage`에 연결했다. 최악 절대 차이는 0.008 이하이다. CIUnsharpMask의 문서화되지 않은 경계 표본 방식 때문에 pixel-exact 판정은 아니다. |
| 8. Digital Film Look | 회귀 상한 | Portra 400, Velvia 50, Tri-X 400 각 0.5/1.0의 RGBAf 6장을 `native.working_film_look`에 연결했다. 관측 최댓값은 0.004713 미만이며 검증 상한은 0.005이다. |
| 9. 실입력 B&W/슬라이드 | 양화는 중앙값 범위 통과, B&W는 열림 | 15개 1768×2906 RGB16 TIFF를 실제 ABI v32 export로 다시 만들고 WIC로 golden과 비교했다. |
| CIVibrance | 전 slider 범위 회귀 | 33³ 표의 음수/양수 plane을 사용해 macOS f32 17장을 `native.color_model`에서 확인했다. |

## Task 9 수치

색상 양화 8개는 RGB16 채널 중앙값 차이가 -7부터 +19 코드였고, 테스트는 절대값 32 코드
이하를 요구한다. 기본 sRGB는 최대 절대 차이도 채널당 1 코드였다. scanner-profile/타겟
경로에는 국소 최대 차이(최대 1,561 코드)가 남아 있으므로 중앙값 통과를 pixel-exact 동등성으로
해석하지 않는다.

B&W 음화 7개는 모두 Windows가 더 밝았다. 중앙값 차이는 +1,089부터 +1,909 RGB16 코드,
최대 절대 차이는 24,520부터 33,217 코드였다. 단일 B&W case의 진단은 Windows 자동 base가
중립 폴백 `(0.8, 0.8, 0.8)`, scene Dmax가 `(1.8, 1.8, 1.8)`임을 보인다. 이 수치는 macOS
소스의 fallback/scene-range 수식과 같은 경로이지만, golden 출력만으로 특정 사진에 맞춘
보정을 넣을 근거는 없다. 따라서 B&W 수치 기준은 아직 pass 조건으로 고정하지 않았다.

## 실행 명령

```powershell
cmake --build --preset x64-debug --target negaflow_texture_stage_tests negaflow_color_model_tests negaflow_scanner_profile_grade_tests negaflow_working_film_look_tests negaflow_task9_bw_slide_golden_tests negaflow_wic_tiff_export_tests
ctest --preset x64-debug -R '^(native\.texture_stage|native\.color_model|native\.scanner_profile_grade|native\.working_film_look|native\.wic_tiff_export)$' --output-on-failure
ctest --preset x64-debug -R '^native\.task9_bw_slide_golden$' --output-on-failure
ctest --preset x64-debug -R '^(native\.working_to_srgb16|native\.wic_png_export|native\.wic_tiff_export|native\.scanner_to_working|native\.scanner_target_grade|native\.develop_export_abi)$' --output-on-failure
./scripts/test-managed.ps1 -Preset x64-debug
```

첫 CTest는 5/5, Task 9는 1/1, 출력 경로 CTest는 6/6 통과했다. 관리 테스트는 Catalog 721,
Shell 905 assertion이 모두 통과했다. Task 9는 대형 TIFF 15개를 다시 써서 132.85초가 걸렸다.

## 남은 경계

- GT-X900 Task 1 원본이 저장소에 들어오면 동일 Windows ABI 경로에서 실제 출력 비교를 추가한다.
- B&W Task 9는 base/proxy의 macOS 진단값 또는 그 이전 중간 golden 없이는 일반적인 원인을 더 좁힐 수 없다.
- 순수 ARM64 Windows 장비에서의 실행은 이 기록의 범위가 아니다.
