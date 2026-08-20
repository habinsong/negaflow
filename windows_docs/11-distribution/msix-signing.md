# Windows 배포 신뢰 모델 — Authenticode, MSI/Burn, MSIX 서명

기준일: 2026-08-04  
상태: v1 배포 기준 결정, 인증서 발급자·설치 범위는 release 전 확정  
관련 문서:

- [배포 채널](deployment-channels.md)
- [업데이트와 롤백](update-and-rollback.md)
- [스캐너 플러그인 보안과 생명주기](../10-scanner/plugin-security-and-lifecycle.md)
- [상위 의사결정 D-011](../00-overview/decision-register.md#d-011--배포-기본안은-아키텍처별-unpackaged-self-contained-설치다)
- [third-party license inventory](../13-build-and-deps/third-party-licenses.md)

## 1. 결론

Negaflow Windows v1의 기본 배포는 **아키텍처별 unpackaged self-contained app을 WiX 기반 MSI 또는 Burn
bootstrapper로 설치하는 방식**이다.

```text
x64 release
  signed bootstrapper.exe
    └── signed Negaflow-x64.msi
          ├── signed Negaflow.exe
          ├── signed Negaflow.Engine.dll
          ├── signed helper executables and DLLs
          ├── self-contained .NET + Windows App SDK payload
          └── assets, shaders, licenses, manifests

ARM64 release
  signed bootstrapper.exe
    └── signed Negaflow-arm64.msi
          └── native ARM64 payload
```

핵심 결정:

1. x64와 ARM64 설치물은 별도로 만들고 별도로 검증한다.
2. .NET과 Windows App SDK는 v1에서 self-contained로 고정해 runtime drift를 release가 통제한다.
3. installer만 서명하지 않는다. app·native engine·helper·uninstaller/update helper 등 모든 배포 PE와 MSI/outer
   bootstrapper를 서명한다.
4. SHA-256 Authenticode와 RFC 3161 SHA-256 timestamp를 기준으로 한다.
5. build runner가 장기 private key를 평문 PFX 또는 일반 CI secret로 보유하지 않게 한다.
6. release manifest와 SBOM/license inventory는 **최종 서명된 bytes**의 hash를 기록한다.
7. MSIX는 v1 기본안이 아니다. package identity 또는 Store MSIX가 실제 제품 요구가 될 때 별도 검증한다.
8. scanner plugin은 본체 installer에 자동 동봉하지 않고 독립 publisher·signature·approval·update 단위로 둔다.

서명은 publisher identity와 byte integrity를 증명한다. 코드가 안전하거나 scanner가 정확하거나 license가
정리됐다는 증거는 아니다.

## 2. 공식 근거

- [Package and deploy Windows apps overview](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/)
- [Choose a distribution path](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/choose-distribution-path)
- [Distribute an unpackaged WinUI 3 app](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/unpackage-winui-app)
- [Windows App SDK self-contained deployment](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/self-contained-deploy/deploy-self-contained-apps)
- [Windows App SDK deployment overview](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/deploy-overview)
- [Code signing options for Windows app developers](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/code-signing-options)
- [SignTool](https://learn.microsoft.com/en-us/windows/win32/seccrypto/signtool)
- [Time Stamping Authenticode Signatures](https://learn.microsoft.com/en-us/windows/win32/seccrypto/time-stamping-authenticode-signatures)
- [Sign an MSIX package](https://learn.microsoft.com/en-us/windows/msix/package/signing-package-overview)
- [Sign an app package using SignTool](https://learn.microsoft.com/en-us/windows/msix/package/sign-app-package-using-signtool)
- [Create a certificate for package signing](https://learn.microsoft.com/en-us/windows/msix/package/create-certificate-package-signing)
- [MSI/EXE Store package requirements](https://learn.microsoft.com/en-us/windows/apps/publish/publish-your-app/msi/app-package-requirements)
- [Windows Installer rollback](https://learn.microsoft.com/en-us/windows/win32/msi/rollback-installation)
- [Windows Installer major upgrades](https://learn.microsoft.com/en-us/windows/win32/msi/major-upgrades)

Microsoft 문서의 비용, 서비스 이름, 지원 지역과 Store 정책은 바뀔 수 있다. 이 문서는 2026-08-04 조사
snapshot이며 구매·출시 당일 다시 확인한다.

## 3. 왜 MSIX가 기본안이 아닌가

MSIX는 깨끗한 설치·제거, package identity, Store update 같은 이점이 있다. 그러나 Negaflow v1의 핵심에는
다음 Win32 성격이 강하다.

- 외부 위치의 원본과 export destination
- 대형 catalog, sidecar, thumbnail, tile cache
- 독립 실행 scanner plugin과 x86 legacy adapter
- 문제 해결용 diagnostics 도구
- plugin별 별도 설치·승인·업데이트
- 파일시스템과 driver에 대한 실물 검증

MSIX가 이 기능을 원천적으로 모두 막는다고 단정하지 않는다. 다만 v1에서 package identity 이점보다 전체
plugin/storage/update matrix를 먼저 떠안는 비용이 크다. 따라서 단순한 unpackaged folder deployment가 아니라,
**서명되고 transaction을 갖는 전통 installer + self-contained payload**를 기본으로 한다.

package identity가 나중에 필요하면 두 대안을 순서대로 검토한다.

1. 기존 installer와 binary location을 유지하는 packaged-with-external-location
2. full MSIX가 전체 scanner/storage contract를 통과할 때 full packaged channel

MSIX를 선택할 때는 “WinUI 3니까 MSIX”가 아니라 필요한 Windows feature와 실측 결과를 근거로 한다.

## 4. 배포 artifact 계층

### 4.1 architecture별 산출물

| 산출물 | architecture | 역할 |
|---|---|---|
| `Negaflow-<version>-x64.exe` | x64 | 직접 배포 bootstrapper |
| `Negaflow-<version>-x64.msi` | x64 | offline/enterprise 설치 |
| `Negaflow-<version>-arm64.exe` | ARM64 | native ARM64 bootstrapper |
| `Negaflow-<version>-arm64.msi` | ARM64 | native ARM64 offline/enterprise 설치 |
| release manifest | neutral text/JSON | filename, size, SHA-256, version, signer |
| SBOM/license bundle | neutral | dependency provenance와 notices |

한 `AnyCPU` app으로 두 architecture를 통합하지 않는다. C++ engine, SIMD, WIC/DirectX, native runtime,
scanner adapter가 architecture-specific이므로 payload를 분명히 나눈다.

ARM64 사용자가 x64 emulation으로 설치할 수 있더라도 공식 ARM64 download는 native ARM64만 포함한다.
x64 scanner adapter를 별도 plugin으로 실행하는 문제와 본체 architecture를 섞지 않는다.

### 4.2 self-contained 범위

v1 self-contained는 다음을 뜻한다.

- .NET runtime을 architecture별 publish output에 포함
- Windows App SDK dependency를 app 옆에 포함
- native engine과 audited third-party native DLL 포함
- production shader를 사전 컴파일해 포함
- 필요한 resources와 localization 포함

“아무 Windows component에도 의존하지 않는다”는 뜻은 아니다. OS의 Direct3D, Direct2D, WIC, Color
Management, COM, Windows Installer, VC/CRT deployment 조건 등은 정확히 inventory한다.

Windows App SDK 공식 문서가 self-contained unpackaged app의 dependency를 executable 옆에 배치할 수 있다고
설명하지만, 실제 Negaflow output은 clean VM에서 검증해야 한다. 개발 PC의 SDK, Visual Studio, VC runtime,
PATH에 우연히 의존하면 release failure다.

### 4.3 single-file publish는 기본이 아니다

최신 Windows App SDK 문서는 특정 구성의 unpackaged self-contained WinUI 3에서 single-file EXE를 지원한다고
설명한다. 그러나 첫 실행 extraction, native DLL/plugin discovery, signature inventory, crash dump symbol mapping,
antivirus behavior가 달라진다.

Negaflow는 다음을 물리 검증하기 전 single-file을 사용하지 않는다.

- extraction path와 ACL
- 시작 시간과 first-run failure
- native DLL load와 shader/resource lookup
- update 중 old extraction cleanup
- signature verification가 실제 loaded bytes까지 추적되는지
- crash diagnostics와 servicing

v1 기본은 명시적 설치 directory의 multi-file payload다.

## 5. publisher와 certificate 선택

### 5.1 production certificate 요구

직접 웹 배포하는 EXE/MSI에는 Microsoft Trusted Root Program에 연결되는 public code-signing certificate 또는
당시 지원되는 Microsoft managed signing service를 사용한다. self-signed certificate는 다음에만 쓴다.

- local developer build
- 격리된 test VM
- 조직이 root trust를 직접 배포하는 enterprise test

일반 사용자에게 `.cer`를 수동으로 trusted root에 넣으라고 요구하지 않는다. root store 오염과 phishing
학습을 유발하며 public release 신뢰 모델이 아니다.

### 5.2 Azure Artifact Signing

2026-08-04 공식 문서는 Azure Artifact Signing을 기존 Trusted Signing의 새 이름으로 설명하고, Store 밖
배포의 권장 옵션으로 제시한다. 장점은 다음과 같다.

- Microsoft가 publisher identity를 검증
- 장기 private key를 CI runner에 배치하지 않음
- cloud signing과 CI 통합
- physical USB token 관리 불필요

그러나 당시 공식 availability 표는 조직 계정을 미국·캐나다·EU·영국, 개인 계정을 미국·캐나다로 제한한다.
한국 법인/개인 자격으로 사용할 수 있다고 가정하지 않는다. 실제 계약 주체, region, identity validation,
서비스 SLA를 release 전에 확인한다.

현재 지역에서 불가능하면 HSM/token 정책을 만족하는 public CA의 OV code-signing certificate를 사용한다.
EV를 SmartScreen 즉시 우회 수단으로 구매하지 않는다. Microsoft의 2026 문서는 2024년 이후 EV도 OV와 같은
reputation 모델이라고 설명한다.

### 5.3 certificate subject 안정성

publisher identity는 장기 제품 자산이다.

- 법인명/개인명 선택을 출시 전에 확정한다.
- certificate 갱신과 provider 변경 시 subject continuity를 확인한다.
- installer UI, file properties, Store publisher, privacy/legal 문서의 이름을 일치시킨다.
- scanner plugin publisher와 Negaflow publisher를 자동으로 동일하다고 가정하지 않는다.
- certificate thumbprint를 영구 identity로 사용하지 않는다. 갱신 때 바뀐다.

MSIX를 쓸 경우 manifest `Publisher`는 signing certificate `Subject`와 정확히 일치해야 한다. Store 예약
identity를 쓸 때는 Partner Center가 부여한 identity 규칙을 따른다.

## 6. private key와 signing service 경계

### 6.1 금지

- repository에 PFX 또는 private key 저장
- 일반 GitHub Actions secret에 base64 PFX 장기 보관
- developer laptop의 exportable key로 production release 서명
- build job 전체에 signing credential 노출
- pull request job이 production signer 호출
- fork build가 production identity로 서명
- timestamp 실패를 무시하고 release

### 6.2 권장 흐름

```text
untrusted build stage
    └── compile/test/package unsigned inner artifacts
           └── malware/provenance/license checks
                  └── protected signing stage
                         ├── verify expected hash and build identity
                         ├── sign inner PE files
                         ├── build final MSI/bootstrapper
                         ├── sign outer artifacts
                         └── independent signature verification
                                └── immutable publish staging
```

signing stage는 protected branch/tag, reviewed workflow, 최소 권한 identity, environment approval, audit log를
사용한다. cloud signer 또는 HSM이 sign operation만 허용하고 raw key export를 허용하지 않는 구성이 목표다.

### 6.3 build와 sign 사이의 byte ownership

sign 직전 manifest에 unsigned payload hash와 build provenance를 기록한다. signer는 allowlisted artifact 이름,
architecture, version, commit, pipeline run을 확인한다. sign 후에는 bytes가 바뀌므로 최종 public release
manifest를 다시 생성한다.

sign 후 다음 작업을 금지한다.

- PE version resource 수정
- installer metadata 수정
- archive 재패키징으로 installer 내부 변경
- executable compression/packing
- config file을 PE resource에 추가

서명 뒤 변하는 것은 별도 detached manifest나 hosting metadata뿐이어야 한다.

## 7. Authenticode 서명 범위

### 7.1 반드시 서명할 것

- `Negaflow.exe`
- native render engine DLL
- C ABI shim DLL
- updater/helper/crash reporter executable
- uninstall 또는 repair helper
- WIA/TWAIN adapter를 본체가 직접 배포하는 경우 각 executable
- MSI package
- Burn/bootstrapper executable
- app-local COM server가 있으면 그 executable/DLL
- 자체 제작한 모든 PE binary

third-party DLL에 upstream signature가 있더라도 final inventory에서 검증한다. upstream-signed DLL을 다시
서명할지 그대로 유지할지는 license, signature provenance, servicing 정책으로 결정하며 이중 서명을 무작정
덮어쓰지 않는다.

### 7.2 별도 scanner plugin

SANE, vendor SDK, community adapter 같은 독립 plugin은 자체 publisher가 서명할 수 있다. 본체 certificate로
재서명하면 support·license·책임 경계가 흐려진다.

plugin installer는 다음을 자체 제공한다.

- signed installer
- signed executable/DLL
- manifest와 content hash
- publisher와 version
- license/notice/source 정보
- update/revocation URL 또는 정책

Negaflow는 설치 후 plugin Authenticode와 SHA-256 identity를 검증하고 사용자가 승인한다. “같은 publisher”는
승인을 보조할 수 있지만 silent trust 조건이 아니다.

### 7.3 non-PE asset

shader blob, ICC profile, preset, localization, license, JSON schema는 Authenticode 대상이 아닐 수 있다. 이들은
release manifest의 SHA-256과 installer payload integrity로 보호한다. runtime-critical asset에는 engine/API
version을 함께 기록한다.

## 8. 서명 알고리즘과 timestamp

### 8.1 기본값

- file digest: SHA-256
- timestamp protocol: RFC 3161
- timestamp digest: SHA-256
- application verification policy: Authenticode default policy
- 승인된 API 하한 VM과 Stable 시점의 지원 Windows 11 VM에서 online/offline verification

개념적 SignTool 형태:

```powershell
signtool sign /fd SHA256 /tr <RFC3161_URL> /td SHA256 <artifact>
signtool verify /pa /all /tw <artifact>
```

실제 certificate selection 옵션은 signing provider/HSM에 맞춘다. 위 명령은 secret 경로를 문서화하기 위한
것이 아니다.

### 8.2 timestamp가 필요한 이유

유효한 trusted timestamp는 서명이 certificate 유효 기간 중 생성되었음을 검증하는 데 필요하다. certificate
만료 뒤에도 적절한 정책 아래 기존 release의 서명을 계속 검증할 수 있게 한다.

검증 사항:

- timestamp가 실제 존재함
- RFC 3161 chain이 유효함
- timestamp time이 signing certificate validity 안임
- file digest와 timestamp digest가 SHA-256임
- `signtool verify` warning도 release failure로 취급

timestamp server 일시 장애 때 unsigned 또는 untimestamped release를 publish하지 않는다. signing job을
재시도하되, 동일 artifact identity와 audit trail을 유지한다.

### 8.3 SHA-1을 쓰지 않는다

v1 최소 OS가 Windows 11 후보이므로 legacy SHA-1 호환 dual-signing이 필요하지 않다. SHA-1을 sole signature,
timestamp digest 또는 신규 release fallback으로 쓰지 않는다.

## 9. 서명 순서

### 9.1 MSI/Burn

권장 순서:

1. release configuration으로 architecture별 app publish
2. build output allowlist와 dependency inventory 생성
3. 자체 PE binary 서명 및 timestamp
4. 모든 PE signature 검증
5. signed payload로 MSI 생성
6. MSI 서명 및 timestamp
7. signed MSI로 Burn/bootstrapper 생성
8. bootstrapper 서명 및 timestamp
9. clean VM install
10. 설치된 PE를 다시 enumerate해 signature 검증
11. 최종 artifact hash/size/provenance manifest 생성
12. immutable release URL에 publish

outer installer signature만 보고 내부 PE 서명을 생략하지 않는다. Microsoft Store의 MSI/EXE 경로도 installer와
포함된 모든 PE가 trusted CA chain으로 서명되어야 한다고 명시한다.

### 9.2 MSIX/MSIX bundle

MSIX package는 유효하고 device가 신뢰하는 certificate로 서명되어야 한다. MSIX bundle은 공식 SignTool
문서에 따라 bundle만 서명해도 내부 package를 포괄하므로 inner architecture package를 별도로 중복 서명할
필요가 없다.

다만 package 내부의 독립 PE Authenticode 정책은 distribution channel과 runtime verification 요구에 따라
별도로 유지할 수 있다. MSIX package signature와 PE Authenticode는 같은 개념이 아니다.

MSIX sign 전에 확인한다.

- package block map/hash algorithm
- identity name
- four-part package version
- publisher subject exact match
- processor architecture
- capabilities/extensions
- app execution trust level
- bundle architecture selection

MSIX는 signing 후 별도 `timestamp` operation을 할 수 없으므로 sign operation에서 RFC 3161 timestamp를 함께
요청한다.

## 10. version 체계

### 10.1 제품 version

Negaflow의 사용자-facing semantic version과 Windows installer version을 분리하되 mapping을 deterministic하게
한다.

```text
productVersion: 1.4.2
buildRevision: 37
MSIX version: 1.4.2.37
MSI ProductVersion-visible fields: 1.4.2
release identity: 1.4.2+win.37
```

Windows Installer는 product version 비교에서 첫 세 필드만 사용하는 제약이 있으므로 fourth build number로만
MSI upgrade 순서를 표현하지 않는다. 같은 public semantic version으로 여러 public MSI를 교체하지 않는다.

### 10.2 MSI identifiers

- `UpgradeCode`: 같은 product line/architecture/install context 안에서 안정적으로 유지
- `ProductCode`: major upgrade package마다 규칙에 따라 변경
- `PackageCode`: byte가 다른 MSI마다 변경
- x64와 ARM64 product relationship을 명시적으로 정의
- per-user와 per-machine install context를 같은 upgrade chain에서 섞지 않음

nonidentical MSI에 같은 `PackageCode`를 재사용하지 않는다. versioned URL의 파일 bytes도 절대 교체하지
않는다.

### 10.3 file version과 protocol version

EXE/DLL file/product version, installer version, catalog schema, scanner protocol, engine ABI는 서로 다른
version axis다. release manifest에 모두 기록하되 하나를 올렸다고 다른 호환성이 자동 보장된다고 보지 않는다.

## 11. MSIX를 선택할 때의 추가 규칙

### 11.1 full MSIX gate

다음을 Windows x64와 ARM64에서 통과해야 한다.

- Library/catalog/cache 위치와 WAL semantics
- arbitrary user-selected source/export paths
- file picker ownership
- external scanner plugin launch
- x86 TWAIN adapter launch
- plugin update와 approval hash 변경
- crash dump와 support bundle
- shell integration과 file associations
- install/update/uninstall 뒤 user data 보존
- Store policy와 license compliance

성공 전에는 MSIX가 scanner-inclusive Windows판의 배포 답이라고 쓰지 않는다.

### 11.2 packaged with external location

package identity가 필요한 Windows API가 생기지만 기존 MSI/update/plugin 모델을 유지해야 한다면 먼저
packaged-with-external-location을 spike한다.

이 모델은 identity package를 등록하지만 app binary는 기존 external install location에 둔다. 다음을 검증한다.

- manifest `Executable`과 실제 absolute install root
- registration/unregistration transaction
- update 중 identity와 binary version 원자성
- per-user/per-machine registration context
- repair와 uninstall
- package identity가 없는 recovery launch
- plugin child process와 file access

identity package 등록 성공만으로 전체 제품을 packaged app으로 간주하지 않는다.

### 11.3 Store MSIX

Store에 MSIX를 제출하면 Microsoft가 certification 후 재서명하고 hosting/update를 제공할 수 있다. 이때도
다음은 Negaflow 책임이다.

- source build provenance
- third-party license
- package capability 최소화
- runtime behavior와 privacy
- artifact/corpus 제외
- scanner plugin 정책
- Store identity와 직접 배포 identity의 migration

## 12. SmartScreen과 사용자 신뢰

### 12.1 확정적으로 말할 수 있는 것

2026-08-04 Microsoft 공식 code-signing 안내는 다음을 구분한다.

- Store MSIX: Store가 재서명하며 Store 설치에서 서명 비용 없음
- Store MSI/EXE: publisher가 trusted CA certificate로 installer와 PE를 서명
- 직접 배포: Azure Artifact Signing 또는 public CA certificate 사용
- OV/EV/managed signing 모두 새 직접 배포 artifact에서 reputation이 축적될 수 있음
- EV가 즉시 SmartScreen bypass를 보장하지 않음
- self-signed/unsigned public download는 적합하지 않음

### 12.2 하지 않을 약속

- “서명했으니 경고가 절대 없다”
- “EV면 첫날부터 경고가 없다”
- “certificate 하나로 모든 plugin이 신뢰된다”
- “Defender가 설치물을 항상 허용한다”
- “다운로드 수 N이면 reputation이 생긴다”

reputation 알고리즘과 threshold를 추측하지 않는다. 초기 release에는 signature가 정상인데 SmartScreen UI가
나올 가능성을 사용자 지원 문서와 telemetry-free support flow에 반영한다.

### 12.3 download page

직접 배포 page는 다음을 명시한다.

- publisher exact display name
- version과 release date
- x64/ARM64 선택 기준
- filename, size, SHA-256
- 최소 Windows version
- certificate 확인 방법
- changelog와 known issues
- scanner plugin은 별도 설치라는 사실
- official domain 외 mirror 경고

사용자에게 보안 경고를 무조건 무시하거나 “More info → Run anyway”를 습관적으로 누르라고 안내하지 않는다.
signature publisher가 기대값과 다르면 설치 중단을 안내한다.

## 13. release manifest

최종 manifest에는 최소 다음을 기록한다.

```text
schemaVersion
productVersion
buildRevision
gitCommit
sourceDate/build timestamp policy
targetOS
architecture
artifact filename
artifact byte size
artifact SHA-256
signer subject
signing certificate serial/thumbprint
certificate issuer
signature digest
timestamp authority and time
Windows App SDK version/mode
.NET runtime version/mode
native dependency inventory hash
SBOM hash
license bundle hash
engine ABI
catalog schema compatibility
scanner protocol range
channel
```

thumbprint는 audit용이며 publisher continuity의 유일한 key가 아니다. manifest 자체도 release channel의 signed
metadata 또는 detached signature로 보호한다. 단순 HTTPS만으로 update manifest 무결성을 끝내지 않는다.

## 14. 서명 검증 gate

### 14.1 CI 정적 gate

- expected artifact allowlist와 실제 output 일치
- 예상하지 못한 EXE/DLL/driver/script 없음
- 모든 required PE에 signature 존재
- trusted chain build 성공
- code-signing EKU 확인
- SHA-256 digest
- RFC 3161 timestamp
- signer subject allowlist
- certificate expiry/revocation 확인 가능 상태
- x64/ARM64 machine type 일치
- signed file hash가 final manifest와 일치
- installer 내부 payload와 loose build output 차이 검토

SignTool exit code 2의 warning도 release failure로 취급한다.

### 14.2 clean VM gate

승인된 API 하한 clean image와 Stable 시점의 지원 Windows 11 clean image에서 다음을 실행한다.

- 인터넷 연결 상태 install
- 인터넷 차단 상태 signature/timestamp 검증과 install
- standard user install 또는 UAC path
- launch, import/develop/export smoke
- repair
- upgrade from previous stable
- failed upgrade rollback
- uninstall
- user catalog/source/export 보존
- Windows Security/SmartScreen 실제 UI 기록
- 설치된 모든 PE signature 재검증

app을 실제로 열지 않았다면 UI/install QA를 완료했다고 말하지 않는다.

### 14.3 architecture gate

- x64 package는 x64 clean VM/physical PC에서 native 실행
- ARM64 package는 ARM64 physical Windows에서 native 실행
- process explorer/diagnostics로 본체 architecture 확인
- 잘못된 architecture installer는 설명 가능한 오류로 중단
- ARM64에서 x64 emulation 성공을 ARM64 build 검증으로 세지 않음

## 15. certificate 갱신과 사고 대응

### 15.1 정상 갱신

certificate 만료 최소 수개월 전에 다음을 준비한다.

- identity validation 재개
- 새 certificate subject 비교
- signing service permission rotation
- test release dual-window 검증
- old timestamped release 검증
- update verifier의 publisher continuity rule 갱신
- Store identity 영향 확인

certificate가 바뀌어도 기존 approval을 무조건 무효화하거나 무조건 유지하지 않는다. publisher subject,
trusted chain, release metadata, authorized certificate rotation record를 함께 본다.

### 15.2 key compromise

의심 시:

1. signer access를 즉시 중지한다.
2. certificate revocation 절차를 시작한다.
3. publish/update endpoints를 freeze한다.
4. 어떤 artifact가 해당 key로 서명됐는지 inventory한다.
5. clean key/identity로 recovery release를 준비한다.
6. updater가 compromised signature 하나만으로 recovery metadata를 신뢰하지 않게 out-of-band channel을 쓴다.
7. 사용자와 enterprise admin에게 exact impacted versions/hashes를 알린다.

reputation 손실보다 공급망 안전을 우선한다.

## 16. 개발과 테스트 certificate

개발용 self-signed certificate는 production publisher와 혼동하지 않게 별도 subject를 쓴다.

- 이름에 `Development` 또는 `Test` 명시
- test machine의 `TrustedPeople` 등 최소 범위에만 설치
- private key export와 수명 제한
- production update feed 접근 금지
- production plugin approval store와 분리
- test build UI에 non-production 표시

개발 certificate 설치 스크립트가 enterprise root store를 광범위하게 수정하지 않게 한다. 제거 절차도 test
setup에 포함한다.

## 17. 설치 범위 결정

per-user와 per-machine 중 하나를 출시 전에 고정한다.

### per-user 후보

장점:

- admin 권한 없이 설치 가능
- user-scoped app data/plugin approval과 자연스럽게 맞음
- 개인 photo workstation에 단순

리스크:

- install root ACL과 executable tampering 검증 필요
- 여러 계정에서 중복 설치
- enterprise 관리가 복잡할 수 있음

### per-machine 후보

장점:

- `%ProgramFiles%`의 강한 기본 ACL
- machine-wide inventory와 enterprise 배포
- shared app binaries

리스크:

- UAC/admin 필요
- user plugin/data와 ownership 경계 추가
- updater elevation과 session handoff

어느 쪽이든 upgrade는 동일 install context를 유지한다. Windows Installer는 per-user product를 per-machine
major upgrade로 자동 넘기는 용도가 아니다.

## 18. non-goals와 금지

- unsigned nightly를 stable feed에 게시
- installer 실행 중 인터넷에서 검증되지 않은 runtime을 즉석 다운로드
- versioned URL의 bytes 교체
- x64/ARM64 package를 같은 filename으로 덮어쓰기
- user data를 uninstall 기본값으로 삭제
- scanner plugin을 본체 publisher로 무단 재서명
- MSIX package identity를 storage truth key로 사용
- certificate thumbprint를 영구 product ID로 사용
- signing 완료를 release readiness 전체 완료로 표현
- build/test 실패 artifact를 수동 서명해 우회

## 19. release 전 체크리스트

### 정책

- [ ] direct web, Store, enterprise channel 범위 확정
- [ ] per-user/per-machine install context 확정
- [ ] x64/ARM64 별도 product/upgrade code 정책 확정
- [ ] publisher legal name 확정
- [ ] signing provider와 지역 자격 재확인
- [ ] certificate rotation/compromise runbook 승인

### build

- [ ] .NET self-contained 확인
- [ ] Windows App SDK self-contained 확인
- [ ] native dependency allowlist 확인
- [ ] production shader/resource inventory 확인
- [ ] SBOM와 license notice 생성
- [ ] source/fixture/private asset 제외 확인

### sign

- [ ] 모든 PE Authenticode 서명
- [ ] MSI 서명
- [ ] bootstrapper 서명
- [ ] SHA-256/RFC 3161 SHA-256 확인
- [ ] signer subject/issuer/EKU 확인
- [ ] timestamp와 revocation status 확인
- [ ] final signed hash manifest 생성

### install

- [ ] clean x64 install/launch/repair/upgrade/uninstall
- [ ] clean ARM64 install/launch/repair/upgrade/uninstall
- [ ] offline install
- [ ] failed-upgrade rollback
- [ ] non-admin/elevation UX
- [ ] installed payload signature sweep
- [ ] user data 보존
- [ ] plugin 없는 import/develop/export 정상 동작

## 20. 남은 실측과 결정

- 한국의 실제 release 주체가 Azure Artifact Signing을 사용할 수 있는가
- OV certificate를 쓸 경우 HSM/token과 CI signing을 어떻게 연결할 것인가
- per-user와 per-machine 중 scanner/plugin 운영에 더 적합한 설치 범위는 무엇인가
- WiX MSI 단독과 Burn bootstrapper 중 prerequisite/repair UX가 더 안정적인가
- self-contained size, cold start, working set이 framework-dependent 대비 얼마인가
- Windows App SDK security servicing을 app release SLA로 얼마나 빨리 반영할 것인가
- packaged-with-external-location이 실제로 필요한 package-identity API가 있는가
- Store MSI/EXE와 직접 배포를 동시에 운영할 때 update ownership을 어떻게 구분할 것인가
- certificate rotation이 updater의 publisher allowlist와 plugin trust store에 미치는 영향은 무엇인가

이 항목이 남아 있어도 v1 방향은 명확하다. **unpackaged self-contained x64/ARM64 설치물, 전체 payload
Authenticode 서명, 독립 plugin 서명, 최종 bytes 검증**이 기준선이다.
