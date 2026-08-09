# Film preset base v4

날짜: 2026-08-09

## 범위

Film base의 `Auto`/`Film`/`Manual` recipe를 Catalog, Shell, ABI 0.10, native CPU pipeline에 연결했습니다.

- Film은 27개 번들 stock ID와 `neutral`, `white-led`, `warm-led`, `halogen`, `fluorescent` light-source ID만 수용합니다. unknown ID는 Shell과 native resolver에서 fail-closed 합니다.
- ABI 0.10의 append-only `nf_develop_export_request_v4`/`nf_develop_preview_v4`는 film stock/light-source UTF-16 ID를 전달합니다. v1~v3의 layout, entry point, 그리고 Preset 거부 의미는 유지합니다.
- native resolver는 stock Dmin/Dmax와 light gain을 해석합니다. 연결된 자동 base component가 있으면 측정 Dmin을 우선하고 stock response만 적용하며, 없으면 stock Dmin fallback에 gain을 한 번 적용합니다. B&W에서는 light gain을 적용하지 않습니다.
- WinUI Film mode는 stock과 light-source picker를 보입니다. `None` stock은 Auto로 돌아가며, Manual sample과 light-source ID는 mode 변경만으로 삭제하지 않습니다. Automation ID는 `negaflow.develop.base.mode.film`, `.film-stock`, `.light-source`입니다.

## 검증

- `scripts/test.ps1 -Preset x64-debug` — native CTest 30/30 통과. v4 null/작은 request, unknown stock, film/light resolver, preview provenance, preset response를 포함합니다.
- `scripts/test-managed.ps1 -Preset x64-debug` — 경고 0, 오류 0, Catalog 317개와 Shell 267개 단언 통과.
- `scripts/test-interop.ps1 -Preset x64-debug` — ABI 0.10, x64, interop 54개 단언 통과.
- x64 Release에서도 native CTest 30/30, Catalog 317개, Shell 267개, ABI 0.10 interop 54개 단언을 통과했습니다. native와 managed ARM64 교차 빌드는 경고·오류 없이 완료했고, provenance gate도 통과했습니다. ARM64 runtime은 실행하지 않았습니다.
- 사용자가 제공한 `OpticFilm8100_frame_1.tiff`(5088×3401, 16-bit RGB)는 CLI 수동 Dmin 전체 경로와 PNG16 export를 통과했습니다. 결과 PNG는 100,377,638바이트, `structure_verified`, `pixels_verified`, `profile_verified`, `source_unchanged_during_decode`가 모두 true이며 SHA-256은 `eab2e899b9e9a913be5a141afca9835040f36d3d28dd8e3bb86dcf044b54708b`입니다.

## 한계

이것은 full macOS Film base parity가 아닙니다. stock Dmin/Dmax와 light gain은 macOS baseline의 documented curve reading을 이식한 값이며 외부 계측 검증은 아닙니다. Windows의 measured-first 판단은 현재 connected component일 때만 적용하므로 macOS의 confident-only estimator와 동치라고 주장할 수 없습니다. Scanner profile grade, 제조사별 picker 그룹, canvas base picker/reset, rendered screenshot/UIA/keyboard/high-contrast/compact/ARM64 runtime 증거는 남아 있습니다. 실제 TIFF export도 Film preset request가 아니라 CLI 수동 Dmin 경로입니다.
