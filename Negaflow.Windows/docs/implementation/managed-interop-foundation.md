# 관리 코드 Interop 기반

기준일: 2026-08-04
범위: .NET 10 셸이 네이티브 C ABI를 안전하게 찾고 버전을 확인하는 첫 부트스트랩

## 목적

WinUI 화면보다 먼저 C#과 `Negaflow.Native.dll` 사이의 실제 이진 경계를 검증합니다. 현재 구현은
engine/session/canvas handle이나 픽셀을 노출하지 않습니다. 공개 C ABI의 두 bootstrap 함수만 소비하며,
UI 상태와 이미지 알고리즘은 이 assembly에 넣지 않습니다.

```text
Negaflow.Interop
  NativeLibraryLoader     절대 경로 DLL 1회 로드와 import resolver
  NativeMethods           source-generated LibraryImport 선언 2개
  NativeAbiReader         ABI version·layout·build-info 검증
  NativeEngineBootstrap   load/export/architecture 오류 분류

Interop.ContractTests
  관리 구조체 layout, 경로 정책, 실제 x64 DLL 호출 검증
```

## DLL 로드 정책

- 호출자는 완전한 절대 경로를 전달해야 합니다.
- 마지막 파일 이름은 정확히 `Negaflow.Native.dll`이어야 합니다.
- 검증한 절대 경로를 `NativeLibrary.Load`에 전달합니다.
- assembly별 단일 `SetDllImportResolver`를 등록한 뒤 `LibraryImport`는 미리 로드한 handle만 사용합니다.
- 다른 경로의 DLL로 같은 process에서 바꾸는 hot reload는 거부합니다.
- P/Invoke stub이 process 종료까지 handle을 사용할 수 있으므로 성공한 handle은 중간에 해제하지 않습니다.

이 정책은 현재 작업 디렉터리나 `PATH`에서 이름이 같은 DLL을 우연히 고르는 경로를 공개 API에서
제거합니다. 서명·payload manifest·dependency hash 검증은 배포 단계에서 추가해야 하며, 절대 경로만으로
설치 무결성이 완성됐다고 보지 않습니다.

## ABI 매핑

- C `uint32_t`는 C# `uint`로 매핑합니다.
- 호출 규약은 `CallConvCdecl`로 명시합니다.
- `nf_build_info_v1`은 blittable fixed buffer 구조체로 두며 관리 코드에서도 크기 44바이트와
  SHA 필드 offset 24를 검사합니다.
- 지원 ABI는 major `0`, minimum minor `1`입니다. major 불일치와 더 오래된 minor를 거부합니다.
- native export가 반환한 version과 build-info 내부 version이 다르면 contract violation입니다.
- unknown architecture/compiler와 비어 있는 source digest를 거부합니다.

공개 결과는 immutable `NativeBuildInfo`로 복사됩니다. raw native 구조체는 Interop assembly 밖으로
나가지 않습니다.

## 오류 경계

다음 부트스트랩 실패를 안정적인 enum으로 구분합니다.

- load failure
- 잘못된 binary format 또는 process/DLL architecture mismatch
- required export 누락
- ABI incompatibility
- native status failure
- layout 또는 build-info contract violation

경로가 상대 경로이거나 파일 이름이 틀린 경우는 호출자 계약 위반이므로 `ArgumentException`으로 남깁니다.
사용자 표시 문자열과 현지화는 이후 Shell이 이 오류 분류를 받아 소유합니다.

## 빌드와 의존성

- SDK: .NET `10.0.302`, runtime `10.0.10`
- source generator: SDK 내장 `LibraryImport`
- 외부 NuGet package: 0개
- 각 managed project에 `packages.lock.json`을 두고 locked restore를 사용
- x64와 ARM64 `PlatformTarget` 및 output을 분리

Microsoft의 공식 [native interop 권장 사항](https://learn.microsoft.com/en-us/dotnet/standard/native-interop/best-practices),
[P/Invoke source generation](https://learn.microsoft.com/en-us/dotnet/standard/native-interop/pinvoke-source-generation),
[native library loading](https://learn.microsoft.com/en-us/dotnet/standard/native-interop/native-library-loading)을
계약 근거로 사용했습니다. 예제 코드를 복사하거나 새 runtime package를 포함하지 않았습니다.

## 검증된 것

- x64 Debug/Release 실제 `Negaflow.Native.dll` load와 두 export 호출
- 각 구성에서 13개 관리 ABI assertion 통과
- x64 관리 DLL PE machine `8664`
- ARM64 Debug/Release 관리 교차 빌드
- ARM64 관리 DLL PE machine `AA64`
- locked restore와 빈 외부 package graph

ARM64 관리 코드와 ARM64 native DLL의 실제 결합 실행은 ARM64 Windows 장치에서 아직 검증하지 않았습니다.
Git metadata가 없는 source archive build에서는 source commit을 별도로 주입하지 않으면 현재의 완전성 검사가
실패합니다. 배포 build provenance 단계에서 이를 명시적으로 해결해야 합니다.

## 의도적으로 아직 하지 않은 것

- WinUI project와 XAML
- opaque handle과 `SafeHandle`
- native event queue와 cancellation
- engine/session/canvas lifecycle
- native DLL 서명·hash·asset manifest 검증
- self-contained publish와 installer staging

실제 native 소유 handle이 C ABI에 생기기 전에 빈 `SafeHandle` 계층을 미리 만들지 않습니다.
