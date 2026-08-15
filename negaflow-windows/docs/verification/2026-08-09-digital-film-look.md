# DigitalFilmLook native vertical slice 검증

- 날짜: 2026-08-09
- 기준: macOS commit `2fa1d6297378673b58b8bec72025e968ccc3125c`
- 구성: x64 Debug, ABI 0.17

## 실행

```powershell
cmake --build --preset x64-debug --target negaflow_digital_film_material_tests negaflow_working_film_look_tests negaflow_develop_export_abi_tests
ctest --preset x64-debug -R '^native\.(digital_film_material|working_film_look|develop_export_abi)$' --output-on-failure
ctest --preset x64-debug -R '^native\.(grain_mend|film_scan_denoise|local_dodge_burn|texture_stage|bw_toning|image_transform|digital_film_material|working_film_look|develop_export_abi)$' --output-on-failure
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-interop.ps1 -Preset x64-debug
out\build\native\x64-debug\Debug\negaflow-cli.exe --export-developed-png16 <OpticFilm8100_frame_1.tiff> <temporary-output.png> 0.90 0.65 0.45 color film_scan portra_400 0.5
```

## 결과

- DigitalFilmLook 직접 경계 3/3 통과
- Chroma 현상 핵심 묶음 9/9 통과
- 관리 build 경고 0, 오류 0
- Interop 78 assertions 통과, ABI 0.17, x64
- 실제 TIFF v11 preview에서 `rendered_digital` route 3과 non-identity 출력 확인
- 사용자 TIFF `OpticFilm8100_frame_1.tiff`(5088×3401)를 Portra 400 film-scan route로 처리해
  99,345,753바이트 PNG16 게시, 구조·전체 pixel·ICC 검증, 원본 불변 확인. 처리 23.26초
- halation 512픽셀 tile 경계, alpha 보존, warm halo와 energy redistribution 확인
- grain 결정성·density 반응과 서로 다른 stock color 방향 확인

## 미검증

- macOS `CIRandomGenerator`와 Windows 절대 좌표 hash 사이의 shared-seed pixel exact 비교
- macOS numeric golden과 사진 corpus 허용오차
- untagged rendered-digital TIFF의 명시적 색공간 계약
- 대형 이미지 peak memory·성능, x64 Release, ARM64 runtime, GPU/WARP

실제 TIFF 출력은 검증 직후 임시 디렉터리에서 삭제했고 사용자 원본은 수정하지 않았습니다.
