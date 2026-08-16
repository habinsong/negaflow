# God Object 해소 추적

기준일: 2026-08-17

## 완료 판정

- 줄 수만 줄이는 partial 분할, include 분할, 같은 정적 상태를 공유하는 파일 이동은 해소로 보지 않는다.
- 한 타입 또는 번역 단위가 서로 독립적인 UI 상태, 도메인 상태, 오케스트레이션, I/O, 진단, 테스트 suite를 함께 소유하면 분리 대상이다.
- 분리된 타입은 한 가지 변경 이유와 명시적인 입력·출력을 가져야 한다.
- 기존 동작 보존은 관련 단위 테스트와 빌드로 확인한다. 검증하지 않은 대상은 완료로 표시하지 않는다.

## 목표 단계

1. 현대 Windows 프로젝트의 500줄 이상 소스·테스트·XAML을 전수 재집계하고 실제 다책임 God Object와 생성 데이터·ABI/DTO·단일 알고리즘·fixture를 근거로 분류한다.
2. 분류된 모든 God Object의 상태·오케스트레이션·I/O·UI 이벤트 책임을 세부 폴더의 실제 협력 타입으로 이동한다. partial/include/파일 이동만으로 완료 처리하지 않는다.
3. 구조 체크포인트를 푸시할 때마다 GitHub Actions의 실패 check와 원본 로그를 확인하고 관측된 원인만 수정한다. 외부 check와 로그가 없는 실패는 별도로 표시한다.
4. 구조 선행 조건이 끝난 뒤 GrainMend 자동·가이드·브러시·복제·IR·민감도·확정·영속성·preview/export 동일 recipe를 macOS 계약과 고정 입력·로그로 구현·검증한다.
5. GrainMend와 현상 경로를 고정 입력으로 계측해 자동 약 5초, 직접 조작 경로 1초 미만의 macOS 기준을 품질 저하 없이 검증·최적화한다.
6. macOS 코드·스크린샷·metrics를 묶어서 대조하고 위치·크기·높이·너비·모서리·정렬·전체 클릭 영역·다국어 확장을 창작 없이 구현한다.
7. setup 설치본을 만들고 computer-use로 Library→Develop→Print→Export 단일 워크플로와 GrainMend 전 도구를 실제 조작한다. 8100·V700 및 지정 fixture는 연결·장치 가용성과 실행 증거를 구분한다.
8. 최종 `main`의 모든 필수 GitHub Actions를 재확인하고 잔여 실패를 로그 기준으로 수정해 필수 CI 통과 상태를 검증한다.
9. 의미 있는 체크포인트마다 이 문서, STATUS, 검증 기록, next-steps, 명시 요청된 메모리를 갱신하고 `main`에 커밋·푸시한다. 미검증 항목은 완료로 주장하지 않는다.

## 500줄 이상 전수 재집계: 실제 분해 대상

2026-08-17 현재 `src/`와 `tests/`의 `.cs`, `.cpp`, `.h`, `.xaml`을 재집계했다. 아래 대상은 서로 독립적인 변경 이유가 실제로 확인된 God Object 또는 God UI/test surface다.

| 우선순위 | 대상 | 줄 | 확인된 독립 책임 | 분해 방향 | 상태 |
|---|---|---:|---|---|---|
| P0 | `src/Native/abi/negaflow_abi.cpp` | 6,264 | export/preview 버전 매핑, auto adjust, GrainMend, IR, flatbed, TIFF probe, soft proof, handle 수명 | ABI 함수군별 adapter와 request mapper; 공개 C ABI만 얇게 유지 | 대기 |
| P0 | `src/Shell/Views/DevelopWorkspaceView.xaml.cs` | 5,167 | 선택·가져오기·미리보기·crop·GrainMend·metadata·version·export·sidebar·resize·localization 이벤트/상태 | `Shell.Core` session/coordinator와 실제 UserControl 경계로 이동 | 진행 중 |
| P0 | `tests/Native.UnitTests/develop_export_abi_tests.cpp` | 4,107 | 서로 독립적인 ABI version/stage/defect/output suite와 fixture | ABI stage군별 suite 번역 단위와 공용 fixture | 대기 |
| P0 | `src/Shell/Views/LibraryWorkspaceView.xaml.cs` | 2,835 | 탐색·선택·rating/flag·collection·folder DnD·scanner session·filter/sort·resize·localization | 탐색/정리, scanner workflow, source sidebar, view presentation 타입 | 대기 |
| P0 | `src/Shell/Views/DevelopWorkspaceView.xaml` | 2,508 | source sidebar, canvas/crop, histogram/tabs, 전체 inspector, GrainMend, metadata/version/export UI | macOS surface 단위 실제 UserControl; 공유 상태를 partial로 숨기지 않음 | 대기 |
| P0 | `src/Interop/NativeDevelopExporter.cs` | 2,342 | ABI layout 검증, recipe validation, 각 payload marshaling, 30여 request version, export/preview/auto/GrainMend 실행 | validation, payload marshaler, version request builder, command adapter | 대기 |
| P0 | `src/Catalog.Core/Library/LibraryFrameReader.cs` | 1,584 | frame identity/source, base/tone/color/effects/transform/metadata/local-adjust recipe 파싱 | frame core reader와 recipe별 codec | 대기 |
| P0 | `src/Native/pipeline/develop_export.cpp` | 1,575 | decode, source observation, develop/tone/look/defect/transform/output stage와 progress/cancel orchestration | stage executor와 pipeline coordinator | 대기 |
| P0 | `src/Shell.Core/Library/LibraryDocument.cs` | 1,468 | document 상태, undo/redo, frame/roll/collection/stack/search 변경, defect sidecar, relink/save | aggregate별 command와 persistence transaction | 대기 |
| P0 | `src/Native/core/tiff_probe.cpp` | 1,425 | Win32 random file I/O, TIFF/BigTIFF parsing, directory selection, segment/deflate 검증, metadata projection | byte reader, directory parser, segment validator, projection | 대기 |
| P0 | `tests/Interop.ContractTests/ContractTestRunner.cs` | 1,414 | layout, run state, auto, IR, flatbed, TIFF, proof, limits, export, path, build contract suite | 계약군별 suite와 공용 assertion | 대기 |
| P0 | `src/Shell.Core/Library/LibraryHostService.cs` | 906 | selection, document lifecycle, edits, collections/rolls/stacks, import/scanner publish, autosave, move/relink, export, defects | selection/session, import/publish, autosave, library commands, export adapter | 대기 |
| P0 | `src/Shell/Views/PrintWorkspaceView.Composition.cs` | 826 | source selection, file tree/filmstrip, inspector, preview drawing/rulers, settings, export | partial 분할 폐기; source controller, preview renderer, settings binder, export workflow | 대기 |
| P0 | `src/Shell.Core/Scanner/ScanSessionController.cs` | 801 | gateway adapter, device/capability state, region clipboard/editing, approval, option clamp, scan orchestration | gateway, device session, region editor, request builder, run coordinator | 대기 |
| P0 | `src/Cli/commands/export_developed_image.cpp` | 726 | CLI 인자 해석, pipeline orchestration, progress/timing, PNG/TIFF 결과 출력 | option parser, run coordinator, report writer | 대기 |
| P0 | `src/Shell.Core/Scanner/ScannerPluginClient.cs` | 706 | wire DTO, JSON parse/validation, process/client calls, path/option/result 검증, publish contract | wire models/codec, transport client, result validator | 대기 |
| P0 | `src/Catalog.Core/Library/LibraryFrameWriter.cs` | 644 | frame core, route/base/tone/color/effects/transform/local-adjust recipe 검증·직렬화 | reader와 대응하는 recipe별 codec | 대기 |
| P1 | `tests/Shell.UnitTests/DevelopRequestFactoryTests.cs` | 638 | source/base/tone/color/output/defect/IR/clone/brush request 계약을 한 메서드가 소유 | 요청 영역별 suite와 공용 frame fixture | 대기 |
| 완료 | `tests/Shell.UnitTests/DevelopPanelTests.cs` | 11개 suite 진입점, 변경 전 550 | panel recipe, version/preset/metadata, slider, export 결과 표현 | `DevelopPanelStateTests`, `InspectorSliderValueTests`, `DevelopOutcomePresenterTests` 실제 타입 분리 | 완료·938 assertions 검증 |
| P1 | `src/Shell/Views/PrintSheetWriter.cs` | 505 | develop 호출, 크기 probe, page 합성, caption/ruler drawing, PNG encode/file I/O | source renderer, page compositor, encoder/writer | 대기 |
| 완료 | `tests/Shell.UnitTests/Program.cs` | 62, 변경 전 약 7,000 | 진입점·진단·fixture/fake·전 도메인 suite | 실행/집계만 남기고 26개 suite와 진단/fixture 타입 분리 | 완료·검증·푸시 |
| 완료 | `tests/Catalog.UnitTests/Program.cs` | 33, 변경 전 3,301 | 전 catalog suite와 fixture | 19개 suite/fixture 타입과 실행/집계 분리 | 완료·검증·푸시 |
| 완료 | `src/Shell.Core/Develop/DevelopPanelState.cs` | 648, 변경 전 1,542 | base/tone/color/effects/route/transform/defect/version/preset/export 상태·검증·I/O | `Develop/{Editing,Defects,Workflow,Presentation}` 협력 타입; 현재 타입은 선택 frame 호환 facade | 완료·clean-index 검증 |

## 500줄 이상 전수 재집계: 검토 후 분해 제외

아래 파일도 모두 열어 타입·메서드 책임을 확인했다. 줄 수만 큰 것이며 현재는 서로 독립적인 상태·오케스트레이션·I/O 변경 이유가 확인되지 않았다. 새 책임이 추가되면 다시 분류한다.

| 대상 | 줄 | 제외 근거 |
|---|---:|---|
| `src/Native/imaging/muted_scene_vibrance_table.cpp` | 9,003 | 생성된 정적 계수 데이터; 실행 상태·오케스트레이션 없음 |
| `src/Native/abi/include/negaflow_abi.h` | 1,791 | 외부 소비자가 포함하는 append-only 공개 ABI 선언 집합; 구현 상태 없음 |
| `src/Native/imaging/infrared_defect_detector.cpp` | 1,197 | IR alignment·mask·component 판정의 단일 검출 알고리즘 |
| `src/Native/imaging/grain_mend_components.cpp` | 1,066 | GrainMend component/evidence/mask 구성의 단일 알고리즘 |
| `src/Native/imaging/defect_heal_brush.cpp` | 985 | brush mask·patch 탐색·합성의 단일 치유 알고리즘 |
| `tests/Native.UnitTests/grain_mend_tests.cpp` | 918 | 동일 GrainMend 알고리즘의 고정 입력 suite |
| `src/Native/imaging/auto_negative_base_resolver.cpp` | 893 | 자동 Dmin 추정의 단일 알고리즘 |
| `src/Catalog.Core/Storage/CatalogBackupStore.cs` | 885 | 하나의 backup generation 생성·검증·prune transaction |
| `src/Interop/NativeDevelopExportV2.cs` | 874 | append-only ABI 구조체/결과 DTO 선언; 동작 상태 없음 |
| `src/Native/imaging/flatbed_frame_grid_detector.cpp` | 862 | flatbed frame grid 검출의 단일 알고리즘 |
| `src/Catalog.Core/Defects/DefectSidecarCodec.cs` | 856 | 하나의 sidecar schema encode/decode 계약 |
| `tests/Native.UnitTests/tiff_probe_tests.cpp` | 824 | TIFF probe 단일 모듈 fixture/suite |
| `src/Native/imaging/film_scan_denoise.cpp` | 802 | film scan denoise 단일 알고리즘 |
| `src/Interop/DevelopExport.cs` | 796 | managed request/result/recipe DTO와 enum 계약; I/O·오케스트레이션 없음 |
| `tests/Native.UnitTests/manual_negative_developer_tests.cpp` | 772 | manual negative developer 단일 알고리즘 suite |
| `src/Native/imageio/wic_tiff_decoder.cpp` | 765 | WIC TIFF decode 단일 I/O boundary |
| `src/Interop/NativeMethods.cs` | 757 | source-generated P/Invoke 선언 집합; 상태·실행 조립 없음 |
| `tests/Native.UnitTests/wic_tiff_decoder_tests.cpp` | 728 | WIC TIFF decoder 단일 suite |
| `src/Native/imaging/scanner_target_grade.cpp` | 713 | scanner target grade 단일 알고리즘 |
| `src/Catalog.Core/Defects/DefectRecipeValidator.cs` | 700 | defect recipe 불변식 검증·복사의 단일 boundary |
| `src/Catalog.Core/Storage/CatalogCommitVerifier.cs` | 681 | 검증된 catalog commit/rollback 단일 transaction |
| `src/Native/imaging/local_dodge_burn.cpp` | 656 | local dodge/burn 단일 알고리즘 |
| `src/Native/imaging/texture_stage.cpp` | 646 | texture stage 단일 알고리즘 |
| `tests/Native.UnitTests/texture_stage_tests.cpp` | 620 | texture stage 단일 suite |
| `src/Native/imaging/digital_film_color_preset.cpp` | 597 | digital film color preset 단일 알고리즘 |
| `src/Native/imaging/grain_mend_detector.cpp` | 595 | GrainMend 후보 검출 단일 알고리즘 |
| `src/Shell.Core/Print/PrintPackageLayout.cs` | 592 | print package 기하 배치 단일 순수 layout boundary |
| `src/Native/output/wic_jpeg_export.cpp` | 577 | JPEG encode 단일 output boundary |
| `src/Native/output/wic_tiff_export.cpp` | 570 | TIFF encode 단일 output boundary |
| `src/Native/imaging/defect_component_structure.cpp` | 568 | defect component 구조 판정 단일 알고리즘 |
| `src/Catalog.Core/Defects/DefectSidecarStore.cs` | 551 | sidecar 원자적 read/write/remove/health 단일 persistence boundary |
| `src/Catalog.Core/Storage/SqliteCatalogStore.cs` | 541 | SQLite catalog read/write 동기화 단일 store boundary |
| `tests/Native.ConformanceTests/scalar_conformance.cpp` | 526 | scalar/native conformance 단일 suite |
| `src/Native/imaging/defect_clone_stamp.cpp` | 522 | clone stamp 단일 알고리즘 |
| `src/Native/core/tiff_deflate_validator.cpp` | 515 | TIFF Deflate payload 검증 단일 알고리즘 |
| `tests/fixtures/tiff/synthetic_wic_tiff.cpp` | 500 | 테스트 fixture 생성기; 제품 상태·오케스트레이션 없음 |

## 현재 체크포인트

- `DevelopWorkspaceView`에 새 복제 도장 상태를 더 넣던 변경을 중단했다.
- 복제 도장 입력 상태는 별도 `GrainMendStrokeSession`으로 이동 중이다. 이 작업은 GrainMend 기능 확장이 아니라 기존 God Object에서 상태 책임을 제거하는 구조 작업이다.
- `Shell.UnitTests/Program.cs`에서 수동 진단 라우팅, 공용 test assertion/frame factory/fake, 26개 도메인 suite를 실제 별도 타입으로 이동했다. `Program`은 진단 위임, suite 실행, 결과 집계만 남는다.
- 진단도 `CatalogSeedDiagnostics`, `CatalogInspectionDiagnostics`, `DevelopPipelineDiagnostics`로 분리해 테스트 suite와 I/O 진단 책임을 섞지 않는다.
- Shell 단위 테스트는 구조 변경 전후 Release 918 assertions가 모두 통과했다.
- `DevelopPanelState`가 소유하던 GrainMend 좌표 역변환, 브러시·복제 획 조립, 검토 결과 수락, 종류/라벨별 제거, sidecar/catalog 쓰기를 `DevelopDefectEditor`로 이동했다. 공개 facade는 선택 frame 전달과 실제 변경 뒤 재선택만 담당한다.
- `DevelopDefectEditResult.Changed`로 성공한 실제 쓰기와 변경 없는 제거를 구분해, 기존의 no-op 제거가 불필요한 재선택을 하지 않던 동작도 보존했다.
- `DevelopPanelTests`는 550줄 단일 타입에서 11줄 suite 진입점으로 축소했다. panel/catalog 왕복, slider 값 계약, export 결과 표현을 `tests/Shell.UnitTests/Develop/` 아래의 독립 타입으로 옮겼고 각 구현 파일은 500줄 미만이다.
- 변경된 working tree에서 Shell 단위 테스트 938 assertions가 통과했다. 이 수치는 사용자의 진행 중 GrainMend 테스트 변경도 함께 포함하므로, 체크포인트 커밋 전에는 clean index 검증을 별도로 남긴다.
- 스테이징한 파일만 내보낸 깨끗한 인덱스에서 `test-managed.ps1 -Preset x64-release`를 실행해 빌드 경고 0개·오류 0개, Catalog 721 assertions, Shell 921 assertions가 통과했다. 추가된 서로 다른 검증 경로는 `DevelopPanelState`를 통한 표시→raw 좌표 변환, 검토 region 수락, 라벨별 선택 제거다.
- `Catalog.UnitTests/Program.cs`는 lock contender 분기, suite 순서, 결과 집계만 남겼다. 현상 경로 계약, 현상 recipe/프리셋, 저장 경로, 프로세스 lock, SQLite 수명주기, defect sidecar, defect 복구, backup/pending restore, catalog session, Library frame 투영·검증·쓰기·정리·앱 메타데이터를 각각 독립 suite 타입으로 이동했다.
- 공용 상태는 `CatalogTestAssert`, frame fixture는 `LibraryFrameFixture`, defect fixture는 `DefectTestFixture`, 저장 fixture는 `CatalogStorageFixtures`로 분리했다. 분리 뒤 가장 큰 suite는 `CatalogBackupRestoreTests` 448줄이며, 서로 다른 저장·복구 책임을 다시 한 타입에 합치지 않았다.
- 스테이징한 Catalog suite 분해만 내보낸 깨끗한 인덱스에서 `test-managed.ps1 -Preset x64-release`를 실행해 빌드 경고 0개·오류 0개, Catalog 721 assertions, Shell 921 assertions가 통과했다. 작업트리의 별도 GrainMend 테스트 변경은 이 수치에서 제외했다.
- `DevelopPanelState`에서 base, tone/auto adjust, color/BW toning/calibration, effects/noise, route/film look/auto correction, transform/crop, version/settings/preset/metadata, export save/run/표현 책임을 실제 협력 타입으로 이동했다. 파일은 `Develop/Editing`, `Develop/Defects`, `Develop/Workflow`, `Develop/Presentation`으로 나눴고 namespace만 같을 뿐 상태와 I/O 소유자는 각각 다르다.
- `DevelopPanelState`는 선택 frame, 호환 facade, 실제 변경 뒤 재선택만 남아 1,542줄에서 648줄이 됐다. 별도 controller가 `Changed=false`를 반환하는 paste no-op은 재선택하지 않는다.
- version/preset controller 경계를 공개 panel 경유로 확인하도록 metadata 정규화·revision, 설정 copy/paste scope, user preset 저장·적용·삭제 8개 assertion을 추가했다. 작업트리 gate는 Catalog 721, Shell 938 assertions를 통과했다.
- 이 체크포인트만 내보낸 깨끗한 인덱스에서 `test-managed.ps1 -Preset x64-release`를 실행해 빌드 경고 0개·오류 0개, Catalog 721 assertions, Shell 929 assertions가 통과했다. 작업트리의 별도 GrainMend 테스트 9개는 제외된 수치다.
- 같은 gate의 직전 1회 실행에서는 Catalog pending-restore 4개 assertion이 실패했으나 동일 바이너리 단독 재실행과 전체 gate 재실행은 각각 721개 전부 통과했다. 소스 변경과 직접 연결된 재현은 없었지만 최초 실패 사실은 숨기지 않으며 clean-index gate를 별도로 실행한다.
- 일반 `dotnet build`의 AnyCPU 패키징은 `RuntimeIdentifier`가 없어 실패했다. 저장소의 x64 preset/setup 경로로 최종 빌드해야 하며 이 실패를 기능 실패나 통과로 바꾸어 말하지 않는다.
