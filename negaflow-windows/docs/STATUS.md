# 구현·검증 상태

기준일: 2026-08-09

| 항목 | 상태 | 증거 |
|---|---|---|
| exact macOS baseline | 고정 | `baseline/bootstrap-manifest.json` |
| canonical source asset hash | bootstrap 완료 | `baseline/source-assets.sha256` |
| 개발 도구 | 검증 | Visual Studio Community 2026 18.8.2, MSVC 14.51 x64/ARM64, SDK 26100, .NET SDK 10.0.302/runtime 10.0.10, C# Windows App SDK component |
| x64 CMake configure/build/run | 통과 | Debug/Release clean configure·build·CLI 실행 |
| x64 native tests | 통과 | 2026-08-09 Release CTest 30/30 통과 |
| ARM64 cross build | 통과 | Debug/Release 전체 target build, CLI/DLL PE `AA64` |
| ARM64 native run | 미검증 | 실제 ARM64 Windows runner 필요 |
| .NET 10/C ABI Interop | 게시·미리보기 파이프라인 노출 | `LibraryImport`, 절대 경로 resolver, ABI/layout 검증에 더해 v1 수동 경로와 `nf_develop_export_v2`/`nf_develop_preview_v2`의 명시적 Auto·Manual base 경로를 호출. ABI 0.6, struct 크기·offset 을 네이티브 `static_assert` 와 관리 assertion 양쪽에서 고정. x64 Debug interop 50 assertions |
| 네이티브 파이프라인 라이브러리 | 분리 완료 | `negaflow_pipeline` 이 `develop_and_export` 와 Film Look workspace 를 소유. CLI 는 workspace 를 이 라이브러리에서 링크. CLI 자체 순서 코드의 수렴은 미완 |
| WinUI shell | 첫 관통 경로 통과 | component package 1.8 locked graph, x64 실제 최대화 실행, ARM64 교차 빌드, 6개 언어, 오른쪽 caption inset, Settings와 SHA 기본 `끔`; 2026-08-09 Shell 200 assertion 통과 |
| static runtime 배포 기반 | 통과 | Release CLI 직접 dependency가 Windows 기본 DLL 5개뿐이며 VC++ Redistributable DLL 없음 |
| float32 pixel contract | 부분 구현 | checked layout/stride/capacity, extended RGB, straight alpha, NaN/Inf 거부 |
| scalar pointwise·spatial | 부분 구현 | exposure, RGB 3×4 matrix, 기본 톤·4-band curve, 고정 64표본 DR/R/G/B point curve, 8-band HSL Color Mixer, 3구간 Color Grading, R/G/B Primary Calibration, 11종 RGB33 Film Emulation 색상→11행 acutance film-scan route x64 test·ARM64 build |
| Film Look source routing | CLI·첫 WinUI 수직 경로 통과 | 명시적 `film_scan`/`rendered_digital`, film 색상→acutance exact 순서, caller cube/scratch, 실패 시 pixel 폐기; 진단·PNG16·TIFF16에서 Primary Calibration 뒤 실행, 실제 TIFF artifact 변화 검증; 미완성 digital graph는 `unsupported_route`; film-scan catalog projection은 C ABI와 첫 WinUI 관통 경로에 연결됐고 정식 UI control surface는 미구현 |
| Catalog Develop route | SQLite→C ABI→WinUI 첫 연결 통과 | `scanner`/`imported` transport와 film/digital signal 분리, legacy marker·강도 1.0 호환, 새 강도 0.5, unknown field 보존, invalid 조합 fail-closed; SQLite snapshot의 frame을 `DevelopExportRequest`로 투영해 ABI 0.6 게시·미리보기에서 사용. Auto는 v2 resolver, Manual은 v2 Dmin, Preset은 명시 거부. 전체 macOS Develop control surface와 rendered-digital graph는 미구현 |
| 세로 슬라이스 (catalog→C ABI→WinUI) | 앱 안에서 한 바퀴 완결·미리보기 연결 | Import→필름 base 슬라이더→노출→Export 를 UI Automation 으로 실제 조작해 `Exported 631×403 in 101 ms` 확인. base 슬라이더 범위가 엔진의 0.001..1.0 을 그대로 받음. 시작 시 `library.sqlite` 생성·lock 획득. ABI 0.6 미리보기를 `WriteableBitmap` 캔버스에 표시하고 겹친 요청은 마지막 상태를 보존. macOS와 동일한 정식 Develop UI, base picker, 취소·진행률은 미구현 |
| catalog SQLite 영속성 | 첫 왕복 통과 | `catalog_metadata` + entity table 9개, 물리 `user_version=1`과 논리 `catalog_version=1` 분리, 재정렬 시 position relocation, pooling 끔, missing/corrupt/미래 version/외부 version/malformed 5종 구분, commit 후 `integrity_check`; x64 Release 303 assertion, ARM64 교차 빌드. backup 세대·pending restore·defect sidecar·C ABI 연결은 미구현 |
| catalog 단일 작성자 강제 | 구조로 강제·프로세스 경계 관측 | `SqliteCatalogStore`는 `internal`. 공개 입구는 `CatalogSession` 하나이며 프로세스 lock 을 못 잡으면 세션이 만들어지지 않음. `NotFound`→빈 라이브러리 변환은 `ReadOrCreate` 한 자리뿐이고 손상·미지원 version 은 거기서도 실패. lock 없이 되는 것은 `CatalogRecovery.IsValidCatalogSource` 확인뿐 |
| catalog 성능 (5만 frame) | 목표 규모 측정 완료 | 최초 쓰기 527ms, 전체 읽기 255ms, 무변경 재저장 343ms, 1건 편집 337ms, 전체 뒤집기 582ms, 파일 10.1MB. 비용이 변경량이 아니라 catalog 크기에 비례함을 기록 |
| 관리 계층 SQLite 의존성 | 고정·취약점 0 | `Microsoft.Data.Sqlite.Core` 10.0.10(MIT) + `SQLitePCLRaw.config.e_sqlite3` 3.0.5 + `SourceGear.sqlite3` 3.53.4(Apache-2.0). 편의 package 는 CVE-2025-6965 native 하한 때문에 배제(ADR-0025) |
| 배포 payload 제3자 native | 최초 도입·범위 축소 | `e_sqlite3.dll` 2종. 네이티브 엔진의 제3자 0개는 유지되나 제품 payload 는 더 이상 0개가 아님. 비Windows RID 28종 제외로 53,571,344→3,788,288 바이트 |
| scalar negative inversion | 부분 구현 | color/B&W `shoulder-print-response-v4`, 고정 float bits와 합성 anchor test |
| 수동 negative develop | 첫 수직 경로 통과 | 채널별 Dmin, color/B&W 고정 response, working buffer 제자리 변환과 scalar exact 일치 |
| TIFF bounded probe | 부분 구현 | Classic/BigTIFF, endian 양쪽, strip/tile bounds, compressed-byte 합계, 선택형 LZW code-stream 의미 검사·작업량 상한·취소, Unicode read-only CLI, 손상 합성 corpus |
| WIC TIFF decode | 수직 경로 통과 | 단일 read-only stream preflight/decode, Microsoft 기본 decoder 고정, RGB/RGBA 16-bit none/LZW, LZW 의미 검사 필수, 독립 검사기 없는 Deflate 격리, ICC 추출, decoded-byte 사전 한도, sink 기반 행 streaming·취소·진행률; 사용자 TIFF 15/15 |
| scanner→working color | 수직 경로 통과 | untagged linear raw 9개와 embedded ICC→ICM→sRGB16→linear float 6개, 64행 streaming 15/15, whole-frame 최종 float exact 일치 15/15 |
| PNG16 output | phase 0 수직 경로 통과 | working→sRGB16, Microsoft WIC encode, 등록 sRGB ICC, 구조·전체 pixel·profile readback, 기존 파일 비덮어쓰기와 같은-directory 게시 |
| TIFF16 output | phase 1 수직 경로 통과 | 무압축 RGB16 Classic TIFF, 단일 IFD, 최소 metadata allowlist, 전체 pixel·ICC readback, 원본 상태 관찰, 단계별 CLI report와 비덮어쓰기 게시 |
| M4 최소 tone | 확장 수직 경로·첫 앱 연결 통과 | 노출→기본 톤→동적 band→파라메트릭 curve→point curve→Color Mixer→Color Grading→Primary Calibration→명시적 film-scan Film Look→TIFF16/PNG16 검증 게시; SQLite catalog→C ABI 0.6→WinUI의 노출·미리보기·Export 연결 확인. 나머지 조정의 정식 macOS 동등 UI는 미구현 |
| M4 단계 진단 | 확장 수직 경로 통과 | 기본 export stage wall/process-CPU, 진단 전용 scanner/develop/tone/Film Look min/max·versioned 비암호 fingerprint, Film Look route·cube/scratch·시간 보고, tone 24·point curve 24·Color Mixer 48·Color Grading 48·Primary Calibration 48·Film Emulation 색상 48/acutance 36-value conformance |
| 이미지 SHA-256 | opt-in 기반 통과 | 기본 `off`는 파일 I/O 0, 명시적 CNG SHA-256 known-answer/multi-chunk/cancel, 사용자 TIFF opt-in 15/15 |
| 네이티브 엔진 제3자 runtime dependency | 0개 | 빈 vcpkg dependency, WIC/ICM/Win32만 사용 |
| WinUI package graph | 고정·감사 | Runtime/WinUI 1.8 component 직접 참조, transitive 명세, 취약 package 0, AI/ML/Widgets 제외, 미사용 WebView2 payload 1.6MB를 x64/ARM64 clean build 출력에서 제외 |
| 제3자 고지 | 기록 완료 | `THIRD-PARTY-NOTICES.md`에 App SDK 조건, 미배포 WebView2 경계, SQLite 스택의 MIT 1건·Apache-2.0 4건 기록. `components.json` 배포 게이트 갱신 |
| Windows 빌드 CI | 구현 완료 | `.github/workflows/windows.yml`의 native·managed·arm64-cross 잡과 로컬 짝 `scripts/ci-gate.ps1`. 러너의 VS 2026과 .NET 10.0.302를 그대로 써서 로컬과 같은 프리셋으로 빌드 |
| ColorSync↔ICM 색상 동등성 | 측정 완료·판정 보류 | 34패치 중 21개 비율 1.000, 깊은 섀도우에서 최대 20.37배. 원인은 ColorSync의 1/16 toe. 현상 후 8비트 코드 2~6, 채널 스프레드 최대 5. ADR-0024로 재현하지 않기로 결정 |
| GPU/WARP | 미구현 | M5 이후 |
| installer/signing | 미구현 | .NET 10과 Windows App Runtime 1.8 prerequisite 연결, SBOM/signing은 M17 범위 |

## 2026-08-06 변경

권리·운영 점검에서 나온 변경입니다. 이 날짜에 x64 Release clean 네이티브 빌드와 `ctest` 37/37,
관리 solution clean 빌드(경고 0·오류 0)와 관리 테스트를 다시 실행해 확인했습니다.

- 저장소 루트에 `.gitattributes`(`* text=auto eol=lf`)를 추가했습니다. 그 전에는 Windows 체크아웃이
  CRLF 작업 사본을 만들어 `verify-provenance.py`의 리소스 SHA-256이 어긋났고, Windows에서 게이트를
  전혀 돌릴 수 없었습니다. 이제 로컬에서 통과합니다. blob은 원래부터 LF였으므로 저장소 내용은
  바뀌지 않았습니다.
- 미사용 WebView2 payload를 셸 출력에서 제외했습니다(ADR-0022).
- 제3자 고지를 `THIRD-PARTY-NOTICES.md`로 기록했습니다.
- macOS golden의 관측 경계를 ADR-0021로 고정했습니다.

build ID는 빌드 당시 미커밋 작업이 있으면 `-dirty`로 표시합니다. ARM64 test executable은 빌드됐지만 x64
호스트에서 실행하지 않았으므로 ARM64 runtime 통과로 표시하지 않습니다.

## 2026-08-07 변경

카탈로그가 처음으로 디스크에 남습니다. 근거는 `verification/2026-08-07-sqlite-catalog-store.md`,
결정은 ADR-0025입니다. 이 날짜에 `ci-gate.ps1 -Preset x64-release` 전체(네이티브 40/40, 관리
303+188 assertion과 interop 44, 경고 0)와 ARM64 관리 교차 빌드, `verify-provenance.py`를 다시 실행했습니다.

- `SqliteCatalogStore`를 추가했습니다. macOS의 table 배치를 그대로 옮기되 물리 schema version과
  논리 catalog version을 분리하고, 없는 파일·손상 파일·미래 물리 version·외부 논리 version·
  malformed payload를 각각 다른 값으로 거부합니다. 어느 것도 빈 라이브러리가 아닙니다.
- 재정렬에서 `position` UNIQUE 제약을 어기는 경로를 찾아 relocation 단계를 넣었습니다. 단계를
  빼면 frame 3개를 재정렬하는 것만으로 쓰기가 실패하는 것을 확인했습니다.
- `CatalogSession`으로 프로세스 lock 과 store 를 묶었습니다. store 를 `internal`로 내려
  lock 없이 카탈로그를 여는 공개 경로를 없앴습니다. 규율이 아니라 구조로 막습니다.
- 편의 package `Microsoft.Data.Sqlite`를 배제했습니다. native SQLite 하한이 CVE-2025-6965 대상이라
  restore 자체가 NU1903으로 실패합니다. 추측이 아니라 restore 출력에서 걸린 것입니다.
- 비Windows RID의 native payload 28종을 빌드 출력에서 제외했습니다. 53,571,344 → 3,788,288 바이트.
- **제품 payload에 제3자 native 바이너리가 처음 들어왔습니다.** 네이티브 엔진의 제3자 0개는
  그대로지만 두 문장은 이제 다른 뜻이므로 고지 문서에서 구분했습니다.
- `nf_develop_export_v1` 로 파이프라인 전체를 C ABI 에 노출했습니다. 그 전까지 셸이 프레임 한 장을
  현상하려면 CLI 프로세스를 띄우는 수밖에 없었습니다. 순서 코드를 복사하지 않기 위해 CLI 안에
  있던 것을 `negaflow_pipeline` 정적 라이브러리로 꺼냈습니다.
- ABI 를 0.2 로 올리고 관리 loader 의 최소 minor 도 올렸습니다. 낡은 엔진은 첫 export 호출이 아니라
  load 시점에 거부됩니다.
- `dumpbin /dependents` 로 확인: imaging·output 을 링크한 뒤에도 `Negaflow.Native.dll` 의 직접
  import 는 `KERNEL32`, `SHLWAPI`, `ole32`, `mscms` 뿐입니다. 네이티브 엔진의 제3자 0개는 유지됩니다.

전체 M0~M18 로드맵 진행률은 산출물 기준 약 16%, 현재 M0~M3 기반 구간은 약 50%로 추정합니다.
`M14 영속성`이 SQLite 왕복까지 올라왔으나 backup 세대·pending restore·legacy migration·defect
sidecar가 남아 있으므로 완료로 세지 않습니다. 색상 수직 경로가 실제 코퍼스를 처리했다는 사실과
ColorSync 수치 동등성은 계속 구분합니다. 산정 방식과 단계별 공백은 `progress/overall-roadmap.md`에
있습니다.

## 2026-08-09 재검증과 문서 동기화

현재 코드가 ABI 0.5 미리보기와 WinUI 캔버스 렌더까지 포함하는데도 이 문서와
`progress/next-steps.md`가 ABI 0.4와 “미리보기 미구현/다음은 import” 상태에 머물러 있던 것을
수정했습니다.

- `scripts/ci-gate.ps1 -Preset x64-release`: native CTest 30/30, Catalog 303 assertion,
  Shell 200 assertion, managed build 경고 0·오류 0.
- `scripts/test-interop.ps1 -Preset x64-release`: Interop 44 assertion, ABI 0.5, x64.
- `py negaflow-mac/scripts/ci/verify-provenance.py`: 파일 1,764개, text 1,721개, binary 43개,
  선언 resource 29개, reachable commit 137개 검증 통과.

이번 재검증에서는 ARM64 교차 빌드나 실제 ARM64 실행을 다시 수행하지 않았습니다. 위 표의 기존
ARM64 교차 빌드 증거는 유지하지만 실제 ARM64 runtime은 계속 미검증입니다.

## 2026-08-09 Base recipe catalog projection

`params.baseEstimationMode`, `filmStockDminID`, `lightSourceProfileID`,
`scannerProfileID`를 기존 `manualBaseRGB`와 독립적으로 Catalog projection에
보존합니다. 이 저장 경계는 이후 Auto v2 resolver가 추가돼도 그대로 유지됩니다. Film preset
Dmin/Dmax/light-source resolver, scanner profile grade, WinUI mode/picker, canvas
base picker는 아직 없습니다. Catalog unit test는 이후 Auto 계약을 포함해 x64 Debug 315 assertions가
통과했습니다.
수동 Base RGB를 편집하면 기존 preset ID는 보존한 채 `baseEstimationMode`를 `Manual`로
기록합니다. 따라서 저장된 recipe가 실제 수동 Dmin 현상 경로와 모순되지 않습니다.

## 2026-08-09 Scene-ranged manual negative

수동 Dmin 현상은 충분한 linear working image에서 64…320 폭의 6% inset 표본을 사용해
채널별 low-percentile density range를 구합니다. base luma gate, chromogenic dark-pixel gate,
1.8D/0.4D 하한과 low-DR smoothstep 축소를 적용하며, B&W는 기하 평균 하나를 세 채널에
공통 적용합니다. 작은 입력은 기존 film-type normal range로 되돌아가고, malformed input은
기존처럼 fail-closed로 픽셀을 공개하지 않습니다. 일반 2:3 세로 frame의 macOS 320×480 표본은
보존하고, 더 극단적인 panoramic input만 통계용 표본 153,600개로 제한합니다. 이 변경은 아직
macOS full Auto estimator, `CIVibrance`와 동등한 muted-scene 후처리, Film preset resolver를
구현하지 않습니다. Auto v2 scene-edge fallback은 아래 별도 slice에 기록합니다.

x64 Debug native CTest 30/30과 `native.manual_negative_developer`의 색상 channel별
1.10/0.99/0.88D, B&W 공통 range 회귀 검사가 통과했습니다.

수동 Base R/G/B도 `InspectorSlider` composite로 교체했습니다. 이 controls는 54 DIP 편집값,
0.01/0.10 keyboard nudge와 stable AutomationId를 제공하지만 macOS 수동 Base 계약에 맞춰 reset은
제공하지 않습니다. x64 WinUI 렌더에서 Base Red `Right`의 `0.00 → 0.01`과 Export 가능 상태 전환을
확인했습니다. Auto/Film mode, picker, canvas base picker, UIA editor/고대비/compact/ARM64 runtime은
미검증입니다.

## 2026-08-09 Develop slider 첫 UI slice

임시 Develop surface의 Exposure를 `InspectorSlider` composite로 교체했습니다. 이 control은
54 DIP 편집값, 0.01/0.10 keyboard nudge, 범위·finite-value 검사, double-click reset과 기존
`negaflow.develop.exposure` AutomationId를 제공합니다. recipe, catalog, C ABI와 preview/export
수식은 변경하지 않았습니다. 값 editor는 `.value` AutomationId와 label·입력 범위 HelpText를 가지며,
`Enter`/수정한 focus-loss commit, `Escape`/수정하지 않은 focus-loss cancel, invalid input의 빨간색·beep·오류
HelpText 및 다음 입력의 오류 해제를 구현합니다. x64 Debug shell build(경고 0·오류 0), managed Catalog
314/Shell 209 assertion, native CTest 30/30과 실제 x64 WinUI 렌더·Right key `-1.00 → -0.99`를 확인했습니다.
Base의 Auto/Film/Manual contract와 최신 editor 상호작용의 UIA runtime, high contrast/compact/ARM64 runtime은
미검증입니다.
상세는 `implementation/develop-inspector-slider.md`에 기록합니다.

## 2026-08-09 Auto base v2 scene-edge slice

v1의 수동 Dmin request/result 레이아웃과 export를 유지한 채 ABI 0.6에
`nf_develop_export_v2`/`nf_develop_preview_v2`를 추가했습니다. v2는 Auto·Manual mode를
명시하고, 성공 결과에 실제 적용 Dmin과 `manual`/`auto_scene_edge`/`auto_fallback` provenance를
돌려줍니다. Preset은 stock resolver가 없으므로 Auto로 묵살하지 않고 Shell과 native validation에서
명시 거부합니다.

Auto는 decode 뒤 linear `WorkingImage`의 6% edge 표본에서 색상/중립 후보를 골라 90th-percentile
Dmin을 결정하고, 후보가 없으면 macOS의 color `(0.86, 0.68, 0.50)` 또는 B&W `(0.80, 0.80, 0.80)`
fallback을 사용합니다. 그 결과는 preview와 export가 공유하는 기존 scene-ranged inversion에 한 번만
전달됩니다. 저장된 stale manual Dmin은 Auto mode에서 request에 사용하지 않습니다. Color/B&W positive
film은 negative inversion으로 보내지 않고 Catalog/Shell에서 명시 거부합니다.

x64 Debug native CTest 30/30, managed Catalog 315/Shell 219 assertions, interop 50 assertions
(ABI 0.6)이 통과했습니다. 이 당시에는 연결 성분 외의 Auto fallback이 아직 없었으며,
이후 sampled-grid fallback update에서 비필름 배제/확장, distributed·strip fallback을 추가했습니다.
cache/diagnostic은 남아 있습니다. 정식 Auto parity나 Auto/Film/Manual mode UI 완료로 세지 않습니다.

## 2026-08-09 Auto sampled-grid fallback update

`auto_connected_component`가 성립하지 않을 때에도 동일한 32–256 linear sample grid에서
non-film dilation, continuous border, distributed mask, 그리고 strip fallback을 macOS 순서대로
실행합니다. 이 compatibility fallback은 ABI layout을 바꾸지 않고 경로별 provenance 값을 보고합니다.
x64 Debug `native.manual_negative_developer`에서 hard-bright backlight, 색상 backlight
demote, non-film masked strip, continuous border, distributed mask와 fixed fallback을 검증했습니다.
cache/diagnostic과 macOS golden fixture 기반 image-result 비교는 아직 없습니다.

같은 resolver는 B&W Auto 결과의 max/min channel ratio가 `1.25`를 넘으면 color candidate path를 한 번
재시도합니다. 이로써 chromogenic B&W의 tinted base를 channel별 Dmin으로 보존하되, color path도
측정에 실패하면 기존 neutral result를 유지합니다. x64 Debug native unit test로 이 재시도를 검증했습니다.

ABI 0.8에서는 결과 layout을 유지하면서 `auto_continuous_border`, `auto_distributed_mask`,
`auto_strip_fallback` 값을 추가했습니다. 이전 `auto_scene_edge` 값은 호환을 위해 보존하며,
새 managed enum과 native ABI test가 새 provenance 값을 검증합니다.
## 2026-08-09 Basic Tone v3 vertical slice

macOS Basic Tone recipe `contrast`, `density`, `highlight`, `shadow`, `whites`, `blacks`를 Catalog의 missing=0 reader/writer와 Shell request factory에 연결했습니다. ABI 0.9 append-only `nf_develop_export_request_v3`/`nf_develop_preview_v3`가 이 다섯 값을 native `BasicToneParameters`로 전달합니다. v1/v2 layout과 Parametric Tone Curve fields는 동결되어 있습니다.

WinUI Inspector에는 `Exposure → Contrast → Highlights → Shadows → Whites → Blacks → Density` 순서의 composite controls와 stable IDs를 추가했고, positive/digital frame에서 tone mutation을 거부합니다. x64 Debug native CTest 30/30, Catalog 317 assertions, Shell 248 assertions, interop 52 assertions(ABI 0.9)을 통과했습니다. computer-use로 Debug Shell 창은 관찰했지만 state/capture runtime 오류가 있어, 실제 WinUI render/UIA/keyboard/high-contrast/compact/ARM64 runtime 증거는 아직 없습니다.

## 2026-08-09 Film preset base v4 slice

Catalog recipe의 Film mode가 27개 bundled stock과 5개 light-source ID를 ABI 0.10 v4 request로 전달하고,
native CPU resolver가 measured-first/fallback Dmin, stock Dmax response, light gain을 적용합니다. Auto/Film/Manual
WinUI control과 stable picker IDs도 연결했습니다. v1~v3 ABI layout·entry point·Preset refusal은 유지합니다.

x64 Debug native CTest 30/30, Catalog 317 assertions, Shell 267 assertions, ABI 0.10 interop 54 assertions을
통과했습니다. 사용자가 제공한 5088×3401 16-bit TIFF는 CLI 수동 Dmin 경로로 PNG16 export까지 통과했으며 결과는
100,377,638바이트와 SHA-256 `eab2e899b9e9a913be5a141afca9835040f36d3d28dd8e3bb86dcf044b54708b`입니다.
이 실제 TIFF 증거는 Film preset request나 rendered/UIA/keyboard/high-contrast/compact/ARM64 runtime 증거가 아닙니다.
scanner-profile grade, canvas picker/reset, macOS confident-only estimator 비교도 남아 있습니다.

같은 소스에서 x64 Release native CTest 30/30, Catalog 317 assertions, Shell 267 assertions, ABI 0.10
interop 54 assertions과 native/managed ARM64 교차 빌드를 통과했습니다. provenance gate는 files=1773,
text=1730, binary=43, declared_resources=29, reachable_commits=137을 확인했습니다. ARM64 runtime은
실행하지 않았습니다.

## 2026-08-09 Parametric Tone Curve control slice

기존 Catalog/ABI/native path의 `curveHighlights`, `curveLights`, `curveDarks`, `curveShadows`를 WinUI의
별도 `Tone curve` 그룹으로 연결했습니다. AutomationId는 각각
`negaflow.develop.curve.highlights`, `.lights`, `.darks`, `.shadows`이며, Basic Tone의 동명
Highlights/Shadows와는 다른 recipe field입니다. Shell state는 엔진 tone-control 범위로 clamp하고
positive/digital frame의 mutation을 거부합니다. x64 Debug 관리형 build warning/error 0, Catalog 317,
Shell 255 assertions을 통과했습니다. 아래 Point Curve v5 slice가 `ToneCurveEditor`를 연결했습니다.

## 2026-08-09 Color Mixer recipe v6 vertical slice

## 2026-08-09 Color Grading recipe v7 vertical slice

`params.colorGrading`의 Shadows/Midtones/Highlights hue·saturation·luminance와
blending/balance를 Catalog read/write, Shell request factory, ABI 0.13
`nf_develop_export_request_v7`/`nf_develop_preview_v7`, native CPU pipeline,
WinUI `ColorGradingEditor`까지 연결했습니다. v7는 v6 prefix 뒤에 11개 float를 append하므로
이전 ABI entry point와 layout은 유지합니다. Inspector는 세 range selector, 150 DIP
hue/saturation wheel, luminance/blending/balance slider 및 pointer capture·keyboard nudge를
제공하며 preview와 export가 같은 recipe를 공유합니다.

x64 Debug native CTest 30/30, Catalog 338 assertions, Shell 276 assertions, interop ABI 0.13
64 assertions을 통과했습니다. rendered WinUI/UIA, compact/high contrast, 실제 ARM64 runtime,
macOS golden pixel 비교는 미검증입니다. 상세는 `implementation/color-grading-v7.md`에 기록합니다.

x64 Release CI gate는 native CTest 30/30, Catalog 338 assertions, Shell 276 assertions과 managed
build 경고·오류 0을 통과했습니다. native/managed ARM64 교차 빌드도 경고·오류 없이 완료했지만
실제 ARM64 실행은 하지 않았습니다. provenance gate는 files=1787, text=1744, binary=43,
declared_resources=29, reachable_commits=140을 확인했습니다.

## 2026-08-09 InspectorSlider focus/reset follow-up

Exposure와 모든 `InspectorSlider` composite는 이제 Tab 순서에서 value button을 제외하고 slider 하나만
논리 focus 대상으로 둡니다. slider가 focus된 상태에서 Enter로 숫자 편집을 시작하며 기존 click/edit,
Enter/focus-loss commit, Escape cancel, invalid draft의 red/beep/focus 복귀는 유지합니다. slider 주위
8 DIP hit outset에서 double-click reset을 받고, Narrator HelpText에 reset과 edit keyboard 동작을
명시합니다. Basic Tone 그룹은 `TabFocusNavigation=Cycle`로 Exposure→Contrast→Highlights→Shadows→
Whites→Blacks→Density 순서의 Tab/Shift+Tab 순환을 유지합니다. x64 Debug managed build 경고·오류 0,
Catalog 338 및 Shell 276 assertions을 통과했습니다.
rendered/UIA, compact/high contrast, 실제 ARM64 runtime 증거는 여전히 없습니다.

`params.colorMixer`의 Hue/Saturation/Luminance 8밴드 recipe를 Catalog read/write, Shell request
factory, ABI 0.12 `nf_develop_export_request_v6`/`nf_develop_preview_v6`, native CPU pipeline,
WinUI `ColorMixerEditor`까지 연결했습니다. v6는 v5 prefix 뒤에 3×8 float를 append하므로 이전 ABI
entry point와 layout은 유지합니다. Inspector에는 macOS와 같은 HSL/All 선택과 Red~Magenta 8개 밴드,
-1…1 slider, reset 및 keyboard nudge를 제공합니다. preview와 export는 같은 recipe를 공유합니다.

x64 Debug native CTest 30/30, Catalog 336 assertions, Shell 275 assertions, interop ABI 0.12 61
assertions을 통과했습니다. v6 ABI test는 malformed mixer를 fail-closed로 거부하고 실제 fixture의
Color Mixer 조정이 preview pixel을 바꾸는 것을 확인합니다. rendered WinUI/UIA, compact/high contrast,
실제 ARM64 runtime, macOS golden pixel 비교는 미검증입니다. 상세는
`implementation/color-mixer-v6.md`에 기록합니다.

x64 Release CI gate는 native CTest 30/30, Catalog 336 assertions, Shell 275 assertions과 managed
build 경고·오류 0을 통과했습니다. native/managed ARM64 교차 빌드도 경고·오류 없이 완료했지만 실제
ARM64 실행은 하지 않았습니다. provenance gate는 files=1783, text=1740, binary=43,
declared_resources=29, reachable_commits=139을 확인했습니다.

## 2026-08-09 Point Curve recipe v5 vertical slice

`params.pointCurves`의 RGB/Red/Green/Blue recipe를 Catalog read/write, Shell request factory,
ABI 0.11 v5 preview/export, native `WorkingToneAdjustParameters.point_curves`, WinUI
`ToneCurveEditor`까지 연결했습니다. 빈 channel은 identity이며 finite 0...1, 64-point 상한,
정렬 뒤 1e-9 간격을 Catalog·Interop·native에서 fail-closed로 검증합니다. v5는 v4 prefix 뒤에
고정 channel 데이터를 append하므로 v1~v4 ABI layout과 export를 보존합니다.

WinUI editor에는 RGB/Red/Green/Blue 채널, click/drag, non-endpoint double-click delete,
1%/Shift 5% key nudge, input/output percent edit, add/delete/reset과 고정 AutomationId를 넣었습니다.
이는 x64 Debug 빌드만 확인됐습니다. `node_repl` Sky UI automation 세션이 이 환경에서
`node_repl exec context not found`로 시작하지 않아 rendered/UIA runtime, compact/high-contrast,
실 ARM64 runtime은 미검증입니다.

x64 Debug native CTest 30/30, Catalog 331 assertions, Shell 271 assertions, ABI 0.11 interop
58 assertions이 통과했습니다. native ABI test는 활성 curve preview의 pixel 변화와 malformed
channel의 request-validation 거절을 확인합니다.

## 2026-08-09 Develop inspector histogram·전폭 구조 체크포인트

고정 macOS 기준과 사용자 제공 macOS 렌더 캡처를 대조해 오른쪽 Develop inspector를
`Histogram → 6 tabs → tab content → common adjustments` 순서로 바꿨습니다. Histogram은 64-bin
luma/R/G/B와 clipping, 네 tone 영역의 pointer/keyboard 조정을 제공하며 Basic Tone recipe와 같은
preview 경로를 사용합니다. 카드·header·content·slider는 가용 폭 전체를 쓰고, disclosure를 위한
기본 `Expander`/중첩 card를 제거해 macOS section당 하나의 visual surface만 남겼습니다.

x64 Debug 관리형 빌드는 경고 0·오류 0, Catalog 338/Shell 300 assertions를 통과했습니다.
실제 150% DPI WinUI 창에서 Histogram과 네 adjustment card가 모두 603 physical pixel 폭임을 확인했고,
Tone Curve header는 UIA `ExpandCollapsePattern`의 `Collapsed → Expanded` 전환과 단일 section 확장을
확인했습니다. 6개 로캘 리소스와 저장소 UI 작업 규칙도 갱신했습니다.

이는 전체 Develop UI 완료가 아닙니다. Edit/Defects/Info/Reset 고유 content, 나머지 adjustment
sections, compact/high contrast와 실제 ARM64 runtime은 미검증입니다. 추가 UI 확장은 보류하고
`progress/next-steps.md` 순서의 catalog backup 세대·commit verifier를 다음 backend 작업으로 둡니다.
