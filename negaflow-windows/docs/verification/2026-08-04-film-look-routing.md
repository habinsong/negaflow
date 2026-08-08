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
