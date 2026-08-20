# Defect Removal surface·recipe·cache 이식 명세

기준일: 2026-08-04  
macOS 기준 커밋: `9be909c`  
소스 근거: `Features/Defects`, `Features/Develop/Inspector/Tools/DefectControlsSection.swift`,
`Chromabase/DefectRemoval`

## 1. 절대 원칙

Windows판 결함 제거는 항상 비파괴다.

```text
immutable source bytes
+ ordered defect recipe
→ rebuildable cleaned-raw cache
→ develop pipeline
→ preview/export/print
```

금지:

- `ScanFrame.rawScanURL`이 가리키는 파일을 제자리 교체
- imported/scanned source를 종료 시 cleaned result로 덮어쓰기
- third-party `.xmp`에 Negaflow recipe 기록
- recipe가 사라졌는데 cleaned cache만 source처럼 승격
- cleaned raw를 원본이라고 표시
- RGB Software Defect Removal을 IR/Digital ICE와 동등하다고 표시
- IR channel capability를 scanner 모델명으로 추정

app-owned sidecar가 authoritative이며 cleaned-raw TIFF/tile cache는 언제든 지울 수 있는 파생물이다.
캐시 재생성 실패 시 원본으로 조용히 fallback해 defect result가 있는 것처럼 export하지 않는다.

## 2. macOS 현재 코드와 Windows 기준의 충돌

`Features/Defects/Workflow/AppModel+DefectBakeOnQuit.swift`는 현재 종료 시 적용된 defect result를
scanner TIFF에 제자리 교체하거나 앱 소유 copy로 relink한 뒤 recipe/history를 폐기한다. 같은 저장소의
data-safety invariant와 sidecar v2 주석은 source와 third-party XMP를 절대 수정하지 않는다고 명시한다.

Windows 이식 결론:

- 종료 bake 경로를 복제하지 않는다.
- source immutable + persistent recipe + rebuildable cache를 기준으로 한다.
- macOS parity baseline을 고정할 때 이 차이를 `P0 data-safety correction`으로 등록한다.
- 향후 macOS가 어느 계약으로 정리되더라도 Windows source overwrite를 허용하는 방향으로 맞추지 않는다.

이것은 시각적 platform delta가 아니라 원본 보존 계약이다.

## 3. 사용자 도구 모델

| 도구 | 입력 | 검출 | 결과 recipe item |
|---|---|---|---|
| Auto | 전체 frame | RGB software detector | `automatic region` |
| Guided | 사용자가 그린 ROI | RGB software detector | `guided region` |
| Brush | 사용자가 칠한 stroke | 없음, heal brush | `brush` |
| Clone Stamp | source point + target stroke | 없음, exact source clone | `clone` |
| Infrared | scanner plugin의 IR plane | IR detector | `infrared clusters` |

Auto, Guided, Brush, Clone Stamp와 Base/Crop/Local Adjustment drawing은 동시에 하나만 active다.
IR clean은 scan completion 뒤 background operation일 수 있지만 같은 frame recipe commit gate를 통과한다.

## 4. 용어

- `draft`: 아직 recipe에 commit되지 않은 stroke/ROI/source point
- `detection session`: Auto/Guided 검출 결과와 excluded set
- `DefectEditItem`: ordered recipe의 한 layer
- `DefectRecipeSnapshot`: frame ID, revision, identity, validated items
- `cleaned raw`: source에 enabled recipe items를 순차 적용한 파생 pixel result
- `patch`: strength 1.0으로 계산된 dirty-region 결과
- `preview`: 검출 component 위치를 그리는 가벼운 normalized points
- `reviewed`: 특정 source identity + recipe revision/SHA 조합에 대한 사용자 검토 완료

## 5. Auto

진입 즉시 normalized display ROI `(0,0,1,1)`로 검출한다. Auto mode는 단순히 full-size Guided ROI가
아니다. detector에 `wholeFrameAuto = true`를 전달해 보수 검출과 구조선 보호 규칙을 활성화한다.

상태:

```text
Off
→ Detecting full frame
→ Preview results / false-positive warning / no defects / failure
→ user include-exclude edits
→ Removing
→ Layer committed + cleaned raw visible
```

Auto sensitivity와 micro-speck 설정은 Guided와 별도로 저장한다.

- UI sensitivity range: `0.7...6.0`
- 기본 UI 값: `6.0`
- detector mapping: range를 `0...1`로 normalize
- scratch sensitivity: normalized + `0.1`, 단 maximum `1.0`
- micro-specks의 frame 시작 기본값은 settings에서 가져오며 기존 legacy single setting을 migration

whole-frame false-positive risk가 감지되면 결과를 자동으로 줄이지 않고 경고한다. 사용자가 component나
class를 제외한 뒤 commit한다.

## 6. Guided

진입만으로 검출하지 않는다. Canvas에서 ROI를 drag한다.

- click/짧은 drag `<6 effective px`: 결과가 있으면 component include/exclude toggle
- ROI drag: 최소 normalized width/height `>0.012`
- 새 ROI를 그리면 이전 detection task를 cancel하고 revision을 올린다.
- sensitivity/micro-specks 변경을 마치면 동일 base ROI를 새로 검출한다.
- 재검출 시 현재 excluded component IDs는 위치 재매칭 없이 초기화되는 것이 현 macOS 동작이다.

Windows에서 제외 상태를 자동 보존하려면 component matching algorithm과 acceptance가 필요하다. 근거 없이
추가하지 않고 현재 동작을 기본 parity로 둔다.

## 7. detection preview

표시 요소:

- detecting progress와 상태
- detected total / excluded count
- automatic false-positive warning
- sensitivity
- micro-specks toggle
- Cancel
- Remove
- defect class chips
- component overlay

분류:

- dust
- pinhole
- horizontal scratch
- vertical scratch
- diagonal scratch
- emulsion damage
- micro speck

class chip은 localized name, count, mean confidence, all-excluded state를 표시한다. 화려한 색 배경 대신
작은 classification marker + text를 쓰고, excluded는 opacity/취소선/상태 text를 함께 써서 색만으로
의미를 전달하지 않는다.

component click은 display point를 base point로 inverse-transform하고 ROI-local pixel로 바꾼 뒤 가까운
component ID를 찾는다. hit radius는 현재 `max(3, field.width / 100)`이다. Windows engine/UI가 다른
downsample을 쓰더라도 같은 selected component가 나오도록 fixture를 둔다.

## 8. detection concurrency

요청 identity:

```text
FrameId
DefectDetectRevision
CleanedRawRevisionAtStart
SourceIdentity
ImageTransform
DisplayROI
BaseROI
Mode
Sensitivity
MicroSpecks
CancellationToken
```

commit 전 조건:

- frame이 catalog/model에 여전히 소유됨
- detect revision 동일
- cleaned-raw revision 동일
- source identity 동일
- task가 취소되지 않음

detect 중 기존 defect layer 결과가 바뀌면 입력 base가 낡았으므로 session을 clear한다. 이전 detection을
현재 image 위에 그리지 않는다.

첫 Guided ROI는 필요한 ROI만 materialize해 빠르게 반환할 수 있다. 이후 재검출/commit용 full session
raw는 background에서 한 번 준비하되 완료 직전에 session/revision을 검사한다. source가 큰 경우에도
첫 작은 ROI가 full-frame decode 완료를 기다리지 않는 것이 목표다.

## 9. detection commit

Remove는 excluded가 아닌 component가 하나 이상일 때만 enabled다. 실행 시:

1. current detect revision을 capture한다.
2. survivor components의 bbox를 계산한다.
3. dilation + `SoftwareDefectRemoval.repairContextRadius` 여백을 더한다.
4. 해당 window만 RGBA8 mask로 render한다.
5. bounded compression을 적용한다.
6. class breakdown와 lightweight preview points를 만든다.
7. Main/UI actor에서 ownership/revision/removing state를 다시 확인한다.
8. Auto 또는 Guided label로 recipe item을 append한다.
9. cleaned raw를 rebuild하고 첫 visible develop result가 나온 뒤 session/progress를 닫는다.

전체 ROI 크기의 mask를 무조건 저장하지 않는다. 비용과 memory가 defect bbox에 비례해야 한다. survivor가
없는 방어 경로에서는 commit 대신 cancel이 기본이다.

## 10. Brush

Canvas draft:

- thickness 초기값 현재 `0.010` normalized display-relative
- stroke points는 display normalized로 수집
- Apply 때 transform inverse로 base normalized points로 바꿈
- draft가 비면 Apply disabled
- Undo는 draft stroke가 있으면 마지막 draft만 제거하고, 없으면 committed defect history를 undo
- Clear Draft와 Reset All Applied Defects를 구분

Brush recipe item은 stroke group 하나다. heal algorithm은 source detail을 보존할 유효 sample을 찾지
못하면 가짜 smear로 성공시키지 않아야 한다. crop/rotate/zoom 이후에도 base coordinates를 통해 같은
source pixels에 적용한다.

pointer events는 충분히 resample/coalesce하되 품질을 바꾸지 않는다. 높은 polling-rate mouse/pen에서
백만 point가 생기지 않도록 geometric tolerance를 정의하고 sidecar limits와 함께 fuzz한다.

## 11. Clone Stamp

interaction:

- macOS Option-click → Windows `Alt+click` 후보로 source 지정
- 새 source를 지정하면 aligned offset을 초기화
- 첫 target stroke가 `source - target` offset을 확정
- 이후 stroke는 같은 offset을 유지
- drag 중 source pixels를 target stroke 안에 preview
- cursor 위치와 대응하는 source crosshair 표시
- size `4...512 px`, 초기 `48 px`
- hardness `0...1`, 초기 `0.5`
- Undo는 통합 defect history

Windows에서 Alt가 메뉴 access key를 활성화할 수 있으므로 실제 WinUI input test를 거쳐 `Alt+click`을
확정한다. 충돌하면 명시적인 `Set Source` mode/shortcut를 platform delta로 승인한다.

recipe:

- normalized base points
- normalized source offset x/y
- physical source-pixel diameter
- hardness

engine은 offset을 source pixel grid에 round하고, source가 image 밖인 pixel은 무변경으로 둔다. 자기
자신으로의 zero offset은 무변경이다. dirty bbox만 render하고 source/destination window의 동일 index를
linear working space에서 alpha composite한다.

## 12. Infrared

IR은 scanner plugin이 full scan 결과로 명시적으로 제공한 IR file/plane이 있을 때만 가능하다.

자동 적용 gate:

- 현재 코드: `colorNegative`만 supported
- `colorPositive`: 검증되지 않아 fail closed
- `bwNegative`, `bwPositive`: silver grain이 IR을 막을 수 있어 fail closed
- unknown film: fail closed
- 동일 frame에 IR layer가 이미 있으면 중복 적용하지 않음

검출 단계:

1. raw와 IR plane decode
2. 크기가 다르면 검증된 resampling policy
3. IR↔raw alignment 추정
4. scene leakage 보정
5. dark border/margin 제외
6. component/classification/cluster mask 생성
7. coverage/alignment safety gate
8. cluster recipe item append

failure는 구분한다.

- no defects
- cancelled
- unreadable
- too small
- alignment unreliable
- coverage too high

IR session은 `owner + frame ID + monotonically increasing session revision` token을 쓴다. 재실행은 이전
task를 취소하고 삭제/취소/새 session 뒤의 늦은 결과를 버린다.

제품 copy:

- plugin/장치가 실제 IR channel을 제공한 경우에만 `Infrared`라고 표시
- RGB path는 `Software Defect Removal` 또는 승인된 제품명
- `Digital ICE`는 타사 상표·특정 하드웨어 기술과 혼동될 수 있으므로 generic 기능명으로 쓰지 않음

## 13. ordered layer model

recipe item kind:

- brush
- region
- infrared
- clone

공통 field:

- stable UUID
- enabled
- strength `0...1`
- value-based localized label source
- value-based summary source
- base size
- lightweight preview
- runtime-only cached patches

cleaned raw는 enabled이고 strength가 유효한 item을 배열 순서대로 적용한다. 순서를 바꾸면 pixel 결과가
달라질 수 있으므로 v1에 reorder UI를 추가하지 않는다. 향후 reorder를 넣으면 명시적 recipe revision과
cache invalidation이 필요하다.

label 문자열을 sidecar에 고정 저장하지 않는다. `automatic(count)`, `guided(count)`, `brush(strokes)`,
`clone(diameter)`, `infrared(count)` 같은 value를 저장하고 현재 app language로 표시한다.

## 14. layer UI

layer가 있을 때만 section을 보인다.

- header: Defect Layers + count
- 5개까지 그대로 표시, 초과 시 약 5행 높이 scroll
- 새 layer append 후 최신 항목으로 scroll
- row: index, enabled, kind icon, localized title, mask show/hide, delete
- summary: class count/mean confidence 또는 brush/clone summary
- strength slider `0.1...1.0` UI 범위
- disabled layer opacity와 명시적 state
- build 중 destructive controls disabled
- 현재 source+recipe identity가 review되지 않았다면 Done/Review action

strength domain은 storage에서 `0...1`, 현재 UI에서 `0.1...1.0`이다. `0`은 disable과 의미가 겹치므로
UI가 0.1을 최소로 둔 현재 차이를 보존한다. API로 0이 들어오면 valid하지만 visible slider round-trip
정책을 테스트해야 한다.

Mask preview는 selected layer ID로 하나만 보이며 layer 삭제/undo 시 ID가 사라지면 자동 clear한다.

## 15. layer edit, undo와 rebuild

각 명령은 recipe snapshot을 먼저 만들고 실패 시 상태를 rollback한다.

- append: 이전 snapshot을 undo stack에 push
- enabled toggle: snapshot push, changed layer 뒤 patch cache invalidate
- delete: snapshot push, 해당 item 제거
- strength drag: 시작 때 snapshot 1회 push, live update coalesce, 종료 때 disk commit
- clear all: snapshot push 후 모든 item 제거
- reset brush/region/clone: 해당 kind만 제거; 다른 kind 유지
- undo: 마지막 full recipe snapshot 복구

현재 별도 redo stack은 관찰되지 않는다. Windows가 redo를 추가하려면 전체 app command model과 sidecar
revision 규칙을 함께 정의해야 하므로 첫 parity 범위에서는 임의 추가하지 않는다.

## 16. live strength

현재 의도:

- 약 25Hz single worker
- drag tick마다 task 생성 금지
- latest generation만 snapshot/hash/rebuild
- live 중 disk persistence 생략
- spinner/status 억제
- drag 종료에서 worker 취소 후 현재 값 한 번 확정 및 disk persist
- drag 전체 undo 1회

Windows 구현은 UI thread에서 canonical serialization/SHA를 하지 않는다. 변경 즉시 old identity를
현재 result로 오인하지 않도록 fail closed하고, 새 identity가 준비되기 전 export 요청은 pending 또는
명시적 block 상태로 둔다.

## 17. cleaned-raw build

### 17.1 full rebuild

```text
source bytes
→ validate source identity
→ decode RGBA16 linear working image
→ ordered enabled layers
→ per-layer dirty patches
→ one final composited surface
→ identity-bound cache
→ develop
```

### 17.2 incremental append

메모리 cleaned base의 applied stamps가 current recipe prefix와 정확히 같으면 새 suffix만 적용한다. 메모리
base가 없고 app-owned disk cache identity가 이전 recipe와 같으면 disk base에서 한 item을 증분 적용할
수 있다. 어느 identity라도 불확실하면 source에서 full rebuild한다.

### 17.3 last-layer fast edit

마지막 layer의 직전 base와 strength-1 patch가 살아 있으면 enabled/strength/delete를 patch composite만으로
즉시 반영할 수 있다. 앞선 layer가 바뀌면 이후 patch cache는 모두 무효다.

### 17.4 commit gate

build 전후 source SHA/byte count가 같고 다음이 일치해야 한다.

- frame ownership
- clean raw revision
- recipe identity
- source identity
- cancellation state

일치하지 않으면 visible/cache/persistence에 commit하지 않는다.

## 18. Windows CPU/GPU 구현 전략

첫 정확성 기준은 deterministic CPU path다.

- detector/classifier/morphology/alignment의 scalar reference
- x64 AVX2/FMA와 ARM64 NEON은 측정된 hot loop만 runtime dispatch
- tile/ROI parallelism은 bounded worker pool
- mask/patch dimensions와 multiplication overflow 사전 검증
- cancel check를 tile/component/phase 경계에 배치

D3D11 compute 후보:

- large convolution/morphology
- mask dilation
- patch compositing
- color/plane preprocessing

CPU에 남길 후보:

- connected-component metadata와 small irregular control flow
- canonical recipe serialization/hash
- filesystem identity/sidecar IO
- 작은 ROI/patch는 GPU dispatch overhead와 비교 후 선택

GPU vendor별로 detection threshold/connected components 순서가 달라지면 recipe 결과가 달라질 수 있다.
첫 구현에서는 detector truth를 CPU로 고정하고 repair/composite부터 GPU화하는 것이 보수적이다. GPU
detector는 fixture에서 component set/classification/confidence 허용오차를 통과한 뒤 opt-in한다.

CUDA는 필요하지 않다. NVIDIA-only 가속을 추가해도 D3D11/CPU가 모든 기능과 동일 품질을 제공해야 하며,
recipe 형식이 CUDA 결과에 종속되면 안 된다.

## 19. sidecar 위치와 포맷

macOS 현재 canonical sidecar는 app support 아래 `negaflow/defects/<frame-uuid>.plist` binary plist v2다.
Windows 권장 위치:

```text
%LOCALAPPDATA%\Negaflow\Catalogs\<catalog-id>\Defects\<frame-id>.nfdrecipe
```

확장자는 제품 결정이며 source 옆에 쓰지 않는 것이 중요하다. 파일은 catalog ID와 frame ID로 namespace해
다른 catalog의 같은 UUID/restore가 충돌하지 않게 한다.

Windows 포맷 후보:

- deterministic binary container + versioned metadata
- JSON manifest + individually compressed binary mask chunks

binary plist를 그대로 채택할 이유는 없다. macOS↔Windows catalog 이동이 목표라면 공통 canonical schema와
golden codec을 따로 설계한다. C# JSON default와 Swift Codable이 field omission/float/UUID를 다르게
인코딩하므로 hash 입력은 별도 canonical binary 또는 엄격한 canonical JSON 규칙을 쓴다.

## 20. recipe v3 권장 identity

현재 macOS fingerprint v2는 mask의 content bytes 대신 item UUID, shape와 stored byte count를 hash한다.
프로세스 내 immutable item 가정에는 빠르지만 장기 persistent sidecar의 bit corruption/tampering을
recipe SHA 하나로 검출하지 못할 수 있다. Windows persistent recipe에는 다음 v3를 권장한다.

```text
RecipeIdentity {
  schema_version
  fingerprint_version
  catalog_id
  frame_id
  monotonic_revision
  source_byte_count
  source_sha256
  canonical_metadata_sha256
  each_blob_sha256[]
  recipe_root_sha256
}
```

mask blob hash는 저장 시 한 번 계산하고 매 slider drag에 수십 MB를 다시 hash하지 않는다. immutable
blob content-address로 재사용하고 item metadata hash만 갱신한다. read/load에서는 blob 길이, decompression
limit, SHA를 모두 검증한다.

## 21. sidecar write ordering

같은 catalog/frame sidecar write는 직렬화한다.

- atomic temp/write-through/rename 또는 Windows의 안전한 replace 패턴
- write 뒤 decode/identity read-back validation
- disk revision > request revision이면 `skipped newer`
- same revision + same snapshot이면 `already current`
- same revision + 다른 recipe면 conflict
- legacy writer가 v2/v3/future document를 downgrade하지 않음
- unsupported/invalid/unreadable 기존 문서를 조용히 덮지 않음
- 실패 시 이전 valid bytes 복원 또는 그대로 유지
- revision-aware delete로 늦은 낮은 revision write가 파일을 되살리지 못함

Windows의 file replace semantics와 antivirus/indexer/share violations를 fault injection으로 검증한다.
`FlushFileBuffers`/directory durability 필요 수준은 catalog durability 문서에서 결정한다.

## 22. resource limits와 untrusted input

sidecar는 app-owned라도 disk corruption, old version, sync conflict를 untrusted input으로 취급한다. 현재
macOS standard cap은 Windows 초기값 참고다.

| resource | current cap |
|---|---:|
| file bytes | 128 MiB |
| items | 4,096 |
| strokes per item | 50,000 |
| strokes per recipe | 100,000 |
| points per stroke | 1,000,000 |
| points per recipe | 5,000,000 |
| preview components per item | 100,000 |
| preview points per recipe | 5,000,000 |
| clusters per item/recipe | 100,000 / 100,000 |
| mask pixels per mask | 100,000,000 |
| total decompressed bytes | 512 MiB |

모든 합/곱은 overflow-aware다. 압축 데이터는 output cap을 적용한 streaming decoder로 풀고 정확히
`width × height × 4`인지 검사한다. zlib bomb, truncated stream, zero-progress decoder, negative/zero
dimension, NaN/Infinity, invalid UUID/hash를 거부한다.

Windows cap은 100+ MP scan/다중 layer fixture를 근거로 조정하되 무제한으로 올리지 않는다. x64와 ARM64
동일 cap을 기본으로 하고 low-memory device에서는 작업 거부/타일링을 명시한다.

## 23. cleaned-raw cache

위치 후보:

```text
%LOCALAPPDATA%\Negaflow\Cache\<catalog-id>\CleanedRaw\
```

규칙:

- app-owned root와 exact filename grammar 검증 뒤에만 삭제
- source/path와 같은 directory에 두지 않음
- cache file은 frame ID, source identity, recipe identity, pixel format, dimensions, engine version을 가짐
- loss는 recipe 손실이 아님
- memory residency eviction은 disk recipe를 지우지 않음
- disk cache identity가 맞지 않으면 사용하지 않고 삭제 후보로 격리
- custom cache folder가 cloud/remote/removable일 때 성능·availability warning
- test process는 사용자 custom folder를 사용하지 않고 격리 temp root
- cache cleanup이 source 또는 third-party sidecar에 도달할 수 없는 path proof

full-frame TIFF 하나가 최종 포맷일 필요는 없다. 100+ MP와 많은 patch에는 tiled, checksummed cache가
decode/partial access에 유리할 수 있다. 품질과 crash recovery benchmark 후 선택한다.

## 24. source relink와 identity mismatch

source identity는 path와 무관한 최소 `byteCount + SHA-256`이다.

- 같은 bytes가 새 path로 relink되면 recipe 재결합 가능
- path가 같아도 bytes가 달라지면 기존 cleaned cache/patch/review receipt 폐기
- recipe는 orphaned/mismatch 상태로 보존하여 사용자가 원본을 다시 찾을 수 있게 함
- 다른 bytes에 recipe를 자동 적용하지 않음
- user-approved rebinding 기능을 만들더라도 visual compare와 새 identity/revision을 요구

hash는 background에서 계산하고 large source의 repeated full hash를 stable file identity/mtime/size cache로
최적화할 수 있지만, 최종 commit/write/export 경계에서는 content identity를 확인한다.

## 25. review receipt

Done은 단순 boolean이 아니다.

```text
ReviewedReceipt {
  reviewed_recipe_revision
  reviewed_recipe_sha256
  reviewed_source_identity_sha256
  reviewed_at
  reviewer_kind = user
}
```

recipe나 source가 바뀌면 자동으로 unreviewed다. reviewed 표시가 stale이면 안 된다. 이는 향후 자동 안전
gate와 export warning에 사용할 수 있지만 user 승인 없이 export를 강제 차단하는 새 정책은 추가하지 않는다.

## 26. export/print 계약

export/print snapshot 시점에:

1. current recipe identity 고정
2. source identity 확인
3. matching cleaned memory/disk cache 사용 또는 source+recipe에서 rebuild
4. 완료 result identity 확인
5. develop/export pipeline 실행

required defect result를 reconstruct할 수 없으면 해당 item을 명시적으로 실패시킨다. 원본으로 export하고
성공으로 보고하지 않는다. 여러 frame batch에서는 success/failure를 개별 기록한다.

## 27. 오류·복구

| 실패 | 처리 |
|---|---|
| detector cancelled | session transient state clear, recipe 불변 |
| detector failed | ROI/result 유지 정책에 따라 retry, success 표시 금지 |
| no selectable components | Remove disabled/cancel |
| mask compression failed | recipe append 금지, detection preview 유지 |
| recipe validation failed | UI mutation rollback, 기존 identity 유지 |
| sidecar write failed | unsaved badge + retry, cleaned result만 성공처럼 유지하지 않음 |
| source mismatch | caches invalidate, recipe orphan/mismatch, Relink |
| cleaned build failed | previous valid result + error 또는 block, raw fallback 은 명시 |
| GPU OOM/device lost | tile/CPU rebuild, quality 저하 금지 |
| cache corrupt/missing | authoritative recipe에서 rebuild |
| future sidecar version | raw bytes 보존, downgrade/overwrite 금지 |

## 28. performance 계측

독립 span:

- source identity
- source decode/materialization
- ROI transform/materialization
- detector preprocessing
- component detection/classification
- preview point build
- mask window build/compression
- recipe canonical/hash/write
- patch compute
- patch composite
- cleaned surface commit
- first visible developed result
- disk cache persist
- export reconstruction

사용자 체감 지표는 `Remove click → 첫 cleaned result visible`이다. full settled develop와 disk cache persist를
같은 spinner에 묶지 않는다. Auto full-frame과 Guided small ROI를 별도 benchmark한다.

fixture:

- 24/60/75/100+ MP
- RGB auto high grain/structure lines
- small/large Guided ROI
- 1/10/100/1000 layer
- long brush/clone paths
- IR alignment success/failure/high coverage/B&W fail-closed
- x64 Intel/AMD와 ARM64
- CPU-only/WARP, Intel/AMD/NVIDIA/Qualcomm GPU

## 29. 접근성

- tool strip은 4개 toggle/Invoke를 정확히 노출
- active, busy, unavailable와 이유
- sensitivity는 RangeValue + mode-specific name
- micro-specks checkbox
- component overlay는 모든 점을 UIA element로 만들지 않고 class summary와 keyboard selection/navigation
  대안을 제공
- class chip: name/count/confidence/included state
- Remove/Cancel은 visible button과 keyboard action이 1:1
- layer list: position, kind, enabled, title, summary, strength, mask state, delete
- progress와 false-positive/coverage/alignment warning live announcement
- mask classification은 color+text/pattern
- high contrast에서 overlay와 excluded state 구분

## 30. 테스트와 출시 gate

단위/속성:

- every record kind shape validation
- canonical hash determinism x64/ARM64
- content blob corruption detection
- bounded decompression/fuzz/overflow
- coordinate transform round-trip
- ordered layer equivalence full vs incremental vs cached patch
- strength composite exactness
- source identity mismatch/relink
- stale detect/IR/build/write rejection
- revision-aware write/delete/conflict

품질:

- clean ground-truth preservation
- dust/scratch recall·precision을 corpus별 보고
- structure-line false positive
- grain texture preservation
- IR/raw alignment and coverage gates
- CPU/D3D11/backend pixel or perceptual tolerance
- exact export reconstruction

실제 UX:

- 모든 도구 pointer/pen/keyboard/Narrator
- frame/tab/tool 전환 중 task
- app crash/restart with unsaved/persisted recipe
- cache 삭제 후 rebuild
- source relink/mismatch
- sidecar write denial/disk full/antivirus lock

출시 차단:

- source overwrite 가능 경로
- recipe 없이 cache만 authoritative인 경로
- stale task가 다른 frame/revision에 layer 추가
- sidecar validation bypass
- CPU/GPU vendor별 의미 있는 품질 차이
- export가 required cleaned result 없이 성공
- IR compatibility fail-open
