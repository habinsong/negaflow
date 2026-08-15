# Auto base v2 sampled-grid slice

2026-08-10 update: Auto first attempts the macOS sampled-grid connected-component path and reports
`auto_connected_component` through ABI 0.8. When that path has no coherent component, the same
32–256 linear sample grid applies non-film dilation, continuous-border, distributed-mask, and
strip fallback in macOS order. If all grid paths fail, the macOS engine's final scene-edge
compatibility measurement collects at least 32 valid edge candidates and uses their channel p90
before falling back to the documented constants.

For color film, a bright component with substantially less orange red-minus-blue separation is demoted
to the first plausible orange component, so the backlight is not selected as film base.

The demotion now matches the fixed macOS selection exactly: it tests only the first component below
`0.87×`, uses the upper median for an even R−B population, and does not skip to a darker third
component when the first lower component fails the color condition. Non-film mode candidates apply
the same p99-relative floor. Edge/coverage fractions use Double, strip RGB uses Double accumulation,
and the final scene-edge fallback shares the uniform pixel-centre bilinear affine coordinate contract.
The Core Image bitmap remains Float RGB, but every luma, percentile, median, MAD, threshold, channel
statistic, and final source comparison promotes those samples to Double. The selected Dmin narrows to
Float only at the public result boundary.

This sampled-grid update supersedes the earlier scene-edge-only description below: it includes
non-film mask, continuous border, distributed mask, masked strip fallback, and the chromogenic B&W
color retry. ABI 0.8 reports `auto_continuous_border`, `auto_distributed_mask`, and
`auto_strip_fallback` separately instead of overloading `auto_scene_edge`. `auto_scene_edge` remains
the weak compatibility fallback after those paths and is not a confident preset measurement.

연결 성분이 선택한 밝은 절반도 다른 sampled-grid 측정과 같은 강건 클러스터를 거칩니다. luma
중앙값과 MAD의 `max(MAD × 1.4826 × 3, 1e-4)` 범위 밖 표본을 먼저 버린 뒤 retained RGB의 채널별
중앙값을 Dmin으로 사용합니다. 이전 Windows 1차 경로만 이 단계를 건너뛰어 같은 연결 성분에 붙은
밝은 오염 셀이 전 프레임의 색·노출 앵커를 움직일 수 있었습니다.

기준일: 2026-08-09  
macOS 기준: `FilmBaseEstimator.swift`, `ChromabaseEngine+NegativePipeline.swift`

`nf_develop_export_request_v1`과 `nf_develop_export_v1`은 그대로 둡니다. ABI 0.6의 v2 request는
`base_estimation_mode`를 별도로 전달합니다. `Manual`은 Dmin 3채널을 그대로 사용하고, `Auto`는 decode
뒤 linear `WorkingImage`의 6% edge 표본에서 base를 결정해 같은 preview/export pipeline에 전달합니다.

- 색상 후보는 R≥G≥B와 최소 mask separation, B&W 후보는 relative neutral spread를 확인합니다.
- 90th-percentile edge transmission을 Dmin으로 사용합니다. 후보가 없으면 macOS의 documented scene
  fallback color `(0.86, 0.68, 0.50)`, B&W `(0.80, 0.80, 0.80)`을 씁니다.
- v2 result는 성공한 develop의 `applied_dmin`과 `manual`/`auto_scene_edge`/`auto_fallback` source를
  반환합니다. Preset은 resolver가 없으므로 `unsupported_base_estimation_mode`로 거부합니다.
- Auto recipe에 남아 있는 manual Dmin은 resolver에 전달하지 않습니다. mode 변경만으로 stored manual
  sample을 삭제하지 않는 Catalog 계약과 결과 사용을 분리합니다.
- Color/B&W positive film은 현재 negative pipeline의 입력이 아닙니다. Auto mode라도 Catalog/Shell이
  `UnsupportedPositiveFilm`으로 거부해 반전 결과를 publish하지 못하게 합니다.

## 검증

- x64 Debug 전체 native CTest 44/44 통과. Auto color/B&W edge, 강건 연결 성분, ordered demotion,
  Float RGB에서 Double로 승격한 `0.85` luma 경계, Double edge fraction, affine sparse scene-edge fallback, constant
  fallback, invalid layout 및 ABI
  export/preview/request 검사를 포함합니다.
- x64 Release `native.manual_negative_developer`·`native.develop_export_abi` 2/2 통과.
- ARM64 Release 두 test target과 `negaflow_native` 교차 빌드 통과.
  ARM64 Windows 장치에서 실행한 증거는 아닙니다.
- `scripts/test-managed.ps1 -Preset x64-debug` — Catalog 315, Shell 219 assertions 통과.
- `scripts/test-interop.ps1 -Preset x64-debug` — ABI 0.6, v2 layout/entry point를 포함해 50 assertions 통과.

## 남은 범위

이것은 macOS full `FilmBaseEstimator` 동등성 완료가 아닙니다. preset은 connected component,
continuous border, distributed mask만 confident measured source로 채택하고, B&W Auto 결과의 채널 비율이
`1.25`를 넘으면 color candidate path를 한 번 재시도해 chromogenic B&W tint를 보존합니다. cache와
measurement diagnostics는 아직 이식하지 않았습니다. Windows sampled-grid 축소와 Core Image affine
축소의 동일 입력 golden도 없으므로 image-result parity 완료를 주장할 수 없습니다.
