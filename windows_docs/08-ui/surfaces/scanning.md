# Scanning surface와 Windows scanner plugin 이식 명세

기준일: 2026-08-04  
macOS 기준 커밋: `9be909c`  
소스 근거: `ScannerKit`, `Features/Scanning`, scanner workflow tests  
공식 근거: [Scan from your app](https://learn.microsoft.com/en-us/windows/apps/develop/devices-sensors/scan-from-your-app),
[Windows.Devices.Scanners](https://learn.microsoft.com/en-us/uwp/api/windows.devices.scanners),
[WIA architecture overview](https://learn.microsoft.com/en-us/windows-hardware/drivers/image/wia-architecture-overview),
[Basic scanning for film scanners](https://learn.microsoft.com/en-us/windows-hardware/drivers/image/basic-scanning-for-film-scanners),
[WIA X resolution](https://learn.microsoft.com/en-us/windows-hardware/drivers/image/wia-ips-xres),
[WIA scan extent](https://learn.microsoft.com/en-us/windows-hardware/drivers/image/wia-ips-xextent),
[TWAIN 2.5 specification](https://twain.org/wp-content/uploads/2021/11/TWAIN-2.5-Specification.pdf)

## 1. 목표와 절대 경계

Windows판도 scanner driver를 Negaflow 본체에 링크하거나 load하지 않는다. 장치 발견·capability 협상·
scan은 별도 executable plugin이 수행하고, 본체는 버전 관리된 JSON/NDJSON과 staging file만 교환한다.

```text
Negaflow.exe (WinUI 3 + app services)
    │ documented scanner CLI protocol
    │ stdin JSON / stdout NDJSON / stderr diagnostics
    │ app-owned staging file path
    ▼
scanner adapter process
    ├─ negaflow-scanner-wia.exe
    ├─ negaflow-scanner-twain-x64.exe
    ├─ negaflow-scanner-twain-x86.exe
    └─ separately distributed SANE/eSCL/vendor adapters if approved
          │
          ▼
      OS service / DSM / vendor driver / device
```

이 경계가 보장해야 하는 것:

- SANE/GPL과 본체의 build·link·배포 분리
- TWAIN Data Source와 host bitness 분리
- vendor driver crash/hang과 WinUI process 분리
- 장치별 COM apartment/DLL global state 격리
- app이 지원하지 않는 option을 추측하지 않는 capability-driven UI
- plugin이 보고한 결과를 신뢰하기 전에 wire·artifact·applied-option 검증
- plugin 없이도 import → develop → export 제품 흐름 완전 동작

`Windows.Devices.Scanners`가 desktop app에서도 제공된다고 해서 app process에서 직접 호출하지 않는다.
WIA adapter 내부에서 사용하면 Windows-native 장치 열거와 기본 scan을 얻으면서 host 경계를 유지할 수 있다.

## 2. UI 구조

Scanner controls는 Library source sidebar의 scan section에 들어간다.

```text
Scan
├─ Scanner [device popup] [Rescan]
├─ Film type
├─ Scan folder [name] [Choose folder]
├─ Resolution | Color mode
├─ Bit depth
├─ Film frame format
├─ Detection: Automatic / Manual [Refresh]
├─ Preview canvas + frame regions
├─ Selected regions [Copy] [Paste] [Add] [Delete]
├─ optional capability controls
│   ├─ physical scan area
│   ├─ IR
│   ├─ brightness / contrast
│   └─ hardware exposure / multi-exposure only when supported
└─ Preview | Scan N / Cancel
```

plugin 상태별 surface:

| 상태 | 표시 | 허용 행동 |
|---|---|---|
| 설치 plugin 없음 | 설치 필요 설명 | Rescan, explicit Demo opt-in |
| 승인 대기 | 이름/version/license/hash | Approve 또는 inspect |
| binary identity 변경 | 재승인 필요 warning | Reapprove/Revoke |
| 승인됨, 장치 없음 | waiting/disconnected | Rescan |
| detecting | searching + progress | 중복 detect 금지 |
| 장치 있음, capability loading | 장치명 + loading | scan disabled |
| capability 불충분 | 구체 unavailable reason | 다른 장치/Rescan |
| ready | 보고된 control만 | Preview/Scan |
| scanning | phase + batch progress | Cancel |

Mock scanner는 production fallback이 아니다. 사용자가 `Demo`를 명시적으로 켠 session에서만 보이고,
실물 장치처럼 `Verified` badge를 얻지 않는다.

## 3. 장치 선택과 발견

host descriptor:

- stable routed ID: `plugin:<pluginId>:<deviceId>`
- display name, vendor, model
- connection: USB/network/SCSI/FireWire/internal
- optional USB VID/PID, serial, firmware, driver version
- verification status: `Verified`, `Compatible Target`, `Experimental`
- backend type은 내부 diagnostics에만 사용하고 일반 UI에는 노출하지 않음

발견 규칙:

1. plugin manifest와 executable identity를 재검증한다.
2. 승인된 plugin만 launch한다.
3. plugin별 `detect`를 bounded concurrency로 실행한다.
4. 각 device ID에 plugin route를 붙인다.
5. duplicate route, invalid text/length, malformed VID/PID를 거부한다.
6. 이전 선택 ID가 여전히 있으면 유지하고, 없으면 첫 장치로 이동한다.
7. selection 변경 후 capability를 새 request identity로 불러온다.
8. 이전 장치의 늦은 capability response는 적용하지 않는다.

Windows WIA adapter는 `DeviceInformation`/`DeviceWatcher` 또는 WIA item enumeration 결과를 내부
device ID로 변환한다. Microsoft 공식 문서상 `Windows.Devices.Scanners`에는 로컬 WIA driver가 설치된
scanner만 나타난다. 따라서 “USB에 보임”과 “WIA에서 획득 가능”을 구분한다.

TWAIN adapter는 DSM에서 열 수 있는 Data Source만 보고한다. registry entry나 vendor application이
있다는 사실만으로 scan 가능하다고 보고하지 않는다.

## 4. capability truth

UI가 소비하는 capability:

- supported resolutions: positive DPI list/range를 finite integer list로 정규화
- Color/Gray/Lineart/Infrared modes
- 8/16-bit per channel
- source/transparency modes
- preview, transparency, infrared, multi-exposure
- scan area, positioned scan area
- lamp warm-up status
- brightness/contrast/hardware-exposure range와 step
- X/Y origin, width/height range와 step
- min/max physical area와 unit
- supported output formats
- opaque capability token
- capability별 disabled reason

원칙:

- model-name table로 capability를 덧붙이지 않는다.
- `supportsInfrared`와 실제 IR result contract가 둘 다 만족되어야 한다.
- option range의 min/max/step이 invalid면 해당 option만 fail-closed한다.
- pixel-unit scan-area capability는 physical mm ROI로 해석하지 않는다.
- inch는 mm로 정규화하고 UI에서만 다시 변환한다.
- capability token은 host가 해석·수정하지 않고 동일 routed scanner의 다음 scan에 그대로 echo한다.
- capability snapshot 뒤 장치가 바뀌면 adapter가 scan을 실패시키고 새 capability 조회를 요구한다.

WIA property 매핑 후보:

| Negaflow | WIA |
|---|---|
| resolution | `WIA_IPS_XRES`, `WIA_IPS_YRES` |
| region origin | `WIA_IPS_XPOS`, `WIA_IPS_YPOS` |
| region extent | `WIA_IPS_XEXTENT`, `WIA_IPS_YEXTENT` |
| bit depth | `WIA_IPA_DEPTH`, `WIA_IPA_BITS_PER_CHANNEL` |
| color mode | `WIA_IPA_DATATYPE` / photometric properties |
| film source | item category `WIA_CATEGORY_FILM` |
| film polarity | `WIA_IPS_FILM_SCAN_MODE` |
| lamp | `WIA_IPS_LAMP` when present |
| transfer format | `WIA_IPA_FORMAT`, `WIA_IPA_TYMED` |

Microsoft 문서도 driver가 요청 extent를 반올림할 수 있으며 returned header/property의 actual 값을 읽어야
한다고 명시한다. 그래서 adapter는 “set call 성공”을 applied evidence로 쓰지 않고, scan 직전/후 actual
properties와 artifact header를 다시 읽어 protocol v2 `appliedOptions`로 보고한다.

## 5. 기본값과 선택 clamp

현재 제품 기본:

- full scan target: 3600 DPI
- bit depth: 가능하면 16-bit/channel
- mode: 가능하면 Color
- film: Color Negative
- auto base: develop 쪽 기본 규칙
- IR: off
- multi-exposure: off
- raw TIFF: on

장치가 3600 DPI를 지원하지 않으면 절댓값 차이가 가장 작은 positive supported resolution을 선택하고,
동률이면 높은 값을 고른다. lowest list item을 기본으로 쓰지 않는다. Epson 계열처럼 50 DPI부터 많은 값을
보고하는 장치에서 저해상도가 조용히 선택되는 일을 막는다.

선택된 resolution/mode/depth가 새 capability에 없으면 preference를 clamp한다. scan request 직전에도
같은 validation을 반복한다.

## 6. preview 계약

두 종류의 preview를 구분한다.

### 6.1 film scanner overview preview

- protocol의 `resolutionDPI = 0`, `preview = true`
- adapter의 native preview operation을 사용
- 8/16-bit는 capability와 backend 계약에 맞춤
- persistent Library source가 아니라 ephemeral artifact

### 6.2 positioned flatbed preview

평판 preview는 frame region을 잡는 측정 surface이므로 장치의 최저 preview resolution을 그대로 쓰지 않는다.

- 목표 300 DPI
- exact 300이 없으면 가장 가까운 supported positive DPI, 동률이면 높은 값
- positive DPI이므로 wire상 full scan request이자 TIFF output
- app에서는 result를 `isPreviewScan` ephemeral frame으로 취급
- preview area는 실제 `appliedOptions.scanArea`에서 가져옴
- 결과 aspect가 applied physical area와 2% 또는 최소 3 pixel 범위에서 맞아야 함
- mismatch이면 artifact를 제거하고 region detection을 시작하지 않음

Microsoft의 `ScanPreviewToStreamAsync`는 최저 scan resolution을 적용하므로 Negaflow의 300-DPI flatbed
계약을 만족하지 않을 수 있다. WIA adapter는 이 경우 preview API 대신 명시적 full scan configuration을
사용해야 한다.

preview lifecycle:

1. app-owned preview temp path 예약
2. full physical preview area 요청
3. applied area + TIFF header 검증
4. ephemeral preview frame 생성
5. bounded preview image decode
6. automatic detection 또는 manual region 준비
7. 새 preview 성공 시 이전 ephemeral preview 제거
8. full scan이 모두 publish되면 preview 제거

preview 실패·취소·session ownership 상실 시 uncommitted RGB/IR/temp path만 제거한다.

## 7. film format matrix

지원 format과 공칭 aperture:

| format | 진행축 × 폭 방향(mm) | aspect 후보 |
|---|---:|---:|
| 35 mm Full | 36 × 24 | 1.5 / 0.6667 |
| 35 mm Square | 24 × 24 | 1.0 |
| 35 mm Half | 18 × 24 | 0.75 / 1.3333 |
| 120 6×4.5 | 41.5 × 56 | 양방향 |
| 120 6×6 | 56 × 56 | 1.0 |
| 120 6×7 | 69 × 55 | 양방향 |
| 120 6×8 | 76 × 56 | 양방향 |
| 120 6×9 | 84 × 56 | 양방향 |
| 120 6×12 | 112 × 56 | 양방향 |
| 120 6×17 | 168 × 56 | 양방향 |

capability max physical area에 standard 또는 rotated aperture가 들어가는 format만 UI에 표시한다.
positioned scan을 지원하지만 preview를 지원하지 않는 장치에는 flatbed region workflow를 열지 않는다.

35 mm perforation option은 Mock/demo fixture에만 해당하고 production capability로 추정하지 않는다.

## 8. automatic frame detection

detector는 color·density·negative polarity를 가정하지 않는 geometry-only detector다.

입력 조건:

- analysis long edge 최대 2048
- 최소 analysis dimension 256, 짧은 변 최소 48
- source normalized top-left coordinates

처리:

1. background-separated component rectangles 탐색
2. 선택 format의 landscape/portrait aspect 후보 비교
3. 반복 strip boundary와 row/column topology 탐색
4. 필요 시 foreground crop
5. deskew estimate 또는 ±1–5° 후보 탐색
6. source coordinate로 역변환
7. ambiguous result는 empty로 fail-closed

적용 직전 gate:

- preview frame ID와 session ID 일치
- requested format 불변
- region revision 불변
- 기존 regions가 비어 있음
- 모든 rect/confidence/angle finite·valid
- `(row,column)` unique
- row-major deterministic order

자동 detection 실패 시 “0 frame”을 성공으로 위장하지 않는다. 사용자가 `Manual`로 전환하거나 `Refresh`할
수 있는 설명을 보인다.

## 9. manual region editing

flatbed overlay:

- add, select, delete
- size copy/paste
- move/resize handles
- arrow nudge 0.5 mm
- Shift+arrow coarse nudge 2 mm
- selected format aspect snap
- straighten angle -45…45°
- automatic/manual source 표시

region rect는 preview physical area에 대한 normalized top-left rectangle이다. full scan ROI:

```text
xMM = previewArea.xMM + rect.minX * previewArea.widthMM
yMM = previewArea.yMM + rect.minY * previewArea.heightMM
wMM = rect.width  * previewArea.widthMM
hMM = rect.height * previewArea.heightMM
```

그 뒤 capability min/max와 origin/extent step으로 quantize한다. origin을 아래로, extent를 위로 quantize해
사용자가 잡은 area를 가능한 한 포함하되 bed boundary를 넘지 않는다.

format aspect snap은 화면 pixel aspect가 아니라 preview physical mm aspect를 사용한다. preview frame의
회전/flip을 적용한 display-direction key movement를 physical source direction으로 되돌리는 변환은 overlay와
request builder가 같은 utility를 사용한다.

## 10. ROI 증거 불변식

positioned full scan의 핵심 gate:

```text
detected/manual ROI
  → requested physical ROI
  → adapter verified applied ROI
  → artifact header dimensions/aspect
  → CaptureManifest appliedOptions + file identity
```

자동 region에서는 다음을 모두 확인한다.

- v2 `appliedOptions` 존재
- applied scanner/device/options가 request와 exact match
- applied ROI가 adapter quantization 계약과 일치
- result width/height가 TIFF header와 일치
- bit depth와 color model이 TIFF와 일치
- output aspect가 applied ROI aspect와 tolerance 내 일치
- manifest에는 requested와 applied를 별도로 기록

`detected ROI = requested full-scan ROI = verified applied/manifest ROI`를 목표로 하되, hardware step 때문에
정규화가 필요한 경우 detected와 applied를 동일하다고 거짓 기록하지 않는다. 차이를 mm와 expected pixel
delta diagnostics로 남긴다.

legacy protocol v1에는 applied evidence가 없으므로 `unknownLegacy(1)`이다. request를 applied로 복사하지
않는다. 자동 positioned region의 production-quality 지원은 v2가 필수다.

## 11. IR와 film compatibility

IR control 표시 조건:

- capability가 IR을 명시
- 선택 film type이 automatic IR correction을 허용
- preview request가 아님

IR 요청 시 result contract:

- RGB와 IR artifact 둘 다 regular file
- v2에서는 둘 다 app staging tree 내부
- 같은 pixel width/height
- `hasInfrared`, `irPath`, applied option이 모순되지 않음
- 요청하지 않은 IR 결과는 거부
- 요청했는데 IR이 없으면 전체 scan 실패

color/B&W film에 대한 IR 가능 여부는 현재 제품의 `InfraredFilmCompatibility` truth를 이식한다. scanner
model name으로 예외를 추가하지 않는다. RGB 기반 defect removal을 Digital ICE/IR과 동등하다고 표시하지
않는다.

## 12. scan request와 wire protocol

protocol v2 request:

```jsonc
{
  "protocolVersion": 2,
  "requestID": "uuid",
  "deviceID": "adapter-internal-id",
  "resolutionDPI": 3600,
  "bitDepth": 16,
  "colorMode": "color",
  "filmType": "colorNegative",
  "preview": false,
  "multiExposure": false,
  "infrared": false,
  "brightnessAdjustment": null,
  "contrastAdjustment": null,
  "scanArea": { "originXMM": 0, "originYMM": 0, "widthMM": 36, "heightMM": 24 },
  "hardwareExposureTime": null,
  "outputRawTIFF": true,
  "capabilityToken": "opaque",
  "outputPath": "absolute app-owned staging path"
}
```

NDJSON event:

```jsonc
{
  "type": "progress | result | error",
  "protocolVersion": 2,
  "requestID": "same uuid",
  "sequence": 3,
  "phase": "scanningRGB",
  "fraction": 0.42
}
```

v2 validation:

- 모든 event version/request ID exact match
- sequence strictly increasing
- progress fraction finite and 0–1
- exactly one terminal result/error
- terminal 뒤 event 금지
- unknown event type 거부
- result의 optional applied fields도 key 존재를 요구해 “누락”과 `null` 구분
- applied options를 request와 field-by-field exact 비교

v1 manifest에는 version/request ID를 JSON에서 아예 생략한다. `null`로 보내 wire compatibility를 깨지
않는다. v1 output provenance는 unknown으로 유지한다.

## 13. artifact transaction

plugin은 최종 Library path를 직접 소유하지 않는다.

1. host가 최종 path 부재 확인
2. 같은 parent tree에 unique staging directory 생성
3. plugin에는 staging output path만 전달
4. process 종료와 terminal event 확인
5. result path가 expected staging path와 exact match하는지 확인
6. regular file, no symlink/reparse, non-empty 확인
7. TIFF decode/header/dimensions/depth/color model 확인
8. IR도 동일 검증
9. final path 부재 재확인
10. same-volume atomic rename으로 commit
11. capture observation/hash manifest 생성
12. durable workflow generation publish
13. frame를 Library에 publish

source TIFF 원본은 이후 불변이다. defect 처리, thumbnail, cleaned raw, sidecar는 app-owned 별도 artifact다.

Windows 구현은 reparse point와 hard-link identity도 확인한다. `GetFileInformationByHandleEx`, final-path
resolution, volume/file ID를 사용해 path string만으로 staging containment를 판정하지 않는다.

## 14. persistent workflow

full scan은 hardware call 전에 session/job generation을 저장한다.

```text
queued → running → finalizing → succeeded
              └──────────────→ failed
queued/running ───────────────→ cancelled
```

한 session은 다음 snapshot에 잠긴 ordered job set이다.

- device descriptor
- backend/plugin identifier와 protocol version
- OS/app/architecture environment
- immutable requested options
- output reservation와 frame publication plan
- attempt number, timestamps, error
- pending capture receipt
- final capture manifest

hardware scan 완료와 Library frame publish를 분리한다. capture 직후 `finalizing` receipt를 durable하게 저장한
뒤 hashing/fixity를 background에서 수행한다. crash 뒤에는 receipt와 실제 file identity를 대조해 publish,
fail, orphan quarantine 중 하나를 선택한다. missing/corrupt catalog를 empty catalog로 간주해 scan files를
삭제하지 않는다.

batch는 hardware를 한 번에 하나씩 수행한다. completed capture의 finalization은 background로 겹칠 수
있지만 frame publication order는 ordinal 순서를 지킨다. 앞 manifest가 실패하면 뒤 frame을 조용히
publish하지 않고 원인을 각각 terminal state로 기록한다.

## 15. progress와 취소

phase:

- connecting
- warming lamp
- ready
- preview scanning
- waiting for film holder
- scanning RGB
- scanning IR
- processing negative
- rendering look
- exporting/finalizing
- complete / busy / disconnected / error

plugin fraction이 없을 때 phase별 fallback을 쓰되 99.5%를 넘기지 않는다. batch display:

```text
overall = (completedOrdinal + currentFrameFraction) / totalFrames
```

progress UI update는 phase/message 변화, 1.5% 이동 또는 200 ms 경과 때만 수행해 UI thread를 과부하시키지
않는다. fraction은 역행하지 않는다.

Cancel:

1. host session ownership을 먼저 무효화
2. adapter process에 cooperative cancellation 신호
3. grace period 뒤 terminate
4. Windows Job Object로 descendant까지 정리
5. queued jobs cancel, captured/finalizing receipt는 보존
6. uncommitted staging만 제거
7. UI를 idle로 복귀

detect/capability/scan wall timeout 후보는 현재 실기 기준 90 s / 180 s / 7200 s를 시작점으로 둔다.
Windows 장치에서 측정해 조정하되 짧은 timeout으로 USB transfer 중 driver를 강제 종료하지 않는다.

## 16. Windows adapter 선택

### WIA adapter

권장 역할:

- Windows.Devices.Scanners 또는 WIA 2.0 COM으로 local WIA devices 발견
- flatbed/film item과 standard properties 협상
- TIFF/RAW capability와 actual returned properties 검증
- Windows-native basic coverage

장점:

- WIA service가 vendor minidriver와 app을 이미 process 분리
- Microsoft가 film item, negative/slide mode, positioned extent를 표준화
- desktop app에서 `Windows.Devices.Scanners` 사용 가능

제약:

- 실제 driver가 film item/16-bit/IR/custom feature를 얼마나 노출하는지는 장치별
- high-level WinRT preview는 최저 resolution을 사용
- advanced vendor-only 기능이 표준 property에 없을 수 있음

### TWAIN adapter

권장 역할:

- WIA에서 필요한 기능을 못 얻는 legacy/pro film scanner
- Data Source capability negotiation과 memory/file transfer
- x86와 x64 adapter를 분리 배포

TWAIN 2.x에서 native 64-bit application은 `TWAINDSM.DLL`을 사용한다. x86 Source와 x64 Source를 한
process에서 섞을 수 있다고 가정하지 않는다. 실제 scanner/driver matrix로 adapter architecture를 고른다.

### 결론 규칙

“TWAIN이 항상 우월” 또는 “WIA면 충분”을 문서만으로 확정하지 않는다. 장치별 acceptance matrix에서 다음
순서로 판정한다.

1. WIA adapter가 required capability와 픽셀 contract를 만족하면 WIA route 승인
2. 부족하고 TWAIN DS가 만족하면 matching-bitness TWAIN route 승인
3. 두 route가 있으면 verified quality/feature/stability 측정으로 default 결정
4. 어느 route도 applied ROI/bit-depth evidence를 못 주면 compatible 또는 experimental로 표시

## 17. plugin trust와 Windows process security

approval identity:

- plugin ID/version
- exact manifest SHA-256
- exact executable SHA-256
- signer/publisher identity는 추가 신호지만 hash approval을 대체하지 않음

launch 직전:

- manifest/executable handle을 no-follow로 열기
- owner/DACL/reparse/hard-link 정책 확인
- file identity와 approved hashes 재검증
- absolute executable path와 working directory 고정
- allowlisted environment block만 전달
- inherited handles를 explicit handle list로 제한
- console window 없음
- Job Object `KILL_ON_JOB_CLOSE`
- process mitigation compatibility를 adapter별로 시험

plugin stdout 4 MiB, stderr 1 MiB 상한을 기준으로 하고 NDJSON 단일 line 상한도 둔다. scanner pixels는 pipe로
전송하지 않는다.

신뢰 UI에는 name/version/license/path/manifest hash/executable hash/state를 표시한다. identity가 바뀌면
자동 실행하지 않고 재승인을 요구한다.

## 18. 접근성·입력

- device picker와 Rescan은 논리적으로 한 행
- capability가 비어 있는 picker를 보여주지 않고 이유 text 표시
- disabled control에는 plugin의 localized-safe reason 또는 host-mapped reason 제공
- Preview/Scan/Cancel은 한 줄 equal-width action row 유지
- region은 이름, 순서, format, physical size, selected/source state를 automation peer로 노출
- pointer drag 외에 keyboard move/resize와 inspector numeric edit 제공
- region border는 색 외에 selected thickness/handles로 상태 표시
- progress bar는 phase, current frame/total, percent를 Narrator에 throttled announce
- scanner disconnect/error 후 focus를 사라진 control에 남기지 않음
- high contrast에서 overlay·handle·warning·focus ring이 system colors를 따름

## 19. 장치 검증 matrix

각 adapter/device/architecture 조합마다:

| 범주 | 반드시 기록할 증거 |
|---|---|
| discovery | OS device ID, adapter route, driver/DSM version |
| capabilities | raw report + normalized host snapshot |
| request | exact JSON/options/token/ROI |
| application | protocol v2 applied options |
| artifact | TIFF headers, dimensions, bit depth, channels, ICC |
| ROI | requested/applied area와 aspect diagnostic |
| timing | open, warm-up, transfer, finalization |
| cancellation | user cancel, timeout, disconnect, host crash |
| recovery | staged/final/pending manifest state |

필수 format matrix:

- 35 mm full/square/half
- 120 6×4.5, 6×6, 6×7, 6×8, 6×9, 6×12, 6×17
- landscape/portrait placement
- single/multiple rows when bed permits
- automatic/manual regions
- 8/16-bit, color/gray
- IR on/off for a genuinely supported compatible film

USB enumeration, vendor app 인식, `DeviceWatcher` 항목 존재는 optical scan evidence가 아니다. 실제
acquisition과 artifact/applied-option validation이 있어야 `Verified`다.

## 20. 구현 완료 gate

- [ ] host는 scanner driver/DSM/SANE library를 링크 또는 load하지 않음
- [ ] WIA/TWAIN adapter가 동일 public scanner CLI schema를 구현
- [ ] manifest/trust/process launch가 Windows ACL·reparse·TOCTOU 검증 통과
- [ ] plugin 없이 import/develop/export가 완전히 동작
- [ ] Mock는 explicit demo에서만 동작
- [ ] capability 외 control을 UI가 노출하지 않음
- [ ] 300-DPI flatbed preview 또는 nearest supported policy 통과
- [ ] 전체 film format detector/ROI matrix 통과
- [ ] v2 request/event/applied option/artifact validation 통과
- [ ] automatic ROI mismatch가 fail-closed
- [ ] RGB/IR transaction과 cleanup failure injection 통과
- [ ] queued/running/finalizing crash recovery 통과
- [ ] x64, ARM64 host와 필요한 x86/x64 adapters 검증
- [ ] 실제 대상 scanner별 route를 optical evidence로 승인
- [ ] Narrator·keyboard·high contrast·scaling 검증

## 21. 남은 조사

- Windows 11 24H2/25H2 실제 WIA driver coverage와 ARM64 driver availability
- 대상 Epson/Plustek/Nikon 모델의 WIA film item·TWAIN DS capability 비교
- WIA 16-bit/channel TIFF/RAW의 endianness, planar/interleaved, ICC behavior
- vendor TWAIN DS가 hidden UI mode와 cancellation을 올바르게 지원하는지
- TWAIN DSM/SDK 재배포 license와 각 vendor DS 설치 조건
- x86 adapter를 ARM64 Windows emulation에서 실제 hardware driver와 함께 쓸 수 있는지
- network eSCL/TWAIN Direct를 별도 adapter로 둘 가치
- Windows Defender/Smart App Control이 user-installed unsigned plugin launch에 미치는 영향
- legal review: 배포물 분리, protocol 의미론, plugin installer와 support 책임
