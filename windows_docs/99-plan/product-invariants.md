# Windows판 제품 불변식

기준일: 2026-08-04  
macOS 기준 커밋: `9be909c`  
상태: 구현보다 우선하는 제품·데이터 안전 계약

이 문서는 Windows 구현 중 편의나 성능 때문에 바꾸면 안 되는 제품 의미를 기록한다. 현재 macOS 코드가
이 계약과 충돌하는 legacy path를 포함할 경우 Windows는 더 위험한 동작을 복제하지 않는다. 충돌은
[decision register](../00-overview/decision-register.md)에 근거와 함께 남긴다.

## 1. 기본 사용자 흐름

```text
import 또는 scan
→ Library에서 정리·선택
→ Develop에서 비파괴 현상
→ 필요한 경우 Defects 편집
→ Export 또는 Print package export
```

- `main` develop target이 기본이다.
- 수동 보정이 기본이며 automatic correction은 명시적 opt-in이다.
- `Develop imports automatically` 기본값은 off다.
- scanner가 없어도 import → develop → export 제품은 완전해야 한다.
- Print workspace의 1차 parity 범위는 file raster/package export다. 직접 printer spool은 별도 후속 기능이다.

## 2. 원본 불변

절대 변경하지 않는다.

- `ScanFrame.rawScanURL`이 가리키는 scanner original
- 가져온 third-party source file
- third-party `.xmp` sidecar
- 사용자가 명시적으로 관리하는 export/print artifact

원본 URL이 바뀔 수 있는 경우:

- 사용자가 명시적으로 source를 이동
- source relink
- persistent bookmark에 대응하는 Windows identity recovery

그 외 cache rebuild, app 종료, defect flatten, backup, catalog recovery는 원본 URL/file bytes를 바꾸지 않는다.

현재 macOS의 `AppModel+DefectBakeOnQuit.swift`에는 scanner original을 replace할 수 있는 경로가 남아 있다.
이는 저장소의 원본 불변 규칙과 충돌하므로 Windows로 옮기지 않는다.

## 3. 비파괴 truth hierarchy

```text
immutable source
  + source identity
  + develop parameters
  + ordered defect recipe
  + crop/orientation/output recipe
= reconstructable result
```

truth:

- catalog record와 schema
- app-owned defect sidecar
- canonical preset/profile asset
- source identity

truth가 아닌 것:

- memory-resident developed frame
- cleaned-raw TIFF
- thumbnail
- scan preview
- GPU texture/effect graph
- export staging file

파생 cache가 존재해도 identity/revision/hash가 현재 source·recipe와 맞지 않으면 사용하지 않는다.

## 4. defect 편집

### 4.1 tool 역할

| 도구 | 역할 |
|---|---|
| Auto | 전역 자동 검출·제거의 시작점 |
| Guided/Region | 사용자가 지정한 영역의 먼지·결함 |
| Brush | 미세 scratch와 잔여 결함 |
| Clone Stamp | 사용자가 지정한 source patch 복제 |

도구를 임의로 하나로 합치거나 이름만 남기고 같은 algorithm으로 만들지 않는다.

### 4.2 ordered recipe

- brush, region, clone 등은 하나의 순서 있는 `defectEdits` 의미를 공유한다.
- 뒤 편집은 앞 편집의 결과를 입력으로 받을 수 있다.
- enable/strength/order 변경은 recipe identity와 revision을 바꾼다.
- stale partial/cleaned cache가 삭제한 결함을 다시 보이게 해서는 안 된다.
- UI undo/redo와 persisted recipe의 순서를 일치시킨다.

### 4.3 app-owned sidecar

현재 macOS에는 versioned defect sidecar와 fingerprint/resource-limit validation이 있다. Windows에서도 다음을
유지한다.

- third-party XMP가 아닌 app-owned location
- serialized/atomic writer
- frame/source identity binding
- monotonic recipe revision
- canonical recipe SHA-256/fingerprint version
- item/stroke/point/mask/decompressed-byte upper bound
- future/invalid/corrupt payload fail-closed
- lower-revision async write가 remove/newer write 뒤에 부활하지 못함

“세션 메모리 전용, sidecar 없음”은 현재 제품 계약이 아니다.

### 4.4 cleaned raw

- cleaned raw는 재생성 가능한 derived cache다.
- memory cache를 disk보다 우선할 수 있지만 둘 다 current identity 확인이 필요하다.
- cache URL이나 존재만 보고 valid로 간주하지 않는다.
- source/recipe identity mismatch, corrupt decode, missing file은 evict/rebuild 대상이다.
- rebuild 불가능하면 export가 실패한다. original로 silently 대체하지 않는다.
- app 종료 시 cleaned raw를 source original에 bake하지 않는다.

### 4.5 RGB와 IR

- RGB 기반 Software Defect Removal을 hardware infrared/Digital ICE와 동등하다고 표현하지 않는다.
- plugin이 IR capability와 artifact를 실제로 보고한 경우에만 IR workflow를 제공한다.
- IR registration, bit depth, dimensions, ROI, source ownership을 검증한다.
- device가 IR을 지원하지 않으면 UI가 가짜 fallback을 만들지 않는다.

## 5. catalog 안전

### 5.1 missing/corrupt는 empty가 아니다

다음을 empty catalog로 취급하지 않는다.

- primary missing
- SQLite open/integrity/schema failure
- future version
- migration marker conflict
- process lock failure
- backup/primary ambiguity

blocked recovery state에서는 orphan/source/cache deletion을 실행하지 않는다.

### 5.2 write

- explicit acknowledged transaction
- dirty/persisted generation 구분
- previous valid primary/recovery 보존
- incremental 또는 full readback verification
- commit 실패 시 exact previous primary 복구
- external change가 write cache를 무효화
- test persistence는 user library를 절대 가리키지 않음

### 5.3 schema

- app catalog schema와 SQLite storage schema를 구분한다.
- unknown future schema는 읽은 척하지 않는다.
- migration은 단계별이며 source를 보존한다.
- portable archive/backup은 canonical representation과 manifest를 가진다.
- 50k frame benchmark를 유지하되 Windows storage tuning은 다시 측정한다.

## 6. Library 동작

- folder monitoring은 이미 추적하는 source의 이동·가용성 변화를 반영한다.
- folder에 새 파일이 나타났다고 자동 import하지 않는다.
- import는 사용자 명시 동작이다.
- source availability와 catalog presence를 구분한다.
- Library에서 제거와 filesystem original을 Recycle Bin으로 보내는 동작을 분리한다.
- delete 전 virtual copy와 shared source ownership을 계산한다.
- stack/collection/folder에서 제거가 source delete 권한을 암시하지 않는다.
- folder tree의 사용자 collapsed state는 새 folder 생성·refresh·restart 뒤에도 보존한다.

## 7. virtual copy

- virtual copy는 source bytes를 공유할 수 있다.
- develop/defect/metadata selection state는 copy별로 독립일 수 있다.
- 한 copy 제거가 공유 source를 삭제하지 않는다.
- 마지막 owner를 판단할 수 없으면 source delete action을 제공하지 않는다.
- relink는 같은 source family와 recipe binding을 일관되게 갱신한다.

## 8. Develop

### 8.1 기본값

- `main` target
- manual correction
- Neutral preset은 진짜 neutral 의미
- auto-develop default off
- existing frame은 global default 변경으로 retroactive 변경되지 않음

### 8.2 stage 의미

- negative/positive/digital source의 branch와 stage order를 manifest로 고정한다.
- input/working/output color domain을 stage마다 명시한다.
- extended-linear 값이 필요한 구간에서 0–1로 조용히 clamp하지 않는다.
- 8-bit fixture로 float pipeline correctness를 판정하지 않는다.
- NaN/Inf, invalid extent/dimension, corrupt array는 indexing 전에 거부한다.
- automatic measurement가 만든 parameter와 user parameter를 구분한다.

### 8.3 target

- `main`은 모든 출력 target의 canonical develop 기반이다.
- Print, scanner-emulation target 등은 이름만 다르게 표시한 같은 preset이 아니다.
- 각 target의 실제 stage와 source/provenance를 문서화한다.
- measured/profile-specific 결과와 generic look을 구분한다.
- ICC/측정 evidence 없이 device-accurate라고 부르지 않는다.

### 8.4 preview/export

- 같은 source, recipe, develop math를 공유한다.
- preview 해상도/cache/presentation transform은 다를 수 있다.
- final export에서 preview-only soft clip이나 display profile을 무조건 bake하지 않는다.
- interactive approximation이 있으면 gesture 종료 후 full-quality commit render를 한다.

## 9. color management

- scanner input, working, display, export, proof profile을 분리한다.
- working space는 문서화된 linear domain을 사용한다.
- monitor profile은 preview가 실제 표시되는 monitor 기준이다.
- window가 monitor를 옮기면 display transform을 갱신한다.
- soft proof는 destination/output profile과 intent를 명시한다.
- profile-only와 paper + black simulation을 구분한다.
- invalid/non-RGB ICC/ICM profile을 extension만 보고 적용하지 않는다.
- gamut warning은 warning overlay이며 output gamut conversion 자체가 아니다.
- HDR/Advanced Color는 별도 verified path 없이 SDR 색관리와 같다고 주장하지 않는다.

## 10. scanner

### 10.1 plugin boundary

- WIA/TWAIN/SANE/vendor SDK는 본체에 link/load하지 않는다.
- separate process, manifest, versioned JSON/NDJSON, staging file만 사용한다.
- 실제 plugin은 별도 저장소·license·signing·installer를 가질 수 있다.
- process separation은 법률 결론이 아니며 release 전 배포물 단위 검토가 필요하다.

### 10.2 capability truth

- resolution, bit depth, transparency, IR, preview, scan area, exposure, brightness, contrast는 plugin이 보고한
  capability만 사용한다.
- 모델명·USB ID·marketing spec로 option을 만들어내지 않는다.
- no implicit Mock fallback. Simulator는 explicit opt-in이다.
- device discovery와 usable scan capability를 구분한다.

### 10.3 request/result equality

```text
detected ROI
= user-confirmed/requested full-scan ROI
= plugin reported applied ROI
= output/manifest verified ROI
```

허용된 device quantization은 capability/response에 명시되고 tolerance가 사전에 정해져야 한다. silently
full-bed scan 후 host crop으로 성공을 가장하지 않는다.

### 10.4 film format

flatbed automatic frame workflow의 현재 지원 대상:

- 35 mm full
- 35 mm square
- 35 mm half
- 120 6×4.5, 6×6, 6×7, 6×8, 6×9, 6×12, 6×17

300-DPI positioned preview 또는 device가 지원하는 nearest positive DPI를 사용한다. format-aware geometry로
detected frame을 요청 ROI에 매핑하고, manual ROI를 항상 recovery path로 둔다.

### 10.5 hardware claims

- virtual/mock contract test는 physical scanner 증거가 아니다.
- USB enumeration은 backend support 증거가 아니다.
- `scanimage -L`, WIA/TWAIN device capability, 실제 preview/full scan을 구분한다.
- preview, single/full scan, all-format ROI, batch, IR, cancel, reconnect를 해당 device에서 검증한다.

## 11. async ownership

모든 async result는 적용 직전에 최소 다음을 확인한다.

- frame/session/job owner ID
- source identity
- parameter/recipe revision
- scanner capability token/request ID
- active window/workspace lifetime
- cancellation/supersession

오래된 result를 “어차피 같은 사진”이라고 적용하지 않는다. selection이 바뀌었다 돌아온 경우에도 revision이
다르면 폐기한다.

terminal event는 exactly once다. progress는 coalesce할 수 있다. cancellation과 success race는 commit point가
판정한다.

## 12. Export

### 12.1 reconstruction

- catalog snapshot, source, develop parameters, defect recipe, output recipe를 고정한다.
- 필요한 non-destructive result를 재구성할 수 없으면 visible failure다.
- cleaned cache나 preview가 없다는 이유로 original을 대신 export하지 않는다.
- selected frame과 snapshot owner를 file publish 직전까지 확인한다.

### 12.2 quality

성능을 위해 다음을 낮추지 않는다.

- pixel dimensions
- JPEG quality
- DPI metadata
- bit depth/format
- ICC profile
- color transform
- output sharpening setting

Quick Export도 이름만 빠른 별도 저품질 pipeline이 아니다. 사용자가 고른 format/DPI/long edge를 동일 final
render contract로 처리한다.

### 12.3 entry parity

- ordinary Export
- Quick Export
- Develop toolbar/menu
- Export/Output tab
- Print package export

어떤 entry에서도 naming, overwrite, progress, cancel, verification 의미가 갈라지지 않는다.

### 12.4 transaction

```text
plan/snapshot
→ app-owned staging
→ render/encode
→ verify size/dimension/profile/metadata/hash
→ journal intent
→ destination publish/replace
→ readback
→ commit acknowledgement
```

crash 뒤 ambiguous state를 임의 성공으로 표시하지 않는다. destination에 도착한 사용자 파일을 cache cleanup이
삭제하지 않는다.

### 12.5 progress

first-file preparation과 completed-file progress를 구분한다. 오래 걸리는 0% 상태는 다음 phase로 설명한다.

- snapshot/reconstruction
- source decode
- first render/shader/profile preparation
- encode
- verify/publish

실제 loaded photo와 large virtual batch를 모두 측정하고 39-photo single/contact/package scenario를 유지한다.

## 13. Print

- current v1 parity는 raster page/package export다.
- paper mm, DPI, margin, orientation, layout geometry가 truth다.
- preview DIP 크기로 final pixel geometry를 계산하지 않는다.
- sheet background와 paper/profile simulation을 구분한다.
- cyanotype/glass plate/gelatin을 측정된 물리 공정 simulation이라고 과장하지 않는다.
- Standard/C-Print/output process의 실제 profile/transform evidence를 manifest에 기록한다.
- direct printer path는 driver color management, printable area, cancel/spool evidence가 마련된 후 별도 추가한다.

## 14. storage와 cache

| 종류 | 사용자 data | clear 가능 | 원본 대체 가능 |
|---|---:|---:|---:|
| source/scanned original | 예 | 아니요 | 해당 없음 |
| catalog/recipe | 예 | reset/maintenance만 | 아니요 |
| thumbnail | 아니요 | 예 | 아니요 |
| scan preview | 아니요 | session cleanup | 아니요 |
| cleaned raw | 아니요 | identity-safe eviction | 아니요 |
| export/print output | 예 | 아니요 | 아니요 |
| backup | recovery data | retention transaction | 아니요 |

storage location 변경은 기존 파일을 자동 이동·삭제하지 않는다. migration을 만들면 명시적 plan, capacity,
copy/hash/readback, atomic switch, rollback을 가져야 한다.

## 15. backup과 recovery

- backup은 catalog만 복사한 것과 restore 가능한 generation을 구분한다.
- manifest/hash/schema/frame/recipe count를 검증한다.
- monotonic sequence를 ordering truth로 우선한다.
- external destination은 다른 volume, writable, connected, capacity sufficient인지 확인한다.
- restore drill은 isolated location에서 실제 open/validate한다.
- restore는 running model을 즉시 교체하지 않고 safe startup에 예약한다.
- corrupt primary를 forensic copy로 보존한다.
- future schema는 primary를 대체하지 않는다.
- 성공 전 marker/staging/generation을 삭제하지 않는다.

## 16. UI/UX

- native WinUI 3 control과 Windows convention을 사용한다.
- 제품 hierarchy와 state meaning은 macOS판과 99.9% 동등하게 유지한다.
- custom glass/pill/gradient/shadow/card wall을 만들지 않는다.
- ordinary control은 quiet, selected/stateful control만 지속 강조한다.
- slider는 full-width track, editable value, keyboard nudge, reset, gesture당 undo 하나를 유지한다.
- requested inline/equal-width rows와 non-wrap segment는 좁은 폭에서도 임의 wrap하지 않는다.
- loading/empty/error/disabled/recovery를 빠뜨리지 않는다.
- shortcut, context menu, drag/drop, focus, accessibility를 mouse-only UI보다 뒤로 미루지 않는다.
- folder collapse와 last selected Settings category 같은 사용자 표현 상태를 restart 후 보존한다.
- 사용자·제품 채널별 primary UI process는 하나이고 second launch는 기존 process로 전달한다.
- single-instance election은 실제 library process lock을 대체하지 않는다.
- main close는 전체 app 종료, auxiliary close는 해당 window 종료라는 현재 제품 의미를 유지한다.
- 정상 close의 verified commit과 OS session-end의 bounded recovery를 같은 save 기회로 취급하지 않는다.
- x64와 ARM64에서 activation·window ownership·shutdown semantics가 같아야 한다.

## 17. 성능

- image quality와 visible behavior를 바꾸지 않고 최적화한다.
- full-frame copy, redundant decode/render, allocator churn, UI invalidation을 먼저 줄인다.
- CPU가 충분히 빠른 작은/결정적 작업은 CPU에 둔다.
- GPU는 Intel/AMD/NVIDIA/Qualcomm 공통 D3D11 path가 기준이다.
- WARP/CPU fallback은 기능 완전해야 한다.
- CUDA는 optional measured NVIDIA acceleration일 뿐이다.
- ARM64는 첫 CLI부터 build/run/test한다.
- memory/VRAM budget을 고정 desktop 가정으로 정하지 않는다.
- interactive work가 background thumbnail/export에 starvation되지 않는다.

성능 결과는 representative hardware, workload, build, input, metric, percentile을 함께 기록한다.

## 18. 테스트와 실제 검증

### synthetic

- algorithm edge/branch/overflow/NaN/ROI
- deterministic numeric conformance
- corrupt payload/fault injection
- state machine/race

### real pixels

- 실제 loaded photo의 Develop/Export/Print
- high-bit-depth TIFF/JPEG/PNG/RAW 후보
- 35 mm/120 scan artifact
- ICC display/export/proof
- banding/halo/seam/orientation/metadata

### real UI

- app을 실제 실행
- click-through workflows
- keyboard/Narrator/high contrast/text scale
- multi-monitor/DPI/theme
- actual screenshots와 UI Automation state

### real hardware

- Intel/AMD/NVIDIA/Qualcomm CPU/GPU
- WARP
- actual scanner/device/driver
- local/removable/network/OneDrive-redirected volume
- printer는 direct-print scope일 때만

자동 test/build가 통과해도 실제 앱/장치/출력 검증을 하지 않았다면 그 범위는 완료가 아니다.

## 19. 라이선스·provenance

- GPL SANE code를 본체에 link/merge하지 않는다.
- WIA/TWAIN/vendor plugin의 source/binary/license/redistribution을 각각 검토한다.
- preset/profile/ICC/sample asset의 제작자·source·license를 추적한다.
- dependency는 SBOM/NOTICE와 actual staged payload가 일치해야 한다.
- third-party code의 algorithm/provenance claim을 문서·source에서 해결한다.
- 상표·기능명은 실제 승인과 legal review 없이 제품 branding으로 확정하지 않는다.
- process boundary는 architecture decision이며 법률 보증이 아니다.

## 20. release honesty

다음을 구분해 보고한다.

- compile
- unit/integration/conformance test
- GUI launch
- click-through UI QA
- physical scanner QA
- package install/upgrade/uninstall
- Authenticode signature
- timestamp/reputation
- notarization은 macOS 용어이며 Windows 서명과 혼동하지 않음
- published artifact와 source commit/provenance

local ad-hoc artifact, unsigned binary, build-only result를 release-ready라고 부르지 않는다.

## 21. 변경 절차

불변식을 바꾸려면:

1. 현재 macOS code/test와 사용자 결정을 인용
2. 문제를 재현
3. 두 플랫폼에 공통인 새 product behavior를 정의
4. data migration/rollback과 public API 영향을 분석
5. synthetic + real pixel/UI/hardware 검증 계획
6. decision register 갱신
7. 양쪽 baseline/delta manifest 갱신

Windows에서만 편의상 바꾸고 나중에 맞추겠다는 방식은 허용하지 않는다.

## 22. 빠른 금지 목록

- original in-place bake/overwrite
- third-party XMP overwrite
- corrupt catalog를 empty로 열기
- cleanup으로 user source/export 삭제
- cleaned cache를 recipe truth로 간주
- export reconstruction failure에서 original fallback
- implicit Mock scanner
- capability 없는 scanner control
- USB 발견을 지원 증거로 사용
- Software Defect Removal을 hardware IR과 동등 표기
- auto-develop default on
- preview와 export의 다른 math
- NVIDIA-only product feature
- x64 emulation을 ARM64 지원으로 표기
- build/test만으로 visual/hardware/release QA 완료 선언
