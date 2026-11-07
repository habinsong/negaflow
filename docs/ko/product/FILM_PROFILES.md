# 필름 프로파일

[문서 홈](../README.md)

번들 스캐너 프로파일은 프로젝트 작성자가 촬영해 랩 스캐너로 스캔한 필름 프레임을 분석해 JSON으로 만든 것입니다.

| 항목 | 현재 값 |
|---|---:|
| 필름 종류 기본값 | 27 |
| 창작 룩 | 6 |
| 스캐너 프로파일 | 15 |
| 롤 관측 | 25 |
| 프레임 | 928 |
| 검증 상태 | 모두 `realOnly` |

> [!NOTE]
> `928`은 프로젝트 작성자가 촬영해 랩 스캐너로 스캔한 필름 컷의 수입니다.

## 서로 다른 세 자료

| 자료 | 형식 | 용도 | 개수 |
|---|---|---|---:|
| 필름 종류 | Swift | Dmin/Dmax와 필름 종류 기본값 | 27 |
| 룩 프리셋 | JSON | 사용자가 고르는 창작 룩 | 6 |
| 스캐너 프로파일 | JSON | 실제 스캔에서 본 상대적인 톤과 색 통계 | 15 |

필름 이름 27개가 색 정확도 프로파일 27개는 아니고, 룩 6개는 스캐너 프로파일과 별개입니다. 이하는 세 번째 자료만 다룹니다.

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

25는 프로파일 그룹별 롤 관측을 더한 값이어서 고유한 롤의 수가 아닙니다. 928은 프레임 수입니다.

## 만드는 방법

1. 촬영과 분류. 원본을 스캐너, 필름 종류, 필름 이름, 롤 이름으로 나눕니다. 분석 전에 회전과 파일 해석을 확인하며 비어 있거나 읽을 수 없는 파일은 세지 않습니다.
2. 프레임 측정. 프레임마다 밝기 백분위와 양 끝의 클리핑, 어두운 곳·중간·밝은 곳의 채널 관계, 채도와 색상 분포, 저채도 픽셀의 Lab 중립축, 그래디언트·선명도·그레인 기준값을 잽니다. 이것은 장면의 관측입니다. 한 프레임의 노출이나 피사체를 스캐너의 고정된 성질로 선언하지 않습니다.
3. 장면 묶기. 밝기, 대비, 채도, 색상 범위로 장면을 묶습니다. 한 종류의 장면이 프로파일을 지배하지 않도록 묶음마다 개수와 분포를 기록합니다.
4. 대표 프레임. 사람이 원본으로 돌아갈 수 있도록 대비가 가장 높은 프레임, 가장 선명한 프레임, 그레인 기준값이 가장 높은 프레임, 밝기와 채도 범위를 대표하는 프레임을 따로 기록합니다.
5. 롤·그룹 집계. `scripts/compile_scanner_profiles.py`가 롤별 자료를 필름·스캐너 그룹으로 묶습니다. 빈 구간을 값이 0인 관측으로 표현하지 않으며 모든 값은 유한해야 하고 표본 수는 실제여야 합니다.
6. JSON과 해시. 최종 파일에는 스키마, ID, 원본 개수, 원본 경로, 집계 통계, 검증 상태, `profileHash`가 들어갑니다. 검사기는 필드, 개수, 유한성, ID와 파일 이름의 일치, 원본 개수, 해시를 확인합니다.

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
| `tone` | 밝기 분포와 양 끝의 클리핑 | 한 프레임의 노출은 기계의 성질이 아님 |
| `color` | 어두운 곳·중간·밝은 곳의 채널과 채도 | 관측한 분포이지 절대 색 행렬이 아님 |
| `neutralAxis` | 저채도 픽셀의 Lab `a*`, `b*` | 중립 물체가 없는 장면이 있어 표본 수를 함께 둠 |
| `hueResponse` | 색상 구간별 채도 변화와 색상 회전 | 두 기계의 자료가 맞을 때만 상대 비교 |
| `texture` | 그래디언트, 선명도, 그레인 기준값 | 기계의 선명도 값으로 직접 쓰지 않음 |
| `sceneBuckets` | 장면별 통계와 대표 프레임 | 사람이 원본을 다시 따라갈 수 있게 함 |

`HS` 타깃의 밝기 채널 선명화는 `texture`에서 잰 기계 상수가 아니며 새 그레인도 합성하지 않습니다. `SP`, `MAIN`, `PRINT`에는 그 선명화가 없습니다.

## 증거 상태

| 상태 | 뜻 | 쓸 수 있는 곳 |
|---|---|---|
| `draft` | 자료나 스키마가 끝나지 않음 | 번들이나 자동 사용에는 쓰지 않음 |
| `realOnly` | 실제 스캔은 있으나 별도 기준 자료가 없음 | 수동 선택만, 정확도 주장 없음 |
| `pairedSmoke` | 짝 자료가 처리 경로만 확인함 | 품질 증거로 쓸 수 없음 |
| `pairedValidated` | 보정·검증 자료와 회귀 검사를 통과함 | 정책이 허용하면 자동 선택 가능 |

지금은 15개 모두 `realOnly`입니다. 실제 자료를 관측해서 만들었다는 점은 확인되지만 기계와 같은 결과를 낸다는 점은 확인되지 않습니다.

기계의 정확도를 주장하려면 자료가 더 필요합니다.

- 같은 실물 프레임임을 확인하는 ID
- 보정과 분리해 둔 검증 자료
- 기준 이미지를 만든 조건
- 스캐너 설정과 작업자의 선택
- 타깃의 배치, 조명, 측정 방법
- 이미지별 합격 기준

## 앱이 쓰는 방식

### 수동 선택

모델명이나 파일 정보로 자동 선택되는 것은 없습니다. `HS`나 `SP` 타깃과 프로파일을 직접 고릅니다. 자동 매칭은 `pairedValidated`에만 허용되므로 현재 번들에는 적용되지 않습니다.

### 두 스캐너의 상대 차이

절대적인 장면 통계는 그대로 쓰지 않습니다. 두 기계에서 짝이 맞는 그룹 사이의 차이만 제한적으로 씁니다.

- 정리한 롤 이름 집합이 같아야 합니다.
- 이미지 수의 차이가 15% 이하여야 합니다.
- 색상 구간은 양쪽 모두 표본 수가 기준을 넘어야 합니다.
- 방향이 뒤집히는 값은 적용하지 않습니다.
- 반대쪽 게인 사이의 값은 로그 영역에서 계산합니다.
- 톤은 Rec.709 감마 밝기에 한 번 적용하고 Lab 색 성분은 보존합니다.

원본 프로파일에는 프레임별 SHA-256이 없고, 롤 이름이 같다고 같은 프레임을 짝지었다는 증거가 되지는 않습니다.

### 흑백과 포지티브

흑백은 색 성분을 버리고 상대 톤만 씁니다. 포지티브는 한 롤의 절대 밝기를 다른 사진에 옮기지 않습니다. 다만 `HS`와 `SP`의 기본 스타일은 포지티브에 절반 강도로 적용되므로 결과가 항상 `MAIN`과 같지는 않습니다.

### 질감

같은 프레임에서 짝을 이룬 자료가 없으면 `texture`를 기계 고유의 선명화나 그레인 값으로 쓰지 않습니다. 그 수치에는 초점, 피사체, JPEG 처리, 랩 작업자의 선택이 모두 섞여 있습니다.

## 파일 무결성

`ScannerProfileRegistry`는 15개 중 일부만 여는 일이 없습니다.

1. 매니페스트 스키마를 읽습니다.
2. 모든 파일이 있는지 확인하고 SHA-256을 검사합니다.
3. 각 JSON의 `profileHash`를 다시 계산합니다.
4. ID, 파일 이름, 스키마, 상태, 개수, 유한성을 검사합니다.
5. 하나라도 어긋나면 번들 전체를 거부합니다.
6. 모두 일치한 읽기 전용 스냅샷만 캐시합니다.

내보내기 기록에는 실제로 쓴 프로파일 ID와 SHA-256이 남습니다.

## 확인 명령

`negaflow-mac/`에서 실행합니다. 첫째는 프로파일 규약 검사, 둘째는 프로파일 재생성, 셋째는 REAL/TARGET 품질 검사입니다.

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

이 저장소에는 배포 주장을 뒷받침할 REAL/TARGET 매니페스트나 승인된 기준선이 없습니다. 합성 테스트는 검사 코드의 실패 조건만 확인하며 프로파일의 정확도를 증명하지 않습니다.

## 참고 자료

- [Kodak Professional Portra 400 technical data](https://www.kodakprofessional.com/sites/default/files/wysiwyg/pro/resources/e4050_portra_400.pdf)
- [darktable negadoctor](https://docs.darktable.org/usermanual/4.6/en/module-reference/processing-modules/negadoctor/)

프로파일 수치는 이 자료들에서 가져오지 않았습니다. 필름 베이스, 장면 톤, 기계 스타일을 따로 다뤄야 하는 이유를 배경으로 읽었을 뿐입니다. JSON 값은 이 프로젝트용으로 촬영한 자료와 저장소의 분석 코드에서 나옵니다.

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
