# 05 — 검증 방법

원칙: **앱은 마지막에.** 개발 중 확인은 CLI 계측기와 단위 시험으로 합니다. 앱을 띄워
클릭하는 것은 전부 끝난 뒤 한 번에 합니다(사용자 요구).

## 1. 계측기

### 1.1 검출 — `--grain-mend-detect`

```bash
negaflow-cli --grain-mend-detect "<source.tiff>" <dmin-r> <dmin-g> <dmin-b> [sensitivity] [guided]
```

내는 것: 분류별 개수, 평균 신뢰도, 채택 화소, 그리고 단계별 시간(디코드/현상/검출,
검출 안에서 검출이미지·먼지형태학·스크래치각도·증거·미세입자·봉합·성분).

`guided` 를 넘기면 화면 가운데 50% ROI 로 가이드 계약(구조선 배제 끔, 면적 ×48)을 돌립니다.

### 1.2 현상·내보내기 — `--export-developed-tiff16`

```bash
negaflow-cli --export-developed-tiff16 <source> <dest> <dmin-r> <dmin-g> <dmin-b> color
```

`stages` 에 decode/develop/tone/film_look/output 시간이 나옵니다. 현상·프리뷰 GPU 작업의
기준선입니다.

### 1.3 결함 도구 다섯 — `--defect-tools`

```bash
Negaflow.Shell.UnitTests.exe --defect-tools <storageRoot> <frameId> [irPath]
```

자동·가이드·브러시·복제·IR 이 실제로 화소를 바꾸는지 잽니다.

**주의: 앱이 켜진 채로 프로덕션 저장소에 대고 돌리지 마십시오.** 카탈로그를 두 프로세스가
잡습니다.

## 2. 단위 시험

```powershell
.\scripts\ci-gate.ps1 -Preset x64-release
```

또는 개별:

```powershell
.\scripts\build.ps1 -Preset x64-release # 네이티브
.\scripts\build-managed.ps1 -Preset x64-release # 관리
.\out\build\managed\Negaflow.Shell.UnitTests\x64\Release\net10.0\win-x64\Negaflow.Shell.UnitTests.exe
```

현재 기준: Shell **1043 assertions, 0 failures**, 경고 0.

### 2.1 GPU 를 넣을 때 반드시 추가할 시험

02 문서의 GPU 경로는 **CPU 경로와 같은 값**을 내야 합니다.

- 같은 입력으로 CPU/GPU 두 경로를 돌려 화소별 차이를 잰다
- 허용 오차: `float` 연산 순서 차이만큼. **먼저 재고 나서 정합니다** — 숫자를 정해 놓고
  거기 맞추지 않습니다
- GPU 가 없는 기계(또는 컴퓨트 미지원)에서 CPU 폴백이 도는지
- WARP 장치로도 같은 값이 나오는지

## 3. 화면 확인 — computer-use

**전부 끝난 뒤에만.** 순서:

1. `Get-Process negaflow.shell` 로 **떠 있는 인스턴스가 없는지** 확인하고 있으면 정리
2. `.\scripts\run-app.ps1 -Architecture x64 -Configuration Release`
3. `request_access` 에 `negaflow.shell.exe` (표시 이름이 아니라 프로세스 이름)
4. `open_application` 은 **한 번만.** 반복하면 인스턴스가 늘고 카탈로그가 충돌해 라이브러리가
   0장으로 보입니다
5. 확인 항목을 미리 목록으로 만들어 두고 순서대로 클릭

### 3.1 확인 목록 (초안)

| # | 확인할 것 | 기대 |
|---|---|---|
| 1 | 라이브러리 사진 수 | 17장 |
| 2 | 현상 뷰 좌측 레일 | macOS 와 아이콘·순서·선택 표시 같음 |
| 3 | GrainMend 카드 | 도구 4개 + , 검토 줄 없음 |
| 4 | 자동 클릭 → 결과 | **5초 미만**, 캡슐에 "결함 N개" |
| 5 | 종류별 칩 | 먼지·핀홀·스크래치·미세입자가 실제 색과 개수로 |
| 6 | 칩 클릭 | 그 종류 전체가 회색으로 바뀜, 개수 갱신 |
| 7 | 점 클릭 | 그 결함 하나만 토글 |
| 8 | 민감도 슬라이더 | 놓으면 재검출 |
| 9 | 미세 입자 체크 | 끄면 재검출, 칩에서 미세입자 사라짐 |
| 10 | 결함 제거 | 레이어 목록에 한 줄 추가, 미리보기 갱신 |
| 11 | 가이드 드래그 | ROI 안에서만 검출 |
| 12 | 브러시 | 컨트롤 바 표시, 굵기 슬라이더, 칠하고 제거 |
| 13 | 복제 도장 | Alt 클릭 소스, 십자 커서, 원 안 미리보기 |
| 14 | 우측 슬라이더 | 끌 때 프리뷰가 즉시 따라옴 |
| 15 | 인화 뷰 | 레이아웃·인스펙터가 macOS 와 같음 |

### 3.2 스크린샷 비교

Windows 스크린샷과 macOS 스크린샷을 같은 배율로 잘라 나란히 붙입니다(04 문서 2절의
PowerShell 조각). 눈으로 "비슷하다"가 아니라 **잘라 붙인 그림**을 문서에 남깁니다.

## 4. 이번 세션에서 겪은 함정

| 함정 | 증상 | 대응 |
|---|---|---|
| 앱 인스턴스 3개 | 라이브러리 0장 | 하나만 남기면 즉시 복구. 데이터는 안전했음 |
| MSBuild 낡은 오브젝트 | 시그니처 바꾼 뒤 LNK2019 | 해당 `.obj` 삭제 또는 소스 타임스탬프 갱신 |
| `run-app.ps1` 을 상대경로로 백그라운드 실행 | "term is not recognized" | 절대경로로 호출 |
| 라이브러리 그리드에서 썸네일 클릭 | 의도와 다른 프레임이 열림 | 파일명으로 확인하고 클릭 |
| `--defect-tools` 가 "frame unavailable" | 디스패처가 큐를 안 돌림 | 앱 종료 후 단독 실행, 또는 계측기 수정 |

## 5. 회귀 방지

- 검출 기준값 표([06](06-detection-reference.md))를 **커밋마다** 갱신
- 속도 표([02](02-grainmend-performance.md) 1절)를 **최적화마다** 갱신
- 화면 항목은 대조표([04](04-workspace-parity.md) 4절)의 판정을 갱신
- 문서를 고치지 않은 커밋은 "무엇이 좋아졌는지 모르는 커밋"입니다
