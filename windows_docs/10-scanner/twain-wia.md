# Windows 스캐너 어댑터 설계 — WIA 2.0, TWAIN, 보조 경로

기준일: 2026-08-04  
상태: 아키텍처 결정, 장치별 물리 검증 전  
대상: Windows 11 x64 및 ARM64  
관련 문서:

- [스캐너 플러그인 아키텍처](plugin-architecture.md)
- [스캐너 프로토콜 계약](protocol-contract.md)
- [플러그인 보안과 생명주기](plugin-security-and-lifecycle.md)
- [실물 하드웨어 검증 매트릭스](hardware-validation-matrix.md)
- [Scanning UI surface](../08-ui/surfaces/scanning.md)

## 1. 결정 요약

Windows판 Negaflow는 WIA와 TWAIN을 본체에 직접 링크하지 않는다. 각 기술을 별도의 native scanner
adapter executable로 감싸고, 본체와는 공통 JSON/NDJSON 프로토콜로만 통신한다.

```text
Negaflow.exe
    │
    │ versioned JSON request / NDJSON event / staged artifact
    │
    ├── negaflow-scanner-wia-{arch}.exe
    │       └── WIA 2.0 COM → WIA service → vendor minidriver
    │
    ├── negaflow-scanner-twain-x64.exe
    │       └── 64-bit DSM → 64-bit vendor Data Source
    │
    └── negaflow-scanner-twain-x86.exe
            └── 32-bit DSM → 32-bit vendor Data Source
```

현재 결정은 다음과 같다.

1. **WIA 2.0 COM을 Windows-native production baseline으로 삼는다.**
2. `Windows.Devices.Scanners`는 discovery spike 또는 제한된 fast path 후보이지, 필름 워크플로의 기본
   acquisition API가 아니다.
3. **TWAIN은 동등한 1급 adapter**이며, 특정 장치가 WIA보다 더 완전한 필름 기능과 픽셀 결과를 제공하면
   그 장치의 기본 route가 될 수 있다.
4. TWAIN은 x64와 x86 adapter를 분리한다. 한 프로세스에서 서로 다른 bitness의 Data Source를 load하지
   않는다.
5. WIA와 TWAIN 중 무엇이 더 좋다는 전역 우선순위를 만들지 않는다. **실제 장치와 실제 드라이버 버전의
   검증 결과**로 route를 선택한다.
6. 발견만 성공하거나 capability 이름만 존재하는 상태는 지원 완료가 아니다. 실제 artifact, 적용값,
   취소·복구, 반복성까지 통과해야 `Verified`다.

이 문서에서 말하는 baseline은 구현 순서와 기본 설계를 뜻한다. Epson, Plustek, Nikon 등 개별 모델의
Windows 지원을 아직 증명했다는 뜻이 아니다.

## 2. 근거와 사실 수준

### 2.1 주요 공식 근거

WIA:

- [WIA architecture overview](https://learn.microsoft.com/en-us/windows-hardware/drivers/image/wia-architecture-overview)
- [Windows Image Acquisition drivers](https://learn.microsoft.com/en-us/windows-hardware/drivers/image/windows-image-acquisition-drivers)
- [Basic scanning for film scanners](https://learn.microsoft.com/en-us/windows-hardware/drivers/image/basic-scanning-for-film-scanners)
- [WIA item tree](https://learn.microsoft.com/en-us/windows/win32/wia/-wia-item-tree)
- [IWiaDevMgr2](https://learn.microsoft.com/en-us/windows/win32/api/wia_xp/nn-wia_xp-iwiadevmgr2)
- [IWiaTransfer](https://learn.microsoft.com/en-us/windows/win32/api/wia_lh/nn-wia_lh-iwiatransfer)
- [IWiaTransferCallback](https://learn.microsoft.com/en-us/windows/win32/api/wia_lh/nn-wia_lh-iwiatransfercallback)
- [WIA transfer constants](https://learn.microsoft.com/en-us/windows-hardware/drivers/image/wia-transfer-constants)
- [WIA properties and property attributes](https://learn.microsoft.com/en-us/windows-hardware/drivers/image/wia-properties-and-property-attributes)
- [WIA RAW format specification](https://learn.microsoft.com/en-us/windows-hardware/drivers/image/wia-raw-format-specification)
- [WIA error handling architecture](https://learn.microsoft.com/en-us/windows-hardware/drivers/image/wia-error-handling-architecture)
- [Windows.Devices.Scanners](https://learn.microsoft.com/en-us/uwp/api/windows.devices.scanners)
- [Scan from your app](https://learn.microsoft.com/en-us/windows/apps/develop/devices-sensors/scan-from-your-app)

TWAIN:

- [TWAIN 2.5 specification](https://twain.org/wp-content/uploads/2021/11/TWAIN-2.5-Specification.pdf)
- [공식 TWAIN DSM 저장소](https://github.com/twain/twain-dsm)
- [TWAIN DSM 2.5.1 release](https://github.com/twain/twain-dsm/releases/tag/v2.5.1)
- [공식 `twain.h`](https://github.com/twain/twain-dsm/blob/master/TWAIN_DSM/src/twain.h)
- [TWAIN Working Group](https://twain.org/)

### 2.2 문서 사실과 제품 증거를 분리한다

각 결론은 다음 네 수준 중 하나로 취급한다.

| 수준 | 의미 | 제품에서 허용되는 표현 |
|---|---|---|
| 표준 정의 | 공식 문서에 property/capability가 정의됨 | “표준에 정의됨” |
| 드라이버 보고 | 설치된 드라이버가 값을 보고함 | “드라이버가 보고함” |
| 실제 적용 | 요청 뒤 read-back과 artifact가 일치함 | “이 드라이버에서 적용 확인” |
| 물리 검증 | 지정 장치·필름·포맷 매트릭스를 반복 통과함 | `Verified` |

예를 들어 WIA가 16-bit 관련 property를 정의하고 있어도 대상 드라이버가 16-bit/channel RGB artifact를
반환했다는 뜻은 아니다. TWAIN Data Source가 `ICAP_BITDEPTH=16`을 보고해도 결과 파일이 실제 16-bit이고
숨은 자동 보정이 없다는 뜻은 아니다.

## 3. 공통 프로세스 경계

### 3.1 본체가 직접 API를 호출하지 않는 이유

WIA service 자체가 out-of-process 구조이더라도 WIA adapter를 생략하지 않는다. WIA service는 vendor
minidriver와 장치 IO를 중개하지만, Negaflow가 요구하는 다음 책임까지 제공하지는 않는다.

- 공통 scanner protocol versioning
- capability 정규화와 거짓 capability 차단
- requested/applied option 증거
- artifact staging과 검증
- 일관된 timeout, cancellation, crash recovery
- scanner route별 diagnostics
- x86 TWAIN과 같은 생명주기 모델
- 본체 UI thread와 COM/DSM 제약 분리

TWAIN Data Source는 app process에 load될 수 있으므로 격리 필요성이 더 크다. 잘못된 vendor DS가 access
violation, message-loop deadlock 또는 무한 대기를 일으켜도 Negaflow 본체와 catalog가 함께 종료되어서는
안 된다.

### 3.2 공통 adapter 책임

WIA와 TWAIN adapter는 동일하게 다음 작업을 수행한다.

1. 자기 backend에서 장치를 발견한다.
2. raw backend identity를 stable normalized ID로 바꾼다.
3. 지원된 capability만 protocol schema로 변환한다.
4. 요청을 backend의 native property/capability로 변환한다.
5. backend가 실제로 수락한 값을 다시 읽는다.
6. acquisition event를 단조 증가 sequence의 NDJSON로 보낸다.
7. artifact를 request별 staging directory에 완성한다.
8. 크기, 포맷, geometry, bit depth, profile, checksum을 검증한다.
9. terminal event를 하나만 보낸다.
10. cancel 또는 failure 뒤 backend를 legal state로 되돌리고 임시 파일을 정리한다.

공통 wire의 정확한 필드와 terminal 규칙은 [스캐너 프로토콜 계약](protocol-contract.md)을 따른다.

### 3.3 backend 고유 상세를 본체에 누출하지 않는다

본체 UI는 `WIA_IPS_XRES`, `ICAP_XRESOLUTION`, `TW_FIX32`, COM HRESULT 같은 backend 세부를 직접 알지
않는다. adapter가 다음처럼 변환한다.

```text
backend property/capability
        ↓
normalized capability
        ↓
common scan request
        ↓
backend negotiation
        ↓
appliedOptions + artifact evidence
```

다만 Diagnostics에는 문제 재현을 위해 backend 이름, adapter version, driver identity, raw status code,
negotiated native values를 별도 evidence bundle로 남긴다. 사용자-facing 오류 문구와 진단 raw data는 분리한다.

## 4. WIA 2.0 경로

### 4.1 WIA 구조

WIA 2.0의 기본 관계는 다음과 같다.

```text
Negaflow WIA adapter
    └── WIA 2.0 COM interfaces
            └── WIA service process
                    └── vendor WIA minidriver
                            └── scanner
```

adapter는 `IWiaDevMgr2`를 통해 장치를 열고 `IWiaItem2` item tree를 탐색한다. root 아래에서 flatbed,
film, feeder 같은 programmable data source를 구분한다. 모델명 문자열만 보고 film source를 추측하지 않는다.

### 4.2 API 층 결정

#### Production baseline: WIA 2.0 COM

필름 스캔에 필요한 핵심은 단순 “스캔 시작”이 아니다.

- item tree와 `WIA_CATEGORY_FILM` 확인
- property type/list/range/step 조회
- 여러 property 설정 뒤 의존 속성 전체 read-back
- child frame 또는 positioned extent
- 16-bit, TIFF 또는 WIA RAW 협상
- stream transfer와 세밀한 progress/cancel
- 반환 header와 property의 실제값 비교

이 정보에 직접 접근하려면 WIA 2.0 COM이 기준 경로가 된다.

#### 제한 후보: `Windows.Devices.Scanners`

WinRT의 `Windows.Devices.Scanners`는 Windows desktop app에서도 사용할 수 있고 장치 열기, flatbed/feeder,
preview와 파일 스캔을 간단히 제공한다. 그러나 Negaflow의 기본 필름 계약에는 다음 공백이 있다.

- film item tree와 child frame의 완전한 노출 여부
- property 변경으로 함께 바뀐 실제값 전체 수집
- raw/16-bit/channel semantics 증명
- 반환 header 수준의 provenance
- vendor-specific film 기능

따라서 이 API는 다음 중 하나로만 사용한다.

- 장치 발견 및 빠른 호환성 spike
- full WIA COM route가 불필요한 문서형 scanner의 제한 경로
- 동일 artifact/applied-value 계약을 완전히 증명한 장치별 최적화

`ScanPreviewToStreamAsync`가 성공했다는 이유만으로 production film route를 승인하지 않는다.

### 4.3 COM apartment와 thread 소유권

WIA adapter는 backend 전용 owner thread를 둔다.

- thread 시작 시 COM apartment를 명시적으로 초기화한다.
- 장치 open, item tree, property storage, transfer object는 owner thread가 소유한다.
- raw COM interface pointer를 worker thread나 callback consumer에 넘기지 않는다.
- protocol stdin reader는 명령을 queue에 넣고 WIA API를 직접 부르지 않는다.
- transfer callback은 최소 정보만 thread-safe event queue에 복사한다.
- stdout NDJSON writer는 backend callback을 block하지 않는다.
- 종료 시 transfer → item → manager 순으로 deterministic release한다.

초기 구현은 한 adapter process당 한 active WIA session만 허용한다. 장치별 병렬 스캔은 실제 driver가
thread-safe하다고 검증되기 전에는 만들지 않는다.

### 4.4 발견과 장치 identity

발견 결과에는 최소 다음 raw 자료를 보존한다.

- WIA device ID 원문
- device type과 item category
- manufacturer, description, name
- driver version 또는 얻을 수 있는 PnP/driver package identity
- root item과 top-level programmable source 목록
- 연결 시점과 adapter architecture

표시 이름은 identity가 아니다. 같은 모델 두 대, USB 포트 변경, 드라이버 재설치가 있을 수 있다. common
device ID는 plugin ID, backend ID, raw device ID를 정규화해 구성하며, 서로 다른 WIA/TWAIN route를 한
물리 장치로 묶는 작업은 serial/PnP instance 등 검증 가능한 공통 근거가 있을 때만 수행한다.

### 4.5 film item 선택

공식 WIA film flow에 맞춘다.

1. top-level items를 열거한다.
2. `WiaItemTypeProgrammableDataSource`와 `WIA_CATEGORY_FILM`을 함께 확인한다.
3. `WIA_IPS_FILM_SCAN_MODE`의 valid values를 조회한다.
4. positive, color negative, B&W negative 등 실제 보고값만 노출한다.
5. `WIA_IPS_LAMP`가 있으면 현재 상태와 writable 여부를 확인한다.
6. format, transfer medium, datatype, depth, bits/channel을 협상한다.
7. existing child frames와 child creation support를 조사한다.
8. full film item, folder acquisition, 개별 child frame 중 실제로 안정적인 route를 선택한다.
9. transfer 뒤 반환 header와 갱신된 property를 읽는다.

flatbed transparency unit을 쓰는 장치가 `WIA_CATEGORY_FILM`을 제대로 제공하지 않을 수도 있다. 그런
장치를 모델명으로 film 지원 처리하지 않는다. 실제 flatbed item의 source/light/polarity extension과 artifact를
검증한 뒤 장치별 profile로만 허용한다.

### 4.6 property 협상은 트랜잭션처럼 다룬다

WIA property는 독립 변수가 아니다. 한 값을 쓰면 driver가 다른 값도 조정할 수 있다. 예를 들어 DPI를
바꾸면 origin/extent의 pixel 값이 바뀔 수 있고, extent를 바꾸면 page size가 custom으로 바뀔 수 있다.

따라서 단순한 `set A; set B; scan`을 금지하고 다음 순서를 사용한다.

```text
1. initial property snapshot
2. valid-values/type/access-right snapshot
3. source and film mode write
4. format/datatype/depth write
5. resolution write
6. dependent property set 전체 재조회
7. ROI를 현재 actual DPI 기준 pixel로 계산
8. page-size/origin/extent write
9. dependent property set 전체 재조회
10. request와 actual 비교
11. transfer
12. post-transfer property + returned header 재조회
13. appliedOptions 확정
```

`WriteMultiple` 성공은 모든 요청값이 그대로 유지됐다는 뜻이 아니다. property 쓰기 직후 다음 관련값을
일괄 재조회한다.

- source/item identity
- `WIA_IPS_FILM_SCAN_MODE`
- `WIA_IPA_FORMAT`, `WIA_IPA_TYMED`
- `WIA_IPA_DATATYPE`, `WIA_IPA_DEPTH`, `WIA_IPA_BITS_PER_CHANNEL`
- `WIA_IPS_XRES`, `WIA_IPS_YRES`
- `WIA_IPS_XPOS`, `WIA_IPS_YPOS`
- `WIA_IPS_XEXTENT`, `WIA_IPS_YEXTENT`
- `WIA_IPS_PAGE_SIZE`, `WIA_IPS_PAGE_WIDTH`, `WIA_IPS_PAGE_HEIGHT`
- pixels per line, bytes per line 등 지원되는 결과 shape 정보

### 4.7 WIA ROI 단위와 변환

단위 혼동은 프레임 일부 잘림을 만드는 치명적 오류다.

| property | 단위 | 의미 |
|---|---|---|
| `WIA_IPS_XRES`, `WIA_IPS_YRES` | pixels per inch | 선택 해상도 |
| `WIA_IPS_XPOS`, `WIA_IPS_YPOS` | pixels | 선택 영역 좌상단 |
| `WIA_IPS_XEXTENT`, `WIA_IPS_YEXTENT` | pixels | 선택 영역 폭과 높이 |
| `WIA_IPS_PAGE_WIDTH`, `WIA_IPS_PAGE_HEIGHT` | 1/1000 inch | 현재 physical page 크기 |

Negaflow protocol의 ROI는 물리 단위 millimeter를 canonical 값으로 유지한다. WIA에 쓸 pixel 좌표는
**driver가 실제 수락한 DPI**를 기준으로 계산한다.

```text
pixel = millimeter / 25.4 × actualDPI
millimeter = pixel / actualDPI × 25.4
pageThousandthsInch = millimeter / 25.4 × 1000
```

반올림 정책은 장치별로 임의 변경하지 않고 다음과 같이 고정한다.

- left/top origin은 requested 영역 바깥을 침범하지 않도록 장치 step에 맞춰 결정한다.
- right/bottom은 전체 필름 프레임을 잘라내지 않도록 extent를 보수적으로 확장하되 bed bounds를 넘지 않는다.
- driver range의 minimum, maximum, nominal, step을 모두 존중한다.
- X/Y DPI가 다르면 축별 actual DPI로 별도 계산한다.
- write 후 read-back된 pixel ROI를 다시 mm로 환산해 protocol의 `appliedOptions.areaMM`에 기록한다.

`WIA_IPS_PAGE_WIDTH/HEIGHT`는 1/1000 inch 단위의 cross-check다. pixel extent와 actual DPI로 환산한
physical size가 page property와 일치하지 않으면 driver inconsistency로 기록한다. 어느 하나를 조용히
정답으로 선택하지 않는다.

protocol v2가 현재 허용하는 1 mm 미만 높이 조정은 호환성 경계일 뿐, 모든 필름 포맷의 exact ROI 물리
검증 합격 기준이 아니다. 자세한 구분은 [하드웨어 검증 매트릭스](hardware-validation-matrix.md)를 따른다.

### 4.8 WIA capability mapping

| Negaflow capability | WIA 후보 | 승인에 필요한 증거 |
|---|---|---|
| source | item category와 item flags | item tree snapshot + 실제 transfer |
| resolution | `WIA_IPS_XRES/YRES` | valid set + read-back + header |
| optical resolution | `WIA_IPS_OPTICAL_XRES/YRES` | 정보용; selectable DPI와 혼동 금지 |
| area | `XPOS/YPOS/XEXTENT/YEXTENT` | pixel read-back + mm 역환산 + artifact geometry |
| physical page | `PAGE_WIDTH/HEIGHT` | 1/1000 inch 값과 extent cross-check |
| polarity | `WIA_IPS_FILM_SCAN_MODE` | valid list + transfer result |
| color/gray | `WIA_IPA_DATATYPE` | read-back + decoded channel model |
| channel depth | `WIA_IPA_BITS_PER_CHANNEL`, `WIA_IPA_DEPTH` | read-back + file/RAW header + decoded samples |
| format | `WIA_IPA_FORMAT` | actual format GUID + magic/header |
| medium | `WIA_IPA_TYMED` | stream/file negotiation evidence |
| preview | `WIA_IPS_PREVIEW` 또는 별도 preview operation | actual DPI/area/artifact |
| lamp | `WIA_IPS_LAMP` | property 존재·권한·상태 |
| brightness/contrast | standard scanner properties | type/range/step + actual 적용 |
| ICC reference | `WIA_IPA_COLOR_PROFILE`, `WIA_IPA_ICM_PROFILE_NAME` 후보 | 실제 profile bytes/hash와 provenance |

마지막 행의 profile property가 존재한다고 해서 해당 profile이 대상 film stock 또는 특정 scanner 상태에
정확하다는 뜻은 아니다. 파일을 얻었더라도 parse 가능성, hash, color space, 장치/driver provenance를
기록하고 measured accuracy는 별도 색 관리 검증으로만 주장한다.

### 4.9 transfer format 우선순위

필름 원본 acquisition의 우선순위는 다음과 같다.

1. 검증된 WIA RAW stream
2. 무손실 16-bit/channel TIFF
3. 무손실이면서 원래 sample semantics를 보존하는 다른 명시적 형식
4. 8-bit TIFF/PNG는 preview 또는 장치 제한 경로
5. JPEG/PDF/XPS는 verified film raw로 사용하지 않음

WIA RAW를 이름만 보고 sensor-native 데이터로 간주하지 않는다. 반환 header에서 최소 다음을 검증한다.

- tag/signature/version
- header size와 data offset
- X/Y resolution
- X/Y extent
- bytes per line
- bits per pixel
- channel count
- bits per channel
- compression
- photometric interpretation
- line order
- palette/profile/data block offset과 size
- 전체 stream 범위와 overflow

TIFF도 extension을 믿지 않는다. decoder로 IFD와 sample metadata를 읽고 `BitsPerSample`, `SamplesPerPixel`,
`SampleFormat`, `PhotometricInterpretation`, planar configuration, compression, dimensions, resolution tags,
embedded profile을 확인한다.

### 4.10 transfer, progress, cancel

WIA 2.0 stream transfer는 `IWiaTransfer::Download`와 `IWiaTransferCallback`을 사용한다.

callback 처리 원칙:

- `GetNextStream`은 request staging 아래의 새 파일 stream만 제공한다.
- callback이 전달한 status/progress/bytes를 common event로 정규화한다.
- progress는 단조 증가시키되 backend가 보고하지 않은 정밀도를 꾸며내지 않는다.
- callback에서 JSON 직렬화나 긴 파일 검증을 하지 않는다.
- callback payload pointer를 callback 수명 밖에서 보관하지 않는다.
- 새 page/stream은 요청이 허용한 artifact cardinality와 비교한다.

cancel은 두 route를 지원하되 한 번만 terminal 처리한다.

1. owner thread가 안전하게 실행할 수 있으면 `IWiaTransfer::Cancel`을 요청한다.
2. callback contract가 허용하는 경우 callback에서 cancellation result를 반환한다.
3. soft deadline 뒤에도 돌아오지 않으면 host가 adapter process를 Job Object 경계에서 종료한다.
4. staging file은 publish하지 않고 다음 실행의 orphan cleanup 대상으로 남긴다.

warm-up 또는 lamp 단계처럼 transfer callback 이전에 멈출 수 있는 구간도 별도 deadline이 필요하다.

### 4.11 preview 정책

Negaflow의 flatbed preview 목표는 300 DPI 또는 장치가 지원하는 가장 가까운 양의 DPI다. WinRT
`ScanPreviewToStreamAsync`는 선택 형식에서 낮은 해상도를 사용할 수 있으므로 이것만으로 300-DPI
계약을 만족할 수 없다.

정책:

- 명시적 DPI를 설정할 수 있는 full-scan artifact route를 preview에도 재사용한다.
- preview artifact는 ephemeral이며 catalog 원본으로 publish하지 않는다.
- requested preview DPI, actual DPI, full-bed area, pixel dimensions를 모두 기록한다.
- 장치가 native overview operation만 지원하면 실제 해상도와 제한을 capability에 표시한다.
- UI에 “300 DPI”를 표시하려면 actual read-back과 artifact header가 이를 증명해야 한다.

### 4.12 WIA 오류 정규화

WIA는 HRESULT, device status, transfer message, vendor error handling UI를 조합할 수 있다. headless adapter는
정상 route에서 vendor modal dialog에 의존하지 않는다.

다음 common status로 정규화한다.

| common status | WIA evidence 예시 |
|---|---|
| `deviceBusy` | 장치 사용 중 HRESULT/status |
| `deviceOffline` | 연결 끊김 또는 offline status |
| `warmingUp` | lamp/device status와 진행 상태 |
| `paperOrFilmJam` | media jam에 해당하는 driver status |
| `coverOpen` | cover-open status |
| `cancelled` | 사용자 cancel이 직접 원인인 종료 |
| `unsupportedOption` | property 부재, read-only, valid-set 밖 값 |
| `appliedMismatch` | 성공 반환 뒤 actual 값이 계약 허용 범위를 벗어남 |
| `invalidArtifact` | stream/header/decode/geometry 검증 실패 |
| `backendFailure` | 기타 HRESULT + 원문 진단 코드 |

vendor UI가 있어야만 복구 가능한 장치는 normal production route가 아니다. Diagnostics의 명시적
troubleshooting action에서만 vendor UI를 허용하는 별도 mode를 검토한다.

### 4.13 WIA의 알려진 리스크

- 대상 장치에 WIA driver가 없을 수 있다.
- vendor가 고급 필름 기능을 TWAIN에만 제공할 수 있다.
- 표준 property를 노출하지만 실제 적용하지 않을 수 있다.
- WIA service 또는 minidriver가 output을 색 변환하거나 보정할 수 있다.
- WIA RAW 이름과 실제 linear sensor semantics가 일치하지 않을 수 있다.
- IR, multi-exposure, analog exposure에는 portable standard mapping이 부족할 수 있다.
- Windows on ARM에서 native WIA driver가 없는 legacy USB 장치는 사용할 수 없을 수 있다.
- 드라이버 update로 property list나 quantization이 달라질 수 있다.

## 5. TWAIN 경로

### 5.1 TWAIN 구조와 DSM 버전 사실

```text
Negaflow TWAIN adapter
    └── DSM_Entry
            └── TWAIN Data Source Manager
                    └── vendor Data Source
                            └── scanner/driver stack
```

공식 DSM 저장소는 cross-platform 32-bit/64-bit 구현과 LGPL license를 명시한다. 2026-08-04 조사 시 공식
GitHub의 최신 표시는 **TWAIN DSM 2.5.1**이다. release note에 따르면 2.5.0 이후 code change나 binary
recompile은 없고 Windows binary의 file/product version과 copyright를 갱신하고 SHA-512/RSA-4096
certificate로 재서명했다. 공개 페이지가 월·일만 표시하므로 이 문서에서는 release year를 추측하지 않는다.

이 사실은 Negaflow가 곧바로 DSM binary를 번들할 수 있다는 뜻이 아니다. 정확한 배포 artifact, license,
notice, source-offer 의무, signature 검증은 release 후보 version을 고정한 뒤 별도 legal/package gate에서
확인한다.

### 5.2 bitness는 별도 프로세스로 해결한다

64-bit process는 32-bit Data Source DLL을 직접 load할 수 없다. 따라서 다음 adapter를 분리한다.

| adapter | process architecture | 허용 DSM/DS | 주 용도 |
|---|---:|---|---|
| `twain-x64` | x64 | x64 DSM + x64 DS | 현재 64-bit vendor route |
| `twain-x86` | x86 | x86 DSM + x86 DS | legacy 32-bit Data Source |
| `twain-arm64` | ARM64 | 실제 ARM64 DSM + ARM64 DS | 공급·검증될 때만 |

x64와 x86 adapter는 별도 executable, manifest, approval hash, crash history, update unit이다. x86 adapter가
x64 adapter의 DLL search path를 공유하지 않게 한다.

Windows ARM64의 x64/x86 app emulation이 존재하더라도 USB scanner driver와 vendor DS 전체가 동작한다는
보장은 없다. ARM64 검증은 다음 조합별로 분리한다.

- native ARM64 adapter + native ARM64 DSM/DS/driver
- emulated x64 adapter + x64 DSM/DS + 호환 driver stack
- emulated x86 adapter + x86 DSM/DS + 호환 driver stack

단순히 adapter process가 launch된 결과를 scanner 지원으로 기록하지 않는다.

### 5.3 TWAIN 상태 머신

TWAIN 2.5의 상태를 adapter owner가 명시적으로 추적한다.

| 상태 | 의미 | 주요 작업 |
|---:|---|---|
| 1 | Pre-Session | DSM 미로드 |
| 2 | DSM Loaded | DSM entry 확보 |
| 3 | DSM Open | source 열거/선택 |
| 4 | Source Open | capability negotiation |
| 5 | Source Enabled | source가 acquisition 준비 |
| 6 | Transfer Ready | transfer-ready event 수신 |
| 7 | Transferring | image data transfer |

정상 흐름:

```text
1 → 2 → 3 → 4 → 5 → 6 → 7 → 6/5 → 4 → 3 → 2 → 1
```

모든 DSM/DS operation 전에 현재 state에서 legal한 triplet인지 검사한다. failure/cancel도 “close 함수를 전부
한번 호출”하는 식으로 처리하지 않고 현재 state에서 허용되는 역방향 순서로 unwind한다.

adapter crash diagnostic에는 다음을 기록한다.

- 마지막 확정 state
- 마지막 보낸 DG/DAT/MSG triplet
- DSM return code와 condition code
- source identity와 bitness
- UI enable 상태
- pending transfer count
- cancel requested 시각과 deadline

### 5.4 owner thread와 Windows message loop

TWAIN Data Source는 thread affinity와 Windows message delivery를 기대할 수 있다. adapter는 DSM/DS 전용
owner thread를 만들고 그 thread에서 message loop를 유지한다.

- DSM load/open/source open/enable/transfer/disable/close는 owner thread에서만 수행한다.
- source enable 전에 message-only 또는 숨은 owner window를 준비한다.
- normal Windows messages를 pump하고 TWAIN event processing 결과를 해석한다.
- `MSG_XFERREADY`, `MSG_CLOSEDSREQ`, `MSG_CLOSEDSOK`, device event를 state queue로 보낸다.
- stdin cancel reader는 atomic flag와 owner-thread message만 게시한다.
- cancellation thread가 직접 `DSM_Entry`를 호출하지 않는다.
- vendor callback에서 stdout write, file hashing, image decode를 수행하지 않는다.

message pumping을 background pool task 하나로 대체하지 않는다. DS별 재진입 제약을 모르는 상태에서 병렬
capability query나 transfer를 만들지 않는다.

### 5.5 capability container를 정확히 파싱한다

TWAIN capability는 단일 숫자만 반환하지 않는다. 공식 header가 정의하는 container 유형을 모두 고려한다.

- `TWON_ONEVALUE`
- `TWON_RANGE`
- `TWON_ENUMERATION`
- `TWON_ARRAY`

각 container에서 다음을 검증한다.

- handle lock 성공 여부와 byte 범위
- item type
- item count와 overflow
- current/default index 범위
- range의 min/max/step/default/current
- `TW_FIX32`의 부호, whole/fraction 변환
- capability가 선언한 unit
- 중복·비정상·음수 값
- container unlock/free ownership

range를 받았다고 모든 중간 값을 무조건 UI에 노출하지 않는다. step이 유효한지 확인하고, 후보 DPI는 실제
set/get/reset probe와 physical scan으로 확정한다.

### 5.6 capability mapping

| Negaflow capability | TWAIN 후보 | 필수 검증 |
|---|---|---|
| X/Y resolution | `ICAP_XRESOLUTION`, `ICAP_YRESOLUTION` | container + set/get + artifact |
| unit | `ICAP_UNITS` | inch/mm/pixel 해석 고정 |
| pixel type | `ICAP_PIXELTYPE` | current/support + decoded channels |
| bit depth | `ICAP_BITDEPTH` | current/support + sample metadata |
| bit order/flavor | 관련 image capability | artifact polarity와 함께 검증 |
| physical size | `ICAP_PHYSICALWIDTH/HEIGHT` | unit 변환 + layout bounds |
| scan area | `DAT_IMAGELAYOUT` | set/get + frame + artifact dimensions |
| transfer mechanism | `ICAP_XFERMECH` | supported/current + 실제 transfer |
| file format | `ICAP_IMAGEFILEFORMAT` | format magic/header |
| headless UI | `CAP_UICONTROLLABLE` + `TW_USERINTERFACE` | `ShowUI=FALSE` 실제 scan |
| indicators | `CAP_INDICATORS` | 숨은 modal/progress UI 부재 |
| online | `CAP_DEVICEONLINE` | 실제 open/scan과 별도 취급 |

IR, multi-exposure, analog exposure, holder type, focus, calibration, hardware dust removal은 이름이 비슷한
capability를 추측해 공통 필드에 연결하지 않는다. vendor Data Source가 명시적으로 보고하고, type/unit과
실제 acquisition을 장치별로 검증하고, extension version을 고정했을 때만 adapter extension으로 노출한다.

### 5.7 source 선택과 stable identity

production scan에서는 vendor source-selection modal dialog를 사용하지 않는다. adapter가 DSM을 통해 source
목록과 identity를 읽고, host가 전달한 backend device ID와 정확히 일치하는 source를 연다.

기록 대상:

- manufacturer/product family/product name
- protocol major/minor와 supported groups
- Data Source path/hash/signature를 얻을 수 있는 경우 그 값
- DSM version, architecture, path/hash
- adapter architecture
- OS와 driver package identity

display name 충돌을 허용하되 display name만으로 자동 연결하지 않는다.

### 5.8 headless UI 계약

Negaflow의 기본 scanning surface가 capability-driven이므로 normal route는 다음을 만족해야 한다.

- `TW_USERINTERFACE.ShowUI = FALSE`
- app이 제공한 owner window handle 사용
- `CAP_UICONTROLLABLE`과 실제 동작 일치
- 설정/scan/cancel 중 예상치 못한 modal window 없음
- indicator를 끌 수 있다고 보고하면 실제로 숨겨짐
- source가 UI 없이도 capability를 적용하고 transfer-ready로 진행함

`CAP_UICONTROLLABLE`이 false이거나 DS가 실제로 modal UI를 강제하면 다음 중 하나다.

1. 해당 route를 `Experimental`로 낮춘다.
2. Diagnostics의 명시적 “vendor UI로 스캔” 제한 기능으로 격리한다.
3. WIA route가 계약을 만족하면 WIA를 기본으로 선택한다.

vendor UI에서 사용자가 임의 설정한 뒤 결과만 받는 흐름은 reproducible `appliedOptions`를 보장하지 못하므로
기본 비파괴 workflow와 동일하게 취급하지 않는다.

### 5.9 TWAIN ROI와 단위

ROI는 `ICAP_UNITS`와 `DAT_IMAGELAYOUT`의 `TW_FRAME`을 함께 다룬다. `TW_FIX32` 값을 double로 변환할 때
부호와 fractional part를 정확히 보존한다.

정책:

1. source open 직후 supported unit을 읽는다.
2. 가능하면 inches 또는 stable physical unit을 명시적으로 선택한다.
3. physical bounds를 read-back한다.
4. protocol의 mm ROI를 selected TWAIN unit으로 변환한다.
5. frame을 set한다.
6. frame을 get해 actual layout을 읽는다.
7. actual frame을 mm로 역변환한다.
8. transfer artifact dimensions와 actual resolution을 대조한다.

pixel unit만 가능한 DS는 resolution 변경과 ROI의 상호작용을 WIA와 동일하게 별도 검증한다. unit이 바뀌었는데
이전 frame 값을 재사용하지 않는다.

### 5.10 transfer mechanism 선택

필름 acquisition의 기본 선호는 다음과 같다.

#### 1순위: memory transfer

- large/high-bit data를 adapter가 직접 staging stream에 쓸 수 있다.
- strip/chunk 크기와 전체 byte count를 검증할 수 있다.
- vendor가 임의 output path를 선택하지 않는다.
- transfer progress와 cancellation을 common protocol에 연결하기 쉽다.

각 memory block에서 row/column/bytes-written 정보를 overflow-safe하게 검증하고, incomplete row나 geometry
불일치를 즉시 failure로 처리한다.

#### 2순위: file transfer

다음 조건을 모두 만족할 때만 사용한다.

- 무손실 TIFF 또는 검증된 raw-like format
- app-controlled staging path 사용 가능
- actual format과 bit depth read-back
- transfer 완료 뒤 header/decode 검증
- 숨은 JPEG 또는 8-bit 변환 없음

#### 제한 경로: native transfer

Windows native/DIB transfer는 preview 또는 8-bit 호환 경로에만 검토한다. 소유권, 메모리 크기, DIB
orientation과 sample depth를 명확히 검증하지 못하면 16-bit film raw route로 승인하지 않는다.

어떤 mechanism이든 `ICAP_XFERMECH`을 set한 뒤 current value를 다시 읽고, 실제 callback/triplet이 선택한
mechanism과 일치하는지 기록한다.

### 5.11 transfer cardinality와 pending count

단일 scan request가 몇 개의 image를 반환할지 명시한다.

- RGB only: RGB artifact 정확히 1개
- RGB+IR separate: RGB와 IR artifact 각각 정확히 1개
- batch/frame request: manifest가 허용한 frame 수와 순서

각 transfer 뒤 pending-transfer count를 읽고 다음 동작을 결정한다. 예상보다 많은 image가 남았다고 조용히
버리거나, 예상보다 적은데 성공 처리하지 않는다. reset/end-xfer operation도 현재 state와 pending count에
맞춰 호출한다.

### 5.12 cancel과 legal unwind

cancel 요청은 owner thread event로 전달한다. owner는 현재 상태에 따라 다음처럼 처리한다.

```text
State 7: 현재 transfer abort/reset → pending 정리
State 6: pending transfer reset/end → State 5
State 5: source disable → State 4
State 4: source close → State 3
State 3: DSM close → State 2
State 2: DSM unload → State 1
```

실제 operation과 condition은 TWAIN spec에서 허용된 triplet을 따른다. 이 표는 목표 상태를 설명하는 것이며
모든 DS에 같은 호출을 무조건 던지라는 뜻이 아니다.

soft cancel deadline 안에 owner thread가 돌아오지 않으면 host가 adapter process를 종료한다. 강제 종료 뒤
artifact는 incomplete로 간주하고 publish하지 않는다. 다음 실행에서 같은 DS가 정상적으로 reopen되는지
복구 test를 수행한다.

### 5.13 TWAIN 오류 정규화

DSM return code와 `DAT_STATUS` condition code를 함께 보존한다.

- success/check-status를 구분한다.
- failure 뒤 condition code 조회 자체가 실패할 수 있음을 기록한다.
- sequence error는 adapter state bug 또는 DS deviation으로 별도 분류한다.
- low-memory, bad-value, capability unsupported, device busy/offline을 common status로 mapping한다.
- vendor numeric code와 원문 identity는 diagnostics에 남긴다.
- 사용자-facing 오류에는 재시도 가능 여부와 다음 조치만 간결히 보여준다.

unknown code를 `deviceOffline` 같은 친숙한 오류로 추측 변환하지 않는다.

### 5.14 TWAIN의 알려진 리스크

- vendor DS가 state machine을 불완전하게 구현할 수 있다.
- UI를 숨긴다고 보고해도 modal window를 만들 수 있다.
- capability가 과장되거나 set/get이 불일치할 수 있다.
- x86 legacy DS가 최신 Windows 보안/ARM64 환경에서 불안정할 수 있다.
- memory transfer의 row/stride semantics가 driver마다 흔들릴 수 있다.
- cancel/close가 hardware warm-up이나 USB IO에서 멈출 수 있다.
- vendor DS와 DSM의 DLL search/load behavior가 packaging에 영향을 줄 수 있다.
- standard capability만으로 IR과 multi-exposure를 일반화하기 어렵다.

## 6. WIA와 TWAIN route를 같은 기준으로 비교한다

### 6.1 전역 순위가 아니라 device-route record

같은 물리 장치가 WIA와 TWAIN에 나타나면 route별 record를 만든다.

```text
physical device candidate
    ├── WIA route record
    └── TWAIN x64/x86 route record
```

각 record는 다음 key를 가진다.

- scanner model과 stable hardware identity evidence
- backend와 adapter version
- driver/DS/DSM version 및 architecture
- capability snapshot hash
- test matrix revision
- verified OS build와 architecture
- last successful physical validation date
- known failures와 required workaround

두 route가 같은 물리 장치라는 확실한 근거가 없으면 자동 병합하지 않는다.

### 6.2 route 점수 순서

기본 route를 고를 때 성능보다 정확성과 복구를 먼저 본다.

1. artifact와 applied-option contract 완전성
2. 16-bit RGB, ROI, polarity, preview 등 필수 필름 기능
3. IR/multi-exposure 등 장치 고유 필수 기능
4. 숨은 보정 없는 픽셀 결과
5. cancel, timeout, disconnect, reopen 안정성
6. 반복 scan geometry와 sample consistency
7. native architecture와 설치 복잡도
8. open/scan latency와 throughput

한 route가 더 빠르더라도 bit depth 또는 ROI를 거짓 보고하면 선택하지 않는다.

### 6.3 UI 노출

일반 사용자에게 WIA/TWAIN이라는 backend 용어를 기본 scanner picker에 강조하지 않는다.

- 같은 장치의 검증된 기본 route를 자동 선택한다.
- alternate route는 Diagnostics 또는 advanced troubleshooting에 둔다.
- route 변경 시 capability와 현재 설정을 다시 로드한다.
- 이전 route의 unsupported 설정을 새 route에 조용히 전달하지 않는다.
- 오류 메시지는 “WIA 오류”보다 사용자가 취할 조치를 우선한다.

Diagnostics에는 `Connection route`, adapter version, architecture, driver identity, capability hash,
applied-options summary를 표시한다.

## 7. WIA/TWAIN 공통 capability 승인 규칙

### 7.1 resolution

- 0 이하 값은 폐기한다.
- list/range/enum type을 보존한다.
- 300-DPI preview는 nearest supported positive DPI 정책을 쓴다.
- X/Y 값이 다르면 UI와 geometry 계산에 그대로 반영한다.
- advertised maximum을 optical resolution이라고 자동 표시하지 않는다.
- actual header와 read-back이 불일치하면 route failure다.

### 7.2 bit depth

- “48-bit color” 문자열을 16-bit/channel 증거로 쓰지 않는다.
- property/capability current value를 읽는다.
- decoded sample storage와 file header를 확인한다.
- 값 범위와 실제 유효 sample bits를 test target으로 검사한다.
- 16-bit request가 8-bit artifact가 되면 자동 fallback하지 않고 명시적으로 실패한다.

### 7.3 polarity와 색 변환

- positive/negative mode가 acquisition light-source 선택인지 단순 software inversion인지 구분한다.
- driver auto color, sharpening, dust removal, exposure correction을 끌 수 있는지 확인한다.
- 끌 수 없는 보정은 capability/route limitation으로 기록한다.
- negative artifact를 positive로 바꿔 반환하면 raw workflow와 호환되는지 별도 판단한다.

### 7.4 scan area

- canonical 단위는 mm다.
- backend native unit과 quantization을 명시한다.
- requested → backend request → read-back → header → decoded geometry를 연결한다.
- full-bed와 모든 지원 film format의 경계 잘림을 확인한다.
- width만 맞고 height가 다른 결과를 성공으로 처리하지 않는다.

### 7.5 IR

- IR capability가 없으면 UI에 표시하지 않는다.
- RGB와 IR이 같은 physical scan session인지 provenance를 기록한다.
- width, height, ROI, orientation, alignment를 대조한다.
- IR artifact가 RGB-derived heuristic이면 hardware IR로 표시하지 않는다.
- backend vendor extension은 versioned mapping과 fixture가 있어야 한다.

## 8. 보조 scanner 기술

### 8.1 eSCL/AirScan

network document scanner용 별도 adapter 후보로 둔다. HTTP/XML이라는 이유로 본체에 직접 구현하지 않는다.
대상 film scanner가 실제 eSCL에서 16-bit, transparency source, 정확한 ROI를 제공한다는 증거가 없으므로 초기
film migration의 우선순위는 낮다.

### 8.2 WSD-WIA

Windows의 WSD-WIA class driver를 통해 보이는 network device는 host 입장에서 WIA route다. raw device가
WSD라는 사실을 diagnostics에 기록할 수 있지만, capability는 WIA adapter가 실제 보고한 값만 사용한다.

### 8.3 TWAIN Direct

TWAIN Direct는 별도 장치/bridge 경로로 평가한다. 문서 스캔 중심 PDF/R workflow가 Negaflow의 16-bit film
TIFF, IR, exact ROI 요구를 만족한다고 가정하지 않는다. badge나 protocol 지원 주장보다 실제 artifact를
우선한다.

### 8.4 vendor SDK

WIA/TWAIN으로 필수 기능을 얻을 수 없을 때만 별도 adapter 후보로 검토한다.

- SDK license와 redistribution 권한
- 지원 OS/architecture
- static/dynamic linking 조건
- source code/header provenance
- vendor runtime 설치와 update ownership
- process crash와 timeout 처리 가능성

SDK를 쓰더라도 common scanner protocol과 out-of-process boundary는 유지한다.

## 9. 장치별 물리 검증

상세 evidence bundle은 [실물 하드웨어 검증 매트릭스](hardware-validation-matrix.md)를 따른다. 이 문서에서
route 비교에 필요한 핵심 gate만 요약한다.

### 9.1 Gate A — 설치, 발견, open

- clean Windows 11 x64/ARM64 설치
- vendor driver source와 version 기록
- non-admin Negaflow 실행
- device identity 안정성
- 첫 open, 두 번째 open, reboot 후 open
- vendor app과 동시 사용 시 busy 처리
- unplug/replug와 port 변경

### 9.2 Gate B — capability truth

- item/source 목록
- positive exact DPI
- 8/16-bit per channel
- color/gray와 polarity
- physical bounds와 positioned area
- preview actual DPI
- IR, multi-exposure, analog exposure
- output format와 ICC/provenance
- unsupported control이 UI에서 숨겨지는지

### 9.3 Gate C — acquisition matrix

- 35 mm full frame
- 35 mm square
- 35 mm half frame
- 120 6×4.5
- 120 6×6
- 120 6×7
- 120 6×8
- 120 6×9
- 120 6×12
- 120 6×17
- full-bed preview at 300 DPI 또는 nearest supported DPI
- manual ROI와 automatic detected ROI
- RGB와, 지원 시 IR

모든 case에서 `detected ROI = requested full-scan ROI = verified applied/manifest ROI` 사슬을 확인한다.

### 9.4 Gate D — artifact

- magic/header와 declared format 일치
- dimensions와 stride
- bits/sample와 channels
- compression과 sample format
- orientation/line order
- resolution metadata
- ICC parse와 hash
- RGB/IR geometry
- file size와 checksum
- staging에서 atomic publish

### 9.5 Gate E — resilience

- open 중 cancel
- lamp warm-up 중 cancel
- RGB scan 중 cancel
- IR scan 중 cancel
- transfer 중 cancel
- adapter 강제 종료 뒤 reopen
- USB disconnect와 reconnect
- host crash 뒤 orphan staging 정리
- 12-frame batch
- 50-cycle open/scan/close

### 9.6 Gate F — 픽셀 품질

- 같은 target/film의 route별 paired scan
- clipping과 channel histogram
- unwanted auto correction
- sharpening/noise reduction
- effective bit depth
- geometry와 alignment
- repeatability
- color profile 유무와 적용 책임

이 gate는 “더 보기 좋은” 결과를 고르는 과정이 아니다. 비파괴 develop pipeline에 들어갈 재현 가능한
acquisition을 찾는 과정이다.

## 10. route 상태와 제품 표현

| 상태 | 최소 증거 | UI 처리 |
|---|---|---|
| `Verified` | 지정 장치/driver/OS/arch에서 전체 필수 gate 물리 통과 | 기본 route 후보 |
| `Compatible Target` | protocol/capability와 일부 실제 scan 통과, matrix 미완료 | 제한 명시 |
| `Experimental` | 기능 결손, UI 의존 또는 복구 불안정 | advanced opt-in |
| `Unsupported` | artifact/provenance/필수 기능 계약 위반 | 일반 UI에서 숨김 |

다음 표현을 금지한다.

- USB에서 보였으므로 지원됨
- WIA/TWAIN source 목록에 있으므로 지원됨
- capability가 있으므로 16-bit/IR 지원됨
- sample scan 한 장 성공으로 모든 포맷 지원됨
- x64에서 성공했으므로 ARM64도 지원됨
- process를 분리했으므로 license 문제가 해결됨

## 11. 배포와 라이선스

### 11.1 WIA

- Windows system WIA API 사용과 vendor driver 재배포 권한은 별개다.
- Negaflow installer는 vendor driver를 허가 없이 포함하지 않는다.
- 사용자가 공식 vendor package를 설치하도록 안내한다.
- driver download URL, checksum, silent install을 임의 자동화하지 않는다.
- 특정 minidriver binary를 복사해 app-private로 load하지 않는다.

### 11.2 TWAIN DSM

- 선택한 DSM version의 license text와 binary provenance를 고정한다.
- LGPL 의무와 수정 여부를 release별로 검토한다.
- official signature와 package hash를 검증한다.
- x86/x64 artifact를 architecture별 inventory에 기록한다.
- system DSM을 사용할지 app-local DSM을 사용할지 DLL search와 servicing 관점에서 결정한다.
- app-local 배포 시 replacement/notice/source 접근 요구를 legal review한다.

### 11.3 vendor Data Source

- vendor DS는 보통 vendor installer가 소유한다.
- Negaflow가 DS DLL을 추출하거나 재배포하지 않는다.
- vendor SDK와 installed DS를 구분한다.
- driver uninstall/update 뒤 stale route approval을 무효화한다.
- DS version 변경 시 capability snapshot과 physical certification을 재평가한다.

### 11.4 프로세스 분리의 한계

별도 process는 crash, bitness, 업데이트, dependency 경계를 명확히 하지만 법률 판단을 자동으로 끝내지
않는다. 프로그램 결합 방식, 배포 묶음, 통신 계약, derivative-work 여부, notice와 source 의무는 각각
검토해야 한다. 최종 배포 판단은 release 시점의 정확한 artifact를 대상으로 한다.

## 12. 구현 순서

### Phase 1 — read-only inventory tools

1. WIA 장치와 item tree dump
2. property ID/type/access/list/range dump
3. TWAIN x64 source와 capability container dump
4. 필요 대상 장치에 한해 TWAIN x86 dump
5. adapter/driver/DSM/DS provenance bundle

이 단계에서 UI나 지원 주장부터 만들지 않는다.

### Phase 2 — WIA baseline acquisition

1. owner thread와 COM lifetime
2. `WIA_CATEGORY_FILM`/flatbed source 선택
3. dependency-aware property transaction
4. 300-DPI explicit preview
5. positioned 16-bit TIFF 또는 WIA RAW
6. callback progress와 cancel
7. post-transfer header/property evidence
8. common protocol v2 terminal handling

### Phase 3 — TWAIN acquisition

1. x64 DSM/source lifecycle와 message loop
2. capability container parser
3. `ShowUI=FALSE` scan
4. image layout set/get
5. memory transfer
6. transfer pending/reset/cancel
7. artifact validation
8. x86 helper와 동일 fixture suite

### Phase 4 — route comparison

1. 동일 장치·필름·설정으로 paired scans
2. capability/applied/artifact 비교
3. cancel/recovery 반복
4. route status 결정
5. device-route registry와 diagnostics
6. alternate-route UI

### Phase 5 — 대상 장치 확대

한 모델 성공 뒤 일반화하지 않는다. 각 모델, driver version, architecture에 대해 물리 matrix를 다시 수행한다.

## 13. 자동 테스트 설계

### 13.1 WIA property fixtures

- single/list/range values
- read-only와 write-only 오보고
- DPI 변경 뒤 extent 갱신
- extent 변경 뒤 page size custom 전환
- X/Y DPI 불일치
- invalid step과 reversed bounds
- film child frames
- requested 16-bit → actual 8-bit mismatch
- format GUID와 artifact magic mismatch

### 13.2 WIA transfer fixtures

- 정상 single stream
- callback progress non-monotonic input
- multiple unexpected streams
- truncated WIA RAW header
- offset/size integer overflow
- invalid bytes-per-line
- cancel before first callback
- cancel during stream write
- success HRESULT + corrupt artifact

### 13.3 TWAIN container fixtures

- ONEVALUE, RANGE, ENUMERATION, ARRAY
- invalid current/default index
- huge item count
- malformed item type
- negative `TW_FIX32`
- zero/negative range step
- duplicate DPI
- capability success 뒤 get-current mismatch
- handle lock/free failure injection

### 13.4 TWAIN state fixtures

- 정상 1→7→1 cycle
- source open failure
- sequence error
- unexpected `MSG_CLOSEDSREQ`
- transfer-ready 없이 timeout
- pending count mismatch
- cancel at states 4, 5, 6, 7
- DS close hang와 forced process termination
- 다음 process에서 reopen

### 13.5 공통 contract fixtures

- request ID mismatch
- non-increasing sequence
- duplicate terminal event
- terminal 뒤 추가 event
- appliedOptions 필수 key 누락
- artifact path staging root 탈출
- symlink/reparse target
- checksum mismatch
- RGB/IR geometry mismatch
- adapter stdout에 비-JSON 오염

자동 fixture는 backend wrapper의 안전성과 contract를 증명한다. 실물 scanner의 광학, driver 적용, USB 안정성을
대신하지 않는다.

## 14. 관측성과 진단 bundle

장치별 실패를 재현하려면 다음 정보를 하나의 redact 가능한 bundle로 내보낸다.

- OS edition/build와 CPU architecture
- Negaflow/adapter/protocol version
- adapter executable hash/signature
- backend route와 process bitness
- device identity의 비민감 부분
- driver package/DSM/DS version
- raw capability/property snapshot
- normalized capability snapshot
- request와 appliedOptions
- event timeline과 timeout phase
- raw HRESULT 또는 DSM/condition code
- artifact metadata와 checksum
- crash dump 존재 여부와 consent 상태

사용자 파일 경로, 계정명, serial number 등 민감할 수 있는 값은 기본 export에서 마스킹한다. 원본 필름
artifact 자체는 명시적 사용자 선택 없이 support bundle에 포함하지 않는다.

## 15. 성능 기준

route 승인에서 성능은 정확성 다음이다. 그래도 다음을 측정한다.

- cold/warm discovery latency
- first/second open latency
- lamp warm-up time
- time to first progress
- transfer throughput
- artifact validation 시간
- adapter private working set
- cancel request부터 process 종료까지 시간
- 12-frame batch의 평균과 p95
- WIA vs TWAIN paired total time

scanner hardware 속도와 adapter overhead를 분리한다. scan이 진행되는 동안 CPU 사용량이 낮다고 adapter가
효율적이라는 뜻은 아니며, 반대로 TIFF hashing/validation CPU를 줄이기 위해 증거를 생략하지 않는다.

## 16. 현재 열린 질문

물리 장치 없이는 다음을 확정하지 않는다.

- 대상 Epson/Plustek/Nikon Windows driver가 WIA와 TWAIN 각각 어떤 source를 제공하는가
- WIA film item이 실제 16-bit/channel RGB와 negative mode를 제공하는가
- WIA RAW/TIFF 결과가 linear인지, driver color correction을 우회할 수 있는가
- WIA의 child frame geometry가 holder 위치와 정확히 대응하는가
- 대상 TWAIN DS가 `ShowUI=FALSE`를 안정적으로 지원하는가
- TWAIN memory transfer가 16-bit sample을 손실 없이 반환하는가
- IR이 WIA/TWAIN에서 별도 image, channel, file 또는 vendor extension 중 무엇으로 노출되는가
- multi-exposure와 analog exposure가 재현 가능하게 제어되는가
- ARM64 Windows에서 대상 vendor USB driver와 x64/x86 DS가 실제 작동하는가
- DSM app-local 배포와 system 설치 중 어느 쪽이 servicing과 license에 적합한가
- 동일 물리 장치의 WIA/TWAIN identity를 안전하게 병합할 공통 key가 있는가
- driver update 뒤 certification invalidation 범위를 어디까지 둘 것인가

## 17. 완료 기준

이 설계의 구현 완료는 adapter executable이 빌드되는 시점이 아니다. 최소 다음이 충족되어야 한다.

- WIA COM baseline이 protocol v2 contract를 완전히 구현한다.
- TWAIN x64와 필요한 x86 route가 같은 host contract를 구현한다.
- requested/applied/header/artifact 값이 연결된다.
- timeout, cancel, crash, disconnect 뒤 본체와 catalog가 안전하다.
- 지원 UI는 실제 capability만 노출한다.
- 장치별 route가 evidence 수준과 함께 기록된다.
- x64와 ARM64가 별도로 검증된다.
- installer가 adapter/DSM/vendor component의 소유권과 license를 분리한다.
- 전체 필름 포맷 matrix가 대상 실물 장치에서 통과한다.

그 전까지 WIA와 TWAIN은 **구현 가능한 adapter 설계**이며, 특정 scanner의 검증된 Windows 지원을 의미하지
않는다.
