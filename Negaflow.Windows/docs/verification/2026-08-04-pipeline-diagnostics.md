# 2026-08-04 파이프라인 CPU 시간·단계 진단 검증

기준일: 2026-08-04
대상: M4 stage CPU report, 진단 전용 RGBA32F 통계, tone conformance 확장

## 검증 범위

- `GetProcessTimes` snapshot 성공, FILETIME 변환, 감소·overflow·실패 처리
- decode+color, develop, tone, output과 전체 user+kernel CPU microseconds JSON
- API 실패 시 `null`이고 export 성공 여부와 분리되는 계약
- active pixel만 쓰는 versioned FNV-1a64와 stride padding 비의존성
- scanner→working, develop, tone의 단계별 min/max/fingerprint
- tone 인수 범위의 source 접근 전 거부
- 기존 무조정 진단 명령 호환
- negative와 tone 합성 fixture의 단일 conformance report
- SHA-256 기본 `off`와 기본 export full-frame 통계 scan 부재

## 실행한 명령

```powershell
cmake --preset x64-debug
cmake --build --preset x64-debug
ctest --preset x64-debug
cmake --preset x64-release
cmake --build --preset x64-release
ctest --preset x64-release
cmake --preset arm64-debug
cmake --build --preset arm64-debug
cmake --preset arm64-release
cmake --build --preset arm64-release
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-interop.ps1 -Preset x64-debug
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-interop.ps1 -Preset x64-release
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-managed.ps1 -Preset arm64-debug
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-managed.ps1 -Preset arm64-release
```

CLI 연결은 권리 확인된 저장소 TIFF fixture와 ignored `out/verification/` 산출물만 사용했습니다. 사용자 TIFF
코퍼스는 이번 체크포인트에서 읽거나 복사하지 않았습니다.

## 자동 검증 결과

| 검사 | 결과 |
|---|---|
| x64 native Debug/Release | CTest 각각 26/26 통과 |
| CPU 시간 단위 계약 | 100 ns 합산 변환, unavailable·감소·overflow와 live snapshot 통과 |
| pixel 통계 계약 | 고정 FNV 기대값, min/max와 서로 다른 padding의 동일 결과 통과 |
| tone conformance | RGBA 24개 finite, failure 0, x64 관찰 최대 absolute/relative error 0 |
| x64 managed ABI Debug/Release | 각각 13 assertion 통과 |
| ARM64 native Debug/Release | 전체 target 교차 빌드 통과, 실행 미검증 |
| ARM64 managed Debug/Release | solution 교차 빌드 통과, 실행 미검증 |
| PE | x64 CLI/DLL `8664`, ARM64 CLI/DLL `AA64` |
| DLL exports | 두 architecture 모두 `nf_get_abi_version`, `nf_get_build_info_v1`만 존재 |
| x64 Release CLI dependency | `bcrypt`, `SHLWAPI`, `ole32`, `mscms`, `KERNEL32`만 존재 |

## 실제 Release 관찰

631×403 저장소 fixture에 exposure `0.75`, contrast `0.35`, curve
`0.30/-0.25/0.20/0.40`을 적용한 한 번의 x64 Release 관찰입니다.

| TIFF16 단계 | wall | process CPU |
|---|---:|---:|
| decode+color | 20,759 µs | 31,250 µs |
| manual develop | 30,163 µs | 31,250 µs |
| tone adjust | 44,256 µs | 31,250 µs |
| output convert+encode+verify+publish | 39,954 µs | 46,875 µs |
| 전체 | 135,258 µs | 140,625 µs |

TIFF structure/metadata/pixel/profile과 PNG structure/pixel/profile은 모두 `true`였습니다. 같은 PNG16
실행의 전체 wall/CPU는 159,720/156,250 µs였습니다. 두 출력 모두 source/artifact SHA mode는 `off`,
source 상태 관찰은 unchanged였습니다. 이 값은 warm-cache 여부와 시스템 부하를 통제하지 않은 단일
관찰이며 benchmark나 제품 성능 보증이 아닙니다.

진단 명령은 scanner→working, develop, tone의 세 fingerprint가 모두 달라 단계 변화가 실제로 기록됨을
확인했습니다. 값 자체는 비암호 진단값이며 문서에 원본 경로, file identity나 SHA-256 값을 남기지
않았습니다. 잘못된 tone 범위는 존재하지 않는 source를 지정해도 `invalid_tone_adjustment_parameter`로 먼저
거부됐습니다. 무조정 진단은 develop 통계를 재사용해 full-frame scan 2회, 실제 tone 진단은 3회였고 두
경로 모두 통계용 추가 full-frame allocation은 0바이트였습니다.

## 남은 제한

- 프로세스 CPU 시간은 모든 스레드 합계라 병렬 실행 시 wall보다 클 수 있고 짧은 stage에서는 관찰
  granularity 때문에 0 또는 큰 계단값이 나올 수 있습니다.
- 기본 export에는 fingerprint scan이 없습니다. 단계 통계는 명시적 개발 진단의 추가 비용입니다.
- FNV-1a64는 충돌 가능한 비암호 값이며 SHA-256, 파일 identity나 보관 무결성 증거가 아닙니다.
- float bit fingerprint가 architecture 사이에서 다르면 즉시 실패로 단정하지 않고 수치 허용오차 report로
  원인을 확인해야 합니다.
- 실제 macOS runtime golden·동적 Core Image downsample·최종 pixel diff는 아직 없습니다.
- ARM64는 교차 빌드와 PE 증거만 있고 실제 ARM64 Windows 실행은 아직 없습니다.
