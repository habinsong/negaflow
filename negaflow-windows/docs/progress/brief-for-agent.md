# 작업 브리프 — Negaflow Windows macOS 동등 이식

**이 문서 하나만 읽고도 일을 시작할 수 있게 썼습니다.** 이어받는 에이전트(Grok 4.6 등)를
위한 것입니다. 사전 지식 없이 읽으십시오.

---

## 0. 당신이 하는 일

macOS 용 사진 현상 앱 **Negaflow** 가 이미 완성돼 있습니다. 그것과 **똑같이 동작하는
Windows 판**을 만드는 중이고, 당신은 그 이어받는 사람입니다.

**핵심 규칙: 창작 금지. macOS 코드와 스크린샷을 보고 1:1 로 옮깁니다.**
macOS 에 없는 것을 만들지 않고, macOS 에 있는 것을 빼지 않습니다.

---

## 1. 저장소

| 경로 | 내용 |
|---|---|
| `C:\Users\habin\negaflow\negaflow-mac\` | **macOS 원본 (Swift).** 정답입니다. 고치지 마십시오 |
| `C:\Users\habin\negaflow\negaflow-windows\` | **Windows 판.** 여기를 고칩니다 |
| `C:\Users\habin\negaflow\negaflow_mac_screenshot\` | macOS 실행 화면 62장 (1343×768) |
| `C:\Users\habin\negaflow-scanner-sane\` | 스캐너 플러그인 (별도 저장소) |

macOS 주요 위치:
- 엔진: `negaflow-mac/Sources/Chromabase/` (159파일 30,556줄)
- 앱: `negaflow-mac/Sources/negaflowApp/` (Features/ 아래 Library·Develop·Print·Canvas·Defects·Workspace)

Windows 주요 위치:
- 네이티브 C++: `negaflow-windows/src/Native/` (abi·color·core·imageio·imaging·output·pipeline)
- 관리 C#: `src/Shell.Core/`(로직) · `src/Shell/`(WinUI 3 화면) · `src/Catalog.Core/` · `src/Interop/`
- 시험: `tests/Native.UnitTests/` · `tests/Shell.UnitTests/`

---

## 2. 사용자 요구 (원문 그대로)

> - GrainMend 를 macOS 에 구현된 **품질·성능·기능·속도·최적화·검출능력·오탐지 억제·UI/UX
>   (크기·모양·색깔·위치)** 모두 싹다 그대로 이식. **창작 없이. 1:1 로.**
> - 자동 검출은 **5초 미만**, 가이드·브러시·복제·IR 은 **즉시**.
> - **라이브러리/현상/인화 뷰의 좌측탭·상단탭·우측탭·하단탭·하단바·상단바 전부** macOS 와
>   동일하게. 좌측탭 안의 세로탭까지. **기능 하나 빼먹지 말 것.** 정렬 옵션, 세부 프레임, 뷰 전부.
> - macOS **Swift 코드와 스크린샷을 둘 다** 보고 맞출 것.
> - **GPU 를 쓸 것.** Intel 내장·AMD 내장·외장(Intel/NVIDIA/AMD) **공통으로 되는 것.**
>   검출뿐 아니라 **현상·프리뷰·보정·우측 슬라이더·인화 등 이미지 관련 전부.**
> - **하드코딩으로 문제를 회피하지 말 것.** 가설·추측 없이 **검증**해서 해결할 것.
> - **500줄 넘는 God object 금지.** 넘기려면 사유를 문서에 적을 것.
> - **전부 끝낸 뒤에 computer-use 로 확인할 것.** 중간에 앱을 띄워 검증하지 말 것.
> - 백엔드 대충 만들고 "된다" 고 보고하지 말 것.

추가로 대화에서 못박은 것:

> - QA 는 사용자가 직접 합니다. **앱이 뜨는 데까지만** 하면 됩니다.
> - 문제를 은폐하지 말고 근본 원인을 해결하십시오. **임시 빌드를 만들지 말고 빌드
>   스크립트를 똑바로 고치십시오.**
> - 로컬 CI 와 GitHub CI 를 함께 생각하되 **로컬 우선**.

---

## 3. 행동 규칙

1. **한국어로 답합니다.** 사용자는 한국어를 씁니다.
2. **커밋에 AI 표시를 넣지 않습니다.** `Co-Authored-By`, "Generated with" 류 금지.
3. **"있음" 으로 적지 마십시오.** 파일이 있고 이름이 같아도 다른 일을 할 수 있습니다.
   실제로 검출기가 "오케스트레이션은 있음" 으로 적혀 있었는데 macOS 의 **브러시 경로**를
   자동에 쓰고 있었습니다. 함수·상수 단위로 대조하고 나서 판정하십시오.
4. **측정 먼저.** "느리다/이상하다" 로는 어디를 고칠지 모릅니다. 이 프로젝트는 계측기가
   있습니다(6절). 숫자를 만들고 나서 고치십시오.
5. **의미 있는 체크포인트마다 커밋·푸시**하고, 커밋 메시지에 **무엇을 왜 고쳤는지와 측정값**을
   적으십시오.
6. **문서를 갱신하지 않은 커밋은 무엇이 좋아졌는지 모르는 커밋입니다.**

---

## 4. 문서 지도

`negaflow-windows/docs/plan/` 에 있습니다. **작업 전에 해당 문서를 읽으십시오.**

| 문서 | 언제 읽나 |
|---|---|
| [`00-overview.md`](../plan/00-overview.md) | 전체 순서와 완료 기준 |
| [`01-grainmend-detection-parity.md`](../plan/01-grainmend-detection-parity.md) | **검출 품질을 고칠 때** — 미대조 파일표, 격차 순 순서 |
| [`02-grainmend-performance.md`](../plan/02-grainmend-performance.md) | **속도·GPU 를 할 때** — 측정값, D3D11 선택 근거, 파이프라인 13단계 |
| [`03-grainmend-uiux.md`](../plan/03-grainmend-uiux.md) | **GrainMend 화면을 할 때** — 캡슐·칩·브러시·복제 macOS 수치 |
| [`04-workspace-parity.md`](../plan/04-workspace-parity.md) | **3뷰 화면을 할 때** — 216개 파일 대조표 골격 |
| [`05-verification.md`](../plan/05-verification.md) | **확인할 때** — 계측기, computer-use 15개 항목, 함정 |
| [`06-detection-reference.md`](../plan/06-detection-reference.md) | **검출 채점표.** macOS 정답값 5장 |
| [`07-ui-gap-audit.md`](../plan/07-ui-gap-audit.md) | **화면 격차 감사.** 없음/창작/다름 판정 |
| [`08-missing-backend.md`](../plan/08-missing-backend.md) | **없는 백엔드 목록.** 히트 0 인 개념들 |
| [`handoff-2026-08-17-2.md`](handoff-2026-08-17-2.md) | 직전 세션이 무엇을 했는지 |

---

## 5. 지금 상태 (측정된 사실만)

### 5.1 검출 품질 — 정답지 대비 6.6%

`OpticFilm8100_frame_4.tiff` (5088×3401), 자동 검출:

| 분류 | macOS | Windows | 차이 |
|---|---:|---:|---:|
| 먼지 | 13 | **0** | −13 |
| 핀홀 | 2 | **0** | −2 |
| 가로 스크래치 | 5 | 3 | −2 |
| 세로 스크래치 | 10 | 11 | +1 |
| 대각 스크래치 | 0 | 1 | +1 |
| **미세 입자** | **197** | **0** | **−197** |
| **합계** | **227** | **15** | **−212** |

다른 프레임 macOS 값: frame_2 **1,720** · frame_3 **623** · frame_5 **647** · frame_7 **956**.
미세 입자가 어느 프레임에서나 **76~91%**. 전체 표는 [`06`](../plan/06-detection-reference.md).

**사용자 확인: macOS 에서도 오검출이 많습니다.** 목표는 "오검출 0" 이 아니라
**macOS 와 같은 것을 고르는 것**입니다.

### 5.2 속도 — 목표의 2.5배

| 단계 | 처음 | 지금 | 목표 |
|---|---:|---:|---:|
| TIFF 디코드 + ICC | 2,730 ms | 2,695 ms | 1,500 ms |
| 현상 | 770 ms | 770 ms | 200 ms |
| 검출 | 18,560 ms | 8,932 ms | 2,500 ms |
| **합계** | **22,059 ms** | **12,397 ms** | **5,000 ms** |

검출 CPU 작업의 **82%가 형태학(`opening`/`closing`) 하나**입니다.

### 5.3 화면

상단바에 별점·플래그·거부·스캔 버튼 2개가 **없음**. 하단바 위치·줌·정렬방향이 **다름**.
좌측 레일 6개 중 **4개 아이콘이 다름**. 자세한 것은 [`07`](../plan/07-ui-gap-audit.md).

### 5.4 백엔드

`MonotoneCubic`·`PositiveDevelop`·IT8 8개·`RenderManifest` 5개·`PhotoNumbering` 등이
**Windows 트리에 한 글자도 없습니다.** 목록은 [`08`](../plan/08-missing-backend.md).

---

## 6. 계측기 — 앱을 띄우지 않고 재는 법

**중간 검증은 전부 이것으로 합니다. 앱은 마지막에만 띄웁니다.**

```bash
# 검출 한 번: 분류별 개수 + 평균 신뢰도 + 단계별 시간
negaflow-cli --grain-mend-detect "<source.tiff>" <dmin-r> <dmin-g> <dmin-b> [sensitivity] [guided]

# 현상·내보내기 단계별 시간
negaflow-cli --export-developed-tiff16 <source> <dest> <dmin-r> <dmin-g> <dmin-b> color

# 결함 도구 다섯이 실제로 화소를 바꾸는지 (앱 종료 후 단독 실행)
Negaflow.Shell.UnitTests.exe --defect-tools <storageRoot> <frameId> [irPath]
```

`negaflow-cli.exe` 는 `out/build/native/x64-release/Release/` 에 있습니다.

**주의**: 위 dmin 은 임의값입니다. 앱이 쓰는 dmin 은 프레임마다 다르고 카탈로그에 있습니다.
macOS 기준값과 같은 조건으로 재려면 dmin 을 맞춰야 합니다([`06`](../plan/06-detection-reference.md) 3.1).

### 검증 코퍼스

| 경로 | 내용 |
|---|---|
| `C:\Users\habin\OneDrive\바탕 화면\negaflow_test\` | OpticFilm 8100 컬러 네거티브 15장 (정답지가 있는 곳) |
| `C:\Users\habin\Downloads\golden\golden\8100\OpticFilm8100_frame_1.tiff` | 기준 프레임 |
| `C:\Users\habin\Downloads\golden\golden\v700\GT-X900_frame_4.tiff` + `.ir.tiff` | IR 짝 (유일) |

---

## 7. 빌드·시험

```powershell
.\scripts\build.ps1 -Preset x64-release            # 네이티브 C++
.\scripts\build-managed.ps1 -Preset x64-release    # 관리 C#
.\scripts\ci-gate.ps1 -Preset x64-release          # 로컬 게이트 전체
.\scripts\run-app.ps1 -Architecture x64 -Configuration Release   # 앱 실행 (마지막에만)
```

관리 시험 직접 실행:

```powershell
.\out\build\managed\Negaflow.Shell.UnitTests\x64\Release\net10.0\win-x64\Negaflow.Shell.UnitTests.exe
```

현재 기준: **Shell 1043 assertions, 0 failures, 경고 0.** 이 숫자가 줄면 안 됩니다.

---

## 8. 작업 순서

**앞 단계가 뒤 단계의 측정 기준을 바꿉니다. 순서대로 하십시오.**

### 1단계 — 검출 품질 ([`01`](../plan/01-grainmend-detection-parity.md), [`06`](../plan/06-detection-reference.md))

1. **미세 입자를 컴포넌트로 승격** ← **지금 당장 할 일**
   macOS `DefectSpeckDetector.merged(into:specks:)` 는 컴포넌트를 더합니다(겹치면 기존 우선).
   Windows `grain_mend_speck_detector.cpp` 의 `merge_micro_speck_mask` 는 마스크 바이트만
   켭니다. 그래서 197개가 0개입니다. **그 패스에 CPU 11초를 쓰면서 화면에 아무 기여도 못
   합니다.** 덧붙여 마스크에 더하는 화소도 240개뿐이라 **임계 자체가 다를 가능성이 큽니다** —
   `DefectSpeckDetector.swift` 임계식을 그대로 대조하십시오.
2. **`DefectDustDetector` 대조** — 먼지 13 + 핀홀 2 가 0인 이유. 후보가 안 서는지 게이트에서
   전멸하는지 **먼저 가르십시오**(후보 화소 수를 임시로 세면 바로 나옵니다).
3. **`DefectContrastField` / `DefectComponentMask+Labeled` 대조** — 2번 결과에 따라
4. **`DefectScratchDetector` 대조** — 자릿수는 맞으니 미세 조정
5. **`applyingWholeFrameAutomaticRiskFlag` 이식** — 오검출 위험 경고

**매 단계마다 `--grain-mend-detect` 로 다섯 프레임을 재고 [`06`](../plan/06-detection-reference.md) 표를 갱신하십시오.**

### 2단계 — 속도·GPU ([`02`](../plan/02-grainmend-performance.md))

1. CPU 낭비 제거: 버퍼 재사용, 각도 워커 상한 2 재검토, 타일 동시 수, 고정 스레드 풀
2. **D3D11 컴퓨트 셰이더**로 형태학(`opening`/`closing`) 이전 — 검출의 82%
3. GPU 를 현상·톤·곡선·믹서·그레이딩·프리뷰 리샘플·인화로 확대

**GPU 는 반드시 CPU 폴백을 둡니다. 두 경로가 같은 값을 내는지 시험으로 고정하십시오.**

### 3단계 — GrainMend 화면 ([`03`](../plan/03-grainmend-uiux.md))
캡슐 남은 결함, 브러시 컨트롤 바 + "칠해서 모았다가 적용" 모델, 복제 도장 오버레이, undo 스택

### 4단계 — 3뷰 전체 화면 ([`04`](../plan/04-workspace-parity.md), [`07`](../plan/07-ui-gap-audit.md))
상단 바 → 하단 바 → 좌측 레일 → 정렬/필터 실제 동작 → 우측 인스펙터 → 인화

### 5단계 — 없는 백엔드 ([`08`](../plan/08-missing-backend.md))
`MonotoneCubic` → `PositiveDevelop` → `PhotoNumbering` → `ScannerTargetGrade` → IT8 → 나머지

### 6단계 — computer-use 검증
**전부 끝난 뒤에만.** [`05`](../plan/05-verification.md) 3.1 절의 15개 항목을 순서대로.

---

## 9. 함정 (실제로 겪은 것)

| 함정 | 증상 | 대응 |
|---|---|---|
| **앱 인스턴스 여러 개** | 라이브러리가 **0장**으로 보임 | 같은 카탈로그를 두 프로세스가 잡습니다. 하나만 남기면 즉시 복구. 데이터는 안전합니다 |
| `open_application` 반복 호출 | 위 상황을 만듦 | **한 번만** 부르십시오 |
| **MSBuild 낡은 오브젝트** | 시그니처 바꾼 뒤 LNK2019 | 해당 `.obj` 삭제 또는 소스 타임스탬프 갱신. `negaflow_imaging.lib` 를 "최신" 으로 보고 재컴파일하지 않습니다 |
| 스크립트를 상대경로로 백그라운드 실행 | "term is not recognized" | 절대경로로 |
| `--defect-tools` 가 `frame unavailable` | 디스패처가 큐를 안 돌림 | 앱 종료 후 단독 실행. **앱이 켜진 채 프로덕션 저장소에 대고 돌리지 마십시오** |
| 빌드가 CS0579 로 무너짐 | 프로젝트 폴더에 `obj\` 생성 | `Get-ChildItem -Path src, tests -Directory -Recurse -Filter 'obj' \| Remove-Item -Recurse -Force` |
| 라이브러리 그리드에서 썸네일 클릭 | 의도와 다른 프레임이 열림 | 파일명 확인하고 클릭 |

---

## 10. 완료 기준

| 항목 | 기준 |
|---|---|
| 검출 품질 | 다섯 프레임 전부에서 분류별 개수가 macOS 의 **±20% 안**. 어떤 분류도 macOS 는 있는데 Windows 가 **0** 이면 안 됨 |
| 자동 속도 | 앱에서 자동 클릭 → 결과 표시까지 **5초 미만** |
| 가이드·브러시·복제·IR | 즉시 (체감 지연 없음) |
| 화면 | macOS 스크린샷과 나란히 놓고 크기·색·위치·정렬이 같음. Swift 에 있는 기능이 전부 있음 |
| GPU | Intel 내장·AMD 내장·외장에서 동작, CPU 폴백 있음, 두 경로 값 동일 |
| God object | 새 파일 전부 500줄 이하 |
| 시험 | 로컬 게이트 통과, 경고 0, assertions 1043 이상 |

---

## 11. 남은 God object

| 대상 | 줄 |
|---|---:|
| `src/Native/abi/negaflow_abi.cpp` | 6,264 |
| `src/Shell/Views/DevelopWorkspaceView.xaml.cs` | 4,835 |
| `tests/Native.UnitTests/develop_export_abi_tests.cpp` | 4,107 |
| `src/Shell/Views/LibraryWorkspaceView.xaml.cs` | 2,835 |
| `src/Shell/Views/DevelopWorkspaceView.xaml` | 2,508 |
| `src/Interop/NativeDevelopExporter.cs` | 2,342 |
| `src/Native/pipeline/develop_export.cpp` | 1,575 |
| `src/Native/core/tiff_probe.cpp` | 1,425 |
| `src/Shell/Views/LibraryWorkspaceView.xaml` | 975 |
| `src/Shell/Views/PrintWorkspaceView.Composition.cs` | 826 |

화면을 이식하면서 표면 하나를 손댈 때마다 그것을 `UserControl` 로 뽑아내면 God object 가
줄어듭니다. `DefectLayerSection` 을 그렇게 했고 늘지 않았습니다.

---

## 12. CI

- macOS `CI`: 통과
- Windows CI: Managed·Native·ARM64 통과. **설치본 잡만 남음** — `Verify silent install and
  uninstall` 이 멈추고 25분 타임아웃. 유력한 자리는 NSIS 가 부르는 `Add-AppxPackage -Register`
- **푸시할 때마다 이전 실행이 취소됩니다.** 설치본 잡 결과를 보려면 완주할 때까지 푸시하지 마십시오

---

## 13. 첫 명령

```
docs/progress/brief-for-agent.md 를 읽었습니다.
8절 1단계 1번(미세 입자 컴포넌트 승격)부터 시작합니다.
먼저 docs/plan/01 과 06 을 읽고, macOS DefectSpeckDetector.swift 와
Windows grain_mend_speck_detector.cpp 를 나란히 대조하겠습니다.
```
