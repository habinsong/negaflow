# 파이프라인 진단 공식 근거와 권리 검토

기준일: 2026-08-04

## Windows CPU 시간

- [GetProcessTimes](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-getprocesstimes)
  는 프로세스 각 스레드의 kernel/user 실행 시간을 합산하고 `FILETIME` 100 ns 단위로 반환합니다. 여러
  코어를 쓰면 user time이 실제 경과 시간보다 클 수 있다고 명시합니다.
- [GetCurrentProcess](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-getcurrentprocess)
  는 현재 프로세스 pseudo handle을 반환하며 닫을 필요가 없습니다.
- [고해상도 시간 stamp 취득](https://learn.microsoft.com/en-us/windows/win32/sysinfo/acquiring-high-resolution-time-stamps)
  은 경과 시간 측정과 CPU 소비 측정이 다른 질문임을 구분하는 참고입니다. 기존 wall time은 단조
  `std::chrono::steady_clock`을 유지하고 CPU 누적값만 별도로 추가했습니다.

이번 구현은 현재 thread의 `GetThreadTimes`가 아니라 프로세스 합계를 씁니다. WIC/ICM 내부 worker의 CPU를
누락하지 않기 위한 선택이며, 다른 동시 작업이 같은 CLI 프로세스에 들어오는 미래 구조에서는 stage
귀속이 흐려질 수 있으므로 다시 검토해야 합니다.

## 빠른 비암호 fingerprint

- [RFC 9923: The FNV Non-Cryptographic Hash Algorithm](https://www.rfc-editor.org/rfc/rfc9923.html)은 FNV를
  빠르고 작은 비암호 hash로 설명합니다. Internet Standards Track 규격은 아니며 security hash로
  해석하지 않습니다.
- 구현은 RFC의 reference C source를 복사하지 않았습니다. 이 저장소에 이미 있던 작은 byte별 XOR·multiply
  연산을 active RGBA32F little-endian bit stream에 고정하고 합성 기대값으로 독립 검증했습니다.
- RFC reference source의 재배포 조건은 이번 저장소 코드에 유입되지 않습니다. 새 third-party payload나
  notice 대상도 없습니다.

## 제한적 특허 화면

- [US10545758B2](https://patents.google.com/patent/US10545758B2/en)는 수정 FNV를 예로 든 병렬 hash 처리
  구조입니다. 이번 scalar byte loop는 병렬 execution-unit 구조를 구현하지 않습니다.
- [JP5288129B2](https://patents.google.com/patent/JP5288129B2/en)는 데이터베이스 정보 추출에서 FNV를
  사용할 수 있다고 설명합니다. 이번 코드는 데이터베이스 식별자 추출을 구현하지 않습니다.

검색 결과는 공개 문서의 제한적 name/claim screen일 뿐이며 특허 유효성, 관할권 또는 완전한 자유실시를
보증하지 않습니다. 새 알고리즘이나 third-party code를 추가하지 않았다는 engineering 기록으로만 씁니다.

## 저작권·라이선스 결론

- Windows API 호출은 Windows SDK/운영체제 경계이며 새 runtime library를 추가하지 않습니다.
- 테스트 입력과 기대값은 저장소 소유 합성 fixture입니다.
- 외부 이미지, ICC profile, benchmark corpus 또는 reference source code를 추가하지 않았습니다.
- Apache-2.0 core의 기존 dependency 정책과 공급망 SHA-256 정책은 그대로입니다.
