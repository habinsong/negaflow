# colorsync-icm-parity-v1 프로파일 합성 규칙

- 날짜: 2026-08-06
- 대상: `colorsync-icm-parity-v1` fixture
- 구현: `Tests/ChromabaseTests/SyntheticScannerICCProfile.swift`
- SHA-256: `8c2dce29801bda9b1f532b3236f61f91171267ad8bbc997d46fb662cf9125d02`
- 크기: 556 바이트

이 문서는 규범입니다. Windows 쪽은 여기 적힌 규칙만으로 **바이트 단위로 동일한** 프로파일을 다시
만들어야 합니다. 재현한 바이트의 SHA-256 이 위 값과 다르면 그 시점에서 비교를 멈추십시오. 두 CMS 가
서로 다른 프로파일을 읽고 있다면 출력 차이는 아무것도 증명하지 못합니다.

실제 스캐너 벤더 ICC 프로파일은 저장소에 넣지 않습니다. 권리 문제가 있고
`scripts/ci/verify-provenance.py` 게이트에 걸립니다. 그래서 코드로 합성합니다.

## 왜 matrix/TRC 인가

입력이 matrix/TRC 이면 A2B/B2A LUT 이 없으므로 CMS 가 쓸 수 있는 경로가 행렬 1개와 채널별 곡선
3개로 좁혀집니다. 두 CMS 가 다른 숫자를 낸다면 원인이 LUT 보간 방식이 아니라 그 좁은 수학
안에 있다는 뜻이고, 그러면 원인을 특정할 수 있습니다. 벤더 프로파일로 먼저 비교하면 차이가
나도 무엇 때문인지 분리되지 않습니다.

## 헤더 (128 바이트)

| 오프셋 | 크기 | 값 | 비고 |
|---:|---:|---|---|
| 0 | 4 | `0x0000022C` (556) | 전체 크기 |
| 4 | 4 | `0` | preferred CMM 없음 |
| 8 | 4 | `0x02100000` | 프로파일 버전 2.1.0 |
| 12 | 4 | `'scnr'` | device class = input |
| 16 | 4 | `'RGB '` | data colour space |
| 20 | 4 | `'XYZ '` | PCS |
| 24 | 12 | `2026,1,1,0,0,0` | uint16 6개. 고정값 — 실제 생성 시각을 쓰면 바이트가 매번 달라집니다 |
| 36 | 4 | `'acsp'` | 파일 시그니처 |
| 40 | 4 | `0` | primary platform 없음 |
| 44 | 4 | `0` | flags |
| 48 | 4 | `0` | device manufacturer |
| 52 | 4 | `0` | device model |
| 56 | 8 | `0` | device attributes |
| 64 | 4 | `1` | rendering intent = media-relative colorimetric |
| 68 | 12 | `0x0000F6D6, 0x00010000, 0x0000D32D` | PCS illuminant D50 |
| 80 | 4 | `0` | profile creator |
| 84 | 16 | `0` | profile ID 미계산 |
| 100 | 28 | `0` | reserved |

헤더 rendering intent 를 `1` 로 둔 이유는 하나입니다. Windows 는
`CreateMultiProfileTransform` 에 `INTENT_RELATIVE_COLORIMETRIC` 을 명시로 넘기지만 macOS 경로는
intent 를 지정하지 않습니다(§ 조사 문서 참조). CMS 가 지정 없을 때 헤더 값으로 되돌아간다면
양쪽이 같은 intent 에 착지합니다.

## 태그 테이블

태그 9개를 아래 **순서 그대로** 씁니다. 테이블은 오프셋 128 에서 시작하고 `count`(4바이트) 뒤에
`signature/offset/size` 12바이트 항목이 이어집니다. 테이블 크기는 `4 + 9*12 = 112`, 첫 태그
데이터는 `align4(128+112) = 240` 에서 시작합니다.

배치 규칙은 하나뿐입니다. **테이블 순서대로, 각 블록을 4바이트 정렬로 이어 붙이고, 어떤 두 태그도
데이터를 공유하지 않는다.** 실제 프로파일은 rTRC/gTRC/bTRC 가 같은 오프셋을 가리키는 경우가 많지만
여기서는 공유하지 않습니다. 공유 여부가 갈리면 바이트가 갈립니다.

| 태그 | 오프셋 | 크기 | 타입 |
|---|---:|---:|---|
| `desc` | 240 | 124 | textDescriptionType |
| `wtpt` | 364 | 20 | XYZType |
| `rXYZ` | 384 | 20 | XYZType |
| `gXYZ` | 404 | 20 | XYZType |
| `bXYZ` | 424 | 20 | XYZType |
| `rTRC` | 444 | 14 | curveType (패딩 포함 16) |
| `gTRC` | 460 | 14 | curveType (패딩 포함 16) |
| `bTRC` | 476 | 14 | curveType (패딩 포함 16) |
| `cprt` | 492 | 63 | textType (패딩 포함 64) |

`size` 필드에는 패딩을 뺀 실제 데이터 크기를 적고, 다음 태그 오프셋을 계산할 때만 4바이트로
올림합니다. 패딩 바이트는 0 입니다.

## 프라이머리와 화이트포인트

sRGB 프라이머리(IEC 61966-2-1)를 Bradford 로 D65 → ICC PCS D50 적응시킨 값입니다. 유도 과정은
아래와 같고, 결과는 표준 sRGB ICC 프로파일의 열과 일치합니다.

1. 프라이머리 xy: R(0.64, 0.33), G(0.30, 0.60), B(0.15, 0.06), 백색 D65(0.3127, 0.3290)
2. xy → XYZ 로 RGB→XYZ 행렬을 세우고 D65 백색으로 스케일
3. Bradford 행렬로 D65 → D50(0.9642, 1.0, 0.8249) 적응
4. s15Fixed16Number 로 인코딩: `round(v * 65536)`

**재현할 때는 3단계까지 다시 계산하지 말고 아래 정수를 그대로 쓰십시오.** 부동소수 연산 순서가
다르면 마지막 자리에서 1이 어긋나고 SHA-256 이 달라집니다.

| 태그 | X | Y | Z |
|---|---|---|---|
| `rXYZ` | `0x00006FA0` | `0x000038F5` | `0x00000390` |
| `gXYZ` | `0x00006297` | `0x0000B787` | `0x000018D9` |
| `bXYZ` | `0x0000249F` | `0x00000F84` | `0x0000B6C3` |
| `wtpt` | `0x0000F6D6` | `0x00010000` | `0x0000D32D` |

`chad`(chromaticAdaptationTag)는 넣지 않습니다. 행렬이 이미 D50 으로 적응돼 있고 `wtpt` 도 D50
이므로 추가 적응이 필요 없습니다. `chad` 를 넣으면 CMS 마다 이중 적용 여부가 갈릴 수 있어 비교
대상이 흐려집니다.

## TRC

세 채널 모두 `curv` 타입, `count = 1` 입니다. ICC 규격에서 `count = 1` 은 "감마 하나"를 뜻하고
값은 u8Fixed8Number 입니다.

- 인코딩 값: `563` (`0x0233`)
- **실제 감마: 563 / 256 = 2.19921875**

2.2 가 아닙니다. u8Fixed8 은 1/256 단위라 2.2 를 정확히 표현하지 못합니다. 비교 기준선을 세울 때
반드시 `2.19921875` 를 쓰십시오. `2.2` 를 쓰면 중간톤에서 약 1e-4 크기의 가짜 차이가 생깁니다.

## 문자열 태그

- `desc` = `Negaflow Synthetic Scanner RGB v1` (33자 + NUL = 34바이트)
- `cprt` = `Negaflow synthetic parity fixture. No rights asserted.` (54자 + NUL = 55바이트)

`desc` 는 ICC v2 textDescriptionType 이라 ASCII 블록 뒤에 빈 Unicode 블록(언어코드 4 + 개수 4)과
빈 ScriptCode 블록(코드 2 + 개수 1 + 67바이트 버퍼)이 항상 따라옵니다. 이 67바이트는 비어 있어도
생략할 수 없습니다.

## 입력 양자화

패치 값은 0.0~1.0 float 이지만 두 CMS 모두 16비트 정수를 받습니다. 양쪽이 같은 정수를 넣어야
합니다.

```
sample_u16 = round(value * 65535.0)
```

JSON 의 `patches[].in` 에는 이미 양자화를 거친 값(`round(v * 65535) / 65535`)이 들어 있습니다.
Windows 는 `in` 값을 다시 양자화하지 말고 `round(in * 65535)` 로 정수만 복원하십시오.
