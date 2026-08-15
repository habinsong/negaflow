# DigitalFilmLook color preset bounded tile 검증

기준일: 2026-08-10

## 변경 계약

rendered-digital color/motion Film Look의 stock color preset은 기존과 같은
linear RGB→sRGB→Color Mixer→Color Grading→Primary Calibration→linear RGB blend 순서를
사용합니다. 각 kernel이 pointwise인 경계를 이용해 사진 전체 원본 RGB 복사 대신 1,048,576 pixel,
약 12 MiB를 목표로 하는 행 타일 원본 버퍼 하나를 재사용합니다. 이미지 폭이 목표보다 크면 최소 한
행을 처리하므로 상한은 `max(12 MiB, 한 active RGB 행)`입니다.

## 가까운 회귀

`native.digital_film_material`은 2,048×1,025, stride 2,051의 deterministic RGBA fixture를 사용합니다.
이는 512행과 513행으로 나뉘어 실제 타일 경계를 통과하고 padding pixel도 포함합니다. 테스트 안의
종전 untiled orchestration과 새 tiled production path의 전체 buffer를 `memcmp`해 RGBA와 padding까지
byte-exact임을 확인합니다. 이 입력의 원본 RGB scratch는 25,190,400바이트에서
12,582,912바이트로 줄었습니다.

## 실행 명령과 결과

```powershell
cmake --build out/build/native/x64-debug --config Debug --target negaflow_digital_film_material_tests
ctest --test-dir out/build/native/x64-debug -C Debug -R "native.digital_film_material" --output-on-failure
powershell -NoProfile -ExecutionPolicy Bypass -File ./scripts/test.ps1 -Preset x64-debug
cmake --build out/build/native/x64-release --config Release --target negaflow_digital_film_material_tests negaflow_working_film_look_tests negaflow_develop_export_abi_tests
ctest --test-dir out/build/native/x64-release -C Release -R "native\.(digital_film_material|working_film_look|develop_export_abi)$" --output-on-failure
cmake --build out/build/native/arm64-release --config Release --target negaflow_digital_film_material_tests negaflow_working_film_look_tests negaflow_develop_export_abi_tests negaflow_native
# 아래 명령만 저장소 root에서 실행
py negaflow-mac/scripts/ci/verify-provenance.py
```

- x64 Debug targeted: 1/1 통과
- x64 Debug 전체 native CTest: 44/44 통과
- x64 Release 인접 native CTest: 3/3 통과
- ARM64 Release 관련 tests와 DLL: 교차 빌드 통과, PE machine 모두 `0xAA64`
- provenance: files 1,975, text 1,848, binary 127, resources 29, commits 148 검증

## 검증 경계

- ARM64 Windows 장치에서 실행하지 않았습니다.
- 55MP 실제 촬영 TIFF와 여러 장 batch의 process working set·처리 시간은 측정하지 않았습니다.
- 새 16개 color/motion profile의 macOS Core Image pixel golden은 여전히 필요합니다.
