# 네이티브 기반 구현

## 목적

WinUI나 GPU보다 먼저 실행 가능한 CPU 정답, architecture 정보와 좁은 ABI를 확보합니다. 현재 코드는
제품 전체가 아니라 이후 D3D11과 C# 셸이 의존할 최소 기반입니다.

## 구조

```text
src/Native/core
  build_info        build/source/CPU capability
  pixel             float32 image layout contract
  pointwise         exposure와 RGB matrix
  negative_inversion shoulder-print-response-v4
  tiff_probe        read-only container preflight

src/Native/color
  icc_profile       bounded ICC structure validation
  srgb_transfer     explicit extended-range sRGB EOTF

src/Native/imageio
  decoded_image     owned RGB16/RGBA16 model
  wic_tiff_decoder  Microsoft built-in TIFF adapter

src/Native/imaging
  scanner_to_working       source policy dispatcher
  linear_scanner_converter untagged scanner raw path
  icm_icc_converter        Windows ICM adapter

src/Native/abi
  negaflow_abi      versioned C ABI DLL

src/Cli
  main/commands     diagnostics split by responsibility
```

## ABI

C ABI v1의 공개 표면은 다음 두 symbol뿐입니다.

- `nf_get_abi_version`
- `nf_get_build_info_v1`

`nf_build_info_v1` 구조체는 44바이트이며 source SHA 필드 offset은 24입니다. dirty 여부는 구조체를
조용히 늘리지 않고 build-info JSON과 build ID에 기록합니다. 이후 이미지 handle/event API는 별도 ABI
version과 수명 테스트가 준비되기 전까지 추가하지 않습니다.

## 픽셀 계약

- linear-sRGB primaries, float32 RGBA
- RGB extended range 보존
- straight alpha, finite, `[0,1]`
- 좌상단 원점, pixel center `(x + 0.5, y + 0.5)`
- hidden clamp 금지
- NaN/Inf와 layout overflow는 명시 오류
- scalar reference는 precise floating point와 고정 statement order 사용

## CLI

```text
negaflow-cli --build-info
negaflow-cli --negative-invert <transmission> <dmin> <dmax> <color|bw>
negaflow-cli --probe-tiff <path>
negaflow-cli --decode-tiff-wic <path>
negaflow-cli --prepare-scanner-tiff <path>
```

CLI entry point는 `wmain`이므로 Windows Unicode 경로를 손실 없이 `std::filesystem::path`로 넘깁니다.
오류 JSON에는 사용자 전체 경로를 넣지 않습니다.

## architecture

- x64: Debug/Release configure, build, run, CTest
- ARM64: Debug/Release native target cross-build
- x86 target 없음
- ARM64 executable은 PE machine `AA64`
- 현재 호스트가 x64이므로 ARM64 runtime은 미검증

## 의존성

현재 runtime 제3자 dependency는 0개입니다. WIC, ICM, COM과 Win32는 Windows 기본 API입니다.
MSVC runtime은 정적으로 링크해 별도 VC++ Redistributable DLL 설치가 필요하지 않습니다. Release
CLI의 직접 import는 `bcrypt.dll`, `SHLWAPI.dll`, `ole32.dll`, `mscms.dll`, `KERNEL32.dll`뿐입니다.

정적 CRT는 설치 단순성을 얻는 대신 CRT 보안 수정 시 앱을 다시 빌드·배포해야 합니다. 향후 libtiff,
zlib, LittleCMS, SQLite 등은 OS API가 제품 계약을 충족하지 못한다는 재현 증거가 있을 때만 exact
version, 최소 feature, manifest와 notice를 함께 추가합니다.
