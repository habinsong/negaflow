# 실촬영 현상 출력 지문 (2026-08-13)

이번 세션은 셸을 크게 손댔습니다 — 라이브러리 격자, 썸네일 파이프라인, 필름스트립, crop,
종횡비, 자동 보정, 출력 패널. **그 중 어느 것도 현상 결과를 바꾸어서는 안 됩니다.** 그것을
말로 주장하지 않고 숫자로 남깁니다.

## 기준

- 입력: `negaflow-mac/Sources/ScannerKit/Resources/Frame.tiff` (1,532,798 바이트, 컬러 네거티브)
- 명령: `negaflow-cli --export-developed-png16 <src> <dst> 0.28 0.18 0.12 color`
- 빌드: x64 **Release** (`out/build/native/x64-release/Release/negaflow-cli.exe`)

## 결과

| 항목 | 값 |
| --- | --- |
| 출력 SHA-256 | `561D12AF26A5E715A75D7BC044C57C7AB806FE44813A6A40F54CB60FDD67A37C` |
| 크기 | 631 × 403 |
| algorithm_version | `shoulder-print-response-v4` |
| clipped_color_components | 0 |
| structure / pixels / profile verified | 전부 true |
| source_unchanged_during_decode | true |
| source_file_bytes | 1,532,798 (그대로) |

인자를 주지 않은 축은 전부 identity 로 기록됐습니다(`exposure_applied` 등 false, film_look
route `identity`). 즉 이 지문은 **디코드 → 스캐너 색상 → 수동 Dmin 반전 → 게시** 경로만의
지문입니다. 톤·필름 룩까지 포함한 지문이 필요하면 인자를 준 별도 항목으로 남기십시오.

## 쓰는 법

셸이나 카탈로그를 고친 뒤 같은 명령을 다시 돌려 해시가 같으면 현상 결과가 그대로입니다.
달라지면 **의도한 변경인지 먼저 확인하십시오** — 셸 작업이 픽셀을 바꿨다면 그건 회귀입니다.

## 이 지문이 증명하지 않는 것

macOS 와 같다는 것은 증명하지 않습니다. 같은 입력에 대해 **Windows 가 스스로 일관된다**는
것만 증명합니다. macOS 대비 수치 비교는 여전히 macOS 호스트가 필요하며,
`2026-08-10-macos-kernel-audit.md` 의 blur 반경 질문도 열려 있습니다.
