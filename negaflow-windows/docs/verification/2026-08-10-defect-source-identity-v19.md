# Defects source identity ABI v19 검증

날짜: 2026-08-10

기준: macOS `2fa1d6297378673b58b8bec72025e968ccc3125c`의
`DefectSourceIdentity(byteCount, sha256)`와 identity-matched cleaned-raw 소비 계약

## 구현 경계

- 비어 있지 않은 region Defects recipe는 source byte count와 32-byte SHA-256 없이 Shell request와
  ABI v19 request를 만들 수 없습니다.
- native는 첫 file observation 뒤 share-deny-write 순차 CNG SHA-256을 계산합니다. hash가 돌기 전과
  끝난 뒤의 volume/file ID, byte count, last-write가 같고 저장된 digest와도 일치해야 decode를 시작합니다.
- decode 뒤 기존 file observation 재검증도 유지합니다. 따라서 hash 중 변경, hash와 decode 사이 교체,
  decode 중 변경은 모두 fail-closed입니다.
- digest나 byte count가 다르면 `observe_source_before/defect_source_identity_mismatch`로 실패하며 preview
  buffer를 결과로 채택하지 않고 export artifact도 게시하지 않습니다.
- Defects가 없는 request는 v19 source identity 필드를 비워야 하며 SHA-256을 계산하지 않습니다.
  기존 v18 export는 append-only ABI 호환을 위해 보존합니다.

## 실행한 명령

```powershell
cmake --build out/build/native/x64-debug --config Debug --target `
  negaflow_develop_export_abi_tests negaflow_image_content_hash_tests
ctest --test-dir out/build/native/x64-debug -C Debug --output-on-failure `
  -R "native\.(develop_export_abi|image_content_hash)"

powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-interop.ps1 `
  -Preset x64-debug
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-managed.ps1 `
  -Preset x64-debug

cmake --build out/build/native/x64-release --config Release --target `
  negaflow_develop_export_abi_tests negaflow_image_content_hash_tests
ctest --test-dir out/build/native/x64-release -C Release --output-on-failure `
  -R "native\.(develop_export_abi|image_content_hash)"
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-interop.ps1 `
  -Preset x64-release
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-managed.ps1 `
  -Preset x64-release

cmake --build out/build/native/arm64-release --config Release --target `
  negaflow_native negaflow_develop_export_abi_tests negaflow_image_content_hash_tests
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-managed.ps1 `
  -Preset arm64-release
```

## 결과

- x64 Debug/Release `native.image_content_hash`와 `native.develop_export_abi`: 각각 `2/2` 통과
- x64 Debug/Release Interop: ABI `0.25`, `107 assertions`, 실패 0
- x64 Debug/Release Catalog: `583 assertions`, 실패 0
- x64 Debug/Release Shell: `314 assertions`, 실패 0
- ARM64 Release native DLL·두 표적 test와 managed 전체 graph: 교차 빌드 경고 0·오류 0
- 64×64 합성 RGB16 TIFF에서 맞는 identity는 v18과 같은 preview pixel을 냈고, 틀린 digest는 decode
  전에 실패했으며 export 파일을 만들지 않았습니다. 원본 TIFF bytes는 불변이었습니다.

이번 체크포인트는 전체 native CTest 44/44를 다시 실행하지 않았습니다. 변경 위험에 가까운 두 test와
전체 ABI/managed graph를 실행했습니다. ARM64 결과는 교차 빌드 증거이며 실기 runtime 증거가 아닙니다.

## 남은 리스크

- source-bound Defects preview는 현재 렌더마다 원본을 한 번 순차 hash합니다. 일반 렌더에는 비용이 없지만,
  대형 TIFF의 반복 slider preview에서는 cleaned-raw/cache가 붙기 전 지연이 커질 수 있습니다.
- 실제 촬영 TIFF의 macOS/Windows 동일 입력 mask·pixel golden은 아직 없습니다.
- brush/clone native 표현, 실제 ARM64 실행, 대형 ROI·수백 장 batch 처리량은 미검증입니다.

새 제3자 코드나 runtime dependency는 추가하지 않았고 Windows CNG만 사용했습니다.
