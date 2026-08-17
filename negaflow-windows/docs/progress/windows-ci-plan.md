# Windows CI 계획 — 빠른 게이트 설계

기준일: 2026-08-06
상태: **구현 완료.** `.github/workflows/windows.yml` 과 `Negaflow.Windows/scripts/ci-gate.ps1`.

이 문서는 원래 계획이었고, 구현하면서 전제 하나가 틀린 것이 드러나 갱신했습니다. 아래
"툴체인" 절을 참조하십시오.

## 로컬 게이트와 GitHub 게이트

저장소는 두 입구를 분리해 유지합니다. 같은 검사를 서로 다른 경로로 돌리므로 어느 한쪽만 고치면
갈라집니다. 짝을 맞춰 두십시오.

| 대상 | 로컬 입구 | GitHub |
|---|---|---|
| macOS | `scripts/ci-gate.sh` | `.github/workflows/ci.yml` |
| Windows | `Negaflow.Windows/scripts/ci-gate.ps1` | `.github/workflows/windows.yml` |

provenance·라이선스 게이트는 macOS 잡에만 있습니다. 그 스크립트가 `Negaflow.Windows/src` 와
`tests` 까지 검사하므로 Windows 에서 중복 실행하지 않습니다. Windows 에서 직접 돌리려면 저장소
루트에서 `py scripts/ci/verify-provenance.py` 입니다.

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

## 툴체인 — 계획 단계의 전제가 틀렸습니다

원래 계획은 "`CMakePresets.json`이 generator를 `"Visual Studio 18 2026"`으로 고정하는데 호스팅
러너에는 VS 2026이 없으니 CI 전용 Ninja 프리셋이 필요하다"였습니다. **이 전제는 사실이 아닙니다.**

구현하면서 확인한 사실입니다.

- `windows-latest`와 `windows-2025` 라벨은 **Windows Server 2025 + Visual Studio 2026** 이미지를
  가리킵니다. 2026-05-07 GA이고 2026-06-08~06-15에 걸쳐 롤아웃됐습니다. VS 2022가 필요하면
  `windows-2022`를 명시해야 합니다.
- 그 이미지의 CMake는 Visual Studio 자동 감지 시 `"Visual Studio 18 2026"` generator 문자열을
  씁니다. 저장소 프리셋이 그대로 동작합니다.
- **.NET SDK 10.0.302가 사전 설치돼 있습니다.** `global.json`이 고정한 바로 그 버전입니다.

따라서 Ninja 프리셋도, `ilammy/msvc-dev-cmd`도, `actions/setup-dotnet`도 넣지 않았습니다. 새로
추가한 action 의존성은 0개이며 기존에 쓰던 `actions/checkout@v7`만 사용합니다. **CI가 로컬과 같은
generator, 같은 프리셋, 같은 SDK로 빌드하므로 "CI 초록 = 로컬 초록"이 성립합니다.**

남은 위험은 러너 이미지가 바뀌는 경우입니다. 두 잡 모두 첫 단계에서 `cmake --version`과
`dotnet --list-sdks`를 찍어 이미지가 움직였을 때 로그만으로 원인을 알 수 있게 했습니다. SDK가
사라지면 `global.json`이 분명한 오류로 실패합니다.

### 캐시를 넣지 않은 이유

`packages.lock.json`이 있어 NuGet 캐시 키를 정확히 만들 수 있지만 v1에는 넣지 않았습니다. 복원이
30초대인데 캐시 저장·복원 오버헤드와 실패 지점이 함께 늘어납니다. **첫 실행들의 실제 시간을 본 뒤**
복원이 병목으로 확인되면 그때 추가합니다. 측정 전에 최적화하지 않는다는 원칙을 여기에도 적용합니다.

Windows 러너는 OS 디스크 IO가 느리고 `D:` 임시 디스크가 빠릅니다. `NUGET_PACKAGES`를 `D:`로 옮기는
것도 같은 이유로 측정 뒤에 판단합니다.

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

## 구현된 것

`.github/workflows/windows.yml`에 잡 3개를 넣었습니다.

| 잡 | 트리거 | 내용 |
|---|---|---|
| `native` | PR·main push·수동 | `cmake --preset x64-release` → build → `ctest` |
| `managed` | PR·main push·수동 | `dotnet restore --locked-mode` → build → 테스트 exe 2개 |
| `arm64-cross` | main push·수동만 | 네이티브·관리 ARM64 교차 빌드, 실행 없음 |

`paths` 필터로 `Negaflow.Windows/**`와 이 워크플로 자신만 감시합니다. `Sources/`만 건드리는 PR에서는
돌지 않습니다. macOS `ci.yml`은 건드리지 않았습니다.

로컬 짝은 `Negaflow.Windows/scripts/ci-gate.ps1`이고 같은 단계를 순차로 돌립니다.

```powershell
.\Negaflow.Windows\scripts\ci-gate.ps1 -Preset x64-release
```

### 구현 시점 로컬 확인

- `ci-gate.ps1` 통과: 네이티브 **39/39**, 관리 빌드 오류 0, Catalog 205 + Shell 45 assertion
- `dotnet restore --locked-mode`가 x64와 ARM64 모두 성공

### 첫 실행 실측 (2026-08-06, PR #2)

| 잡 | 실측 | 계획 예측 |
|---|---:|---:|
| Native build and tests | 2분 27초 | ~3.5분 |
| Managed build and tests | 1분 30초 | ~3.5분 |
| **벽시계(병렬)** | **2분 27초** | ~4분 |

첫 실행에 세 잡 모두 통과했습니다. 예측보다 빨랐고 목표 8분의 3분의 1 이하입니다.

**NuGet 캐시는 넣지 않기로 확정합니다.** 관리 잡 전체가 체크아웃·복원·빌드·테스트 2종을 합쳐
1분 30초입니다. 복원은 병목이 아니며, 캐시를 넣으면 절약분보다 오버헤드와 실패 지점이 큽니다.
`NUGET_PACKAGES`를 `D:`로 옮기는 것도 같은 이유로 하지 않습니다.

이 판단은 시간이 늘어나면 다시 봅니다. 관리 잡이 3분, 네이티브 잡이 5분을 넘기면 재검토합니다.

### 남은 튜닝

1. `main`에서 안정적으로 초록이 유지되면 `docs/STATUS.md`에 실행 날짜·구성·실패 여부를 추가합니다.
2. 러너 이미지가 Windows SDK 10.0.26100 관련 문제를 보고한 적이 있으므로, 네이티브 잡이 실패하면
   `Toolchain` 단계의 CMake SDK 선택 로그를 먼저 확인합니다. 첫 실행에서는 문제가 없었습니다.
3. ARM64 교차 빌드는 `main` push와 수동 실행에서만 돕니다. 통과해도 runtime 검증이 아닙니다.

## 이 계획이 다루지 않는 것

- 실제 ARM64 **실행** 검증. 호스팅 ARM64 Windows 러너 또는 실제 장비가 필요하며 별도 사안입니다.
- WinUI 셸의 GUI end-to-end 테스트. 현재 셸은 프로세스 기동 확인 수준이며 UI 자동화는 M8 이후입니다.
- MSIX 패키징·서명. M17 범위입니다.
