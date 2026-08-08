# 2026-08-04 압축 TIFF 사전 검사 검증 기록

기준일: 2026-08-04
대상: TIFF LZW code-stream 의미 검사, compressed-input budget과 Deflate 격리

## 검증 범위

- TIFF 구조 범위 검사와 LZW 의미 검사의 분리
- decoded-byte 한도를 compressed stream scan보다 먼저 적용
- Clear/EOI, literal·dictionary·forward code와 정확한 복원 길이
- TIFF early-change 9→10→11→12-bit와 entry 4094 한계
- trailing data, compressed-input budget과 cooperative cancellation
- 독립 validator가 없는 Deflate의 WIC 진입 전 격리
- CLI 압축 진단값 전달, 기존 SHA-256 기본 `끔`과 외부 dependency 0 유지
- x64 Debug/Release 실행, x64 관리 ABI, ARM64 native/managed 교차 빌드

## 실행한 명령

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1 -Preset x64-debug
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1 -Preset x64-release
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-interop.ps1 -Preset x64-debug
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-interop.ps1 -Preset x64-release
cmake --build --preset arm64-debug --clean-first
cmake --build --preset arm64-release --clean-first
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-managed.ps1 -Preset arm64-debug
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-managed.ps1 -Preset arm64-release
```

PE, export와 dependency는 Visual Studio 2026의 `dumpbin /headers`, `/exports`, `/dependents`로
확인했습니다. 사용자 코퍼스 명령은 실제 파일명과 경로가 로그·문서에 남지 않도록 PowerShell 배열로
전달했고 SHA-256을 호출하지 않았습니다.

## 자동 검증 결과

| 검사 | 결과 |
|---|---|
| x64 native Debug | CTest 26/26 통과 |
| x64 native Release | CTest 26/26 통과 |
| x64 managed ABI Debug/Release | 각각 13 assertion 통과 |
| ARM64 native Debug/Release | 전체 target 교차 빌드 통과, 실행 미검증 |
| ARM64 managed Debug/Release | solution 교차 빌드 통과, 실행 미검증 |
| PE | x64 CLI/DLL `8664`, ARM64 CLI/DLL `AA64` |
| DLL exports | 두 architecture 모두 `nf_get_abi_version`, `nf_get_build_info_v1`만 존재 |
| x64 Release CLI dependency | `bcrypt`, `SHLWAPI`, `ole32`, `mscms`, `KERNEL32`만 존재 |
| 새 runtime dependency | 0개 |

첫 ARM64 Debug 증분 build에서는 오래된 `tiff_probe.obj`의 COMDAT metadata 때문에 `LNK1163`이 한 번
발생했습니다. 같은 source를 해당 preset의 `--clean-first`로 전부 재생성한 뒤 Debug와 Release 전체 target이
통과했습니다. 실패를 코드 통과로 숨기지 않으며, 실제 ARM64 실행 증거도 아닙니다.

## 합성 압축 입력 결과

| 입력/경계 | 결과 |
|---|---|
| 1×1 RGB16 정상 LZW | 9 compressed byte, 8 code, 6 decoded byte 전체 accounting 후 WIC exact sample |
| 300행 정상 LZW | 9→10→11→12-bit early-change 전체 통과, 1,802 code와 1,800 decoded byte exact |
| 사전 한계 정상 LZW | entry 4094 뒤 12-bit Clear·9-bit reset, 3,843 code와 3,840 decoded byte exact |
| 정상 forward case | `code == next` 두 번, 5 code와 6 decoded byte exact |
| EOI 뒤 nonzero fill bit | 마지막 segment byte 안 fill bit는 허용, 의미 검사 완료 |
| Clear 누락 | `invalid_compressed_data`, WIC 전 거부, sample 0 |
| EOI 누락 | `invalid_compressed_data`, WIC 전 거부, sample 0 |
| 기대 복원 길이보다 1 byte 부족·초과 | 둘 다 `invalid_compressed_data`, WIC 전 거부, sample 0 |
| 정의되지 않은 forward code | `invalid_compressed_data`, WIC 전 거부, sample 0 |
| EOI 뒤 추가 byte | `invalid_compressed_data`, WIC 전 거부, sample 0 |
| LZW 8-byte 작업량 한도 | `compressed_data_limit_exceeded`, WIC 전 거부 |
| 이미 요청된 취소 | `cancelled`, WIC 전 종료 |
| 384 MiB decoded 출력을 주장하는 작은 LZW | decoded memory limit이 의미 scan보다 먼저 거부 |
| 정상 Deflate | `unsupported_layout`, WIC 전 격리 |
| 길이가 모순되는 Deflate | `unsupported_layout`, WIC 전 격리 |

Deflate 손상 fixture를 격리하기 전 진단에서는 현재 로컬 WIC가 성공과 원래 작은 sample을 반환했습니다.
이 관찰 때문에 정상 fixture도 예외로 허용하지 않았습니다. WIC가 모든 Deflate를 잘못 처리한다는 일반화는
하지 않습니다.

## 실제 TIFF read-only 재검증

사용자 TIFF 15개와 권리 확인된 저장소 fixture 1개, 총 16개를 x64 Release에서 whole-frame과 64행
streaming으로 각각 처리했습니다.

| 검사 | 결과 |
|---|---:|
| scanner→working whole/stream exact pixel parity | 16/16 |
| 사용자 LZW 의미 검사 후 decode | 6/6 |
| streaming 결과의 full decoded source 보유 | 0/16 |
| 최대 application-owned WIC copy buffer | 2,605,056 bytes |
| 최대 ICC conversion temporary | 3,907,584 bytes |
| 사용자 원본 크기·수정 시각·속성 변화 | 0/15 |
| 일반 이미지 SHA-256 계산 | 0 |

전체 parity의 단일 wall 관찰은 약 34.9초였습니다. 사용자 LZW 한 개의 CLI 관찰은 의미 검사와 WIC
whole-frame decode 약 1.66초, 64행 scanner→working 준비 약 2.61초였습니다. warm cache, 파일 시스템과
시스템 부하를 통제하지 않았으므로 benchmark나 성능 보증이 아닙니다. 결과 JSON은 compressed byte 전체,
복원 byte 전체, 0보다 큰 code 수와 검사 완료 boolean을 확인했고 경로·파일명·hash는 기록하지 않았습니다.

## 남은 제한

- Deflate는 독립 검증기가 없어 정상 입력도 현재 사용할 수 없습니다.
- 동기식 WIC `CopyPixels` 안쪽의 hard CPU deadline과 선점 취소는 없습니다.
- 512 MiB compressed-input 상한은 제품 전체 process memory/CPU reservation을 대신하지 않습니다.
- LZW validator는 WIC RGB16 allowlist의 사전 검사이며 범용 TIFF decoder가 아닙니다.
- fuzz/ASan, network `IStream`, multi-IFD와 실제 ARM64 Windows 실행은 아직 없습니다.
- 특허 조사는 제한적 공개 screen이며 법률 의견이나 완전한 FTO 결론이 아닙니다.
