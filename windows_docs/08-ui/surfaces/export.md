# Export·Quick Export surface와 트랜잭션 이식 명세

기준일: 2026-08-04  
macOS 기준 커밋: `9be909c`  
소스 근거: `Features/Export`, `Chromabase/Export`, Library export tracking  
공식 근거: [Windows Imaging Component overview](https://learn.microsoft.com/en-us/windows/win32/wic/-wic-about-windows-imaging-codec),
[WIC native pixel formats](https://learn.microsoft.com/en-us/windows/win32/wic/-wic-codec-native-pixel-formats),
[IWICBitmapEncoder](https://learn.microsoft.com/en-us/windows/win32/api/wincodec/nn-wincodec-iwicbitmapencoder),
[Windows Color System](https://learn.microsoft.com/en-us/windows/win32/api/_wcs/),
[CreateMultiProfileTransform](https://learn.microsoft.com/en-us/windows/win32/api/icm/nf-icm-createmultiprofiletransform)

## 1. 역할

Export는 현재 preview bitmap을 저장하는 기능이 아니다. export 시작 순간의 source, develop, defect,
metadata, profile, naming과 산출물 집합을 immutable snapshot으로 고정하고, 모든 파일을 staging에서 만든
뒤 충돌 없이 publish하며, 성공 event를 catalog에 durable commit하는 트랜잭션이다.

핵심 보장:

- source bytes가 snapshot 이후 바뀌면 실패
- active defect recipe 결과를 재구성하지 못하면 실패
- preview proxy를 final output으로 사용하지 않음
- primary/paired sidecar를 부분 publish하고 성공으로 보고하지 않음
- existing source/output을 덮어쓰지 않음
- crash 뒤 app-owned artifact만 identity로 판별해 복구
- batch는 frame별 success/failure/cancel을 보존
- Quick Export도 품질 경로를 우회하지 않음

## 2. UI 구조

Export section:

```text
Export
├─ File / Quality / Source detail tabs
├─ Recipe selector + save/rename/delete
├─ selected detail controls
└─ Export (N) + reveal

Quick Export
├─ JPEG / PNG
├─ DPI
├─ long edge
├─ JPEG quality or PNG bit depth
├─ folder
├─ filename preview
└─ Quick Export (N) + reveal

Batch progress
├─ completed / total / percent / failures
└─ Pause / Resume / Cancel / Retry Failed
```

Print/package가 ExportSection을 재사용할 때:

- paper layout은 source DPI를 허용하지 않고 positive DPI만 허용
- composite layout은 Source tab을 숨김
- long-edge control을 숨기는 layout이 있음
- action count는 page/output count 의미를 사용

## 3. 실행 가능 조건

일반 Export/Quick Export:

- actionable selection이 비어 있지 않음
- 다른 export batch가 실행 중이지 않음
- print package export가 실행 중이지 않음
- 모든 selected frame이 한 번 이상 developed됨
- 어느 selected frame도 developing 중이 아님
- 일반 Export는 naming template도 valid

Print selection:

- selection이 비어 있지 않음
- batch/package가 실행 중이지 않음
- preview scan 제외
- developing 중 아님
- normal Export는 naming template valid

`developTarget == print`인 developed output에는 exact printer output ICC가 필요하다. `Raw TIFF`에는
printer ICC를 적용하지 않는다. profile이 없거나 validation이 실패하면 실행 전에 block하고 이유를
표시한다.

UI의 enabled 규칙과 command/shortcut의 enabled 규칙은 같은 service를 사용한다.

## 4. 일반 Export 설정

### 4.1 File

- format: JPEG, PNG, TIFF
- destination root
- naming template
- sequence start
- filename preview
- recipe preset

### 4.2 Quality

- format-specific encoding controls
- color space: sRGB, Display P3, Adobe RGB
- DPI
- long edge
- output sharpening amount/medium

DPI 후보:

```text
Source/unspecified(0), 72, 150, 240, 300, 600
```

Long edge 후보:

```text
Full size(0), 1024, 2048, 4096, 6000 px
```

long edge는 축소만 하며 upscaling하지 않는다. DPI는 pixel dimension을 자동 변경하는 값이 아니라
metadata와 output sharpening scale의 입력이다. paper layout에서는 `0`을 숨기고 저장값이 0이면 UI
effective value를 300으로 보여준다.

### 4.3 Source

- metadata policy
- Main Flat Master
- Original Raw copy
- Negaflow JSON sidecar + XMP
- current source summary

세 옵션은 primary output과 별도 artifact다. 선택되면 basename collision 검사와 transaction에 모두
포함한다.

## 5. format별 encoding

| format | controls | 현재 기본 | alpha |
|---|---|---|---|
| JPEG | quality `0...1`, step .01 | `1.0` | 불가 |
| PNG | 8/16-bit | 일반 16-bit | 선택 가능 |
| TIFF | none/LZW/Deflate, 8/16-bit | 16-bit none | 선택 가능 |
| Raw TIFF | fixed 16-bit none, full size, no sharpening | 내부/paired 용도 | opaque |

validation:

- DPI ≥ 0
- long edge nil 또는 > 0
- JPEG quality finite `0...1`
- sharpening finite `0...1`
- JPEG + preserve alpha 금지
- Raw TIFF는 16-bit, uncompressed, opaque, no sharpening, no resize

Windows WIC는 JPEG/PNG/TIFF native encoder와 high-bit-depth pixel formats를 제공한다. 그러나
`IWICBitmapFrameEncode::SetPixelFormat`은 요청한 format 대신 가장 가까운 supported format을 반환할 수
있다. 따라서 성공 HRESULT만 확인하지 않고 encoder가 돌려준 실제 pixel format, output file bit depth,
channel/alpha, ICC embedding을 read-back 검증한다.

WIC codec 교체·third-party codec runtime discovery는 결과 재현성을 흔들 수 있다. v1은 Windows built-in
encoder CLSID를 명시하고 OS build/codec identity를 manifest에 남긴다. 필요하면 검증된 bundled encoder를
도입하되 dependency/license 결정이 선행되어야 한다.

## 6. JPEG 품질과 chroma

macOS ImageIO 경로는 실측상 사용자가 `0.95` 이상을 고르면 encoder에 최소 `0.995`를 전달해 4:4:4를
유도한다. 이 임계값은 Windows WIC에 그대로 복사할 수 없다. encoder implementation과 option semantics가
다르기 때문이다.

Windows gate:

- quality curve와 실제 quantization/subsampling을 fixture로 조사
- 고품질 구간의 4:4:4 또는 동등한 chroma preservation을 bitstream parser로 확인
- macOS `0.95/0.995` 수치를 WIC에 가정하지 않음
- UI quality `1.0`의 시각/크기 결과를 golden으로 고정
- 4:2:0이 unavoidable한 경로는 사용자 선택 의미와 문서에 명시

JPEG는 8-bit quantization 직전에 deterministic dither를 적용한다. PNG/TIFF도 8-bit에서만 동일한
output dither를 쓰며 16-bit에는 적용하지 않는다.

## 7. color management

일반 output profile:

- sRGB
- Display P3
- Adobe RGB

Print target:

- exact user-selected printer-class RGB ICC snapshot
- profile name + profile bytes SHA-256
- working image에는 profile을 미리 적용하지 않고 final output transform/embedding에서 사용

Windows 후보 path:

```text
linear working pixels
→ validated ICC transform (WCS/ICM spike)
→ target integer/float pixels
→ WIC encoder
→ IWICColorContext / embedded ICC
→ read-back profile SHA and pixel verification
```

WCS/ICM `CreateMultiProfileTransform`은 ICC/WCS profile chain을 만들 수 있지만 WCS의 ICC 처리에는
profile class/color-space 제약이 있다. 다음 검증 전에는 ColorSync와 동등하다고 확정하지 않는다.

- ICC v2/v4 matrix/TRC/LUT RGB profiles
- relative/perceptual intent
- black point compensation 요구
- 16-bit precision과 round-trip
- malformed/profile-bomb rejection
- macOS ColorSync reference chart ΔE와 gradient/banding
- thread safety/transform cache

WCS가 품질/재현성 gate를 못 넘으면 검증된 ICC CMM 도입을 별도 dependency/license decision으로 한다.
WIC color context는 profile embedding을 담당할 수 있으나 pixel transform을 자동으로 정확히 수행했다는
증거로 간주하지 않는다.

## 8. resize와 output sharpening

순서:

```text
full-quality develop
→ optional print composition
→ long-edge downscale only
→ output sharpening
→ output color transform
→ bit-depth conversion + optional dither
→ encode
```

현재 macOS resize는 Lanczos이며 aspect를 유지하고 output dimension을 round한다. Windows D2D/WIC/GPU
resampler 후보는 impulse, slanted edge, moiré, alpha edge, extreme panorama fixture로 비교한다. 다른
resampler를 쓰더라도 승인된 품질 tolerance가 필요하다.

sharpening medium:

- Screen: radius 0.45, intensity base 0.22, reference 144 DPI
- Matte Paper: radius 1.00, intensity base 0.34, reference 300 DPI
- Glossy Paper: radius 0.75, intensity base 0.28, reference 300 DPI

effective DPI는 선택값, 0이면 medium reference다. resolution scale은 `0.5...2.0` clamp, radius에
sqrt scale을 적용하고 intensity는 base × strength다. Windows unsharp implementation이 Core Image와
다르면 kernel/border/alpha/linear-light 정의를 공통 engine spec로 고정한다.

## 9. metadata policy

정책:

- All
- Copyright Only
- Remove Location
- Minimal

의미:

| policy | source metadata | GPS/location | Negaflow-added technical metadata |
|---|---|---|---|
| All | 가능한 supported field 유지 | 유지 | 추가 |
| Remove Location | 유지 | GPS와 IPTC location 제거 | 추가 |
| Copyright Only | author/copyright/rights subset | 제거 | orientation 등 최소 |
| Minimal | source metadata 없음 | 제거 | 필요한 output facts만 |

source metadata input limits:

- string ≤ 4096 UTF-8 bytes
- array ≤ 128 entries
- finite numbers only
- integer array type 보존
- unknown/untrusted complex values drop

pixel transform이 이미 구워졌으므로 output orientation은 1이다. scanner make/model은 실제 persisted scan
session/job provenance가 하나로 확인될 때만 쓴다. 현재 선택 device를 추정해 넣지 않는다. imported
frame의 import timestamp를 EXIF capture/digitized time으로 쓰지 않는다.

`Remove Location`은 GPS dictionary만 지우는 것으로 끝내지 않고 IPTC city/sub-location/province/country
key도 제거한다. Windows WIC metadata query writer가 container마다 경로가 다르므로 policy별 실제 file을
ExifTool 같은 독립 inspector와 자체 decoder로 검증한다.

## 10. naming template

기본 pattern: `{name}`

token:

```text
{date} {roll} {frame} {name} {preset} {sequence}
{rollcode} {film} {camera}
```

규칙:

- pattern trim 후 최대 160 UTF-8 bytes
- unknown/unclosed brace는 invalid
- sequence/frame은 4자리 zero padding
- sequence start 최소 1
- token 값과 최종 결과 모두 filesystem-safe component로 sanitize
- final basename 최대 200 UTF-8 bytes
- empty result invalid
- date는 export batch 시작 date/time zone을 고정해 모든 item에 동일 day grouping
- localized UI label과 token literal은 분리; token은 migration 때문에 stable English identifier 유지

Windows sanitize는 다음을 추가 고려한다.

- `<>:"/\\|?*`, control chars
- trailing dot/space
- `CON`, `PRN`, `AUX`, `NUL`, `COM1...`, `LPT1...`
- case-insensitive collision
- Unicode normalization/case folding
- full path length와 extended path semantics

미리보기와 실제 planning은 같은 renderer를 사용한다.

## 11. output folder와 collision

실제 folder:

```text
<root>\<YYYY-MM-DD>\<source-group>\
```

source group은 imported folder name, scanner abbreviation 또는 default import group을 sanitize한 값이다.
폴더 생성 실패는 export 후반의 generic error로 숨기지 않고 root/volume diagnostics와 함께 즉시 표시한다.

unique basename은 primary만 확인하지 않는다.

- primary
- `-main-flat`
- `-original`
- `.negaflow.json`
- `.xmp`

모두 비어 있는 이름을 고른다. batch planner 내부의 이미 예약된 path와 disk existing path를 동시에
검사한다. Windows path 비교는 canonicalized path + existing file ID를 사용하고 symlink/reparse point,
hardlink, case-insensitivity를 고려한다.

어떤 output도 protected source 또는 다른 output과 동일 file을 참조할 수 없다. 기존 file을 overwrite하는
옵션은 v1에 두지 않는다.

## 12. Quick Export

목적은 화면 공유용 빠른 output이며 develop 품질 자체를 낮추지 않는다.

기본값:

- format JPEG
- JPEG quality `1.0`
- long edge `2048 px`
- DPI `150`
- PNG `8-bit`
- naming `{name}`
- sidecar/main-flat/original copy 없음

지원 format은 JPEG/PNG만이다. Quick Export는 full-quality develop 후 마지막 resize/encode 비용만 줄인다.
해상도, ICC, defect result, source verification을 우회하지 않는다. 일반 Export 설정과 별도 persistence를
쓴다.

## 13. recipe presets

Export recipe v1은 다음을 저장한다.

- format
- `ExportOptions`
- write sidecar
- write main-flat
- write original raw
- filename template

recipe identity:

- optional preset UUID/name
- canonical configuration SHA-256
- Print target이면 output ICC SHA도 configuration identity에 포함

recipe name은 trim 후 최대 80 characters이며 empty/duplicate 정책을 store에서 검증한다. selected recipe를
적용하면 UI settings를 한 번에 바꾸고, 이후 수동 변경이 recipe와 달라졌는지 dirty indicator를 제공하는
것을 후보로 두되 현재 동작 확인 없이 추가하지 않는다.

recipe file은 app-owned, versioned, atomic이고 invalid file을 empty recipe list로 조용히 치환하면서 기존
파일을 덮지 않는다.

## 14. immutable export snapshot

snapshot 필수 field:

- raw source URL + byte identity + stat/file identity
- source kind
- cleaned memory/disk cache + defect identity + `requiresCleanedRaw`
- output artifact layout
- format/options/output ICC
- film type/effective develop parameters/image transform/base
- scanner/scan-session provenance
- source bit depth/pixel size/DPI
- preset/scanner profile/crop
- virtual copy/rating/pick/history/snapshots
- app metadata overlay + source metadata identity
- app/renderer version
- export recipe identity
- print composition if any
- verification level

preset overrides, frame film type, develop target와 image transform을 snapshot 값으로 materialize한다. UI model
object를 background worker에서 다시 읽지 않는다.

## 15. source generation verification

최초 capture:

1. file identity before
2. full byte SHA-256 + byte count
3. file identity after
4. before == after일 때만 valid

Windows file identity에는 가능한 경우 volume serial + file ID, size, last-write/change metadata를 포함한다.
`standard`는 최초 full hash 뒤 file identity가 그대로면 recheck hash를 생략하고, 하나라도 다르면 full
hash한다. `strict`는 모든 gate에서 full rehash한다. 두 mode 모두 journal artifact identity는 실제
SHA-256이다.

network/removable/cloud placeholder에는 local NTFS identity 가정이 성립하지 않을 수 있다. provider별
identity 불확실 시 strict 또는 staged source copy를 쓴다.

39장 같은 batch의 source hash는 bounded concurrency(현재 macOS 후보 최대 4)로 capture한다. disk를
과포화하거나 UI MainThread에서 hash하지 않는다.

## 16. defect-required export

Raw TIFF를 제외한 output에서 enabled strength > epsilon defect layer가 하나라도 있으면
`requiresCleanedRaw = true`다.

입력 우선순위:

1. identity-matched cleaned memory image
2. identity-matched app-owned cleaned disk cache
3. source + persistent defect recipe full rebuild

어느 것도 가능하지 않으면 load/render error다. source raw로 fallback 금지. cleaned identity의 bound source
SHA/byte count가 snapshot source identity와 일치해야 한다.

Raw TIFF는 defect/develop을 적용하지 않고 source artifact 의미를 지키며, resize/sharpen/profile을 금지한다.

## 17. develop/render pipeline

```text
snapshot validation
→ source access/materialization
→ source generation recheck
→ cleaned raw resolution if required
→ source decode in correct orientation/color semantics
→ film-base estimate or validated cached base
→ full-quality develop
→ optional main-flat render
→ optional print composition
→ resize/sharpen/color/quantize
→ encode artifacts in staging
→ render manifest/sidecars
```

TIFF 16-bit처럼 exact full-resolution format은 decode proxy를 사용하지 않는다. 다른 format도 proxy가
quality-equivalent final decode라는 검증 없이는 long-edge convenience를 이유로 upstream quality를
낮추지 않는다.

base estimate를 frame cache에 되돌려 넣을 때 snapshot base key, source generation, current frame ownership와
develop tracking identity가 모두 같아야 한다.

## 18. artifact set

선택 가능한 final layout:

```text
<name>.<ext>                  primary
<name>-main-flat.<ext>        optional
<name>-original.<source-ext>  optional exact source copy
<name>.negaflow.json          optional technical sidecar
<name>.xmp                    optional XMP representation
```

Main Flat은 film/base/geometry를 보존하지만 creative adjustments를 중립화한 `developTarget = main` 결과다.
Original copy는 snapshot source bytes와 identity가 같아야 하며 re-encode하지 않는다. JSON/XMP는 output
history, develop state, profile/provenance/manifest를 담되 source 옆 third-party XMP를 수정하지 않는다.

## 19. staging과 publish

frame transaction:

1. transaction UUID 발급
2. final output과 같은 volume/root 아래 owned staging directory 생성
3. owner marker + preparation journal durable write
4. 모든 artifact를 staging에 생성
5. regular file, size > 0, format/decode/identity/manifest 검증
6. final destinations가 비어 있고 source와 distinct인지 재검사
7. preparation journal을 full artifact journal로 promote
8. exclusive rename/move로 각 artifact publish
9. final artifact identity 재검증
10. catalog commit intent 기록
11. catalog commit attempted 기록 직후 durable catalog write
12. success event commit 결과 처리
13. journal committed 표시 후 제거

staging을 `%TEMP%`에 두고 다른 volume으로 copy하면 atomic rename 보증이 사라진다. final directory 내부의
숨김 owned staging 또는 같은 volume의 app-owned sibling을 사용한다.

Windows 파일 publish는 `CREATE_NEW`/exclusive semantics로 existing destination을 절대 대체하지 않는다.
SMB/FAT/exFAT/OneDrive의 rename/durability 차이는 실제 volume matrix에서 검증한다.

## 20. commit journal과 crash recovery

journal은 단순 temp cleanup list가 아니다. artifact byte identity와 transaction state를 가진다.

state:

```text
preparation
→ published
→ catalogCommitIntent
→ catalogCommitAttempted
→ committed

recovery branches:
preserveArtifacts / rollbackIntent
```

복구 원칙:

- app-owned staging owner marker와 identity가 맞을 때만 staging 삭제
- uncommitted final도 journal identity와 file ownership proof가 맞을 때만 자동 rollback
- catalog write를 시도했지만 결과가 불명확하면 artifact를 자동 삭제하지 않음
- catalog에 success event가 있으나 artifact integrity를 확인 못하면 Library를 block
- user가 파일을 바꾼 path는 삭제/덮기 금지
- unsupported/corrupt journal을 무시하고 계속 열지 말고 bounded recovery surface 제공

catalog commit이 실패했는데 rollback도 실패하면 `indeterminate`다. 성공처럼 보고하지 않고 Library
persistence를 block하여 다음 사용이 inconsistent state를 확대하지 않게 한다.

## 21. batch planning과 scheduling

selection의 ordered projection을 한 번 snapshot한다. sequence는 `max(1,start)+offset`이다. 모든 output
path를 batch 시작 전에 계획하고 batch 내부 collision을 예약 set으로 막는다.

현재 scheduler:

- 최대 동시 frame 2
- shared cursor dynamic scheduling
- 느린 item이 자기 자신만 점유하고 다른 worker의 미래 item을 예약하지 않음
- source materialization을 batch 앞에서 한 구간으로 모음

Windows concurrency는 고정 2를 출발점으로 하되 RAM/VRAM, source storage, codec 특성을 측정해 bounded
adaptive 값을 검토한다. 무제한 `Task.WhenAll` 금지.

## 22. pause, cancel, retry

item state:

- queued
- running
- succeeded
- failed(message)
- cancelled

Pause는 새 item scheduling을 멈추며 이미 running transaction의 중간 cancel을 의미하지 않는다. Cancel은
queued를 cancelled로 바꾸고 waiting worker를 풀어 종료한다. running item의 cooperative cancellation
범위는 transaction atomicity와 함께 명시한다. publish 이후 catalog commit 중간을 임의 cancel하지 않는다.

Retry Failed/Cancelled:

- succeeded item 유지
- retry item은 disk와 reserved paths를 다시 확인해 fresh unique URL 계획
- 동일 plan ID/state mapping 유지
- 새 checkpoint를 durable write한 뒤 실행

## 23. batch checkpoint

batch 시작 전에 plan + item state를 app-owned checkpoint에 저장한다. 저장 실패 시 UI batch begin을
rollback한다. 각 running/finished/pause/cancel 전환 뒤 checkpoint를 갱신한다.

재시작:

- succeeded artifact/journal/catalog event reconcile
- running은 transaction journal 상태에 따라 succeeded/failed/cancelled/recoverable 판정
- queued/cancelled/failed를 사용자에게 Resume/Retry로 제공
- source/profile/recipe identity가 달라졌으면 기존 plan을 자동 실행하지 않음

retryable item이 없으면 checkpoint를 제거한다. checkpoint 손상은 빈 batch로 덮지 않고 recovery/backup을
유지한다.

## 24. progress UX

표시:

- finished / total
- percent
- failure count
- Pause/Resume/Cancel
- 완료 뒤 Retry Failed
- per-item name/state/error/output path를 확장 surface에서 확인 가능

overall progress를 frame count만으로 계산하는 현재 UI는 단순하고 안정적이지만 첫 frame 준비 중 0%에서
멈춘 것처럼 보일 수 있다. Windows는 기능을 바꾸지 않는 범위에서 phase를 분리한다.

```text
Preparing sources
Preparing item i/N
Developing
Encoding
Publishing
Recording catalog
```

frame count와 current phase를 함께 표시한다. fake continuous percent를 만들지 않는다. 취소 요청과 실제
중단 완료를 구분한다.

## 25. reveal

Reveal은 root가 아니라 실제 `<date>/<source-group>` folder를 Explorer에서 연다. 경로가 아직 없거나
removable volume이 빠졌으면 nearest existing root 또는 구체적 오류를 보여준다. Windows Shell API를
사용해 item selection이 가능하면 마지막 primary output을 선택한다.

## 26. 성능과 품질

독립 span:

- plan/naming/collision
- source materialization/hash
- cleaned raw resolution/rebuild
- decode
- develop
- composition/resize/sharpen/color transform
- quantize/dither
- encode per artifact
- sidecar/manifest
- staging validation
- publish
- catalog commit

성능 기준은 실제 loaded 24/60/100+ MP와 large virtual batch를 모두 쓴다. Quick Export도 Library/Develop
toolbar와 Output/Print 진입 경로를 모두 검증한다. JPEG quality, bit depth, DPI, ICC, defect, resize를
몰래 낮춰 속도를 만들지 않는다.

memory:

- whole batch full-resolution images를 동시에 retain하지 않음
- bounded decode/render workers
- format encoder streaming/tile 가능성 조사
- artifact별 temp buffer 즉시 release
- 16-bit 100+ MP의 peak committed/private/VRAM 측정

## 27. 검증

각 output read-back:

- expected file type/magic
- width/height
- bit depth/channels/alpha
- ICC profile presence + SHA/name/class
- DPI
- orientation 1
- metadata policy
- primary/main-flat/original/sidecar manifest pairing
- nonzero size + decode success
- SHA-256 identity

quality fixture:

- color chart and gradients
- saturated fine color detail/JPEG chroma
- alpha edges
- resize slanted edge/moire
- output sharpening by medium/DPI
- ICC v2/v4 and malformed profiles
- source with GPS/IPTC/copyright/mixed metadata
- defect-required reconstruction

## 28. 접근성

- File/Quality/Source는 selection container
- format/bit depth/compression/metadata/medium은 named controls
- disabled option은 이유 제공
- naming error/preview를 text와 live validation으로 노출
- path는 middle ellipsis 시 full tooltip/accessible value
- Export count를 accessible name에 포함
- batch progress는 determinate progress + text
- failure count와 per-item error를 Narrator로 탐색 가능
- Pause/Resume/Cancel/Retry state가 자동화 tree에 즉시 반영
- color space/profile warning을 색만으로 표시하지 않음

## 29. 출시 gate

- all UI settings round-trip/persist와 recipe apply 일치
- Quick Export 기본과 사용자 저장값 migration 일치
- WIC 요청 pixel format과 실제 output bit depth 검증
- ICC transform/embedding이 reference tolerance 통과
- source 또는 기존 output overwrite 0
- active defect result 누락 export 0
- multi-artifact partial publish가 success로 기록되지 않음
- kill-at-every-transaction-step crash recovery 통과
- batch pause/cancel/retry/checkpoint/restart 통과
- x64/ARM64, Intel/AMD/NVIDIA/Qualcomm/WARP에서 engine result 의미 동일
- NTFS, removable exFAT, OneDrive placeholder, read-only/full disk/long path 검증
- actual 39-frame single/contact-sheet 관련 workflow에서 first-file phase와 progress가 정확함
