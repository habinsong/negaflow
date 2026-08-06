# Windows CI 계획 — 빠른 게이트 설계

기준일: 2026-08-06
상태: 계획. 아직 구현하지 않았습니다.

## 문제

`.github/workflows/ci.yml`의 잡 4개가 전부 `runs-on: macos-26`입니다. 약 26,700줄 Windows 트리
(C++ 18,788 / 헤더 2,867 / C# 3,942 / XAML 1,138)가 CI에서 **한 번도 빌드·테스트되지 않습니다.**
현재 검증은 전부 개발자 로컬 머신에서만 이뤄집니다.

provenance·라이선스 게이트는 macOS `static` 잡이 `Negaflow.Windows/src`와 `tests`까지 검사하므로
권리 쪽 공백은 없습니다. 비어 있는 것은 **빌드·테스트 CI**입니다.

## 설계 목표

**PR 피드백 8분 이내, 목표 5분.** 30분~1시간짜리 게이트는 만들지 않습니다. 아래 시간 예산을 넘기는
제안은 채택하지 않습니다.

## 실측 작업 시간

로컬 워크스테이션(x64, VS 18.8.2) 실측입니다. CI 러너는 이보다 느리지만 배수는 크지 않습니다.

| 작업 | 실측 |
|---|---:|
| 네이티브 configure (VS generator) | 3.3s |
| 네이티브 clean build x64 Release (테스트 exe 25개 포함 전체 타깃) | 64.1s |
| `ctest` x64 Release (37 test) | 4.8s |
| 관리 solution 전체 build (7 project, Release x64) | 12.3s |
| 관리 테스트 2종 실행 (205 + 45 assertion) | 1초 미만 |
| 셸 x64 clean build | 11.8s |

**실제 계산 작업은 합계 약 95초입니다.** 즉 CI가 30분 걸린다면 그건 컴파일 때문이 아니라 설계
때문입니다. 시간은 러너 부팅, 체크아웃, SDK 설치, NuGet 복원에서 나갑니다. 계획의 초점은 컴파일
최적화가 아니라 **그 오버헤드를 줄이고 잡을 병렬로 두는 것**입니다.

## 툴체인 제약 (선결 과제)

`CMakePresets.json`이 generator를 `"Visual Studio 18 2026"`으로 고정합니다. GitHub 호스팅
`windows-2025` 이미지에는 VS 2026이 없습니다. **이 프리셋 그대로는 CI에서 configure가 실패합니다.**

`CMakeLists.txt`에는 MSVC 버전 고정이 없습니다. 요구사항은 C++20과 정적 CRT
(`CMAKE_MSVC_RUNTIME_LIBRARY`)뿐이므로 generator만 분리하면 됩니다.

해결: CI 전용 configure 프리셋을 Ninja로 추가합니다.

```json
{
  "name": "ci-x64-release",
  "generator": "Ninja",
  "binaryDir": "${sourceDir}/out/build/native/ci-x64-release",
  "cacheVariables": { "BUILD_TESTING": "ON", "CMAKE_BUILD_TYPE": "Release" }
}
```

Ninja는 VS에 번들로 들어 있고 GitHub 러너 이미지에도 있습니다. MSVC 환경은
`ilammy/msvc-dev-cmd`(또는 `vcvarsall.bat` 직접 호출)로 잡습니다. VS generator보다 빠르고 러너의
VS 버전에 덜 묶입니다.

부수 효과로 CI가 로컬과 **다른 툴셋**으로 컴파일하게 됩니다. 이식성 검증에는 오히려 이득이지만,
"CI 초록 = 로컬 초록"이 아니라는 점은 인지해야 합니다. 로컬 VS 2026 프리셋은 그대로 둡니다.

## 잡 구성

세 잡을 **병렬**로 둡니다. 벽시계 시간은 가장 긴 잡 하나입니다.

### 잡 A — `windows-native` (약 3분)

```
runs-on: windows-2025
timeout-minutes: 15
- checkout (fetch-depth: 1)
- msvc-dev-cmd (arch: x64)
- cmake --preset ci-x64-release
- cmake --build --preset ci-x64-release
- ctest --preset ci-x64-release --output-on-failure
```

### 잡 B — `windows-managed` (약 2분)

```
runs-on: windows-2025
timeout-minutes: 15
- checkout (fetch-depth: 1)
- setup-dotnet (global.json의 10.0.302)
- actions/cache: ~/.nuget/packages, key = hash(**/packages.lock.json)
- dotnet restore --locked-mode
- dotnet build --no-restore -c Release -p:Platform=x64
- Catalog.UnitTests.exe / Shell.UnitTests.exe 실행 후 JSON 결과 확인
```

`--locked-mode`를 쓰는 이유는 이 저장소가 이미 project별 `packages.lock.json`을 갖고 있어서
캐시 키가 정확하고, lock이 어긋나면 즉시 실패하기 때문입니다.

### 잡 C — `windows-arm64-cross` (약 3분, PR에서는 조건부)

ARM64 교차 빌드만 하고 테스트는 실행하지 않습니다(호스트가 x64). 매 PR마다 돌릴 가치는 낮으므로
`push: main`과 nightly에서만 돌리거나, `Negaflow.Windows/**` 경로 필터를 겁니다.

## 시간 예산

| 구간 | 콜드 | 캐시 적중 |
|---|---:|---:|
| 러너 부팅 + 체크아웃 | ~50s | ~50s |
| .NET SDK 준비 | ~40s | ~10s |
| NuGet 복원 | ~35s | ~5s |
| MSVC 환경 | ~10s | ~10s |
| 실제 빌드 + 테스트 | ~95s | ~95s |
| **잡 하나 합계** | **~3.5분** | **~2.5분** |
| **벽시계(병렬)** | **~4분** | **~3분** |

## 예산을 지키는 규칙

1. **PR에서는 Release만** 빌드합니다. Debug는 `main` push와 nightly에서만 돌립니다. Debug/Release를
   PR마다 둘 다 돌리면 시간이 그대로 두 배가 됩니다.
2. **ARM64는 PR 기본 경로에서 뺍니다.** 교차 빌드는 실행 검증이 아니므로 PR마다의 가치가 낮습니다.
3. **matrix를 남발하지 않습니다.** (구성 × 아키텍처 × 러너) 조합이 곧 분 단위 비용입니다.
4. **C++ 컴파일러 캐시(sccache/ccache)는 지금 도입하지 않습니다.** 전체 빌드가 64초인데 캐시 복원·
   저장 오버헤드와 설정 복잡도가 이득보다 큽니다. 빌드가 5분을 넘기기 시작하면 그때 재검토합니다.
5. **provenance 게이트를 Windows에서 중복 실행하지 않습니다.** macOS `static` 잡이 이미 Windows
   경로까지 검사합니다. `.gitattributes`가 추가돼 이제 Windows 개발자도 로컬에서
   `py scripts/ci/verify-provenance.py`를 직접 돌릴 수 있습니다.
6. **`timeout-minutes: 15`를 모든 잡에 겁니다.** 행이 걸려도 한 시간을 태우지 않습니다.
7. 기존 `concurrency: cancel-in-progress`를 그대로 상속합니다.
8. `fetch-depth: 1`을 씁니다. Windows 잡은 히스토리가 필요 없습니다.

## 도입 순서

1. `ci-x64-release` Ninja 프리셋을 추가하고 **로컬에서 먼저** configure·build·ctest 37개가 통과하는지
   확인합니다. 이게 안 되면 CI에서도 안 됩니다.
2. 잡 B(관리 코드)를 먼저 넣습니다. 가장 빠르고 실패 모드가 단순합니다.
3. 잡 A(네이티브)를 넣습니다.
4. 두 잡이 `main`에서 안정적으로 초록이 된 뒤 잡 C를 nightly로 붙입니다.
5. 그 시점에 `docs/STATUS.md`의 M1 CI 항목과 `progress/overall-roadmap.md`의 M1 추정치를 갱신합니다.

## 이 계획이 다루지 않는 것

- 실제 ARM64 **실행** 검증. 호스팅 ARM64 Windows 러너 또는 실제 장비가 필요하며 별도 사안입니다.
- WinUI 셸의 GUI end-to-end 테스트. 현재 셸은 프로세스 기동 확인 수준이며 UI 자동화는 M8 이후입니다.
- MSIX 패키징·서명. M17 범위입니다.
