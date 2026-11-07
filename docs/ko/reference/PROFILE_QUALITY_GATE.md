# 스캐너 프로파일 품질 검사

[문서 홈](../README.md)

`scripts/evaluate_profile_quality.py`(`negaflow-mac/`에서 실행)는 스캐너 프로파일을 바꾼 결과가 승인된 기준선보다 나빠졌는지 검사합니다. `LUT_target/analyze_lut_target.py`가 만든 `SOURCE/summary.json` 두 개를 비교하며, 프로파일 조정에 쓰지 않고 따로 둔 검증 케이스만 판정에 반영합니다.

이 도구는 좋은 색이 무엇인지 정하지 않습니다. 어떤 수치가 내려가야 하고 올라가야 하는지, 얼마나 움직여도 되는지는 사람이 코퍼스 매니페스트에 적습니다. 기본 합격선은 없습니다.

지금 이 저장소에는 REAL/TARGET 이미지 쌍이 없습니다(`LUT_target/REAL`과 `LUT_target/TARGET`이 비어 있음). 그래서 실제 코퍼스 매니페스트도, 승인된 기준선도, 실제 장치의 합격 결과도 없습니다. 합성 테스트는 검사기 코드만 확인합니다.

> [!WARNING]
> 스캐너 색 정확도는 이 저장소만으로 승인할 수 없습니다. 배포 결정에는 고정된 REAL/TARGET 쌍, 조정에 쓰지 않은 검증 케이스, 사람이 정한 허용 오차가 필요합니다.

## 현재 프로파일을 앱이 쓰는 범위

사용자가 직접 `HS`나 `SP` 타깃을 고르면 번들 `realOnly` 그룹에서 얻은 제한된 상대 차이를 쓸 수 있습니다.

조건:

- 필름 종류와 필름 이름이 같습니다.
- 정리한 원본 롤 이름 집합이 같습니다.
- 이미지 수의 차이가 15% 이하입니다.

원본 프로파일에는 프레임별 ID나 SHA-256이 없고, 롤 이름이 같다고 같은 프레임을 짝지었다는 증거가 되지는 않습니다. 그래서 실제 장비와 같은 결과라고 부를 수 없습니다.

적용 규칙:

- 두 그룹에서 방향이 반대인 값은 적용하지 않습니다.
- 흑백은 색 성분을 모두 버리고 상대 톤만 남깁니다.
- 짝이 되는 롤이 없는 슬라이드 프로파일에는 상대 보정을 적용하지 않습니다.
- 같은 위치에서 짝을 이룬 자료가 없으면 스캐너 질감과 샤프닝은 적용하지 않습니다.
- 톤은 Rec.709 감마 밝기에 한 번 적용하고 Lab `a*`, `b*`는 보존합니다.
- 색 게인은 로그 영역에서 보간해서 반대쪽 기준점 사이의 관계를 지킵니다.
- 어느 파일이나 매니페스트의 SHA-256이 어긋나면 프로파일 번들 전체를 거부합니다.

## 제조사 자료로 확인되는 것

- [Fujifilm Frontier 570/SP-3000 안내서](https://www.photolabdigital.com/fuji_frontier570_en%5B1%5D.pdf)는 에어리어 CCD, Hyper-tone, Hyper-sharpness 같은 기능을 말하지만 전달 함수나 설정값은 공개하지 않습니다.
- [Noritsu HS-1800 제품 정보](https://www.noritsu.eu/hardware/noritsu-film-scanner.html)는 지원 규격, 해상도, 처리량을 싣지만 고정된 색 전달 함수는 주지 않습니다.
- [Noritsu 특허 US 7,589,863](https://patents.google.com/patent/US7589863/en)은 작업자가 농도, 계조, 선명도를 고르는 미니랩의 흐름을 설명합니다.

이 자료는 처리가 장면과 작업자에 따라 달라진다는 것을 보여 줍니다. HS-1800이나 SP-3000을 재현할 상수는 주지 않으며, negaflow는 제품 이름만 보고 그런 값을 추측하지 않습니다.

## 코퍼스 매니페스트 스키마 v1

매니페스트는 고정하려는 입력 자료 옆에 둡니다. 예: `LUT_target/quality/corpus-v1.json`. 경로는 매니페스트 파일 기준이며 `--data-root`를 주면 그 경로가 기준입니다.

<details>
<summary>매니페스트 예시</summary>

```json
{
  "schemaVersion": 1,
  "corpusVersion": "scanner-corpus-2026-07-10.1",
  "acceptedBaselineSHA256": "sha256:<64 lowercase hex>",
  "cases": [
    {
      "role": "calibration",
      "stem": "NORITSU/color nega/Portra 400/calibration-01",
      "real": {
        "path": "REAL/NORITSU/color nega/Portra 400/calibration-01.tif",
        "sha256": "sha256:<64 lowercase hex>"
      },
      "target": {
        "path": "TARGET/NORITSU/color nega/Portra 400/calibration-01.tif",
        "sha256": "sha256:<64 lowercase hex>"
      }
    },
    {
      "role": "holdout",
      "stem": "NORITSU/color nega/Portra 400/holdout-01",
      "real": {
        "path": "REAL/NORITSU/color nega/Portra 400/holdout-01.tif",
        "sha256": "sha256:<64 lowercase hex>"
      },
      "target": {
        "path": "TARGET/NORITSU/color nega/Portra 400/holdout-01.tif",
        "sha256": "sha256:<64 lowercase hex>"
      }
    }
  ],
  "metrics": [
    {
      "name": "mean_delta_e2000",
      "direction": "lowerIsBetter",
      "allowedRegression": 0.0
    },
    {
      "name": "similarity_score_0_100",
      "direction": "higherIsBetter",
      "allowedRegression": 0.0
    },
    {
      "name": "neutral_a_shift",
      "direction": "absoluteLowerIsBetter",
      "allowedRegression": 0.0
    }
  ]
}
```

</details>

`0.0`은 권장값이 아닙니다. 측정 방식과 배포 정책에 맞춰 항목과 허용 오차를 정하세요.

## 매니페스트 규칙

- `schemaVersion`은 정확히 `1`이어야 합니다. 모르는 버전과 모르는 필드는 거부합니다.
- `corpusVersion`은 자료의 고정된 선택과 분할에 붙이는 이름입니다.
- `acceptedBaselineSHA256`은 승인된 `summary.json`의 정확한 바이트를 고정합니다.
- 케이스는 `calibration` 또는 `holdout`입니다. 이름은 겹치지 않아야 합니다.
- 자료는 비어 있으면 안 되고 두 역할 모두 케이스가 하나 이상 있어야 합니다.
- REAL과 TARGET 파일은 모두 `sha256:<소문자 16진수 64자>`로 고정합니다.
- 지표 이름은 겹치지 않아야 합니다.
- `allowedRegression`은 0 이상의 유한한 수여야 합니다. 불리언은 거부합니다.
- 방향은 `lowerIsBetter`, `higherIsBetter`, `absoluteLowerIsBetter`만 받습니다.

`absoluteLowerIsBetter`는 0에서의 거리를 비교합니다. 0이 검토를 마친 기준일 때만 쓰세요.

## 후보와 승인된 기준선 준비

```bash
python3 LUT_target/analyze_lut_target.py
```

배포를 승인하기 전에 후보의 `SOURCE/summary.json` 전체를 다음 승인 기준선 파일로 보관합니다. 후보가 검토를 통과하기 전에는 기존 승인 파일을 덮어쓰지 않습니다. 승인 파일의 정확한 SHA-256을 `acceptedBaselineSHA256`에 넣으세요.

후보와 기준선 요약에는 매니페스트의 케이스가 정확히 한 번씩 들어 있어야 합니다. 빠진 케이스, 중복, 처리 실패, 매니페스트 밖의 케이스는 입력 오류입니다.

`calibration` 케이스는 프로파일을 맞추는 데 쓸 수 있고 판정에는 반영하지 않습니다. `holdout` 케이스는 조정과 선택에서 제외합니다. 검증 수치는 케이스별로 비교하므로 평균이 좋아져도 한 장이 나빠진 것을 가릴 수 없습니다.

## 실행

<details open>
<summary>품질 검사 명령</summary>

```bash
python3 scripts/evaluate_profile_quality.py \
  --manifest LUT_target/quality/corpus-v1.json \
  --candidate-summary LUT_target/SOURCE/summary.json \
  --baseline-summary LUT_target/quality/accepted-summary-v1.json \
  --data-root LUT_target \
  --verify-files all \
  --report build/profile-quality-report.json
```

</details>

파일 검증 모드:

| 값 | 하는 일 | 배포 근거로 사용 |
|---|---|---|
| `all` | REAL/TARGET 파일마다 경로와 SHA-256 확인 | 가능 |
| `holdout` | 검증 파일만 확인 | 빠른 진단용 |
| `none` | 이미지 파일을 확인하지 않음 | 불가 |

기본값은 `all`입니다. 보고서에는 사용한 모드, 매니페스트와 요약 파일의 해시, 파일 검증 결과, 검증 세트의 케이스별 비교와 개수가 남습니다. 같은 JSON이 stdout과 `--report` 파일에 나가며 파일은 원자적으로 저장합니다.

종료 코드:

- `0`: 입력이 유효하고 허용 오차를 넘은 퇴보가 없음
- `1`: 입력은 유효하지만 검증 수치가 하나 이상 범위를 벗어남
- `2`: 스키마, 자료, 해시, 경로, 지표가 틀렸거나 없음

## 검사기 테스트

```bash
python3 -m unittest scripts/tests/test_evaluate_profile_quality.py
```

테스트는 임시 합성 파일로 정상 비교, 퇴보, 해시 변경, 잘못된 스키마와 숫자, 중복·누락·실패 케이스, 빈 자료를 확인합니다. 실제 스캐너 출력의 품질을 증명하지는 않습니다.
