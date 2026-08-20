# Windows scanner 실기 검증 매트릭스

기준일: 2026-08-04  
상태: physical QA 실행 명세  
목적: “장치가 보인다”와 “Negaflow film scan workflow를 지원한다”를 분리

관련 문서:

- [plugin architecture](plugin-architecture.md)
- [protocol contract](protocol-contract.md)
- [WIA and TWAIN adapters](twain-wia.md)
- [scanning surface](../08-ui/surfaces/scanning.md)

코드 근거:

- `Sources/Chromabase/Imaging/FlatbedFrameDetector.swift`
- `Sources/negaflowApp/Features/Scanning/Runtime/AppModel+FlatbedScanning.swift`
- `Sources/negaflowApp/Features/Scanning/Runtime/AppModel+ScannerCapabilityLoading.swift`
- `Sources/negaflowApp/Features/Scanning/WorkflowPersistence/AppModel+FullScanOrchestration.swift`
- `Tests/ChromabaseTests/FlatbedFrameDetectorTests.swift`
- `Tests/negaflowAppTests/FlatbedScanRegionTests.swift`
- `Tests/negaflowAppTests/ScannerWorkflowSafetyTests.swift`

## 1. 결론

Windows scanner 지원 표시는 다음 단계를 모두 통과한 **정확한 조합**에만 붙입니다.

```text
scanner hardware
+ firmware
+ Windows build
+ CPU architecture
+ vendor driver package/version
+ adapter kind/version/architecture
+ connection path
+ requested format/options
```

같은 marketing model name이라도 USB product ID, hardware revision, firmware, driver bitness가 다르면
별도 row입니다.

USB Device Manager에서 보이는 것, WIA/TWAIN enumeration, capability query, preview, full scan,
pixel/ROI/provenance validation은 서로 다른 증거입니다.

## 2. 증거 등급

| 등급 | 증거 | 허용 표현 |
|---|---|---|
| E0 | vendor 문서/광고 | 조사 대상 |
| E1 | USB/PnP enumeration | OS가 장치를 봄 |
| E2 | WIA item 또는 TWAIN DS enumeration | adapter 후보가 장치를 나열함 |
| E3 | capability dump | driver가 값을 보고함 |
| E4 | preview artifact | preview route가 실제 pixel을 반환함 |
| E5 | full-scan artifact + applied evidence | 특정 option/ROI로 획득됨 |
| E6 | 전체 format/quality/recovery matrix 반복 통과 | 해당 조합 verified |

`verifiedStatus = verified`는 E6에만 사용합니다. E2/E3은 `compatibleTarget` 또는
`experimental`입니다.

## 3. 자동화된 현재 증거와 실기 증거 분리

현재 repository test가 증명하는 것:

- 35 mm/120 format enum과 nominal aspect
- geometry-only detector behavior
- mock overview에서 format별 region detection
- normalized region -> physical scan area 변환
- full-scan request에 그 area 전달
- v2 applied options와 capture manifest에 area 보존
- automatic region의 output aspect mismatch rejection
- preview/session/revision ownership

현재 repository test가 증명하지 않는 것:

- Windows WIA/TWAIN device enumeration
- 실제 scanner lamp/holder/transport
- 실제 16-bit/channel transfer
- 실제 ROI origin/extent 적용
- 실제 IR registration
- 실제 multi-exposure
- vendor color correction disable
- Windows ARM64 driver
- cancellation 뒤 physical recovery

Mock fixture의 format별 frame count는 test image 배치의 기대값이지 모든 holder의 물리 수용 장수
표준이 아닙니다.

| fixture format | test count |
|---|---:|
| 35 mm 36 x 24 | 6 |
| 35 mm 24 x 24 | 8 |
| 35 mm 24 x 18 | 11 |
| 120 6 x 4.5 | 4 |
| 120 6 x 6 | 3 |
| 120 6 x 7 | 2 |
| 120 6 x 8 | 2 |
| 120 6 x 9 | 2 |
| 120 6 x 12 | 1 |
| 120 6 x 17 | 1 |

실제 holder의 frame count를 이 표로 강제하지 않습니다.

## 4. OS와 architecture matrix

최소 검증 축:

| host OS | host app | adapter | driver/data source | 상태 |
|---|---|---|---|---|
| Windows 11 x64 supported baseline | x64 | WIA x64 | native x64 WIA | 필수 |
| Windows 11 x64 supported baseline | x64 | TWAIN x64 | 64-bit DS | 대상 장치가 제공할 때 |
| Windows 11 x64 supported baseline | x64 | TWAIN x86 | 32-bit DS | legacy target |
| Windows 11 ARM64 supported baseline | ARM64 | WIA ARM64 | native ARM64 WIA | 필수 ARM64 target |
| Windows 11 ARM64 supported baseline | ARM64 | TWAIN x64 | emulated/native availability | 실기 결정 |
| Windows 11 ARM64 supported baseline | ARM64 | TWAIN x86 | emulation + driver path | 실기 결정 |

Windows version은 “최신” 문자열로 기록하지 않고 build number와 patch를 기록합니다. release 직전
supported baseline을 다시 고정합니다.

## 5. Device inventory record

장치마다 다음 record를 먼저 만듭니다.

```yaml
case_id: SCN-0001
captured_at_utc: 2026-08-04T00:00:00Z
operator: redacted-or-lab-id
host:
  windows_edition: Windows 11
  build: exact-build
  cpu: exact-model
  architecture: x64-or-arm64
  ram_bytes: exact
  usb_controller: exact
device:
  vendor: exact-driver-string
  model: exact-driver-string
  hardware_revision: observed-or-unknown
  firmware: observed-or-unknown
  usb_vid: observed
  usb_pid: observed
  serial_hash: sha256-or-absent
  connection: direct-usb-or-hub
driver:
  package_provider: exact
  package_version: exact
  date: exact
  hardware_ids: exact
adapter:
  kind: wia-or-twain
  version: exact
  architecture: x86-x64-arm64
  sha256: exact
  signer: exact
protocol:
  manifest_schema: 1
  protocol: 2
```

serial 원문은 public artifact에 넣지 않습니다. lab record에서 필요하면 접근을 제한합니다.

## 6. 대상 장치 선정

초기 lab matrix는 최소 세 종류를 포함합니다.

1. modern flatbed film scanner/transparency unit
2. dedicated 35 mm film scanner
3. legacy scanner whose useful driver is 32-bit TWAIN

제품 조사 후보로 Epson, Plustek, Nikon 계열을 사용할 수 있지만, 구체 모델을 verified로 표시하려면
이 문서의 실기 row가 필요합니다. macOS SANE backend/device-list 증거를 Windows WIA/TWAIN 증거로
재사용하지 않습니다.

같은 장치가 WIA와 TWAIN을 모두 제공하면 같은 조건으로 두 adapter를 비교합니다. 한쪽이 먼저
성공했다고 다른 쪽 조사를 생략하지 않습니다.

## 7. Discovery matrix

| case | PnP/USB | WIA enumerate | TWAIN x64 | TWAIN x86 | open | reconnect stable ID |
|---|---:|---:|---:|---:|---:|---:|
| device A |  |  |  |  |  |  |

각 cell은 pass/fail/unsupported/not-run 중 하나이며 evidence path를 가집니다.

필수 evidence:

- Device Instance ID 또는 hardware IDs
- WIA root/item tree dump
- TWAIN identity list
- adapter raw device response
- routed ID
- driver version
- cold boot와 reconnect 차이

USB VID/PID가 맞아도 adapter open이 실패하면 “detected” 이상으로 올리지 않습니다.

## 8. Capability capture

### 8.1 raw와 normalized를 둘 다 저장

```text
driver raw capabilities
    -> adapter mapping
    -> plugin JSON
    -> host normalized ScannerCapabilities
    -> visible WinUI controls
```

각 단계 snapshot을 같은 case ID로 묶습니다.

### 8.2 capability table

| capability | raw backend evidence | plugin value | host value | UI | verified by scan |
|---|---|---|---|---|---|
| resolutions |  |  |  |  |  |
| modes |  |  |  |  |  |
| bit depths |  |  |  |  |  |
| transparency |  |  |  |  |  |
| preview |  |  |  |  |  |
| scan area |  |  |  |  |  |
| positioned area |  |  |  |  |  |
| IR |  |  |  |  |  |
| multi-exposure |  |  |  |  |  |
| brightness |  |  |  |  |  |
| contrast |  |  |  |  |  |
| hardware exposure |  |  |  |  |  |
| TIFF/RAW output |  |  |  |  |  |
| ICC/profile |  |  |  |  |  |

capability query만 통과한 항목은 마지막 열이 비어 있습니다.

### 8.3 range validation

list:

- item count
- order
- duplicates
- current/default

range:

- min/max/step
- current/default
- unit
- boundary set/read-back
- non-step input rounding

boolean:

- absent versus false
- backend reports but acquisition fails

## 9. Film format matrix

### 9.1 nominal formats

현재 `FilmFrameFormat`:

| code | display | strip width mm | strip height mm |
|---|---|---:|---:|
| `fullFrame35mm` | 35 mm - 36 x 24 | 36 | 24 |
| `square35mm` | 35 mm - 24 x 24 | 24 | 24 |
| `halfFrame35mm` | 35 mm - 24 x 18 | 18 | 24 |
| `medium645` | 120 - 6 x 4.5 | 41.5 | 56 |
| `medium66` | 120 - 6 x 6 | 56 | 56 |
| `medium67` | 120 - 6 x 7 | 69 | 55 |
| `medium68` | 120 - 6 x 8 | 76 | 56 |
| `medium69` | 120 - 6 x 9 | 84 | 56 |
| `medium612` | 120 - 6 x 12 | 112 | 56 |
| `medium617` | 120 - 6 x 17 | 168 | 56 |

이는 nominal aperture/aspect contract입니다. 실제 film image edge와 holder mask는 다를 수 있으므로
detector/ROI evidence를 따로 기록합니다.

### 9.2 per-format rows

| format | orientation | preview detect | manual ROI | full ROI | applied evidence | output aspect | repeat |
|---|---|---:|---:|---:|---:|---:|---:|
| 35 mm full | landscape |  |  |  |  |  |  |
| 35 mm full | portrait |  |  |  |  |  |  |
| 35 mm square | n/a |  |  |  |  |  |  |
| 35 mm half | landscape |  |  |  |  |  |  |
| 35 mm half | portrait |  |  |  |  |  |  |
| 120 6 x 4.5 | both |  |  |  |  |  |  |
| 120 6 x 6 | n/a |  |  |  |  |  |  |
| 120 6 x 7 | both |  |  |  |  |  |  |
| 120 6 x 8 | both |  |  |  |  |  |  |
| 120 6 x 9 | both |  |  |  |  |  |  |
| 120 6 x 12 | both |  |  |  |  |  |  |
| 120 6 x 17 | both |  |  |  |  |  |  |

장치 physical area가 format을 수용하지 못하면 unsupported이고 failure가 아닙니다. 하지만 UI에서
그 format을 숨기는 capability/geometry evidence가 있어야 합니다.

## 10. Preview

### 10.1 flatbed preview resolution

현재 product target은 300 DPI입니다.

선택 규칙:

- supported positive resolutions만 사용
- 300과 절대 차이가 가장 작은 값
- 동률이면 높은 값
- native “lowest resolution preview” API를 무조건 사용하지 않음

flatbed positioned workflow preview는 explicit resolution full-scan artifact route를 사용할 수 있습니다.
preview artifact는 ephemeral이며 final source로 publish하지 않습니다.

### 10.2 preview record

- requested scan area
- applied scan area
- requested target DPI
- selected backend DPI
- reported DPI
- artifact DPI metadata
- width/height
- bit depth
- color model
- acquisition time
- warmup time
- holder/film layout photo or diagram

### 10.3 preview acceptance

- correct device/session ownership
- non-empty decodable artifact
- applied evidence available for v2
- scan area within physical bounds
- preview image maps top-left normalized detector coordinates consistently
- rotate/orientation mapping verified
- repeated preview does not retain stale regions
- cancel leaves no published preview as full scan

## 11. ROI chain

### 11.1 names

```text
R_previewPhysical  = physical area actually scanned for overview
R_detectedUnit     = detector result in overview normalized coordinates
R_detectedPhysical = map(R_detectedUnit, R_previewPhysical)
R_requested        = full scan request
R_applied          = plugin v2 appliedOptions.scanArea
R_manifest         = CaptureManifest applied evidence
R_artifact         = pixel geometry interpreted with R_applied
```

### 11.2 exact-support invariant

지원 표의 `exact ROI` pass는 다음을 요구합니다.

```text
R_detectedPhysical
    == R_requested
    == R_applied
    == R_manifest
```

모든 값은 origin X/Y, width, height를 포함합니다.

현재 protocol v2 validator는 backend alignment를 위해 applied height의 1 mm 미만 차이를 수용할 수
있습니다. 이것은 protocol safety compatibility이며 exact ROI pass가 아닙니다. delta가 있으면:

- exact ROI column = fail 또는 exception
- requested/applied 둘 다 evidence에 기록
- manifest = applied는 필수
- artifact aspect를 applied area와 비교
- device-specific exception을 release owner가 승인

strict equality 요구와 protocol tolerance를 섞지 않습니다.

### 11.3 geometry acceptance

automatic region output:

- artifact pixel aspect와 applied physical aspect 비교
- relative tolerance 2%
- 최소 pixel tolerance 3 px

이 현재 application safety check는 장치의 optical crop 정확도 측정을 대체하지 않습니다. 별도로
calibrated target/film edge를 이용해 origin/extent error를 mm와 pixels로 측정합니다.

### 11.4 ROI case sheet

```yaml
region_id: row-0-col-0
format: medium67
source: automatic
preview:
  physical_area_mm: {x: 0, y: 0, width: 200, height: 100}
  artifact_pixels: {width: 0, height: 0}
detected:
  unit_rect: {x: 0, y: 0, width: 0, height: 0}
  confidence: 0
  straighten_degrees: 0
mapped_physical_mm: {x: 0, y: 0, width: 69, height: 55}
requested_mm: {x: 0, y: 0, width: 69, height: 55}
applied_mm: {x: 0, y: 0, width: 69, height: 55}
manifest_mm: {x: 0, y: 0, width: 69, height: 55}
artifact:
  width: 0
  height: 0
  bit_depth: 16
  color_model: rgb
exact_roi_pass: false
aspect_pass: false
```

## 12. Manual region

manual edit는 automatic straighten angle을 0으로 invalidates하고 source를 manual로 바꿉니다.

검증:

- create
- move
- resize with selected format aspect
- copy/paste size
- delete
- refresh
- keyboard accessibility
- orientation switch
- region overlap
- out-of-bounds clamp
- minimum/maximum size
- selected region persistence during current preview

manual region은 automatic detector의 output-aspect safety gate와 의미가 다를 수 있지만 requested/applied/
manifest evidence는 동일하게 필요합니다.

## 13. Resolution matrix

각 advertised DPI:

| requested | backend set | read-back | result | TIFF metadata | dimensions plausible | pass |
|---:|---:|---:|---:|---:|---:|---:|
|  |  |  |  |  |  |  |

검증:

- X/Y resolution separately
- list/range/current/default
- preview 0 convention과 actual backend DPI 분리
- optical resolution property는 selectable resolution 증거가 아님
- interpolation resolution을 optical이라고 표시하지 않음
- dimensions가 physical area와 DPI에서 plausible
- driver rounding을 applied evidence에 반영

## 14. Bit depth와 sample fidelity

각 mode/depth:

| color mode | requested bits/channel | backend read-back | decoded bits/component | sample range | pass |
|---|---:|---:|---:|---:|---:|
| RGB | 8 |  |  |  |  |
| RGB | 16 |  |  |  |  |
| gray | 8 |  |  |  |  |
| gray | 16 |  |  |  |  |
| IR | device-specific |  |  |  |  |

16-bit container라고 16-bit sensor precision을 주장하지 않습니다. 필요하면 step/ramp target과
histogram occupied levels를 측정합니다.

검증:

- no 8-bit-expanded-to-16 surprise
- endianness
- unsigned/integer sample format
- planar/chunky
- channel order
- alpha absence/meaning
- clipping
- black/white offset
- orientation

## 15. Color path

장치별:

- driver auto color correction on/off
- negative inversion on/off
- gamma
- sharpening
- dust removal
- grain reduction
- exposure auto
- ICC assignment
- raw/linear mode

를 capability와 artifact로 확인합니다.

Negaflow이 scanner profile accuracy를 주장하려면 별도 measured target/profile evidence가 필요합니다.
driver가 반환한 profile name이나 embedded ICC 존재만으로 device-accurate라고 부르지 않습니다.

동일 target을 WIA와 TWAIN으로 scan해:

- pixel dimensions
- bit depth
- histogram/clipping
- color transform
- embedded profile
- metadata

차이를 기록합니다.

## 16. Film polarity

각 mode:

- color negative
- color positive/slide
- B&W negative
- B&W positive

에 대해 backend property, applied evidence, artifact polarity를 기록합니다.

driver가 negative mode에서 자체 inversion/color correction을 한다면 Negaflow의 non-destructive inversion
pipeline과 충돌합니다. raw negative density를 얻을 수 없는 route는 제한 지원 또는 unsupported로
표시합니다.

## 17. Infrared

### 17.1 capability

IR은 device model table이 아니라:

- backend-reported IR source/mode
- successful IR acquisition
- v2 applied infrared true
- RGB/IR artifact validation

으로만 켭니다.

### 17.2 physical matrix

| film | IR requested | RGB | IR | dimensions | registration | usable | pass |
|---|---:|---:|---:|---:|---:|---:|---:|
| color negative |  |  |  |  |  |  |  |
| color positive |  |  |  |  |  |  |  |
| chromogenic B&W |  |  |  |  |  |  |  |
| silver B&W |  |  |  |  |  |  |  |

RGB와 같은 dimensions만으로 pixel registration이 증명되지 않습니다. fiducial/defect target으로
translation, scale, rotation, nonlinear offset을 측정합니다.

IR이 물리적으로 부적절한 film type에는 capability가 있어도 product gate가 막아야 합니다.

### 17.3 unrequested IR

IR off scan에서 IR path/flag/file이 나타나면 pass가 아닙니다. host가 거부해야 합니다.

## 18. Multi-exposure

검증:

- capability query
- enabled/disabled set/read-back
- scan count/time 변화
- artifact dynamic range 변화
- motion/registration
- cancellation between passes
- IR와 동시 사용 가능 여부
- driver UI 없이 deterministic operation

단순히 scan이 오래 걸렸다는 것으로 multi-exposure를 증명하지 않습니다.

## 19. Headless behavior

Negaflow UI가 scanner control의 owner입니다.

WIA/TWAIN adapter:

- vendor modal UI 없음이 기본
- unexpected dialog detect
- desktop/session lock
- focus stealing 없음
- headless control unsupported면 capability/adapter status에 표시

TWAIN `ShowUI = FALSE`를 요청했는데 DS가 UI를 띄우거나 transfer를 시작하지 못하면 target device
row에서 기록합니다. 이를 일반 success로 숨기지 않습니다.

## 20. Progress와 long-running scan

단계:

- connecting
- warming lamp
- preview scanning
- waiting for holder
- RGB
- IR
- device processing
- exporting/staging
- complete

각 단계의 timestamps와 fraction monotonicity를 기록합니다. fraction이 제공되지 않는 단계는
indeterminate로 표시합니다.

long scan:

- maximum advertised DPI
- largest physical area
- 16-bit RGB
- IR/multi-exposure combinations
- cold lamp

에서 timeout, stdout budget, memory, disk peak를 측정합니다.

## 21. Cancellation matrix

| phase | API cancel | process exits | descendants exit | staging clean | device reusable | elapsed |
|---|---:|---:|---:|---:|---:|---:|
| detect |  |  |  |  |  |  |
| capabilities |  |  |  |  |  |  |
| warmup |  |  |  |  |  |  |
| RGB transfer |  |  |  |  |  |  |
| IR transfer |  |  |  |  |  |  |
| processing |  |  |  |  |  |  |
| file flush |  |  |  |  |  |  |

device reusable:

1. cancel 완료
2. detect
3. capabilities
4. low-cost preview

가 성공해야 pass입니다. process가 사라진 것만으로 scanner recovery를 주장하지 않습니다.

## 22. Disconnect/reconnect

시험:

- idle unplug
- warmup unplug
- RGB transfer unplug
- IR transfer unplug
- result 직전 unplug
- reconnect same port
- reconnect different port/hub
- system sleep/resume
- USB selective suspend

확인:

- stable error category
- no partial publication
- no stale capability token
- routed device ID behavior
- serial absent device ambiguity
- re-enumeration
- next scan

## 23. Busy와 multi-client

- vendor app가 device를 연 상태
- Windows Scan app가 device를 연 상태
- second Negaflow plugin process
- WIA와 TWAIN 동시 open
- two user sessions

busy를 not-found로 바꾸지 않습니다. retry/backoff와 user action을 구분합니다.

## 24. Repeatability

최소 반복 후보:

- quick preview 20회
- representative full scan 10회
- maximum-cost scan 3회
- cancel/recover 10회
- reconnect 5회
- app restart 5회

측정:

- dimensions
- applied ROI
- duration
- file size
- hash는 analog noise 때문에 동일성 기준이 아님
- mean/percentile pixel statistics
- crash/hang
- handle/process leak
- device state

반복 수는 release risk와 scan 비용에 따라 늘릴 수 있지만 줄일 때 이유를 기록합니다.

## 25. Performance

장치 시간과 host 시간을 분리합니다.

```text
enumeration
device open
capability query
lamp warmup
mechanical acquisition
USB transfer
driver processing
adapter TIFF write
host validation
commit
catalog manifest
```

CPU/GPU pipeline 성능과 scanner mechanical time을 섞지 않습니다. scanner plugin이 GPU를 사용할 이유는
기본적으로 없으며 vendor algorithm이 요구하는 경우 별도 측정합니다.

## 26. Resource capture

- adapter peak working set/private bytes
- x86 virtual address pressure
- handle count
- threads
- disk write bytes
- staging peak
- stdout/stderr bytes
- WIA service/vendor process resources
- USB throughput

large flatbed 16-bit scan의 plausible output size를 ROI/DPI/channel로 계산해 disk-space preflight와
비교합니다.

## 27. Packaging/install matrix

| action | x64 OS | ARM64 OS | standard user | admin install | rollback |
|---|---:|---:|---:|---:|---:|
| main app install |  |  |  |  |  |
| WIA plugin install |  |  |  |  |  |
| TWAIN x64 plugin |  |  |  |  |  |
| TWAIN x86 plugin |  |  |  |  |  |
| driver install |  |  |  |  |  |
| plugin update |  |  |  |  |  |
| plugin uninstall |  |  |  |  |  |

driver install은 plugin install과 분리합니다. plugin installer가 vendor driver를 허가 없이 bundle하지
않습니다.

## 28. Evidence bundle

각 run:

```text
SCN-0001/
    environment.json
    device.json
    driver.json
    plugin-manifest.json
    plugin-hashes.json
    detect-raw.json
    detect-normalized.json
    capabilities-raw.json
    capabilities-plugin.json
    capabilities-host.json
    request.json
    events.ndjson
    result.json
    capture-manifest.json
    artifact-metadata.json
    roi.json
    timings.json
    logs-redacted/
    images-private/
    report.md
```

공개 저장소에는 라이선스와 privacy 검토를 통과한 synthetic/cropped evidence만 넣습니다. 실제 scans와
serial/path는 private lab storage에 둘 수 있습니다.

## 29. Result vocabulary

- `PASS`: 모든 required assertion 충족
- `FAIL`: 실행했고 assertion 위반
- `UNSUPPORTED`: backend/device가 capability를 제공하지 않음
- `BLOCKED`: 환경/장치/권한 때문에 실행 못 함
- `NOT RUN`: 아직 실행 안 함
- `INCONCLUSIVE`: evidence가 모순되거나 부족

`BLOCKED`, `NOT RUN`, `INCONCLUSIVE`를 pass로 세지 않습니다.

## 30. Device support row

```yaml
support_status: experimental
verified_scope:
  os_builds: []
  host_architectures: []
  adapters: []
  driver_versions: []
  formats: []
  resolutions: []
  bit_depths: []
  infrared: false
  multi_exposure: false
limitations: []
evidence_case_ids: []
last_verified_at: null
```

제품 UI와 website는 이 row보다 넓은 지원을 주장하면 안 됩니다.

## 31. Release gate

장치 하나를 verified로 올리기 위한 최소 gate:

- exact inventory record
- signed adapter package
- E2 enumeration
- E3 complete capability snapshot
- E4 preview
- E5 representative full scans
- advertised format 전체 row
- exact ROI chain 또는 명시적으로 승인된 exception
- applied/manifest/artifact consistency
- advertised bit depth 실물 검증
- IR/multi-exposure 광고 시 해당 physical tests
- cancel/recover
- disconnect/reconnect
- repeatability
- install/update/rollback
- privacy-redacted evidence bundle
- known limitations

## 32. App-level scanner release gate

개별 장치 외에:

- scanner plugin이 없어도 import/develop/export 완전
- no implicit Mock fallback
- capability 없는 control 없음
- stale device/session result 적용 없음
- preview artifact가 original full scan으로 승격되지 않음
- failed result가 catalog에 publish되지 않음
- scanner original overwrite 없음
- plugin update가 active scan을 교체하지 않음
- x64/ARM64 main app parity
- accessibility/localization

## 33. 현재 미실행 상태

이 문서는 실행 계획이며 Windows physical hardware 결과가 아닙니다. 현재 확인된 것은 macOS repository의
virtual/geometry/protocol test 구조와 공식 WIA/TWAIN 문서입니다.

따라서 다음 표현은 아직 금지합니다.

- “Epson/Plustek/Nikon Windows 지원 완료”
- “WIA가 16-bit film scan을 보장”
- “TWAIN이면 모든 legacy scanner 지원”
- “ARM64 Windows에서 x86 scanner 완전 호환”
- “IR registration verified”

각 표현은 해당 case ID와 artifact가 생긴 뒤에만 갱신합니다.
