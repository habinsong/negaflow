# 서드파티 라이선스·SBOM·배포 경계

> 상태: Windows 구현 전 공급망·배포 설계  
> 기준일: 2026-08-04  
> 대상: Negaflow Windows x64·ARM64 코어 앱, 설치 프로그램, 스캐너 플러그인, 개발 도구, 데이터 자산  
> 주의: 이 문서는 기술적 감사 기준이며 법률 자문이 아니다. 실제 출시 artifact와 당시 라이선스 원문을 대상으로 최종 검토한다.

## 0. 결론

Negaflow Windows판은 `Apache-2.0 앱 + permissive library 몇 개`라는 한 줄 설명으로 배포할 수 없다. 실제 출시물에는 다음처럼 서로 다른 조건의 구성 요소가 들어갈 수 있다.

- Apache-2.0인 Negaflow 자체 코드
- MIT인 LittleCMS core
- 프로젝트 고유 permissive license인 libtiff와 별도 LZW notice
- zlib license인 zlib
- public domain인 SQLite core
- CDDL-1.0 또는 LGPL-2.1 중 하나를 명시적으로 선택해야 하는 LibRaw
- Microsoft의 별도 binary redistribution terms가 적용될 수 있는 .NET/Windows App SDK/Visual C++ runtime
- LGPL인 TWAIN DSM 후보
- GPL-2.0-or-later인 별도 SANE 플러그인과 SANE 실행 경로
- vendor 고유 조건의 scanner driver/Data Source
- 빌드 도구 자체의 라이선스와 별도 운영 조건이 있는 WiX Toolset
- 자체 제작, 공개 데이터, 제조사 자료가 섞일 수 있는 profile·preset·시험 corpus

따라서 다음을 제품 정책으로 고정한다.

1. **배포하는 정확한 파일**을 기준으로 라이선스를 판단한다.
2. vcpkg/NuGet metadata만 믿지 않고 upstream release의 실제 license와 notices를 보존한다.
3. 직접 의존성뿐 아니라 선택 feature와 전이 의존성을 inventory한다.
4. 코어 앱, architecture별 installer, 스캐너 플러그인, source bundle에 각각 별도 SBOM을 만든다.
5. SANE·GPL 경계는 별도 repository/process/protocol뿐 아니라 **별도 설치·업데이트·배포 선택**까지 유지한다.
6. 프로세스 분리나 DLL 분리는 법률 결론이 아니다. 실제 결합·배포 방식과 라이선스 조건을 다시 본다.
7. CDDL/LGPL 구성 요소는 선택 license, linkage, 수정 여부, source 제공 방식을 릴리스 전에 확정한다.
8. 사용하지 않는 codec, tool, optional plugin은 build graph와 installer에서 제거한다.
9. notice와 source access는 온라인 링크 하나에만 의존하지 않고 설치물에서 접근 가능하게 한다.
10. SBOM 생성 성공은 라이선스 준수나 보안 검토 완료를 뜻하지 않는다.

---

## 1. 현재 확인된 프로젝트 경계

### 1.1 macOS 저장소의 현재 사실

현재 `/Users/songhabin/Negaflow`의 루트 `LICENSE`는 Apache License 2.0이다. `Package.swift`에는 외부 Swift package dependency가 없고 Apple system framework 및 system `sqlite3`를 링크한다. 현재 공개 provenance 문서는 macOS 앱이 SANE code/header/binary를 포함하지 않고 별도 GPL-2.0-or-later 프로그램과 JSON/NDJSON으로 통신한다고 기록한다.

이 사실은 Windows판의 dependency를 자동 승인하지 않는다. Windows판은 C++ codec, color engine, native runtime과 installer가 추가되므로 새 release inventory가 필요하다.

### 1.2 현재 SANE 플러그인 저장소의 사실

별도 `/Users/songhabin/negaflow-scanner-sane` 저장소의 `LICENSE`는 플러그인 자체를 GPL-2.0-or-later로 선언하고, `COPYING`에 GPL v2 전문을 둔다. provenance 문서는 다음 경계를 기록한다.

- 플러그인과 코어 앱은 별도 repository·executable이다.
- 코어 앱은 플러그인을 링크하거나 app bundle에 포함하지 않는다.
- SANE 실행 파일은 독립 설치된다.
- device-independent JSON/NDJSON과 결과 파일로 통신한다.
- plugin release는 자체 license, notices, source archive를 제공한다.

Windows에서도 이보다 약한 경계를 만들지 않는다. 다만 Windows용 SANE 지원을 실제로 배포할지는 별도 제품·장치·법무 결정이다.

### 1.3 Windows판의 예상 배포 단위

```text
Negaflow Windows Core
├── x64 MSI/Burn bundle
├── ARM64 MSI/Burn bundle
├── app files
│   ├── WinUI 3/.NET shell
│   ├── native engine
│   ├── approved in-process libraries
│   ├── assets/shaders
│   ├── LICENSE
│   ├── THIRD-PARTY-NOTICES
│   └── SBOM
└── update metadata

Scanner plugins — independently selected and installed
├── WIA adapter
├── TWAIN x64 adapter + optional DSM decision
├── TWAIN x86 adapter if justified
├── SANE plugin if separately approved
└── vendor-specific adapter if separately approved
```

코어 앱 installer와 plugin installer가 같은 웹 페이지에 나열될 수는 있다. 그것이 한 package, 한 license, 한 update transaction임을 뜻해서는 안 된다.

---

## 2. 용어와 판정 단위

### 2.1 source license와 binary distribution terms

소스 저장소가 MIT라고 해서 다운로드한 모든 runtime binary와 redistributable이 동일한 조건이라고 가정하지 않는다. 특히 Microsoft 구성 요소는 다음을 분리해 확인한다.

- GitHub source repository license
- NuGet package license expression과 package 내 license/notice
- Windows용 product distribution license
- self-contained runtime에 포함된 파일
- Visual Studio REDIST 목록
- 설치 프로그램과 redistributable의 Microsoft Software License Terms

### 2.2 build-time과 ship-time

| 구분 | 예시 | release inventory 처리 |
|---|---|---|
| build-only | compiler, CMake, WiX CLI, test framework runner | 사용 조건·버전 기록, 보통 app SBOM payload와 분리 |
| generated artifact input | FXC/DXC, resource compiler | compiler/license/provenance를 build manifest에 기록 |
| app runtime | native DLL, .NET runtime, Windows App Runtime | artifact SBOM과 notices에 포함 |
| OS component | WIC, WIA, D3D11, Direct2D | 재배포하지 않으면 payload inventory에서 분리, 지원 OS 계약에 기록 |
| optional plugin | TWAIN/SANE/vendor adapter | plugin별 SBOM·license·installer |
| user-installed driver | vendor WIA minidriver/TWAIN DS | 재배포 금지 기본, detect된 provenance만 진단 |
| test-only data | 공개 image corpus | 앱 payload 제외, CI 사용 권리와 attribution 별도 |

build-only라고 라이선스 검토가 필요 없다는 뜻은 아니다. 생성된 output에 대한 조건, 상업 사용 조건, 조직 차원의 fee, service terms가 있을 수 있다.

### 2.3 link 형태

- source incorporation
- static link
- app-local dynamic link
- system-installed dynamic link
- separate executable/process
- command-line tool invocation
- build-only code generator
- downloaded-at-runtime component

각 방식은 유지보수·보안 경계를 바꾸지만 라이선스 의무를 자동으로 없애지 않는다.

### 2.4 수정 여부

`unmodified`는 단지 upstream source diff가 없다는 뜻으로 사용한다. 다음은 수정 또는 별도 파생 파일로 기록한다.

- local patch
- overlay port patch
- build-system patch
- backport
- generated amalgamation 변경
- source file 내 macro 또는 copyright header 변경
- vendor sample code의 제품 코드 편입

compiler define과 feature selection은 항상 source modification은 아니지만, 배포되는 code composition을 바꾸므로 inventory에 기록한다.

---

## 3. 라이선스 분류와 기본 정책

### 3.1 Permissive

예: MIT, BSD-2-Clause, BSD-3-Clause, zlib, libpng license, libtiff license, Apache-2.0.

기본 처리:

- copyright와 permission/license text 보존
- binary distribution notice 조건 확인
- 광고·endorsement 제한 확인
- source modification 표시 조건 확인
- Apache NOTICE 파일이 있으면 section 4 조건과 함께 처리
- patent grant/termination 조항이 있는 license는 정확한 원문 보존

`permissive`는 `notice 불필요`라는 뜻이 아니다.

### 3.2 Public domain

SQLite upstream은 deliverable core code와 documentation이 public domain이라고 설명한다. 그러나 다음을 구분한다.

- 공식 SQLite core source
- vcpkg port의 build script
- third-party wrapper/provider
- 암호화 extension 등 별도 상용/비-public-domain 구성 요소
- Negaflow가 추가한 수정 파일

SQLite core에 의무적 notice가 없더라도 provenance와 SBOM에는 이름·version·source/hash를 기록한다. jurisdiction 또는 조직 정책상 public-domain dedication에 추가 보증이 필요한지는 별도 법무 판단이다.

### 3.3 Weak copyleft/file-level reciprocal

예: LGPL-2.1, CDDL-1.0, MS-RL.

이들을 `GPL은 아니므로 permissive`로 분류하지 않는다.

- covered file 또는 library를 구분한다.
- 수정 파일의 공개/제공 조건을 확인한다.
- executable distribution에서 source 접근 고지 조건을 확인한다.
- relink/replacement 권리와 static/dynamic link 영향을 확인한다.
- license 전문과 notice를 포함한다.
- 동일 이름의 다른 선택 라이선스가 있는지 확인한다.
- package를 어떤 license option으로 소비했는지 명시한다.

### 3.4 Strong copyleft

예: GPL-2.0-or-later, GPL-3.0-or-later.

Negaflow 코어 앱에 GPL source, object, static library, app-local library를 포함하거나 링크하지 않는 것이 기본 정책이다. GPL component가 필요한 경우 다음을 먼저 수행한다.

1. 제품 기능상 정말 필요한지 확인
2. OS API 또는 permissive 대안 평가
3. 별도 프로그램·repository·배포 경계 설계
4. 통신 친밀도와 공유 구조 검토
5. complete corresponding source와 설치 notice 준비
6. 실제 distribution 전체를 법무 검토

별도 process라는 사실 하나로 derivative/aggregate 판단이 끝났다고 표현하지 않는다.

### 3.5 Proprietary 또는 redistribution-controlled

예: vendor scanner driver/SDK, Microsoft redistributable, commercial codec, font, profile, installer extension.

- 다운로드 가능하다고 재배포 가능한 것이 아니다.
- 개발 SDK license와 runtime redistribution 권한을 분리한다.
- architecture별 binary 권리를 확인한다.
- 수정·추출·app-local 복사 가능 여부를 확인한다.
- 자동 다운로드·silent install이 허용되는지 확인한다.
- 계약 종료와 update/withdrawal 시 대응을 기록한다.

---

## 4. Windows v1 직접 의존성 후보 판정표

아래 표는 기준일의 설계 판정이다. 실제 version과 artifact를 고정하기 전 최종 승인이 아니다.

| 구성 요소 | 예상 역할 | 확인된 license/조건 | 링크·배포 후보 | 현재 판정 |
|---|---|---|---|---|
| Negaflow 자체 | 앱·엔진 | Apache-2.0 | source/app binary | 승인 기준 |
| LittleCMS core | ICC transform | MIT | in-process native library | 승인 후보 |
| LittleCMS `fastfloat` | optional plugin | GPL-3.0-or-later 경고 | 포함 안 함 | 금지 |
| LittleCMS `threaded` | optional plugin | GPL-3.0-or-later 경고 | 포함 안 함 | 금지 |
| libtiff | TIFF/BigTIFF | libtiff permissive + LZW notice | in-process native library | 승인 후보 |
| zlib | TIFF Deflate/DNG 조건부 | zlib license | 최소 feature | 승인 후보 |
| SQLite core | catalog | public domain | 정확한 provider 하나 | 승인 후보 |
| LibRaw | camera RAW | LGPL-2.1 또는 CDDL-1.0 선택 | 별도 native DLL 후보 | 조건부·법무 결정 필요 |
| Windows App SDK source | WinUI 3/runtime | upstream source MIT, 실제 package terms 확인 | NuGet/self-contained runtime | package별 승인 필요 |
| .NET library package | shell/runtime | package는 MIT 계열, Windows product distribution terms 별도 | self-contained 후보 | exact artifact 승인 필요 |
| Visual C++ Runtime | C++ runtime | Visual Studio license/REDIST 조건 | central redist 또는 app-local 승인 목록 | licensed redistribution 필요 |
| WiX Toolset | MSI/Burn 생성 | source MS-RL + 현재 OSMF 운영 조건 | build-only | 상업 사용 조건 승인 필요 |
| WIA API | scanner adapter | Windows OS API | OS 제공 | 재배포 없음 |
| TWAIN DSM | TWAIN routing | upstream LGPL | system/app-local 결정 전 검토 | 조건부 plugin |
| vendor WIA/TWAIN driver | 장치 지원 | vendor별 | 사용자 설치 기본 | 무허가 재배포 금지 |
| SANE plugin | 선택 scanner 경로 | GPL-2.0-or-later | 별도 process/repository/installer | 코어와 별도 조건부 |

### 4.1 표를 읽는 규칙

- `승인 후보`는 기능·성능·ARM64·보안 검증도 통과해야 한다.
- `package별 승인`은 repository license 배지로 끝나지 않는다.
- `금지` feature가 transitive/default feature로 들어와도 실패한다.
- 후보 dependency가 실제 manifest에 없다면 notice에 미리 넣지 않는다.
- 반대로 실제 payload에 있는 파일이 표에 없으면 release를 실패시킨다.

---

## 5. LittleCMS 2

### 5.1 허용 범위

LittleCMS 2 core의 고정 release source는 MIT license다. core library를 in-process CPU color reference로 사용할 수 있는 후보로 유지한다.

필수 artifact:

- exact upstream tag/commit
- source archive hash
- vcpkg baseline과 port version
- build feature 목록
- core `LICENSE`
- binary hash
- x64/ARM64 build provenance
- local patch 또는 `none`

### 5.2 금지 optional feature

upstream `meson_options.txt`는 `fastfloat`와 `threaded` plugin을 GPL 3.0을 수용할 때만 사용하라는 경고와 함께 별도 option으로 둔다. Negaflow 코어 정책:

- `fastfloat = false`
- `threaded = false`
- vcpkg default feature 변화가 있어도 두 plugin이 들어오지 않게 검증
- 설치된 binary 이름·export·SBOM에서 plugin 부재 확인
- upstream `utils`를 app installer에 포함하지 않음

자체 bounded thread pool과 core `THR` context 사용은 GPL plugin을 포함하지 않는 별도 구현 방향이다.

### 5.3 update gate

- license file diff
- Meson/CMake option diff
- vcpkg feature diff
- 새 전이 JPEG/TIFF dependency 여부
- ICC malformed corpus
- CPU reference golden
- x64/ARM64 ABI와 symbol inventory

상세 기술 설계는 [../04-color-management/lcms2.md](../04-color-management/lcms2.md)를 따른다.

---

## 6. libtiff와 압축 codec

### 6.1 libtiff

libtiff는 고유한 permissive license를 사용하며 binary/source distribution에서 copyright와 permission notice를 보존한다. 이름을 광고·홍보에 사용하는 제한도 원문대로 유지한다. 최신 release license에는 LZW 구현 관련 별도 BSD notice가 포함될 수 있으므로 license file 일부를 임의로 요약해 넣지 않고 **release의 전체 `LICENSE.md`**를 보존한다.

### 6.2 최소 feature

현재 설계는 TIFF의 다음 codec만 필요로 한다.

- uncompressed
- LZW — libtiff 내부
- Deflate — zlib

따라서 initial vcpkg build는 default feature를 끄고 실제 port에서 `zip`에 해당하는 최소 feature만 승인한다. 다음은 요구가 생기기 전까지 포함하지 않는다.

- JPEG-in-TIFF/libjpeg-turbo
- LZMA/xz
- WebP
- Zstd
- LERC
- tools/contrib executables

### 6.3 zlib

zlib license는 origin 오표시 금지, 수정 source 표시, source distribution에서 notice 보존 조건을 가진다. product documentation acknowledgment는 upstream 원문상 appreciated일 수 있지만, Negaflow는 감사 가능성을 위해 notice에 전체 license를 포함한다.

기록할 것:

- zlib exact version/hash
- libtiff가 실제로 link한 zlib artifact
- static/dynamic 형태
- local patch와 수정 표시
- debug/release artifact 분리
- x64/ARM64 hash

### 6.4 codec 추가 gate

codec 하나를 켜면 다음이 늘어난다.

- 공격 입력 surface
- transitive license와 notices
- architecture binary
- fuzz corpus
- installer 크기
- CVE 대응 범위

파일 한 개를 읽는 편의를 위해 default feature 전체를 켜지 않는다.

상세 기술 설계는 [../05-image-io/libtiff.md](../05-image-io/libtiff.md)를 따른다.

---

## 7. SQLite

### 7.1 core 판정

SQLite 공식 copyright 문서는 배포되는 core code와 documentation이 public domain이라고 설명한다. Negaflow는 이를 `license 없음`이라는 빈 문자열로 기록하지 않고 다음처럼 provenance를 남긴다.

```text
component: SQLite
status: Public-Domain
upstream: https://sqlite.org/
version/check-in: exact
source hash: exact
provider/wrapper: separately inventoried
compile options: exact
```

### 7.2 구분해야 할 것

- 공식 SQLite amalgamation
- vcpkg가 적용한 patch
- C# provider/NuGet wrapper
- encryption extension
- recovery extension 또는 tool
- ICU/FTS 등 optional feature

SQLite Encryption Extension는 core public-domain 지위와 다르므로 명시적 commercial license 없이 포함하지 않는다. 사용하지 않는 extension은 build에서 끈다.

### 7.3 provider 중복 금지

다음 둘이 동시에 다른 native SQLite를 넣을 수 있다.

- vcpkg `sqlite3`
- managed NuGet provider의 bundled native runtime

release payload에는 선택한 native SQLite provider 하나만 있어야 한다. 동일 process에 두 버전이 로드되면 license inventory뿐 아니라 파일 locking, compile option, recovery semantics도 불명확해진다.

---

## 8. LibRaw — 출시 전 선택이 필요한 구성 요소

### 8.1 확인된 upstream 사실

LibRaw 공식 문서는 library를 다음 두 license 중 하나로 사용할 수 있다고 설명한다.

- LGPL-2.1
- CDDL-1.0

upstream은 future version에서 licensing이 바뀌지 않는다고 보장하지 않으므로 매 release에서 다시 확인한다. bundled code에는 dcraw 계보와 BSD-licensed 부분 등 추가 acknowledgement가 있으므로 최상위 license 두 개만 notice에 넣고 끝내지 않는다.

### 8.2 현재 기술 권장

```text
Negaflow native engine
        │ narrow app-owned ABI
        ▼
Negaflow.Raw.LibRaw.dll
        │
        ▼
Pinned LibRaw + approved features only
```

이 DLL 경계의 목적:

- LibRaw file/patch 범위 명확화
- decoder crash·version provenance 관찰
- source bundle 재현
- 교체/업데이트 단위 분리
- 앱 고유 코드와 covered code 혼합 최소화

이 구조는 어느 license option의 의무도 자동 충족하지 않는다.

### 8.3 CDDL 후보 검토

CDDL을 선택한다면 최소 다음을 법무 검토한다.

- covered software/file 범위
- 수정한 LibRaw source file 공개·제공 방식
- executable distribution 시 source 접근 고지
- adapter file이 covered file에 포함되는지
- static vs dynamic linkage 영향
- license 전문과 notices
- source 제공 위치와 유지 기간
- 특허·상표·보증 조항

`CDDL이면 변경 공개 의무 없음`이라고 문서화하지 않는다.

### 8.4 LGPL 후보 검토

LGPL-2.1을 선택한다면 최소 다음을 법무 검토한다.

- library와 수정분의 source 제공
- license 전문과 notices
- 사용자가 수정 library로 교체 또는 relink할 수 있는 권리
- dynamic link와 installer 파일 보호 방식
- reverse engineering 제한과 EULA 충돌 여부
- static link 시 object/relink 요구
- source offer 또는 직접 source 배포 방식
- adapter와 library의 경계

`DLL로 만들면 끝`이라고 문서화하지 않는다.

### 8.5 feature와 전이 의존성

LibRaw feature에 따라 다음이 추가될 수 있다.

- zlib — deflated DNG
- libjpeg-turbo — lossy DNG 등
- Jasper — 일부 RED 경로 후보
- OpenMP runtime
- 별도 demosaic pack

초기 정책:

- OpenMP off
- GPL demosaic pack 포함 금지
- lossy DNG는 corpus와 제품 범위가 승인될 때만
- `libraw::raw_r` thread-safe target 후보
- 전이 dependency를 LibRaw notice에 묻지 않고 각각 inventory

### 8.6 최종 선택 gate

- [ ] RAW가 Windows v1 필수인지 확정
- [ ] exact LibRaw release 선정
- [ ] CDDL-1.0/LGPL-2.1 중 선택
- [ ] linkage와 adapter 경계 법무 확인
- [ ] 수정 여부와 source bundle 생성
- [ ] transitive feature/license 확인
- [ ] x64/ARM64 실제 build/run
- [ ] installer에서 notice/source access 확인
- [ ] updater가 source/notice를 누락하지 않는지 확인

결정하지 못하면 v1에서 camera RAW 지원을 보류하는 것이 잘못된 license 설명으로 배포하는 것보다 안전하다. 상세 기술 설계는 [../05-image-io/libraw.md](../05-image-io/libraw.md)를 따른다.

---

## 9. 조건부 image/SIMD dependency

### 9.1 libjpeg-turbo

WIC JPEG 경로가 품질·metadata·성능 계약을 만족하면 넣지 않는다. 채택 시 upstream license 문서의 다음 묶음을 그대로 검토한다.

- IJG license
- Modified BSD 3-Clause
- SIMD code의 zlib license 등 component notices
- 사용 API가 libjpeg인지 TurboJPEG인지
- binary/static distribution 때 필요한 IJG acknowledgment
- tools가 payload에 들어가는지

license 문서는 binary-only 또는 static-linked app documentation에 IJG 기반임을 알리는 문구가 필요하다고 설명한다. 임의 번역 한 줄 대신 승인한 notice와 원문을 포함한다.

### 9.2 libpng

WIC PNG 16-bit/ICC 계약이 부족할 때만 평가한다. 채택 시 exact release의 `LICENSE`와 전이 zlib를 각각 기록한다. `libpng-2.0` 같은 SPDX expression만 복사하지 않고 release source의 실제 notice를 보존한다.

### 9.3 libdeflate, zlib-ng, Zstd

성능 측정 없이 바꾸지 않는다.

- API 호환이 license/source identity 호환을 뜻하지 않는다.
- zlib replacement를 쓰면 실제 구현 이름과 version을 SBOM에 기록한다.
- CPU ISA dispatch와 ARM64 build를 확인한다.
- libtiff가 어느 implementation을 link했는지 binary provenance로 확인한다.
- license 및 patent 조항을 exact release에서 다시 검토한다.

### 9.4 Google Highway

현재는 채택하지 않은 SIMD 후보다. upstream은 Apache-2.0/BSD-3-Clause 선택 license를 제공한다. 도입 시:

- 실제 선택 license를 manifest에 기록
- Apache-2.0을 선택하면 LICENSE/NOTICE와 modification 기록 검토
- BSD-3-Clause를 선택하면 notice/endorsement 조건 보존
- header-only/template code가 각 object에 편입되는 범위 기록
- x64/ARM64 target macro가 GPL 또는 별도 package를 끌지 않는지 확인

성능 gate는 [../16-cpu/simd-and-dispatch.md](../16-cpu/simd-and-dispatch.md)를 따른다.

---

## 10. Microsoft 런타임과 SDK

### 10.1 Windows App SDK

공개 Windows App SDK source repository는 MIT로 표시된다. 그러나 Negaflow가 실제로 배포하는 것은 source checkout만이 아니다.

- `Microsoft.WindowsAppSDK` NuGet package
- Windows App Runtime package/binaries
- bootstrapper/installer 또는 self-contained payload
- architecture-specific native binaries
- package 자체 third-party notices

따라서 exact NuGet package 내부의 license expression, license file, notices, redistribution terms를 보존한다. GitHub repository의 MIT badge 하나로 runtime binary 전체를 설명하지 않는다.

### 10.2 .NET

.NET 공식 license 정보는 다음을 구분한다.

- library package: 일반적으로 MIT
- product distribution: Windows에서는 .NET Library License
- source repository: MIT
- 각 distribution의 third-party notices
- self-contained app에 편입되는 host/runtime 파일

Negaflow가 self-contained publish를 사용하면 resolved output의 실제 파일과 함께 해당 .NET distribution license 및 third-party notice를 포함·보존한다. framework-dependent publish로 바꾸더라도 설치 전제와 runtime download terms를 다시 검토한다.

### 10.3 Visual C++ Runtime

Microsoft 문서는 Visual C++ Redistributable 배포가 licensed Visual Studio 사용자에게 허용되고 해당 Microsoft Software License Terms 및 REDIST 목록을 따른다고 설명한다.

운영 규칙:

- 사용한 Visual Studio/Build Tools edition과 license 권한 확인
- 해당 release의 REDIST 목록 보존
- debug non-redist 파일 배포 금지
- architecture에 맞는 supported redistributable 사용
- central deployment와 app-local 중 공식 권장·업데이트·installer 요구 비교
- redistributable signature와 exact version 기록
- Microsoft에서 받은 unmodified package 사용
- installer가 비공식 mirror에서 runtime을 받지 않음

### 10.4 Windows system DLL

D3D11, Direct2D, DXGI, WIC, WIA 등 OS component를 app installer에서 복사하지 않는다. system DLL을 payload에 넣으려면 OS SDK에 존재한다는 이유가 아니라 명시적인 redistribution 권한이 있어야 한다.

### 10.5 FXC/DXC와 shader output

- compiler executable은 build tool inventory에 기록한다.
- runtime compiler를 app에 넣지 않는다.
- compiler package/license와 generated blob provenance를 기록한다.
- generated DXBC/DXIL이 어떤 compiler/source/options에서 나왔는지 baseline manifest에 기록한다.
- shader source가 third-party algorithm/code에서 유래했다면 별도 provenance가 필요하다.

---

## 11. WiX Toolset와 installer 도구

### 11.1 2026-08-04 현재 확인 사항

WiX Toolset source repository의 `LICENSE.TXT`는 MS-RL이다. 현재 repository README는 source license와 별개로 Open Source Maintenance Fee 정책을 안내하고, 수익을 창출하는 사용에 fee가 필요하다고 명시한다.

따라서 WiX는 다음처럼 관리한다.

- `오픈 소스이므로 무료`라고 가정하지 않는다.
- 실제 사용할 WiX major/version의 license와 OSMF 정책을 확인한다.
- Negaflow의 사용이 정책상 어떤 범주인지 확인한다.
- 필요한 sponsor/fee/상업 license 절차를 release budget에 반영한다.
- source 수정 또는 WiX 파일 편입 시 MS-RL file-level 조건을 검토한다.
- WiX extension과 Burn bootstrapper payload의 license를 별도 inventory한다.
- tool 자체와 tool이 만든 MSI/Bootstrapper output의 권리 관계를 정확한 terms로 확인한다.

### 11.2 대안 판단

WiX 조건을 수용할 수 없다고 해서 임의의 installer generator로 바꾸지 않는다. 후보마다 다음을 비교한다.

- x64/ARM64 MSI와 bundle 지원
- update/rollback/repair
- code signing
- per-user/per-machine
- custom action 최소화
- license와 commercial use 조건
- long-term servicing
- deterministic build와 SBOM

현재 배포 아키텍처가 WiX MSI/Burn을 전제로 하므로, 도구 변경은 [../11-distribution/deployment-channels.md](../11-distribution/deployment-channels.md)의 결정 변경 절차를 거친다.

---

## 12. 스캐너 플러그인 라이선스

### 12.1 WIA

WIA COM API는 Windows system surface다. 그러나 WIA minidriver와 vendor installer는 Microsoft OS component와 동일하지 않을 수 있다.

- vendor driver를 Negaflow installer에 포함하지 않는다.
- vendor download page를 단순 링크할 수 있는지와 재배포 권한을 구분한다.
- driver binary를 추출해 app-private로 복사하지 않는다.
- user-installed driver의 version/signature는 진단 정보이지 Negaflow SBOM payload가 아니다.
- vendor SDK sample code를 복사하면 별도 license/provenance가 필요하다.

### 12.2 TWAIN DSM

공식 TWAIN DSM repository는 LGPL license를 사용한다고 밝히며 32-bit/64-bit 구현을 제공한다. 실제 채택 전 다음을 결정한다.

- system-installed DSM을 탐색할지
- official DSM을 plugin package에 app-local 배포할지
- DSM exact release와 binary provenance
- LGPL version과 전문
- modified/unmodified
- replacement/source 접근 방식
- x86/x64 각각의 package
- DSM 외 vendor Data Source의 소유권

TWAIN adapter process가 Apache-2.0이어도 DSM을 함께 배포하면 plugin package notices와 source 의무가 생길 수 있다. DS는 보통 vendor installer 소유이므로 DSM license에 포함된다고 보지 않는다.

### 12.3 SANE

Windows SANE 경로를 제공한다면 macOS보다 약하지 않은 분리를 유지한다.

```text
Negaflow Core — Apache-2.0 distribution
       │ versioned device-independent JSON/NDJSON
       ▼
Negaflow SANE Plugin — GPL-2.0-or-later distribution
       │ documented CLI/process boundary
       ▼
SANE executable/backends — exact upstream license/provenance
```

필수 조건:

- 별도 repository
- 별도 executable
- 별도 installer 또는 사용자의 명시적 별도 설치
- 코어 MSI payload에 미포함
- 별도 LICENSE/COPYING/notices/SBOM/source bundle
- SANE header/library를 코어 또는 Apache plugin에 링크하지 않음
- SANE data structure를 wire contract에 복사하지 않음
- 코어 update가 plugin을 묵시적으로 설치·업데이트하지 않음
- 사용자가 코어만 설치할 수 있음
- distribution arrangement 전체 법무 검토

GNU FAQ가 pipe/command-line communication을 무조건 별도 프로그램으로 판정한다고 요약하지 않는다. 통신의 친밀도, 공유 구조, 상호 의존성, 함께 배포하는 방식까지 본다.

### 12.4 Vendor SDK plugin

- SDK 사용권과 runtime redistribution 권한
- 장치별 royalty 또는 계정 조건
- sample code 수정·재배포
- driver bundling 금지
- architecture별 binary
- signing certificate owner
- support 종료와 binary 철회
- 개인정보/telemetry

어느 vendor SDK도 코어 scanner abstraction의 필수 dependency가 되면 안 된다.

상세 구조는 [../10-scanner/plugin-architecture.md](../10-scanner/plugin-architecture.md)와 [../10-scanner/plugin-security-and-lifecycle.md](../10-scanner/plugin-security-and-lifecycle.md)를 따른다.

---

## 13. 데이터·사진·ICC·폰트·아이콘의 권리

코드 license scanner만으로 release를 승인하지 않는다. 다음 비코드 자산도 inventory한다.

### 13.1 자체 제작 자산

- 제작자/권리자
- 제작 날짜와 source file
- 사용한 도구
- 제3자 template/brush/font/model 사용 여부
- 배포 범위
- 원본과 export hash

현재 macOS provenance는 ScannerKit sample TIFF, app icon, look preset, scanner profile이 maintainer 제작 또는 측정이라고 기록한다. Windows로 복사할 때 해당 provenance와 hash를 유지한다.

### 13.2 제조사 데이터시트

- 공개된 curve의 사실값과 문서 표현을 구분한다.
- chart image나 장문 설명을 앱에 복제하지 않는다.
- 수치가 측정값인지 chart 추정인지 표시한다.
- film/scanner 상표는 호환성 식별 용도이며 제휴를 암시하지 않는다.

### 13.3 ICC profile

ICC 포맷이 공개됐다는 사실과 특정 profile 파일의 재배포 권리는 다르다.

- 사용자가 제공한 profile은 사용자 데이터로 취급
- OS/display/vendor profile을 app bundle로 복사하지 않음
- bundled working/output profile은 source·license·hash 확인
- scanner measurement로 생성한 profile은 source measurement 권리와 생성 provenance 기록
- profile 이름과 profile byte identity를 분리

### 13.4 시험 corpus

- CI 다운로드 전용과 app shipping을 구분
- DOI/version/license/hash 고정
- attribution 필요 여부
- derivative/golden image 배포 권리
- private user photo 금지
- 원본을 공개 artifact로 업로드할 권리 확인
- benchmark screenshot에도 source 권리 확인

현재 FILM-R v2는 품질 측정 시에만 다운로드하고 앱/저장소에 넣지 않는 기존 경계를 유지한다.

### 13.5 폰트와 아이콘

- Windows system font를 app payload로 복사하지 않음
- XAML glyph/font dependency가 실제로 shipping되는지 확인
- open-source font는 OFL 등 정확한 license와 reserved font name 조건 확인
- SVG/icon pack의 author/license/attribution 확인
- 생성형 도구를 사용했다면 source·약관·사람의 편집 기록을 보존

---

## 14. Dependency manifest

각 직접·전이 구성 요소는 다음 필드를 가진다.

```yaml
componentId: stable-id
name: upstream-name
version: exact-version
source:
  repository: canonical-url
  commitOrTag: exact
  archiveHash: sha256-or-sha512
package:
  manager: vcpkg-or-nuget-or-manual
  packageId: exact
  baselineOrLock: exact
  packageHash: exact
license:
  expression: SPDX-when-accurate
  choice: selected-option-or-null
  files:
    - exact-license-file
  notices:
    - exact-notice-file
usage:
  scope: build-or-runtime-or-plugin-or-test
  linkage: static-or-dynamic-or-process-or-none
  features: []
  architectures: [x64, arm64]
modifications:
  patches: []
  owner: null
  removalCondition: null
artifacts:
  - path
  - hash
review:
  reviewedAt: date
  reviewer: owner
  legalStatus: approved-or-pending
  securityStatus: approved-or-pending
```

이는 형식 예시이며 현재 production schema가 아니다. 실제 schema에는 secret, 개인 이름, 내부 URL을 공개 SBOM에 노출하지 않도록 privacy review를 한다.

### 14.1 expression만으로 부족한 경우

- dual license에서 실제 선택
- license 예외
- component별 혼합 license
- source와 binary terms 차이
- commercial redistribution agreement
- 폰트 reserved name
- data attribution
- vendor EULA

이 경우 machine-readable expression과 사람이 승인한 obligation record를 함께 둔다.

---

## 15. SBOM 설계

### 15.1 목적

SBOM은 다음 질문에 신속히 답하기 위한 inventory다.

- 취약점이 발표된 component가 어느 artifact에 있는가?
- x64에는 있는데 ARM64에는 없는 library가 있는가?
- plugin이 코어 installer에 섞였는가?
- 실제 binary가 manifest version과 일치하는가?
- 어느 source와 license로 재현할 수 있는가?

### 15.2 artifact별 SBOM

- Negaflow x64 MSI
- Negaflow ARM64 MSI
- x64 app payload
- ARM64 app payload
- update bundle/feed artifact
- WIA plugin package
- TWAIN x64 package
- TWAIN x86 package
- 각 vendor plugin
- SANE plugin package
- source compliance bundle

하나의 repo-level SBOM으로 모든 artifact를 대표하지 않는다.

### 15.3 포함 관계

SBOM은 최소 다음 relationship을 표현한다.

- installer `CONTAINS` app payload
- app `DEPENDS_ON` Windows App Runtime/.NET/native DLL
- libtiff `DEPENDS_ON` zlib
- LibRaw `DEPENDS_ON` 실제 enabled codec
- plugin `CONTAINS` app-local DSM인 경우
- plugin `INTERACTS_WITH` user-installed driver는 payload 포함과 구분
- generated shader `GENERATED_FROM` source/compiler manifest는 별도 provenance 연결

### 15.4 생성 도구

Microsoft `sbom-tool`은 SPDX SBOM 생성 후보지만 자동 채택하지 않는다.

검증할 것:

- CMake/vcpkg native static library 포착
- NuGet transitive package 포착
- self-contained .NET runtime 포착
- WiX/Burn 최종 payload 포착
- embedded license files
- architecture별 차이
- manually bundled assets/plugins
- package verification와 schema validation

도구가 놓친 component는 별도 adapter/manifest input으로 보완한다. 생성 도구 version과 실행 옵션도 기록한다.

### 15.5 SBOM 검증

- 최종 staged directory와 file-by-file 비교
- PE import와 static library provenance 보완
- NuGet/vcpkg lock과 비교
- installer extract 결과와 비교
- license inventory와 component count 비교
- 금지 component name/hash scan
- source URL과 version이 placeholder가 아닌지 검사
- schema validator 통과
- release signature 전 최종 생성

---

## 16. Third-Party Notices

### 16.1 사용자 접근 위치

- installer가 설치하는 `Third-Party Notices` 문서
- 앱 `About` 또는 `Legal` 화면에서 로컬 문서 열기
- release download 페이지
- source repository의 release-specific archive

앱이 실행되지 않는 상황에서도 설치 directory에서 접근 가능하게 한다. 온라인 링크만 제공하지 않는다.

### 16.2 생성 규칙

- exact artifact manifest에서 생성
- component 이름과 version
- upstream URL
- 선택 license
- 원문 license/notice
- required acknowledgment
- modification/source availability 안내
- plugin은 별도 section 또는 별도 notice
- 중복 license 전문은 deduplicate할 수 있지만 component mapping을 잃지 않음
- 번역 요약은 원문을 대체하지 않음

### 16.3 Negaflow 자체 license

Apache-2.0 `LICENSE`를 app distribution에 포함한다. Negaflow 또는 포함한 Apache-licensed component에 `NOTICE`가 생기면 Apache-2.0 section 4 요구를 검토하고 derivative distribution의 readable notice 위치에 반영한다.

### 16.4 금지

- NuGet 페이지 링크만 나열
- SPDX ID만 표시
- source tree의 현재 `master` license에 링크
- 사용하지 않은 dependency notice를 대량 포함해 실제 inventory를 숨김
- 반대로 static-linked component를 DLL 목록에 없다는 이유로 누락
- license text를 요약문으로 교체
- x64 notice를 ARM64에 무검증 복사

---

## 17. Source compliance bundle

CDDL/LGPL/GPL component를 배포하는 artifact에는 실제 의무를 충족하는 source 제공 전략이 필요하다. 기술적으로 다음을 묶을 수 있다.

- 정확한 upstream source archive
- cryptographic hash
- 모든 local patch
- build recipe/preset/toolchain 설명
- enabled features
- license 전문
- copyright notices
- 재빌드에 필요한 non-secret manifest
- source와 binary version mapping

### 17.1 배포 위치

선택지:

- binary download 옆에 source archive 직접 제공
- installer에 source archive 포함
- 유효한 written offer가 license상 허용되고 운영 가능한 경우 그 방식

Negaflow의 선호는 가능하면 **동일 release 페이지에 exact source archive를 직접 제공**하는 것이다. 링크 유실, 버전 불일치, 제공 기간 운영 부담을 줄일 수 있다. 그러나 실제 license가 written offer 또는 다른 요건을 어떻게 규정하는지는 법무가 확인한다.

### 17.2 재현성

source archive만 제공하고 build에 필요한 patch/config를 누락하지 않는다. private signing key와 proprietary build infrastructure는 source bundle에 넣지 않지만, 해당 library를 재빌드하는 데 필요한 공개 가능한 recipe는 포함한다.

---

## 18. Installer와 update의 라이선스 보존

### 18.1 clean install

- LICENSE/THIRD-PARTY-NOTICES/SBOM 설치
- app About에서 현재 version 문서 열림
- architecture와 notice가 일치
- source compliance URL/version 일치
- plugin은 설치하지 않은 상태가 기본

### 18.2 update

- 새 dependency manifest로 notice 재생성
- 삭제된 component notice가 history artifact에는 남고 현재 설치물에서는 정확히 갱신
- CDDL/LGPL/GPL source archive를 새 binary와 동시에 게시
- license 선택이 조용히 바뀌지 않음
- plugin update가 core notice를 덮어쓰지 않음

### 18.3 uninstall

- app-owned license files 제거 가능
- 사용자 사진/catalog/source는 제거하지 않음
- shared VC runtime/vendor driver를 임의 제거하지 않음
- plugin uninstaller가 core notice나 다른 plugin source bundle을 제거하지 않음

### 18.4 offline

인터넷이 없어도 사용자는 설치된 구성 요소의 license를 볼 수 있어야 한다. source 제공이 온라인인 경우 URL, exact version, 접근 실패 시 support 경로를 로컬 notice에 기록한다.

---

## 19. 자동화할 release gate

### 19.1 payload inventory

- staged directory의 모든 파일 hash
- PE architecture와 signer
- imported DLL 목록
- managed assembly/package identity
- embedded resource/asset manifest
- installer extraction 결과

### 19.2 manifest 일치

- payload 파일마다 owner component가 하나 이상 존재
- component마다 license status가 `approved`
- direct/transitive package lock 일치
- x64/ARM64 expected difference allowlist
- local patch hash 일치
- source archive가 binary version과 일치

### 19.3 금지 항목

- SANE binary/header/library in core payload
- LittleCMS `fastfloat`/`threaded` GPL plugin
- LibRaw GPL demosaic pack
- debug CRT/non-redist files
- unapproved vendor driver/DSM/Data Source
- runtime HLSL compiler
- test corpus/private photo
- unknown unsigned executable/DLL
- license가 `UNKNOWN`, `NOASSERTION`인데 면제가 없는 component

### 19.4 notice 검증

- required license file 포함
- expected component/version 문자열 포함
- required IJG acknowledgment 등 component-specific rule
- stale component notice 검출
- app About local link
- source URL/version/hash
- SPDX schema validation

자동화가 license 해석을 대신하지 않는다. 승인한 규칙이 실제 artifact에서 깨지지 않았는지 확인한다.

---

## 20. Dependency 추가 절차

1. 필요한 제품 문제를 기록한다.
2. Windows/표준 library/기존 dependency로 해결 가능한지 확인한다.
3. 후보 upstream 정본과 maintenance 상태를 확인한다.
4. exact release source와 hash를 확보한다.
5. license, notices, patents, trademarks, commercial terms를 조사한다.
6. default/optional/transitive feature를 펼친다.
7. x64/ARM64 build와 runtime을 확인한다.
8. 공격 surface와 fuzzing 계획을 만든다.
9. static/dynamic/process/build-only 경계를 결정한다.
10. source 제공·notice·SBOM 생성 proof를 만든다.
11. binary size, startup, memory, throughput을 측정한다.
12. 법무·보안·기술 승인을 기록한다.
13. 한 dependency만 manifest에 추가한다.

단순 header 하나를 복사하는 것도 이 절차의 축소판을 거친다. Stack Overflow, blog, vendor sample의 출처 불명 code를 편입하지 않는다.

---

## 21. Dependency 업데이트 절차

### 21.1 diff

- upstream changelog와 security advisory
- license/notice/copyright
- repository owner와 source URL
- build option/default feature
- transitive dependency
- ABI/export symbol
- minimum compiler/OS
- x64/ARM64 support
- source archive signature/hash

### 21.2 검증

- clean restore/build
- license/SBOM/notice diff
- malformed input corpus
- image/color golden
- catalog migration
- GPU/CPU conformance
- installer payload diff
- source compliance bundle 재생성

### 21.3 차단 조건

- license가 미확정으로 변경
- 새로운 copyleft component 유입
- source 또는 license file 누락
- ARM64 artifact 미생성
- known security fix가 빠진 older port
- unverifiable prebuilt binary
- required commercial terms 승인 없음
- notice generator가 final artifact와 불일치

---

## 22. 보안과 license를 함께 보는 이유

과거 취약 version을 `license가 편하다`는 이유로 고정하면 안 된다. 반대로 긴급 보안 update라고 license 변경을 생략해서도 안 된다.

각 component 상태는 두 축으로 관리한다.

| 보안 | 라이선스 | 판정 |
|---|---|---|
| 승인 | 승인 | release 후보 |
| 승인 | 미정 | 배포 차단 |
| 취약 | 승인 | 배포 차단 또는 명시적 완화/긴급 결정 |
| 취약 | 미정 | 배포 차단 |

CVE scanner가 `not affected`라고 판정하려면 실제 feature, 호출 경로, version, patch 근거를 기록한다. package 이름이 같다는 이유로 blanket dismissal하지 않는다.

---

## 23. 저장소에 보존할 감사 자료

Windows 구현 저장소가 생기면 다음을 version control에 둔다.

```text
third_party/
  manifest/
  licenses/
  notices/
  patches/
  source-index/
  approvals/

release/
  sbom/
  payload-manifest/
  source-compliance/
```

단, upstream source tarball이나 대형 binary를 무조건 Git에 vendoring하지 않는다. license가 허용하고 retention 정책에 맞는 immutable artifact storage를 사용할 수 있다. 저장소에는 URL, hash, signature, retrieval evidence와 보존 위치를 기록한다.

### 23.1 approval record

- component/version
- exact artifact
- use/link/distribution
- selected license
- obligations
- notices/source delivery
- reviewer/date
- expiry or next review
- open question
- replacement/removal plan

승인은 새 major version이나 license diff에 자동 승계되지 않는다.

---

## 24. 법무 검토가 반드시 필요한 미결정

1. LibRaw를 Windows v1에 포함할지
2. 포함한다면 CDDL-1.0과 LGPL-2.1 중 어느 option을 선택할지
3. LibRaw adapter/link/source 제공 방식
4. TWAIN DSM을 app-local로 배포할지 system 설치를 사용할지
5. Windows용 SANE plugin을 제공할지, 어느 installer/channel에서 제공할지
6. core와 plugin을 같은 download page/installer UI에서 제시하는 방식
7. .NET self-contained Windows distribution의 정확한 license/notice 묶음
8. Windows App Runtime self-contained payload의 정확한 terms
9. Visual C++ redistributable을 bootstrapper에 포함할 권리와 방식
10. WiX Toolset의 현재 Open Source Maintenance Fee 적용과 비용 승인
11. scanner vendor SDK/driver 재배포가 필요한 장치가 있는지
12. bundled ICC/profile/font/icon/test data 권리

이 항목이 결정되지 않았는데 release artifact를 먼저 만들지 않는다.

---

## 25. Architecture Decision Record에 남길 것

각 중요한 선택은 다음 질문에 답한다.

- 왜 이 dependency가 필요한가?
- OS API나 기존 component로 해결하지 못한 근거는 무엇인가?
- 어느 exact version/feature를 쓰는가?
- x64/ARM64에서 동일한가?
- static/dynamic/process/build-only 중 무엇인가?
- 어느 license option을 선택했는가?
- notice/source/SBOM 의무는 무엇인가?
- 보안 update owner는 누구인가?
- 제거 또는 대체 조건은 무엇인가?
- 실제 release evidence는 어디 있는가?

`법무 확인 필요`를 영구 상태로 두지 않는다. 출시 전에 승인 또는 제외로 닫는다.

---

## 26. 출시 전 체크리스트

### 코어 앱

- [ ] root Apache-2.0 LICENSE 포함
- [ ] 모든 staged file이 component manifest에 연결됨
- [ ] LittleCMS core MIT license 포함
- [ ] LittleCMS GPL optional plugin 부재
- [ ] libtiff 전체 release license와 LZW notice 포함
- [ ] zlib exact license 포함
- [ ] SQLite source/provider 구분
- [ ] LibRaw가 있다면 선택 license와 source compliance 승인
- [ ] Windows App SDK/.NET package 내부 license/notices 반영
- [ ] Visual C++ REDIST 권리와 exact package 확인
- [ ] x64/ARM64 SBOM 각각 생성·검증

### Installer

- [ ] WiX 또는 선택 도구의 상업 사용 조건 승인
- [ ] build-only tool이 payload에 들어가지 않음
- [ ] debug/non-redist runtime 부재
- [ ] offline third-party notices 접근 가능
- [ ] update 후 notice/source version 일치
- [ ] uninstall이 shared/vendor component를 무단 제거하지 않음

### 스캐너

- [ ] 코어 payload에 SANE/TWAIN/vendor driver가 우발적으로 없음
- [ ] WIA adapter와 vendor driver 소유권 구분
- [ ] TWAIN DSM exact license/source/replacement 정책
- [ ] 각 plugin 별도 SBOM/notices/version
- [ ] SANE plugin 별도 GPL LICENSE/COPYING/source
- [ ] process 분리만으로 법률 결론을 내리지 않았음
- [ ] plugin 없는 코어 설치가 완전함

### 자산과 시험

- [ ] bundled resource provenance와 hash
- [ ] ICC/profile 재배포 권리
- [ ] font/icon source와 license
- [ ] 시험 corpus가 app artifact에 들어가지 않음
- [ ] private photo/path가 SBOM·notice·support bundle에 없음

### 감사

- [ ] license diff가 reviewer에게 보임
- [ ] `UNKNOWN`/`NOASSERTION` 면제 없음 또는 만료·근거 있음
- [ ] source compliance download 실제 접근 확인
- [ ] release page와 installed notice가 같은 build ID
- [ ] 모든 승인 날짜와 담당자 기록

---

## 27. 금지 패턴

- GitHub license badge만 보고 승인
- vcpkg SPDX field만 법률 근거로 사용
- `DLL이면 LGPL 해결`이라고 단정
- `별도 process면 GPL 해결`이라고 단정
- `public domain이므로 inventory 불필요`라고 판단
- source repository MIT를 Microsoft binary terms 전체로 일반화
- WiX가 open source이므로 상업 사용 비용·조건이 없다고 가정
- default vcpkg feature를 무검토 사용
- codec tool/contrib executable까지 installer에 포함
- GPL optional plugin이 성능이 좋다는 이유로 core에 포함
- vendor driver를 설치 PC에서 추출해 재배포
- online license URL만 넣고 offline notice 누락
- current `main`의 license file에 링크하고 release 원문 미보존
- dual license에서 선택을 기록하지 않음
- static library를 PE import에 없다는 이유로 SBOM에서 누락
- build tool을 app runtime dependency로 오분류
- test-only corpus를 release payload에 포함
- source archive와 shipped binary version 불일치
- ARM64 artifact를 x64 SBOM 복사본으로 설명
- security emergency를 이유로 license diff 생략
- license 승인을 새 major version에 자동 승계

---

## 28. 공식·원문 근거

### 프로젝트

- [Negaflow Apache-2.0 LICENSE](../../LICENSE)
- [현재 Negaflow provenance](../../docs/legal/PROVENANCE.md)
- [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0)
- [Apache GPL compatibility 설명](https://www.apache.org/licenses/GPL-compatibility)
- [GNU FAQ — aggregates and separate programs](https://www.gnu.org/licenses/gpl-faq.html)

### Native dependencies

- [LittleCMS 2.19.1 LICENSE](https://github.com/mm2/Little-CMS/blob/lcms2.19.1/LICENSE)
- [LittleCMS optional plugin license warning](https://github.com/mm2/Little-CMS/blob/lcms2.19.1/meson_options.txt)
- [libtiff 4.7.2 LICENSE](https://gitlab.com/libtiff/libtiff/-/blob/v4.7.2/LICENSE.md)
- [zlib upstream repository and LICENSE](https://github.com/madler/zlib)
- [SQLite public-domain statement](https://sqlite.org/copyright.html)
- [LibRaw official licensing](https://www.libraw.org/about)
- [LibRaw LGPL-2.1 text](https://github.com/LibRaw/LibRaw/blob/0.22-stable/LICENSE.LGPL)
- [LibRaw CDDL-1.0 text](https://github.com/LibRaw/LibRaw/blob/0.22-stable/LICENSE.CDDL)
- [libjpeg-turbo license roll-up](https://github.com/libjpeg-turbo/libjpeg-turbo/blob/main/LICENSE.md)
- [Google Highway license files](https://github.com/google/highway)

### Microsoft runtime와 build

- [Windows App SDK repository/license](https://github.com/microsoft/WindowsAppSDK)
- [.NET license information](https://github.com/dotnet/core/blob/main/license-information.md)
- [.NET runtime third-party notices](https://github.com/dotnet/runtime/blob/main/THIRD-PARTY-NOTICES.TXT)
- [Latest supported Visual C++ Redistributable](https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist)
- [Determine which DLLs to redistribute](https://learn.microsoft.com/en-us/cpp/windows/determining-which-dlls-to-redistribute)
- [WiX Toolset repository and OSMF notice](https://github.com/wixtoolset/wix)
- [WiX MS-RL license](https://github.com/wixtoolset/wix/blob/main/LICENSE.TXT)
- [Microsoft sbom-tool](https://github.com/microsoft/sbom-tool)

### Scanner

- [TWAIN DSM official repository](https://github.com/twain/twain-dsm)
- [SANE backends repository](https://gitlab.com/sane-project/backends)
- [WIA overview](https://learn.microsoft.com/en-us/windows/win32/wia/-wia-startpage)

---

## 29. 관련 문서

- [vcpkg-cmake.md](vcpkg-cmake.md)
- [../04-color-management/lcms2.md](../04-color-management/lcms2.md)
- [../05-image-io/libtiff.md](../05-image-io/libtiff.md)
- [../05-image-io/libraw.md](../05-image-io/libraw.md)
- [../10-scanner/plugin-architecture.md](../10-scanner/plugin-architecture.md)
- [../10-scanner/plugin-security-and-lifecycle.md](../10-scanner/plugin-security-and-lifecycle.md)
- [../10-scanner/twain-wia.md](../10-scanner/twain-wia.md)
- [../11-distribution/deployment-channels.md](../11-distribution/deployment-channels.md)
- [../11-distribution/update-and-rollback.md](../11-distribution/update-and-rollback.md)
- [../12-performance/ci-and-testing.md](../12-performance/ci-and-testing.md)
- [../99-plan/maintenance.md](../99-plan/maintenance.md)

---

## 30. 완료 정의

라이선스와 공급망 준비가 완료됐다고 말하려면 다음이 실제 release candidate에서 증명되어야 한다.

- 최종 installer를 풀어 나온 모든 파일이 owner component와 exact source에 연결된다.
- x64와 ARM64가 각각 정확한 SBOM을 가진다.
- 모든 component의 license option, linkage, modification, notices가 승인됐다.
- LittleCMS GPL plugin, SANE, unapproved DSM/driver, debug runtime이 코어 payload에 없다.
- CDDL/LGPL/GPL component의 exact source와 patch가 binary와 동시에 제공된다.
- 사용자는 offline에서도 license와 notices를 열 수 있다.
- .NET, Windows App Runtime, VC runtime의 source license와 binary terms를 구분해 기록했다.
- WiX를 포함한 build tool의 상업 사용 조건을 충족했다.
- plugin은 코어와 별도 installer·SBOM·notice·update 수명을 가진다.
- asset와 test corpus 권리도 code dependency와 같은 수준으로 추적된다.
- dependency 또는 license가 바뀌면 자동 diff가 release 승인을 다시 요구한다.

이 증거가 없으면 `오픈 소스 라이선스 문제 없음`이라고 보고하지 않는다.
