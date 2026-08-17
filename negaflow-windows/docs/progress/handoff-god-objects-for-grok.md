# God Object 해소 — 인계 문서 (Grok 4.6 전용)

작성일: 2026-08-17 · 대상 저장소: `C:\Users\habin\negaflow\negaflow-windows`

이 문서 하나만 읽고 시작할 수 있게 썼습니다. 아래 **1절 프롬프트를 그대로 복사해** 붙이면
됩니다. 2절 이후는 그 프롬프트가 참조하는 근거이며, 작업자가 판단이 필요할 때 읽는 자리입니다.

---

## 1. 그대로 붙일 프롬프트

```
당신은 negaflow-windows 저장소에서 God Object 를 해소합니다.
저장소 루트는 C:\Users\habin\negaflow\negaflow-windows 입니다.

## 절대 규칙 (어기면 작업 전체가 무효입니다)

1. 모든 소스 파일은 500줄 이하입니다. src/ 와 tests/ 아래 .cs · .cpp · .h · .xaml
   전부가 대상이며 예외는 없습니다. 500줄을 넘기려면 그 파일에 대한 구체적인 사유를
   docs/implementation/god-object-remediation.md 에 적어야 합니다. 사유 없이 500줄을
   넘는 파일은 미해결입니다.
2. 눈속임 금지. 다음은 해소로 인정되지 않습니다:
   - partial class 로 파일만 쪼개기
   - #include 로 조각내기
   - 같은 정적 상태를 공유한 채 파일만 옮기기
   서로 다른 "변경 이유"를 가진 책임(상태 / 오케스트레이션 / I/O / UI 이벤트)을
   실제 타입 경계로 옮겨야 합니다. 나눈 타입은 변경 이유가 하나여야 하고 입력·출력이
   명시적이어야 합니다.
3. 동작을 바꾸지 마십시오. 이 작업은 순수 구조 작업입니다. 함수 본문은 손대지 않고
   옮기기만 합니다. 알고리즘·임계값·순서를 "개선"하지 마십시오.
4. 하드코딩으로 문제를 회피하지 마십시오. 값을 박아 넣거나 검사를 건너뛰어 실패를
   없애는 것은 금지입니다.
5. 문제를 은폐하지 마십시오. 스크립트가 실패하면 그 스크립트를 고치십시오. 임시
   빌드나 우회 경로를 만들어 "되는 것처럼" 만들지 마십시오.
6. 커밋 메시지·코드·문서 어디에도 Claude / Anthropic / Grok / AI 관련 표기를 넣지
   마십시오. Co-Authored-By 트레일러도 금지입니다. 푸시 전에 나가는 커밋 범위를
   grep 해서 확인하십시오.
7. 커밋 메시지는 영어, 코드 주석과 docs/ 는 한국어입니다(저장소의 기존 관행).
   사용자에게 보고할 때는 한국어로 하십시오.
8. 검증하지 않은 것을 완료라고 쓰지 마십시오. 각 체크포인트마다 아래 명령이
   통과해야 합니다.

## 검증 (체크포인트마다 반드시)

    cd C:\Users\habin\negaflow\negaflow-windows
    .\scripts\build.ps1 -Preset x64-release
    .\scripts\test.ps1 -Preset x64-release          # 네이티브 CTest, 71/71 이어야 함
    .\scripts\test-managed.ps1 -Preset x64-release  # Catalog 721, Shell 1032 이상

세 개가 모두 통과하지 않으면 커밋하지 마십시오.

## 일감

docs/progress/handoff-god-objects-for-grok.md 의 4절에 500줄 초과 43개 파일이
우선순위 순으로 있습니다. 위에서부터 하나씩 해소하십시오.

한 파일을 끝낼 때마다:
  1. 세 검증 명령을 돌린다
  2. docs/implementation/god-object-remediation.md 의 그 줄을 갱신한다
     (해소했으면 나눈 결과를, 사유를 인정받았으면 그 사유를)
  3. 커밋한다. 커밋 메시지에 줄 수를 적기 전에 wc -l 로 먼저 재십시오
  4. 다음 파일로 넘어간다

푸시는 사용자가 따로 지시할 때만 하십시오.

## 이미 끝난 예 (이 방식을 그대로 따르십시오)

grain_mend_components.cpp 1,098줄 → 235줄, grain_mend_detector.cpp 600줄 → 242줄.
5절에 어떻게 갈랐는지 적어 두었습니다. 커밋 487d36b, 685a190 을 보십시오.

## 함정 (실제로 겪은 것들)

- 프로젝트 폴더 안에 obj\ 가 생기면 전체 빌드가 CS0579 로 무너집니다. 6절.
- 파일은 CRLF 입니다. LF 로 다시 쓰지 마십시오.
- 앱 실행은 .\scripts\run-app.ps1 뿐입니다. 빌드 폴더의 exe 는 실행되지 않습니다.
```

---

## 2. 이 규칙이 어디서 왔는가 (사용자 원문)

작업자가 규칙의 무게를 오해하지 않도록 사용자의 말을 그대로 옮깁니다. 축약하지 않았습니다.

> 현재 windows 프로젝트에서 500줄 이상인 God Object를 먼저 전수 식별·분해해라. 단순히
> 파일만 나누는 partial 분할로 눈속임하지 않고, 서로 다른 변경 이유를 가진 상태·
> 오케스트레이션·I/O·UI 이벤트 책임을 실제 타입 경계로 이동하고 조치해라. 유지보수
> 가능하게 세부폴더별로 파일과 코드 분할할것.

> 모든 God-object 의 기준은 500자 이하이다. 그 이상일경우에는 특별한 사유/이유/근거가
> 있어야한다. 따라서 모두 전면 수정해라. 메모리에 저장하고. 싹다!!!! 어느하나 빠짐없이.

> 특별한 사유 없이 500줄 넘는 God object 만들면 죽여버린다.

> God-Object 나오면 분해먼저하고 개발해라.

> 하드코딩해서 문제를 회피하지 말것. 가설이나 추측없이 검증해서 문제를 해결할것.

> 문제를 은폐하려고 하지말고 근본적인 문제의 원인을 해결하라고.

> 자체 빌드를 만들지말고 빌드 스크립트를 똑바로 만들라고. 매번 이지랄 할거야?

> 백엔드 구현 대충하고 된다고 구라치면 진짜 미국 법원에 소송한다. 마지막 경고다.

## 3. 메모리 기록 (규칙의 근거)

`C:\Users\habin\.claude\projects\C--Users-habin-negaflow\memory\` 에 저장된 항목입니다.
Grok 세션은 이 메모리를 읽을 수 없으므로 요지를 여기 옮깁니다.

### `god-object-500-line-rule`

negaflow-windows 의 모든 소스 파일은 **500줄 이하**여야 한다. 초과는
`docs/implementation/god-object-remediation.md` 에 그 파일에 대한 사유를 적어야만
허용된다. 기본 면제는 없다 — 사용자가 "어느 하나 빠짐없이" 적용된다고 못박았다.

**왜:** 책임이 몇 개의 거대한 파일에 쌓이면 사용자가 코드를 유지·수리할 수 없다. 사용자가
이 작업을 GrainMend 나 CI 보다 계속 앞세우는 이유이며, 유지 불가능한 코드베이스를 다른
모든 수정을 막는 것으로 본다.

**적용:** `.cs`·`.cpp`·`.h`·`.xaml` 을 다시 세고 500줄 초과를 모두 미해결로 다룬다.
`partial` 조각내기, `#include` 조각내기, 책임을 옮기지 않은 파일 이동은 **해소가 아니다.**
사유로 인정되는 것은 생성된 데이터 표, append-only 공개 ABI/DTO 선언 집합, 하나의 응집된
알고리즘이나 그 고정 입력 suite 정도이며, 각각 문서에서 따로 논증해야 한다.

**신규 파일에도 적용된다.** 2026-08-17 에 사용자는 이것을 *새로 만드는 것*에 대한 금지로
다시 말했다 — 새로 추가한 파일이 500줄을 넘으면 나중에 치울 일이 아니라 **그 자리에서
위반**이다. 쓰기 전에 나눌 계획을 세워야 한다.

### `no-workarounds-fix-root-cause`

빌드 스크립트·런처·시험 도구가 실패하면 **그것을 고친다.** 계속 나아가려고 일회성 우회를
만들지 않는다. 2026-08-17 에 사용자가 두 번 연속으로 강하게 말했다.

**왜:** 임시 우회는 배포되지 않는 빌드를 검증하므로 확인의 값어치가 없고, 진짜 결함은
저장소에 남아 다음 세션에 다시 발견된다.

**적용:** 실패한 단계가 곧 일감이다. 무엇이 원인인지 **먼저 재현해 특정한 뒤** 고친다.
값을 박아 넣거나 검사를 건너뛰거나 입력을 특수 처리해 실패를 없애지 않는다. 정말 범위 밖
이면 그렇게 말하고 실패한 채로 둔다 — 병행 경로를 만들어 성공이라고 보고하지 않는다.

### `quality-speed-optimization-always`

모든 변경은 **속도·최적화·품질** 세 축으로 함께 판단한다. 맞기만 한 변경은 끝난 것이
아니다. 전후를 측정해 숫자를 커밋 본문이나 검증 기록에 적는다.

**GrainMend 의 확정 수치(2026-08-17):** 자동 검출은 **앱에서 5초 미만**, 가이드·브러시·
복제·IR 은 **즉시**여야 한다.

### `no-claude-attribution`

저장소나 GitHub 에 남는 어디에도 도구 제작사 표기를 넣지 않는다. `Co-Authored-By` 트레일러
금지, "Generated with ..." 문구 금지, 코드 주석·문서·커밋 메시지에 언급 금지.
**왜:** 트레일러가 GitHub Contributors 목록에 나타나며 사용자가 원하지 않는다.
푸시 전에 나가는 커밋 범위를 grep 해 확인한다.

### `negaflow-windows-verification-habits`

- **최적화 전에 먼저 잰다.** 추측은 두 번 연속 틀렸다.
- **비트 동일성은 주장하지 말고 증명한다.**
- **macOS 코드가 실제로 호출되는지 확인한 뒤 이식한다.** 죽은 코드를 옮기면 원본 제품에
  없는 동작을 지어내게 된다.

### `match-macos-ui-exactly`

Windows 포팅에서 UI/UX 를 창작하지 않는다. 완성된 macOS 앱의 화면을 그대로 옮긴다.

---

## 4. 500줄 초과 전수 목록 (2026-08-17 재집계)

`src/` 와 `tests/` 의 `.cs`·`.cpp`·`.h`·`.xaml` **718개** 중 **43개**가 초과합니다.

### 4.1 사유가 인정된 것 (건드리지 마십시오)

| 대상 | 줄 | 사유 |
|---|---:|---|
| `src/Native/imaging/muted_scene_vibrance_table.cpp` | 9,003 | 생성된 데이터 표. 첫 줄이 `Generated by scripts/generate-civibrance-table.ps1` 이며 제어 흐름이 0개다. 실행 로직은 `muted_scene_vibrance.cpp`(121줄)에 있다 |
| `src/Native/abi/include/negaflow_abi.h` | 1,838 | 외부 소비자가 포함하는 append-only 공개 C ABI 선언 집합. 구현 상태가 없다 |

### 4.2 미해결 — 위에서부터 하십시오

| # | 대상 | 줄 | 첫 갈래 힌트 |
|---:|---|---:|---|
| 1 | `src/Native/abi/negaflow_abi.cpp` | 6,409 | 버전별 요청 매핑(`map_request_v*`) / 결과 쓰기(`write_*`) / preview / export / detect / infrared / flatbed. **요청 매핑만 빼도 절반이 갑니다** |
| 2 | `src/Shell/Views/DevelopWorkspaceView.xaml.cs` | 4,844 | macOS surface 단위 **실제 UserControl** 로 쪼개야 합니다. 5.3 참조 |
| 3 | `tests/Native.UnitTests/develop_export_abi_tests.cpp` | 4,107 | 시험 suite. 주제별 파일로 가르십시오(요청 검증 / preview / export / defect / infrared) |
| 4 | `src/Shell/Views/LibraryWorkspaceView.xaml.cs` | 2,835 | 그리드 가상화·필터·정렬·가져오기·드래그가 한 파일에 있습니다 |
| 5 | `src/Shell/Views/DevelopWorkspaceView.xaml` | 2,512 | 2번과 짝입니다. 카드마다 UserControl 로 나가면 함께 줄어듭니다 |
| 6 | `src/Interop/NativeDevelopExporter.cs` | 2,482 | 페이로드 빌더(`Build*Payload`) / 검증(`Validate*`) / 호출부로 갈립니다 |
| 7 | `src/Native/abi/include/negaflow_abi.h` | 1,838 | (4.1 사유 인정) |
| 8 | `src/Native/pipeline/develop_export.cpp` | 1,601 | 단계 실행 / detect 타깃 / preview 타깃 / gamut 표시 |
| 9 | `src/Native/core/tiff_probe.cpp` | 1,425 | 태그 파서 / 검증 / 레이아웃 판정 |
| 10 | `src/Native/imaging/infrared_defect_detector.cpp` | 1,197 | macOS 는 `InfraredDefectRemoval+*.swift` 10개로 나뉘어 있습니다. **그 경계를 그대로 쓰십시오** |
| 11 | `src/Shell/Views/LibraryWorkspaceView.xaml` | 975 | |
| 12 | `src/Native/imaging/defect_heal_brush.cpp` | 945 | |
| 13 | `tests/Native.UnitTests/grain_mend_tests.cpp` | 918 | |
| 14 | `src/Interop/NativeDevelopExportV2.cs` | 914 | 버전별 DTO 선언 — 4.1 의 ABI 헤더와 같은 사유가 될 수 있습니다. **논증하고 문서에 적으십시오** |
| 15 | `src/Native/imaging/auto_negative_base_resolver.cpp` | 893 | |
| 16 | `src/Catalog.Core/Storage/CatalogBackupStore.cs` | 885 | |
| 17 | `src/Native/imaging/flatbed_frame_grid_detector.cpp` | 862 | |
| 18 | `src/Catalog.Core/Defects/DefectSidecarCodec.cs` | 856 | |
| 19 | `src/Interop/DevelopExport.cs` | 844 | DTO 선언 집합 — 14번과 같은 논증이 가능합니다 |
| 20 | `src/Shell/Views/PrintWorkspaceView.Composition.cs` | 826 | |
| 21 | `tests/Native.UnitTests/tiff_probe_tests.cpp` | 824 | |
| 22 | `src/Native/imaging/film_scan_denoise.cpp` | 802 | |
| 23 | `tests/Native.UnitTests/manual_negative_developer_tests.cpp` | 772 | |
| 24 | `src/Interop/NativeMethods.cs` | 772 | P/Invoke 선언 집합 — 14번과 같은 논증이 가능합니다 |
| 25 | `src/Native/imageio/wic_tiff_decoder.cpp` | 765 | |
| 26 | `tests/Native.UnitTests/wic_tiff_decoder_tests.cpp` | 728 | |
| 27 | `src/Native/imaging/scanner_target_grade.cpp` | 713 | |
| 28 | `src/Catalog.Core/Defects/DefectRecipeValidator.cs` | 700 | |
| 29 | `src/Catalog.Core/Storage/CatalogCommitVerifier.cs` | 681 | |
| 30 | `src/Native/imaging/local_dodge_burn.cpp` | 656 | |
| 31 | `src/Native/imaging/texture_stage.cpp` | 646 | |
| 32 | `tests/Native.UnitTests/texture_stage_tests.cpp` | 620 | |
| 33 | `src/Native/imaging/digital_film_color_preset.cpp` | 597 | 데이터 표에 가깝습니다. 확인하고 논증하십시오 |
| 34 | `src/Shell.Core/Print/PrintPackageLayout.cs` | 592 | |
| 35 | `src/Native/output/wic_jpeg_export.cpp` | 577 | |
| 36 | `src/Native/output/wic_tiff_export.cpp` | 570 | |
| 37 | `src/Native/imaging/defect_component_structure.cpp` | 568 | |
| 38 | `src/Catalog.Core/Defects/DefectSidecarStore.cs` | 551 | |
| 39 | `src/Catalog.Core/Storage/SqliteCatalogStore.cs` | 541 | |
| 40 | `tests/Native.ConformanceTests/scalar_conformance.cpp` | 526 | |
| 41 | `src/Native/imaging/defect_clone_stamp.cpp` | 522 | |
| 42 | `src/Native/core/tiff_deflate_validator.cpp` | 515 | |

목록을 다시 뽑는 명령:

```bash
find src tests -type f \( -name '*.cs' -o -name '*.cpp' -o -name '*.h' -o -name '*.xaml' \) \
  -exec wc -l {} \; | awk '$1 > 500' | sort -rn
```

---

## 5. 이미 끝낸 두 건 — 이 방식을 따르십시오

### 5.1 `grain_mend_components.cpp` 1,098 → 235줄 (커밋 `487d36b`)

한 파일이 다섯 가지 서로 다른 일을 하고 있었습니다. 책임별로 갈랐습니다.

| 새 파일 | 줄 | 책임 |
|---|---:|---|
| `grain_mend_component_types.h` | 90 | 공용 `Component` 타입과 **조율값 한 표** |
| `grain_mend_component_gates` | 158 | 연결요소 라벨링, 먼지·스크래치 형태 게이트 |
| `grain_mend_structure_lines` | 345 | 격자·연장 판정으로 구조선 기각 |
| `grain_mend_grain_field` | 161 | 그레인 밭·고립 판정 기각 |
| `grain_mend_mask_paint` | 130 | 마스크 칠하기, 내부 구멍 메우기 |
| `grain_mend_component_classification` | 74 | 분류기 조립 |
| `grain_mend_components.cpp` (남은 것) | 235 | 오케스트레이션만 |

**요령 두 가지:**

- 조율 상수가 파일 곳곳에 흩어져 있었습니다. 공용 헤더의 `namespace tuning` 한 표로
  모았습니다 — 어떤 값이 실제로 쓰이는지 천 줄을 읽지 않고 보려면 그래야 합니다.
- 함수 본문은 **한 글자도 고치지 않고** 옮겼습니다. 옮기다 드러난 것은 헤더 선언이
  실제 정의와 어긋난 두 곳뿐이었고(`paint_component` 의 인자는 채울 값이 아니라 확장
  반지름, `is_isolated` 는 `noexcept`), 그것만 맞췄습니다.

### 5.2 `grain_mend_detector.cpp` 600 → 242줄 (커밋 `685a190`)

| 새 파일 | 줄 | 책임 |
|---|---:|---|
| `grain_mend_detection_image` | 114 | 축소, 휘도·최댓값 채널 만들기 |
| `grain_mend_scratch_angles` | 262 | 여덟 방향 능선 검출과 방향 적분 |
| `grain_mend_detector.cpp` (남은 것) | 242 | 후보 임계 판정만 |

가르다 보니 옛 파일이 **전이 포함으로 얻어 쓰던 헤더 두 개**가 드러났습니다
(`srgb_transfer.h`, `grain_mend_detection_image.h`). 쓰는 자리에 명시했습니다.

### 5.3 `DevelopWorkspaceView.xaml.cs` 는 왜 안 줄었는가

5,057 → 4,844 로만 줄었습니다. 순수 투영만 빼내는 방식은 한계에 닿았습니다 — 남은 4,300줄은
대부분 XAML 에 묶인 이벤트 핸들러입니다. **macOS surface 단위로 실제 `UserControl` 을
만들어야 합니다.**

성공한 예가 있습니다. GrainMend 레이어 목록을 그렇게 냈습니다(커밋 `c0529fc`):

```
src/Shell/Views/Controls/DefectLayerSection.xaml(.cs)   화면
src/Shell/Views/Controls/DefectLayerRowView.cs          한 줄이 내는 값
src/Shell/Views/Controls/DefectLayerBrushConverter.cs   상태 → 색
src/Shell/Views/Develop/DevelopWorkspaceView.DefectLayers.cs  배선(97줄)
src/Shell.Core/Develop/Presentation/DefectLayerProjection.cs  무엇을 낼지
src/Shell.Core/Develop/Editing/DevelopDefectLayerPanel.cs     조작
```

God object 는 **한 줄도 늘지 않았습니다.** 같은 방식으로 카드를 하나씩 떼어 내십시오.

---

## 6. 함정 (실제로 겪은 것)

### 6.1 프로젝트 폴더 안의 `obj\` — 전체 빌드가 무너집니다

증상: 모든 프로젝트가 `CS0579: 특성이 중복되었습니다` 로 실패. `dotnet clean` 으로 **안
고쳐집니다.**

원인: `Directory.Build.props` 가 `obj`·`bin` 을 `out\` 으로 옮겨 놓았습니다. 그런데 무언가가
프로젝트 폴더 안에 `obj\` 를 만들면(예: 상대 경로 `BaseIntermediateOutputPath` 로 publish 를
한 번 돌리면 모든 프로젝트에 생깁니다) 기본 `**\*.cs` 글롭이 그 안의 생성된 AssemblyInfo 를
함께 컴파일합니다.

확인하는 법 — 추측하지 말고 MSBuild 에게 물으십시오:

```powershell
dotnet build .\src\Catalog.Core\Negaflow.Catalog.Core.csproj -c Release -p:Platform=x64 `
  --runtime win-x64 --self-contained true --getItem:Compile
```

`obj\` 가 들어간 Identity 가 보이면 그것입니다.

치료:

```powershell
Get-ChildItem -Path src, tests -Directory -Recurse -Filter 'obj' | Remove-Item -Recurse -Force
```

`Directory.Build.props` 에 `DefaultItemExcludes` 로 막아 두었지만, 이미 생긴 것은 지워야
합니다.

### 6.2 앱 실행

```powershell
.\scripts\run-app.ps1 -Architecture x64 -Configuration Release
```

빌드 폴더의 `Negaflow.Shell.exe` 를 직접 실행하면 **되지 않습니다.**
`WindowsPackageType=MSIX` 라 apphost 가 런타임을 앱 폴더에서만 찾아
"You must install or update .NET" 으로 끝납니다. 스크립트는 배포와 같은 길(패키지 →
`makeappx unpack` → 느슨한 레이아웃 등록 → AUMID 실행)을 갑니다. `-Unregister` 로 치웁니다.

### 6.3 줄 끝

저장소 파일은 **CRLF** 입니다. PowerShell 로 파일을 다시 쓸 때
`New-Object System.Text.UTF8Encoding($false)` 로 **BOM 없이** 쓰고 `WriteAllLines` 를
쓰십시오(CRLF 를 유지합니다).

한글이 든 `.ps1` 스크립트를 만들 때는 **BOM 이 필요합니다.** Windows PowerShell 5.1 은 BOM
없는 파일을 ANSI 로 읽어 한글이 깨지고 파싱 오류가 납니다.

### 6.4 지역화 파일

`src/Shell/Strings/{en-US,ko-KR,ja-JP,zh-Hans,fr-FR,de-DE}/Resources.resw` 여섯 개는
**항목 수가 같아야 합니다**(현재 각 645개). 하나만 고치면 안 됩니다.

### 6.5 간헐적 시험 실패

게이트를 연달아 돌리면 Catalog suite 가 한 번씩 실패할 때가 있습니다. 단독 실행하면 721개가
모두 통과합니다. 소스 변경과 연결된 재현은 아직 없습니다 — 실패하면 단독으로 한 번 더
돌려 보십시오.

---

## 7. 이 작업과 GrainMend 이식의 관계

같은 저장소에서 GrainMend 를 macOS 에서 이식하는 작업이 동시에 진행됩니다
(`docs/progress/handoff-2026-08-17.md`). 충돌을 피하려면:

- **GrainMend 네이티브 파일은 이미 전부 500줄 아래입니다.** 다시 건드리지 마십시오.
  (`grain_mend_*` 중 가장 큰 것이 `grain_mend_structure_lines.cpp` 345줄)
- 4.2 목록의 **1·2·3·4·5·6번**부터 하시면 겹치지 않습니다.
- `src/Shell.Core/Develop/**` 와 `src/Shell/Views/Controls/DefectLayer*` 는 GrainMend
  쪽에서 활발히 바뀝니다. 마지막에 하십시오.

---

## 8. 완료 판정

- `find` 재집계에서 500줄 초과가 4.1 의 사유 인정 항목만 남는다.
- `docs/implementation/god-object-remediation.md` 의 모든 줄에 해소 결과 또는 논증된
  사유가 적혀 있다.
- 세 검증 명령이 모두 통과한다.
- 커밋 범위에 도구 제작사 표기가 없다.
