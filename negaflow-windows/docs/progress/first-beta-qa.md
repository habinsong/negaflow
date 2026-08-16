# Windows 최초 QA·프리뷰 데모·베타 추적

기준일: 2026-08-16

이 문서는 최초 QA·프리뷰 데모·베타 테스트의 단일 추적 문서다. 아래 사용자 목표의 기능·품질·성능·검증 범위는 축약하거나 재해석하지 않는다. 각 목표는 실제 Windows 앱, 지정 입력, 실제 장치, macOS 기준 화면·코드로 검증되기 전까지 완료로 표시하지 않는다.

## 현재 최우선 구조 작업

- GrainMend 기능 확장보다 먼저 저장소 전체의 God Object를 해소한다.
- 최소 필수 대상은 `DevelopWorkspaceView.xaml.cs`와 `tests/Shell.UnitTests/Program.cs`이며, 파일 크기뿐 아니라 한 타입이 UI 상태·도메인 상태·오케스트레이션·I/O 또는 서로 독립적인 테스트 suite를 함께 소유하는 모든 지점을 전수 조사한다.
- partial 분할이나 메서드의 기계적 이동은 완료로 보지 않는다. 서로 다른 변경 이유를 실제 응집된 타입·모듈·테스트 프로젝트 경계로 분리하고 기존 동작 보존을 빌드와 관련 테스트로 검증한다.
- 이 구조 체크포인트가 닫히기 전에는 GrainMend를 비롯한 새 기능을 기존 God Object에 추가하지 않는다.

## 사용자 목표

1. GrainMend 기능이 동작하지 않고 "고칠 것을 찾지 못했습니다"만 표시된다. 자동·가이드·브러시·복제 도구·IR을 모두 macOS와 동일하게 동작하게 한다. 복제 도구가 잘려 보이는 문제도 수정한다.
2. 창작한 UI/UX를 제거하고 각종 뷰의 크기·모양·모서리 라운딩·위치·정렬을 macOS와 동일하게 한다. 누락된 현상 버튼, 아예 만들지 않은 UI/UX, 백엔드에 연결되지 않은 UI를 모두 구현·연결한다. `C:\Users\habin\negaflow\negaflow_mac_screenshot`의 기준 화면을 그대로 대조한다.
3. Library에서 사진을 불러온 뒤 Develop에서 이미지와 썸네일이 보여야 하며 하단 탭 전체가 동작해야 한다. Library와 Develop을 분리된 데이터 흐름으로 두지 않는다.
4. 창작한 Develop 좌측 탭을 제거하고 macOS Develop 좌측 탭의 모든 기능과 여러 사진을 다루는 흐름을 동일하게 구현한다. Library 좌측 탭에만 있는 기능으로 축소하지 않는다.
5. 창작한 UI/UX 때문에 글자가 잘리거나 가려지는 문제를 모든 화면·상태·지원 언어에서 수정한다.
6. Develop 우측 탭의 모든 슬라이더가 실시간으로 반응하게 한다. 수초 지연을 허용하지 않으며 슬라이더 하나가 아니라 모든 실시간 편집 경로를 포함한다.
7. 자동 톤·자동 색상·자동 레벨이 모두 동작하고 실시간 사용에 적합한 속도를 내게 한다.
8. 이미지 crop·rotate·flip을 포함한 모든 이미지 편집 기능의 속도와 반응성을 개선한다.
9. Print에서 선택한 이미지가 표시되게 하고 UI/UX와 전체 기능을 macOS와 동일하게 구현한다.
10. macOS 스크린샷과 동일한 UI/UX 위치·크기·모양 및 기능을 모두 구현한다. `computer-use`로 연결된 8100과 V700 스캐너를 사용해 스캔·보정·인화·내보내기 전체 흐름을 검증한다. `C:\Users\habin\OneDrive\바탕 화면\negaflow_test`로 일반 이미지 경로를 테스트하고 `C:\Users\habin\Downloads\golden\golden`으로 IR을 테스트한다. `C:\Users\habin\negaflow\negaflow-windows`와 `C:\Users\habin\negaflow-scanner-sane` 양쪽을 모두 수정·검증한다. 스크린샷 기준은 `C:\Users\habin\negaflow\negaflow_mac_screenshot`, macOS 코드 기준은 `C:\Users\habin\negaflow\negaflow-mac`과 `C:\Users\habin\negaflow-scanner-sane\negaflow-mac`이다. 검증되지 않은 상태에서 "다했습니다" 또는 "완성했습니다"라고 주장하지 않는다.

## 추가 운영 요구

- `computer-use`를 사용한다. 각 프로젝트마다 Markdown 문서를 만들고 한 것·안 한 것·수정할 것·수정한 것·검증한 것을 모두 기록하고 계속 최신화하며, 작업을 재개할 때 먼저 읽는다. 컨텍스트 압축 뒤에도 잊지 않도록 메모리 업데이트 노트를 남긴다. 이 작업은 최초 QA이자 프리뷰 데모 베타 테스트다.
- 체크포인트 마다 커밋/푸시 하고, 그거랑 별개로 문서는 계속 작성하고 최신화해라
- 1번부터 끝까지 목표 사항 축약없이, 생략없이 목표 단위로 기록해놔라. 말 토씨하나 빼지 말고
- UI/UX를 창작하지 않는다. 아예 존재하지 않거나 동작하지 않는 요소를 모두 찾아 구현·연결하고, 각종 뷰의 크기·모양·모서리 라운딩·위치·높이·너비가 macOS와 완전히 동일하게 한다.
- 이미지 현상·보정·인화·내보내기의 품질·속도·성능을 모두 최적화한다. 특히 속도를 우선하며 슬라이더는 한 가지 예일 뿐이고 전체 이미지 처리 경로를 포함한다.
- 속도·품질·성능 최적화는 로그를 남겨 추측이나 확인되지 않은 가설 없이 검증하면서 해결한다.
- GrainMend 성능 기준은 macOS와 같이 자동 검출 약 5초 이내, 가이드·브러시·복제·IR은 입력 후 즉각적인 반응(1초 미만)이다. 검출 품질·오탐 방지·원본 불변·preview/export 동일 recipe를 낮춰 속도를 맞추지 않는다.
- UI/UX는 `computer-use`를 사용해 Windows 실제 화면을 캡처하고 macOS 스크린샷과 비교하며, 양쪽 코드와 고정 metric도 함께 비교한다.
- 다국어 텍스트 길이 확장을 고려해 UI/UX를 구현한다. 지원 언어별 문자열이 길어져도 뒤쪽 글자가 잘리거나 가려지지 않게 하고, macOS 계약을 벗어나지 않는 범위에서 줄바꿈·가변 너비·최소 높이와 접근성 이름이 자연스럽게 동작하도록 한다. 여섯 언어(`de`, `en`, `fr`, `ja`, `ko`, `zh-Hans`)의 실제 렌더링을 각각 검증한다.
- Library·Develop·Print는 분리된 기능이 아니라 하나의 연속된 워크플로다. 현재 끊긴 이미지·썸네일·선택·filmstrip·Print 대상 전달을 모두 수정한다.
- Negaflow 본체와 `negaflow-scanner-sane` 모두 저장소에 이미 있는 setup/build-installer 경로로 최신 소스를 빌드·설치한 뒤 `computer-use` 검증을 수행한다. 설치된 오래된 실행 파일이나 임의 실행 경로를 기준으로 삼지 않는다.
- 체크포인트 커밋·푸시는 별도 작업 브랜치를 만들지 않고 각 저장소의 `main`에 직접 수행한다. 저장소에는 `main`만 유지한다.
- macOS `negaflow-mac/scripts/ci-gate.sh`처럼 각 Windows 프로젝트에 단일 로컬 CI 진입점을 둔다. 이후 수동으로 빌드 단계를 반복하지 않고 본체는 `scripts/local-ci.ps1`의 core gate→setup build→설치→package identity→실제 창 생성→제거를, SANE은 Release build→CTest→setup build→설치 payload→`detect`→제거를 각각 한 번에 통과한 산출물만 QA에 사용한다. 각 실행 로그 경로를 문서 증거에 남긴다.

## 상태 표

상태 값은 `미재현`, `재현`, `수정 중`, `수정`, `부분 검증`, `검증 완료`만 사용한다. `검증 완료`는 해당 목표의 전체 실제 경로와 macOS 동등성 증거가 있을 때만 쓴다.

| 목표 | 상태 | 현재 확인 사실 | 수정할 것 | 수정한 것 | 검증한 것 |
| --- | --- | --- | --- | --- | --- |
| 1 | 부분 검증 | 설치본 Auto가 네이티브 0/1 마스크를 review 단계에서 임계값 8로 다시 걸러 `고칠 것을 찾지 못했습니다`를 표시한 원인을 실제 frame 진단과 앱 계측으로 확정했다. Auto는 macOS 기준 약 5초 이내, Guided·Brush·Clone·IR은 1초 미만 반응이 필요하다. IR은 현재 Shell 진입점이 없다. | Guided·Brush·Clone·IR을 실제 설치본과 지정 입력에서 macOS 품질·시간 기준으로 수정·검증하고, Auto 편집 재시작 영속성을 추가 확인 | review 마스크는 0이 아닌 모든 native 후보를 유지하도록 수정했다. Release CI 네이티브 DLL 복사를 구성별로 수정하고 실제 frame 진단 매트릭스·선택 review 진단·JSONL 계측을 추가했다. GrainMend 네 도구는 macOS 캡슐 높이·라운딩·간격·축소 규칙으로 다시 배치했다. | `OpticFilm8100_frame_1.tiff` 설치본 Auto에서 4,096 후보 overlay와 제거/취소 review를 3,761ms에 표시했고 `제거`로 편집을 확정했다. 원본 SHA-256 `F281DEECF07FE8E6B4019EB2BE0D87985F2F1D7A861119388279796DDB5A872B`와 수정 시각은 바뀌지 않았다. Auto 외 경로는 미검증이다. |
| 2 | 수정 중 | Print 불일치에 더해 Develop 좌측 탭 전체와 히스토그램 아래 검사기 탭의 폭·정렬·히트 영역이 macOS와 다름을 확인했다. 전체 화면별 치수·라운딩·위치 대조는 아직 남았다. | 스크린샷·SwiftUI·고정 UI metric을 화면별로 계속 대조하고 설치본에서 동일 창 크기·DPI로 다시 캡처 | Print 왼쪽 파일 영역·활성 프레임 헤더를 연결했다. Develop 검사기 탭은 macOS `HStack(spacing: 0)`과 `frame(maxWidth: .infinity, minHeight: 32)` 계약대로 여섯 등분, 각 구간 전체 Stretch 히트 영역, 아이콘 중앙 정렬, 15px 구분선, 외곽 3px·18px 라운딩으로 고정했다. | `computer-use`로 Print 수정 전후와 Develop 좌측 Library/Files 상태, GrainMend 캡슐을 캡처했다. 검사기 탭 최신 Stretch 수정은 Release 빌드만 통과했고 설치본 렌더·히트 영역은 아직 재검증 전이다. 전체 UI parity는 미검증이다. |
| 3 | 부분 검증 | `negaflow_test`의 `OpticFilm8100_frame_1.tiff`를 Library에서 고르면 같은 frame id가 Develop 중앙 이미지·왼쪽 선택기·하단 filmstrip에 전달된다. | 다중 선택·오프라인·삭제·재연결·키보드 경로와 macOS 상호작용 대조 | `ActiveFrameId`를 LibraryHost와 presentation에 연결하고, Library 선택 복원 및 Filmstrip 재진입 덮어쓰기를 수정했다. | `activeFrameId=7bcc36cb-cda8-46bd-9d2e-b5896e45ceac`, Develop 중앙 8100 이미지와 선택 filmstrip 카드, 재시작 뒤 같은 id 유지 확인. |
| 4 | 부분 검증 | 설치본에서 Windows가 창작한 단일 이미지 가져오기/Frame ComboBox 구조와 macOS에 없는 좌측 탭 내용을 확인했다. | Library 탭의 인라인 scanner controls·Develop defaults와 Versions·Presets·Film·Output의 실제 기능·상태·키보드 흐름을 macOS와 동일하게 연결 | macOS `WorkflowSidebar.swift`의 Library·Files·Versions·Presets·Film·Output 6탭과 76/48 rail, 32px 버튼, 7px 간격, header padding을 적용했다. 단일 Frame ComboBox를 렌더에서 제거하고 `LibrarySourceSection.swift` 기준 이미지·폴더·스캐너 3분할 가져오기 캡슐과 현재 폴더 트리를 공유 catalog/active frame에 연결했다. Files 탭은 같은 catalog 전체 폴더 트리를 사용하며 선택 탭을 presentation에 저장한다. | 설치본 2560×1392에서 Library의 3분할 캡슐과 `negaflow_test` 15장, Files의 `negaflow_test` 15장·`Temp` 1장·`scratchpad` 1장을 확인했다. 앱 재시작 뒤 Files 탭 선택 유지도 확인했다. 나머지 기능은 미검증이다. |
| 5 | 부분 검증 | 설치본에서 기존 복제 도구 문자열 클리핑을 재현했다. | 여섯 로케일·DPI·창 크기별 실제 렌더 대조 | GrainMend 네 캡슐과 Develop 가져오기 3분할의 사용자 문자열을 macOS와 같은 축소 가능 단일 행으로 배치해 구간을 넘지 않게 했다. | 한국어 2560×1392 설치본에서 `복제 도장`과 이미지·폴더·스캐너 캡슐이 잘리지 않음을 확인했다. `de`, `en`, `fr`, `ja`, `zh-Hans`와 다른 DPI는 미검증이다. |
| 6 | 미재현 | 사용자 보고: Develop 우측 슬라이더 반영이 수초 지연 | 입력→recipe→preview scheduling→native render→present 지연 계측 및 실시간 갱신 | 없음 | 없음 |
| 7 | 미재현 | 사용자 보고: 자동 톤·자동 색상·자동 레벨이 실패하거나 매우 느림 | 세 기능을 독립 재현하고 macOS 결과·지연과 대조 | 없음 | 없음 |
| 8 | 미재현 | 사용자 보고: crop·rotate·flip 등 기하 편집이 매우 느림 | gesture→transform preview 경로와 불필요한 전체 렌더·I/O 점검 | 없음 | 없음 |
| 9 | 부분 검증 | Library에서 고른 8100 frame이 Print 미리보기와 하단 filmstrip에 전달되며 재시작 뒤에도 유지된다. 수정 전에는 첫 테스트 fixture로 되돌아가고 왼쪽이 항상 "사진 없음"이었다. | Print의 나머지 Layout·Content·Output 기능과 치수·라운딩·간격·상태를 macOS 기준으로 대조 | Print filmstrip을 공유 선택에 연결하고, 왼쪽 파일 트리·활성 프레임 헤더·트리 클릭 선택을 macOS `PrintWorkspaceSidebar.swift` 기준으로 연결했다. | `computer-use`에서 트리의 `OpticFilm8100_frame_1.tiff` 클릭→상단/좌측/우측 헤더→미리보기→filmstrip 동일 프레임, 앱 재시작 뒤 동일 상태를 확인했다. 전체 Print parity는 미검증이다. |
| 10 | 미재현 | 전체 macOS UI/UX·기능, 8100/V700 스캔, 보정, 인화, 내보내기, 지정 입력·IR 검증 요구 | 1~9를 닫은 뒤 실제 장치·입력으로 전 구간 검증 | 없음 | 없음 |

UI 완료 판정에는 각 화면·상태별로 다음 증거가 모두 필요하다: macOS에 해당 요소가 존재하는지, 같은 동작인지, 같은 위치인지, 같은 높이·너비인지, 같은 모양인지, 같은 모서리 반경인지, 문자열이 잘리거나 가리지 않는지, 백엔드가 실제로 연결됐는지, 같은 입력 상태에서 렌더한 Windows 캡처가 기준과 일치하는지. 하나라도 없으면 완료가 아니다.

성능 완료 판정은 슬라이더에 한정하지 않는다. 이미지 표시, 현상, 자동 톤·색상·레벨, GrainMend, crop·rotate·flip, Print preview, 인화 산출, 내보내기 각각에서 입력 반응 지연·첫 결과 지연·최종 결과 시간·CPU·메모리를 측정한다. 속도 개선 뒤에도 preview/export/print가 같은 recipe와 품질 계약을 지키는지 확인한다.

성능 작업은 다음 순서를 지킨다: 고정 입력과 재현 절차 확정 → 단계별 시작·완료·취소·폐기 로그와 wall time·CPU·메모리·처리량 수집 → 측정으로 병목 확정 → 한 번에 한 원인만 수정 → 같은 입력·같은 설정으로 재측정 → 품질 diff와 기능 회귀 확인. 추측이나 측정되지 않은 가설만으로 코드를 바꾸지 않는다.

UI/UX 작업은 다음 증거를 한 묶음으로 남긴다: 같은 창 크기·DPI·입력·선택·탭·펼침 상태의 macOS 기준 스크린샷, `computer-use`로 캡처한 Windows 실제 화면, 양쪽 화면을 만드는 macOS/Windows 코드 위치, `baseline/swift-ui-metrics.json`의 수치, 차이 목록, 수정 후 재캡처, 클릭·키보드·접근성·백엔드 동작 결과. 여섯 지원 언어 각각에서 텍스트의 잘림·가림·부자연스러운 생략·컨트롤 겹침과 포커스/접근성 이름을 확인한다. 스크린샷만 또는 코드만으로 완료 처리하지 않는다.

## 단일 워크플로 불변식

Library·Develop·Print는 하나의 catalog와 하나의 사용자 작업 흐름을 공유한다. Library의 현재 projection·interaction scope·active frame·selected set은 Develop의 중앙 이미지·좌측 파일/filmstrip·하단 filmstrip과 Print의 대상 집합으로 이어져야 한다. 화면 전환은 프레임을 다시 한 장씩 가져오는 동작이 아니며, Develop recipe·thumbnail revision·source revision도 같은 frame identity를 유지한다. 어느 화면에서든 이미지·썸네일·선택·순서·recipe가 끊기거나 다른 프레임으로 바뀌면 완료가 아니다.

## 읽은 기준

- `docs/STATUS.md`
- `docs/progress/next-steps.md`
- `docs/progress/overall-roadmap.md`
- `baseline/`
- `C:\Users\habin\negaflow\windows_docs\08-ui\parity-contract.md`
- `C:\Users\habin\negaflow\windows_docs\08-ui\surfaces\library.md`
- `C:\Users\habin\negaflow\windows_docs\08-ui\surfaces\develop.md`
- `C:\Users\habin\negaflow\windows_docs\08-ui\surfaces\defects.md`
- `C:\Users\habin\negaflow\windows_docs\08-ui\surfaces\print.md`

## 체크포인트 기록

### CP0 — 목표 고정

- 한 것: 사용자 목표의 기능·품질·성능·검증 범위와 운영 요구를 이 문서에 고정했다.
- 안 한 것: 실제 앱 재현, 코드 수정, 렌더 비교, 장치 스캔, 출력 검증.
- 수정할 것: 상태 표의 목표 1부터 실제 증거를 채운다.
- 수정한 것: 이 추적 문서만 생성했다.
- 검증한 것: 목표 1~10과 추가 운영 요구가 빠짐없이 포함됐는지 문서 diff로 확인한다.

### CP1 — 최신 setup 기준 실행 준비

- 한 것: 본체 `scripts/build-release.ps1`와 SANE `scripts/build-installer.ps1`, 두 NSIS setup의 설치 경로·교체 방식·검증 범위를 읽었다.
- 안 한 것: 현재 작업 트리 빌드, setup 생성, 최신 setup 설치, GUI 재실행.
- 수정할 것: 두 setup을 현재 소스로 빌드하고 설치한 뒤 설치 시각·해시·실행 결과를 기록한다.
- 수정한 것: 최신 setup만 실제 QA 기준으로 사용한다는 운영 규칙을 이 문서에 추가했다.
- 검증한 것: 현재 설치된 `C:\Users\habin\AppData\Local\Negaflow\App\Negaflow.Shell.exe`가 `computer-use` 실행 뒤 창을 노출하지 않았고, 현재 소스보다 앞선 2026-08-16 22:16 빌드임을 확인했다. 원인은 아직 확정하지 않았다.

### CP2 — 로컬 CI와 설치본 시작 경로

- 한 것: macOS `ci-gate.sh`와 같은 단일 Windows 진입점 `scripts/local-ci.ps1`을 만들고 x64 Release core gate, setup build, 임시 설치, package identity 등록, 실제 창 생성, 제거를 한 번에 실행했다.
- 안 한 것: 이 통과는 macOS UI/UX·이미지 품질 parity, 실제 8100/V700 스캔, GrainMend 사용자 워크플로 검증을 의미하지 않는다.
- 수정할 것: 로컬 CI를 통과한 setup을 실제 기본 경로에 설치한 뒤 `computer-use` 전체 워크플로 QA를 진행한다.
- 수정한 것: 패키지 ID 없이 실행한 Negaflow와 빈 WinUI 진단 앱이 모두 `0x80073D54`를 stowed exception으로 남기며 종료되는 배포 결함을 확인했다. setup이 unsigned loose package를 현재 사용자에게 등록하고 실패 시 이전 설치를 복구하도록 바꿨으며, setup 검증에 실제 창 생성과 package 제거를 추가했다.
- 검증한 것: `scripts/local-ci.ps1` 통과. native CTest 71/71, catalog 721 assertions, shell 905 assertions, setup 설치·package identity·창 생성·제거 통과. 설치 파일 SHA-256은 `d43909ab55f3c16164e5e3445f19d318bf782d52180e89f0bcfc97b228d97f6d`, 로그는 `out\logs\local-ci-20260817-000901.log`이다.

### CP3 — 로컬 CI 통과 setup의 실제 기본 경로 설치

- 한 것: 로컬 CI를 통과한 본체 1.0.9 setup과 SANE 1.0.4 setup을 실제 기본 경로에 설치하고 설치본을 `computer-use`로 실행했다.
- 안 한 것: 화면이 열렸다는 사실은 Library→Develop→Print, GrainMend, 성능, UI/UX parity 통과가 아니다.
- 수정할 것: `computer-use` 캡처에서 다시 확인된 한국어 글자 깨짐·잘림, 좌측 패널의 macOS 불일치, 접근성 트리 미노출을 목표 2·5와 다국어 검증 항목에서 수정한다.
- 수정한 것: 이전에 창이 열리지 않던 unpackaged 설치본을 package identity를 가진 최신 설치본으로 교체했다.
- 검증한 것: `Negaflow.Windows_1.0.9.0_x64__esnvpjf0wq370`, `InstallLocation=C:\Users\habin\AppData\Local\Negaflow\App`, `Status=Ok`; `computer-use`가 `Negaflow.Windows_esnvpjf0wq370!App`의 2560×1392 창을 캡처했다. 같은 시점의 설치본 SANE `detect`는 GT-X900과 OpticFilm 8100을 모두 반환했다.

### CP4 — Library→Develop→Print 공유 활성 프레임

- 한 것: `C:\Users\habin\OneDrive\바탕 화면\negaflow_test` 카탈로그에서 `OpticFilm8100_frame_1.tiff`를 선택하고 Library→Develop→Print를 이동한 뒤 앱을 재시작해 같은 frame id·이미지·썸네일·filmstrip·인화 대상이 유지되는지 확인했다. macOS `PrintWorkspaceSidebar.swift`, `ContentView+PrintWorkspace.swift`, `print_overview.png`를 함께 대조했다.
- 안 한 것: 이 체크포인트는 GrainMend 다섯 경로, 실제 장치 신규 스캔, Print 전체 기능·픽셀/치수 parity, 여섯 언어 렌더링, 전체 성능 목표를 완료하지 않았다.
- 수정할 것: 목표 1의 GrainMend 자동·가이드·브러시·복제·IR 실제 입력 검증으로 이동한다. UI/UX 전체 대조는 화면별 metric·상태·언어 증거가 모일 때까지 완료로 표시하지 않는다.
- 수정한 것: LibraryHost의 선택 집합과 활성 한 장을 분리하고 `presentation.json`에 활성 frame id를 저장했다. Library의 그룹화된 `GridView` 선택 delta를 공유 상태에 반영하고 projection 교체 전체에서 프로그램 선택 이벤트를 차단했다. 모든 presentation 변경 때 Filmstrip이 불필요하게 항목을 재바인딩하면서 이전 선택으로 되돌리던 재진입을 제거했다. Develop·Print filmstrip과 Print 미리보기를 같은 활성 frame에 연결했다. Print 왼쪽의 고정 빈 상태를 Library와 같은 폴더/사진 트리로 교체하고 트리 선택, 상단·좌측·우측 활성 프레임명을 연결했다.
- 검증한 것: 실제 설치본 2560×1392 화면에서 `activeFrameId=7bcc36cb-cda8-46bd-9d2e-b5896e45ceac`, Develop 중앙 이미지·왼쪽 선택기·하단 선택 카드, Print 파일 트리·미리보기·하단 선택 카드·세 헤더가 모두 `OpticFilm8100_frame_1.tiff`를 가리켰다. 재시작 뒤 같은 id가 유지됐다. 최종 `scripts/local-ci.ps1` 종료 코드는 0이고 로그는 `out\logs\local-ci-20260817-010313.log`, setup SHA-256은 `855f19360a5e7a19d4540255ddbcc2ec80bc8d4c021a51b3f452fe7d1032e742`다. native x64 Release 71/71, catalog 721 assertions, shell 909 assertions를 확인했고 setup 설치, package identity, 실제 창 생성, 제거를 통과했다.
