# Windows 업데이트와 롤백 설계

기준일: 2026-08-04  
상태: Direct 배포 transaction 결정, 수치 timeout·rollout 비율은 실측 전  
관련 문서:

- [배포 채널](deployment-channels.md)
- [서명과 installer 신뢰](msix-signing.md)
- [catalog와 storage](../14-persistence/catalog-and-storage.md)
- [scanner plugin lifecycle](../10-scanner/plugin-security-and-lifecycle.md)
- [product invariants](../99-plan/product-invariants.md)

## 1. 결론

Direct Stable/Beta의 업데이트는 **서명된 metadata → 완전한 signed installer 다운로드 → app 종료 → Windows
Installer transaction → 새 app health check** 순서로 수행한다.

```text
Negaflow.exe
  check signed feed
  download full installer to protected staging
  verify size + SHA-256 + Authenticode + version + architecture
  checkpoint app state and catalog backup
  write update intent journal
  exit cleanly
        ↓
signed updater/installer
  reverify same artifact
  execute MSI/Burn upgrade
  let Windows Installer rollback deployment failure
  launch exact new version
        ↓
new Negaflow.exe
  verify installed payload/ABI/schema
  recover pending jobs safely
  mark health success
  finalize update journal
```

v1은 delta patch보다 **full offline installer**를 사용한다. 다운로드 크기 최적화보다 byte provenance, rollback,
architecture 분리, 재현 가능한 support를 우선한다.

가장 중요한 구분:

1. **deployment rollback**: installer가 실패해 old binary를 복구하는 것
2. **application-data rollback**: catalog/sidecar migration을 이전 상태로 되돌리는 것
3. **product downgrade**: 사용자가 더 낮은 app version을 다시 설치하는 것

이 셋은 같은 기능이 아니다. Windows Installer rollback이 catalog schema를 되돌려주지 않는다. 반대로 catalog
backup이 깨진 binary install을 수리하지 않는다.

## 2. 공식 근거

- [Windows Installer rollback](https://learn.microsoft.com/en-us/windows/win32/msi/rollback-installation)
- [Windows Installer major upgrades](https://learn.microsoft.com/en-us/windows/win32/msi/major-upgrades)
- [Package codes](https://learn.microsoft.com/en-us/windows/win32/msi/package-codes)
- [Restart Manager overview](https://learn.microsoft.com/en-us/windows/win32/rstmgr/about-restart-manager)
- [Restart Manager with a primary installer](https://learn.microsoft.com/en-us/windows/win32/rstmgr/using-restart-manager-with-a-primary-installer)
- [Background Intelligent Transfer Service](https://learn.microsoft.com/en-us/windows/win32/bits/about-bits)
- [App Installer update settings](https://learn.microsoft.com/en-us/windows/msix/app-installer/update-settings)
- [Create an App Installer file](https://learn.microsoft.com/en-us/windows/msix/app-installer/how-to-create-appinstaller-file)
- [MSIX differential updates](https://learn.microsoft.com/en-us/windows/msix/desktop/managing-your-msix-deployment-update)
- [Enterprise MSIX deployment](https://learn.microsoft.com/en-us/windows/msix/desktop/managing-your-msix-deployment-enterprise)
- [Publish Store MSI/EXE updates](https://learn.microsoft.com/en-us/windows/apps/publish/publish-your-app/msi/publish-update-to-your-app-on-store)

## 3. 불변식

업데이트는 다음을 절대 깨지 않는다.

- source original을 수정·교체·삭제하지 않음
- third-party XMP를 덮어쓰지 않음
- catalog missing/corrupt를 empty catalog로 취급하지 않음
- corrupt catalog를 근거로 orphan cleanup하지 않음
- active export/scan을 조용히 중단하고 성공 처리하지 않음
- 새 binary와 old native DLL이 섞인 상태로 launch하지 않음
- signature/hash/version 검증 실패 artifact를 실행하지 않음
- Stable이 Beta feed/artifact로 fallback하지 않음
- x64가 ARM64 package를, ARM64가 x64 package를 native update로 설치하지 않음
- downgrade로 newer schema를 손상하지 않음
- core update가 scanner plugin bytes를 덮어쓰지 않음
- uninstall/update가 사용자 원본과 export를 지우지 않음

업데이트를 못 해도 현재 app의 offline import/develop/export가 가능한 경우 그 기능을 막지 않는다. 단, 알려진
critical security issue가 현재 operation 자체를 위험하게 만들면 정확한 범위와 이유를 표시한다.

## 4. 구성 요소와 권한

### 4.1 app

Negaflow 본체가 담당:

- update policy와 channel 읽기
- feed fetch/parse/signature 검증
- 대상 version/architecture 선택
- download 요청과 progress UI
- artifact pre-verification
- active job drain/cancel UX
- catalog checkpoint/backup 검증
- update journal 작성
- clean shutdown

본체가 설치 directory의 자기 binary를 직접 교체하지 않는다.

### 4.2 updater/launcher helper

signed helper가 담당:

- app process 종료 확인
- staging artifact 재검증
- expected install context 확인
- MSI/Burn 실행과 exit code capture
- exact target version launch
- update result handoff

helper는 일반-purpose command runner가 아니다. command line에 임의 executable/arguments를 받아 elevated로
실행하지 않는다. 요청 schema와 install root, product code, target artifact를 allowlist한다.

### 4.3 Windows Installer

Windows Installer는 install script 실행 중 rollback script와 필요한 old file copy를 만들고, install failure 시
기본적으로 rollback한다. 이 기능을 비활성화하지 않는다.

custom action은 최소화한다. 꼭 필요하면:

- deferred execution과 권한 범위를 명확히 함
- corresponding rollback action 제공
- idempotent/retry-safe 설계
- user data를 건드리지 않음
- network access 금지
- arbitrary script execution 금지

가능한 작업은 WiX/MSI 표준 table/component semantics로 표현한다.

### 4.4 Restart Manager

Windows Installer 4.0 이상은 Restart Manager를 사용해 사용 중인 file을 가진 app을 찾아 재시작을 줄일 수 있다.
그러나 Negaflow는 unsaved edit와 active export/scan이 있으므로 installer가 갑자기 강제 종료하기 전에 app
자체의 controlled shutdown을 먼저 수행한다.

Restart Manager는 마지막 방어다.

- app이 restart request를 받으면 state를 안전하게 저장
- active scanner plugin child를 bounded cancel
- export journal checkpoint
- catalog transaction 종료
- dirty setting flush
- restart command에 update-complete token 사용

다른 user session의 process를 자동으로 종료할 수 있다고 가정하지 않는다.

## 5. update feed trust

### 5.1 TLS만으로 끝내지 않는다

HTTPS는 transport confidentiality/integrity에 필요하지만 update authority의 유일한 root가 아니다. feed
metadata는 detached signature 또는 signed envelope를 갖는다.

검증 순서:

1. HTTPS endpoint와 redirect policy 확인
2. 최대 response size와 timeout 적용
3. strict JSON/schema parse
4. metadata signature 검증
5. channel과 architecture 일치
6. issued/expiry/time policy
7. version monotonic/authorized rollback 정책
8. installer URL allowlist
9. size/hash/signer policy 확보

signature가 invalid하면 cache나 unsigned alternate feed로 fallback하지 않는다.

### 5.2 metadata authority와 binary signer

두 trust root를 분리한다.

- release metadata signing key: 어떤 version/hash를 제공할지 승인
- Authenticode publisher: downloaded executable bytes와 publisher를 증명

둘 다 맞아야 install한다. CDN 침해로 signed old installer가 바뀐 URL에 놓여도 metadata hash/anti-rollback이
막아야 한다. code-signing key 하나가 침해되어도 metadata authority가 승인하지 않은 artifact는 거부해야 한다.

### 5.3 feed schema

최소 필드:

```json
{
  "schemaVersion": 1,
  "channel": "stable",
  "architecture": "x64",
  "version": "1.4.2",
  "buildRevision": 37,
  "publishedAt": "2026-08-04T00:00:00Z",
  "expiresAt": "2026-08-11T00:00:00Z",
  "minimumUpgradableVersion": "1.1.0",
  "catalogSchemaReadMin": 8,
  "catalogSchemaReadMax": 10,
  "engineAbi": 12,
  "installerUri": "https://download.example/.../Negaflow-1.4.2-win-x64.exe",
  "installerSize": 123456789,
  "installerSha256": "...",
  "mandatoryAfter": null,
  "revokedVersions": [],
  "rollout": { "id": "stable-1.4.2", "percentage": 100 },
  "signature": "..."
}
```

예시는 schema shape이며 URL, version, size가 실제 release 값이라는 뜻은 아니다.

### 5.4 anti-rollback

client는 channel별 highest accepted release sequence/version을 app-owned protected state에 기록한다. 더 낮은
version metadata는 기본 거부한다.

긴급 rollback은 일반 `version < current`만으로 허용하지 않는다. 별도 signed authorization을 요구한다.

- from version/range
- exact target version/hash
- affected channel/architecture
- reason/advisory ID
- issue/expiry time
- minimum safe catalog schema
- authorized metadata key

local state 삭제만으로 무조건 옛 vulnerable release를 설치할 수 없게 installer와 feed 양쪽에서 검증한다.

## 6. update 확인 정책

### 6.1 확인 시점

- app launch를 network 응답으로 block하지 않음
- launch 뒤 idle/background에서 확인
- 사용자가 `Check for Updates`를 선택하면 즉시 확인
- last successful/attempted check와 backoff 기록
- offline은 정상 상태
- metered network 정책 존중
- enterprise policy가 있으면 public check 금지

### 6.2 표시

사용자에게 다음을 구분한다.

| 상태 | UI |
|---|---|
| checking | Settings/About의 조용한 progress |
| up to date | version과 last checked |
| optional update | release notes와 Download/Install |
| downloaded | Restart to Update 또는 Install when ready |
| mandatory security update | 이유, deadline, 가능한 작업 |
| feed failure | 현재 app 계속 사용, retry/diagnostics |
| invalid metadata | security 오류, 자동 실행 금지 |
| managed by organization | IT가 관리한다는 표시 |

일반 update를 매 launch modal로 방해하지 않는다. 현재 catalog가 손상됐거나 active export가 실패한 문제를
“업데이트하면 해결될 수 있음”으로 덮지 않는다.

### 6.3 staged rollout

rollout bucket은 stable installation identifier에서 privacy-safe deterministic하게 계산한다. hardware serial,
source path, account name을 server에 보내지 않는다.

- percentage는 signed metadata에 포함
- bucket algorithm version 고정
- security hotfix는 별도 정책
- rollout pause가 이미 다운로드한 artifact를 자동 삭제하지 않음
- revoked rollout은 install 직전 재확인

구체 비율과 기간은 release operations가 결정한다. 테스트하지 않은 “1% → 10% → 100%”를 고정 진리로
문서화하지 않는다.

## 7. 다운로드

### 7.1 full installer

v1은 exact full offline installer를 내려받는다.

장점:

- 모든 previous version에서 같은 upgrade path
- inner payload provenance 단순
- corrupted partial patch와 base-version 조합 제거
- rollback/reinstall/support가 쉬움
- x64/ARM64 분리 명확

delta update는 bandwidth가 실제 사용자 문제이고 signed patch/base verification, fallback full installer,
recovery matrix를 구현할 가치가 측정된 뒤 검토한다.

### 7.2 downloader 선택

BITS는 network cost를 고려하고 interruption/reboot 후 transfer를 이어갈 수 있는 Windows API다. 후보로 두되
무조건 도입하지 않는다.

두 구현 후보:

1. app-owned resumable HTTP download
2. per-user BITS job

선택 gate:

- proxy/enterprise compatibility
- metered network
- app exit/reboot resume
- credential/token ownership
- orphan job cleanup
- progress/cancel UX
- temp file ACL와 final handoff
- 추가 COM complexity

어떤 transport든 completion은 authenticity가 아니다. download 뒤 size/hash/signature를 별도로 검증한다.

### 7.3 staging root

```text
%LOCALAPPDATA%\Negaflow\Updates\Staging\<request-id>\
  installer.partial
  installer.ready
  metadata.signed
  state.json
```

규칙:

- current user만 쓰기 가능한 app-owned directory
- reparse point/symlink/hardlink defense
- random request ID와 exact path
- final filename을 URL path에서 그대로 신뢰하지 않음
- partial과 verified-ready 이름 분리
- file open handle과 path identity 재확인
- download completion 뒤 flush/close/hash
- verify 후 atomic rename
- install 직전 다시 open/hash/signature

temp 또는 Downloads의 공격자 교체 가능한 파일을 곧바로 elevated installer에 넘기지 않는다.

### 7.4 disk space

preflight에는 최소 다음을 포함한다.

- installer bytes
- download temporary overhead
- MSI rollback cache/old files
- new self-contained payload
- catalog verified backup
- log와 crash margin

정확한 요구량은 package manifest와 현재 install을 바탕으로 계산한다. 부족하면 active app을 종료하기 전에
알린다.

## 8. artifact verification

### 8.1 download 직후

- expected exact byte size
- SHA-256
- Authenticode signature presence
- signer subject/chain/EKU
- RFC 3161 timestamp
- revocation status 정책
- PE/MSI architecture
- embedded product/file version
- expected filename type
- no unexpected alternate data/redirected path

### 8.2 install 직전

app이 한 검증을 helper가 신뢰하지 않고 다시 수행한다. app verification과 elevation 사이 TOCTOU를 줄이기
위해 verified file handle/identity를 보존하거나 exact path·file ID·size·hash를 다시 확인한다.

### 8.3 install 후

- install root canonical path
- file allowlist
- app/engine/helper version coherence
- architecture
- all required PE signatures
- engine ABI
- assets/shader/license manifest hashes
- updater version

old Shell + new DLL 또는 new Shell + old engine 같은 mixed payload는 launch 전에 fail closed한다.

## 9. pre-update application checkpoint

### 9.1 active operation drain

update install 전에 다음 상태를 확인한다.

- import/decode jobs
- Develop render jobs
- export queue와 publish transaction
- print operation
- preview/full scanner scan과 plugin process
- catalog write transaction
- sidecar/backup operation

사용자에게 선택지를 준다.

- 작업 완료 후 업데이트
- 안전하게 취소 가능한 작업 취소 후 업데이트
- 업데이트 나중에

export publish 또는 scanner acquisition의 파괴적 중간 상태를 강제 종료하지 않는다.

### 9.2 catalog checkpoint

업데이트 직전:

1. 새로운 mutation 접수 중지
2. active transaction 완료/rollback
3. WAL checkpoint 정책 실행
4. integrity check의 정의된 최소 단계
5. catalog schema/version 기록
6. verified backup 생성
7. backup reopen/read 검증
8. backup hash와 journal record

catalog가 이미 corrupt이면 update로 이를 숨기지 않는다. update를 계속할지 여부와 별개로 recovery 상태를
명확히 표시한다. corrupt catalog를 empty catalog로 복사하지 않는다.

### 9.3 user files

source original과 third-party sidecar를 backup이라는 이름으로 rewrite하지 않는다. app-owned catalog,
app-owned sidecar/recipe, settings 중 migration 대상만 backup한다. export/scan staging은 각 transaction journal에
따라 완료·정리한다.

## 10. update journal

### 10.1 상태 머신

```text
idle
  → checking
  → available
  → downloading
  → verified
  → checkpointing
  → readyToInstall
  → installerRunning
  → installedPendingHealth
  → healthy
  → finalized
```

failure branches:

```text
downloadFailed
verificationFailed
checkpointFailed
installerFailedRolledBack
installerFailedIndeterminate
installedHealthFailed
dataMigrationFailed
rollbackPending
manualRecoveryRequired
```

### 10.2 journal 필드

- transaction ID
- from/to version과 architecture/channel
- feed issue/signature identity
- installer path/file ID/size/hash/signer
- install context
- old/new engine ABI
- old/new catalog schema range
- backup path/hash/schema
- phase와 monotonic sequence
- timestamps
- app/helper/installer process IDs
- MSI exit/result code
- health check result
- rollback authorization if any
- last durable error

### 10.3 durability

- app-owned directory
- temp write + flush + atomic replace
- one writer ownership
- monotonically increasing phase
- terminal 이후 뒤 상태로 임의 이동 금지
- corrupt journal은 idle로 간주하지 않음
- unknown schema는 manual recovery 또는 compatible reader

## 11. installer transaction

### 11.1 app shutdown handoff

app은 helper에 다음을 전달한다.

- random one-time transaction token
- journal path/ID
- exact verified installer identity
- expected from/to version
- app process handle/ID와 creation identity
- desired post-install launch

helper는 token과 journal이 맞지 않으면 종료한다. command line에 user-controlled arbitrary paths를 그대로
elevated하지 않는다.

### 11.2 running process

helper는 app 종료를 bounded wait한다. scanner plugin/helper child도 Job Object 또는 recorded process identity로
정리한다. 같은 이름의 unrelated process를 종료하지 않는다.

timeout 시:

- 사용자에게 남은 process와 작업 상태 안내
- 강제 종료는 명시적 선택 또는 installer policy
- catalog writer가 남아 있으면 install 시작 금지

### 11.3 MSI major upgrade

같은 `UpgradeCode`, 올바른 `ProductCode/PackageCode`, version과 install context로 previous product를 찾는다.
Windows Installer가 old/new component를 transaction으로 처리하게 한다.

주의:

- Windows Installer는 version 비교에서 첫 세 ProductVersion 필드를 사용
- per-user → per-machine 또는 반대 context를 같은 major upgrade로 넘기지 않음
- nonidentical MSI에 같은 PackageCode 금지
- rollback disabled property/action 금지
- custom action이 만든 external state는 별도 rollback 필요

`RemoveExistingProducts` scheduling 같은 WiX 세부는 실제 component rule과 rollback test로 확정한다. 문서 한
줄의 “권장 위치”를 모든 upgrade에 복사하지 않는다.

### 11.4 exit code

다음을 구분한다.

- success
- success, restart required
- user cancelled
- another install in progress
- detection/version conflict
- disk space
- signature/policy block
- rollback completed
- rollback disabled/failed/indeterminate

unknown code를 success로 취급하지 않는다. 원문 MSI/bootstrapper log를 privacy-safe diagnostics에 연결한다.

## 12. 새 app health check

### 12.1 startup gate

새 version 첫 실행은 일반 startup 전에 다음을 검사한다.

- install manifest version 일치
- app/native engine/helper ABI 일치
- required DLL/assets/shaders 존재와 hash
- architecture 일치
- settings schema parse
- catalog header/schema read compatibility
- update journal phase
- pending migration/recovery ownership

catalog를 열기 전 binary coherence를 검사한다.

### 12.2 health success 정의

단순 process start가 아니다. 최소:

- app window/shell initialization
- native engine creation
- catalog read-only preflight
- migration이 필요하면 transaction 완료
- Library 기본 query
- required resource load
- no fatal startup exception/device-independent fallback failure
- journal finalization 가능

GPU hardware별 render 전체를 first-launch blocking gate로 만들지는 않는다. GPU failure는 WARP/fallback 정책과
별도 진단한다. 그러나 engine ABI mismatch를 무시하고 UI만 떴다고 healthy 처리하지 않는다.

### 12.3 health timeout

정확한 시간은 startup profiling 후 결정한다. 느린 catalog, driver initialization, first-run shader/cache를 고려해
하드코딩한 짧은 timeout으로 정상 설치를 rollback하지 않는다. health app과 helper가 phase heartbeat와 fatal
result를 명시적으로 교환한다.

## 13. catalog migration

### 13.1 migration은 app transaction

installer custom action에서 catalog를 migrate하지 않는다. 사용자 profile, session, file access, app domain
invariant를 아는 새 app이 수행한다.

순서:

1. catalog exclusive lock
2. source schema 확인
3. verified pre-update backup 확인
4. migration plan과 expected target schema
5. database transaction
6. schema/data invariant checks
7. commit
8. reopen/read validation
9. migration journal finalize

### 13.2 failure

commit 전 실패:

- DB transaction rollback
- old catalog 유지
- update journal에 migration failure
- old binary가 new install에 의해 교체되었는지 별도 판단

commit 후 validation 실패:

- 성공으로 보고하지 않음
- backup 자동 복원은 현재 catalog에 새 user mutation이 없다는 ownership proof가 있을 때만
- 그렇지 않으면 두 copy를 보존하고 recovery UI

### 13.3 forward-only schema

새 schema가 old app에서 읽히지 않으면 binary downgrade가 곧 data rollback은 아니다.

정책 후보:

- migration 전 old-compatible shadow backup 보존
- new schema를 읽을 수 없는 old app launch 차단
- emergency rollback은 backup restore와 함께 한 transaction으로 제공
- update 후 user edits가 생기면 old backup restore가 그 edits를 잃을 수 있으므로 자동 수행 금지

schema migration은 reversible이라고 검증된 경우에만 reverse migration을 제공한다.

## 14. rollback 종류

### 14.1 installer failure rollback

MSI transaction 중 failure가 나면 Windows Installer의 기본 rollback을 사용한다.

검증:

- old app files 복원
- registration/file associations 복원
- install root에 mixed version 없음
- app launch 가능
- user data untouched
- updater journal terminal result

### 14.2 pre-health automatic rollback

새 binary 설치 후 catalog migration 전에 fatal binary coherence/startup failure가 나면 old signed full installer로
rollback할 수 있다.

조건:

- old exact installer/hash/signer가 보존됨
- catalog schema가 아직 old-compatible
- 새 app mutation이 없음
- authorized rollback metadata
- user/enterprise policy 허용

조건이 하나라도 불명확하면 자동 downgrade 대신 recovery UI와 manual installer를 제공한다.

### 14.3 post-migration rollback

가장 위험하다. old binary와 old catalog backup을 함께 되돌려야 할 수 있다.

자동 허용 조건:

- migration 직후 health failure
- post-migration user mutation 0
- source/export/plugin external state 변화 없음
- backup integrity/identity 검증
- old installer 검증
- journal이 단일 transaction ownership을 증명

그 외에는:

- 현재 data와 backup 둘 다 보존
- new app recovery/export route
- support bundle
- explicit user choice

사진 edit를 잃는 silent rollback은 금지한다.

### 14.4 user-requested downgrade

Settings에 arbitrary “이전 버전 설치” 목록을 기본 제공하지 않는다. support가 승인한 compatible release와
signed rollback metadata에 한정한다.

### 14.5 security rollback/revocation

문제 release를 낮은 안전 version으로 내릴 때도 anti-rollback authorization과 schema gate를 거친다. 취약한
old version으로 가는 rollback은 허용하지 않는다.

## 15. old installer와 backup retention

### 15.1 보존 대상

- 현재 설치 version의 exact signed installer 또는 verified recovery package
- 최신 verified pre-update catalog backup
- update journal/log
- release manifest와 signer/hash

### 15.2 정리

새 version이 healthy terminal에 도달한 즉시 모든 recovery artifact를 삭제하지 않는다. retention은 disk budget,
security revocation, schema compatibility를 고려한다.

삭제 전:

- active/pending transaction 없음
- current version health 확인
- 최소 recovery point 유지
- file ownership과 path identity 확인
- user data 아님을 확인

cleanup failure는 app 기능 실패로 만들지 않되 diagnostics에 남긴다.

## 16. crash와 power-loss recovery

startup에서 journal을 읽고 phase별로 복구한다.

| durable phase | 해석 | 조치 |
|---|---|---|
| downloading | partial artifact | resume 또는 안전 삭제 |
| verified | install 전 | 재검증 후 사용자에게 재개 |
| checkpointing | backup 불확실 | backup 검증, install 금지 |
| readyToInstall | app 종료 전/후 | process와 artifact 확인 |
| installerRunning | outcome 불명 | installed product inventory와 MSI log 확인 |
| installedPendingHealth | 새 binary 있음 | exact version health launch |
| dataMigrationFailed | data 상태 주의 | old/new schema와 backup 비교 |
| rollbackPending | 복구 중단 | installer/catalog ownership 재검증 |
| finalized | 완료 | retention cleanup만 |

unknown/corrupt journal을 `idle`로 바꾸고 진행하지 않는다. install root, product inventory, catalog schema,
backup hash를 read-only로 조사해 manual recovery 상태를 만든다.

## 17. mixed-version 방지

각 process startup에서 다음을 교차 검증한다.

- Shell version
- native engine file/product version
- C ABI version
- engine build manifest ID
- shader/kernel manifest version
- helper/updater protocol version
- scanner protocol range

불일치 시:

- catalog write 금지
- original/export write 금지
- repair installer 안내
- support bundle 가능
- “일부 기능만 계속”으로 위험한 mixed state를 숨기지 않음

scanner plugin version은 core payload와 독립이므로 exact product version 일치를 요구하지 않고 protocol range와
approval identity를 검사한다.

## 18. plugin update와 core update 분리

### 18.1 독립 transaction

core updater는 plugin을 업데이트하지 않는다. plugin manager도 core install directory를 쓰지 않는다.

```text
core update journal
plugin update journal per plugin ID
```

### 18.2 compatibility preflight

core update 전에 installed plugin manifest를 읽고 target core의 protocol range와 비교할 수 있다.

- compatible: 그대로 유지
- incompatible but update available: 사용자에게 별도 plugin update 안내
- incompatible/no update: plugin 비활성화 예정 안내
- unknown/corrupt: launch 금지, core update는 계속 가능

scanner가 없더라도 core photo workflow update를 막지 않는다.

### 18.3 plugin rollback

plugin rollback은 [plugin security and lifecycle](../10-scanner/plugin-security-and-lifecycle.md)의 approval/hash와
device validation을 따른다. old plugin으로 되돌렸다고 old driver/hardware behavior가 복구된다고 가정하지 않는다.

## 19. enterprise policy

관리 가능한 policy:

- update owner: organization
- public feed check enable/disable
- organization mirror feed
- update deferral window
- mandatory deadline
- user install UI enable/disable
- allowed channel
- allowed signer/publisher
- plugin install/update policy
- reboot behavior

policy source와 precedence를 문서화한다. registry key가 존재한다는 이유만으로 신뢰하지 않고 machine policy의
ACL과 type/value를 검증한다.

managed mode에서는 app이 public installer를 자동 실행하지 않는다. IT가 newer version을 배포했을 때 journal과
health check는 그대로 적용할 수 있다.

## 20. Microsoft Store MSI/EXE update

Store에 MSI/EXE listing을 올려도 기존 사용자 update는 Store가 전달하지 않는다. app/installer 자체 updater가
계속 책임진다.

필수 정책:

- Store install marker
- Store policy가 in-app update를 허용하는지 release 시 확인
- submitted versioned URL과 public direct URL identity
- Store certification 전 새 update를 Store user에게 노출할지 결정
- duplicate Direct/Store install 방지
- channel migration

Store page를 업데이트한 사실을 installed clients rollout 완료로 세지 않는다.

## 21. MSIX/App Installer 경로

full MSIX channel을 나중에 채택하면 Windows App Installer의 update settings를 사용할 수 있다.

- `OnLaunch`
- `HoursBetweenUpdateChecks`
- `ShowPrompt`
- `UpdateBlocksActivation`
- `AutomaticBackgroundTask`
- `ForceUpdateFromAnyVersion`

`ForceUpdateFromAnyVersion=true`는 lower version downgrade도 허용한다. 이를 항상 켜두지 않는다. emergency
rollback 요구와 schema compatibility를 함께 검토한다.

`UpdateBlocksActivation`은 critical update에서 쓸 수 있지만 user가 자기 사진을 offline으로 export할 복구
기회를 박탈할 수 있다. security threat와 data-access 필요를 구분한 product policy가 필요하다.

MSIX가 block-level differential download를 제공해도 package rollback과 catalog rollback은 여전히 별개다.

## 22. update UX

### 22.1 optional update

- version과 주요 변경
- download size
- restart 필요
- release notes
- `Download`, `Later`
- active work가 있으면 자동 install하지 않음

### 22.2 ready to install

- 저장되지 않은 edit 상태
- active export/scan 수
- 예상 app 종료
- `Install and Restart`, `Later`

“Restart”는 OS reboot가 아니라 app restart인지 명확히 쓴다. 실제 OS reboot가 필요하면 별도로 표시한다.

### 22.3 failure

- 현재 version이 계속 사용 가능한지
- installer rollback 성공 여부
- catalog/data가 변경됐는지
- `Retry`, `Open Current Version`, `Repair`, `Export Diagnostics`

rollback을 확인하지 않았으면 “이전 버전으로 복원되었습니다”라고 말하지 않는다.

### 22.4 mandatory update

다음을 설명한다.

- 왜 필수인지
- deadline
- 지금 가능한 작업
- offline/recovery access
- enterprise contact

일반 feature update를 mandatory로 남용하지 않는다.

## 23. telemetry 없는 rollout 안전성

사용자가 analytics를 거부해도 update가 안전해야 한다.

- signed feed와 staged percentage
- support reports
- opt-in crash diagnostics
- canary hardware lab
- Store/installer failure metrics가 제공되는 범위
- manual pause/revoke

원본 path/image/recipe를 수집하지 않고도 version, architecture, installer exit category 같은 최소 집계는 별도
consent/policy 아래 설계할 수 있다. 수집하지 않았다면 success rate를 추측해 보고하지 않는다.

## 24. logging

### 24.1 기록

- transaction/version/channel/architecture
- feed fetch result와 signature key ID
- download bytes/duration/retry category
- artifact verification result
- signer subject/serial 일부와 hash
- checkpoint/backup result
- MSI/bootstrapper exit code
- installed payload verification
- health/migration/rollback phase

### 24.2 제외

- source/export absolute path
- image pixels/thumbnails
- scanner serial 원문
- account name
- certificate private material
- feed authentication credential

support bundle은 path를 salted identifier로 바꾸고 artifact/log 포함을 사용자에게 보여준다.

## 25. 실패 주입 테스트

### 25.1 feed

- TLS failure
- redirect to untrusted host
- oversized JSON
- malformed/unknown schema
- invalid/expired signature
- stale metadata
- stable/beta mismatch
- x64/ARM64 mismatch
- unauthorized downgrade
- revoked target

### 25.2 download

- disconnect/resume
- proxy auth
- metered network pause
- partial content mismatch
- wrong size/hash
- valid signature but unapproved hash
- approved hash but wrong signer
- disk full
- staging reparse attack
- file replacement between verification and elevation

### 25.3 checkpoint

- active scan/export
- catalog busy
- WAL checkpoint failure
- corrupt catalog
- backup disk full
- backup read-back failure
- crash after backup before journal phase

### 25.4 installer

- app refuses to close
- other session process
- another MSI running
- UAC denied
- file locked
- power loss
- custom action failure
- rollback success
- rollback failure/indeterminate
- reboot required
- wrong install context

### 25.5 first launch

- missing native DLL
- wrong engine ABI
- corrupt shader/asset
- settings migration failure
- catalog migration before/after commit failure
- GPU unavailable/WARP path
- crash before health acknowledgement
- health helper crash

### 25.6 rollback

- old installer missing
- old installer hash mismatch
- catalog backup corrupt
- post-migration edits exist
- rollback authorization expired
- target old app cannot read schema
- old version revoked for security

## 26. clean-machine matrix

각 public candidate에서 최소:

| OS/arch | install source | from version | network | expected |
|---|---|---|---|---|
| Win11 x64 | Direct | clean | online | install/launch |
| Win11 x64 | Direct | previous stable | online | upgrade/health |
| Win11 x64 | MSI | previous stable | offline | upgrade/rollback test |
| Win11 ARM64 | Direct | clean | online | native install/launch |
| Win11 ARM64 | Direct | previous stable | online | native upgrade/health |
| Win11 ARM64 | MSI | previous stable | offline | upgrade/rollback test |
| managed x64 | enterprise | previous | blocked public feed | IT update only |
| managed ARM64 | enterprise | previous | blocked public feed | IT update only |

추가로 full catalog fixture, large library, installed plugin compatible/incompatible cases를 반복한다.

## 27. 성능과 사용자 영향 측정

- feed check latency와 timeout
- download throughput/resume overhead
- hash/signature verification 시간
- checkpoint/backup 시간과 size
- app shutdown latency
- installer duration p50/p95
- first healthy launch 시간
- disk peak usage
- rollback duration
- retained recovery bytes

update가 느리다는 이유로 signature, backup read-back, catalog invariant를 생략하지 않는다. 병목이 확인되면
다운로드/backup scheduling 또는 compression을 최적화한다.

## 28. release operations runbook

### 정상 release

1. exact signed candidate QA
2. immutable artifact upload
3. CDN read-back hash/signature
4. signed metadata 생성
5. internal/canary feed publish
6. update/rollback 실기
7. staged rollout
8. support/known issue 관찰
9. stable 확대
10. health 기준 뒤 recovery artifact retention cleanup

### rollout pause

1. feed percentage/pointer를 signed update로 중지
2. target artifact 신규 제공 중단
3. installed users 영향 범위 파악
4. current app 사용 가능성 안내
5. fix 또는 authorized rollback 결정

### emergency revoke

1. exact version/hash revoke metadata
2. signer/feed compromise 여부 판단
3. safe fixed release
4. schema-compatible update/rollback plan
5. public advisory
6. enterprise notification
7. forensic artifact 보존

## 29. 금지

- running app이 자기 install directory를 직접 덮어쓰기
- hash만 확인하고 signature를 생략하거나 그 반대
- HTTPS이므로 metadata signature 생략
- app verification 결과만 믿고 elevated helper가 재검증하지 않음
- corrupted update journal을 idle로 취급
- installer rollback 성공을 catalog rollback 성공으로 표시
- schema-incompatible old app 자동 실행
- post-update user edit를 silent backup restore로 잃음
- plugin과 core를 한 transaction으로 강제 묶음
- delta update를 fallback full package 없이 출시
- rollout 문제 version URL의 bytes 교체
- Store MSI/EXE가 existing clients를 자동 update한다고 가정
- `ForceUpdateFromAnyVersion`을 의미 없이 항상 활성화

## 30. 완료 기준

- signed feed가 channel/architecture/anti-rollback을 검증함
- exact full installer가 protected staging에서 이중 검증됨
- active scan/export/catalog mutation을 안전하게 drain함
- verified catalog backup 없이는 migration update를 시작하지 않음
- MSI rollback enabled와 failure injection이 검증됨
- new app이 binary/ABI/schema health를 명시적으로 확인함
- binary rollback과 data rollback을 UI/log에서 구분함
- power loss/crash의 모든 durable phase가 recovery path를 가짐
- x64와 ARM64 clean/upgrade/rollback matrix가 각각 통과함
- enterprise/Store/MSIX update owner가 혼동되지 않음
- core와 plugin update journal/ownership이 분리됨

이 기준 전에는 “자동 업데이트 지원”이라고 표현하지 않는다. update check, installer download, 한 번의 성공
upgrade는 rollback과 data safety를 증명하지 않는다.
