# Catalog Develop route 공식 근거와 권리 조사

기준일: 2026-08-04

## 저장소 기준 구현

같은 Apache-2.0 저장소에서 다음 source를 직접 읽어 persistence 의미를 확인했습니다.

- `Sources/Chromabase/Develop/DevelopParameters.swift`
- `Sources/Chromabase/Film/FilmType.swift`
- `Sources/Chromabase/Adjustments/FilmEmulation.swift`
- `Sources/negaflowApp/Services/Storage/Catalog/Models/LibraryFrameRecord.swift`
- `Sources/negaflowApp/Services/Storage/LibraryWorkflowTracking.swift`
- `Sources/negaflowApp/Features/Develop/Model/DevelopmentProcess.swift`
- `Sources/negaflowApp/Features/Library/Model/AppModel+Import.swift`
- `windows_docs/14-persistence/catalog-and-storage.md`
- `windows_docs/15-digital-film/virtual-development.md`

확인한 사실은 다음과 같습니다.

1. `LibraryFrameRecord.sourceKind`의 `scanner`/`imported`는 loader와 등록 출처를 선택하는 transport입니다.
2. `DevelopParameters.isDigitalSource`는 optional이며 키가 없으면 기존 필름 recipe입니다.
3. 디지털 프로세스는 `colorPositive`/`bwPositive`와 marker `true` 조합입니다.
4. missing `filmEmulationIntensity`는 `1.0`, 새 구조체 기본값은 `0.5`입니다.
5. frame top-level `filmType`과 params 안의 `filmType`은 catalog에 함께 존재합니다.
6. macOS import가 `.importedFile`을 저장한다는 사실만으로 digital source를 의미하지 않습니다.

Windows 코드는 이 의미를 독립 C# 모델과 switch 기반 이름 매핑으로 작성했습니다. Swift 구현의 code,
JSON encoder 내부나 제3자 catalog code를 복사하지 않았습니다.

## 공식 기술 근거

- [Microsoft: Required properties](https://learn.microsoft.com/en-us/dotnet/standard/serialization/system-text-json/required-properties)는
  required property가 빠졌을 때 `JsonException`을 낼 수 있고, 새 애플리케이션에서 non-optional constructor
  parameter 존중을 권장합니다. 이번 reader는 필수 frame 필드를 수동 검사하고 stable error enum으로
  반환합니다.
- [Microsoft: Handle unmapped members](https://learn.microsoft.com/en-us/dotnet/standard/serialization/system-text-json/missing-members)는
  기본 deserialize가 알 수 없는 property를 무시하며, 필요하면 unknown member를 거부할 수 있음을
  설명합니다. 전체 recipe를 좁은 POCO로 다시 써서 미래 필드를 잃지 않도록 route projection만 읽습니다.
- [Microsoft: Handle overflow JSON](https://learn.microsoft.com/en-us/dotnet/standard/serialization/system-text-json/handle-overflow)는
  `JsonExtensionData`, `JsonElement`와 `JsonNode`로 모델 밖 데이터를 보존하는 방법을 설명합니다. writer는
  기존 `JsonObject`를 깊게 복사한 뒤 소유 field만 변경합니다.
- [Microsoft: Customize property order](https://learn.microsoft.com/en-us/dotnet/standard/serialization/system-text-json/customize-properties)는
  output property 순서를 제어할 수 있음을 설명합니다. catalog payload는 attribute 선언 순서에 의존하지
  않고 재귀적 ordinal key 정렬을 사용합니다.
- [Microsoft: Utf8JsonWriter](https://learn.microsoft.com/en-us/dotnet/api/system.text.json.utf8jsonwriter?view=net-10.0)는
  forward-only UTF-8 JSON writer와 기본 구조 검증 계약을 제공합니다. `CatalogJson`은 이 .NET 기본 API만
  사용하며 새 package를 추가하지 않습니다.

## 제한형 공개 특허 검색

- [US6181836B1](https://patents.google.com/patent/US6181836B1/en)은 원본과 별도인 resolution-independent
  modification parameter file을 image database에 저장하는 non-destructive image editing을 다룹니다.
  Google Patents에는 `Expired - Lifetime`, 예상 만료 2013-06-30으로 표시됩니다. 이번 변경은
  resolution-independent layer/function format이나 해당 raster 구조를 구현하지 않고 기존 Negaflow frame의
  세 route field만 검증·보존합니다.
- [US10860196B1](https://patents.google.com/patent/US10860196B1/en)은 edit experience와 transformation UI를
  다루며 Google Patents에는 `Active`, 예상 만료 2039-07-12로 표시됩니다. 이번 변경에는 edit 추천,
  transformation UI, XMP 기반 experience 또는 content-aware 기능이 없습니다.
- [US20150363373A1 / US11210455B2](https://patents.google.com/patent/US20150363373)는 서로 다른 앱 사이에
  공유 가능한 non-destructive processing pipeline format을 다룹니다. Google Patents에는 granted family의
  현재 상태가 `Expired - Fee Related`로 표시됩니다. 이번 fixture는 제품 간 범용 pipeline format이 아니라
  같은 저장소의 legacy decode 의미를 검증하는 테스트 데이터입니다.

Google Patents의 상태와 예상 만료는 법률 결론이 아닙니다. 이 검색은 가까운 공개 제목과 claims를
무심코 복제하지 않기 위한 제한형 engineering screen이며, 관할별 유효성 판단이나 freedom-to-operate
보증이 아닙니다.

## 라이선스·저작권 결론

- 제품 의미는 동일 Apache-2.0 저장소의 source와 문서를 기준으로 독립 구현했습니다.
- Microsoft 문서는 공개 .NET API 동작 확인에만 사용했고 sample code를 복사하지 않았습니다.
- 특허 문서는 회피 경계 확인에만 사용했고 code, figure, format 또는 청구항 절차를 구현 자산으로
  복사하지 않았습니다.
- `System.Text.Json`은 .NET runtime 기본 구성요소이며 새 runtime dependency, binary 또는 데이터
  payload를 추가하지 않았습니다.
