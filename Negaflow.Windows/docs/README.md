# Negaflow Windows 개발 문서

이 디렉터리는 Windows판 구현의 현재 사실, 근거, 결정, 검증 결과와 남은 위험을 기록합니다.
계획과 실제 통과 증거를 섞지 않으며, cross-build 성공을 실제 장치 실행 성공으로 표시하지 않습니다.

## 문서 지도

### 진행 상황

- [전체 로드맵과 진행률](progress/overall-roadmap.md)
- [M0~M3 기반 단계 상세](progress/m0-m3-foundation.md)
- [현재 한눈에 보기](STATUS.md)

### 구현 설명

- [네이티브 기반](implementation/native-foundation.md)
- [관리 코드 Interop 기반](implementation/managed-interop-foundation.md)
- [제한형 TIFF 사전 검사](implementation/tiff-probe.md)
- [압축 TIFF LZW 의미 사전 검사와 Deflate 격리](implementation/compressed-tiff-preflight.md)
- [WIC TIFF 디코더](implementation/wic-tiff-decoder.md)
- [Scanner TIFF에서 working linear-sRGB까지](implementation/scanner-color-to-working.md)
- [선택형 이미지 SHA-256 구현](implementation/image-content-hash.md)
- [수동 네거티브 현상 수직 경로](implementation/manual-negative-development.md)
- [PNG16 출력·검증·게시](implementation/png16-output-publish.md)
- [TIFF16 출력·최소 메타데이터 검증·게시](implementation/tiff16-output-publish.md)
- [노출·대비·파라메트릭·포인트 커브](implementation/tone-adjustment-pipeline.md)
- [DR/R/G/B 포인트 커브 scalar](implementation/point-curve-scalar.md)
- [8대역 Color Mixer scalar](implementation/color-mixer-scalar.md)
- [3구간 Color Grading scalar](implementation/color-grading-scalar.md)
- [R/G/B Primary Calibration scalar](implementation/primary-calibration-scalar.md)
- [Film Emulation RGB33 색상 cube](implementation/film-emulation-color-cube.md)
- [macOS Film Emulation Core Image golden 생성기](implementation/macos-film-emulation-golden.md)
- [Film Emulation acutance](implementation/film-emulation-acutance.md)
- [Working Film Look source routing](implementation/working-film-look-routing.md)
- [Catalog Develop route projection](implementation/catalog-develop-route.md)
- [파이프라인 CPU 시간과 빠른 픽셀 진단](implementation/pipeline-diagnostics.md)
- [WinUI 셸 기반](implementation/winui-shell-foundation.md)

### 환경과 검증

- [개발 환경과 설치 상태](setup/development-environment.md)
- [2026-08-04 검증 기록](verification/2026-08-04-foundation.md)
- [2026-08-04 사용자 TIFF 코퍼스 검증](verification/2026-08-04-local-tiff-corpus.md)
- [2026-08-04 WinUI 셸 검증](verification/2026-08-04-winui-shell.md)
- [2026-08-04 PNG16 출력 검증](verification/2026-08-04-png16-output.md)
- [2026-08-04 TIFF16 출력·단계 보고 검증](verification/2026-08-04-tiff16-output.md)
- [2026-08-04 노출·대비·커브 수직 경로 검증](verification/2026-08-04-tone-adjustment.md)
- [2026-08-04 DR/R/G/B 포인트 커브 scalar 검증](verification/2026-08-04-point-curve.md)
- [2026-08-04 8대역 Color Mixer scalar 검증](verification/2026-08-04-color-mixer.md)
- [2026-08-04 3구간 Color Grading scalar 검증](verification/2026-08-04-color-grading.md)
- [2026-08-04 R/G/B Primary Calibration scalar 검증](verification/2026-08-04-primary-calibration.md)
- [2026-08-04 Film Emulation RGB33 색상 cube 검증](verification/2026-08-04-film-emulation-color.md)
- [2026-08-04 Film Emulation Core Image golden·acutance 검증](verification/2026-08-04-film-emulation-core-image-golden.md)
- [2026-08-04 Film Look source routing 검증](verification/2026-08-04-film-look-routing.md)
- [2026-08-04 Film Look CLI·실제 출력 검증](verification/2026-08-04-film-look-cli.md)
- [2026-08-04 Catalog Develop route 검증](verification/2026-08-04-catalog-develop-route.md)
- [2026-08-04 파이프라인 CPU 시간·단계 진단 검증](verification/2026-08-04-pipeline-diagnostics.md)
- [2026-08-04 압축 TIFF 사전 검사 검증](verification/2026-08-04-compressed-tiff-preflight.md)
- [이미지 I/O 조사와 권리 검토](research/image-io-sources.md)
- [압축 TIFF 사전 검사 공식 근거와 권리 검토](research/compressed-tiff-preflight-sources.md)
- [출력 encode·게시 근거와 권리 검토](research/output-encode-sources.md)
- [TIFF16 출력·메타데이터 공식 근거와 권리 검토](research/tiff16-output-sources.md)
- [네거티브 반전 근거와 권리 조사](research/negative-inversion-sources.md)
- [톤 조정 공식 근거와 권리 조사](research/tone-adjustment-sources.md)
- [포인트 커브 공식 근거와 권리 조사](research/point-curve-sources.md)
- [Color Mixer 공식 근거와 권리 조사](research/color-mixer-sources.md)
- [Color Grading 공식 근거와 권리 조사](research/color-grading-sources.md)
- [Primary Calibration 공식 근거와 권리 조사](research/primary-calibration-sources.md)
- [Film Emulation 색상 cube 공식 근거와 권리 조사](research/film-emulation-color-sources.md)
- [Film Emulation acutance 공식 근거와 권리 조사](research/film-emulation-acutance-sources.md)
- [Film Look source routing 공식 근거와 권리 조사](research/film-look-routing-sources.md)
- [Catalog Develop route 공식 근거와 권리 조사](research/catalog-develop-route-sources.md)
- [파이프라인 진단 공식 근거와 권리 검토](research/pipeline-diagnostics-sources.md)
- [Swift UI 패리티 기준선](research/swift-ui-parity-baseline.md)

### 결정 기록

- [ADR-0001: Windows 구현 기준선](decisions/0001-foundation.md)
- [ADR-0002: scalar 픽셀 계약](decisions/0002-scalar-pixel-contract.md)
- [ADR-0003: TIFF 사전 검사 계약](decisions/0003-tiff-probe-contract.md)
- [ADR-0004: OS 우선 이미지·색상 경로와 제3자 의존성 게이트](decisions/0004-os-first-image-and-color.md)
- [ADR-0005: 이미지 content SHA-256은 기본 끔](decisions/0005-image-content-sha256-off-by-default.md)
- [ADR-0006: SANE은 별도 GPL 스캐너 플러그인으로 유지](decisions/0006-scanner-plugin-boundary.md)
- [ADR-0007: 첫 출력은 검증된 16-bit sRGB PNG로 게시](decisions/0007-verified-png16-output-boundary.md)
- [ADR-0008: TIFF16 출력은 최소 메타데이터를 검증한 뒤 게시](decisions/0008-verified-tiff16-minimal-metadata-boundary.md)
- [ADR-0009: 첫 톤 조정은 macOS 수식과 순서를 보존하고 동적 측정 차이를 명시](decisions/0009-tone-adjustment-scalar-contract.md)
- [ADR-0010: 저비용 CPU 시간과 진단 전용 픽셀 fingerprint를 분리](decisions/0010-low-cost-pipeline-diagnostics.md)
- [ADR-0011: LZW는 독립 사전 검사하고 Deflate는 검증기 전까지 격리](decisions/0011-bounded-lzw-preflight-and-deflate-quarantine.md)
- [ADR-0012: 포인트 커브는 고정 64표본 scalar 계약으로 시작](decisions/0012-bounded-point-curve-scalar-contract.md)
- [ADR-0013: Color Mixer는 고정 8대역 working-RGB HSL scalar로 시작](decisions/0013-bounded-color-mixer-scalar-contract.md)
- [ADR-0014: Color Grading은 고정 3구간 extended-linear scalar로 시작](decisions/0014-bounded-color-grading-scalar-contract.md)
- [ADR-0015: Calibration은 고정 R/G/B Primary scalar로 시작](decisions/0015-bounded-primary-calibration-scalar-contract.md)
- [ADR-0016: Film Emulation 색상 단계는 고정 RGB33 cube로 격리](decisions/0016-bounded-film-emulation-color-cube.md)
- [ADR-0017: provenance gate는 Windows 1차 C++와 제3자 payload를 구분](decisions/0017-first-party-windows-native-provenance-boundary.md)
- [ADR-0018: Film Emulation acutance는 11행 bounded spatial kernel로 격리](decisions/0018-bounded-film-emulation-acutance.md)
- [ADR-0019: Film Look은 명시적 source 종류로 완전한 경로를 선택](decisions/0019-explicit-film-look-source-routing.md)
- [ADR-0020: catalog의 전송 출처와 현상 신호를 분리하고 legacy recipe를 명시적으로 투영](decisions/0020-explicit-catalog-develop-route.md)

## 사실 우선순위

충돌이 생기면 다음 순서로 판단합니다.

1. 같은 source revision에서 생성한 실행 로그와 machine-readable 결과
2. `baseline/`의 고정 manifest와 SHA-256
3. `decisions/`의 채택된 결정
4. `implementation/`의 현재 구현 설명
5. `progress/`의 계획과 진행률 추정

## 갱신 규칙

- 구현이나 설치 상태가 바뀌면 관련 문서와 `STATUS.md`를 같은 변경에서 갱신합니다.
- 검증하지 않은 항목에는 `통과`를 쓰지 않습니다.
- 진행률은 시간이나 출시일 예측이 아니라 로드맵 산출물 충족 비율입니다.
- 명령은 실제 실행한 것과 다음 실행 후보를 구분합니다.
- 외부 코드·사진·프로파일을 추가하기 전에 출처, 라이선스, 재배포 권리와 SHA-256을 기록합니다.
- 사용자 원본은 읽기 전용으로 다루며, 테스트 artifact는 합성 데이터나 권리 확인된 저장소 자산만 사용합니다.
