# 2026-08-04 Film Look source routing 검증

기준일: 2026-08-04
대상: `chromabase-working-film-look-v1`

## 검증 범위

`native.working_film_look`은 다음 계약을 실행합니다.

- 효과가 없는 film/digital source는 identity이며 유효한 pixel을 bit-exact로 보존
- 활성 film scan은 `film_scan_emulation`으로 선택
- 활성 rendered digital은 별도 `digital_film_look`으로 선택하고 현재 `unsupported_route`
- 알 수 없는 source enum과 비유한 intensity는 route 선택 전에 거부
- RGB33 색상 뒤 acutance를 수동으로 호출한 결과와 routed 결과의 12개 RGBA pixel bit-exact 일치
- Velvia 50, intensity 0.73에서 색상 step 15, acutance amount 0.1606, 4픽셀 폭 scratch 44개 보고
- 같은 profile/step의 caller-owned cube 재사용
- intensity 0.024에서 색상 step 0이지만 unquantized acutance 적용
- 잘못된 image layout, cube 누락, 작은 scratch와 non-finite pixel 실패 시 결과 pixel 폐기
- 작은 scratch는 cube build와 색상 pixel loop 전에 조기 거부

## 빌드·실행 결과

| 대상 | 결과 |
|---|---|
| x64 Debug 전체 build | 통과 |
| x64 Debug CTest | 33/33 통과 |
| x64 Release 전체 build | 통과 |
| x64 Release CTest | 33/33 통과 |
| ARM64 Debug 전체 target cross-build | 통과 |
| ARM64 Release 전체 target cross-build | 통과 |

네 구성 모두 새 `working_film_look.cpp`와 unit test를 기존 `/W4 /WX`, precise floating-point 정책으로
컴파일했습니다. ARM64 executable은 x64 호스트에서 실행하지 않았으므로 ARM64 runtime 수치 통과로
표시하지 않습니다.

Release PE header에서 새 unit test와 CLI는 x64 `8664`, ARM64 `AA64`였습니다. DLL export는 기존
`nf_get_abi_version`, `nf_get_build_info_v1` 두 개뿐이며, x64 CLI 직접 dependency는 Windows 기본
`bcrypt`, `SHLWAPI`, `ole32`, `mscms`, `KERNEL32` 다섯 개로 유지됩니다.

## 성능·메모리 경계

- matching color cube는 재사용하며 route 내부에 전역 cache가 없습니다.
- acutance scratch 요구량은 `width × 11` pixel이고 높이에 따라 늘지 않습니다.
- route는 별도 full-frame image를 만들지 않고 owned `WorkingImage`를 제자리 처리합니다.
- null/작은 workspace는 색상 pixel loop 전에 차단합니다.
- 이번 검증은 합성 4×3 fixture이며 megapixel wall/process-CPU benchmark는 아직 실행하지 않았습니다.

## 제품 경계

현재 CLI, C ABI, recipe persistence와 WinUI는 이 route를 호출하지 않습니다. 따라서 이 검증은 native
source 계약과 film-scan stage 순서 통과이며, 제품 Develop graph나 `DigitalFilmLook` 완료를 뜻하지
않습니다. 일반 이미지 content SHA-256은 계산하지 않았고 기본 `끔` 정책을 바꾸지 않았습니다.

이 절은 `0c7e8a1` native checkpoint 당시의 범위입니다. 후속 CLI·실제 출력 연결은
[Film Look CLI·실제 출력 검증](2026-08-04-film-look-cli.md)에 별도로 기록합니다.

## 2026-08-10 addendum — Digital B&W Film Look 15종

후속 `chromabase-working-film-look-v4`는 macOS 고정 profile 계약의 B&W negative 13종과 B&W reversal
2종을 native registry와 halation → spectral emulsion → acutance → single-channel grain 경로로
연결했습니다. film-scan identity, color/B&W kind 불일치 identity, B&W workspace의 color cube 미할당,
CLI 이름, ABI enum, managed enum/JSON/catalog/Shell request projection을 함께 검증했습니다.

실행한 x64 명령과 결과:

```powershell
ctest --preset x64-debug --output-on-failure
ctest --preset x64-release --output-on-failure
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-managed.ps1 -Preset x64-debug
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-managed.ps1 -Preset x64-release
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-interop.ps1 -Preset x64-debug
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-interop.ps1 -Preset x64-release
```

- native Debug/Release CTest: 각각 43/43 통과
- Catalog: Debug/Release 각각 492 assertions 통과
- Shell: Debug/Release 각각 305 assertions 통과
- Interop: Debug/Release 각각 95 assertions, ABI 0.23, x64 통과
- 실제 TIFF ABI preview가 rendered digital B&W 전체 graph를 실행하고 중립 RGB를 내는 것을 확인

Release gate를 처음 재시도할 때 앞선 제한시간 종료 뒤 남은 MSBuild child와 새 build가 같은
`.obj/.tlog/.exe`를 동시에 잡아 `Permission denied`가 발생했습니다. 남은 build 종료 뒤 `/m:1 /nr:false`로
직렬 재빌드하고 위 Release CTest·managed·interop을 다시 실행해 모두 통과했습니다. source/test 실패로
분류하지 않습니다.

ARM64 Debug/Release는 다음 대상의 순수 ARM64 교차 빌드가 통과했습니다.

```powershell
cmake --preset arm64-debug
cmake --build out/build/native/arm64-debug --config Debug --target negaflow_digital_bw_film_look_tests negaflow_working_film_look_tests negaflow_film_look_command_support_tests negaflow_develop_export_abi_tests negaflow_native negaflow_cli -- /m:1 /nr:false
cmake --preset arm64-release
cmake --build out/build/native/arm64-release --config Release --target negaflow_digital_bw_film_look_tests negaflow_working_film_look_tests negaflow_film_look_command_support_tests negaflow_develop_export_abi_tests negaflow_native negaflow_cli -- /m:1 /nr:false
```

x64 호스트에서 ARM64 executable을 실행하지 않았으므로 ARM64 runtime 통과를 의미하지 않습니다.
macOS Core Image pixel golden, 기준 artifact가 없는 acutance radius의 Gaussian sigma,
`CIRandomGenerator`와 Windows 결정적 grain의 통계 동등성, 실제 대형 촬영 TIFF·수백 장 batch와 나머지
color/motion profile 16종은 아직 검증하지 않았습니다.

## 2026-08-10 addendum — Film Emulation color/motion 16종

macOS delta commit `6b51695e747aa5d98531b8abee3c110a2531c0c7`의 추가 slide 4종,
color negative 8종, motion picture 4종을 Windows에 연결했습니다. 각 profile은 macOS의 tone/color
response, acutance, 활성 scatter·halation·grain material과 stock color preset을 사용합니다. 기존
ABI 값 0~26은 유지하고 새 값만 27~42에 append했으며 ABI struct/export와 버전 0.23은 바꾸지 않았습니다.

실행한 주요 명령:

```powershell
cmake --build --preset x64-debug --target negaflow_film_emulation_color_tests negaflow_digital_film_material_tests negaflow_working_film_look_tests negaflow_film_look_command_support_tests negaflow_native
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-managed.ps1 -Preset x64-debug
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-interop.ps1 -Preset x64-debug
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1 -Preset x64-debug
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\ci-gate.ps1 -Preset x64-release -IncludeArm64Cross
```

결과:

- x64 Debug/Release native CTest: 각각 43/43 통과
- Catalog: Debug/Release 각각 540 assertions 통과
- Shell: Debug/Release 각각 306 assertions 통과
- x64 Debug Interop: 95 assertions, ABI 0.23 통과
- 43개 CLI 이름(`none` 포함) round-trip과 catalog 42종 JSON round-trip 통과
- 16개 새 RGB33 cube가 finite·서로 다른 response를 만들고, 27개 color/motion material·preset·
  acutance registry가 모두 완결됨을 확인
- 실제 synthetic TIFF ABI preview가 Vision3 500T로 decode→공통 현상→DigitalFilmLook→preview를 통과
- ARM64 Release native·managed·WinUI 전체 graph 교차 빌드 통과

ARM64 executable은 x64 host에서 실행하지 않았으므로 ARM64 runtime 결과가 아닙니다. 새 16종은 macOS
source 수치와 Windows pipeline 연결을 검증했지만 profile별 macOS Core Image pixel golden이 현재 고정
artifact에 없습니다. 따라서 새 profile의 수치 결과 동등성, 실제 촬영 TIFF의 macOS/Windows pixel diff,
대형 batch 성능은 아직 미검증입니다.
