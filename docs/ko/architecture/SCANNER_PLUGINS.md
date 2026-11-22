# 스캐너 플러그인 구조

[문서 홈](../README.md)

negaflow의 기본 입력은 이미지 가져오기입니다. 실제 스캐너는 외부 플러그인이 있을 때만 연결됩니다.

> [!IMPORTANT]
> 앱은 스캐너 모델명으로 기능을 추측하지 않습니다. 플러그인이 보고한 것만 화면과 요청에 들어가고, 데모 장치는 사용자가 직접 데모 모드를 고를 때만 나타납니다.

## 구성 요소

| 요소 | 역할 |
|---|---|
| 이미지 가져오기 | RAW, DNG, TIFF, PNG, JPEG를 현상 경로로 보냅니다. |
| 외부 플러그인 | 별도 프로세스로 실행되어 실제 장치를 제어하고 JSON으로 통신합니다. |
| 데모 스캐너 | 개발용 `negaflow Scanner`와 `negaflow Flatbed Scanner`를 갖춥니다. 데모를 직접 골라야 켜집니다. |
| ImageCaptureCore 연결 | macOS 이미지 캡처 장치용 호환 코드이며 지금은 비활성입니다. |

SANE 구현 코드는 본체 저장소 밖의 별도 GPL 프로젝트에 있습니다.

- <https://github.com/habinsong/negaflow-scanner-sane>

## 연결 방식

macOS에서는 화면이 `ScannerKit`과 통신하고 `ScannerKit`이 아래 세 `ScannerBackend` 구현 가운데 알맞은 쪽으로 보냅니다.

1. `ExternalScannerBackend`: 설치된 외부 플러그인을 실행합니다.
2. `MockScannerBackend`: 개발용 합성 이미지를 만듭니다.
3. `InactiveImageCaptureBackend`: 지금은 비활성입니다.

Windows에서는 셸이 외부 플러그인용 `ScannerPluginGateway`나 데모 모드용 `SimulatedScannerGateway`로 연결합니다.

플러그인 장치 ID는 앱에서 `plugin:<pluginId>:<deviceId>`로 나타납니다.

플러그인을 실행할 때는 `plugin:<pluginId>:`를 떼고 플러그인 자체의 장치 ID만 보냅니다.

## 플러그인 찾기

기본 매니페스트 경로는 macOS가 `~/Library/Application Support/negaflow/Plugins/<id>/manifest.json`, Windows가 `%LOCALAPPDATA%\Negaflow\Plugins\<id>\manifest.json`입니다. macOS의 테스트와 로컬 개발에서는 `NEGAFLOW_PLUGINS_DIR`로 다른 폴더를 가리킬 수 있습니다.

| 필드 | 규칙 |
|---|---|
| `schemaVersion` | 지금은 정확히 `1` |
| `protocolVersion` | 없으면 `1`(`1`과 `2`를 지원하며 Windows에서 스캔할 때는 `2`가 필요함) |
| `id` | 고유한 플러그인 ID |
| `name` | 화면에 보이는 이름 |
| `pluginVersion` | 선택 플러그인 버전 문자열 |
| `kind` | 생략하면 기본값 `"scanner"`, 다른 문자열은 거부 |
| `license` | 배포 라이선스 |
| `homepage` | 프로젝트 주소 |
| `executable` | 플러그인 폴더 안의 상대 경로(`.`, `..`, 선행 `/`, 심볼릭 링크, 리파스 포인트 불가) |

`id`는 ASCII 문자 1~64자입니다. 첫 글자에는 영문자나 숫자만 오고 나머지 자리에는 영문자, 숫자, `.`, `_`, `-`만 들어갑니다. `:`는 장치 ID 구분자이므로 허용하지 않습니다.

매니페스트와 실행 파일이 모두 확인될 때만 플러그인이 열리며, 옛 스키마나 아직 지원하지 않는 스키마와 알 수 없는 프로토콜 버전은 즉시 거부합니다.

### 파일 안전 검사

> [!WARNING]
> 매니페스트나 실행 파일의 바이트가 바뀌면 이전 승인이 폐기됩니다. 파일 안전 조건과 SHA-256 해시는 실행 직전에 다시 확인합니다.

- macOS에서는 플러그인 폴더와 매니페스트, 실행 파일의 소유자가 현재 사용자여야 하며 그룹이나 타인의 수정 권한과 심볼릭 링크는 막습니다.
- Windows에서는 플러그인 폴더와 매니페스트, 실행 파일의 리파스 포인트를 거부하며 실행 파일 경로가 플러그인 디렉터리 안에 머물러야 합니다.
- 두 플랫폼 모두 매니페스트와 실행 파일의 SHA-256을 기록합니다.
- 처음 실행할 때 사용자가 승인합니다.
- 파일 바이트가 바뀌면 승인이 무효가 됩니다.
- 해시와 ID는 실행 직전에 다시 계산합니다.

## 명령

플러그인은 항상 별도 프로세스로 띄웁니다.

| 명령 | 결과 |
|---|---|
| `detect` | JSON 장치 목록 |
| `capabilities <deviceId>` | JSON 기능 목록. `detect`가 보고한 장치 ID와 제조사, 모델 JSON을 stdin으로 받을 수 있음 |
| `scan`(macOS) / `scan <deviceId>`(Windows) | stdin으로 설정 JSON을 받고 stdout으로 진행 상황 NDJSON과 최종 결과를 냄 |

## 스캔 프로토콜

### 버전 1

옛 호환 규격이라 요청과 NDJSON에서 `protocolVersion`이나 `requestID`와 `sequence` 필드가 빠집니다. 또한 실제로 반영된 설정을 보고할 수 없으므로 요청 설정을 그대로 복사하는 대신 결과를 `.unknownLegacy(protocolVersion: 1)`로만 기록합니다.

### 버전 2

매니페스트에 `"protocolVersion": 2`가 있을 때만 켜집니다. Windows에서 스캔을 실행할 때는 프로토콜 v2가 필수입니다.

요청에는 아래가 들어갑니다.

- `protocolVersion: 2`
- 앱이 만든 `requestID` UUID

`capabilities` 응답은 선택 필드 `capabilityToken`을 반환할 수 있는데 앱은 이 토큰을 해석하는 대신 그 장치로 보내는 다음 v2 `scan` 요청에만 그대로 전달합니다. 따라서 v1 요청이나 다른 장치의 요청에서는 이 토큰을 제외하며 토큰의 형식과 유효성은 플러그인이 직접 살핍니다.

한 백엔드의 다른 모델에 잘못 다시 연결되는 일을 막기 위해 앱은 마지막 `detect`에서 받은 `deviceID`, `vendor`, `model`을 `capabilities`의 선택 stdin JSON으로 되넘깁니다. 이때 기존 플러그인은 이 입력을 무시해도 되지만 장치 주소가 바뀔 수 있는 플러그인은 이 식별 정보를 기능 스냅샷에 함께 기록해 두고 다음 `scan`에서 다시 확인합니다.

NDJSON 이벤트마다 똑같은 버전과 요청 ID를 되풀이하며 앞 이벤트보다 큰 0 이상의 `sequence`를 붙입니다. 이벤트 종류는 `progress`, `result`, `error`만 허용하는데 이 가운데 `result`와 `error`는 스트림의 마지막 이벤트이므로 그 뒤에 다른 출력이 뒤따르면 실패로 처리합니다. 또한 오류 없이 끝난 스캔에는 `result`가 단 한 건만 들어갑니다.

아래 조건에 걸리면 모두 닫힌 채로 멈춥니다.

- 읽을 수 없는 이벤트
- 버전이나 요청 ID가 없거나 다른 경우
- 반복되거나 순서가 어긋난 sequence
- 모르는 이벤트
- 중복된 결과
- 마지막 이벤트 뒤의 추가 출력
- 잘못된 UTF-8

macOS에서는 스트림 도중 v2 규격을 어기면 평소의 제한 시간을 기다리는 대신 플러그인을 즉시 종료하며 Windows에서는 프로세스가 끝난 뒤 v2 이벤트 스트림을 검증합니다.

### 실제로 적용된 설정

v2 `result`에는 `appliedOptions`가 반드시 들어갑니다.

- `deviceID`, `resolutionDPI`, `bitDepth`, `colorMode`, `filmType`
- `scanArea`: `originXMM`, `originYMM`, `widthMM`, `heightMM`으로 구성되며 플러그인이 백엔드에 실제로 보낸 영역을 나타냅니다. 여기서 `originXMM`과 `originYMM`, `widthMM`은 요청과 일치하고 백엔드가 스캔 높이를 잘못 계산하는 문제를 피할 때만 `heightMM`이 1mm 미만으로 달라질 수 있습니다. 앱은 수신한 픽셀 크기를 이 영역과 대조하므로 요청을 그대로 베끼면 검사가 무의미해집니다.
- `infrared`, `multiExposure`
- `hardwareExposureTime`, `brightnessAdjustment`, `contrastAdjustment`
- `outputRawTIFF`

뒤의 조정 항목 셋은 설정이 `null`이어도 키를 반드시 포함합니다.

`resolutionDPI: 0`은 미리보기를 가리키므로 0이 아닌 미리보기나 0인 본 스캔은 막습니다. 마찬가지로 알 수 없는 옵션이나 다른 장치의 응답, 결과 헤더와 `appliedOptions`의 해상도나 비트 심도, IR 상태가 어긋나는 응답도 거부합니다.

검사를 통과하면 앱은 플러그인 ID 대신 자기 스캐너 ID와 요청 ID를 기록하고 최종 출력 경로를 지킵니다. 그때서야 `.verified(options)`로 표시합니다.

v1에서는 `ScanResult.resolution`과 `bitDepth`가 요청 설정으로 대체될 수 있지만 출처를 표시하는 `reportedResolution`과 `reportedBitDepth`는 결과가 직접 보고한 유효한 수치만 받습니다.

## 위치를 지정하는 평판 스캔 영역

이 작업 흐름의 미리보기는 장치 기본 설정에 맡기는 대신 300dpi에 가장 가까운 지원 해상도를 명시해 요청하는데 장치 기본 해상도는 25dpi까지 내려갈 수 있어 프레임을 배치하거나 검출하기에 너무 거칠기 때문입니다. 해상도를 지정한 미리보기는 플러그인의 전용 미리보기 경로 대신 일반 스캔 경로로 실행됩니다.

위치를 고른 평판 스캔은 플러그인이 아래를 모두 보고할 때만 켜집니다.

- 미리보기
- `supportsScanArea: true`와 `supportsPositionedScanArea: true`
- 물리 스캔 영역 단위(`scanAreaUnit != "pixel"`)
- 음수가 아닌 시작점과 유효한 범위를 가진 mm 단위의 `scanOriginXRange`, `scanOriginYRange`
- 양수 최소와 최대 범위를 가진 mm 단위의 `scanWidthRange`, `scanHeightRange`

앱은 고른 영역을 플러그인의 단계 크기까지 바깥으로 넓히고 영역마다 개별 본 스캔 작업을 만들며 모델명으로 기능을 추측하는 과정은 생략합니다. 반면 선택 필드가 없는 옛 플러그인은 고정 프레임 흐름을 따릅니다.

## 프로세스 제한과 취소

- macOS 상한: stdout 4MiB, stderr 1MiB, 제한 시간은 `detect` 90초, `capabilities` 180초, `scan` 2시간이며 스트림 도중 v2 규격을 어기면 즉시 종료합니다.
- Windows 상한: stdout은 `detect`와 `capabilities` 4MiB, `scan` 8MiB(줄당 256KiB), stderr 512KiB, 제한 시간은 `detect` 15초, `capabilities` 180초, `scan` 2시간이며 프로세스가 끝난 뒤 v2 스트림을 살핍니다.

상한을 넘으면 프로세스를 즉시 종료하고 실패로 처리합니다. 이때 정리 과정에서는 이미 파이프에 도착한 바이트만 읽고, 자식 프로세스가 파이프를 물려받았더라도 EOF를 기다리는 대신 바로 핸들을 닫습니다.

`cancelScan()`은 플러그인이 끝나고 파이프 핸들러가 닫히고 다음 작업의 자리가 비어야 복귀합니다.

## 스캔 파일 게시

플러그인은 앱이 넘겨준 `outputPath`에 원본 이미지를 기록하고 결과의 `path` 필드에 똑같은 경로를 반환하는데, 이 경로는 최종 폴더와 한 디스크 안에 만든 임시 위치이며 게시 절차는 아래 순서를 따릅니다.

1. 앱이 설정 JSON과 `outputPath`를 플러그인에 보냅니다.
2. 플러그인이 스캔 파일을 임시 폴더에 기록합니다.
3. 플러그인이 요청의 `outputPath`와 일치하는 `path`가 든 결과를 넘겨줍니다.
4. 앱이 파일 형식과 픽셀 크기, 경로를 확인합니다.
5. 검사를 통과하면 앱이 최종 스캔 폴더로 한 번에 옮겨 게시하고, 취소되거나 오류가 나거나 출력이 잘못됐으면 임시 자료를 지웁니다.

앱이 확인하는 것:

- 비어 있지 않은 일반 파일
- macOS에서는 ImageIO가 읽을 수 있는 이미지(v2에서는 TIFF 강제), Windows에서는 `NativeTiffSourceProbe`의 메타데이터 검사를 통과하는 TIFF
- 기대한 형식과 픽셀 크기
- 요청의 `outputPath`와 결과의 `path`에 적힌 경로의 일치 여부

취소나 시간 초과, 잘못된 출력이나 플러그인 실패가 발생하면 임시 폴더를 즉시 정리하여 검증을 통과한 스캔만 최종 폴더에 게시합니다.

v2의 IR 파일 또한 앱이 지정한 임시 폴더 안에 생성되어야 하며 앱이 파일 형식과 디코딩 상태, 픽셀 크기를 살핍니다. 반면 v1은 기존 플러그인과의 호환을 위해 외부 IR 경로도 허용합니다.

## SANE 경계

SANE 구현과 의존성, 설정과 장치별 처리, 테스트와 배포 문서는 모두 별도 저장소 [`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane)에 있습니다.

이 프로젝트는 Homebrew의 기본 SANE을 기반으로 한 표준 macOS 14+ 설치 프로그램과, 공식 SANE 1.4.0에 업스트림의 최소 `coolscan2`/`coolscan3` 할당 패치를 적용해 빌드하는 별도의 macOS 26+ Coolscan 설치 프로그램을 배포합니다. 이때 표준 설치 경로는 Coolscan 장치를 따로 차단하는 대신 그 할당 패치만 뺍니다.

본체 저장소는 장치와 무관한 외부 프로세스 규격만 정의하고 검증하므로, 이미지 파일만 가져오는 사용자는 스캐너 플러그인 없이 앱을 그대로 실행할 수 있습니다.

negaflow 앱은 SANE 구현을 링크하거나 앱 배포본에 포함하는 대신, 별도 저장소와 실행 파일, 소스 배포, GPL 라이선스를 갖춘 독립 플러그인으로 분리합니다. 아울러 여기서는 기술 구조만 기록하며, 실제 배포 전에는 두 산출물의 파일 구성과 통신 규약을 다시 살핍니다.

## 검사

앱 테스트는 가짜 외부 플러그인을 실제 프로세스로 실행해 아래를 확인합니다.

- 플러그인 찾기
- 장치 찾기
- 기능 연결
- 진행 이벤트
- 최종 결과
- 취소와 실패 뒤의 정리

SANE 구현은 플러그인 저장소의 SwiftPM 테스트와 Release 빌드에서 따로 검증을 거칩니다.
