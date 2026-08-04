# M0~M3 기반 단계 상세

기준일: 2026-08-04

## M0 — 제품 기준선

### 만든 것

- macOS 구현 기준 commit `2fa1d6297378673b58b8bec72025e968ccc3125c`
- Windows 문서 조사 기준 commit `9be909c43edd7e04ba98cdc9d6a0c688739e343e`
- 두 기준 사이의 알려진 correctness delta
- bootstrap baseline manifest
- 현재 conformance에 사용하는 source asset SHA-256 목록

### 남은 것

- 전체 macOS surface와 상태 전이 manifest
- 전체 kernel/stage stable ID
- 실제 사진·ICC·export 기준 artifact의 권리 manifest
- LibRaw, Adobe RGB, installer, scanner 배포의 최종 포함/제외 결정

## M1 — Windows 저장소와 도구 체인

### 만든 것

- 별도 `Negaflow.Windows/` build root
- Visual Studio generator 기반 x64/ARM64 Debug/Release preset
- C++20 static core, `Negaflow.Native.dll`, console CLI
- 44바이트 C ABI v1과 두 개의 export symbol allowlist
- architecture와 CPU feature를 담은 build-info JSON
- `.vsconfig`, WinGet configuration, `global.json`, vcpkg manifest
- strict warning, precise floating-point, CTest 진입점
- static MSVC runtime과 OS DLL만 남긴 Release native dependency
- `.slnx`, 공통 managed build 정책과 architecture별 output
- source-generated `LibraryImport` 기반 `Negaflow.Interop`
- 절대 경로 native load, ABI version/layout 검증과 stable bootstrap failure
- 외부 package가 없는 Interop/Core project lock과 dual-RID WinUI component package lock

### 검증된 것

- x64 Debug/Release 실행
- ARM64 Debug/Release cross-build
- x64 PE `8664`, ARM64 PE `AA64`
- DLL export는 `nf_get_abi_version`, `nf_get_build_info_v1` 두 개
- vcpkg 빈 manifest의 x64/ARM64 restore
- Release CLI에서 `MSVCP140.dll`, `VCRUNTIME*.dll` dependency 없음
- x64 Debug/Release 관리 ABI 계약 13개 assertion 통과
- x64/ARM64 관리 assembly PE가 각각 `8664`/`AA64`
- Visual Studio Community instance에서 현재 ID의 Windows App SDK C# component 감지

### 남은 것

- 실제 ARM64 Windows 실행 lane
- hosted CI와 clean-machine restore evidence
- shader compiler, WARP config, packaging, artifact SBOM

## M2 — scalar reference

### 만든 것

- `Rgba32F` 16바이트 픽셀과 checked image view
- finite RGB/alpha, stride, capacity, overflow 검사
- 음수와 1 초과 RGB를 보존하는 exposure
- RGB 3×4 color matrix
- color/B&W `shoulder-print-response-v4` 네거티브 반전
- 채널별 수동 Dmin과 고정 response를 선택해 owned WorkingImage를 제자리 반전하는 작은 orchestration
- macOS 순서의 노출, sRGB-luma 기본 톤과 4-band 파라메트릭 커브 scalar
- macOS post-pipeline 첫 단계의 고정 64표본 DR/R/G/B 포인트 커브 scalar
- macOS post-pipeline 두 번째 단계의 고정 8대역 HSL Color Mixer scalar
- macOS post-pipeline 세 번째 단계의 고정 shadows/midtones/highlights Color Grading scalar
- macOS post-pipeline 네 번째 단계의 고정 R/G/B Primary Calibration scalar
- film-scan source 분기의 11종 profile·5% intensity·고정 RGB33 Film Emulation 색상 standalone scalar
- 같은 분기의 unquantized profile acutance와 11행 caller-owned separable Gaussian scratch
- 명시적 film/digital source route와 film-scan 색상→acutance fail-closed orchestration
- fixed fallback과 bounded `portable_area_v1` percentile 측정, 제자리 tone orchestration
- versioned 합성 fixture와 JSON conformance report
- AVX/OSXSAVE/AVX2/FMA 및 ARM64 NEON capability 식별

### 현재 수치 증거

- 합성 네거티브 반전 3 case
- 최대 절대 오차 약 `5.19e-8`
- 최대 상대 오차 약 `2.88e-7`
- x64 Debug/Release test 통과
- 3×2 tone Float32 fixture, 검정 anchor, alpha/stride와 64×64 percentile 계약 통과
- 3×2 point curve fixture의 LUT 표본과 24개 RGBA 값, 64/65개 제어점 경계 통과
- 4×3 Color Mixer fixture의 48개 RGBA 값, 24개 control 범위·회색 gate·대역 순서 통과
- 4×3 Color Grading fixture의 48개 RGBA 값, 세 구간·identity·pivot·처리 순서 통과
- 4×3 Primary Calibration fixture의 48개 RGBA 값, 여섯 control·회색 gate·처리 순서 통과
- 4×3 Film Emulation 색상 fixture의 48개 RGBA 값과 11종 profile node signature, 431,244바이트 cube 계약 통과
- macOS Core Image 두 run의 12,912개 numeric value exact 반복, 색상 최대 절대 오차 `0.0018888685`
- Ektar/Provia/Velvia impulse·step 6개 acutance signature 최대 절대 오차 `0.00015372`, conformance 36개 값
- film-scan route가 수동 색상→acutance 결과와 bit-exact이며 cube 재사용·낮은 강도·identity·오류 폐기 통과
- x64 Debug/Release CTest 각각 33/33, ARM64 Debug/Release 전체 target 교차 빌드 통과
- ARM64에서는 같은 source가 컴파일되지만 수치 실행은 아직 미검증

### 남은 것

- Film Look CLI recipe/report와 catalog source metadata 연결, cube 경계·fractional alpha 확대
- blur, local contrast, histogram, morphology, defect, crop/resize와 digital-film 전체 그래프
- forced scalar/base/AVX2 dispatch와 실제 NEON 실행
- ROI/halo/cancellation 계약
- macOS baseline generator와 더 넓은 golden corpus

## M3 — 이미지 I/O 시작

### 이번에 만든 것

- Windows 읽기 전용 핸들 기반 TIFF 구조 검사
- Classic TIFF와 BigTIFF, little/big endian header/IFD 처리
- 폭·높이·bit depth·sample format·compression·orientation·planar·ICC 길이 수집
- strip/tile 배열 범위, 실제 segment offset+byte count, 예상 segment 수 검증
- 모든 크기 계산의 checked 64-bit 처리
- IFD, segment, metadata, ICC, RGBA32F working-memory 상한
- 다중 IFD를 조용히 무시하지 않고 명시적 오류로 분류
- Unicode 경로를 받는 `wmain` CLI와 `--probe-tiff`
- Microsoft 기본 WIC TIFF decoder vendor/CLSID 고정
- 같은 read-only `IStream`을 사용하는 preflight와 WIC decoder
- RGB/RGBA 16-bit none/LZW full pixel decode와 ICC bytes 추출
- 정상 합성 LZW exact sample decode와 잘린 LZW segment의 preflight 거부
- decoded pixel 크기의 checked 계산과 buffer 할당 전 상한 적용
- strip/tile compressed byte 합계와 512 MiB LZW 입력 작업량 상한
- TIFF 6.0의 Clear/EOI, 유효 code reference, 9→10→11→12-bit early-change, 4094 사전 한계,
  strip별 기대 복원 byte 수와 trailing data를 확인하는 독립 LZW 의미 검사
- LZW 의미 검사 중 `stop_token` 취소와 code/압축/복원 byte 진단값
- 독립 무결성 검증기가 없는 Deflate tag 8의 WIC 진입 전 fail-closed 격리
- 선택적 WIC 행 묶음, 단조 row progress, 묶음 사이 cooperative cancellation과 부분 sample 폐기
- `WicTiffRowSink` streaming API와 full decoded sample vector 없는 소비 경로
- ICC header/tag table bounded validation
- ICC 없는 scanner raw의 direct linear-sRGB float 변환
- embedded RGB ICC의 Windows ICM relative-colorimetric 변환과 sRGB EOTF
- 재사용 ICM transform과 chunk temporary만 사용하는 scanner→working row 경로
- non-opaque alpha 명시 거부와 16-bit intermediate provenance
- 이미지 content SHA-256 기본 `off`와 명시적 CNG opt-in·cancel/progress
- extended-linear working→opaque sRGB16 최종 경계 변환과 clipping 계수
- Microsoft 기본 WIC PNG encoder/decoder 고정, 등록 sRGB ICC 삽입과 exact pixel/profile readback
- Microsoft 기본 WIC TIFF encoder/decoder 고정, 무압축 RGB16과 exact pixel/profile readback
- Classic TIFF 단일 IFD 최소 metadata tag allowlist와 descriptive/private tag fail-closed 거부
- 같은 디렉터리 `CREATE_NEW` staging, flush, 기존 목적지 비덮어쓰기 단일 파일 게시
- content를 읽지 않는 source file ID·크기·최종 수정 시각 전후 관찰
- PNG16/TIFF16 공통 decode·color·develop·tone orchestration과 단계별 byte·memory·wall/process-CPU report
- 진단 전용 scanner→working/develop/tone active RGBA32F min/max·versioned 비암호 fingerprint
- `--decode-tiff-wic`, `--prepare-scanner-tiff`, `--sha256-image`, `--export-developed-png16`,
  `--export-developed-tiff16` CLI

### 검증한 입력

- 합성 little-endian Classic TIFF
- 합성 big-endian Classic TIFF
- 합성 big-endian BigTIFF
- 합성 tiled Classic TIFF와 tile geometry/count 불일치
- 잘린 header, 잘못된 byte order, 범위 밖 IFD/tag/strip, 중복 tag
- oversized ICC 주장, working-memory 초과, 다중 IFD
- 저장소의 실제 16-bit big-endian TIFF 4개
- 수동 구성한 정상 RGB16 LZW와 384 MiB 확장을 주장하는 작은 손상 fixture
- 9→10→11→12-bit 경계를 모두 지나는 정상 LZW와 Clear/EOI 누락, 잘못된 forward code, trailing
  data, 압축 입력 상한, 사전 취소 합성 fixture
- 정상·손상 Deflate 합성 fixture가 모두 WIC 전에 같은 격리 경계로 거부됨
- 사용자 scanner의 5088×3401 RGB/RGBA 16-bit TIFF 15개, 약 1.68GB
- 사용자 코퍼스 WIC decode 15/15, working 변환 15/15, 원본 불변 15/15
- 사용자 코퍼스 whole-frame/64행 streaming 최종 float exact 일치 15/15
- 이미지 SHA 기본-off 무 I/O와 opt-in 15/15, 원본 관측값 불변
- 합성 working image의 PNG16 구조·전체 pixel·ICC exact readback과 publish 경합 보존
- 권리 확인된 저장소 TIFF fixture의 decode→color→develop→PNG16 게시
- 합성 working image의 무압축 TIFF16 구조·최소 IFD·전체 pixel·ICC exact readback과 목적지 보존
- 권리 확인된 저장소 TIFF fixture의 decode→color→develop→TIFF16 게시와 source 상태 불변 관찰

### 남은 것

- 다중 IFD 사용자 정책과 bounded chain traversal
- 독립 Deflate 검증 또는 최소 dependency gate, WIC 압축 해제 CPU budget·deadline
- ColorSync golden과 Windows ICM 수치 비교
- 필요성이 입증될 때만 libtiff/LittleCMS dependency 결정
- tile decode, 최종 working/output downstream streaming과 process memory budget
- M4 tone의 실제 macOS runtime pixel diff·cross-platform 허용오차 manifest와 catalog transaction·복구
- fuzzing/ASan corpus와 실제 대형 scanner TIFF
