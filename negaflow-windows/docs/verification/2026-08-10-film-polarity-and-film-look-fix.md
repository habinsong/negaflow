# 2026-08-10 film polarity와 Film Look 수정 검증

## 범위

- ABI v17의 negative/positive polarity
- color/B&W와 polarity를 결합한 4상태 film type
- positive film scan의 base·반전 우회와 B&W positive 중립 출력
- macOS commit `6b51695e747aa5d98531b8abee3c110a2531c0c7`에 맞춘 film-scan Film Look identity
- B&W digital process에 현재 color stock을 적용하지 않는 profile-kind gate

## 실행

```powershell
cmake --build --preset x64-debug --target negaflow_working_film_look_tests negaflow_film_look_command_support_tests negaflow_develop_export_abi_tests
ctest --preset x64-debug -R '^native\.(working_film_look|develop_export_abi)$' --output-on-failure
ctest --preset x64-debug -R '^cli\.film_look_command_support$' --output-on-failure
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-interop.ps1 -Preset x64-debug
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-managed.ps1 -Preset x64-debug
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1 -Preset x64-debug
```

## 결과

- x64 Debug native CTest: 42/42 통과
- Interop contract: 95 assertions 통과, ABI 0.23, x64
- Catalog: 447 assertions 통과
- Shell: 304 assertions 통과
- managed solution build: 경고 0, 오류 0

Release x64와 ARM64 교차 빌드는 이번 Debug 핵심 체크포인트에서 반복하지 않았습니다. 실제 macOS runtime
numeric golden과 실제 ARM64 실행 결과는 이 기록의 범위가 아닙니다.
