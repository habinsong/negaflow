# 스캐너 플러그인 구조

[문서 홈](../README.md)

negaflow의 기본 입력은 이미지 가져오기입니다. 실제 스캐너는 외부 플러그인이 있을 때만 연결됩니다.

> [!IMPORTANT]
> 앱은 스캐너 모델명으로 기능을 추측하지 않습니다. 플러그인이 보고한 것만 화면과 요청에 들어가고, 데모 장치는 사용자가 직접 데모 모드를 고를 때만 나타납니다.

## 구성 요소

| 요소 | 역할 |
|---|---|
| 이미지 가져오기 | RAW, DNG, TIFF, PNG, JPEG를 현상 경로로 보냅니다. |
| 외부 플러그인 | 별도 프로세스로 실행되어 실제 장치를 다루고 JSON으로 통신합니다. |
| 데모 스캐너 | 개발용 `negaflow Scanner`와 `negaflow Flatbed Scanner`를 제공합니다. 데모를 직접 골라야 씁니다. |
| ImageCaptureCore 연결 | macOS 이미지 캡처 장치용 호환 코드이며 지금은 비활성입니다. |

이 저장소에는 SANE 구현이 없습니다. 그 코드는 별도 GPL 프로젝트에 있습니다.

- <https://github.com/habinsong/negaflow-scanner-sane>

## 연결 방식

화면은 `ScannerKit`과 통신하고 `ScannerKit`은 세 백엔드 중 하나로 보냅니다.

1. `ExternalScannerBackend`: 설치된 외부 플러그인을 실행합니다.
2. `MockScannerBackend`: 개발용 합성 이미지를 만듭니다.
3. `InactiveImageCaptureBackend`: 지금은 비활성입니다.

화면은 `ScannerBackend`만 봅니다. 플러그인 장치 ID는 앱에서 `plugin:<pluginId>:<deviceId>`로 나타납니다.

플러그인을 실행할 때는 `plugin:<pluginId>:`를 떼고 플러그인 자체의 장치 ID만 보냅니다.

## 플러그인 찾기

기본 폴더는 `~/Library/Application Support/negaflow/Plugins/<id>/manifest.json`입니다. 테스트와 로컬 개발에서는 `NEGAFLOW_PLUGINS_DIR`로 다른 폴더를 가리킵니다.

| 필드 | 규칙 |
|---|---|
| `schemaVersion` | 지금은 정확히 `1` |
| `protocolVersion` | 없으면 `1`, `1`과 `2`를 지원 |
| `id` | 고유한 플러그인 ID |
| `name` | 화면에 보이는 이름 |
| `kind` | 플러그인 종류 |
| `license` | 배포 라이선스 |
| `homepage` | 프로젝트 주소 |
| `executable` | 실행 파일 경로 |

`id`는 ASCII 문자 1~64자입니다. 첫 글자는 영문자나 숫자이고 나머지는 영문자, 숫자, `.`, `_`, `-`입니다. `:`는 장치 ID 구분자라서 쓸 수 없습니다.

매니페스트와 실행 파일이 모두 확인될 때만 플러그인이 열립니다. 옛 스키마, 앞으로 나올 스키마, 모르는 프로토콜은 짐작으로 읽지 않습니다.

### 파일 안전 검사

> [!WARNING]
> 매니페스트나 실행 파일의 바이트가 바뀌면 이전 승인이 폐기됩니다. 소유자, 권한, 심볼릭 링크 여부, SHA-256은 실행 직전에 다시 확인합니다.

- 플러그인 폴더, 매니페스트, 실행 파일의 소유자가 현재 사용자여야 합니다.
- 그룹이나 다른 사용자가 쓸 수 있으면 거부합니다.
- 심볼릭 링크는 거부합니다.
- 매니페스트와 실행 파일의 SHA-256을 기록합니다.
- 처음 쓸 때 사용자가 승인합니다.
- 파일 바이트가 바뀌면 승인이 무효가 됩니다.
- ID는 실행 직전에 다시 계산합니다.

## 명령

플러그인은 별도 프로세스로 실행됩니다.

| 명령 | 결과 |
|---|---|
| `detect` | JSON 장치 목록 |
| `capabilities <deviceId>` | JSON 기능 목록. `detect`가 보고한 장치 ID, 제조사, 모델 JSON을 stdin으로 받을 수 있음 |
| `scan` | stdin으로 설정 JSON을 받고, stdout으로 진행 상황 NDJSON과 최종 결과를 냄 |

## 스캔 프로토콜

### 버전 1

옛 호환 규격입니다. 요청과 NDJSON에 `protocolVersion`, `requestID`, `sequence`가 없습니다. 실제로 적용된 설정을 보고할 수 없어서 결과를 `.unknownLegacy(protocolVersion: 1)`로 기록합니다. 요청 값을 검증된 것처럼 복사해 넣지 않습니다.

### 버전 2

매니페스트에 `"protocolVersion": 2`가 있을 때만 씁니다.

요청에는 아래가 들어갑니다.

- `protocolVersion: 2`
- 앱이 만든 `requestID` UUID

`capabilities` 응답은 선택 필드 `capabilityToken`을 돌려줄 수 있습니다. 앱은 이 값을 해석하지 않고, 같은 장치의 다음 v2 `scan` 요청에만 그대로 넘깁니다. v1 요청에는 넣지 않고, 장치 사이에서 토큰을 섞지 않습니다. 토큰의 형식과 유효성은 플러그인이 직접 검사해야 합니다.

같은 백엔드의 다른 모델에 잘못 다시 연결되는 것을 막으려고, 앱은 마지막 `detect`의 `deviceID`, `vendor`, `model`을 `capabilities`의 선택 stdin JSON으로 되넘깁니다. 기존 플러그인은 이 입력을 무시해도 됩니다. 장치 주소가 바뀔 수 있는 플러그인은 이 식별 정보를 기능 스냅샷에 묶고 다음 `scan`에서 다시 확인해야 합니다.

NDJSON 이벤트마다 같은 버전과 요청 ID를 되풀이하고, 앞 이벤트보다 큰 0 이상의 `sequence`를 붙입니다. 허용되는 것은 `progress`, `result`, `error`뿐입니다. `result`와 `error`는 마지막 이벤트이고 그 뒤에 무엇이 오면 실패입니다. 오류 없이 끝난 스캔에는 `result`가 정확히 하나 있습니다.

아래는 모두 닫힌 채로 실패합니다.

- 읽을 수 없는 이벤트
- 버전이나 요청 ID가 없거나 다른 경우
- 반복되거나 순서가 어긋난 sequence
- 모르는 이벤트
- 중복된 결과
- 마지막 이벤트 뒤의 추가 출력
- 잘못된 UTF-8

v2 규격을 어기면 평소의 제한 시간을 기다리지 않고 플러그인을 바로 끝냅니다.

### 실제로 적용된 설정

v2 `result`에는 `appliedOptions`가 있어야 합니다.

- `deviceID`, `resolutionDPI`, `bitDepth`, `colorMode`, `filmType`
- `scanArea`: `originXMM`, `originYMM`, `widthMM`, `heightMM`. 플러그인이 백엔드에 실제로 보낸 영역입니다. 백엔드가 스캔 크기를 잘못 계산하는 문제를 피하려고 1mm 미만으로 조정할 수 있습니다. 앱은 돌아온 픽셀 크기를 이 영역과 대조하므로 요청을 그대로 베끼면 검사가 무의미해집니다.
- `infrared`, `multiExposure`
- `hardwareExposureTime`, `brightnessAdjustment`, `contrastAdjustment`
- `outputRawTIFF`

뒤의 조정 값 셋은 값이 `null`이어도 키가 있어야 합니다.

`resolutionDPI: 0`은 미리보기입니다. 0이 아닌 미리보기나 0인 본 스캔은 거부합니다. 모르는 값, 다른 장치, 결과 헤더와 `appliedOptions`가 어긋나는 해상도·비트 심도·IR 상태도 거부합니다.

검사를 통과하면 앱은 플러그인 ID 대신 자기 스캐너 ID와 요청 ID를 기록하고 최종 출력 경로를 유지합니다. 그때서야 `.verified(options)`로 표시합니다.

v1에서는 `ScanResult.resolution`과 `bitDepth`가 요청값으로 대체될 수 있습니다. 출처를 보여 주는 `reportedResolution`과 `reportedBitDepth`는 결과가 직접 보고한 올바른 값만 받습니다.

## 위치를 지정하는 평판 스캔 영역

이 작업 흐름의 미리보기는 장치에 맡기지 않고 300dpi에 가장 가까운 지원 값을 해상도로 명시해 요청합니다. 장치 기본값은 25dpi까지 낮을 수 있고, 그 정도면 프레임을 놓거나 검출하기에 너무 거칩니다. 해상도가 붙은 미리보기는 일반 스캔이라서 플러그인의 미리보기 경로를 쓰지 않습니다.

위치를 고른 평판 스캔은 플러그인이 아래를 모두 보고할 때만 켜집니다.

- 미리보기
- `supportsPositionedScanArea`
- mm 단위의 `scanOriginXRange`, `scanOriginYRange`
- mm 단위의 `scanWidthRange`, `scanHeightRange`

앱은 고른 영역을 플러그인의 단계 크기까지 바깥으로 넓히고 영역마다 본 스캔 작업을 하나씩 만듭니다. 모델명으로 짐작하는 일은 없습니다. 선택 필드가 없는 옛 플러그인은 고정 프레임 흐름을 유지합니다.

## 프로세스 제한과 취소

- stdout 상한: 4MiB
- stderr 상한: 1MiB

상한을 넘으면 프로세스를 끝내고 실패합니다. 정리 중에는 이미 도착한 바이트만 읽습니다. 자식 프로세스가 파이프를 물려받았어도 EOF를 기다리지 않습니다.

`cancelScan()`은 플러그인이 끝나고 파이프 핸들러가 닫히고 다음 작업의 자리가 비어야 돌아옵니다.

## 스캔 파일 게시

플러그인은 앱이 준 `outputPath`에 정확히 원본 이미지를 쓰고 결과에도 같은 경로를 돌려줍니다. 이 경로는 최종 폴더와 같은 디스크의 임시 위치입니다. 흐름은 이렇습니다.

1. 앱이 설정 JSON과 `outputPath`를 플러그인에 보냅니다.
2. 플러그인이 스캔 파일을 임시 폴더에 씁니다.
3. 플러그인이 같은 `outputPath`가 든 결과를 돌려줍니다.
4. 앱이 형식, 크기, 경로를 확인합니다.
5. 통과하면 앱이 최종 스캔 폴더에 원자적으로 게시합니다. 취소, 실패, 잘못된 출력이면 임시 자료를 지웁니다.

앱이 확인하는 것:

- 비어 있지 않은 일반 파일
- ImageIO가 읽을 수 있는 이미지
- 기대한 형식과 픽셀 크기
- 요청과 결과에서 같은 경로

취소, 시간 초과, 잘못된 출력, 플러그인 실패가 있으면 임시 폴더를 지우고 불완전한 스캔은 게시하지 않습니다.

v2의 IR 파일도 앱이 준 임시 폴더 안에 있어야 합니다. 파일 형식, 읽기 가능 여부, 픽셀 크기를 확인합니다. v1은 이미 나와 있는 플러그인과의 호환을 위해 외부 IR 경로를 받을 수 있습니다.

## SANE 경계

SANE 구현, 의존성, 설정, 장치별 처리, 테스트, 배포 문서는 모두 별도 저장소 [`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane)에 있습니다.

그 프로젝트는 Homebrew의 기본 SANE을 쓰는 표준 macOS 14+ 설치 프로그램과, 공식 SANE 1.4.0을 업스트림의 최소 `coolscan2`/`coolscan3` 할당 수정과 함께 빌드하는 별도의 macOS 26+ Coolscan 설치 프로그램을 배포합니다. 표준 경로는 Coolscan을 미리 막지는 않지만 그 수정을 담고 있지 않습니다.

이 저장소는 장치와 무관한 외부 프로세스 규격만 문서화하고 검사합니다. 이미지 파일만 가져오는 사용자에게는 스캐너 플러그인이 필요 없습니다.

negaflow 앱은 SANE 구현을 링크하지 않고 앱 배포본에 넣지도 않습니다. 플러그인은 자체 저장소, 실행 파일, 소스 배포, GPL 라이선스를 가집니다. 이 문서는 구조를 기록할 뿐 파생 저작물인지 여부를 판정하지 않습니다. 실제 배포 전에 두 산출물의 파일과 통신 규약을 다시 확인합니다.

## 검사

앱 테스트는 가짜 외부 플러그인을 실제 프로세스로 실행해 아래를 확인합니다.

- 플러그인 찾기
- 장치 찾기
- 기능 연결
- 진행 이벤트
- 최종 결과
- 취소와 실패 뒤의 정리

SANE 구현은 플러그인 저장소의 SwiftPM 테스트와 Release 빌드에서 따로 검사합니다.
