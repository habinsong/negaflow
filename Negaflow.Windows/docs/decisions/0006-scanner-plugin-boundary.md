# ADR-0006: SANE은 별도 GPL 스캐너 플러그인으로 유지

상태: 채택
기준일: 2026-08-04

## 문제

초기 `windows_docs`에는 Windows 장치 API인 WIA와 TWAIN을 후보로 조사한 문서가 있습니다. 그러나 현재
macOS 제품의 실제 계약은 장치 API를 본체에 직접 연결하는 구조가 아닙니다. Negaflow 본체는 장치 비종속
외부 프로세스 프로토콜만 소유하고, SANE 구현은 별도 GPL 프로젝트가 담당합니다.

Windows판이 WIA/TWAIN을 새 기준으로 삼으면 기존 제품과 통신 경로가 둘로 갈라지고, SANE 플러그인과
장치 기능 검증을 중복 구현하게 됩니다. 또한 SANE 구현을 Apache-2.0 본체에 포함하거나 직접 링크하면
현재 배포 경계와 달라집니다.

## 근거

- 루트 `Package.swift`, `README*.md`, `docs/architecture/SCANNER_PLUGINS.md`는 SANE 구현·의존성·설정·배포를
  `negaflow-scanner-sane` 별도 프로젝트가 소유한다고 명시합니다.
- 기존 본체의 `ScannerKit`은 플러그인을 별도 프로세스로 실행하고 JSON/NDJSON 프로토콜 v1·v2로만
  통신합니다. 본체는 SANE 코드나 장치별 backend를 포함하지 않습니다.
- SANE upstream의 루트 [`COPYING`](https://gitlab.com/sane-project/backends/-/blob/master/COPYING)은
  프로젝트 라이선스를 GPL-2.0-or-later로 표시합니다. 개별 파일의 예외 조항까지 포함한 최종 배포 검토는
  플러그인 저장소의 책임으로 남기며, 이 ADR은 파생저작물 여부에 대한 법률 판단을 하지 않습니다.
- SANE 공식 [`backends` 저장소](https://gitlab.com/sane-project/backends/-/tree/master)는 scanner backend와
  `scanimage` frontend를 같은 upstream 배포물로 관리합니다.

## 결정

1. Windows 본체는 장치 비종속 외부 프로세스 플러그인 host만 구현합니다.
2. 기존 manifest schema와 scanner protocol v1·v2 의미, fail-closed 검사, 취소·출력 검증 계약을
   Windows에서도 재사용합니다.
3. SANE 구현, backend, 의존성, 구성, 설치 파일, 장치별 처리와 테스트는 별도 GPL 플러그인에 둡니다.
4. Windows 본체는 SANE 라이브러리를 링크하거나 앱 프로세스에 로드하거나 본체 배포물에 포함하지 않습니다.
5. WIA와 TWAIN은 현재 제품 기준선과 구현 대상이 아닙니다. 관련 `windows_docs`는 과거 후보 조사로만
   보존하며 채택된 아키텍처로 해석하지 않습니다.
6. SANE Windows 플러그인의 구현과 배포 방식은 사용자가 후속 작업으로 소유합니다. 본체 쪽 M15 작업은
   해당 플러그인에 종속되지 않는 host와 계약 검증까지만 담당합니다.

## 무결성 경계

일반 이미지 내용 SHA-256 설정은 기본 `끔`이지만 플러그인 공급망 검증과는 무관합니다. 플러그인 manifest와
실행 파일의 신원·변경 감지에 필요한 해시는 보안 경계이므로 사용자 이미지 옵션에 따라 꺼지지 않습니다.
Windows용 저장 위치, 소유권·ACL 정책, 서명 정책은 M15/M17에서 Windows 보안 모델에 맞춰 별도 ADR로
확정합니다.

## 현재 구현 범위

- 현재 Windows 코드에는 SANE, WIA, TWAIN 구현이 없습니다.
- 현재 UI에는 특정 scanner backend를 암시하는 설명 문구를 넣지 않습니다.
- 이번 결정에서 외부 코드, sample, icon, 장치 profile 또는 특허 구현을 복사하지 않았습니다.

## 결과

장치 지원은 기존 제품과 동일한 한 개의 외부 프로세스 경계를 유지합니다. Apache-2.0 본체는 SANE 배포물과
분리되고, scanner가 필요 없는 사용자는 GPL 플러그인을 설치하지 않아도 됩니다. 실제 Windows host의
프로세스 격리·경로·ACL·서명·timeout 검증은 아직 미구현입니다.
