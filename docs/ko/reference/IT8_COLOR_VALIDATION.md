# IT8 색 검사

[문서 홈](../README.md)

색 정확도는 눈으로만 보지 않고 측정해야 합니다. IT8 이미지를 실물 타깃의 기준 파일과 짝지어 패치마다 수치 결과를 기록합니다.

> [!IMPORTANT]
> 공개 IT8 자료로는 검사기와 색 계산의 퇴보를 확인할 수 있습니다. 실제 스캐너나 컬러 네거티브 필름의 정확도는 증명하지 못합니다. 장치를 판단하려면 확인된 실물 타깃과 그 장치의 실제 측정이 필요합니다.

## 증거의 종류

| 이름 | 확인하는 것 | 확인하지 못하는 것 |
|---|---|---|
| `algorithmRegression` | 파일 파싱, ICC 변환, 패치 면적, Lab, CIEDE2000 | 실제 스캐너의 정확도 |
| `deviceCharacterization` | 확인된 실물 타깃을 실제 장치로 측정한 결과 | 다른 타깃이나 장치의 정확도 |
| `syntheticModel` | 독립된 합성 모델의 수학적 왕복 | 실제 필름이나 장치의 정확도 |

`deviceCharacterization`에는 실물 타깃의 제조사, 재질, 일련번호, 배치가 필요합니다. 하나라도 기준 파일 헤더와 다르면 아무것도 평가하지 않습니다.

IT8.7/1과 ISO 12641-1 투과 타깃은 포지티브 투과 원본용입니다. 이 결과는 컬러 네거티브의 오렌지 마스크, 염료 상호작용, C-41 편차, HS·SP 출력의 정확도에 대해 아무것도 말해 주지 않습니다. 그런 주장에는 같은 컬러 네거티브를 두 경로로 돌린 짝 자료와 별도의 검증 세트가 필요합니다.

공개된 FADGI OpenDICE 이미지/기준 쌍을 패치 264개로 측정했습니다. 중앙값 ΔE00 9.8815, p95 13.2745, 최댓값 15.5996입니다. 독립된 LittleCMS 변환과 평가기의 차이는 Lab 기준 최대 0.105였습니다. 이 관측은 필름 정확도 관문을 통과하지 못합니다. 이 스캔은 포지티브 IT8이고 실물 일련번호를 확인하지 못했으며 네거티브의 카메라·광원·필름 측정이 붙어 있지 않기 때문입니다.

공개 네거티브 데이터셋도 살펴봤습니다. FADGI 네거티브 기준은 측정한 색 패치가 아니라 밀도만 담고 있습니다. BlueNeg는 복원한 기준을 pseudo ground truth라고 표시합니다. 2024년 ARRI AQUA 분광 측정 연구는 자료를 공개 다운로드가 아니라 요청 시 제공합니다. 어느 것도 현재의 반전을 위한 독립된 장면 색 기준을 주지 못합니다.

[공개된 Kodak ColorPlus 200 노출 시리즈](https://discuss.pixls.us/t/any-interest-in-a-film-negative-feature-in-rt/12569/262)(Sony ILCE-7 RAW 스캔 다섯 장, −1에서 +3 EV)도 검토했습니다. 차트가 Grey White Balance Colour Card여서 X-Rite 기준값은 쓰지 않았습니다. 표본 패치 영역 120곳 중 디코딩된 카메라 RGB에서 0이나 최대치에 닿은 곳은 없었습니다. 이는 디코딩된 신호의 확인이지 센서 모자이크의 직접 측정이나 색 정확도 결과가 아닙니다. 그 차트와 스캔 환경의 측정된 기준이 없으면 출력의 색 치우침이 입력 탓인지 앱 탓인지 가를 수 없습니다. 재배포 권리를 확인하지 못해 파일은 저장소 밖에 둡니다.

[FADGI](https://www.digitizationguidelines.gov/guidelines/digitize-OpenDice.html) · [BlueNeg](https://huggingface.co/datasets/ttgroup/blueneg-release) · [Plutino 2024](https://doi.org/10.1002/col.22946)

## 공개 회귀 자료

FADGI/OpenDICE의 두 파일을 한 쌍으로 씁니다.

- 안내: <https://www.digitizationguidelines.gov/guidelines/digitize-OpenDice.html>
- 이미지: <https://www.digitizationguidelines.gov/guidelines/OpenDICE/IT8-7.1.tif>
  - SHA-256: `c62ee73f26390a2ad90e7e28280cbd1efb4f18834425bb7112ff1f8016832ffd`
  - 크기: `6255 x 4170`
  - 형식: `Adobe RGB (1998)`가 내장된 16비트 RGB
- 기준 파일: <https://www.digitizationguidelines.gov/guidelines/OpenDICE/Profile_IT8-7.1.txt>
  - SHA-256: `19337b85f213eb4397e91c91298201f421ef3ca33b0ef6da3d752a0880491840`
  - 패치: `A1`부터 `L22`까지 Lab 값 264개
  - 16번째 열: 밀도

재배포 권리를 확인하지 못해 파일은 저장소와 앱에 넣지 않습니다. 직접 내려받아 [예시 매니페스트](../../reference/IT8_FADGI_OPENDICE.example.json)가 가리키게 하세요. 예시의 등급은 `algorithmRegression`이며 `deviceCharacterization`으로 바꾸면 검사기가 거부합니다. `negaflow-mac/`에서 실행합니다.

```bash
swift run negaflow it8-bench ../docs/reference/IT8_FADGI_OPENDICE.example.json \
  --image /path/to/IT8-7.1.tif \
  --reference /path/to/Profile_IT8-7.1.txt \
  --out /path/to/it8-report.json
```

## 측정 규칙

- 이미지, 기준 파일, 선택한 ICC 중 하나라도 SHA-256이 매니페스트와 다르면 멈춥니다.
- 보고서 v2는 매니페스트 텍스트의 SHA-256도 기록합니다.
- `A01`과 `A1`은 같은 좌표를 읽고 보고서에는 원래 ID가 남습니다.
- 22 × 12 격자에서 패치마다 가운데 60%를 원본 해상도의 부동소수점으로 읽으며 행은 `A`–`L`, 열은 `1`–`22` 순서입니다.
- 내장 ICC를 따릅니다.
- 계산은 선형 sRGB D65에서 XYZ로, Bradford D50 적응을 거쳐 Lab D50/2°로 갑니다.
- 패치마다 면적, 픽셀 수, RGB 평균과 표준편차, 양 끝의 클리핑 비율, 비유한 값 개수, 기준 Lab과 측정 Lab, L/a/b 차이, CIEDE2000을 기록합니다.
- 중앙값, p95, 최댓값은 관측이지 합격선이 아닙니다. 근거 없는 평균 기준을 만들지 않으며 `qualityDecision`은 `notEvaluated`로 남습니다.
- 프로파일을 맞추는 데 쓴 타깃은 독립 검증에 다시 쓰지 않습니다.

### 실물 타깃 세부 정보

실제 장치로 측정할 때는 작업자가 타깃 라벨에서 아래 항목을 읽어 적습니다.

<details>
<summary>측정 블록 예시</summary>

```json
{
  "measurement": {
    "samplerVersion": "center-mean-v1",
    "renderingIntent": "relativeColorimetric",
    "physicalTargetIdentity": {
      "manufacturer": "target label manufacturer",
      "material": "target label material",
      "serial": "target label serial",
      "batchMetadataKey": "PROD_DATE",
      "batchValue": "reference header production date"
    }
  }
}
```

</details>

`MANUFACTURER`, `MATERIAL`, `SERIAL`, 배치 헤더(`BATCH`, `BATCH_ID`, `PROD_DATE` 중 하나)가 기준 파일과 글자 하나까지 같아야 합니다. 최상위 `targetID`는 `serial`과, `batchID`는 `batchValue`와 같아야 합니다.

이 기록은 작업자가 적은 내용과 기준 파일이 일치한다는 것만 보여 줍니다. 이미지에서 라벨을 읽거나 작업자의 입력을 보증하지는 않습니다. 세부 정보가 없을 때 가장 가까운 날짜나 일반 기준 파일로 대신하지 않습니다.

기준 파일에 광원이나 관측자 정보가 있으면 D50/2° 규약과 맞춰 보고, 어긋나면 멈춥니다. 지금은 `measurement.renderingIntent`로 Core Image 변환을 직접 고정할 수 없어서 보고서에 `manifestDeclarationNotControlledByEvaluator`라고 적습니다.

## `PRINT` 출력

IT8.7/1은 입력 장치용입니다. 프린터 출력에는 프린터, 용지, 잉크 또는 화학 약품, 드라이버나 공정 조건의 조합을 실제로 측정해 만든 RGB 프린터 ICC가 필요합니다.

확인과 사용 순서:

1. ICC 크기, `prtr` 장치 클래스, `RGB ` 데이터 공간, Lab/XYZ PCS, `acsp` 서명을 확인합니다.
2. ColorSync가 양방향으로 변환할 수 있는지 확인합니다.
3. 선택할 때 프로파일 이름, 바이트, SHA-256을 고정합니다.
4. `MAIN` 작업 이미지와 페이지 레이아웃이 끝난 뒤 최종 출력에 한 번 적용합니다.
5. `rawScanTIFF`나 `-main-flat`에는 적용하지 않습니다.
6. 프로파일이 없거나 틀리면 임시 출력을 만들기 전에 실패합니다. sRGB로 대신하지 않습니다.

현재의 Core Image와 ColorSync 경로가 모든 macOS 버전에서 렌더링 인텐트와 블랙 포인트 보정을 비트 단위로 고정한다고 주장하지 않습니다.

## `MAIN` 합성 패치 회귀

`NegativeAutoBalanceTests`와 `shoulder-print-response-v4`입니다.

MAIN/CS는 스위치가 켜져 있든 꺼져 있든 v4 곡선을 씁니다. 남겨 둔 v6 테스트는 자기 고정 기본 곡선을 검사하며, 그 테스트의 프레임 변동 0은 자동 밸런스 ON의 결과가 아닙니다.

[네거티브 반전 응답](PRINT_RESPONSE.md)

## HS와 SP의 상대 스타일 회귀

`A1`부터 `L22`까지 Lab D50 패치 264개가 든 기준 파일을 SHA-256으로 고정합니다. 패치마다 합성 네거티브를 만들고 `MAIN`, `HS`, `SP` 경로를 각각 두 번 돌립니다.

```bash
swift run negaflow scanner-relative-it8-bench \
  /path/to/Profile_IT8-7.1.txt \
  --sha256 sha256:19337b85f213eb4397e91c91298201f421ef3ca33b0ef6da3d752a0880491840 \
  --out /path/to/scanner-relative-it8-report.json
```

보고서에는 패치별 RGB와 Lab, 기준에 대한 `DeltaE00`, 타깃 사이의 상대 `DeltaE00`, 클리핑과 비유한 값의 플래그가 들어갑니다. 중성 램프의 단조성은 `A16...L16` 밀도 열에서 읽습니다.

선형 sRGB로 바꿨을 때 0...1을 벗어나는 색은 합성 네거티브로 정확히 만들 수 없어 표시 가능한 범위로 제한합니다. 그래서 넓은 범위의 통계는 관측이지 합격선이 아닙니다.

증거 등급은 언제나 `syntheticModel`, 판정은 언제나 `notEvaluated`입니다. 프로파일 매니페스트나 어느 파일의 SHA-256이 어긋나면 멈춥니다. 실제 장비의 정확도에는 같은 실물 네거티브를 두 기계로 스캔한 자료와 별도의 검증 자료가 필요합니다.

D50/2°는 기준 파일 헤더에서 확인한 것이 아닙니다. Lab을 D50/2°로 읽는 이 벤치 자체의 규약이므로 `colorimetryInterpretationProvenance`는 `benchmarkContractNotVerifiedFromReferenceHeader`입니다.
