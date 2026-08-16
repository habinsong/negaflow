# Windows 최초 QA·프리뷰 데모·베타 추적

기준일: 2026-08-16

이 문서는 최초 QA·프리뷰 데모·베타 테스트의 단일 추적 문서다. 아래 사용자 목표의 기능·품질·성능·검증 범위는 축약하거나 재해석하지 않는다. 각 목표는 실제 Windows 앱, 지정 입력, 실제 장치, macOS 기준 화면·코드로 검증되기 전까지 완료로 표시하지 않는다.

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
- UI/UX는 `computer-use`를 사용해 Windows 실제 화면을 캡처하고 macOS 스크린샷과 비교하며, 양쪽 코드와 고정 metric도 함께 비교한다.
- 다국어 텍스트 길이 확장을 고려해 UI/UX를 구현한다. 지원 언어별 문자열이 길어져도 뒤쪽 글자가 잘리거나 가려지지 않게 하고, macOS 계약을 벗어나지 않는 범위에서 줄바꿈·가변 너비·최소 높이와 접근성 이름이 자연스럽게 동작하도록 한다. 여섯 언어(`de`, `en`, `fr`, `ja`, `ko`, `zh-Hans`)의 실제 렌더링을 각각 검증한다.
- Library·Develop·Print는 분리된 기능이 아니라 하나의 연속된 워크플로다. 현재 끊긴 이미지·썸네일·선택·filmstrip·Print 대상 전달을 모두 수정한다.
- Negaflow 본체와 `negaflow-scanner-sane` 모두 저장소에 이미 있는 setup/build-installer 경로로 최신 소스를 빌드·설치한 뒤 `computer-use` 검증을 수행한다. 설치된 오래된 실행 파일이나 임의 실행 경로를 기준으로 삼지 않는다.
- 체크포인트 커밋·푸시는 별도 작업 브랜치를 만들지 않고 각 저장소의 `main`에 직접 수행한다. 저장소에는 `main`만 유지한다.

## 상태 표

상태 값은 `미재현`, `재현`, `수정 중`, `수정`, `부분 검증`, `검증 완료`만 사용한다. `검증 완료`는 해당 목표의 전체 실제 경로와 macOS 동등성 증거가 있을 때만 쓴다.

| 목표 | 상태 | 현재 확인 사실 | 수정할 것 | 수정한 것 | 검증한 것 |
| --- | --- | --- | --- | --- | --- |
| 1 | 미재현 | 사용자 보고: 후보 없음만 표시, 복제 도구 클리핑, 자동·가이드·브러시·복제·IR 동작 실패 | 실제 앱에서 다섯 경로를 각각 재현하고 macOS 동작·결과와 대조 | 없음 | 없음 |
| 2 | 미재현 | 사용자 보고: 화면 크기·형태·라운딩·위치·정렬 불일치, 현상 버튼 누락, 미구현 UI와 미연결 백엔드 존재 | 스크린샷·SwiftUI·고정 UI metric을 화면별로 대조 | 없음 | 없음 |
| 3 | 미재현 | 사용자 보고: Library 가져오기 뒤 Develop 이미지·썸네일·하단 탭 단절 | frame selection·interaction scope·thumbnail·filmstrip·workspace 전달 경로 점검 | 없음 | 없음 |
| 4 | 미재현 | 사용자 보고: Develop 좌측 탭이 macOS와 다르고 한 장 가져오기 흐름으로 축소됨 | macOS Develop 좌측 6탭과 Library interaction scope를 그대로 연결 | 없음 | 없음 |
| 5 | 미재현 | 사용자 보고: 문자열 클리핑·가림 | 여섯 로케일·DPI·창 크기별 실제 렌더 대조 | 없음 | 없음 |
| 6 | 미재현 | 사용자 보고: Develop 우측 슬라이더 반영이 수초 지연 | 입력→recipe→preview scheduling→native render→present 지연 계측 및 실시간 갱신 | 없음 | 없음 |
| 7 | 미재현 | 사용자 보고: 자동 톤·자동 색상·자동 레벨이 실패하거나 매우 느림 | 세 기능을 독립 재현하고 macOS 결과·지연과 대조 | 없음 | 없음 |
| 8 | 미재현 | 사용자 보고: crop·rotate·flip 등 기하 편집이 매우 느림 | gesture→transform preview 경로와 불필요한 전체 렌더·I/O 점검 | 없음 | 없음 |
| 9 | 미재현 | 사용자 보고: Print에 이미지가 전달되지 않고 UI/UX도 불일치 | Library/Develop 선택 집합→Print layout·preview 전달과 macOS 화면 대조 | 없음 | 없음 |
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
