# 스캐너 프로파일 품질 검사

[문서 홈](../README.md)

`scripts/evaluate_profile_quality.py`(`negaflow-mac/`에서 실행)는 스캐너 프로파일을 바꾼 결과가 승인된 참조 요약보다 나빠졌는지 검사하며, `LUT_target/analyze_lut_target.py`가 만든 `SOURCE/summary.json` 두 개를 비교해 프로파일 조정에서 분리해 보관한 검증 케이스만 판정에 반영합니다.

어떤 수치가 내려가야 하고 올라가야 하는지, 또 얼마나 움직여도 되는지는 사람이 코퍼스 매니페스트에 직접 적습니다.

현재 저장소의 `LUT_target/REAL`과 `LUT_target/TARGET` 폴더는 비어 있으므로 합성 테스트는 검사기 코드의 동작만 살핍니다.

> [!WARNING]
> 스캐너 색 정확도 승인에는 고정된 REAL/TARGET 쌍과 별도 검증 케이스를 비롯해 사람이 정한 허용 오차가 모두 갖춰져야 합니다.

## 현재 프로파일의 적용 범위

`HS`와 `SP`는 기본적으로 각자의 고정 타깃 렌더링 표를 따릅니다. 여기에 `HS`나 `SP`에 대응하는 스캐너 프로파일(`scannerProfileID`)까지 함께 고르면 번들 `realOnly` 그룹에서 얻은 제한된 상대 차이가 함께 들어갑니다.

조건:

- 필름 종류와 필름 이름이 일치함
- 정리한 원본 롤 이름 집합이 일치함
- 이미지 수의 차이가 15% 이하입니다.

원본 프로파일에는 롤 이름 수준의 집계 통계만 들어 있으므로, 이 프로파일은 실제 장비를 복제하는 대신 상대적인 스타일 차이를 보태는 역할만 맡습니다.

적용 규칙:

- 두 그룹에서 방향이 일치하는 항목만 반영합니다.
- 흑백은 색 성분을 모두 버리고 상대 톤만 유지합니다.
- 대응하는 롤이 있는 슬라이드 프로파일에만 상대 보정이 들어갑니다.
- `HS` 타깃은 해상도에 따른 고정 휘도 샤프닝(`noritsuTexture`)을, 수동 `ScannerProfileGrade`는 `texture_sharpness_p95`에서 구한 제한된 언샤프 마스크를 반영하며, `SP`는 샤프닝을 생략하고 두 경로 모두 스캐너 그레인 합성을 배제합니다.
- 톤은 Rec.709 감마 밝기에 한 번 반영하고 Lab `a*`, `b*`는 그대로 유지합니다.
- 색 게인은 로그 영역에서 보간해서 양 끝 고정점과의 관계를 지킵니다.
- 어느 파일이나 매니페스트의 SHA-256이 어긋나면 프로파일 번들 전체가 거부됩니다.

## 제조사 자료로 확인되는 것

- [Fujifilm Frontier 570/SP-3000 안내서](https://www.photolabdigital.com/fuji_frontier570_en%5B1%5D.pdf)는 에어리어 CCD와 Hyper-tone, Hyper-sharpness처럼 장비가 제공하는 기능을 소개합니다.
- [Noritsu HS-1800 제품 정보](https://www.noritsu.eu/hardware/noritsu-film-scanner.html)는 지원 규격과 해상도, 처리량을 안내합니다.
- [Noritsu 특허 US 7,589,863](https://patents.google.com/patent/US7589863/en)은 작업자가 농도와 계조, 선명도를 고르는 미니랩의 흐름을 설명합니다.

이 자료들은 처리가 장면과 작업자에 따라 달라진다는 점을 보여 주므로, negaflow는 실측된 자료에서 확인된 수치만 프로파일에 넣습니다.

## 코퍼스 매니페스트 스키마 v1

매니페스트는 고정하려는 입력 자료 옆에 배치합니다. 예: `LUT_target/quality/corpus-v1.json`. 경로는 매니페스트 파일 기준이며 `--data-root`를 주면 그 경로가 기준입니다.

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

예시의 `0.0`은 자리표시자일 뿐이므로 측정 방식과 배포 정책에 따라 항목과 허용 오차를 직접 정하세요.

## 매니페스트 규칙

- `schemaVersion`은 정확히 `1`이어야 하며 모르는 버전과 필드는 거부합니다.
- `corpusVersion`은 자료의 고정된 선택과 분할에 붙이는 이름입니다.
- `acceptedBaselineSHA256`은 승인된 `summary.json`의 정확한 바이트를 잠급니다.
- 케이스는 `calibration` 또는 `holdout`이며 이름은 서로 모두 달라야 합니다.
- 두 역할 모두 최소 한 건 이상의 케이스를 포함해야 합니다.
- REAL과 TARGET 파일은 모두 `sha256:<소문자 16진수 64자>`로 잠급니다.
- 지표 이름은 서로 모두 다릅니다.
- `allowedRegression`은 0 이상의 유한한 수만 허용하며 불리언은 거부합니다.
- 방향은 `lowerIsBetter`, `higherIsBetter`, `absoluteLowerIsBetter`만 받습니다.

`absoluteLowerIsBetter`는 0에서의 거리를 비교하므로 0이 검토를 마친 목표치일 때만 지정하세요.

## 후보와 승인된 참조 요약 준비

```bash
python3 LUT_target/analyze_lut_target.py
```

후보가 검토를 통과하면 `SOURCE/summary.json`을 다음 승인 요약 파일로 보관하고 그 SHA-256을 `acceptedBaselineSHA256`에 기록합니다.

후보와 승인 요약에는 매니페스트의 케이스가 정확히 한 번씩 들어 있어야 하며 빠진 케이스나 중복, 처리 실패, 매니페스트 밖의 케이스는 모두 입력 오류로 걸러냅니다.

`calibration` 케이스는 프로파일을 조정하는 데만 활용하고 판정에서는 제외하는 반면 `holdout` 케이스는 조정과 선택에서 빼고 검증에만 들어갑니다. 검증 수치는 케이스별로 비교하므로 평균이 좋아져도 개별 사진이 나빠진 결과를 바로잡을 수 있습니다.

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

| 모드 | 동작 | 배포 근거로 사용 |
|---|---|---|
| `all` | REAL/TARGET 파일마다 경로와 SHA-256 확인 | 가능 |
| `holdout` | 검증 파일만 확인 | 빠른 진단용 |
| `none` | 이미지 파일 확인 생략 | 불가 |

기본 모드는 `all`입니다. 보고서에는 사용한 모드, 매니페스트와 요약 해시, 파일 검증 결과와 검증 세트의 케이스별 비교가 기록되며, 똑같은 JSON이 표준 출력과 `--report` 경로(임시 파일에 먼저 다 기록한 뒤 교체)로 나갑니다.

종료 코드:

- `0`: 입력이 유효하고 허용 오차를 넘은 퇴보가 없음
- `1`: 입력은 유효하지만 범위를 벗어난 검증 수치가 발견됨
- `2`: 스키마나 자료, 해시나 경로, 지표가 잘못됨

## 검사기 테스트

```bash
python3 -m unittest scripts/tests/test_evaluate_profile_quality.py
```

이 단위 테스트는 임시 합성 파일로 정상 비교와 퇴보, 해시 변경과 잘못된 스키마, 누락이나 실패 케이스와 빈 자료 처리를 검증합니다.
