# 2026-08-04 Film Look CLI·실제 출력 검증

기준일: 2026-08-04
대상: `chromabase-working-film-look-v1`의 진단·PNG16·TIFF16 연결

## 검증 범위

- `film_scan`/`rendered_digital`, 12개 profile 이름과 finite intensity의 명시적 parsing
- Film Look이 `tone_adjust` 뒤, `output_convert_encode_verify_publish` 전에 실행되는 순서
- 기존 명령은 `film_scan + none + 0.5` identity로 유지
- tone 인수와 Film Look 인수를 각각 생략하거나 두 그룹 모두 전달하는 정확한 인수 수 계약
- 활성 색상에서 caller-owned RGB33 cube, 활성 acutance에서 `width × 11` scratch만 준비
- identity는 cube/scratch 할당 0, 낮은 intensity `0.024`는 acutance scratch만 준비
- 네거티브 현상 명령의 `rendered_digital`은 source I/O 전에 명시적으로 거부
- Film Look 오류 때 부분 처리 pixel을 출력에 게시하지 않는 fail-closed 연결
- source/artifact SHA-256 기본 `off` 유지

## 자동 통합 검증

`cli.export_developed_tiff_film_look`은 저장소 소유
`Sources/ScannerKit/Resources/Frame.tiff`를 다음 세 recipe로 실제 게시합니다.

1. 기존 인수만 사용한 identity Film Look
2. 활성 tone 여섯 값과 identity Film Look
3. 2번과 같은 tone에 `film_scan velvia_50 0.73` Film Look을 추가

세 TIFF가 모두 WIC encode, 구조·최소 metadata, 전체 pixel·ICC readback과 같은-directory 게시를
통과해야 합니다. 이어서 tone이 같은 2번과 3번 artifact가 서로 같지 않은지 확인해 차이가 Film Look에서
왔고 그 결과가 실제 output encoder까지 전달됐음을 검증합니다. 성공 JSON에서는 다음 순서와 값을
확인합니다.

```text
tone_adjust < film_look < output_convert_encode_verify_publish
route = film_scan_emulation
color_applied = true
acutance_applied = true
source_sha256_mode = off
artifact_sha256_mode = off
```

마지막으로 존재하지 않는 source와 `rendered_digital`을 함께 전달해 exit code 2와
`negative_develop_requires_film_scan_source`를 확인합니다. 따라서 거부가 file observation보다 먼저라는
사실도 검증됩니다. script는 자신이 만든 고정 test output만 시작·종료 시 제거합니다.

## 빌드·실행 결과

| 대상 | 결과 |
|---|---|
| x64 Debug 전체 build | 통과 |
| x64 Debug CTest | 37/37 통과 |
| x64 Release 전체 build | 통과 |
| x64 Release CTest | 37/37 통과 |
| ARM64 Debug 전체 target cross-build | 통과 |
| ARM64 Release 전체 target cross-build | 통과 |

ARM64 executable은 x64 호스트에서 실행하지 않았으므로 ARM64 runtime 수치나 WIC 게시 통과로 표시하지
않습니다.

Release PE header에서 CLI, DLL과 새 command-support test는 x64 `8664`, ARM64 `AA64`였습니다. DLL
export는 두 architecture 모두 `nf_get_abi_version`, `nf_get_build_info_v1` 두 개뿐입니다. x64 Release
CLI 직접 dependency는 Windows 기본 `bcrypt`, `SHLWAPI`, `ole32`, `mscms`, `KERNEL32` 다섯 개로
유지되며 새 제3자 runtime은 없습니다.

## 수동 실제 파일 확인

x64 Debug CLI로 동일 fixture를 활성 Velvia 50 recipe에 넣어 PNG16과 TIFF16을 각각 생성했습니다.
두 명령 모두 exit code 0, `published=true`, `film_scan_emulation`, color/acutance 적용과 SHA mode `off`를
보고했습니다. PNG는 631×403의 정상 프레임으로 열렸고, 산출물은 빈 파일·깨진 container·전체 단색이
아닌 장면 이미지임을 육안 확인했습니다. 이 확인은 색 정확도 golden을 대신하지 않으며, 색상 수치는
별도 macOS Core Image golden과 native conformance가 담당합니다.

## 성능·메모리 경계

- Film Look은 별도 full-frame float buffer를 만들지 않고 tone 결과의 owned image를 제자리 처리합니다.
- workspace는 active color cube 431,244바이트와 `width × 11 × 12`바이트 acutance scratch로 제한됩니다.
- export report는 workspace byte와 Film Look wall/process-CPU 시간을 기록하지만 pixel fingerprint를 위해
  영상을 다시 순회하지 않습니다.
- 일반 이미지와 출력 artifact의 SHA-256은 명시적으로 켜지 않았고 계산하지 않았습니다.

## 남은 위험

- source metadata와 legacy recipe를 읽고 쓰는 catalog projection은 생겼지만 실제 SQLite/import
  writer와 restart 저장·재로드는 아직 없습니다.
- C ABI와 WinUI는 source/profile/intensity를 아직 노출하지 않습니다.
- 활성 rendered-digital 전체 graph는 아직 `unsupported_route`입니다.
- 실제 대형 사용자 TIFF의 Film Look 성능·메모리 benchmark와 실제 ARM64 Windows 실행이 남았습니다.
- 이번 실제 파일 확인은 한 저장소 fixture이며 전체 사진 corpus 시각·수치 동등성 검증은 아닙니다.
