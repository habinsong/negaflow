# Windows 설계 문서 감사 절차와 2026-08-04 결과

> 상태: 문서 집합 자체의 재현성·최신성 감사  
> 기준일: 2026-08-04  
> 대상: windows_docs 전체  
> macOS source 기준: 9be909c43edd7e04ba98cdc9d6a0c688739e343e  
> 주의: 이 감사는 Windows 구현·빌드·실기 검증이 아니라 문서 근거와 내부 일관성 검증이다.

## 0. 목적

Windows 이식 문서는 구현보다 먼저 만들어지므로 다음 종류의 drift가 생기기 쉽다.

- macOS source의 파일·커널·기능 수가 바뀜
- 이전 GPU/backend 결론이 새 결정과 충돌
- 후보 dependency를 이미 채택한 것처럼 표현
- 지원 종료 OS나 runtime version을 영구 기준으로 고정
- MSIX, installer, scanner plugin의 배포 경계를 혼동
- 상대 링크가 새 문서 구조를 따라가지 못함
- 웹 조사와 직접 코드 관찰을 같은 증거 등급으로 표시
- 계획 checklist를 완료 증거로 오인

이 문서는 감사할 축, 재현 명령, 2026-08-04의 실제 결과와 남은 한계를 기록한다.

## 1. 감사 범위

### 포함

- 71개 Markdown 파일
- README와 기술 결정 등록부
- UI·엔진·색 관리·I/O·scanner·배포·성능·CPU·유지보수 문서
- 모든 상대 Markdown 링크
- 코드 fence 형식
- macOS commit·파일·줄·kernel 수치
- 현재 backend·CPU·배포·OS·라이선스 결론
- 시간에 민감한 Microsoft/upstream 사실
- 문서가 실제로 수행하지 않은 검증의 경계

### 제외

- Windows source build
- D3D11·Direct2D·WARP 실행
- WinUI 3 render
- x64·ARM64 Windows hardware
- WIA/TWAIN scanner
- installer·signing·update
- monitor ICC·HDR·printer 측정
- 모든 외부 URL의 전수 availability 검사

제외 항목은 “문서 감사 통과”로 증명되지 않는다.

## 2. 현재 worktree 경계

감사 시작 시 확인:

~~~text
HEAD
9be909c43edd7e04ba98cdc9d6a0c688739e343e

git status --short
?? docs/postmortem-digital-film-look-2026-08-04.md

git check-ignore -v windows_docs/README.md
.gitignore:111:/windows_docs/
~~~

해석:

- macOS source는 문서의 기준 commit과 같다.
- docs/postmortem-digital-film-look-2026-08-04.md는 사용자 소유의 관련 없는 미추적 파일이다.
- 감사에서 읽거나 수정·stage·삭제하지 않는다.
- windows_docs는 gitignore 대상이므로 일반 git diff/status만으로 문서 변경을 검증할 수 없다.
- 따라서 링크·문법·내용 검사를 별도 read-only command로 수행한다.

## 3. macOS source 수치 재현

### 3.1 집계 정의

두 commit을 같은 방식으로 비교한다.

- git archive의 Sources와 Tests
- 확장자가 .swift인 regular file
- 줄 수는 newline byte 수
- 파일 수는 Swift file 수
- 테스트 함수는 func test... 이름 패턴
- source import 수는 Sources + Tests의 Swift 파일에서 import line을 가진 파일 수
- CIImage·CGImage 수는 Sources의 Swift 파일 literal occurrence

이 정의 밖의 JSON, Metal source string 내부 line, resource, generated binary와 문서는 총 Swift 줄 수에
포함하지 않는다.

### 3.2 commit 비교 결과

| 영역 | 80fc71e | 9be909c | 증감 |
|---|---:|---:|---:|
| Sources/Chromabase | 25,664줄 / 139파일 | 27,107줄 / 147파일 | +1,443 / +8 |
| Sources/ScannerKit | 6,736 / 50 | 6,736 / 50 | 0 |
| Sources/negaflowApp | 75,783 / 517 | 75,913 / 517 | +130 / 0 |
| Sources/negaflowCLI | 1,074 / 11 | 1,074 / 11 | 0 |
| Tests | 67,933 / 247 | 68,790 / 249 | +857 / +2 |
| 합계 | 177,190 / 964 | 179,620 / 974 | +2,430 / +10 |
| test 이름 패턴 | 약 1,840 | 약 1,878 | +38 |

### 3.3 현재 Chromabase 하위 폴더

| 폴더 | Swift 줄 | 파일 |
|---|---:|---:|
| Adjustments | 2,617 | 18 |
| DefectRemoval | 5,893 | 35 |
| Develop | 1,093 | 11 |
| Digital | 1,184 | 8 |
| Engine | 1,648 | 6 |
| Export | 3,985 | 23 |
| Film | 1,903 | 11 |
| Imaging | 2,676 | 10 |
| Profiles | 6,108 | 25 |
| 합계 | 27,107 | 147 |

Presets와 ScannerProfiles는 resource 폴더라 Swift file 수 표에는 들어가지 않는다.

### 3.4 현재 UI 기능별 줄 수

| 기능 | Swift 줄 | 파일 |
|---|---:|---:|
| Library | 14,350 | 98 |
| Develop | 7,997 | 65 |
| Export | 7,030 | 41 |
| Defects | 6,114 | 45 |
| Print | 5,894 | 17 |
| Scanning | 4,335 | 21 |
| Canvas | 2,630 | 21 |
| Workspace | 1,376 | 9 |
| Versions | 168 | 3 |
| Help | 73 | 1 |
| Features 합계 | 49,967 | 321 |

### 3.5 custom kernel

| 항목 | 80fc71e | 9be909c |
|---|---:|---:|
| ChromabaseMetalKernels.swift | 618줄 | 814줄 |
| stitchable function | 21 | 31 |
| coreimage::sample_t literal | 42 | 56 |
| destination/sampler/texture2d literal | 0 | 0 |

31은 전체 render stage나 dispatch 수가 아니다. custom stitchable color function 수다.

### 3.6 감사 중 수정된 수치 오류

이전 문서에는 서로 다른 방식으로 셌다고 설명된 수치가 있었지만, 실제로는 같은 commit에서도
다음 값이 맞지 않았다.

- Chromabase 27,223 또는 27,285 → 27,107
- Digital 1,283 → 1,184
- Engine 1,665 → 1,648
- kernel file 831 → 814
- initial kernel 22 → 21
- Tests 68,867 → 68,790

현재 [macOS 인벤토리](../00-overview/mac-inventory.md)와
[기술 결정 등록부](../00-overview/decision-register.md)는 위 재계산 값으로 갱신됐다.

## 4. 상위 결정 일관성 감사

### 4.1 GPU

정본:

~~~text
D3D11 FL 11_0
SM 5.0 / FXC / DXBC
Direct2D 1.1 custom effects
같은 D3D11 device의 DirectCompute
WARP
완전한 CPU fallback
~~~

감사한 잘못된 과거 표현:

- D3D12 FL 12_0·SM6 필수
- D3D11On12 항상 사용
- 31개 kernel 전체를 한 pass로 기계 이식
- fixed warp width
- NVIDIA/AMD occupancy 수치를 공통 default로 사용
- CUDA 완전 제외 또는 CUDA 필수

현재 결론:

- D3D12는 계측 뒤 선택 tier 후보
- CUDA는 NVIDIA 전용 후순위 후보
- DirectML·Work Graphs는 일반 image pipeline 기준선에서 제외
- 31개 kernel은 current-coordinate authoring 후보
- spatial producer가 필요한 9개 subgraph는 별도 materialization 가능
- vendor마다 기능은 같고 speed/permutation만 다를 수 있음

### 4.2 CPU

정본:

- x64 Intel·AMD 공통 baseline은 MSVC default/SSE2 범위
- ARM64는 Armv8.0-A + NEON baseline
- AVX2와 FMA는 별도 capability와 수치 gate
- AVX-512·SVE2는 v1 필수 아님
- Google Highway는 후보, 필수 dependency 아님
- Intel/AMD vendor ID로 pixel algorithm을 나누지 않음

감사 query는 “SSE4.2 필수”, “Highway 확정”, “ARM64 나중”, “ARM64EC 본체”를 찾는다.

### 4.3 배포

정본:

- architecture별 unpackaged self-contained 후보
- Direct Stable의 offline-complete MSI/bootstrapper
- Authenticode와 signed update metadata
- MSIX/Store는 미래 gate
- plugin installer와 update 분리
- binary rollback과 catalog rollback 분리

WiX는 무료 고정 전제가 아니다. 현재 upstream OSMF 조건을 승인하거나 동등 installer 대안을
선택해야 한다.

### 4.4 scanner

정본:

- 모든 backend는 out-of-process plugin
- WIA 2.0 COM 기본 후보
- TWAIN x64와 필요한 x86 adapter 분리
- SANE는 GPL 별도 repository·installer·update·source
- capability-driven UI
- mock은 explicit development opt-in
- 실제 requested/applied/decoded ROI와 bit depth 증거

WIA/TWAIN/SANE 이름이 문서에 있다는 사실은 특정 장치 지원 선언이 아니다.

### 4.5 UI

정본:

- C#/.NET + WinUI 3
- native Windows focus/input/accessibility
- pixel은 C++ D2D/D3D, widget은 XAML
- raw Direct2D 기준. Win2D dependency는 채택하지 않음
- 99.9%는 기능·상태·결과·복구 동등성

### 4.6 data safety

정본:

- 원본 불변
- missing/corrupt catalog는 empty catalog가 아님
- export reconstruction 실패 시 original fallback 금지
- virtual copy shared source 삭제 안전성
- atomic/serialized app-owned write
- async apply 직전 frame/session/revision 검증

## 5. 시간 민감 정보 감사

### 5.1 Windows 11

2026-08-04 공식 release information에서 확인:

| release | Home/Pro end of updates | Enterprise/Education end |
|---|---:|---:|
| 24H2 | 2026-10-13 | 2027-10-12 |
| 25H2 | 2027-10-12 | 2028-10-10 |
| 26H1 | 2028-03-14 | 2029-03-13 |

26H1은 공식 설명상 2026년 신형 장치용이며 기존 24H2/25H2의 일반 in-place feature update가 아니다.

감사 결론:

- 24H2 build 26100을 API 하한 후보로 둘 수 있음
- Stable 고객 지원 OS와 동일하게 고정하면 안 됨
- API minimum, CI image, tested OS, supported OS, grace period를 분리

### 5.2 Windows App SDK

2026-08-04 공식 release channel snapshot:

- latest stable package: 2.3.1
- release date: 2026-07-16
- servicing family 2.0 current
- end of servicing: 2027-04-29

self-contained는 runtime version을 앱이 통제하지만 servicing update가 자동 적용되지 않는다. 앱이
새 runtime을 통합해 재배포한다.

### 5.3 .NET

2026-08-04 공식 support snapshot:

- .NET 10 LTS active
- latest patch snapshot: 10.0.10
- end of support: 2028-11-14

구현·출시 시 최신 supported patch를 다시 고정한다.

### 5.4 Windows SDK

2026-08-04 공식 release notes 상단:

- 10.0.28000.2526
- released July 2026

문서의 이전 10.0.28000.2114 May snapshot을
[개발 환경](../13-build-and-deps/development-environment.md)에서 갱신했다.

### 5.5 WiX

현재 upstream repository:

- source license는 MS-RL
- README에 Open Source Maintenance Fee 정책
- 수익 창출 사용에는 fee가 필요하다는 안내

이 정보는 법률 결론이나 실제 조직 승인 증거가 아니다. release blocker Q-020으로 남긴다.

## 6. Markdown 구조 감사

### 6.1 2026-08-04 결과

| 검사 | 결과 |
|---|---:|
| Markdown files | 71 |
| Markdown lines | 52,685 |
| external URL occurrences | 547 |
| broken local links | 0 |
| orphan Markdown documents | 0 |
| unmatched backtick/tilde fences | 0 |
| CRLF files | 0 |
| NUL-containing files | 0 |
| decision IDs | 17 unique, D-001…D-017 |
| open-question IDs | 25 unique, Q-001…Q-025 |
| spike IDs | 12 unique, S0…S11 |
| roadmap milestones | 19 unique, M0…M18 |
| render-failure IDs | 19 unique, F-001…F-019 |

새 감사 파일을 추가하기 전 첫 실행은 67파일이었고, 감사 파일 포함 68파일이었다. 이후 실제
AppEntry·termination 코드와 Windows lifecycle API를 대조한 application-lifecycle 명세를 추가해
69파일, 기준선 manifest를 추가해 70파일, 화면별 정본 index를 추가해 현재 71파일이다. 기존의 짧고
경쟁 제품 일화 중심이던 성능 실패 문서는 F-001…F-019 복구 계약으로 교체했다.

README, 열린 질문과 스파이크의 milestone 번호는
[이행 로드맵](migration-roadmap.md)의 M0…M18 제목을 정본으로 대조한다. 2026-08-04 감사에서는
오래된 중간 계획 때문에 M3 이후 번호가 한 단계씩 밀린 표를 발견해 모두 로드맵 기준으로 수정했다.

수정한 오래된 링크:

- 05-image-io/README.md → export-formats.md
- surfaces/export-print.md → export.md + print.md
- 16-cpu-acceleration/simd.md → 16-cpu/simd-and-dispatch.md
- scanner/plugin-abi.md → scanner/protocol-contract.md
- 존재하지 않는 security threat-model → scanner plugin security 문서
- maintenance의 잘못된 decision-register 상대 경로

### 6.2 링크 검사 예시

다음 read-only Python은 Markdown inline link의 local target 존재 여부만 검사한다. reference-style,
HTML, GitHub anchor semantics와 외부 HTTP 상태를 모두 검증하는 완전한 parser는 아니다.

~~~python
from pathlib import Path
from urllib.parse import unquote
import re

root = Path("windows_docs").resolve()
broken = []

for path in root.rglob("*.md"):
    text = path.read_text(encoding="utf-8")
    for match in re.finditer(r"!?\[[^\]]*\]\(([^)]+)\)", text):
        target = match.group(1).strip()
        if target.startswith(("http:", "https:", "mailto:", "#")):
            continue
        relative = unquote(target.split("#", 1)[0])
        if relative and not (path.parent / relative).resolve().exists():
            broken.append((path, target))

assert not broken, broken
~~~

### 6.3 fence 검사

- 세 backtick 시작/종료 수
- 세 tilde 시작/종료 수
- delimiter family별 짝수 여부

Markdown 안에서 더 긴 fence 또는 indented code를 쓰기 시작하면 checker를 확장한다.

## 7. 상충 용어 감사

다음 검색은 zero result만 목표로 하지 않는다. 과거 결정을 명시적으로 폐기하는 문장은 정상이다.
문맥을 읽어 긍정적 기준선인지 과거 오류 설명인지 구분한다.

~~~text
커널 21개
Highway 확정
SSE4.2 기준선
CUDA 제외 확정
D3D12 v1 기준선
SM 6.0 필수
sparse package 확정
MSIX v1 기본
Win2D 또는 D2D
24H2 영구 최소
~~~

2026-08-04 결과:

- “21개”는 80fc71e의 역사적 실측값과 color-pipeline의 명시적 오해/반박 문맥에만 남고,
  현재 9be909c kernel 수는 모두 31로 표시
- Highway는 후보라고 명시
- x64 baseline은 SSE2/default
- CUDA는 후순위 후보
- D3D12/SM6는 과거안 또는 선택 tier 문맥
- MSIX는 미래 channel
- raw Direct2D 기준선
- 24H2는 API 하한 후보, Stable support와 분리

## 8. 증거 등급 감사

| 문장 유형 | 필요한 표기 |
|---|---|
| 현재 macOS code에서 직접 셈 | commit·path·집계 방법 |
| 공식 API contract | 공식 URL·확인일 |
| upstream license | exact artifact/version·원문 |
| Windows에서 실행 안 함 | 후보·계획·미검증 |
| virtual/mock test | virtual/mock이라고 표시 |
| physical hardware | model·ID·driver·artifact |
| 성능 | dataset·hardware·build·percentile |
| 색 정확도 | ICC·측정 장비·환경 |
| 배포 완료 | final signed bytes·clean VM·update/rollback |

“문서를 충분히 썼다”는 구현 완료 증거가 아니다.

## 9. 완료율과 문서 수

문서 파일 수는 작업 완료율 분모가 아니다.

- 하나의 work item이 여러 문서를 갱신할 수 있다.
- 한 문서가 여러 architecture·surface·release gate를 포함할 수 있다.
- audit artifact를 추가했다고 고정한 1차 작업 범위를 늘리지 않는다.
- 1차 문서 범위 60개는 60/60 완료 상태를 유지한다.
- 이 문서는 그 뒤의 별도 최종 감사 artifact다.

향후 문서가 늘어나면 파일 수만 보고 완료율을 다시 계산하지 않는다. 새 scope를 명시적으로 승인할
때만 새 denominator를 만든다.

## 10. 다시 실행할 감사 순서

1. git status --short
2. git rev-parse HEAD
3. 기준 commit과 current commit의 Swift archive count
4. stitchable 함수명·signature·count
5. UI feature directory count
6. decision register의 모든 상태
7. stale term search
8. local link와 fence checker
9. Windows/.NET/Windows App SDK/SDK lifecycle
10. dependency·installer·plugin license 원문
11. 열린 질문과 milestone gate
12. README 읽기 순서와 문서 지도
13. 사용자 소유 dirty file 비접촉 확인

## 11. 현재 남은 문서 리스크

- 547개 외부 URL occurrence는 전수 HTTP 상태를 확인하지 않았다.
- 외부 문서 내용은 서비스·version과 함께 바뀔 수 있다.
- Windows implementation이 없으므로 모든 실행 gate는 미완료다.
- macOS main이 움직이면 9be909c 뒤 delta를 새 baseline에 승격할지 결정해야 한다.
- 라이선스 문서는 법률 자문이 아니며 실제 release payload 승인이 필요하다.
- scanner matrix는 실제 Windows driver와 장치를 요구한다.
- monitor ICC/HDR·printer 품질은 physical measurement를 요구한다.

## 12. 감사 완료 정의

문서 감사가 완료됐다고 말하려면:

- [x] HEAD와 dirty boundary 확인
- [x] macOS source count 재계산
- [x] 31개 kernel count 확인
- [x] 상위 GPU·CPU·배포·scanner 결정 정렬
- [x] time-sensitive official source 재확인
- [x] README·결정·질문·spike 갱신
- [x] local link 0 broken
- [x] fence 0 error
- [x] Windows 실행을 했다고 과장하지 않음
- [ ] 외부 link 전수 availability — 현재 범위 밖
- [ ] Windows implementation gate — 문서 감사가 대체하지 않음

## 13. 공식 출처

- [Windows 11 release information](https://learn.microsoft.com/en-us/windows/release-health/windows11-release-information)
- [Windows App SDK release channels](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/release-channels)
- [Windows App SDK deployment overview](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/deploy-overview)
- [.NET support policy](https://dotnet.microsoft.com/en-us/platform/support/policy)
- [Windows SDK release notes](https://learn.microsoft.com/en-us/windows/apps/windows-sdk/release-notes)
- [Visual Studio 2026 release notes](https://learn.microsoft.com/en-us/visualstudio/releases/2026/release-notes)
- [WiX repository and OSMF notice](https://github.com/wixtoolset/wix)
- [LibRaw licensing](https://www.libraw.org/about)
- [TWAIN DSM repository](https://github.com/twain/twain-dsm)
