# CLI 스캐너 JSON

[문서 홈](../README.md)

스크립트와 다른 앱은 이 JSON으로 스캐너 정보를 읽습니다. CLI는 `ScannerKit`이 받은 장치 정보와 기능을 JSON으로 바꿔 줄 뿐입니다.

| 항목 | 규약 |
|---|---|
| 명령 | `detect --json`, `capabilities <scannerID> --json` |
| stdout | JSON 문서 하나와 끝의 줄바꿈 |
| stderr | 진단 로그 |
| 스키마 | `negaflow.scanner-cli`, 버전 `1` |

## 명령

```bash
negaflow detect [--demo] --json
negaflow capabilities <scannerID> [--demo] --json
```

`--json`은 읽기 전용인 이 두 명령에서만 동작합니다. `scan`이나 `develop`에 붙이면 `unsupported_json_command` 오류로 끝납니다.

## 공통 형태

성공과 실패 모두 stdout에 JSON 문서 하나를 씁니다.

<details>
<summary>성공 응답 예시</summary>

```json
{
  "schema": "negaflow.scanner-cli",
  "schemaVersion": 1,
  "command": "capabilities",
  "status": "ok",
  "payload": {},
  "error": null
}
```

</details>

실패하면 `status`는 `error`, `payload`는 `null`입니다. `error`에는 바뀌지 않는 기계용 코드와 설명이 들어갑니다. 로그와 진행 상황은 stderr로만 나갑니다.

## 기능 정보

`capabilities`의 payload에는 항상 아래 필드가 모두 있습니다.

- `resolutionsDPI`, `modes`, `bitDepths`
- `sourceModes`, `transparencyModes`
- `supportsPreview`, `supportsTransparency`, `supportsInfrared`
- `supportsMultiExposure`, `supportsScanArea`, `supportsPositionedScanArea`
- `supportsLampWarmupStatus`
- `brightnessRange`, `contrastRange`, `hardwareExposureRange`
- `scanOriginXRange`, `scanOriginYRange`, `scanWidthRange`, `scanHeightRange`
- `disabledReasons`
- `minScanArea`, `maxScanArea`, `scanAreaUnit`
- `outputFormats`, `estimatedScanSpeeds`

장치가 보고하지 않은 값은 추측하지 않습니다. `null`, 빈 배열, `false`, 또는 플러그인이 보낸 `disabledReasons`로 나옵니다.

`estimatedScanSpeeds`는 아래 객체의 배열이며 DPI 오름차순입니다.

```json
{ "dpi": 3600, "seconds": 42.0 }
```

앱과 CLI는 같은 `ScannerCapabilities`를 읽습니다. 화면의 컨트롤이 JSON 필드를 따르는지는 일관성 검사로 확인합니다.

## 버전 규칙

- 기존 필드의 의미와 타입은 바꾸지 않습니다.
- 새 선택 필드는 옛 프로그램이 모르는 필드를 무시할 수 있을 때만 넣습니다.
- 필드를 없애거나 이름 또는 타입을 바꾸면 `schemaVersion`을 올립니다.
- 해상도, 모드, 비트 심도는 플러그인이 준 순서를 지킵니다. 예상 속도만 DPI 순으로 정렬합니다.
