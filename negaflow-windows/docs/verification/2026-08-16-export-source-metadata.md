# 원본 메타데이터 복사 — 정책 네 가지 실측

기준일: 2026-08-16

## 무엇이 비어 있었는가

`ExportMetadataPolicy` 는 네 값을 **받기만** 했습니다. `remove_location` 과 `all` 은 이름이
원본 메타데이터를 싣겠다는 뜻인데, 구현은 원본 파일을 열지도 않았습니다. 사용자가 "원본
그대로" 를 골라도 앱이 아는 값(장비·소프트웨어·날짜·필름)만 실렸습니다.

## macOS 의 규칙

`ExportSourceMetadata`(`negaflow-mac/Sources/Chromabase/Export/ExportMetadataPolicy.swift`)
가 원본의 TIFF·EXIF·IPTC·GPS 사전을 읽고 정책으로 거릅니다.

| 정책 | TIFF | EXIF | IPTC | GPS |
| --- | --- | --- | --- | --- |
| `minimal` | 안 실음 | 안 실음 | 안 실음 | 안 실음 |
| `copyright_only` | Artist·Copyright 만 | 안 실음 | 저작권 항목만 | 안 실음 |
| `remove_location` | 전부 | 전부 | 장소 항목 뺌 | **안 실음** |
| `all` | 전부 | 전부 | 전부 | 전부 |

앱이 아는 값은 **나중에** 써서 겹치는 자리를 덮습니다.

## Windows 구현에서 걸린 것 세 가지

전부 측정으로 드러났습니다. 셋 다 문서나 추론으로는 나오지 않았습니다.

**1. WIC 는 하위 덩이를 이름이 아니라 태그 번호로 열거합니다.** `/exif` 가 아니라
`/{ushort=34665}` 입니다. 이름으로 찾는 코드는 EXIF·GPS·IPTC 를 **하나도** 못 찾았습니다.
열거 결과를 그대로 찍어 보고서야 드러났습니다.

```
/ifd/{ushort=33723}  <블록 iptc>
/ifd/{ushort=34665}  <블록 exif>
/ifd/{ushort=34853}  <블록 gps>
```

**2. IPTC 항목은 `/{str=By-line}` 로 나옵니다.** 이름을 통째로 정규화하면 `strbyline` 이
되어 어떤 규칙과도 안 맞습니다. `{str=…}` 껍데기를 벗겨야 합니다.

**3. 게시 검증이 원본 태그를 거절했습니다.** `inspect_minimal_rgb_tiff_ifd` 는 최소 IFD
허용 목록을 강제하므로, 옮겨 실은 `270`·`700`·`33723`·`34853` 에서 게시가 실패했습니다.
사용자가 원본 메타데이터를 실으라고 골랐으면 "뜻밖의 태그" 라는 말이 성립하지 않으므로,
정책이 원본을 싣는 경우에는 그 판정을 끕니다. 중복 태그·항목 수 상한·색 프로파일 존재는
그대로 봅니다. 픽셀과 어긋날 수 있는 구조 태그(크기·스트립·해상도·ICC)는 애초에 옮기지
않습니다.

## 실측

64 × 64 단색 TIFF 에 골든 픽스처와 같은 항목을 싣고, 네 정책으로 실제 내보낸 뒤 다시
읽었습니다(셸을 띄우지 않고 출력 패널과 같은 요청 경로).

| 항목 | minimal | copyrightOnly | removeLocation | all |
| --- | :-: | :-: | :-: | :-: |
| TIFF ImageDescription | | | ✓ | ✓ |
| TIFF Artist / Copyright | | ✓ | ✓ | ✓ |
| TIFF Make / Model (앱) | ✓ | | ✓ | ✓ |
| TIFF Software / DateTime (앱) | ✓ | | ✓ | ✓ |
| EXIF LensModel / ISO | | | ✓ | ✓ |
| EXIF UserComment | FilmType 만 | | FilmType + FilmStock | 〃 |
| IPTC By-line / CopyrightNotice | | ✓ | ✓ | ✓ |
| IPTC Headline | | | ✓ | ✓ |
| IPTC City | | | | ✓ |
| GPS | | | | ✓ |

macOS task6 골든(`docs/verification/macos-golden/task6-metadata-policy/tiff-tags.json`)의
정책별 태그 구성과 같은 규칙입니다.

**덤으로 맞춘 것.** macOS 는 EXIF 시각과 함께 오프셋 세 태그(`36880`·`36881`·`36882`)를
`+00:00` 으로 씁니다. Windows 는 시각만 쓰고 있었습니다 — 오프셋 없는 EXIF 시각은 읽는 쪽이
제 시간대로 해석해 몇 시간씩 어긋납니다. 세 태그를 함께 쓰도록 맞췄습니다.

## 시험

- 네이티브 69개 통과. `wic_tiff_export_tests` 에 정책 판정 표를 못 박았습니다 — 태그 번호로
  덩이를 알아보는지, 구조 태그가 어느 정책에서도 안 새는지, IPTC 이름의 껍데기를 벗기는지.
  오늘 이 셋이 각각 한 번씩 틀렸으므로 셋 다 시험에 있습니다.
- 실파일 왕복은 위 표가 근거입니다.

## 아직 아닌 것

- **JPEG 은 확인하지 않았습니다.** 코드 경로는 같고(`/app1/ifd` 접두사만 다름) TIFF 로만
  실측했습니다. 확인 전에는 됐다고 적지 않습니다.
- PNG 은 EXIF 를 받지 않으므로 정책이 흔적을 남기지 않습니다. 이는 macOS 도 같습니다.
