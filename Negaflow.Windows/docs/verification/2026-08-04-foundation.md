# 2026-08-04 기반 검증 기록

## source 상태

- Windows 구현은 `Negaflow.Windows/` 아래 새 파일입니다.
- root worktree의 기존 tracked file은 수정하지 않았습니다.
- 현재 Windows 구현은 미커밋 상태이므로 build ID에 `-dirty`가 붙습니다.

## 실행한 주요 명령

```powershell
cmake --preset x64-debug --fresh
cmake --build --preset x64-debug --parallel
ctest --preset x64-debug
cmake --preset x64-release --fresh
cmake --build --preset x64-release --parallel
ctest --preset x64-release
cmake --preset arm64-debug --fresh
cmake --build --preset arm64-debug --parallel
cmake --preset arm64-release --fresh
cmake --build --preset arm64-release --parallel
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-interop.ps1 -Preset x64-debug
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-interop.ps1 -Preset x64-release
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-managed.ps1 -Preset arm64-debug
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-managed.ps1 -Preset arm64-release
dotnet format .\Negaflow.Windows.slnx --verify-no-changes --no-restore
```

추가로 실제 TIFF 전후 SHA-256/수정 시각/속성, WIC·ICM JSON 결과, PE header, DLL export table과
Release import dependency를 검사했습니다. TIFF SHA-256은 일회성 개발 검증에서 명시적으로 켠 것이며
제품 이미지 설정 기본값은 `끔`입니다.

## 결과 요약

| 검증 | 결과 |
|---|---|
| x64 Debug CTest | 18/18 통과 |
| x64 Release CTest | 18/18 통과 |
| ARM64 Debug cross-build | 통과 |
| ARM64 Release cross-build | 통과 |
| ARM64 native run | 실행하지 않음 |
| x64 CLI/DLL PE | `8664` |
| ARM64 CLI/DLL PE | `AA64` |
| DLL C exports | 두 architecture 모두 2개 allowlist와 일치 |
| Release CLI 직접 DLL dependency | `bcrypt.dll`, `SHLWAPI.dll`, `ole32.dll`, `mscms.dll`, `KERNEL32.dll` |
| VC++ Redistributable DLL dependency | 없음, static runtime |
| Visual Studio | Community 2026 18.8.2, complete/launchable, reboot 불필요, Windows App SDK C# component 확인 |
| compiler | MSVC 19.51.36252.0 |
| .NET SDK/runtime | 10.0.302 / 10.0.10 |
| x64 Interop contract | Debug/Release 각각 13개 assertion 통과 |
| ARM64 managed cross-build | Debug/Release 통과, 실제 실행 안 함 |
| managed PE | x64 `8664`, ARM64 `AA64` |
| NuGet graph | project reference 외 package 0개, locked restore 통과 |

WIC codec은 COM으로 활성화되므로 `WindowsCodecs.dll`이 정적 import 목록에 나타나지 않지만 Windows
기본 runtime API로 사용됩니다.

## x64 CTest 목록

1. `native.build_info`
2. `native.scalar_kernels`
3. `native.tiff_probe`
4. `native.image_content_hash`
5. `native.icc_profile`
6. `native.srgb_transfer`
7. `native.manual_negative_developer`
8. `native.scanner_to_working`
9. `native.scanner_stream_parity`
10. `native.scalar_conformance`
11. `cli.build_info`
12. `cli.negative_invert`
13. `native.wic_tiff_decode`
14. `cli.probe_tiff`
15. `cli.decode_tiff_wic`
16. `cli.prepare_scanner_tiff`
17. `cli.sha256_image`
18. `cli.develop_negative_tiff`

## scalar conformance

- fixture: `scalar-foundation-v1`
- algorithm: `shoulder-print-response-v4`
- case: 3
- finite result: 3
- failure: 0
- 최대 절대 오차: 약 `5.1856e-8`
- 최대 상대 오차: 약 `2.8809e-7`

## 이미지 I/O와 색상

- bounded Classic/BigTIFF preflight와 strip/tile 손상 입력 test
- Microsoft 기본 WIC TIFF decoder CLSID 고정
- path를 재개방하지 않는 동일 read-only `IStream` preflight/decode
- RGB/RGBA 16-bit 전체 decode와 ICC bytes 추출
- 정상 합성 LZW의 exact sample decode와 잘린 LZW segment의 preflight 거부
- 384 MiB decoded pixel을 주장하는 합성 입력을 64 MiB 한도로 버퍼 할당 전에 거부
- 5행 LZW의 2행 묶음/whole-frame exact 일치와 첫 행 뒤 cooperative cancellation
- sink 기반 row decode가 full decoded sample vector 없이 exact sample을 전달
- bounded ICC header/tag validation
- untagged scanner raw direct-linear 변환
- embedded RGB ICC → Windows ICM → sRGB16 → float32 linear-sRGB
- 64행 WIC→scanner-color streaming과 whole-frame 최종 float exact 일치
- 사용자 TIFF 15개 전체의 whole-frame/streaming exact pixel parity 15/15
- non-opaque alpha 명시 거부
- 사용자 TIFF 15개 전체 working 변환 15/15
- 이미지 SHA-256 기본 control은 파일 I/O 없이 `disabled`
- 명시적 CNG SHA-256 known-answer, multi-chunk, cancellation과 opt-in CLI
- 수동 Dmin color/B&W negative develop가 scalar reference와 exact 일치
- 저장소 TIFF decode→scanner color→develop CLI와 SHA 기본-off JSON

상세 코퍼스 결과는 [`2026-08-04-local-tiff-corpus.md`](2026-08-04-local-tiff-corpus.md)에 있습니다.

## C ABI와 architecture

두 Release DLL의 export는 다음 두 개뿐입니다.

- `nf_get_abi_version`
- `nf_get_build_info_v1`

색상·image I/O 라이브러리는 아직 공개 C ABI에 연결하지 않았으므로 ABI v1과 44바이트 구조체가
변하지 않았습니다.

C# `Negaflow.Interop`도 같은 두 export만 source-generated `LibraryImport`로 호출합니다. 관리 구조체의
크기 44바이트와 source digest offset 24를 별도로 검증하고, native DLL은 호출자가 지정한 절대 경로에서만
한 번 로드합니다.

## 남은 검증 공백

- 실제 ARM64 장치 실행
- ARM64 관리 Interop과 ARM64 native DLL의 실제 결합 실행
- native handle·event queue·cancellation 수명 검증
- macOS ColorSync golden과 ICM 비교
- LZW code stream 의미 검증, 손상 Deflate와 압축 해제 CPU deadline
- ASan/libFuzzer 또는 동등한 fuzz lane
- long path, sparse BigTIFF, SMB/removable volume
- tile decode, 최종 working/downstream streaming과 process memory budget
- output encode, ICC embed, readback와 atomic publish
