# 구현·검증 상태

기준일: 2026-08-04

| 항목 | 상태 | 증거 |
|---|---|---|
| exact macOS baseline | 고정 | `baseline/bootstrap-manifest.json` |
| canonical source asset hash | bootstrap 완료 | `baseline/source-assets.sha256` |
| 개발 도구 | 검증 | Visual Studio Community 2026 18.8.2, MSVC 14.51 x64/ARM64, SDK 26100, .NET SDK 10.0.302/runtime 10.0.10, C# Windows App SDK component |
| x64 CMake configure/build/run | 통과 | Debug/Release clean configure·build·CLI 실행 |
| x64 native tests | 통과 | Debug/Release CTest 각각 37/37 통과 |
| ARM64 cross build | 통과 | Debug/Release 전체 target build, CLI/DLL PE `AA64` |
| ARM64 native run | 미검증 | 실제 ARM64 Windows runner 필요 |
| .NET 10/C ABI Interop | 기반 통과 | `LibraryImport`, 절대 경로 resolver, ABI/layout 검증. x64 Debug/Release 13개 assertion, ARM64 교차 빌드 |
| WinUI shell | 첫 기반 통과 | component package 1.8 locked graph, x64 실제 최대화 실행, ARM64 교차 빌드, 6개 언어, 오른쪽 caption inset, Settings와 SHA 기본 `끔` |
| static runtime 배포 기반 | 통과 | Release CLI 직접 dependency가 Windows 기본 DLL 5개뿐이며 VC++ Redistributable DLL 없음 |
| float32 pixel contract | 부분 구현 | checked layout/stride/capacity, extended RGB, straight alpha, NaN/Inf 거부 |
| scalar pointwise·spatial | 부분 구현 | exposure, RGB 3×4 matrix, 기본 톤·4-band curve, 고정 64표본 DR/R/G/B point curve, 8-band HSL Color Mixer, 3구간 Color Grading, R/G/B Primary Calibration, 11종 RGB33 Film Emulation 색상→11행 acutance film-scan route x64 test·ARM64 build |
| Film Look source routing | CLI 출력 수직 경로 통과 | 명시적 `film_scan`/`rendered_digital`, film 색상→acutance exact 순서, caller cube/scratch, 실패 시 pixel 폐기; 진단·PNG16·TIFF16에서 Primary Calibration 뒤 실행, 실제 TIFF artifact 변화 검증; 미완성 digital graph는 `unsupported_route`; catalog projection은 구현, C ABI·WinUI는 미연결 |
| Catalog Develop route | 첫 관리 경계 통과 | `scanner`/`imported` transport와 film/digital signal 분리, legacy marker·강도 1.0 호환, 새 강도 0.5, unknown field 보존, invalid 조합 fail-closed; x64 Debug/Release 각각 163 assertion, ARM64 Debug/Release 교차 빌드; SQLite·실제 restart·C ABI는 미구현 |
| scalar negative inversion | 부분 구현 | color/B&W `shoulder-print-response-v4`, 고정 float bits와 합성 anchor test |
| 수동 negative develop | 첫 수직 경로 통과 | 채널별 Dmin, color/B&W 고정 response, working buffer 제자리 변환과 scalar exact 일치 |
| TIFF bounded probe | 부분 구현 | Classic/BigTIFF, endian 양쪽, strip/tile bounds, compressed-byte 합계, 선택형 LZW code-stream 의미 검사·작업량 상한·취소, Unicode read-only CLI, 손상 합성 corpus |
| WIC TIFF decode | 수직 경로 통과 | 단일 read-only stream preflight/decode, Microsoft 기본 decoder 고정, RGB/RGBA 16-bit none/LZW, LZW 의미 검사 필수, 독립 검사기 없는 Deflate 격리, ICC 추출, decoded-byte 사전 한도, sink 기반 행 streaming·취소·진행률; 사용자 TIFF 15/15 |
| scanner→working color | 수직 경로 통과 | untagged linear raw 9개와 embedded ICC→ICM→sRGB16→linear float 6개, 64행 streaming 15/15, whole-frame 최종 float exact 일치 15/15 |
| PNG16 output | phase 0 수직 경로 통과 | working→sRGB16, Microsoft WIC encode, 등록 sRGB ICC, 구조·전체 pixel·profile readback, 기존 파일 비덮어쓰기와 같은-directory 게시 |
| TIFF16 output | phase 1 수직 경로 통과 | 무압축 RGB16 Classic TIFF, 단일 IFD, 최소 metadata allowlist, 전체 pixel·ICC readback, 원본 상태 관찰, 단계별 CLI report와 비덮어쓰기 게시 |
| M4 최소 tone | 확장 수직 경로 통과 | 노출→기본 톤→동적 band→파라메트릭 curve→point curve→Color Mixer→Color Grading→Primary Calibration→명시적 film-scan Film Look→TIFF16/PNG16 검증 게시; source/profile/intensity catalog projection은 구현, 실제 DB·UI/ABI 연결은 미검증 |
| M4 단계 진단 | 확장 수직 경로 통과 | 기본 export stage wall/process-CPU, 진단 전용 scanner/develop/tone/Film Look min/max·versioned 비암호 fingerprint, Film Look route·cube/scratch·시간 보고, tone 24·point curve 24·Color Mixer 48·Color Grading 48·Primary Calibration 48·Film Emulation 색상 48/acutance 36-value conformance |
| 이미지 SHA-256 | opt-in 기반 통과 | 기본 `off`는 파일 I/O 0, 명시적 CNG SHA-256 known-answer/multi-chunk/cancel, 사용자 TIFF opt-in 15/15 |
| 네이티브 엔진 제3자 runtime dependency | 0개 | 빈 vcpkg dependency, WIC/ICM/Win32만 사용 |
| WinUI package graph | 고정·감사 | Runtime/WinUI 1.8 component 직접 참조, transitive 명세, 취약 package 0, AI/ML/Widgets 제외, 미사용 WebView2 payload 1.6MB를 x64/ARM64 clean build 출력에서 제외 |
| 제3자 고지 | 기록 완료 | `THIRD-PARTY-NOTICES.md`에 App SDK 조건과 미배포 WebView2 경계 기록, `components.json` 배포 게이트 갱신 |
| Windows 빌드 CI | 미구현 | 현재 CI 잡 4개가 전부 macOS. Windows 트리는 로컬 검증만. 계획은 `progress/windows-ci-plan.md` |
| GPU/WARP | 미구현 | M5 이후 |
| installer/signing | 미구현 | .NET 10과 Windows App Runtime 1.8 prerequisite 연결, SBOM/signing은 M17 범위 |

## 2026-08-06 변경

권리·운영 점검에서 나온 변경입니다. 이 날짜에 x64 Release clean 네이티브 빌드와 `ctest` 37/37,
관리 solution clean 빌드(경고 0·오류 0)와 관리 테스트를 다시 실행해 확인했습니다.

- 저장소 루트에 `.gitattributes`(`* text=auto eol=lf`)를 추가했습니다. 그 전에는 Windows 체크아웃이
  CRLF 작업 사본을 만들어 `verify-provenance.py`의 리소스 SHA-256이 어긋났고, Windows에서 게이트를
  전혀 돌릴 수 없었습니다. 이제 로컬에서 통과합니다. blob은 원래부터 LF였으므로 저장소 내용은
  바뀌지 않았습니다.
- 미사용 WebView2 payload를 셸 출력에서 제외했습니다(ADR-0022).
- 제3자 고지를 `THIRD-PARTY-NOTICES.md`로 기록했습니다.
- macOS golden의 관측 경계를 ADR-0021로 고정했습니다.

build ID는 빌드 당시 미커밋 작업이 있으면 `-dirty`로 표시합니다. ARM64 test executable은 빌드됐지만 x64
호스트에서 실행하지 않았으므로 ARM64 runtime 통과로 표시하지 않습니다.

전체 M0~M18 로드맵 진행률은 산출물 기준 약 15%, 현재 M0~M3 기반 구간은 약 46%로 추정합니다.
색상 수직 경로가 실제 코퍼스를 처리했다는 사실과 ColorSync 수치 동등성은 구분합니다. 산정 방식과
단계별 공백은 `progress/overall-roadmap.md`에 있습니다.
