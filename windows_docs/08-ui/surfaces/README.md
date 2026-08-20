# WinUI 3 화면별 이식 명세 지도

> 상태: 화면 명세의 정본 진입점  
> 기준일: 2026-08-04  
> macOS source 기준: `9be909c43edd7e04ba98cdc9d6a0c688739e343e`  
> 상위 계약: [UI/UX 99.9% 동등성](../parity-contract.md),
> [기준선 manifest](../../99-plan/baseline-manifest.md)

## 0. 목적

이 폴더의 문서는 XAML 화면 스케치가 아니다. 현재 macOS Negaflow의 surface별 기능, 상태 전이,
입력, 오류·복구, 데이터 안전성, 접근성, 성능과 acceptance를 Windows native UI로 옮기기 위한 계약이다.

화면 하나가 독립적으로 예뻐 보이는 것만으로 완료하지 않는다. Library의 ordered selection이 Develop,
Export, Print 대상으로 이어지고, Develop·Defects의 recipe가 preview와 final output에서 같으며, Scanner가
보고한 capability만 UI에 나타나는 전체 workflow를 검증한다.

---

## 1. 문서 지도

| Surface | 정본 | 핵심 소유권 | 최초 milestone |
|---|---|---|---|
| Library | [library.md](library.md) | import, catalog projection, selection, culling, source lifecycle | M9 |
| Canvas | [canvas.md](canvas.md) | image geometry, presentation, tools, overlays, input | M8 |
| Develop | [develop.md](develop.md) | 비파괴 recipe, inspector, history, preview scheduling | M10 |
| Defects | [defects.md](defects.md) | ordered defect recipe, detection, brush/clone, cleaned cache | M11 |
| Export | [export.md](export.md) | immutable snapshot, encode, publish, catalog transaction | M12 |
| Print | [print.md](print.md) | paper/package layout, color preview, page artifact export | M13 |
| Settings | [settings.md](settings.md) | preferences, storage, plugins, shortcuts, diagnostics | M14 |
| Scanning | [scanning.md](scanning.md) | plugin capability, preview/ROI, scan provenance | M15 |

Shell, app lifetime, input, accessibility와 canvas interop의 공통 규칙은 이 폴더가 아니라 다음 문서가
소유한다.

- [shell과 navigation](../shell-and-navigation.md)
- [application lifecycle](../application-lifecycle.md)
- [input과 shortcuts](../input-and-shortcuts.md)
- [accessibility와 localization](../accessibility-localization.md)
- [SwapChainPanel canvas](../swapchainpanel-canvas.md)

surface 문서와 공통 문서가 충돌하면 제품 의미는 [제품 불변식](../../99-plan/product-invariants.md)과
[결정 등록부](../../00-overview/decision-register.md)를 먼저 확인하고, 실제 macOS source를 다시 읽는다.

---

## 2. 공통 완료 축

각 surface는 다음 축을 따로 판정한다.

| 축 | 질문 | 최소 증거 |
|---|---|---|
| 기능 | macOS에서 가능한 작업을 모두 끝낼 수 있는가 | action/surface manifest + scenario |
| 정보 구조 | 같은 상태와 다음 행동을 찾을 수 있는가 | annotated capture + navigation trace |
| 시각 | 위계·밀도·canvas 공간이 제품 의미를 유지하는가 | DPI/theme/text-scale 비교 |
| 입력 | pointer/keyboard/touchpad/pen과 취소가 자연스러운가 | event trace + manual QA |
| 데이터 | source/recipe/catalog/artifact가 안전한가 | transaction/fault-injection log |
| 접근성 | Narrator, focus, UIA pattern, high contrast가 완전한가 | Accessibility Insights + manual trace |
| 성능 | interaction과 batch가 예산 안인가 | ETW/PIX + P50/P95/P99 |
| 복구 | offline, failure, cancel, restart에서 의미가 보존되는가 | recovery scenario + durable evidence |

한 축이 통과했다고 전체 surface를 완료로 표시하지 않는다. screenshot 유사도는 시각 축의 일부일 뿐이고,
unit test 통과는 실제 Narrator·DPI·hardware 동작의 증거가 아니다.

---

## 3. 공통 상태 어휘

모든 surface가 같은 이름과 의미로 다음 상태를 사용한다.

| 상태 | 사용자에게 보이는 의미 | 명령 정책 |
|---|---|---|
| empty | 작업 대상이 없음 | import/scan/recovery 진입만 활성 |
| loading | 필요한 data를 읽는 중 | 충돌 mutation 차단, safe navigation 허용 |
| ready | 현재 state가 일관됨 | context에 맞는 command 활성 |
| interactive | 연속 조정·drag 중 | latest-wins preview, undo 1개 준비 |
| committing | disk/catalog/artifact를 확정 중 | 중복 commit 차단 |
| canceling | 새 작업 차단, 이미 제출된 작업 drain | cancel 중복 실행 금지 |
| recoverable_error | 재시도·relink·공간 확보 등 가능 | 명시적 recovery action |
| blocked | data state가 불명확해 mutation 금지 | recovery/export evidence만 허용 |
| source_offline | catalog/thumbnail은 있으나 원본 부재 | 원본 필요 명령 비활성 + Relink |
| plugin_unavailable | scanner 기능만 없음 | core import/develop/export 유지 |

surface별로 필요하면 하위 상태를 추가하지만 `loading` spinner 하나로 모든 상태를 숨기지 않는다.
disabled control은 단순 회색 표시뿐 아니라 이유와 다음 가능한 행동을 제공한다.

---

## 4. cross-surface identity

### 사진·recipe

```text
Library FrameId + SourceIdentity
        │
        ├─ DevelopRecipeRevision
        ├─ TransformRevision
        ├─ DefectRecipeIdentity
        ├─ ProofConfigurationRevision
        └─ ExportSnapshotIdentity
```

- UI object reference나 grid index를 domain identity로 사용하지 않는다.
- source path만으로 같은 파일이라고 단정하지 않는다.
- virtual copy는 source를 공유할 수 있지만 recipe identity는 독립이다.
- async 결과는 publish 직전에 frame ownership과 revision을 다시 확인한다.
- remove/relink가 진행되면 old completion은 cache와 UI에 publish하지 않는다.

### selection

Library가 제공하는 ordered ID projection이 다음 소비자의 입력이다.

- Develop active frame과 filmstrip scope
- Defects 현재 frame
- Export 선택 집합과 sequence
- Print page/package placement source

각 화면이 별도 배열을 재정렬해 command 대상과 보이는 순서를 갈라놓지 않는다.

---

## 5. 핵심 workflow 연결

### 5.1 import → Library → Develop

1. File activation, picker 또는 drag/drop을 import command로 normalize한다.
2. source probe·identity·metadata를 background에서 준비한다.
3. catalog transaction이 승인된 뒤 Library projection에 publish한다.
4. 현재 기본값대로 자동 현상은 explicit opt-in일 때만 수행한다.
5. 사용자가 Develop에 들어가면 같은 `FrameId`와 source/recipe revision을 사용한다.

검증:

- unsupported/corrupt/offline item이 전체 batch를 가짜 성공시키지 않음
- 중복 import 정책과 source identity가 일치
- import 중 취소·종료·disk full recovery
- Library selection과 Develop active frame 일치

### 5.2 Scan → Library

1. core가 plugin manifest와 trust를 검증한다.
2. plugin inventory/capability만 Scanning UI를 구성한다.
3. preview·ROI·resolution·bit depth 요청을 versioned protocol로 보낸다.
4. plugin이 실제 적용한 option과 artifact를 보고한다.
5. core가 staging file과 provenance를 검증한 뒤 Library transaction으로 가져온다.

USB 발견, model name, request 값은 적용 증거가 아니다. capability에 없는 control을 disabled placeholder로
만들지 않고 아예 노출하지 않는다.

### 5.3 Develop ↔ Canvas ↔ Defects

- Develop inspector는 recipe intent를 바꾼다.
- Canvas는 current revision의 결과와 tool geometry를 표시한다.
- Defects는 source를 덮지 않고 ordered recipe와 재구성 가능한 cleaned-raw cache를 만든다.
- slider/brush/ROI drag는 gesture 하나당 undo boundary 하나다.
- tool 전환, Escape, frame 전환, workspace 전환의 cancel order를 공유한다.
- proof/clipping/debug overlay는 final export pixel에 들어가지 않는다.

### 5.4 Develop/Defects → Export

Export 시작 시 다음을 immutable snapshot으로 고정한다.

- source content identity
- develop/transform/defect recipe identity
- format, size, DPI, quality, output profile
- metadata policy와 naming sequence
- destination와 artifact set

preview bitmap을 저장하지 않는다. active recipe를 full-quality graph로 재구성하지 못하면 원본으로
fallback하지 않고 명시적으로 실패한다.

### 5.5 Library/Develop → Print

Windows v1 Print는 현재 macOS와 같이 paper/package layout을 파일 artifact로 내보내는 workspace다.
OS print dialog·spooler는 독립 후속 범위다.

- ordered selection이 page placement source
- paper physical size, margin, cell, DPI를 layout identity에 포함
- Develop/Defects 결과와 output color policy를 재사용
- page preview proxy와 final page raster를 분리
- 일반 Export와 Quick Export의 설정·진입 경로도 별도 검증

### 5.6 Settings → 모든 surface

Settings 변경은 변경 범위에 맞는 generation만 갱신한다.

| 설정 | 영향 |
|---|---|
| language | 문자열·layout·accessibility name 재평가 |
| theme | XAML chrome와 canvas surround, image pixel 불변 |
| display/proof profile | presentation/proof cache |
| export default | 다음 export snapshot, 진행 중 job 불변 |
| storage path | 새 transaction, 기존 source 자동 이동 금지 |
| scanner plugin | 다음 inventory session, 진행 중 process 정책 적용 |
| shortcut | command mapping, action ID 불변 |

---

## 6. 공통 command 계약

- toolbar, menu, context menu, shortcut, accessibility invoke는 같은 semantic action을 호출한다.
- visible placement와 enabled predicate를 command 실행 로직과 분리하되 truth는 하나다.
- text/IME focus 중 single-key photo command를 실행하지 않는다.
- destructive command는 대상 수·source 영향·복구 가능성을 확인한다.
- pointer-only 작업에는 keyboard/inspector/menu 대체 경로가 있다.
- Escape는 가장 안쪽 transient interaction부터 닫는다.

권장 Escape 순서:

```text
shortcut recorder / text composition
→ active drag or tool gesture
→ modal teaching/flyout/dialog
→ current tool session
→ surface navigation은 유지
```

OS close나 session end를 Escape command로 대체하지 않는다.

---

## 7. 공통 visual·layout matrix

각 surface capture는 최소 다음 조합을 포함한다.

- 100%, 150%, 200% DPI
- 100%, 150%, 200% text scale
- light, dark, high contrast
- minimum supported window, typical laptop, wide desktop
- long 한국어·독일어와 CJK glyph
- 1개/다중 monitor, 서로 다른 DPI
- empty/loading/ready/error/disabled/progress

99.9% 동등성은 macOS pixel 복제가 아니다. Windows native typography, focus visual, title bar, picker,
menu와 scrollbar를 사용하면서 다음을 보존한다.

- canvas가 제품의 중심이라는 공간 위계
- inspector와 filmstrip의 정보 밀도
- primary/secondary/destructive command 우선순위
- 좁은 폭에서 명령이 말없이 사라지지 않는 규칙
- 작품을 가리는 불필요한 card·gradient·decoration 금지

---

## 8. 공통 accessibility matrix

각 surface는 다음을 실제 UIA tree와 Narrator에서 확인한다.

- stable semantic automation ID
- Name, ControlType, value/state, disabled reason
- keyboard tab/arrow order와 focus return
- invoke, toggle, range, selection, grid/list, scroll pattern
- live progress와 오류 announcement의 중복 억제
- icon-only action의 accessible name과 shortcut hint
- color만으로 상태를 구분하지 않음
- high contrast에서 focus·selection·warning 식별
- canvas tool의 keyboard/numeric equivalent

literal `.accessibilityIdentifier` 수나 XAML `AutomationProperties.Name` 존재만으로 coverage를 완료하지
않는다. runtime collection item과 dynamic state를 함께 검사한다.

---

## 9. 공통 오류·복구 matrix

| 오류 | 보존할 것 | 사용자 행동 |
|---|---|---|
| source offline/changed | catalog, recipe, thumbnail, identity evidence | Relink/검토 |
| decode failure | source 불변, 다른 item 작업 가능 | Retry/지원 정보 |
| GPU device lost | recipe, selection, transform, current request | 자동 재생성/fallback |
| cache corrupt | source와 recipe | 안전 폐기·재생성 |
| catalog commit failure | last known committed snapshot, journal | mutation 차단/복구 |
| export collision | source와 기존 destination | 새 이름/위치 선택 |
| disk full/permission | staging·journal evidence | 공간 확보/다른 위치 |
| scanner unplug/plugin exit | core library/develop state | reconnect/retry |
| app restart/update | committed state와 recovery journal | 자동 복구/명시 선택 |

surface는 domain error를 숨기지 않되 raw HRESULT, exception, private path를 기본 사용자 문구로 노출하지
않는다. 진단 세부는 privacy 경계 안의 support surface에서 제공한다.

---

## 10. evidence artifact set

surface acceptance run은 다음을 묶는다.

```text
surface_run.json
environment.json
baseline_identity.json
action_trace.ndjson
state_trace.ndjson
screenshots/
accessibility_tree/
performance_trace/
fault_injection_report.json
review_receipt.json
```

필수 identity:

- macOS baseline commit과 product spec version
- Windows build commit/package hash
- x64 또는 ARM64 architecture
- Windows/Windows App SDK/.NET version
- GPU/driver/monitor/DPI/input device
- language/theme/text scale
- source corpus digest와 privacy class

artifact path에 사용자 홈 경로와 원본 filename을 넣지 않는다. screenshot이나 accessibility tree가 사진
내용·metadata를 포함하면 protected evidence로 분류한다.

---

## 11. surface별 최소 golden scenario

| Surface | golden scenario |
|---|---|
| Library | 폴더 import → filter/sort → compare/survey → rating → virtual copy → remove/relink |
| Canvas | fit/100%/pan → compare → overlay → crop/tool → monitor·DPI 이동 → device recovery |
| Develop | manual develop → slider/number/reset → history/copy-paste → proof → frame 전환 |
| Defects | detect → include/exclude → strength → brush/clone → undo → cache rebuild → export |
| Export | single/batch → collision → progress/cancel/retry → publish → catalog recovery |
| Print | paper/package → drag/resize/keyboard → color preview → multi-page artifact export |
| Settings | category navigation → preference persist → shortcut conflict → cache/diagnostic/plugin state |
| Scanning | capability inventory → preview → ROI → scan/cancel/unplug → applied option/provenance import |

각 scenario는 정상 경로와 적어도 하나의 실패·취소·restart 경로를 포함한다.

---

## 12. 문서 갱신 규칙

macOS source가 바뀌면 파일 수나 screenshot만 비교하지 않는다.

1. exact source commit을 고정한다.
2. action/menu/shortcut/localization/accessibility generated delta를 만든다.
3. surface state·workflow·error·recovery의 curated delta를 검토한다.
4. 각 surface 문서와 known delta register를 갱신한다.
5. Windows mapping과 test/evidence requirement를 갱신한다.
6. 양쪽 reviewer가 의도된 차이인지 누락인지 승인한다.

Windows native 차이는 숨기지 않고 다음 중 하나로 기록한다.

- equivalent native translation
- approved product difference
- temporary gap with owner/expiry
- defect

---

## 13. 구현 착수 순서

surface는 한꺼번에 정적 mock으로 만들지 않는다.

1. M8에서 shell, lifecycle, command, canvas, error skeleton을 세운다.
2. M9 Library로 실제 catalog projection과 selection을 연결한다.
3. M10 Develop로 canonical recipe와 render scheduling을 연결한다.
4. M11 Defects로 가장 복잡한 tool/cache/recipe 경계를 연결한다.
5. M12 Export로 final-quality transaction을 닫는다.
6. M13 Print로 layout와 output color 경계를 닫는다.
7. M14 Settings·shortcut·localization·accessibility를 전체 surface에 완결한다.
8. M15 Scanner를 capability 기반 외부 plugin으로 연결한다.

M14가 처음 접근성을 생각하는 시점은 아니다. M8부터 각 surface의 UIA·keyboard contract를 구현하고,
M14에서 전체 coverage와 설정 surface를 완결한다.

---

## 14. 완료 정의

- [ ] 8개 surface가 baseline manifest의 모든 stable surface/state/action과 mapping됨
- [ ] 공통 identity와 revision이 cross-surface trace에서 일치함
- [ ] import/scan→develop→defects→export/print end-to-end workflow 통과
- [ ] toolbar/menu/context/shortcut/UIA가 같은 command truth 사용
- [ ] 정상·loading·empty·cancel·offline·recoverable·blocked 상태 검증
- [ ] x64·ARM64에서 native UI와 engine interop 검증
- [ ] Intel·AMD·NVIDIA·Qualcomm/WARP/CPU backend가 같은 UI 기능 제공
- [ ] DPI/theme/text-scale/language/high-contrast matrix 검증
- [ ] Narrator와 keyboard-only golden scenario 검증
- [ ] source·recipe·catalog·artifact data-safety fault injection 통과
- [ ] 실제 artifact가 exact baseline/build/hardware identity를 가리킴
- [ ] 승인되지 않은 delta와 만료된 waiver가 0개

현재는 Windows implementation과 실기 evidence가 없으므로 이 완료 정의는 미통과다. 이 문서는 구현
범위와 증거 계약을 고정한 것이며 UI가 실제로 만들어졌다는 주장이 아니다.
