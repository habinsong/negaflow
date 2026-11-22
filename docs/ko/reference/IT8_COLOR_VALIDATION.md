# IT8 색 검사

[문서 홈](../README.md)

색 정확도는 눈대중 대신 수치로 검증해야 하므로 IT8 이미지를 실물 타깃의 참조 파일과 연결해 패치마다 수치 결과를 기록합니다.

> [!IMPORTANT]
> 공개 IT8 자료로는 검사기와 색 계산의 퇴보를 확인할 수 있으며, 실제 스캐너나 컬러 네거티브 필름의 장치를 평가하려면 확인된 실물 타깃과 그 장치의 실측 데이터가 필요합니다.

## 검증 범위의 구분

| 이름 | 확인하는 것 | 범위 밖 |
|---|---|---|
| `algorithmRegression` | 파일 파싱과 ICC 변환, 패치 면적과 Lab, CIEDE2000 | 실제 스캐너의 정확도 |
| `deviceCharacterization` | 확인된 실물 타깃과 실제 장치의 패치 대조 결과 | 다른 타깃이나 장치의 정확도 |
| `syntheticModel` | 독립된 합성 모델의 수학적 왕복 | 실제 필름이나 장치의 정확도 |

`deviceCharacterization`에는 실물 타깃의 제조사와 재질, 일련번호와 배치가 모두 들어가야 하며 참조 파일 헤더와 완전히 일치할 때만 평가가 이루어집니다.

IT8.7/1과 ISO 12641-1 투과 타깃은 포지티브 투과 원본용이므로, 컬러 네거티브의 오렌지 마스크와 염료 상호작용, C-41 편차, HS와 SP 출력을 검증하려면 똑같은 컬러 네거티브를 두 경로로 처리한 대응 자료와 별도의 검증 세트를 갖춰야 합니다.

공개된 FADGI OpenDICE 이미지와 참조 파일을 패치 264개로 측정한 결과 중앙값 ΔE00은 9.8815, p95는 13.2745, 최댓값은 15.5996이었으며 독립된 LittleCMS 변환과 평가기의 차이는 Lab에서 최대 0.105였습니다. 다만 이 스캔은 실물 일련번호가 빠진 포지티브 IT8이고 네거티브의 카메라와 광원, 필름 실측치가 포함되어 있지 않아서 알고리즘 회귀 확인에만 활용됩니다.

공개 네거티브 데이터셋도 함께 검토했으나, FADGI 네거티브 자료는 색 패치 대신 농도만 기록되어 있고 BlueNeg는 복원된 참조치를 pseudo ground truth로 표기하며 2024년 ARRI AQUA 분광 연구는 개별 요청 시에만 자료를 제공하므로 현재 반전 파이프라인의 독립된 장면 색 참조치에서는 모두 빠집니다.

[공개된 Kodak ColorPlus 200 노출 시리즈](https://discuss.pixls.us/t/any-interest-in-a-film-negative-feature-in-rt/12569/262)(Sony ILCE-7 RAW 스캔 다섯 장, −1에서 +3 EV)도 살펴봤는데 차트가 Grey White Balance Colour Card여서 X-Rite 참조치는 적용하지 않았습니다.

표본 패치 영역 120곳 모두 디코딩된 카메라 RGB에서 0과 최대치 안쪽에 들어왔으나 이는 디코딩된 신호 범위만 보여 줄 뿐이고 차트와 스캔 환경의 실측 참조치가 빠져 있어 출력 색 치우침의 원인을 분리할 수 없으며 재배포 권리도 미확인 상태라 저장소 밖에 보관합니다.

[FADGI](https://www.digitizationguidelines.gov/guidelines/digitize-OpenDice.html) · [BlueNeg](https://huggingface.co/datasets/ttgroup/blueneg-release) · [Plutino 2024](https://doi.org/10.1002/col.22946)

## 공개 회귀 자료

FADGI/OpenDICE의 두 파일을 함께 불러옵니다.

- 안내: <https://www.digitizationguidelines.gov/guidelines/digitize-OpenDice.html>
- 이미지: <https://www.digitizationguidelines.gov/guidelines/OpenDICE/IT8-7.1.tif>
  - SHA-256: `c62ee73f26390a2ad90e7e28280cbd1efb4f18834425bb7112ff1f8016832ffd`
  - 크기: `6255 x 4170`
  - 형식: `Adobe RGB (1998)`가 내장된 16비트 RGB
- 참조 파일: <https://www.digitizationguidelines.gov/guidelines/OpenDICE/Profile_IT8-7.1.txt>
  - SHA-256: `19337b85f213eb4397e91c91298201f421ef3ca33b0ef6da3d752a0880491840`
  - 패치: `A1`부터 `L22`까지 Lab 수치 264개
  - 16번째 열: 농도

재배포 권리가 확인된 파일만 저장소에 포함하므로, 이 두 파일은 직접 내려받아 [예시 매니페스트](../../reference/IT8_FADGI_OPENDICE.example.json)에 경로를 연결해 `negaflow-mac/`에서 실행하세요(예시 분류는 `algorithmRegression`으로 고정되며 `deviceCharacterization`으로 바꾸면 검사기가 거부함).

```bash
swift run negaflow it8-bench ../docs/reference/IT8_FADGI_OPENDICE.example.json \
  --image /path/to/IT8-7.1.tif \
  --reference /path/to/Profile_IT8-7.1.txt \
  --out /path/to/it8-report.json
```

## 측정 규칙

- 이미지와 참조 파일, 선택한 ICC 가운데 어느 항목이라도 SHA-256이 매니페스트와 다르면 멈춥니다.
- 보고서 v2는 매니페스트 텍스트의 SHA-256도 기록합니다.
- `A01`과 `A1`은 똑같은 좌표를 읽고 보고서에는 원래 ID가 유지됩니다.
- 22 × 12 배열에서 패치마다 가운데 60%를 원본 해상도의 부동소수점으로 읽으며 행은 `A`–`L`, 열은 `1`–`22` 순서입니다.
- 내장 ICC를 따릅니다.
- 계산은 선형 sRGB D65에서 XYZ로, Bradford D50 적응을 거쳐 Lab D50/2°로 갑니다.
- 패치마다 면적, 픽셀 수, RGB 평균과 표준편차, 양 끝의 클리핑 비율과 비유한 항목 개수, 참조 Lab과 측정 Lab, L/a/b 차이와 CIEDE2000을 기록합니다.
- 중앙값과 p95, 최댓값은 관측 통계로만 남고 `qualityDecision`은 언제나 `notEvaluated`로 유지됩니다.
- 프로파일 조정에 사용한 타깃은 독립 검증 세트에서 분리합니다.

### 실물 타깃 세부 정보

실제 장치로 측정할 때는 작업자가 타깃 라벨에서 아래 항목을 읽어 기입합니다.

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

`MANUFACTURER`와 `MATERIAL`, `SERIAL`과 배치 헤더(`BATCH`, `BATCH_ID`, `PROD_DATE` 가운데 맞는 항목)가 참조 파일과 문자 단위로 완전히 일치해야 하며, 최상위 `targetID`는 `serial`과, `batchID`는 `batchValue`와 같아야 합니다.

이 기록은 작업자가 입력한 라벨 정보와 참조 파일 헤더의 일치 여부를 대조하며, 세부 정보가 빠졌을 때는 평가가 중단됩니다.

참조 파일에 광원이나 관측자 정보가 있으면 D50/2° 규약과 대조해 어긋나면 멈춥니다. 지금은 `measurement.renderingIntent`로 Core Image 변환을 직접 고정할 수 없어서 보고서에 `manifestDeclarationNotControlledByEvaluator`라고 적습니다.

## `PRINT` 출력

IT8.7/1은 입력 장치용입니다. 프린터 출력에는 프린터와 용지, 잉크나 화학 약품과 드라이버 또는 공정 조건의 조합을 실제로 측정해 만든 RGB 프린터 ICC를 갖춰야만 변환이 열립니다.

확인과 사용 순서:

1. ICC 크기와 `prtr` 장치 클래스, `RGB ` 데이터 공간과 Lab/XYZ PCS, `acsp` 서명을 대조합니다.
2. ColorSync가 양방향으로 변환할 수 있는지 살핍니다.
3. 선택할 때 프로파일 이름과 바이트, SHA-256을 잠급니다.
4. `MAIN` 작업 이미지와 페이지 레이아웃이 끝난 뒤 최종 출력에 한 번 반영합니다.
5. `rawScanTIFF`, `dng`, `-main-flat`은 작업 색 공간을 그대로 지킵니다.
6. 프로파일이 빠졌거나 잘못되었으면 임시 출력을 만들기 전에 즉시 오류로 멈춥니다.

Core Image와 ColorSync 경로의 렌더링 인텐트와 블랙 포인트 보정 세부 동작은 macOS 버전에 따라 달라질 수 있습니다.

## `MAIN` 합성 패치 회귀

`NegativeAutoBalanceTests`와 `shoulder-print-response-v4`입니다.

MAIN/CS는 스위치가 켜져 있든 꺼져 있든 v4 곡선을 따르며, 기존 v6 테스트는 자기 고정 기본 곡선만 별도로 검사합니다.

[네거티브 반전 응답](PRINT_RESPONSE.md)

## HS와 SP의 상대 스타일 회귀

`A1`부터 `L22`까지 Lab D50 패치 264개가 든 참조 파일을 SHA-256으로 잠근 뒤, 패치마다 합성 네거티브를 만들고 `MAIN`, `HS`, `SP` 경로를 각각 두 번 거칩니다.

```bash
swift run negaflow scanner-relative-it8-bench \
  /path/to/Profile_IT8-7.1.txt \
  --sha256 sha256:19337b85f213eb4397e91c91298201f421ef3ca33b0ef6da3d752a0880491840 \
  --out /path/to/scanner-relative-it8-report.json
```

보고서에는 패치별 RGB와 Lab, 참조치 대비 `DeltaE00`과 타깃 간 상대 `DeltaE00`, 클리핑과 비유한 수의 플래그가 들어갑니다. 무채색 램프의 단조성은 `A16...L16` 농도 열에서 확인합니다.

선형 sRGB로 바꿨을 때 0...1을 벗어나는 색은 합성 네거티브에서 표시 가능한 범위로 클램프되므로, 넓은 색역의 통계는 관측 수치로만 남깁니다.

검증 분류는 언제나 `syntheticModel`이고 판정은 `notEvaluated`입니다. 프로파일 매니페스트나 어느 파일의 SHA-256이 어긋나면 멈추며, 실제 장비의 정확도 검증에는 똑같은 실물 네거티브를 두 기계로 스캔한 자료와 별도의 검증 자료가 필요합니다.

Lab을 D50/2°로 해석하는 것은 이 벤치 자체의 규약이므로 `colorimetryInterpretationProvenance`에는 `benchmarkContractNotVerifiedFromReferenceHeader`가 들어갑니다.
