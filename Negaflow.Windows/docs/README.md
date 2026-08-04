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
- [WIC TIFF 디코더](implementation/wic-tiff-decoder.md)
- [Scanner TIFF에서 working linear-sRGB까지](implementation/scanner-color-to-working.md)
- [선택형 이미지 SHA-256 구현](implementation/image-content-hash.md)
- [수동 네거티브 현상 수직 경로](implementation/manual-negative-development.md)

### 환경과 검증

- [개발 환경과 설치 상태](setup/development-environment.md)
- [2026-08-04 검증 기록](verification/2026-08-04-foundation.md)
- [2026-08-04 사용자 TIFF 코퍼스 검증](verification/2026-08-04-local-tiff-corpus.md)
- [이미지 I/O 조사와 권리 검토](research/image-io-sources.md)
- [네거티브 반전 근거와 권리 조사](research/negative-inversion-sources.md)

### 결정 기록

- [ADR-0001: Windows 구현 기준선](decisions/0001-foundation.md)
- [ADR-0002: scalar 픽셀 계약](decisions/0002-scalar-pixel-contract.md)
- [ADR-0003: TIFF 사전 검사 계약](decisions/0003-tiff-probe-contract.md)
- [ADR-0004: OS 우선 이미지·색상 경로와 제3자 의존성 게이트](decisions/0004-os-first-image-and-color.md)
- [ADR-0005: 이미지 content SHA-256은 기본 끔](decisions/0005-image-content-sha256-off-by-default.md)

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
