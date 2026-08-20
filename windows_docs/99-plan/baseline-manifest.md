# macOS 기준선·동등성 manifest 명세

> 상태: Windows 구현 전 schema·추출·비교 계약  
> 기준일: 2026-08-04  
> 기준 commit: 9be909c43edd7e04ba98cdc9d6a0c688739e343e  
> 관련 결정: [D-014](../00-overview/decision-register.md)  
> 관련 계약: [UI/UX 동등성](../08-ui/parity-contract.md),
> [장기 유지보수](maintenance.md), [이행 로드맵](migration-roadmap.md)

## 0. 결론

99.9% 동등성을 “기억하고 있는 macOS 화면”이나 움직이는 `main`과 비교하지 않는다. 각 Windows
milestone은 exact macOS commit에서 **자동 추출한 사실**과 사람이 승인한 **제품 의미**를 하나의
versioned baseline set으로 고정한다.

manifest는 두 종류의 사실을 섞되 출처를 숨기지 않는다.

```text
generated facts
  enum/action/key/asset/kernel/schema/hash처럼 source에서 결정적으로 추출

curated contracts
  surface state, disabled 이유, error/recovery, 플랫폼 번역, 허용 delta처럼 리뷰가 필요한 의미
```

정규식 한 번으로 Swift source를 훑은 결과를 production manifest라고 부르지 않는다. enum `allCases`,
resource table, test fixture와 canonical inventory를 compile/run할 수 있는 macOS 기준선 exporter가
generated layer의 정본 후보이다. 화면 구조와 사용자 의미는 source path와 test를 근거로 사람이
curate하고 review한다.

## 1. 목적

- Windows가 어느 macOS commit과 동등해야 하는지 고정
- action, menu, shortcut, localization, accessibility, surface 누락 탐지
- pipeline·asset·schema drift를 UI drift와 함께 추적
- 의도된 Windows native 번역과 실제 기능 누락 구분
- macOS 변경을 자동 요구사항이 아니라 review 가능한 delta로 전환
- x64·ARM64·CPU/GPU backend가 같은 제품 contract를 소비하게 함
- Beta/RC/Stable evidence가 정확히 어느 baseline을 검증했는지 연결

## 2. 비목표

- SwiftUI view tree를 XAML로 자동 변환
- screenshot pixel hash만으로 UI 동등성 판정
- macOS shortcut chord를 Windows에 기계적으로 치환
- source file·line 수를 기능 완료율로 사용
- private image corpus나 사용자 path를 manifest에 포함
- runtime telemetry를 제품 spec의 정본으로 사용
- 한 거대한 JSON에 binary, screenshot, ETL과 dump를 embed

## 3. current source snapshot

2026-08-04에 commit `9be909c` source를 읽어 확인한 집계다. 아래 수치는 manifest generator가 이미
존재한다는 뜻이 아니라 첫 exporter의 회귀 기대값이다.

| 항목 | 현재 값 | source |
|---|---:|---|
| `WorkflowShortcutGroup` | 7 | `WorkflowShortcutActions.swift` |
| `WorkflowShortcutAction` | 66 | 같은 파일 |
| `AppLocalizedText` key | 256 | `Localization/Core/AppLocalizedText.swift` |
| `AppLocalizedPhrase` key | 597 | `Localization/Phrases/AppLocalizedPhrase.swift` |
| localization key 합계 | 853 | 위 두 enum |
| 사용자 언어 | 6 | en, ko, ja, zh-Hans, fr, de |
| `system` language selector | 1 | explicit locale-following option |
| `AppMenuCatalog` section | 10 | `Localization/Core/AppMenuCatalog.swift` |
| menu command occurrence | 34 | 같은 catalog의 중복 포함 |
| menu command key unique | 24 | 같은 catalog |
| literal accessibility ID template | 38 | `.accessibilityIdentifier("...")` literal |
| stitchable color kernel | 31 | `ChromabaseMetalKernels.swift` |

주의:

- `AppMenuCatalog`는 localization/test용 정적 catalog다. 실제 `AppStandardMenuCommands`와
  `AppWorkflowMenuCommands`에는 rating 1–5, process, target, Defects tool, dynamic enabled state가 더 있다.
  따라서 34 occurrence를 전체 실제 menu item 수라고 부르지 않는다.
- 38개 accessibility literal에는 interpolation template가 포함되고 helper argument로 전달되는 ID,
  label/value/hint와 runtime collection item identity는 포함되지 않는다.
- localization 853 key는 key 수다. 각 언어의 formatted placeholder·plural·accessibility 의미가 맞다는
  증거는 별도다.
- 31 kernel은 전체 graph stage/dispatch 수가 아니다.

## 4. baseline artifact set

한 파일에 모든 책임을 넣지 않는다. 권장 set:

```text
baseline/
├── baseline.json               identity, versions, component hashes
├── actions.json                stable action·entry·enabled contract
├── shortcuts.json              mac default와 Windows approved mapping
├── menus.json                  semantic menu tree와 dynamic rule
├── localization.json           keys, placeholders, locale coverage
├── accessibility.json          stable semantic IDs와 patterns
├── surfaces.json               surface/state/interaction manifest
├── pipeline.json               graph/stage/kernel/default/tolerance identity
├── persistence.json            catalog/sidecar/recipe/export schema identity
├── scanner.json                protocol/capability/format identity
├── assets.json                 preset/profile/resource hashes와 provenance refs
├── known-deltas.json           approved platform translation/defer register
└── evidence-index.json         tests, captures, reports의 digest/URI
```

이 경로는 future artifact layout 제안이며 현재 저장소에 파일이 존재한다고 주장하지 않는다.
Windows 구현 repository가 생길 때 exact location과 JSON Schema files를 M0에서 고정한다.

### 4.1 분리 이유

- localization change가 GPU baseline hash를 불필요하게 바꾸지 않음
- surface reviewer와 engine reviewer가 자기 영역 diff를 읽기 쉬움
- 공개 가능한 manifest와 protected evidence를 분리
- schema별 독립 migration 가능
- giant file의 conflict와 무의미한 reserialization 감소

### 4.2 root index

`baseline.json`은 다른 파일의 relative name, schema version과 SHA-256을 기록한다. child file이
바뀌면 root digest도 바뀐다. path는 baseline root 상대 경로이며 절대 developer path를 넣지 않는다.

## 5. identity와 version 축

root 필수 field:

```json
{
  "manifest_schema": 1,
  "product_spec_version": "independent-semver-or-date",
  "generated_at_utc": "RFC3339 timestamp",
  "source": {
    "repository_identity": "approved repository identifier",
    "mac_commit": "9be909c43edd7e04ba98cdc9d6a0c688739e343e",
    "working_tree_policy": "clean-archive",
    "exporter_version": "versioned tool identity"
  },
  "components": [],
  "approvals": []
}
```

위 JSON은 schema shape 예시다. `product_spec_version`, exporter와 approvals는 실제 값이 승인되기 전
placeholder를 production artifact에 남기지 않는다.

독립 version:

- baseline manifest schema
- product/spec
- macOS source commit
- Windows source commit
- action/menu/shortcut schema
- localization asset bundle
- catalog·sidecar·recipe·algorithm schema
- C ABI
- scanner protocol
- shader/pipeline asset bundle
- conformance corpus
- toolchain/dependency lock
- installer/update/signing policy

앱 version 하나로 모든 축을 추정하지 않는다.

## 6. generated와 curated field 표기

각 record는 가능한 경우 다음 provenance를 가진다.

```text
origin.kind
  generated_source
  generated_resource
  generated_test_fixture
  curated_code_review
  curated_product_decision
  measured_macos
  measured_windows

origin.reference
  repo-relative path + stable symbol

origin.commit
  exact SHA

origin.extractor
  exporter component/version 또는 reviewer identity
```

line number는 보조 정보다. source edit로 쉽게 움직이므로 stable symbol/path와 commit을 정본으로 쓴다.

curated record에는 reviewer, review date, reason과 next-review trigger가 필요하다. “직관적으로 동일”은
review reason이 아니다.

## 7. action manifest

### 7.1 stable action ID

macOS `WorkflowShortcutAction.rawValue` 66개는 현재 stable action ID의 강한 후보다.

record field:

```text
action_id
group_id
title_resource_id
semantic_description
destructive
toggle_or_momentary
repeat_policy
selection_scope
allowed_workspaces
entry_points
enabled_predicate_id
disabled_reason_id
result_event_id
undo_contract
shortcut_customizable
```

Swift method name이나 XAML command class 이름을 ID로 만들지 않는다. `action_id`는 platform-neutral product
meaning이고 macOS/Windows handler symbol은 mapping이다.

### 7.2 entry point

같은 action의 entry point:

- toolbar
- main menu
- context menu
- keyboard shortcut
- button/inspector
- drag/drop
- activation
- accessibility action

각 entry가 별도 handler와 enabled logic을 가지면 drift 위험으로 표시한다. Windows에서는 한
application command service로 모으되 visible placement와 focus return은 surface별로 기록한다.

### 7.3 enabled predicate

source closure의 code text를 hash하는 것만으로 의미를 보존할 수 없다. predicate는 stable 조건 token으로
curate한다.

예:

```text
requires.actionable_frame
requires.exportable_selection
forbids.active_scan
requires.scanner_capability.preview
requires.flatbed_region_workflow
```

Windows test는 token별 truth table을 실행하고 macOS fixture 결과와 비교한다.

## 8. shortcut manifest

현재 66개 default shortcut은 macOS source test에서 모두 valid·unique여야 한다. 그러나 Windows mapping은
다음 때문에 별도 field다.

- Command→Ctrl 단순 치환으로 OS/menu chord 충돌 가능
- Option→Alt는 menu activation과 AltGr 영향을 받음
- macOS Control chord의 Windows 의미가 다름
- keyboard layout과 IME 차이
- Windows reserved/system shortcut

record:

```text
action_id
mac_default.key
mac_default.modifiers
windows_default.key
windows_default.modifiers
mapping_reason
customizable
reserved_conflict_result
legacy_aliases
```

사용자 override migration은 action ID 기준이다. title 번역이나 chord string을 key로 쓰지 않는다.
removed action의 override를 다른 action에 자동 적용하지 않고 migration report에 남긴다.

필수 검사:

- platform별 default signature unique
- allowed key set과 modifier-only 거부
- 모든 action에 localized title
- menu/toolbar/shortcut enabled truth 동일
- Settings recorder와 runtime accelerator가 같은 normalized signature
- 6개 언어와 QWERTY/QWERTZ/AZERTY/IME/AltGr smoke

## 9. menu manifest

정적 `AppMenuCatalog`만 복사하지 않는다. 실제 SwiftUI `Commands` tree를 함께 curate한다.

```text
menu_id
title_resource_id
platform_role
ordered_children
separator_id
dynamic_collection
action_id
visible_predicate
enabled_predicate_id
check_state_id
shortcut_action_id
```

Windows native translation:

- macOS application menu 역할은 Windows File/Help/About/Settings convention으로 재배치 가능
- Windows system menu는 제품 menu manifest 밖의 native surface
- role-based default item과 custom `CommandMenu`를 중복 생성하지 않음
- dynamic process/target/rating list의 순서와 selected state 보존
- visible title은 localization, menu/action ID는 비현지화

menu parity는 label screenshot이 아니라 action, role, order cluster, enabled/check state와 keyboard 접근으로
검증한다.

## 10. localization manifest

### 10.1 key inventory

현재 두 key domain:

- `AppLocalizedText`: 256
- `AppLocalizedPhrase`: 597

Windows `.resw` key를 무조건 enum name과 다르게 만들지 않는다. namespace collision이 없으면 stable source
key를 보존하고, 변환이 필요하면 explicit mapping과 alias를 둔다.

record:

```text
resource_id
source_domain
format_kind
placeholder_names_types_order
required_locales
technical_string
accessibility_usage
max_length_hint_if_product_owned
deprecated_aliases
```

### 10.2 값 hash의 한계

언어별 string hash는 무단 변경 탐지에는 유용하지만 번역 품질을 증명하지 않는다.

- Unicode normalization
- plural/select
- argument order
- typographic punctuation
- BiDi isolate
- access key
- truncation/layout
- screen-reader 발음

을 별도 검증한다.

`system`은 번역 locale가 아니라 OS/app language를 따르는 selector다. 실제 required translation locale는
en, ko, ja, zh-Hans, fr, de 여섯 개다.

## 11. accessibility manifest

### 11.1 literal ID는 시작점

source에서 직접 확인한 literal accessibility ID template는 38개다. 다음은 별도다.

- interpolation으로 만들어지는 item/page ID
- helper parameter로 전달되는 ID
- label/value/hint만 있고 ID가 없는 control
- custom accessibility representation
- collection virtualization의 runtime peer
- dynamic error/progress live region

따라서 regex literal 수를 accessibility coverage로 쓰지 않는다.

### 11.2 record

```text
semantic_id
surface_id
mac_identifier_template
windows_automation_id_template
role_or_control_type
name_resource_id
value_schema
state_schema
patterns
focus_order_group
live_setting
virtualized_item_identity
```

Windows `AutomationId`는 macOS spelling을 기계 복사할 필요는 없지만 mapping이 stable해야 한다. 현재 문서의
`Negaflow.Main`, `Negaflow.Canvas`, `Negaflow.Workspace.*` 후보와 기존 `negaflow.*` ID 사이에 mapping/alias
정책을 한 번 정한다.

### 11.3 test

- ID uniqueness는 한 visual tree scope 안에서 평가
- virtualized item 재사용 뒤 identity/value 갱신
- role/pattern/name/value/state snapshot
- keyboard focus와 invoking control 복귀
- Narrator live region rate limit
- high contrast/text scale에서 hidden semantic control 없음

## 12. surface manifest

surface ID는 source file이나 XAML class가 아니라 제품 의미다.

예:

```text
shell.main
library.grid
library.compare
library.survey
develop.canvas
develop.inspector.base
defects.brush
export.dialog
print.contact-sheet
scan.preview
settings.color-management
recovery.catalog-blocked
```

record:

```text
surface_id
parent_surface_id
workspaces
source_symbols
windows_mapping
entry_action_ids
state_ids
interaction_ids
persistence_keys
accessibility_ids
performance_scenarios
golden_workflow_ids
platform_translation
```

### 12.1 state record

각 surface는 해당되는 state를 명시한다.

```text
initial
loading
empty
ready
disabled
busy_foreground
busy_background
partial_success
error_recoverable
error_blocking
cancelled
stale
offline_source
permission_or_trust
```

state field:

- entry predicate
- visible information/action
- allowed action IDs
- focus target
- persistence mutation
- async owner/revision
- exit transitions
- accessibility announcement
- mac evidence
- Windows evidence

surface가 `ready` screenshot만 있으면 manifest coverage가 아니다.

### 12.2 layout와 visual

pixel coordinate 전체를 manifest에 넣지 않는다. durable 의미를 기록한다.

- hierarchy와 region ownership
- minimum usable canvas/panel relationship
- inline/equal-width/non-wrap invariant
- quiet vs persistent selected emphasis
- native platform translation
- DPI/text-scale breakpoint evidence

macOS point와 Windows effective pixel 수치는 separate measured fields이며 하나를 다른 값으로 자동 복사하지
않는다.

## 13. lifecycle manifest

[앱 수명주기 명세](../08-ui/application-lifecycle.md)의 stable state/transition도 baseline에 들어간다.

```text
instance scope
activation kinds
window cardinality/ownership
startup phases
normal close phases
session-end behavior
crash/restart behavior
terminal receipts
```

current macOS source에서 model-level termination failure와 delegate-level forced exit가 충돌하므로 Q-025가
닫히기 전에는 이를 하나의 “동등한 종료 동작”으로 flatten하지 않는다. observed behavior와 approved
Windows target을 별도 field로 둔다.

## 14. pipeline manifest

31개 kernel 이름만 나열하는 파일이 아니다.

필수:

- canonical parameter schema와 defaults
- stage ordering/branch predicate
- kernel/function identity와 source hash
- input count, alpha/coordinate semantics
- spatial producer/halo/ROI
- working format와 color domain
- measurement reduction semantics
- CPU scalar reference identity
- D3D11/D2D/WARP shader bytecode/compiler manifest
- operation별 tolerance
- corpus version/hash

같은 visible output을 여러 backend가 만들더라도 backend-specific binary hash는 별도 component이고 product
result tolerance는 공통 contract다. CUDA optional tier가 생겨도 새 feature/default/preset을 추가하지 않는다.

## 15. persistence와 scanner manifest

### persistence

- catalog logical/schema version
- sidecar/recipe/cache schema
- source identity와 path migration policy
- atomic commit/read-back generation
- export journal phase/version
- backup generation/restore drill
- app data root/channel identity

### scanner

- protocol major/minor
- command/event/schema hash
- capability enum/token
- film format/ROI units
- request/applied equality rules
- plugin manifest schema
- architecture/license/install identity

scanner device support claim은 baseline의 generic protocol entry만으로 증명되지 않는다. physical evidence
index에 model, USB ID, driver, backend, applied ROI와 artifact가 있어야 한다.

## 16. asset manifest

asset record:

```text
asset_id
kind
logical_version
relative_path
sha256
byte_length
schema
source/provenance reference
redistribution decision reference
required/optional
consumers
```

대상:

- presets
- scanner profiles
- ICC profiles
- localization tables
- shader source/bytecode
- icon/font/vector
- test vectors/corpus index
- NOTICE/license documents

filesystem enumeration order를 믿지 않고 stable asset ID로 정렬한다. 같은 filename의 다른 content를 silent
replacement하지 않는다.

## 17. known delta register

delta는 누락을 숨기는 예외 목록이 아니다.

```text
delta_id
baseline_component/id
classification
severity
mac_behavior
windows_behavior
reason
platform_translation 또는 deferred_feature
user impact
data/quality/accessibility impact
owner
approved_by/date
introduced/expires
verification
release_note_required
```

classification:

- native platform translation
- intentional product change
- temporary implementation gap
- unsupported hardware/dependency
- macOS-only behavior
- Windows-only behavior
- source ambiguity awaiting decision

severity:

- P0 data loss/security/core result
- P1 required workflow/state/accessibility
- P2 bounded visual/platform translation
- P3 internal implementation difference

P0/P1를 `99.9%`의 0.1%로 승인하지 않는다. temporary gap에는 owner, expiry milestone와 hard gate가
필수다.

## 18. evidence index

manifest는 test/report 자체를 embed하지 않고 immutable digest와 위치를 가리킨다.

```text
evidence_id
requirement_id
kind
platform/architecture
source/build/baseline identity
environment/hardware
artifact URI
sha256
created/reviewer
result
limitations
retention/access class
```

kind:

- source extraction
- unit/conformance/integration
- screenshot/visual diff
- UI Automation tree
- manual keyboard/Narrator
- numeric pixel/color
- performance trace
- scanner hardware
- installer/update/signing
- license/SBOM/provenance

외부 CI URL 하나만 저장하지 않는다. retention 만료 후에도 최소 result manifest, hash와 재현 정보가 남아야
한다. protected image/dump/ETL은 공개 manifest와 access class를 분리한다.

## 19. canonical serialization과 hash

### 규칙

- UTF-8, BOM 없음
- LF newline
- object key와 unordered set 안정 정렬
- ordered product list는 의미 순서 보존
- number format canonical
- timestamp는 UTC RFC 3339
- absolute path·machine username 없음
- NaN/Infinity를 JSON number로 기록하지 않음
- duplicate key 거부
- unknown required field/schema는 fail closed
- child bytes SHA-256 뒤 root index 생성

pretty JSON과 canonical digest input이 다를 수 있으면 canonical byte generation을 명시하고 두 byte의 hash를
혼동하지 않는다. initial implementation에서 자체 “거의 canonical” serializer를 여러 언어로 각각 만들지
않는다. 한 exporter와 cross-language verifier test vector를 둔다.

## 20. 생성 절차

### 20.1 macOS 기준선 export

1. exact commit과 clean archive 확인
2. exporter tool/source version 고정
3. compiled enum/resource/asset inventory 생성
4. pipeline/schema/test fixture inventory 생성
5. curated surface/action/state layer와 join
6. duplicate/missing/orphan ID 검사
7. canonical serialize·hash
8. 이전 baseline과 semantic diff
9. macOS domain/UI/engine reviewer 승인
10. immutable baseline release

### 20.2 Windows mapping

1. 같은 product IDs import
2. Windows handler/surface/resource/AutomationId mapping
3. generated Windows inventory 추출
4. baseline required record와 set comparison
5. approved native translation과 known delta 적용
6. behavior/numeric/UI/hardware evidence 연결
7. milestone gate report 생성

### 20.3 regex의 역할

`rg`/regex는 빠른 drift 탐지와 exporter bootstrap에는 유용하다. 그러나 다음을 놓친다.

- multiline/conditional declaration
- helper-generated/dynamic menu
- generic/interpolated ID
- runtime capability visibility
- compiled resource fallback
- view state와 enabled predicate 의미

따라서 regex count는 audit clue이며 release manifest exporter의 단독 parser가 아니다.

## 21. semantic diff

diff category:

```text
added
removed
renamed_with_alias
default_changed
predicate_changed
ordering_changed
localization_changed
accessibility_changed
schema_changed
asset_content_changed
tolerance_changed
evidence_only_changed
```

hash가 다르다고 모두 breaking은 아니고 hash가 같다고 product behavior가 같은 것도 아니다. component별
semantic comparator를 사용한다.

예:

- action 추가: Windows scope/milestone 결정 필요
- shortcut chord 변경: user override migration 필요
- title 번역 변경: layout/access key QA 필요
- preset JSON bytes 변경: pixel conformance 재실행
- source file 이동만: stable symbol/content가 같으면 evidence reference update
- test evidence 추가: product baseline unchanged

## 22. CI와 gate

### macOS side

- current source exporter가 checked baseline과 다른데 delta record가 없으면 fail
- action/localization/accessibility/asset ID duplicate fail
- default shortcut conflict fail
- localization key/placeholder coverage fail
- menu action orphan/unknown fail
- kernel/pipeline inventory mismatch fail

### Windows side

- required action/resource/surface mapping missing fail
- P0/P1 unresolved delta fail
- x64/ARM64 generated inventory mismatch fail
- CPU/GPU backend가 다른 product schema/default를 report하면 fail
- AutomationId duplicate/required pattern missing fail
- stale evidence가 required gate를 만족한다고 표시되면 fail

### release report

```text
baseline identity
Windows build identity
required/implemented/verified counts
P0/P1/P2/P3 delta counts
expired waiver count
missing/stale evidence
architecture/backend/hardware coverage
```

단순 “manifest checker green”은 실제 UI/색/스캐너/인쇄 QA를 대체하지 않는다.

## 23. baseline 갱신 workflow

macOS main change를 발견했을 때:

1. old/new baseline 생성
2. semantic delta report
3. bug fix, feature, rename, mac-only, experiment 분류
4. product owner가 Windows 요구 시점 결정
5. schema/asset migration 영향 분석
6. Windows milestone/owner/evidence gate 지정
7. approved baseline version 발행
8. 이전 baseline과 report 보존

`main`을 가리키는 floating reference를 baseline field에 넣지 않는다. release branch도 exact commit으로 resolve해
기록한다.

긴 Windows milestone 중 새 macOS feature가 들어왔다고 현재 완료 기준을 조용히 바꾸지 않는다. security/data
safety fix는 expedited triage할 수 있지만 역시 explicit delta다.

## 24. privacy·보안

- repository URL에 credential/token 없음
- developer absolute path·username 없음
- private source filename/image metadata 없음
- corpus는 logical ID/hash/license/access class만
- support dump/ETL raw location은 protected evidence index
- reviewer identity는 조직 정책에 맞는 ID만
- manifest signature가 필요하면 signing policy와 key rotation을 별도 관리
- untrusted plugin이 core baseline을 쓰거나 바꾸지 못함
- installer가 baseline을 생성하지 않고 signed release payload의 baseline을 검증

manifest hash는 executable signature를 대체하지 않는다. signed artifact 안의 baseline과 payload inventory를
연결하고 Authenticode·update metadata·SBOM을 각각 검증한다.

## 25. 구현 전 spike

- [ ] compiled macOS exporter가 66 actions, 7 groups, 256+597 localization keys를 재현
- [ ] actual menu tree의 static/dynamic entry를 action ID에 매핑
- [ ] accessibility literal/helper/runtime ID inventory 결합
- [ ] 31 kernel + graph stage + asset hash export
- [ ] canonical serializer의 Swift/C++/C# cross-check test vector
- [ ] old/new baseline semantic diff golden
- [ ] P0/P1/P2 delta gate와 expiry
- [ ] Windows x64·ARM64 exporter output set equality
- [ ] evidence index retention/permission/privacy drill

## 26. 완료 정의

- [ ] schema files와 exporter version이 source-controlled
- [ ] clean archive에서 deterministic byte-identical output
- [ ] current snapshot 집계와 exact IDs 일치
- [ ] generated/curated provenance가 모든 required record에 있음
- [ ] actions/menu/shortcuts/localization/accessibility/surface/pipeline/data/scanner/assets 포함
- [ ] stable ID rename/alias/migration 정책
- [ ] known delta severity·owner·expiry·evidence
- [ ] Windows x64·ARM64 mapping completeness
- [ ] evidence가 exact baseline/build/hardware를 가리킴
- [ ] actual UI·numeric·hardware QA 없이 manifest만으로 완료 주장하지 않음

## 27. 남은 위험

- SwiftUI declarative view와 dynamic menu/state를 완전 자동 추출하기 어려움
- source enum count를 사용자 기능 수로 오인할 위험
- curated surface layer가 코드보다 늦게 갱신될 위험
- stable ID를 class/filename에 결합해 refactor가 false delta를 만드는 위험
- JSON hash만 맞추고 실제 disabled/error/recovery 의미가 어긋날 위험
- screenshot diff가 native font/DPI 번역을 과도하게 실패시키거나 실제 누락을 놓칠 위험
- protected evidence retention 만료로 release claim을 재검증하지 못할 위험

## 28. 관련 자료

- [UI/UX 동등성 계약](../08-ui/parity-contract.md)
- [기능 지도](../08-ui/feature-map.md)
- [앱 수명주기](../08-ui/application-lifecycle.md)
- [입력·단축키](../08-ui/input-and-shortcuts.md)
- [접근성·현지화](../08-ui/accessibility-localization.md)
- [커널 인벤토리](../02-shaders/kernel-inventory.md)
- [제품 불변식](product-invariants.md)
- [이행 로드맵](migration-roadmap.md)
- [장기 유지보수](maintenance.md)
- [문서 감사](documentation-audit.md)
