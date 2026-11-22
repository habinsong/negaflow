# 필름 프로파일

[문서 홈](../README.md)

번들 스캐너 프로파일은 프로젝트 작성자가 직접 촬영해 랩 스캐너로 읽은 필름 프레임을 분석해 JSON으로 정리한 자료입니다.

| 항목 | 현재 수량 |
|---|---:|
| 필름 종류 기본값 | 27 |
| 스타일 룩 | 6 |
| 스캐너 프로파일 | 15 |
| 롤 관측 | 25 |
| 프레임 | 928 |
| 검증 상태 | 모두 `realOnly` |

> [!NOTE]
> `928`은 작성자가 촬영하고 랩 스캐너로 디지털화한 필름 컷 수를 가리킵니다.

## 서로 다른 세 자료

| 자료 | 형식(macOS 번들) | 용도 | 개수 |
|---|---|---|---:|
| 필름 종류 | Swift | Dmin/Dmax와 필름 종류 기본값 | 27 |
| 룩 프리셋 | JSON | 사용자가 고르는 스타일 룩 | 6 |
| 스캐너 프로파일 | JSON | 실제 스캔에서 본 상대적인 톤과 색 통계 | 15 |

Windows에서는 똑같은 필름 종류 27개, 룩 프리셋 6개, 스캐너 프로파일 15개가 C++와 C# 안에 컴파일되어 들어갑니다. 필름 이름 27개는 색 정확도 프로파일과 별개이고 룩 6개 역시 스캐너 프로파일과 역할이 다르므로, 아래부터는 세 번째 자료인 스캐너 프로파일만 설명합니다.

## 지금 번들에 있는 것

`Sources/Chromabase/ScannerProfiles/`에 15개가 있습니다.

<details>
<summary>15개 프로파일 전체</summary>

| 스캐너 | 필름 종류 | 필름 | 롤 관측 | 프레임 | 상태 |
|---|---|---|---:|---:|---|
| NORITSU | 컬러 네거티브 | Fuji C200 | 3 | 111 | `realOnly` |
| NORITSU | 컬러 네거티브 | Kodak Ektar 100 | 2 | 76 | `realOnly` |
| NORITSU | 컬러 네거티브 | Kodak Portra 160 | 1 | 37 | `realOnly` |
| NORITSU | 컬러 네거티브 | Kodak Portra 400 | 2 | 75 | `realOnly` |
| NORITSU | 컬러 네거티브 | Kodak Portra 800 | 1 | 38 | `realOnly` |
| NORITSU | 컬러 네거티브 | Kodak Pro Image 100 | 1 | 37 | `realOnly` |
| NORITSU | 컬러 네거티브 | Kodak UltraMax 400 | 1 | 38 | `realOnly` |
| NORITSU | 컬러 네거티브 | Kodak Vision3 250D | 1 | 37 | `realOnly` |
| NORITSU | 컬러 네거티브 | Kodak Vision3 50D | 1 | 38 | `realOnly` |
| NORITSU | 컬러 슬라이드 | Kodak Ektachrome 100 | 1 | 38 | `realOnly` |
| NORITSU | 컬러 슬라이드 | Kodak Ektachrome 100D | 5 | 181 | `realOnly` |
| SP-3000 | 컬러 네거티브 | Kodak Ektar 100 | 2 | 76 | `realOnly` |
| SP-3000 | 컬러 네거티브 | Kodak Portra 160 | 1 | 38 | `realOnly` |
| SP-3000 | 컬러 네거티브 | Kodak Vision3 250D | 2 | 71 | `realOnly` |
| SP-3000 | 컬러 슬라이드 | Kodak Ektachrome 100D | 1 | 37 | `realOnly` |
| **합계** |  |  | **25** | **928** | **15 `realOnly`** |

</details>

여기서 25는 프로파일 그룹별 롤 관측 횟수를 합산한 수치이고 928은 분석에 들어간 프레임 수입니다.

## 만드는 방법

1. 촬영과 분류: 원본을 스캐너, 필름 종류, 필름 이름, 롤 이름으로 나누고 분석 전에 회전과 파일 디코딩을 점검하여 비어 있거나 깨진 파일은 걸러냅니다.
2. 프레임 측정: 프레임마다 밝기 백분위와 양 끝의 클리핑, 암부와 중간톤, 명부의 채널 관계, 채도와 색상 분포, 저채도 픽셀의 Lab 무채색축, 그래디언트와 선명도, 그레인 지표를 계산합니다. 이 기록은 개별 장면의 관측 결과로만 보며 한 프레임의 노출이나 피사체 특성을 스캐너의 고정된 성질로 일반화하는 오류를 막습니다.
3. 장면 분류: 밝기와 대비, 채도와 색상 구간별로 장면을 나누고 특정 유형의 장면이 프로파일을 치우치게 만들지 않도록 구간마다 표본 수와 분포를 함께 기록합니다.
4. 대표 프레임: 사람이 원본을 다시 대조할 수 있도록 대비나 선명도, 그레인 지표가 가장 높은 프레임과 밝기, 채도 구간을 대표하는 프레임을 따로 추립니다.
5. 롤과 그룹 집계: `scripts/compile_scanner_profiles.py`가 롤별 자료를 필름과 스캐너 조합별로 집계하며 표본이 없는 빈 구간은 0으로 채우는 대신 비워 놓고 실제 표본이 있는 유한한 값만 반영합니다.
6. JSON과 해시: 최종 파일에는 스키마와 ID, 원본 수와 경로, 집계 통계, 검증 상태, `profileHash`를 기록하며 검사기가 필수 필드와 표본 수, 수치의 유한성과 ID, 파일 이름의 일치 여부, 해시를 살핍니다.

## JSON의 모양

<details>
<summary>프로파일 JSON 예시</summary>

```json
{
  "schemaVersion": 2,
  "id": "noritsu__color-nega__kodak-portra-400",
  "displayName": "NORITSU · color nega · Kodak Portra 400",
  "scanner": "NORITSU",
  "kind": "color nega",
  "filmKey": "kodak portra 400",
  "validationStatus": "realOnly",
  "rollCount": 2,
  "imageCount": 75,
  "singleRollLimited": false,
  "sourceProfiles": [],
  "tone": {},
  "color": {},
  "neutralAxis": {},
  "neutralAxisBins": [],
  "hueResponse": [],
  "texture": {},
  "sceneBuckets": [],
  "coverageCandidates": [],
  "profileHash": "sha256:..."
}
```

</details>

## 주요 항목

| 항목 | 내용 | 주의할 점 |
|---|---|---|
| `tone` | 밝기 분포와 양 끝의 클리핑 | 개별 프레임의 노출과 기계 고유의 응답을 구분해 해석함 |
| `color` | 암부, 중간톤, 명부의 채널과 채도 | 절대 색 행렬 대신 관측된 상대 분포로만 해석함 |
| `neutralAxis` | 저채도 픽셀의 Lab `a*`, `b*` | 무채색 물체가 없는 장면을 구분하려고 표본 수를 함께 기록함 |
| `hueResponse` | 색상 구간별 채도 변화와 색상 회전 | 두 기계의 자료가 맞을 때만 상대 비교 |
| `texture` | 그래디언트, 선명도, 그레인 지표 | `HS`/`SP`(`ScannerTargetGrade`)에서는 참조에서 제외하고, 단독 `ScannerProfileGrade`에서만 `texture_sharpness_p95` 기반의 제한된 언샵 마스크를 계산함(합성 그레인 제외) |
| `sceneBuckets` | 장면별 통계와 대표 프레임 | 사람이 원본을 다시 따라갈 수 있게 함 |

`ScannerTargetGrade`에서 `HS`는 `texture` 통계와 무관하게 해상도에 비례하는 고정 휘도 선명화 패스를 실행하고 나머지 타깃(`SP`, `F135`, `HR`, `MAIN`, `PRINT`, `EXPIRED`, `CS`)은 타깃 선명화 단계를 생략합니다.

반면 스캐너 타깃 밖에서 개별 스캐너 프로파일을 수동으로 반영할 때(`ScannerProfileGrade`)는 합성 그레인 없이 `NaturalToneSpline` 기반의 제한된 톤과 색 보정, `texture_sharpness_p95` 기반의 제한된 언샵 마스크만 들어갑니다.

## 검증 상태

| 상태 | 의미 | 허용 범위 |
|---|---|---|
| `draft` | 자료나 스키마가 끝나지 않음 | 번들이나 자동 반영에서 제외함 |
| `realOnly` | 실제 스캔은 있으나 별도 기준 자료가 없음 | 수동 선택만, 정확도 주장 없음 |
| `pairedSmoke` | 대응 자료가 처리 경로만 확인함 | 품질 검증 근거로 삼지 않음 |
| `pairedValidated` | 보정과 검증 자료, 회귀 검사를 통과함 | 정책이 허용하면 자동 선택 가능 |

현재 번들에 들어간 15개는 모두 `realOnly` 상태이므로 실제 스캔을 관측해 만들었다는 출처만 확인하며 실제 스캐너 출력과의 일치 여부는 별도 검증 대상으로 보류합니다.

기계의 정확도를 주장하려면 아래 자료가 뒷받침되어야 합니다.

- 똑같은 실물 프레임임을 확인하는 ID
- 보정과 분리해 둔 검증 자료
- 기준 이미지를 만든 조건
- 스캐너 설정과 작업자의 선택
- 타깃의 배치, 조명, 측정 방법
- 이미지별 합격 기준

## 앱의 활용 방식

### 수동 선택

현재 번들은 모두 `realOnly` 상태여서 모델명이나 파일 메타데이터로 프로파일을 자동 연결하는 대신 사용자가 `HS`나 `SP` 타깃과 프로파일을 직접 고르며, 자동 매칭은 향후 `pairedValidated` 단계를 통과한 프로파일에만 허용됩니다.

### 두 스캐너의 상대 차이

스캐너 타깃 밖에서 `ScannerProfileGrade`로 개별 프로파일을 수동 적용할 때는 `NaturalToneSpline`으로 제한된 톤과 색을 계산하는 반면, `HS`와 `SP`(`ScannerTargetGrade`)에서는 개별 프로파일의 절대 통계를 배제하고 두 기계에서 대응하는 그룹의 상대 차이만 제한적으로 따릅니다.

- 정리한 롤 이름 집합이 서로 일치해야 합니다.
- 이미지 수의 편차는 15% 이내로 제한됩니다.
- 색상 구간은 양쪽 모두 표본 수가 최소 기준을 넘깁니다.
- 보정 방향이 반전되는 구간은 걸러냅니다.
- 양쪽 게인의 상대 비율은 로그 영역에서 구합니다.
- 톤은 Rec.709 감마 밝기에 한 번 입히고 Lab 색 성분은 그대로 지킵니다.

원본 프로파일에는 프레임별 SHA-256이 들어가지 않으므로 롤 이름이 일치하더라도 개별 프레임 단위의 일대일 대응이 아닌 롤 단위의 통계 비교로만 봅니다.

### 흑백과 포지티브

흑백에서는 색 성분을 버리고 상대 톤만 반영하며, 포지티브에서는 한 롤의 절대 밝기를 다른 사진에 옮기는 대신 네 스캐너 타깃(`HS`, `SP`, `F135`, `HR`)의 기본 스타일을 절반 강도로 적용하므로 `MAIN`과는 다른 톤이 만들어집니다.

### 질감

똑같은 실물 프레임을 양쪽 기계로 스캔한 대응 자료가 없는 한 `texture` 통계에는 촬영 초점과 피사체, JPEG 압축과 랩 작업자의 설정이 함께 섞여 있으므로 `HS`와 `SP`(`ScannerTargetGrade`)는 이를 기계 고유의 선명화나 그레인 강도로 삼는 대신 참조에서 배제합니다.

다만 스캐너 타깃 밖에서 개별 프로파일을 수동으로 적용할 때(`ScannerProfileGrade`)는 합성 그레인 없이 `texture_sharpness_p95`에서 제한된 언샵 마스크만 들어갑니다.

## 파일 무결성

`ScannerProfileRegistry`는 실행 중에 15개 프로파일 전체를 일괄 검증해 엽니다.

1. 매니페스트 스키마(`schemaVersion == 2`), 프로파일 개수, 고유 ID를 대조합니다.
2. 모든 파일의 존재 여부와 원본 파일 SHA-256을 점검하고 읽기 전후의 파일 상태가 일치하는지 살핍니다.
3. 각 JSON을 디코딩해 `schemaVersion == 2`, ID, 매니페스트에 적힌 `profileHash`가 맞는지 검증합니다.
4. 어느 한 항목이라도 어긋나면 번들 전체를 거부합니다.
5. 모두 일치한 읽기 전용 스냅샷만 메모리에 캐시합니다.

JSON 내용에서 `profileHash`를 다시 계산하고 개수, 검증 상태, 유한성을 확인하는 작업은 오프라인 검사 스크립트인 `negaflow-mac/scripts/validate_scanner_profiles.py`가 맡습니다.

내보내기 메타데이터에는 실제 적용한 프로파일 ID와 SHA-256을 함께 기록합니다.

## 확인 명령

아래 세 명령은 모두 `negaflow-mac/`에서 실행하며 순서대로 프로파일 규약 검사와 프로파일 재생성, REAL/TARGET 품질 검사를 맡습니다.

```bash
python3 scripts/validate_scanner_profiles.py \
  --mode profile-contract \
  --profiles Sources/Chromabase/ScannerProfiles
```

```bash
python3 scripts/compile_scanner_profiles.py \
  --source LUT_target/SOURCE \
  --out LUT_target/PROFILES \
  --resource-out Sources/Chromabase/ScannerProfiles
```

```bash
python3 scripts/evaluate_profile_quality.py \
  --manifest LUT_target/quality/corpus-v1.json \
  --candidate-summary LUT_target/SOURCE/summary.json \
  --baseline-summary LUT_target/quality/accepted-summary-v1.json \
  --data-root LUT_target \
  --verify-files all \
  --report build/profile-quality-report.json
```

본체 저장소는 아직 배포 기준을 통과한 REAL/TARGET 매니페스트나 승인된 참조치를 포함하지 않으므로, 현재의 합성 테스트는 프로파일 정확도를 보증하는 대신 검사 스크립트의 오류 검출 동작만 확인해 줍니다.

## 참고 자료

- [Kodak Professional Portra 400 technical data](https://www.kodakprofessional.com/sites/default/files/wysiwyg/pro/resources/e4050_portra_400.pdf)
- [darktable negadoctor](https://docs.darktable.org/usermanual/4.6/en/module-reference/processing-modules/negadoctor/)

위 문헌은 필름 베이스, 장면 톤, 기계 스타일을 서로 분리해야 하는 이론적 배경으로만 참고했으며 번들 JSON의 실제 값은 모두 이 프로젝트용으로 직접 촬영한 스캔 자료와 저장소의 분석 스크립트에서 계산했습니다.

## 코드와 관련 문서

- `Sources/Chromabase/ScannerProfiles/`
- `Sources/Chromabase/Profiles/ScannerProfile/`
- `Sources/Chromabase/Profiles/ScannerTargetGrade/`
- `scripts/compile_scanner_profiles.py`
- `scripts/validate_scanner_profiles.py`
- `scripts/evaluate_profile_quality.py`
- [스캐너 프로파일 품질 검사](../reference/PROFILE_QUALITY_GATE.md)
- [IT8 색 검사](../reference/IT8_COLOR_VALIDATION.md)
- [Chroma Engine](CHROMA_ENGINE.md)
