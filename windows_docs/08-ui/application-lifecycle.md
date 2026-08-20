# 애플리케이션 수명주기·인스턴싱·활성화 명세

> 상태: 조건부 기준안과 구현 전 검증 계약  
> 기준일: 2026-08-04  
> macOS source 기준: 9be909c43edd7e04ba98cdc9d6a0c688739e343e  
> 관련 결정: [D-017](../00-overview/decision-register.md),
> [제품 불변식](../99-plan/product-invariants.md),
> [catalog와 storage](../14-persistence/catalog-and-storage.md)  
> 열린 질문: [Q-024, Q-025](../99-plan/open-questions.md)

## 0. 결론

Windows Negaflow의 기본 제품 모델은 **사용자·제품 채널별 primary UI process 하나**다.
두 번째 launch는 새 catalog writer나 새 main window를 만들지 않고 primary process로 activation을
전달한다. 다만 다음을 혼동하지 않는다.

- single UI instance는 catalog lock의 대체물이 아니다.
- `AppInstance` redirection 성공은 activation 작업 성공이 아니다.
- 정상 창 닫기와 Windows session 종료는 같은 시간·UX 계약이 아니다.
- crash recovery callback은 정상적인 autosave·journal의 대체물이 아니다.
- file association은 앱 인스턴싱을 구현했다는 이유만으로 자동 채택하지 않는다.

기본 구현 후보는 Windows App SDK `AppInstance`다. 공식 migration 안내의 single-instance 예제가
x64에서 동작한다고 명시하는 현재 문서 한계가 있으므로, ARM64에서 같은 API와 custom `Main` 경로가
실제 동작한다고 스파이크하기 전에는 전체 아키텍처 지원을 주장하지 않는다. 실패하면 제품의
single-primary 계약은 유지하고 named mutex와 authenticated local activation channel 같은 대안을
별도로 검증한다.

## 1. 이 문서가 소유하는 범위

### 포함

- process instancing과 activation redirection
- main, Settings, About, Help window의 process 수명 관계
- cold launch, warm activation, second launch
- 정상 사용자 close와 명시적 Exit
- installer/Restart Manager가 요청하는 close
- logoff, restart, shutdown의 session-end 처리
- crash, hang, 강제 종료 뒤 복구 경계
- catalog·defect edit·preview·backup·export·scanner job의 drain 순서
- x64와 ARM64의 같은 동작 검증

### 제외

- catalog schema와 transaction 내부: [catalog와 storage](../14-persistence/catalog-and-storage.md)
- installer protocol과 binary rollback: [update와 rollback](../11-distribution/update-and-rollback.md)
- scanner child process 종료: [scanner lifecycle](../10-scanner/plugin-security-and-lifecycle.md)
- GPU device lost: [canvas](swapchainpanel-canvas.md)
- 전체 diagnostics·dump privacy 정책: [profiling tools](../12-performance/profiling-tools.md)

## 2. macOS source에서 관찰한 현재 계약

### 2.1 Scene와 창

`Sources/negaflowApp/App/AppEntry.swift`에는 다음 scene가 있다.

| scene | 현재 의미 | Windows 대응 |
|---|---|---|
| `Window("negaflow", id: "main")` | primary workspace | `MainWindow` |
| About window | 단일 제품 정보 surface | owned/non-modal `AppWindow` 후보 |
| `Settings` | 환경 설정 | single Settings `AppWindow` |
| Quick Start Help window | 도움말 | owned/non-modal `AppWindow` 후보 |

`applicationShouldTerminateAfterLastWindowClosed`는 `true`다.
`ApplicationLifecycleTests.testLastWindowCloseRequestsFullApplicationTermination`도 이 동작을 고정한다.
따라서 Windows판에서 main window의 X 버튼을 tray/background mode로 바꾸면 현재 제품과 동등하지 않다.
Negaflow v1은 tray resident나 headless background shell을 만들지 않는다.

Settings, About, Help를 닫는 것은 app 종료가 아니다. main window close와 명시적 Exit만 전체 process
종료 coordinator로 들어간다. auxiliary window owner가 사라질 때는 해당 창을 먼저 닫거나 함께
종료하며 orphan top-level window를 남기지 않는다.

### 2.2 startup 순서

`AppModel+ApplicationStartup.swift`의 현재 순서는 다음과 같다.

```text
cache residency setting bind
→ library restore
→ scanner device refresh
→ UI test fixture 준비
→ 필요 시 selection 복구
→ production launch에서 scheduled backup 확인
```

Windows에서는 framework bootstrap과 instance redirection이 이 순서보다 앞에 추가된다. 그러나
library restore가 실패했을 때 빈 catalog를 ready 상태로 표시하지 않는 제품 계약은 그대로다.

### 2.3 정상 종료 transaction

`AppModel+LibraryTermination.swift`와 관련 테스트에서 관찰한 의미:

1. persistence가 비활성 또는 catalog가 이미 blocked면 owned preview를 정리하고 즉시 종료한다.
2. 종료 저장이 이미 진행 중이면 중복 시작하지 않고 기다린다.
3. uncommitted defect edit가 있으면 먼저 결과를 굽고 recipe 상태를 정리한다.
4. 최신 catalog generation snapshot을 만든다.
5. commit 뒤 다시 읽어 안전성을 승인한다.
6. commit 중 더 최신 dirty generation이 생기면 새 generation을 다시 승인한다.
7. 종료 시 backup 설정이면 검증된 backup까지 기다린다.
8. 성공한 뒤 app-owned preview를 지운다.

관련 테스트가 고정하는 항목:

- read-back 승인 전에는 종료 reply를 보내지 않음
- write/read-back 실패는 unsaved error와 preview를 보존
- 더 최신 generation이 생기면 첫 성공만으로 종료하지 않음
- on-termination backup은 검증이 끝난 뒤 reply
- 정상 완료 뒤 preview temp 제거

Windows 종료 coordinator는 이 순서를 단순 `Window.Closed` callback 하나로 축약하지 않는다.

### 2.4 현재 macOS 종료 실패의 중요한 모호성

현재 `NegaflowApplicationDelegate.applicationShouldTerminate`는 model completion의
`shouldTerminate == false`에서 동기 저장을 한 번 더 시도하지만, 그 결과와 무관하게
`reply(toApplicationShouldTerminate: true)`를 호출한다. model이 즉시 `.terminateCancel`을 반환하는
경로도 delegate는 `.terminateNow`로 바꾼다.

즉, model 수준 테스트는 실패 시 `false`를 보고하고 state를 보존하지만 app delegate 수준의 현재
동작은 **종료를 계속 진행**한다. `ApplicationLifecycleTests`도 snapshot 준비 실패가 명시적 Quit을
막지 않는 현재 동작을 고정한다.

이것은 다음 중 어느 사양인지 source만으로 결정할 수 없다.

- 의도된 UX: 오류를 기록하고 종료를 우선
- 안전상 결함: 마지막 verified catalog를 보장하지 못하면 정상 close를 취소해야 함
- 중간 정책: bounded retry 후 recovery marker를 남기고 사용자에게 선택권 제공

Windows에서 임의로 하나를 확정하지 않는다. [Q-025](../99-plan/open-questions.md)을 닫기 전 기준안은
다음과 같다.

- 정상 사용자 close: commit/read-back 실패 시 창을 유지하고 복구 action을 표시
- OS session end/critical shutdown: dialog나 긴 commit에 의존하지 않고 이미 저장된 journal을 사용
- installer update: controlled shutdown handshake가 실패하면 update를 중단

이 기준안은 데이터 안전에 보수적이지만 현재 macOS delegate의 마지막 실패 UX와 1:1 동일하지 않다.
따라서 parity deviation으로 명시하고 제품 결정을 받아야 한다.

### 2.5 source에서 확인되지 않은 activation

현재 macOS app entry에서 `onOpenURL`, document scene 또는 app-level external-event handler는 확인되지
않는다. Import Images/Folder는 menu·shortcut·picker와 root drag/drop으로 진입한다.

따라서 Windows v1에서 file association, custom protocol, login startup을 넣는 것은 단순 포팅이 아니라
새 제품 동작이다. association은 사용자가 승인한 별도 결정과 installer/uninstall 복구가 있을 때만
활성화한다.

## 3. Windows process와 instance 모델

### 3.1 기본은 single primary UI process

Windows App SDK WinUI 앱은 기본적으로 multi-instance다. Negaflow는 기본 동작을 그대로 쓰지 않는다.

이유:

- 한 사용자의 기본 library에는 writer 하나만 있어야 한다.
- scanner adapter·device session과 export destination reservation의 소유자가 명확해야 한다.
- second launch가 catalog-blocked recovery window를 두 개 만들면 복구 의미가 모호해진다.
- macOS 제품은 한 application process 안의 main/Settings/About/Help scene로 동작한다.
- 두 main window에 같은 selection/model을 복제하는 것은 요청된 기능이 아니다.

single-primary 범위:

```text
Windows user SID
× product channel (Stable/Beta/Internal)
× install identity
```

machine-global mutex 하나를 쓰지 않는다. 다른 로그인 사용자는 각자 app을 실행할 수 있어야 하고,
Stable과 Beta는 별도 app data root·update feed·activation key를 가져야 한다.

### 3.2 instance key와 catalog lock은 독립이다

| 보호 | 막는 문제 | 실패 시 동작 |
|---|---|---|
| instance registration | 같은 channel의 shell 중복 | primary로 activation redirect |
| catalog process lock | 다른 channel/version/process의 같은 library write | recovery/read-only가 승인되기 전 fail closed |
| export reservation | 같은 destination 충돌 | 사용자에게 명시적 conflict |
| scanner device ownership | 같은 physical device 동시 제어 | adapter/device busy |

Beta와 Stable이 각자의 primary instance를 가져도 같은 catalog를 동시에 쓸 수 있다는 뜻이 아니다.
catalog lock은 process name이나 activation key가 아니라 실제 library identity를 기준으로 한다.

### 3.3 `AppInstance` 후보

정상 후보 흐름:

```text
process entry
→ Windows App SDK runtime/bootstrap 확인
→ current activation args 획득
→ FindOrRegisterForKey(channel-scoped primary key)
   ├─ current: Activated handler 연결 후 startup 계속
   └─ other: RedirectActivationToAsync(args)
             → 성공/실패 기록
             → 이 process를 명시적으로 종료
```

중요한 공식 API 의미:

- redirection은 async다.
- Windows App SDK의 redirection은 terminal operation이 아니다.
- redirect한 process는 성공 뒤 스스로 종료해야 한다.
- argument를 명시적으로 전달한다.
- circular redirection 방어는 앱 책임이다.
- STA를 동기 block해 redirection을 기다리면 안 된다.

primary window, catalog, engine, scanner host를 만들고 난 뒤 redirection 여부를 판단하지 않는다.
버릴 resource와 side effect가 생기기 전 custom `Main`에서 처리하는 것이 기준안이다.

### 3.4 ARM64는 별도 gate다

Microsoft의 현재 lifecycle migration 문서에는 제시한 single-instance code가 x64 target에서 기대대로
동작한다는 주의가 있다. 반면 2026-07-11에 갱신된 일반 multi-instance 안내는 custom entry point와
`AppInstance` redirection을 architecture 제한 없이 설명한다. 이 문서 차이는 `AppInstance` 전체가
ARM64에서 미지원이라는 증거도 아니고 Negaflow ARM64 경로가 검증되었다는 증거도 아니다.

필수 스파이크:

- C# custom `Main` x64/ARM64 compile·launch
- packaged test와 실제 unpackaged self-contained 모두
- cold-launch 100-way race에서 primary 하나
- second activation redirect/exit
- primary가 closing/unregister 중인 race
- Stable/Beta와 서로 다른 Windows user session
- ARM64 native process에서 x64 helper를 요구하지 않음

실패 대안은 architecture마다 서로 다른 제품 의미를 만드는 것이 아니다. named mutex와 같은
instance-election primitive, ACL로 제한된 named pipe 또는 다른 authenticated local channel을 함께
설계해 x64·ARM64가 같은 activation semantics를 가진다.

## 4. activation 종류와 제품 정책

2026-08-04 공식 문서상 unpackaged Windows App SDK rich activation은 일반적으로 `Launch`, `File`,
`Protocol`, `StartupTask`를 다룰 수 있다. API 가능성은 제품 채택과 다르다.

| activation kind | v1 정책 | 이유 |
|---|---|---|
| `Launch` | 필수 | shortcut, Start, executable launch |
| second `Launch` | 필수 redirect | 기존 main window activate |
| `File` | 조건부 | 현재 macOS의 명시적 import보다 범위 확대 |
| `Protocol` | 기본 비활성 | 외부 입력·보안·idempotency 계약 없음 |
| `StartupTask` | 제외 | tray/background workflow가 없음 |
| notification activation | 제외 | cloud/push 요구사항 없음 |

### 4.1 activation envelope

UI service로 전달하는 내부 envelope는 OS object를 장기 보관하지 않는다.

```text
activation_id
kind
received_monotonic_time
source_process/channel identity
bounded normalized arguments
validated file candidates
delivery attempt
terminal disposition
```

terminal disposition:

- `accepted`
- `deferred`
- `rejected_invalid`
- `rejected_busy`
- `duplicate`
- `failed`

OS activation을 받았다는 사실과 import transaction이 성공했다는 사실을 별도 기록한다.

### 4.2 warm activation routing

primary `Activated` callback은 다음을 직접 수행하지 않는다.

- catalog write
- image decode
- file enumeration
- window를 무조건 새로 생성
- active export/scan 취소
- modal dialog 위에 또 dialog 표시

callback은 arguments를 bounded immutable envelope로 바꾸고 UI `DispatcherQueue`에 전달한다. UI
coordinator는 현재 lifecycle state와 transaction state를 다시 확인한다.

```text
Running + Launch
  → main window show/activate

Running + approved File
  → validate → import queue → existing selection policy

CatalogBlocked + File
  → recovery surface 유지 → activation을 bounded defer 또는 명시적 reject

ClosingBeforeCommit + activation
  → close 취소가 승인된 경우에만 Running으로 복귀

ExitCommitted + activation
  → 현재 instance에 적용 금지, 새 launch가 인수하도록 실패/재시도
```

### 4.3 file activation 검증

association이 승인되더라도 file path를 신뢰하지 않는다.

- shell item을 canonical path string 하나로 축약하기 전에 실제 handle과 type을 확인
- directory, reparse point, cloud placeholder, removable/network path 구분
- 파일 수·총 path bytes·enumeration depth 상한
- extension이 아니라 decoder probe로 실제 형식 확인
- executable, plugin, preset bundle을 image로 실행하지 않음
- 기존 import duplicate·source identity·원본 불변 transaction 사용
- partial success와 unsupported file을 명시적으로 보고

association 등록·제거는 installer owner가 담당한다. 매 launch마다 registry를 무조건 다시 쓰지 않는다.

## 5. 창 소유권과 process lifetime

### 5.1 window registry

| window | cardinality | owner | close 효과 |
|---|---:|---|---|
| Main | 1 | process | 전체 app 종료 요청 |
| Settings | 0..1 | Main | 설정 창만 닫기 |
| About | 0..1 | Main | 창만 닫기 |
| Quick Start | 0..1 | Main | 창만 닫기 |
| modal dialog | 0..1 per owner | invoking window | invoking operation으로 결과 전달 |

`AppWindow`는 top-level `HWND`와 1:1이다. registry는 `WindowId`, HWND, XAML root,
`DispatcherQueue`, owner, lifecycle generation을 함께 추적한다. 닫힌 창의 XamlRoot나 HWND를 picker,
dialog, canvas attach에 다시 사용하지 않는다.

### 5.2 main activation

second launch가 primary로 redirect되면:

1. main window가 최소화되어 있으면 정상 restore한다.
2. 현재 virtual desktop/focus-stealing 정책을 존중한다.
3. 무조건 foreground 강탈을 가정하지 않는다.
4. attention이 필요하지만 foreground activation이 거부되면 taskbar signal 같은 native 대안을 검토한다.
5. About/Settings가 열려 있어도 새 main window를 만들지 않는다.

`Show`, `Activate`, `SetForegroundWindow` 성공을 같은 것으로 기록하지 않는다. foreground 정책은 실제
Windows user gesture와 automation에서 검증한다.

### 5.3 placement

- main과 Settings placement ID를 분리한다.
- monitor 제거, DPI 변경, work area 변화 뒤 보이는 영역으로 clamp한다.
- maximized, full-screen, normal placement를 분리한다.
- 최소 창 크기는 effective pixel이 아니라 XAML/DPI 계약으로 계산한다.
- crash 직전 drag의 매 tick을 동기 저장하지 않고 debounced snapshot을 쓴다.
- placement 손상이 catalog blocked로 오인되지 않게 presentation store를 분리한다.

## 6. 정상 close coordinator

### 6.1 상태 기계

```text
Running
  └─ close request → CloseIntercepted
                      ├─ no durable work → ExitApproved
                      └─ work → Draining
                                  → BakingDefects
                                  → CatalogCommit
                                  → ReadbackVerify
                                  → OptionalBackup
                                  ├─ success → ExitApproved
                                  └─ failure → ExitFailed

ExitFailed
  ├─ Retry → Draining
  ├─ ReturnToApp → Running
  └─ DiscardAndExit → product policy가 명시적으로 허용할 때만
```

각 state transition은 monotonically increasing `shutdown_generation`을 가진다. 이전 async completion이
새 close attempt를 승인하지 못한다.

### 6.2 `AppWindow.Closing`

`AppWindow.Closing`은 `AppWindowClosingEventArgs.Cancel`을 제공한다. async commit이 필요한 Negaflow는
첫 close event에서 닫기를 취소하고 coordinator를 시작한 뒤, 성공하면 one-shot bypass token으로 다시
닫는다.

규칙:

- event handler에서 `.Result`, `.Wait()` 또는 UI message pump block 금지
- 첫 event에서 `Cancel = true`
- UI는 중복 close/Exit command를 같은 shutdown generation으로 coalesce
- 성공 뒤 `allow_next_close` token을 한 번만 소비
- programmatic second close가 다시 transaction을 시작하지 않음
- commit 실패 시 token을 만들지 않음
- closing 중 Settings/About/Help를 먼저 닫아도 main commit owner는 유지

XAML `Window.Closed`는 이미 닫힌 뒤 cleanup signal로만 쓴다. durable commit 시작점으로 사용하지 않는다.

### 6.3 drain 순서

정상 close에서 모든 background 작업을 한꺼번에 kill하지 않는다.

| 작업 | close 시 정책 |
|---|---|
| interactive preview/render | cancel/supersede, published recipe 보존 |
| defect gesture | current macOS 의미에 맞게 bake 또는 명시적 실패 |
| catalog debounce save | cancel 후 최신 snapshot으로 통합 |
| scan preview | uncommitted app-owned temp만 정리 |
| physical full scan | cooperative cancel 후 adapter unwind; published artifact 보존 |
| export before publish | cancel 가능, staging 제거 |
| export publish/verify | critical section 완료 또는 실패 receipt |
| print spool submit | OS spooler state와 app generation 분리 |
| scheduled backup | on-termination 설정일 때 verified completion 정책 |
| updater | app shutdown receipt가 나온 뒤만 install |

scanner process 종료와 catalog commit을 병렬로 무제한 기다리지 않는다. dependency graph와 deadline을
명시하며, 정상 user close에는 진행 단계와 취소/복구 의미를 보인다.

### 6.4 종료 완료 receipt

updater나 test harness가 사용할 receipt:

```text
shutdown_generation
reason
catalog_generation_requested
catalog_generation_verified
backup_generation_verified 또는 null
active export/scanner terminal disposition
preview cleanup result
completed_at
result
```

receipt에 source path, image metadata, protocol argument를 넣지 않는다. updater는 receipt와 process exit를
둘 다 확인하며, process name만 보고 unrelated process를 종료하지 않는다.

## 7. OS session end와 update 종료

### 7.1 정상 close와 다른 계약

| 원인 | 사용자 UI | 허용 작업 | 신뢰할 복구 수단 |
|---|---|---|---|
| main X / Exit | 진행·오류·재시도 가능 | full verified close transaction | catalog commit/read-back |
| installer controlled shutdown | bounded 안내 | current critical section, checkpoint, receipt | update journal + prior autosave |
| `WM_QUERYENDSESSION` | dialog 의존 금지 | 빠른 checkpoint와 restart registration update | periodic save + journal |
| `WM_ENDSESSION(TRUE)` | prompt 금지 | handle close, bounded marker | 다음 launch recovery |
| crash/hang | UI 보장 없음 | recovery callback은 제한적 best effort | prior atomic commit + WER |
| process kill/power loss | 없음 | 실행 기회 없음 | atomic writes + journal + read-back recovery |

Microsoft는 update/session 종료 메시지에 응답할 시간이 짧고 예시 기준 각 메시지에 5초 안에
응답해야 한다고 안내한다. 그러므로 100MP render, defect bake, full backup, scanner warm-up 취소를
`WM_QUERYENDSESSION`에서 새로 시작하지 않는다.

### 7.2 Win32 message bridge

WinUI/`AppWindow`만으로 session-end 의미가 모두 전달된다고 가정하지 않는다. main HWND subclass 또는
승인된 message bridge가 다음을 lifecycle coordinator에 전달한다.

- `WM_QUERYENDSESSION`
- `WM_ENDSESSION`
- `ENDSESSION_CLOSEAPP`
- `ENDSESSION_CRITICAL`
- `ENDSESSION_LOGOFF`

`lParam`은 bit mask다. equality 하나로 분기하지 않는다.

`WM_QUERYENDSESSION`에서 기본은 사용자의 shutdown 의사를 존중해 빠르게 응답한다. 데이터 손실을
막는 주된 방법은 shutdown을 장시간 block하는 것이 아니라 평상시의 작은 atomic commit, checkpoint와
crash-safe journal이다. 실제 미디어 굽기처럼 중단 자체가 물리 손상을 만드는 경우가 아니라면
`ShutdownBlockReasonCreate`를 일상적인 저장 지연 수단으로 쓰지 않는다.

### 7.3 Restart Manager

installer는 먼저 Negaflow 자체 controlled shutdown handshake를 사용한다. Restart Manager는 열린 binary
handle을 찾고 system update와 협력하는 보조 수단이다.

- update가 active scan/export publish를 강제 중단하지 않음
- app이 명시적으로 close를 거부하면 update를 연기
- 다른 user session을 자동 kill하지 않음
- `ENDSESSION_CLOSEAPP`에서 prompt 없이 recoverable state로 전환
- installer가 catalog migration을 수행하지 않음

### 7.4 Application Recovery and Restart

후보 API:

- `RegisterApplicationRecoveryCallback`
- `ApplicationRecoveryInProgress`
- `ApplicationRecoveryFinished`
- `RegisterApplicationRestart`

이 기능은 optional defense다.

- recovery callback에서 전체 catalog graph를 새로 serialize하지 않는다.
- 이미 준비된 bounded recovery snapshot이나 journal marker만 flush하는 안을 검증한다.
- callback ping interval을 지킨다.
- `ApplicationRecoveryFinished`가 process를 종료하는 의미를 테스트한다.
- restart는 user consent, update path, 60초 anti-loop 조건 등 OS 정책의 영향을 받는다.
- restart command line에는 임의 path·secret·activation payload를 넣지 않는다.
- restart 뒤 primary instance election과 recovery를 다시 수행한다.

fatal exception을 잡고 손상된 process에서 계속 실행하지 않는다. WER dump와 recovery artifact의 역할을
분리한다.

## 8. startup와 recovery 순서

### 8.1 cold launch

```text
process entry
→ runtime/dependency integrity
→ instance election/redirection
→ crash/update marker read
→ app data root와 channel identity 확정
→ catalog process lock
→ interrupted export/scan/update journal 검사
→ catalog primary/backup/read-back health 검사
→ presentation preference 읽기
→ MainWindow + loading/recovery root 생성
→ catalog restore
   ├─ blocked → recovery workspace
   └─ ready → selection/workspace 복구
→ scanner discovery는 app-ready와 별도 async phase
→ scheduled backup due 확인
```

scanner discovery가 늦다고 catalog recovery를 막지 않는다. 반대로 catalog가 blocked인데 scanner
discovery 성공을 app ready로 해석하지 않는다.

### 8.2 warm activation

warm activation은 cold startup 함수를 다시 호출하지 않는다.

- process lock 재획득 금지
- catalog restore 재시작 금지
- scheduled backup 중복 시작 금지
- AppModel·engine singleton 중복 생성 금지
- activation별 bounded transaction만 생성

### 8.3 recovery precedence

여러 marker가 동시에 있으면 다음 우선순위를 쓴다.

1. mixed-version/update integrity failure
2. catalog open/transaction ambiguity
3. pending restore/migration
4. ambiguous export publish receipt
5. interrupted scanner staging
6. presentation state 복구
7. deferred external activation

file activation 때문에 blocked catalog를 빈 catalog로 대체하거나 자동 orphan cleanup하지 않는다.

## 9. activation·close 동시성

### 9.1 소유 identity

모든 비동기 결과는 적용 직전에 다음을 확인한다.

```text
process_instance_id
app_lifecycle_generation
window_generation
catalog_generation/session
request/activation/shutdown id
owner frame 또는 transaction id
```

### 9.2 주요 race

| race | 안전 결과 |
|---|---|
| second launch vs first process startup | primary 하나, activation 0/1회 정확히 전달 |
| activation vs catalog blocked | import 미실행, recovery surface 유지 |
| close vs activation | 명시된 state machine만 전이, 새 window 중복 없음 |
| close vs export publish | terminal receipt 뒤 catalog generation 승인 |
| close vs scanner result | session identity가 맞는 committed result만 채택 |
| close vs newer dirty generation | 최신 generation 재승인 |
| primary exit vs redirect | redirect failure가 무한 재시작/loop를 만들지 않음 |
| update vs second launch | update gate가 새 activation을 받지 않거나 새 version으로 넘김 |
| crash recovery vs normal startup | recovery marker exactly once 소비 |

activation queue는 무한하지 않다. 같은 kind와 동일 payload identity는 coalesce할 수 있지만 terminal
disposition을 잃지 않는다.

## 10. 보안과 privacy

- instance key에 raw user path나 library path를 넣지 않는다.
- local activation channel은 같은 user SID와 install/channel identity만 허용한다.
- named object DACL을 default permissive 상태로 두지 않는다.
- activation payload byte·file count·nesting에 상한을 둔다.
- file/protocol text를 log에 그대로 남기지 않는다.
- crash dump에는 pixel buffer, path, metadata, access token이 들어갈 수 있다고 가정한다.
- support bundle에 dump를 자동 포함하지 않고 명시적 동의·redaction·size 확인을 거친다.
- recovery command line은 opaque bounded ID만 사용한다.
- side-by-side channel이 서로의 activation registration을 제거하지 않는다.
- uninstall은 자기 channel/architecture가 소유한 registration만 제거한다.

## 11. 진단 event

최소 event:

```text
app.process.start
app.instance.elected
app.activation.received
app.activation.redirect.started/completed/failed
app.window.created/closing/closed
app.shutdown.started/phase/completed/failed
app.session.query_end/end
app.recovery.registered/invoked/completed
app.restart.registered/activation
```

공통 field:

- product/channel/version
- architecture
- process instance ID
- lifecycle generation
- activation/shutdown ID
- monotonic duration
- phase/result/stable error code
- OS build와 Windows App SDK runtime identity

포함하지 않는 field:

- 전체 command line
- raw activation URI
- source/export path
- image content·metadata
- scanner serial number

## 12. x64·ARM64 검증 matrix

| 시나리오 | x64 Intel | x64 AMD | ARM64 Qualcomm |
|---|---:|---:|---:|
| cold launch | 필수 | 필수 | 필수 |
| 100-way launch race | 필수 | smoke | 필수 |
| warm activation | 필수 | smoke | 필수 |
| main close + read-back | 필수 | smoke | 필수 |
| newer dirty generation | 필수 | smoke | 필수 |
| Settings/About/Help ownership | 필수 | smoke | 필수 |
| update close/Restart Manager | 필수 | smoke | 필수 |
| logoff/restart | 필수 | smoke | 필수 |
| crash/hang recovery | 필수 | smoke | 필수 |
| Stable/Beta side-by-side | 필수 | smoke | 필수 |

ARM64에서 x64 emulation으로 shell을 실행한 결과는 ARM64 pass가 아니다. x86 scanner adapter가 살아 있어도
primary shell, lifecycle coordinator, catalog owner와 engine은 native ARM64다.

## 13. 결정적 test corpus와 fault injection

### 13.1 instance·activation

- 2, 10, 100 processes 동시 launch
- primary startup의 각 phase에서 second launch
- redirect 직전 primary 정상 종료
- primary crash와 registration race
- duplicate activation ID
- oversized file list
- invalid/reparse/offline/cloud placeholder item
- separate Windows users
- Stable/Beta/Internal side-by-side

### 13.2 normal close

- clean catalog/no jobs
- dirty generation
- uncommitted defect gesture
- commit write failure
- read-back failure
- commit 중 더 최신 dirty generation
- on-termination backup success/failure
- export before/after publish
- scanner preview/full transfer/finalization
- repeated X/Alt+F4/Exit command
- Settings가 열린 상태

### 13.3 session/update/crash

- `WM_QUERYENDSESSION` accept/cancel sequence
- `WM_ENDSESSION` true/false
- logoff, restart, update close
- 5초 deadline보다 느린 injected storage
- WER recovery callback ping timeout
- crash before/after catalog rename
- kill process tree
- power-loss harness
- restart loop prevention

### 13.4 assertions

- primary UI process exactly one per scope
- activation terminal disposition exactly once
- no duplicate catalog writer
- no empty-catalog overwrite
- no unverified generation marked clean
- original files unchanged
- no partial final export
- no orphan scanner child
- no stale callback after lifecycle generation change
- failed normal close policy matches Q-025 decision
- shutdown deadline miss를 성공으로 기록하지 않음

## 14. 성능 budget

실측 전에 숫자를 임의 확정하지 않는다. 다음 phase를 분리해 p50/p95/p99를 수집한다.

- process entry → instance election
- secondary launch → redirect completion → secondary exit
- cold process entry → recovery/loading window visible
- loading window → catalog ready
- warm activation → main visible/attention delivered
- close request → first visible phase
- close request → catalog verified
- close request → process exit
- `WM_QUERYENDSESSION` handler duration
- crash recovery callback duration

UI first frame를 빨리 보이게 하려고 catalog 오류를 숨기지 않는다. 반대로 scanner enumeration과 전체
thumbnail preload를 first usable workspace의 blocking prerequisite로 만들지 않는다.

## 15. milestone 연결

### M8

- custom `Main`과 instance election x64/ARM64
- main/Settings/About/Help window registry
- activation queue와 UI dispatcher
- normal close coordinator skeleton
- one-image workflow 중 second-launch/close race

### M9

- approved import activation이 Library transaction으로 연결
- catalog blocked/offline/duplicate UX
- drag/drop, picker, activation의 동일 import semantics

### M17

- installer registration ownership
- Restart Manager와 controlled shutdown receipt
- update 중 launch gate
- association install/repair/uninstall/rollback
- recovery/restart registration

### M18

- actual x64/ARM64 lifecycle matrix
- logoff/restart/update/manual close QA
- privacy review와 support evidence
- Q-024·Q-025 닫힘

## 16. release gate

- [ ] primary UI process 범위가 user/channel/install identity로 고정됨
- [ ] x64·ARM64에서 같은 instance election/redirect 동작
- [ ] second process가 window/catalog/engine을 만들기 전에 redirect 판단
- [ ] redirection success 뒤 secondary가 명시적으로 종료
- [ ] primary closing race가 activation loss·loop를 만들지 않음
- [ ] main close는 full app 종료, auxiliary close는 local close
- [ ] catalog read-back과 최신 generation 승인
- [ ] normal close 실패 정책이 Q-025로 승인됨
- [ ] `WM_QUERYENDSESSION`/`WM_ENDSESSION` 5초 조건에서 안전
- [ ] crash/kill/power loss는 prior journal로 복구
- [ ] updater가 shutdown receipt와 process exit를 모두 확인
- [ ] association을 채택했다면 install/repair/uninstall/rollback 검증
- [ ] activation/dump/support artifact privacy review
- [ ] 실제 UI·session 테스트를 실행하지 않고 완료라고 표시하지 않음

## 17. 남은 위험

- Windows App SDK single-instance guidance의 x64 명시와 ARM64 실제 동작 차이
- unpackaged self-contained bootstrap 이전/이후 instance election 순서
- `AppWindow.Closing` async re-entry와 one-shot bypass race
- Windows foreground activation 제한으로 기존 창이 전면에 오지 않을 수 있음
- current macOS delegate와 데이터 안전 기준안의 종료 실패 UX 차이
- update, logoff, user close에서 서로 다른 deadline을 하나의 함수로 오용할 위험
- recovery callback에서 손상된 heap/COM/XAML을 사용하려는 위험
- file association이 현재 제품 범위를 불필요하게 넓힐 위험

## 18. 공식 자료

- [App instancing with the app lifecycle API](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/applifecycle/applifecycle-instancing)
- [Multi-instance apps with Windows App SDK](https://learn.microsoft.com/en-us/windows/apps/develop/launch/multi-instance-apps)
- [Create a single-instanced WinUI 3 app with C#](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/applifecycle/applifecycle-single-instance)
- [Application lifecycle functionality migration](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/migrate-to-windows-app-sdk/guides/applifecycle)
- [Rich activation with the app lifecycle API](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/applifecycle/applifecycle-rich-activation)
- [App activation for Windows App SDK desktop apps](https://learn.microsoft.com/en-us/windows/apps/develop/launch/activate-an-app)
- [Manage app windows](https://learn.microsoft.com/en-us/windows/apps/develop/ui/manage-app-windows)
- [AppWindow.Closing](https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.ui.windowing.appwindow.closing)
- [AppWindowClosingEventArgs.Cancel](https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.ui.windowing.appwindowclosingeventargs)
- [WM_QUERYENDSESSION](https://learn.microsoft.com/en-us/windows/win32/shutdown/wm-queryendsession)
- [WM_ENDSESSION](https://learn.microsoft.com/en-us/windows/win32/shutdown/wm-endsession)
- [Registering for Application Recovery](https://learn.microsoft.com/en-us/windows/win32/recovery/registering-for-application-recovery)
- [Application Recovery and Restart Functions](https://learn.microsoft.com/en-us/windows/win32/recovery/application-recovery-and-restart-functions)
- [RegisterApplicationRestart](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-registerapplicationrestart)
- [Using Windows Error Reporting](https://learn.microsoft.com/en-us/windows/win32/wer/using-wer)
