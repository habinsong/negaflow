# 2026-08-04 노출·대비·커브 수직 경로 검증

기준일: 2026-08-04
대상: M4 최소 tone scalar, 동적 band 측정, TIFF16/PNG16 CLI 연결

## 검증 범위

- macOS 처리 순서와 Float32 수식의 Windows scalar 이식
- 노출·기본 톤·파라메트릭 커브 적용 임계값과 사용자 입력 범위
- extended RGB의 tone-safe gamut 진입, 검정 anchor와 alpha 보존
- 작은 이미지 fixed fallback과 동적 `portable_area_v1` 측정
- 4% border, percentile index, band 간격과 측정 메모리 한도
- 실패 시 조정 pixel 폐기
- 기존 8개 인수 export의 no-op 호환
- 실제 decode→negative develop→tone→TIFF16/PNG16 검증 게시
- SHA-256 기본 `off`, 경로·file identity 값 미보고
- x64 Debug/Release 실행과 ARM64 Debug/Release 교차 빌드

## 실행한 명령

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1 -Preset x64-debug
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1 -Preset x64-release
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\build.ps1 -Preset arm64-debug
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\build.ps1 -Preset arm64-release
```

CLI 실제 연결은 권리 확인된 저장소 TIFF fixture와 ignored `out/verification/` 산출물로 확인했습니다.
사용자 TIFF 코퍼스는 이번 검증에서 읽거나 복사하지 않았습니다.

## 자동 검증 결과

| 검사 | 결과 |
|---|---|
| x64 native Debug | 후속 진단 체크포인트 포함 CTest 26/26 통과 |
| x64 native Release | 후속 진단 체크포인트 포함 CTest 26/26 통과 |
| x64 managed ABI Debug/Release | 각각 13 assertion 통과 |
| ARM64 native Debug/Release | tone test를 포함한 전체 target 교차 빌드 통과, 실행 미검증 |
| PE·ABI | x64 `8664`, ARM64 `AA64`, DLL export 두 개 유지 |
| x64 Release CLI dependency | `bcrypt`, `SHLWAPI`, `ole32`, `mscms`, `KERNEL32`만 존재 |
| 합성 고정 fixture | 3×2 exposure+basic+curve 6 pixel이 독립 Float32 기대값과 허용오차 내 일치 |
| 검정 anchor | negative contrast와 shadow curve 모두 absolute black 0 유지 |
| alpha/stride | fractional alpha exact 보존, row padding 미기록 |
| 동적 측정 | 64×64 합성 입력에서 4% border 제외 3,600 sample과 band exact 일치 |
| 측정 한도 | limit 초과 시 output pixel 폐기 |
| 사용자 범위 | exposure ±5, tone ±1 밖의 값은 거부하고 pixel 미공개 |

fixture 수치 허용오차는 absolute·relative 각각 `4e-6`입니다. 실제 macOS GPU runtime output golden이
아니라 기존 Metal 수식을 별도로 Float32 전사해 만든 저장소 합성 기준입니다.

## 실제 CLI 수직 경로

631×403 저장소 fixture에 exposure `0.5`, contrast `0.25`, curve
`0.1/-0.1/0.2/-0.2`를 적용한 x64 Release 한 번의 관찰값입니다.

| 값 | 결과 |
|---|---:|
| decode+color | 20,194 µs |
| manual develop | 30,517 µs |
| tone adjust | 42,874 µs |
| output encode+verify+publish | 37,829 µs |
| 전체 | 131,571 µs |
| curve sampling | `portable_area_v1`, 35,636 luma |
| measurement temporary | 285,088 bytes |
| TIFF structure/metadata/pixel/profile | 모두 `true` |
| source/artifact SHA mode | 모두 `off` |

같은 pipeline을 PNG16에도 실행해 structure/pixel/profile이 모두 `true`임을 확인했습니다. 기존 8개 인수
TIFF16 명령은 exposure/basic/curve 적용 여부가 모두 `false`, sampling mode `none`, `curve_bands: null`로
성공했습니다.
무조정 tone stage는 같은 x64 Release 관찰에서 10 µs였습니다.

무조정 TIFF와 조정 TIFF를 WIC로 다시 decode한 빠른 FNV-1a 진단 fingerprint는 각각
`71c18294563f3dff`, `ebaaaf55fd063f89`로 달랐고 치수·RGB16 layout·ICC byte 길이는 같았습니다. 이
fingerprint는 export 기본 작업에 포함되지 않으며 cryptographic hash가 아닙니다.

성공 JSON은 `ConvertFrom-Json`으로 검사했습니다. `source_path`, `destination_path`, `volume_serial`,
`file_index`, `source_sha256`, `artifact_sha256` 값 필드는 없었습니다. 관찰 방식 이름만 기록하며 실제
file identity 값은 기록하지 않습니다.

## 해석 제한

- 실제 macOS Core Image runtime output과 최종 pixel diff를 아직 만들지 않았습니다.
- 동적 band의 target·border·percentile은 같지만 Windows 면적 평균과 비공개 Core Image 다중 패스
  downsample은 bit-exact하다고 주장하지 않습니다.
- ARM64는 compile/PE 증거만 있고 실제 Windows ARM64에서 tone·WIC를 실행하지 않았습니다.
- 시간 값은 현재 PC의 단일 실행이며 benchmark나 성능 보증이 아닙니다.
- scalar 구현은 SIMD/GPU 최적화 전입니다.
- 후속 ADR-0010에서 stage process CPU와 진단 전용 versioned fingerprint를 추가했습니다. 실제 macOS
  runtime 비교는 여전히 없습니다.
