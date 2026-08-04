# ADR-0020: catalog의 전송 출처와 현상 신호를 분리하고 legacy recipe를 명시적으로 투영한다

- 상태: 채택
- 날짜: 2026-08-04

## 문제

macOS catalog의 `sourceKind`는 파일이 스캐너에서 왔는지 가져오기로 등록됐는지만 나타냅니다.
`imported` 파일은 디지털 카메라 사진일 수도 있고 필름 스캔일 수도 있으므로 이 값만으로 Film Look
경로를 고를 수 없습니다. 실제 기존 현상 분기는 `DevelopParameters.isDigitalSource`와 `filmType`에
있으며 다음 호환 규칙도 갖습니다.

- `isDigitalSource` 키 없음: 기존 필름 recipe
- `isDigitalSource == true`: 포지티브 디지털 recipe
- `filmEmulationIntensity` 키 없음: 과거 출력 보존을 위해 `1.0`
- 새 `DevelopParameters` 기본 강도: `0.5`

Windows가 `imported`를 디지털로 추측하거나 missing intensity에 새 기본값을 적용하면 catalog를 다시
열었을 때 source route나 출력이 바뀝니다. 반대로 top-level `filmType`, params 안의 `filmType`, 디지털
marker가 서로 어긋난 상태를 조용히 정리하면 손상된 recipe를 성공처럼 게시할 수 있습니다.

## 결정

1. `FrameSourceTransport`는 `scanner`/`imported` 전송 출처만 소유합니다. Film Look source 선택에 직접
   사용하지 않습니다.
2. 새 Windows frame record는 top-level `sourceSignalKind`를 명시적으로 저장합니다. 현재 지원 값은
   `filmNegativeScan`, `filmPositiveScan`, `renderedDigital`이며 `sceneLinearDigital`과 `unknown`은 완전한
   entrance가 생길 때까지 visible unsupported입니다.
3. legacy record에 `sourceSignalKind`가 없으면 `isDigitalSource`와 `filmType`만으로 호환 투영합니다.
   파일 확장자, decoder, `sourceKind`, 선택 profile 또는 pixel 통계로 추정하지 않습니다.
4. `renderedDigital`은 포지티브 film type과 legacy `isDigitalSource == true`가 함께 있어야 합니다.
   필름 신호 저장 시 `isDigitalSource`를 `false`로 쓰지 않고 키를 제거해 기존 nil 의미를 보존합니다.
5. frame top-level과 params의 `filmType`이 다르거나, 네거티브+디지털 marker, source signal+marker 불일치,
   unknown 이름, 비유한·범위 밖 강도는 fail-closed로 거부합니다. 부분 route는 반환하지 않습니다.
6. missing `filmEmulationIntensity`는 `1.0`으로 읽고, `DevelopRouteSelection.FromProcess`가 만드는 새
   recipe만 `0.5`를 사용합니다.
7. 읽기·쓰기·이름 매핑·규칙·직렬화를 `Negaflow.Catalog.Core`에 격리합니다. Shell과 native render DLL은
   catalog JSON을 직접 해석하지 않습니다.
8. route writer는 알 수 없는 frame/params 필드를 깊은 복사로 보존하고, key를 ordinal 순서로 쓰는
   deterministic JSON serializer를 제공합니다. 이것은 전체 catalog v6 codec이나 macOS fingerprint byte
   parity 완료를 뜻하지 않습니다.
9. SQLite provider, catalog root/lock/transaction과 C ABI 연결은 이번 작은 경계에 넣지 않습니다.
10. 일반 이미지 SHA-256은 읽거나 계산하지 않으며 기본 `끔` 정책과 무관합니다.

## 결과

가져온 필름 스캔이 디지털 사진으로 오분류되지 않고, 같은 persisted recipe는 재로딩 뒤 같은 Film Look
source와 legacy 강도를 가집니다. 명시적 source signal과 macOS 호환 marker가 함께 기록되므로 이후
C ABI/WinUI가 문자열이나 파일 종류를 추측할 필요가 없습니다. 대신 실제 SQLite transaction, import
metadata 작성자와 native render snapshot 연결은 후속 구현이 필요합니다.

## 남은 한계

- 전체 `LibraryFrameRecord`/catalog v6 schema, SQLite, process lock과 crash recovery는 아직 없습니다.
- `DevelopRouteSnapshot`은 native C ABI나 WinUI preview/export에 아직 전달되지 않습니다.
- macOS catalog를 Windows에서 직접 여는 제품 정책과 exact fingerprint byte parity는 결정되지 않았습니다.
- `sceneLinearDigital` entrance와 완전한 rendered-digital Film Look graph는 미구현입니다.
- 제한형 공개 특허 검색은 법률 자문이나 freedom-to-operate 보증이 아닙니다.

## 근거

- `Sources/Chromabase/Develop/DevelopParameters.swift`
- `Sources/negaflowApp/Services/Storage/Catalog/Models/LibraryFrameRecord.swift`
- `Sources/negaflowApp/Features/Develop/Model/DevelopmentProcess.swift`
- `Sources/negaflowApp/Features/Library/Model/AppModel+Import.swift`
- `windows_docs/14-persistence/catalog-and-storage.md`
- `windows_docs/15-digital-film/virtual-development.md`
- [Microsoft: Required properties](https://learn.microsoft.com/en-us/dotnet/standard/serialization/system-text-json/required-properties)
- [Microsoft: Handle unmapped members](https://learn.microsoft.com/en-us/dotnet/standard/serialization/system-text-json/missing-members)
- [Microsoft: Handle overflow JSON](https://learn.microsoft.com/en-us/dotnet/standard/serialization/system-text-json/handle-overflow)

실행 증거와 권리 검색은 각각 `verification/2026-08-04-catalog-develop-route.md`와
`research/catalog-develop-route-sources.md`에 기록합니다.
