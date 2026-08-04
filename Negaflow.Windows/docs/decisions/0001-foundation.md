# ADR-0001: Windows 구현 기준선과 초기 경계

상태: 채택
기준일: 2026-08-04

## 문제

Windows 설계 문서는 `9be909c`를 조사 기준으로 사용하지만 실제 구현 착수 시 저장소 HEAD는
깨끗한 `2fa1d6297378673b58b8bec72025e968ccc3125c`입니다. 움직이는 `main`을 따라가면 완료
기준이 사라지므로 exact commit을 선택해야 합니다.

## 결정

- Windows M0 기준선을 `2fa1d6297378673b58b8bec72025e968ccc3125c`로 고정합니다.
- 설계 문서 조사 기준 `9be909c`는 별도 필드로 보존합니다.
- 두 커밋 사이의 디지털 필름 명부 범위 수정은 correctness fix로 포함합니다.
- Windows 구현은 루트 아래 `Negaflow.Windows/`에서 시작하되, 별도 저장소로 옮길 수 있는
  자체 build root를 유지합니다.
- 첫 구현은 제3자 의존성이 없는 C++20 core/DLL/CLI/test입니다.
- 셸은 C#/.NET 10/WinUI 3, 엔진은 C++20, 경계는 좁은 C ABI로 유지합니다.
- x64와 ARM64 프리셋을 동시에 정의합니다. cross-compile과 실제 ARM64 실행 증거는 구분합니다.

## 지원 정책

- Windows SDK API 기준 후보는 build 26100입니다.
- 현재 개발 호스트 build 26200은 개발 증거일 뿐 고객 지원 범위 선언이 아닙니다.
- 출시 지원 Windows 버전은 M17에서 당시 지원 중인 release로 다시 확정합니다.

## 의존성

초기 M1 네이티브 엔진과 Interop 경로에는 Windows SDK 외 제3자 runtime dependency가 없습니다.
후속 WinUI 셸의 Microsoft component package graph는 `third_party/manifest/components.json`에서 별도로
고정·감사합니다. LittleCMS, libtiff, SQLite, LibRaw, WiX와 scanner 구성 요소는 실제 기능이 시작될 때
하나씩 라이선스·ARM64·보안 gate를 거친 뒤 추가합니다.

## 결과

이 결정은 M0 전체 baseline exporter나 제품 동등성 완료를 뜻하지 않습니다. 현재 manifest는
bootstrap 상태이며, generated/curated baseline set과 실제 macOS fixture는 후속 작업입니다.
