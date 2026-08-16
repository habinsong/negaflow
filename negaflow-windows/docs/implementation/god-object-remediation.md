# God Object 해소 추적

기준일: 2026-08-17

## 완료 판정

- 줄 수만 줄이는 partial 분할, include 분할, 같은 정적 상태를 공유하는 파일 이동은 해소로 보지 않는다.
- 한 타입 또는 번역 단위가 서로 독립적인 UI 상태, 도메인 상태, 오케스트레이션, I/O, 진단, 테스트 suite를 함께 소유하면 분리 대상이다.
- 분리된 타입은 한 가지 변경 이유와 명시적인 입력·출력을 가져야 한다.
- 기존 동작 보존은 관련 단위 테스트와 빌드로 확인한다. 검증하지 않은 대상은 완료로 표시하지 않는다.

## 전수 조사 결과와 순서

| 우선순위 | 대상 | 현재 크기 | 섞인 책임 | 분해 방향 | 상태 |
|---|---|---:|---|---|---|
| P0 | `tests/Shell.UnitTests/Program.cs` | 50줄대 진입점, 변경 전 약 7,000줄 | 테스트 진입점, 수동 진단 CLI, fixture, fake, Shell·Develop·Library·Print·Scanner suite | 진입점은 suite 집계만 유지하고 도메인별 실제 suite 타입, 공용 test infrastructure, 별도 진단 타입으로 이동 | 1차 완료·검증 |
| P0 | `src/Shell/Views/DevelopWorkspaceView.xaml.cs` | 약 5,300줄 | 선택·가져오기·내보내기·미리보기·크롭·GrainMend·검사기·사이드바·설정·포인터 상태 | 도메인 세션과 오케스트레이터를 `Shell.Core` 협력 타입으로 이동하고 뷰는 이벤트 번역·렌더 동기화만 유지 | 진행 중 |
| P0 | `src/Shell/Views/LibraryWorkspaceView.xaml.cs` | 약 2,800줄 | Library 탐색·가져오기·스캐너·선택·메타데이터·미리보기·레이아웃 | 탐색/선택, 가져오기/스캐너, 메타데이터, 표시 상태 책임 분리 | 대기 |
| P0 | `tests/Catalog.UnitTests/Program.cs` | 33줄, 변경 전 3,301줄 | 카탈로그 전체 suite와 fixture를 한 타입이 소유 | 저장소·복구·sidecar·reader/writer suite와 공용 fixture 분리 | 완료·검증 |
| P0 | `src/Interop/NativeDevelopExporter.cs` | 약 2,300줄 | ABI marshaling, 요청 검증, preview/export, 자동보정, GrainMend/IR 검출 | 호출별 marshaler와 명령별 adapter로 분리하되 public ABI facade는 얇게 유지 | 대기 |
| P0 | `src/Native/abi/negaflow_abi.cpp` | 약 6,300줄 | 여러 독립 ABI 명령의 검증·변환·호출 | ABI 함수군별 내부 adapter 번역 단위로 분리하고 공개 C ABI는 얇은 진입점으로 유지 | 대기 |
| P1 | `src/Shell.Core/Develop/DevelopPanelState.cs` | 1,328줄, 변경 전 1,542줄 | 현상 recipe 전 영역과 버전·내보내기·결함 편집 | recipe 영역별 command/service로 분리하고 선택 frame facade는 얇게 유지 | 진행 중: 결함 편집 분리 |
| P1 | `src/Shell.Core/Library/LibraryDocument.cs` | 약 1,500줄 | 문서 상태, 저장, undo, sidecar, defect, collection 변경 | 저장 트랜잭션·undo·defect persistence 책임 분리 | 대기 |
| P1 | `tests/Native.UnitTests/develop_export_abi_tests.cpp` | 약 4,100줄 | 독립 ABI stage suite와 fixture | stage군별 실행 파일 또는 suite 번역 단위로 분리 | 대기 |

`src/Native/imaging/muted_scene_vibrance_table.cpp`의 약 9,000줄은 생성된 정적 계수 데이터이며 상태·오케스트레이션 책임을 소유하지 않는다. 파일 크기만으로 God Object로 분류하지 않되 생성 경로와 무결성 검증은 유지한다.

## 현재 체크포인트

- `DevelopWorkspaceView`에 새 복제 도장 상태를 더 넣던 변경을 중단했다.
- 복제 도장 입력 상태는 별도 `GrainMendStrokeSession`으로 이동 중이다. 이 작업은 GrainMend 기능 확장이 아니라 기존 God Object에서 상태 책임을 제거하는 구조 작업이다.
- `Shell.UnitTests/Program.cs`에서 수동 진단 라우팅, 공용 test assertion/frame factory/fake, 26개 도메인 suite를 실제 별도 타입으로 이동했다. `Program`은 진단 위임, suite 실행, 결과 집계만 남는다.
- 진단도 `CatalogSeedDiagnostics`, `CatalogInspectionDiagnostics`, `DevelopPipelineDiagnostics`로 분리해 테스트 suite와 I/O 진단 책임을 섞지 않는다.
- Shell 단위 테스트는 구조 변경 전후 Release 918 assertions가 모두 통과했다.
- `DevelopPanelState`가 소유하던 GrainMend 좌표 역변환, 브러시·복제 획 조립, 검토 결과 수락, 종류/라벨별 제거, sidecar/catalog 쓰기를 `DevelopDefectEditor`로 이동했다. 공개 facade는 선택 frame 전달과 실제 변경 뒤 재선택만 담당한다.
- `DevelopDefectEditResult.Changed`로 성공한 실제 쓰기와 변경 없는 제거를 구분해, 기존의 no-op 제거가 불필요한 재선택을 하지 않던 동작도 보존했다.
- 스테이징한 파일만 내보낸 깨끗한 인덱스에서 `test-managed.ps1 -Preset x64-release`를 실행해 빌드 경고 0개·오류 0개, Catalog 721 assertions, Shell 921 assertions가 통과했다. 추가된 서로 다른 검증 경로는 `DevelopPanelState`를 통한 표시→raw 좌표 변환, 검토 region 수락, 라벨별 선택 제거다.
- `Catalog.UnitTests/Program.cs`는 lock contender 분기, suite 순서, 결과 집계만 남겼다. 현상 경로 계약, 현상 recipe/프리셋, 저장 경로, 프로세스 lock, SQLite 수명주기, defect sidecar, defect 복구, backup/pending restore, catalog session, Library frame 투영·검증·쓰기·정리·앱 메타데이터를 각각 독립 suite 타입으로 이동했다.
- 공용 상태는 `CatalogTestAssert`, frame fixture는 `LibraryFrameFixture`, defect fixture는 `DefectTestFixture`, 저장 fixture는 `CatalogStorageFixtures`로 분리했다. 분리 뒤 가장 큰 suite는 `CatalogBackupRestoreTests` 448줄이며, 서로 다른 저장·복구 책임을 다시 한 타입에 합치지 않았다.
- 스테이징한 Catalog suite 분해만 내보낸 깨끗한 인덱스에서 `test-managed.ps1 -Preset x64-release`를 실행해 빌드 경고 0개·오류 0개, Catalog 721 assertions, Shell 921 assertions가 통과했다. 작업트리의 별도 GrainMend 테스트 변경은 이 수치에서 제외했다.
- 일반 `dotnet build`의 AnyCPU 패키징은 `RuntimeIdentifier`가 없어 실패했다. 저장소의 x64 preset/setup 경로로 최종 빌드해야 하며 이 실패를 기능 실패나 통과로 바꾸어 말하지 않는다.
