# 다음에 어디서부터 이어서 할 것인가

기준일: 2026-08-07

이 문서는 작업을 한동안 놓았다가 돌아왔을 때 가장 먼저 읽는 곳입니다. 이미 결정된 것을 다시
논쟁하지 않고, 다음 한 걸음을 바로 시작하기 위한 기록입니다.

## 지금 상태

전체 M0~M18 로드맵의 약 15%, 기반 구간 M0~M3 는 약 46% 입니다. 산정 근거는
`overall-roadmap.md`, 항목별 증거는 `../STATUS.md` 에 있습니다.

동작하는 것은 **CLI 수직 경로 하나**입니다. TIFF 디코드 → 스캐너 색상 → 수동 Dmin 현상 →
톤·포인트 커브·Color Mixer·Color Grading·Primary Calibration → 명시적 film-scan Film Look →
검증된 PNG16/TIFF16 게시까지 한 장이 끝까지 갑니다.

- 네이티브 테스트 39개, 관리 assertion 250개, 전부 통과
- Windows CI 가 PR 마다 돌고 벽시계 약 2분 30초
- 네이티브 엔진의 제3자 runtime dependency 0개 (Windows 기본 DLL 5개만)

**아직 앱은 존재하지 않습니다.** WinUI 셸은 6개 언어 골격뿐이고 엔진과 연결돼 있지 않습니다.
SQLite 영속성이 없어 아무것도 저장되지 않습니다. GPU 경로는 착수 전입니다.

## 닫힌 결정 — 다시 열지 마십시오

| 결정 | 내용 |
|---|---|
| ADR-0004 | 이미지·색상은 OS API 우선. **유효합니다.** |
| ADR-0017 | Windows `src`/`tests` 만 1차 native source, vendoring 금지 |
| ADR-0021 | macOS golden 은 test-only 관측. 관측 float 총량 512 상한 |
| ADR-0022 | 미사용 WebView2 페이로드 미배포 |
| ADR-0024 | ColorSync 의 섀도우 toe 를 재현하지 않음 |

**LittleCMS 검토는 폐기됐습니다.** 색 차이의 원인이 Windows CMS 선택이 아니라 ColorSync 가 ICC
사양에서 벗어나 있다는 사실이므로, Windows 에서 CMS 를 교체해도 macOS 와 같아지지 않습니다.
`overall-roadmap.md` 의 해당 항목은 이 사안에 한해 무효입니다.

---

## 1. SQLite 영속성 — 여기서 시작하십시오

`src/Catalog.Core/Storage/` 에 경로 해석과 프로세스 락까지 올라가 있습니다. SQLite 자체가 없습니다.

### 첫 행동: ADR-0025 를 먼저 쓰십시오

코드보다 결정이 먼저 막고 있습니다. **어떤 SQLite 를 쓸 것인가.**

macOS 는 OS 가 libsqlite3 를 공개 API 로 제공하지만 **Windows 에는 앱이 쓸 수 있는 시스템 SQLite 가
없습니다.** `winsqlite3.dll` 이 있긴 하나 Microsoft 가 서드파티 앱 사용을 공식 지원하지 않습니다.

**결론은 `Microsoft.Data.Sqlite` 입니다.** 근거:

- 카탈로그가 관리 코드(`Catalog.Core`, C#)에 살고 `Storage/` 도 C# 입니다. 네이티브에 SQLite 를
  넣으면 C# 이 자체 C ABI 를 한 겹 더 타야 하며 얻는 것이 없습니다.
- **"제3자 runtime dependency 0개" 는 네이티브 엔진에 대한 기준입니다.** 셸은 이미 WinUI 와
  Windows App SDK 위에서 돕니다. 관리 계층에 MIT 패키지를 더해도 네이티브 엔진의 0개는 유지됩니다.
- SQLite CVE 대응 책임을 Microsoft 가 집니다. 1인 프로젝트에서 이 값어치가 큽니다.
- ADR-0017 의 vendoring 금지를 건드릴 필요가 없습니다. 그 게이트는 이 저장소의 자산입니다.

`winsqlite3.dll` 은 배제합니다. 미지원 API 위에 제품 데이터베이스를 얹을 이유가 없습니다.

ADR 에 **"의존성 0개 원칙은 네이티브 엔진에 적용되며 관리 계층에는 적용되지 않는다"** 를 명시하십시오.
지금 애매하게 두면 이후 모든 패키지 추가에서 같은 논쟁이 반복됩니다.

`THIRD-PARTY-NOTICES.md` 에 MIT 한 절을 추가하고 `components.json` 의
`third_party_runtime_dependencies` 에도 등록하십시오.

### 그다음

스키마, 마이그레이션, 트랜잭션과 복구를 `Storage/` 위에 올립니다.

**종료 조건: 앱을 껐다 켜도 카탈로그가 남고, source 종류와 stage 순서가 바뀌지 않는다.**

---

## 2. 세로 슬라이스 — 실질적으로 가장 중요합니다

카탈로그가 저장되기 시작하면 곧바로 `카탈로그 → C ABI → WinUI 셸` 을 연결합니다.

**목표는 기능이 아닙니다.** 이미지 한 장이 Library 에 보이고, Develop 에서 슬라이더 하나가 먹고,
Export 가 파일을 쓰면 충분합니다. 못생겨도 됩니다.

### 왜 이것이 파이프라인 확장보다 먼저인가

지금까지 28단계를 CLI 로만 검증했습니다. CLI 검증은 앱에서 가장 위험한 것들을 **전부 우회합니다** —
UI 스레딩, 취소, 객체 수명, 사용자 조작 중 메모리 압박, C ABI 경계의 예외 전파.

구성요소를 격리해 만들면 통합 리스크가 프로젝트 끝으로 밀립니다. 데이터 계약과 지연·출력 형식이
뒤늦게 깨지고, 그때는 이미 각 구성요소를 최적화해 둔 뒤라 재작업 비용이 큽니다. 얇더라도 끝까지
한 번 뚫어 두면 구조와 패턴이 자리를 잡고 기본이 동작한다는 것이 증명됩니다.

M8(ABI·셸)이 18%, M9~M14(제품 표면)가 2% 라는 것은 **앱이 아직 없다**는 뜻입니다. 남은 85% 에
UI 와 장치 연동처럼 검증이 어렵고 되돌리기 비싼 것들이 몰려 있습니다.

### 미리 알아 둘 함정

WinUI 3 는 **STA** UI 모델입니다. 모든 UI 요소는 그것을 만든 스레드가 소유하고 그 스레드의
`DispatcherQueue` 에 묶입니다.

- 백그라운드 스레드에서 컨트롤을 건드리면 **예외가 납니다.**
- UWP 의 ASTA 와 달리 **reentrancy 보호가 없습니다.** 메시지를 펌프하는 async 코드에서 XAML
  컨트롤로 재진입하는 경로를 주의해야 합니다.
- 결과를 UI 로 돌릴 때는 `DispatcherQueue.TryEnqueue` 를 씁니다. 백그라운드 작업에 들어가기
  **전에** `DispatcherQueue` 를 캡처해 두는 편이 깔끔합니다. `HasThreadAccess` 로 확인할 수 있습니다.
- C++/WinRT 쪽 수명은 `winrt::implements` 파생과 `[this, self=get_strong()]` 캡처로 잡습니다.

이 함정들은 CLI 에서 절대 드러나지 않습니다. 세로 슬라이스를 미루면 이것들을 M9 이후에 한꺼번에
만나게 됩니다.

**종료 조건: 앱을 실행해 찍은 스크린샷 한 장.**

---

## 3. GPU 스파이크 — 버릴 코드로

M5 전체가 아니라 **스테이지 하나만** D3D11 로 던져 보고, FP32 결과가 기존 scalar golden 의
허용오차 안에 드는지 확인하는 정도입니다.

현재 모든 수치 계약이 CPU scalar 기준으로 고정돼 있습니다. macOS 는 Core Image(GPU)로 돌고
Windows 는 scalar 로 맞췄으며 앞으로 D3D11/WARP 가 들어옵니다. 세 구현이 서로 허용오차 안에
있어야 하는데, GPU 는 결합 순서와 정밀도가 CPU 와 미묘하게 달라 지금 잡아 둔 2.1e-3 / 4.0e-4 가
유지될 보장이 없습니다.

20단계를 scalar 가정 위에 다 쌓은 뒤 알면 golden 체계를 다시 설계해야 합니다. 세로 슬라이스
작업 중 어디쯤에서 하루 던져 보는 것으로 충분합니다.

**중요: golden 허용오차를 조이지 마십시오.** 세 구현은 각각 **하나의 기준(Core Image)** 과
비교돼야 합니다. 서로 사슬처럼 비교하면 오차가 누적됩니다.

---

## 4. 그 외 (순서 무관)

- 독립 Deflate 검증기를 구현하거나 dependency gate 를 열 근거를 확보합니다. 현재 Deflate 는
  fail-closed 로 격리돼 있습니다.
- 최종 working buffer 와 출력을 downstream row/tile 소비자로 넘기고 전체 process budget 을
  적용합니다. (M7, 현재 6%)
- WinUI 셸의 축소 폭·DPI·High Contrast·keyboard matrix 를 검증합니다.
- 나머지 Develop 후처리 단계를 macOS 실행 순서대로 이식합니다.

---

## 하지 않기로 한 것

**다점 TRC 프로파일의 ColorSync 측정.** 한때 다음 작업 1순위로 적었으나 철회합니다.

ADR-0024 가 이미 "재현하지 않는다" 로 결정했으므로, 측정 결과가 어느 쪽이든 **지금 하는 행동이
바뀌지 않습니다.** 차이의 크기도 8비트 코드 255단계 중 2~6, 그것도 하이라이트에 한정됩니다.
행동을 바꾸지 않는 측정에 macOS 세션과 CI 시간을 쓰는 것은 비용 대비 효과가 맞지 않습니다.

ADR-0024 의 재검토 조건이 실제로 발생하면 그때 합니다. 그 조건과 재현 방법은 ADR 에 이미 적혀
있으므로 다시 조사할 필요가 없습니다.

## 아직 열린 결정

- **Windows 가 macOS 와 같은 그림을 내야 하는가?** 제품 요구가 명시되면 ADR-0024 를 다시 엽니다.
  지금은 "측정된 플랫폼 차이" 로 둡니다.
- **카탈로그 스키마를 macOS 와 공유할 것인가?** 라이브러리 이식성에 영향을 줍니다. ADR-0025 를
  쓸 때 함께 판단하는 편이 좋습니다.

## 재개하는 방법

```powershell
# Windows 전체 게이트 (네이티브 + 관리)
.\Negaflow.Windows\scripts\ci-gate.ps1 -Preset x64-release
```

```bash
# 저장소 전체 provenance·라이선스 게이트
py scripts/ci/verify-provenance.py
```

macOS 쪽 짝은 `scripts/ci-gate.sh` 입니다. 두 입구는 분리돼 있으니 한쪽만 고치면 갈라집니다.
