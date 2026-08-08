# 파이프라인 CPU 시간과 빠른 픽셀 진단

## 기본 export 경계

PNG16/TIFF16 export는 기존 `std::chrono::steady_clock` wall time과 함께 다음 JSON을 냅니다.

```text
cpu_time_source: get_process_times
cpu_time_scope: process_user_plus_kernel_all_threads
stages.*.wall_microseconds
stages.*.cpu_microseconds
total_wall_microseconds
total_cpu_microseconds
```

CPU snapshot은 `process_cpu_time.h/.cpp`가 소유합니다. Win32 `FILETIME`의 kernel/user 누적값을 각각
단조성 검사하고 두 delta를 overflow 검사 뒤 합산합니다. 어느 snapshot이든 실패하면 해당 구간은
`null`이고 export 결과와 게시 artifact는 그대로 유지됩니다.

프로세스 범위를 선택한 이유는 WIC encode/decode와 ICM 변환이 호출 스레드 밖에서 수행한 CPU도 포함하기
위해서입니다. 이 값은 여러 스레드가 병렬 실행되면 wall time보다 클 수 있으며, 성능 보증이 아니라 같은
환경에서 회귀를 찾는 관찰값입니다.

## 진단 전용 단계 통계

`--develop-negative-tiff`는 파일을 만들지 않는 개발 진단 명령입니다. 기존 형식은 그대로 유효하고 여섯
tone 값을 모두 추가할 수 있습니다.

```powershell
negaflow-cli --develop-negative-tiff <source> <dmin-r> <dmin-g> <dmin-b> <color|bw>
negaflow-cli --develop-negative-tiff <source> <dmin-r> <dmin-g> <dmin-b> <color|bw> <exposure> <contrast> <curve-highlights> <curve-lights> <curve-darks> <curve-shadows>
```

두 번째 형식의 tone 값은 source를 열기 전에 제품 범위 노출 `[-5, 5]`, 나머지 `[-1, 1]`로 검증합니다.
성공 JSON의 `stage_statistics`는 다음 세 상태를 각각 보고합니다.

- scanner ICC/linear 정책을 적용한 working RGBA32F
- 수동 Dmin negative develop 직후
- exposure/basic/parametric tone 직후

각 상태에는 4채널 min/max와 `pixel_fingerprint_fnv1a64`가 있습니다. fingerprint 계약은
`fnv1a64-rgba32f-bits-le-v1`이고 active pixel만 row-major RGBA 순서로 읽습니다. stride padding은
min/max와 fingerprint 모두에서 제외하며 잘못된 layout이나 non-finite active pixel은 통계를 공개하지
않고 거부합니다. 이 계산은 의도적으로 full-frame scan이므로 기본 export에는
사용하지 않습니다. tone이 무연산이면 develop 통계를 재사용해 2회, 실제 적용되면 3회 scan하며 JSON은
실제 횟수와 추가 full-frame allocation 0바이트를 명시합니다.

## SHA-256과의 분리

성공 JSON은 `pixel_fingerprint_cryptographic:false`를 명시합니다. FNV는 충돌 저항을 제공하지 않으며
보관 검증, 외부 전달, 중복 확정 또는 공격자 입력의 무결성 판단에 사용하지 않습니다. 일반 이미지
SHA-256은 계속 기본 `off`이고 명시적 `--sha256-image` 작업만 파일 전체를 읽습니다. 기존
`--decode-tiff-wic`과 `--prepare-scanner-tiff`의 빠른 fingerprint도 각각 u16/working RGBA32F algorithm
version과 `cryptographic:false`를 함께 보고합니다.

## 수치 적합성

`negaflow-conformance`는 다음 두 합성 계약을 한 보고서에 포함합니다.

- `scalar-foundation-v1`: negative inversion 3개 anchor
- `tone-mapping-scalar-v1`: exposure+basic+curve 3×2 RGBA, 총 24개 값

tone 허용오차는 absolute/relative 각각 `4e-6`입니다. 이는 저장소 소유 수식 fixture이며 실제 macOS
Core Image runtime golden이나 동적 downsample bit-exact 증거는 아닙니다.
