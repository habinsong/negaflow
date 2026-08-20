# Windows 배포 채널 설계

기준일: 2026-08-04  
상태: v1 primary channel 결정, Store/enterprise는 검증 gate 정의  
관련 문서:

- [서명과 installer 신뢰](msix-signing.md)
- [업데이트와 롤백](update-and-rollback.md)
- [scanner plugin architecture](../10-scanner/plugin-architecture.md)
- [scanner plugin security](../10-scanner/plugin-security-and-lifecycle.md)
- [Windows architecture](../00-overview/architecture.md)

## 1. 결론

Negaflow Windows v1의 primary channel은 **공식 웹사이트에서 제공하는 서명된 architecture별 offline
installer**다.

```text
Primary
  Direct Stable
    ├── x64 signed self-contained installer
    └── ARM64 signed self-contained installer

Optional
  Direct Beta
  Enterprise Offline
  Microsoft Store MSI/EXE listing

Future gate
  Microsoft Store MSIX
  packaged-with-external-location identity package
```

채널별 핵심 정책:

| 채널 | v1 상태 | package model | update owner | scanner plugin |
|---|---|---|---|---|
| Direct Stable | 기본 | unpackaged self-contained MSI/Burn | Negaflow updater | 허용, 별도 설치·승인 |
| Direct Beta | opt-in | Stable과 동일 모델 | Negaflow updater | 허용, 호환성 별도 표시 |
| Enterprise Offline | 지원 후보 | signed offline MSI | 조직 IT | 정책으로 허용/차단 |
| Store MSI/EXE | 후속 | unpackaged installer listing | Negaflow updater | Store 정책·실기 통과 전 비활성 |
| Store MSIX | 미래 | full packaged | Microsoft Store | 외부 plugin 전체 gate 전 비활성 |
| Sparse identity | 필요 시 spike | external-location identity + MSI | Negaflow updater | 실제 process/path 검증 필요 |

Direct Stable을 고른 이유는 macOS 배포 형태를 모방하기 위해서가 아니다. 스캐너 adapter, x86 child
process, 대형 사용자 파일, catalog/cache, 문제 해결 도구, architecture별 native engine을 가장 투명하게
검증하고 서비스할 수 있기 때문이다.

## 2. 공식 근거

- [Package and deploy Windows apps](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/)
- [Choose a distribution path](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/choose-distribution-path)
- [Distribute an unpackaged WinUI 3 app](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/unpackage-winui-app)
- [Self-contained Windows App SDK deployment](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/self-contained-deploy/deploy-self-contained-apps)
- [Microsoft Store MSI/EXE requirements](https://learn.microsoft.com/en-us/windows/apps/publish/publish-your-app/msi/app-package-requirements)
- [Upload MSI/EXE packages](https://learn.microsoft.com/en-us/windows/apps/publish/publish-your-app/msi/upload-app-packages)
- [Publish MSI/EXE updates](https://learn.microsoft.com/en-us/windows/apps/publish/publish-your-app/msi/publish-update-to-your-app-on-store)
- [Get started with Microsoft Store](https://learn.microsoft.com/en-us/windows/apps/publish/get-started)
- [Grant package identity with external location](https://learn.microsoft.com/en-us/windows/apps/desktop/modernize/grant-identity-to-nonpackaged-apps)
- [App Installer file](https://learn.microsoft.com/en-us/windows/msix/app-installer/how-to-create-appinstaller-file)

Store 정책, certification, signing service availability는 release 시점에 다시 확인한다.

## 3. 채널과 build flavor를 혼동하지 않는다

### 3.1 channel

channel은 사용자가 update를 받는 정책과 distribution owner를 뜻한다.

- `stable`
- `beta`
- `enterprise`
- `store`
- `development`

### 3.2 architecture

architecture는 별도 axis다.

- `win-x64`
- `win-arm64`
- `win-x86`: 본체 없음, 일부 scanner plugin에만 허용

### 3.3 configuration

- `Release`: public/enterprise distribution
- `Debug`: developer only
- `Sanitized/Instrumented`: QA only, public feed 금지

`beta`라고 Debug binary를 배포하지 않는다. Stable과 Beta는 같은 hardened Release configuration이며 feed와
feature policy만 다르다. QA build가 production signing identity를 얻지 못하게 한다.

## 4. artifact naming과 immutable URL

### 4.1 filename

권장 형식:

```text
Negaflow-1.4.2-win-x64.exe
Negaflow-1.4.2-win-x64.msi
Negaflow-1.4.2-win-arm64.exe
Negaflow-1.4.2-win-arm64.msi
Negaflow-1.4.2-release-manifest.json
Negaflow-1.4.2-SBOM.spdx.json
Negaflow-1.4.2-licenses.zip
```

public filename에 `latest.exe`만 제공하지 않는다. 편의 redirect는 둘 수 있지만 redirect target은 versioned
immutable URL이어야 한다.

### 4.2 URL

```text
https://download.negaflow.example/windows/stable/1.4.2/Negaflow-1.4.2-win-x64.exe
https://download.negaflow.example/windows/stable/1.4.2/Negaflow-1.4.2-win-arm64.exe
```

한 번 공개한 versioned URL의 bytes를 교체하지 않는다. signing 실수나 packaging 문제를 발견하면 새 version
또는 build revision을 발행한다.

Store MSI/EXE 제출도 Microsoft 공식 요구대로 versioned HTTPS URL을 사용하고 제출 후 해당 URL의 binary를
바꾸지 않는다.

## 5. Direct Stable

### 5.1 목적

- scanner-inclusive 제품의 기준 channel
- 즉시 hotfix와 rollback 통제
- x64/ARM64 native payload
- 독립 plugin ecosystem
- 명시적 release notes와 known issues

### 5.2 설치물

두 형태를 제공할 수 있다.

| 형태 | 사용자 | 설명 |
|---|---|---|
| `.exe` bootstrapper | 일반 사용자 | prerequisite/architecture/install UX 조정 |
| `.msi` offline | 관리자/enterprise | 표준 배포와 repair, 명시적 silent options |

두 파일이 서로 다른 app build를 담지 않는다. 같은 signed payload와 product version을 사용하고 최종 hash를
각각 기록한다.

bootstrapper가 인터넷에서 본체를 내려받는 작은 web stub가 되지 않게 한다. primary public installer는
offline-complete다. 이는 Store MSI/EXE 경로의 standalone installer 요구와 clean-room 검증에도 유리하다.

### 5.3 architecture 선택

download page는 OS architecture를 힌트로 제안할 수 있지만 사용자 agent만 신뢰하지 않는다.

- x64 Windows → x64 installer
- ARM64 Windows → native ARM64 installer
- ARM64에서 x64 fallback을 공식 기본으로 권하지 않음
- 잘못된 architecture 실행 시 설치 전 설명 가능한 오류
- scanner x86 adapter는 별도 plugin component이며 app installer 선택과 무관

하나의 multi-architecture bootstrapper를 도입하려면 그 bootstrapper 자체의 native 실행, payload 선택,
signature, offline behavior를 둘 다 검증해야 한다. 초기에는 단순한 별도 installer가 기준이다.

### 5.4 update

Direct Stable은 Negaflow가 서명한 update metadata와 signed installer를 사용한다. app binary가 실행 중인
자기 자신을 덮어쓰지 않는다. 자세한 transaction은 [업데이트와 롤백](update-and-rollback.md)을 따른다.

### 5.5 scanner plugin

Direct Stable은 external plugin을 허용하는 기준 channel이다.

- 본체 installer에 SANE/GPL plugin을 자동 포함하지 않음
- WIA/TWAIN adapter도 ownership에 따라 core 또는 별도 signed component로 분리
- plugin installer와 update feed 독립
- first use 전 hash/signature/user approval
- plugin 없이 import/develop/export 완전 동작
- plugin failure가 app update를 block하지 않음

## 6. Direct Beta

### 6.1 목적

- production-like installer/update 검증
- 새 GPU/codec/scanner route의 제한 rollout
- catalog migration과 rollback rehearsal
- x64/ARM64 hardware coverage 확대

Beta는 support 책임이 없는 nightly가 아니다. signed Release build, changelog, known issue, expiration 없는
정상 product data를 사용한다.

### 6.2 Stable과의 관계

권장 정책은 **동일 설치의 channel switch**이지 Stable/Beta의 무제한 side-by-side가 아니다.

이유:

- 같은 catalog와 source originals를 두 app이 동시에 열 위험
- file association와 shell registration 충돌
- plugin approval/update state 혼선
- cache schema와 engine version 충돌

channel switch 전:

1. active export/scan job이 없는지 확인
2. catalog checkpoint와 verified backup
3. target channel이 현재 schema를 열 수 있는지 확인
4. updater metadata signer와 channel authorization 확인
5. app 종료 뒤 installer 실행

Stable → Beta는 명시적 opt-in이다. Beta → Stable은 단순 downgrade가 아니며 stable version과 catalog schema가
호환될 때만 허용한다.

### 6.3 beta telemetry와 privacy

Beta 참여가 원본 이미지, 경로, scanner serial, catalog 내용을 자동 전송하는 동의가 아니다. 진단 수집은
별도 opt-in과 redact 규칙을 따른다. crash dump도 명시적 사용자 동의 없이 필름 pixel을 포함할 수 있는
memory region을 업로드하지 않는다.

## 7. Development와 nightly

### 7.1 public channel이 아니다

- production website 기본 download에 노출하지 않음
- production updater가 발견하지 않음
- production signing identity 사용 금지 또는 별도 제한 profile
- production catalog를 자동으로 열지 않음
- UI에 명확한 non-production 표시

### 7.2 격리

```text
%LOCALAPPDATA%\Negaflow-Development\
%LOCALAPPDATA%\Negaflow-Beta\  # side-by-side를 허용하는 내부 QA일 때만
```

개발 build는 production data root를 사용하지 않는다. production catalog 복사본으로 migration test를 할 수는
있지만 원본 경로와 write 권한을 제한한 fixture 환경에서 수행한다.

## 8. Enterprise Offline

### 8.1 목표

- 인터넷 차단 환경
- Intune/Configuration Manager/소프트웨어 배포 도구
- 조직이 update 시점을 통제
- managed certificate/policy와 plugin allowlist

### 8.2 package

enterprise에는 signed offline MSI를 기준으로 제공한다.

- 모든 prerequisite 포함 또는 명시적 offline prerequisite bundle
- deterministic silent install/uninstall/repair command
- machine-readable exit codes
- restart 요구를 정확히 보고
- per-user/per-machine context 문서화
- x64/ARM64 별도 detection rule
- version, UpgradeCode/ProductCode inventory

web bootstrapper처럼 install 시 payload를 새로 내려받지 않는다.

### 8.3 update ownership

enterprise policy가 app self-update를 disable할 수 있어야 한다.

```text
updatePolicy = managed
checkUI = hidden or organization-controlled
feed = organization mirror or none
installerOwner = IT
```

app이 조직 정책을 우회해 public feed에서 설치하지 않는다. 그러나 security-critical version이 오래된 경우
UI에 비파괴적인 경고와 support 정보는 표시할 수 있다.

### 8.4 plugin policy

조직은 다음을 정책으로 제어할 수 있다.

- user-scope plugin 설치 허용 여부
- machine-scope allowlisted publisher/plugin ID
- WIA/TWAIN adapter만 허용
- unsigned/self-signed plugin 차단
- plugin update owner
- diagnostics와 dump export 범위

machine policy가 있더라도 host는 protocol/artifact validation을 생략하지 않는다.

## 9. Microsoft Store MSI/EXE

### 9.1 무엇을 제공하는가

Store는 기존 unpackaged MSI/EXE app의 listing과 install 진입점을 제공할 수 있다. official requirements:

- HTTPS versioned installer URL
- standalone `.msi` 또는 `.exe`
- downloader stub 금지
- silent install 지원
- installer와 포함된 모든 PE에 trusted CA signature
- architecture별 package 제출
- 제출 후 URL의 bytes 불변

### 9.2 중요한 update 제한

Store의 MSI/EXE submission update는 새 고객에게 최신 installer를 제시하지만, 기존 사용자에게 Store가 자동
또는 수동 update를 배포하는 방식이 아니다. 기존 사용자는 app/installer 자체 updater가 책임진다.

따라서 Store listing을 추가해도 다음을 유지해야 한다.

- Negaflow signed update metadata
- installer transaction과 rollback
- Store-installed marker와 policy
- in-app update가 Store 정책에 허용되는지 release마다 확인

“Store에서 설치했으니 Store가 업데이트한다”는 UI를 만들지 않는다.

### 9.3 scanner gate

초기 Store MSI/EXE channel은 scanner plugin이 다음을 통과하기 전 scanner 기능을 기본 제공한다고 약속하지
않는다.

- Store certification/policy
- external executable install/launch
- plugin별 별도 download disclosure
- x86 adapter
- vendor driver 요구
- updater ownership
- uninstall과 orphan plugin 처리

필요하면 Store build는 import/develop/export만 제공하고 scanner section에 direct edition과의 차이를 정확히
설명한다. 기능 차이를 숨기거나 같은 SKU인 것처럼 광고하지 않는다.

### 9.4 동일 설치 감지

Direct와 Store MSI/EXE가 같은 machine에 중복 설치되지 않게 product family detection을 둔다.

- 동일 app root/catalog를 두 설치가 공유하지 않음
- 한 channel에서 다른 channel로 이동하는 공식 migration 제공
- uninstall 후 user data 보존
- file association ownership transfer
- update feed ownership transfer

## 10. Microsoft Store MSIX

### 10.1 장점

- Store hosting와 certification
- Store가 MSIX를 재서명
- Store-managed update
- architecture bundle 선택
- clean package install/uninstall
- package identity 기반 Windows 기능

### 10.2 v1 blocker/gate

다음이 모두 실제 packaged build에서 통과하기 전 미래 channel이다.

- catalog SQLite/WAL과 backup/recovery
- thumbnail/tile cache
- user-selected arbitrary sources/exports
- external scanner plugin process
- user-scope executable plugin location
- x86 TWAIN adapter
- Job Object/handle inheritance
- plugin signature/approval/update
- support bundle/crash dump
- app data migration와 uninstall 보존
- Store policy와 certification

MSIX container의 파일/registry virtualization이 있다고 해서 catalog가 안전해지거나 깨진다고 추측하지 않는다.
실제 path와 journal behavior를 기록한다.

### 10.3 scanner 없는 Store edition

Store MSIX를 먼저 내야 한다면 scanner 없는 edition이 현실적 후보다.

- import/develop/export는 완전한 제품으로 유지
- scanner button을 fake device로 채우지 않음
- direct edition에만 scanner plugin이 있다는 차이를 listing/UI에 명시
- catalog format은 가능하면 동일
- source original과 sidecar 불변식 유지
- direct edition migration tool을 제공하기 전 수동 data copy를 안내하지 않음

## 11. packaged with external location

### 11.1 선택 조건

unpackaged app이 실제로 필요한 Windows feature를 사용할 수 없을 때만 선택한다.

예:

- 특정 notification/background task
- manifest 기반 extension
- package identity를 검사하는 API

단순히 “현대적인 설치처럼 보이기 위해” 추가하지 않는다.

### 11.2 구조

```text
existing signed MSI-installed binaries
    +
small identity package registered with ExternalLocation
    =
packaged-with-external-location app
```

installer와 update는 계속 Negaflow가 소유한다. full MSIX의 clean update model을 자동으로 얻는 것이 아니다.

### 11.3 gate

- external location이 실제 install root와 정확히 일치
- identity registration failure 시 app fallback 또는 명시적 fail
- binary update와 identity version 원자성
- repair/uninstall registration cleanup
- per-user/per-machine context
- x64/ARM64 identity package
- scanner plugin child launch
- no-identity recovery mode

## 12. channel identity metadata

app의 About/Diagnostics에는 다음을 표시한다.

- product version
- build revision/commit-derived build ID
- channel
- architecture
- package model: unpackaged / external-location / MSIX
- install context: per-user / per-machine
- update owner: Negaflow / Store / organization
- signer publisher
- Windows App SDK/.NET deployment mode
- engine ABI와 catalog schema

이 정보는 support bundle에도 들어간다. 사용자가 “어디서 설치했는지” 기억하는 데 의존하지 않는다.

## 13. release metadata와 feed 분리

### 13.1 feed URL

channel과 architecture를 분리한다.

```text
/windows/stable/x64/feed-v1.json
/windows/stable/arm64/feed-v1.json
/windows/beta/x64/feed-v1.json
/windows/beta/arm64/feed-v1.json
```

app은 자기 channel/architecture feed만 읽는다. server redirect로 다른 architecture나 beta를 섞지 않는다.

### 13.2 metadata 최소 필드

```text
schemaVersion
channel
architecture
version
minimumUpgradableVersion
catalogSchemaReadRange
engineAbi
installerUri
installerSize
installerSha256
installerSignerPolicy
releaseNotesUri
publishedAt
mandatoryAfter
revokedVersions
```

metadata는 signed envelope 또는 detached signature로 인증한다. TLS는 필요하지만 단독 authenticity root로
삼지 않는다.

### 13.3 feed failure

- timeout은 app launch failure가 아님
- invalid signature는 “업데이트 없음”이 아니라 security failure로 진단
- stale cached feed에는 expiry/issued-at 정책
- clock skew를 고려하되 무기한 유효하게 만들지 않음
- parsing failure에서 installer URL을 추측하지 않음
- stable app이 beta feed로 fallback하지 않음

## 14. build once, promote by identity

### 14.1 원칙

release candidate가 모든 gate를 통과하면 동일한 signed bytes를 Stable로 promote한다. Stable용으로 다시
compile하면 검증한 artifact와 배포한 artifact가 달라진다.

```text
source commit
  → deterministic release build
  → signed candidate
  → QA by exact SHA-256
  → metadata promotion
  → immutable stable URL
```

채널 문자열이 binary에 compile-time으로 박혀 재빌드가 필요하지 않게 한다. install/update metadata 또는
signed configuration에서 channel을 결정하되 tampering으로 beta/stable 경계가 무너지지 않게 한다.

### 14.2 예외

Store가 재서명하는 MSIX는 direct artifact와 byte-identical일 수 없다. 이 경우 다음 chain을 기록한다.

- 같은 source/build provenance
- Store 제출 전 package hash
- Partner Center submission ID
- Store-delivered package identity/version
- Store signature/publisher

“동일 bytes” 대신 “동일 source payload와 검증 가능한 재서명 chain”을 사용한다.

## 15. scanner plugin 배포 채널

### 15.1 core와 별도다

plugin index가 있더라도 plugin은 core release artifact가 아니다.

```text
Core feed
  Negaflow app releases

Plugin feed(s)
  WIA adapter
  TWAIN adapter
  SANE plugin
  vendor-specific adapter
```

plugin마다 publisher, repository, license, architecture, protocol range, device validation status가 다를 수 있다.

### 15.2 plugin metadata

- plugin ID와 display name
- plugin version
- protocol min/max
- architecture
- publisher subject
- installer/artifact SHA-256
- supported OS
- device/driver validation matrix link
- license/notice/source link
- update/revocation status
- core compatibility range

model list만으로 “지원 장치”를 주장하지 않는다. 실제 evidence level을 함께 표시한다.

### 15.3 install UX

- scanner surface에서 사용자가 명시적으로 plugin 설치를 선택
- official publisher/domain/hash 표시
- browser/installer handoff 전 설명
- install 뒤 재탐색
- first run approval
- core app이 admin credential을 받아 vendor driver를 silent install하지 않음

### 15.4 core update와 plugin

core updater는 plugin directory를 덮어쓰거나 삭제하지 않는다. protocol 호환성이 깨지면:

- plugin을 비활성화
- 이유와 compatible version 제시
- import/develop/export는 계속 동작
- 자동으로 다른 plugin/backend를 가장하지 않음

## 16. locale와 region

한 architecture installer 안에 supported localization resources를 포함하는 방식을 우선한다. locale별로
서로 다른 executable을 만들면 release/signing/test matrix가 불필요하게 늘어난다.

다만 다음은 region별 차이가 있을 수 있다.

- Store listing와 commerce
- privacy/legal text
- code signing service availability
- download CDN/retention
- export/cryptography 규정
- scanner driver availability

region 차이를 binary feature flag로 숨기지 않고 channel metadata와 release policy에서 명시한다.

## 17. 사용자 데이터와 channel 이동

### 17.1 공통 invariant

- 원본은 installer/update/uninstall이 수정하지 않음
- catalog는 missing/corrupt를 empty로 취급하지 않음
- cache는 재생성 가능하지만 무단 삭제하지 않음
- app-owned data 삭제는 별도 명시적 사용자 선택
- third-party XMP를 덮어쓰지 않음

### 17.2 channel migration

Direct ↔ Store 또는 Stable ↔ Beta 이동은 다음 정보를 검사한다.

- current catalog schema와 target read/write range
- sidecar schema
- engine recipe version
- plugin approval store compatibility
- pending export/scan journal
- source bookmark/path identity
- backup 존재와 검증

호환되지 않으면 target 설치는 data를 자동 변환하거나 초기화하지 않고 중단한다.

### 17.3 side-by-side가 필요한 내부 QA

별도 product identity, app data root, protocol namespace, file association, update feed를 사용한다. 같은 source를
read-only로 열더라도 catalog와 sidecar write ownership을 공유하지 않는다.

## 18. hosting과 CDN

### 18.1 필수 속성

- HTTPS
- versioned immutable object
- correct content length/type
- byte-range 지원 여부 기록
- 안정적인 global delivery
- retention과 rollback artifact 보존
- access log의 privacy policy
- origin write 권한 최소화
- publish 후 read-back hash 검증

### 18.2 publish transaction

1. versioned artifact upload
2. CDN/origin에서 다시 download
3. size/hash/signature 검증
4. release notes와 manifest publish
5. feed의 새 version pointer를 원자적으로 전환
6. 여러 region에서 feed/artifact read-back
7. canary update
8. staged rollout 또는 stable 공개

artifact보다 feed를 먼저 publish하지 않는다.

### 18.3 revocation

문제가 있는 version의 artifact를 즉시 삭제하는 것만으로 해결하지 않는다. 이미 설치된 사용자가 있고 forensic
hash가 필요하다.

- feed에서 신규 제공 중지
- revoked version metadata
- emergency fixed version
- updater warning/block 정책
- immutable artifact는 접근 제한 또는 quarantine 상태로 보존
- public advisory에 exact version/hash

## 19. Store와 Direct 중복 방지

### 19.1 설치 detection

- Windows Installer product/upgrade identity
- known install roots
- package identity가 있으면 package family
- running process와 active job
- catalog ownership marker

하나만 보고 결정하지 않는다.

### 19.2 migration UX

```text
다른 Negaflow 배포 채널이 설치되어 있습니다.
현재 채널: Direct Stable 1.4.2
대상 채널: Microsoft Store

1. 작업을 완료하고 catalog backup 검증
2. 현재 앱 제거, 사용자 데이터 유지
3. 대상 앱 설치
4. 호환성 확인 후 기존 catalog 연결
```

자동으로 기존 installer를 강제 제거하거나 user data directory를 삭제하지 않는다.

## 20. 지원과 수명주기

### 20.1 지원 대상 표시

각 release는 다음을 게시한다.

- supported Windows builds
- supported architectures
- last supported app version
- security update window
- scanner route/plugin validation date
- known driver exclusions
- catalog forward/backward compatibility

### 20.2 end of support

EOL app은 launch를 강제로 막지 않되, online update/security capability가 더 이상 안전하지 않으면 정확한
경고를 표시한다. 사용자가 offline으로 자기 사진에 접근하고 export할 수 있는 복구 경로를 보존한다.

server shutdown 전에:

- 마지막 installer와 hashes
- license notices/SBOM
- offline help
- catalog/export migration guidance
- update feed의 terminal metadata

를 보존한다.

## 21. 채널별 QA matrix

| 시나리오 | Direct Stable | Beta | Enterprise | Store MSI/EXE | Store MSIX |
|---|---:|---:|---:|---:|---:|
| clean x64 install | 필수 | 필수 | 필수 | 필수 | gate |
| clean ARM64 install | 필수 | 필수 | 필수 | 필수 | gate |
| offline install | 필수 | 권장 | 필수 | installer 자체 필수 | Store 관리 |
| self-update | 필수 | 필수 | policy off 검증 | 정책 확인 | Store 관리 |
| failed update rollback | 필수 | 필수 | IT 배포 | 필수 | Store/package |
| scanner plugin | 전체 gate | experimental 가능 | policy matrix | 미확정 | 초기 비활성 |
| x86 scanner adapter | 실물 gate | 실험 | policy matrix | 미확정 | 미확정 |
| uninstall data preserve | 필수 | 필수 | 필수 | 필수 | 필수 |
| channel migration | 기준 | Stable 복귀 | 조직 절차 | Direct 충돌 | Direct 충돌 |

## 22. 출시 단계

### Stage 0 — 내부

- development certificate
- isolated data root
- no public updater
- x64/ARM64 CI artifact

### Stage 1 — closed beta

- production-like signing
- immutable beta feed
- explicit users
- update/rollback rehearsal
- scanner hardware evidence 수집

### Stage 2 — Direct Stable

- public trusted signature
- x64/ARM64 offline installer
- stable signed feed
- release notes/SBOM/licenses
- plugin separate distribution

### Stage 3 — enterprise

- offline MSI
- silent deployment contract
- managed update policy
- plugin allowlist policy

### Stage 4 — Store evaluation

- MSI/EXE listing policy spike
- MSIX scanner-less prototype
- full MSIX plugin/storage matrix
- migration and duplicate-install UX

## 23. 금지

- `latest.exe` bytes를 제자리 교체
- Stable app이 parsing 실패 시 Beta feed 사용
- Store MSI/EXE가 자동 Store update된다고 표시
- x64 artifact를 ARM64 native build로 표시
- Debug/nightly를 production publisher로 무제한 서명
- Store와 Direct가 같은 catalog를 동시에 쓰게 허용
- core installer에 SANE/GPL plugin을 조용히 포함
- plugin 없는 상태에서 mock scanner 자동 fallback
- package model이 달라도 같은 QA 결과를 재사용
- Store certification을 scanner 실물 검증으로 간주

## 24. 완료 기준

- Direct Stable x64/ARM64 installer가 exact signed bytes로 QA됨
- architecture 자동 안내와 잘못된 installer failure가 검증됨
- stable/beta feed가 cryptographically 분리됨
- update owner가 About/Diagnostics에 표시됨
- Store MSI/EXE의 기존 사용자 update 제한이 product 정책에 반영됨
- enterprise가 self-update를 정책으로 끌 수 있음
- channel 이동이 catalog/source/plugin 불변식을 지킴
- scanner plugin은 독립 artifact/approval/update 단위를 유지함
- full MSIX는 gate를 통과하기 전 기본 배포로 표시되지 않음
- hosting의 immutable URL, read-back hash, revocation runbook이 검증됨

이 기준을 만족하기 전에는 “Windows 배포 완료”라고 보고하지 않는다. installer가 한 번 실행됐다는 사실은
update, rollback, Store, enterprise, ARM64, plugin 배포가 준비됐다는 증거가 아니다.
