# ADR-0010: 저비용 CPU 시간과 진단 전용 픽셀 fingerprint를 분리한다

- 상태: 채택
- 날짜: 2026-08-04

## 배경

M4 단일 이미지 경로에는 wall time뿐 아니라 CPU 사용량과 단계별 수치 비교 증거가 필요합니다. 다만 일반
export에서 이미지 전체를 다시 훑거나 파일 전체 SHA-256을 계산하면 사용자가 요청한 빠른 로컬 작업 경계와
충돌합니다. WIC와 ICM은 내부 작업 스레드를 사용할 수 있으므로 현재 호출 스레드만 재는 값도 실제 단계
비용을 과소 보고할 수 있습니다.

## 결정

1. 기본 PNG16/TIFF16 export는 `GetProcessTimes(GetCurrentProcess())` 전후 snapshot으로
   decode+color, develop, tone, output과 전체 CPU 시간을 기록합니다.
2. CPU 값은 프로세스 모든 스레드의 user+kernel 합계입니다. 여러 코어가 동시에 일하면 wall time보다 클
   수 있습니다. API 실패나 감소·overflow는 export 실패로 바꾸지 않고 JSON `null`로 기록합니다.
3. FILETIME의 100 ns 단위 차이를 합산한 뒤 정수 microsecond로 내립니다. 이 단위는 표시 단위이며 실제
   scheduler 계측 해상도가 100 ns라는 뜻은 아닙니다.
4. 기본 export에는 픽셀 통계, FNV 또는 SHA-256을 위한 full-frame scan을 추가하지 않습니다. source와
   artifact SHA-256은 계속 `off`입니다.
5. 기존 개발 진단 명령 `--develop-negative-tiff`만 scanner→working, develop, tone 각 단계의 active
   pixel min/max와 `fnv1a64-rgba32f-bits-le-v1` fingerprint를 보고합니다. stride padding은 제외하고 각
   RGBA32F bit pattern을 little-endian byte 순서로 고정합니다. tone이 무연산이면 bit-identical develop
   통계를 재사용해 세 번째 scan을 생략합니다.
6. FNV fingerprint는 빠른 회귀 비교용 비암호 값이며 security, 파일 identity, 무결성 증거 또는 사용자
   이미지 SHA-256을 대체하지 않습니다. 치수·min/max·수치 허용오차 보고서와 함께 해석합니다.
7. 공급망, installer, 실행 파일, plugin과 bundled resource의 필수 SHA-256 정책은 바꾸지 않습니다.

## 결과

기본 export의 새 비용은 작은 Win32 snapshot 호출뿐입니다. 두세 번의 full-frame scan은 사용자가 명시한
개발 진단 명령 안에만 남습니다. `negaflow-conformance`는 기존 negative fixture와 함께 고정 tone fixture의
24개 RGBA 값을 허용오차로 보고하므로, bit fingerprint가 달라졌을 때 수치 차이를 별도로 판단할 수 있습니다.

## 권리와 의존성

Windows SDK의 `GetProcessTimes`와 기존 저장소 소유 FNV 구현만 사용합니다. RFC 9923의 reference code를
복사하지 않았고 새 제3자 코드나 runtime dependency를 추가하지 않았습니다. 제한적인 공개 특허 검색에서는
FNV를 사용하는 응용과 수정·병렬 FNV 특허가 확인됐지만 이번 구현은 그 병렬 구조나 응용 claim을 사용하지
않습니다. 이는 법률 자문이나 완전한 FTO 결론이 아닙니다.

상세 근거와 한계는 `research/pipeline-diagnostics-sources.md`에 기록합니다.
