# CLI 스캐너 JSON

[문서 홈](../README.md)

스크립트나 다른 앱이 스캐너 정보를 읽을 때 쓰는 규격입니다.
실제 스캐너 구현과는 분리되어 있습니다.
CLI는 `ScannerKit`이 받은 장치 정보와 기능만 JSON으로 바꿉니다.

| 항목 | 계약 |
|---|---|
| 지원 명령 | `detect --json`, `capabilities <scannerID> --json` |
| stdout | JSON 문서 하나와 마지막 줄바꿈 |
| stderr | 진단 로그 |
| 현재 스키마 | `negaflow.scanner-cli`, 버전 `1` |

## 명령

```bash
negaflow detect [--demo] --json
negaflow capabilities <scannerID> [--demo] --json
```

현재 `--json`은 위 두 읽기 전용 명령에서만 쓸 수 있습니다.
파일을 바꾸거나 진행 상황을 보내는 `scan`, `develop` 명령에 붙이면 `unsupported_json_command`
오류로 끝납니다.

## 공통 형식

성공과 실패 모두 stdout에 JSON 문서 하나만 씁니다. 마지막에는 줄바꿈이 들어갑니다.

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

실패하면 `status`에 `error`가 들어가고 `payload`는 비웁니다.
`error`에는 바뀌지 않는 기계용 코드와 사람이 읽는 설명이 들어갑니다.
진단 로그는 stderr로 보냅니다. stdout에는 로그나 진행률을 섞지 않습니다.

## 기능 정보

`capabilities`의 `payload`에는 다음 필드가 모두 들어갑니다.

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

장치가 알려 주지 않은 값은 추측하지 않습니다.
값에 맞춰 `null`, 빈 배열, `false`, 또는 플러그인이 보낸 `disabledReasons`를 그대로 씁니다.

`estimatedScanSpeeds`는 다음 객체의 배열이며 DPI 오름차순입니다.

```json
{ "dpi": 3600, "seconds": 42.0 }
```

앱 화면과 CLI는 같은 `ScannerCapabilities`를 읽습니다.
일치 검사에서는 화면에 열린 기능과 JSON 필드가 같은 값을 따르는지 확인합니다.

## 버전 규칙

- 기존 필드의 뜻이나 자료형을 바꾸지 않습니다.
- 새 선택 필드는 이전 프로그램이 모르는 필드를 무시할 수 있을 때만 추가합니다.
- 필드 삭제, 이름 변경, 자료형 변경 때는 `schemaVersion`을 올립니다.
- 해상도, 모드, 비트 심도는 플러그인 순서를 지킵니다.
- 예상 속도만 DPI로 정렬합니다.
