# Catalog Develop route projection 구현

## 현재 범위

`Negaflow.Catalog.Core`는 전체 catalog DB가 아니라 persisted frame에서 native Film Look까지 필요한
최소 route를 읽고 쓰는 UI·native 비종속 관리 코드 경계입니다.

```text
frame sourceKind                 frame sourceSignalKind
scanner / imported              filmNegativeScan / filmPositiveScan / renderedDigital
       │                                      │
       └── loader transport                    ├── DevelopmentProcess
                                              └── FilmLookSource

params
  filmType
  isDigitalSource?              legacy compatibility marker
  filmEmulation
  filmEmulationIntensity?
```

`sourceKind == imported`는 digital source가 아닙니다. 가져온 필름 스캔은 film route를 유지하며, 디지털
사진은 explicit `sourceSignalKind == renderedDigital`과 legacy marker `true`를 함께 저장합니다.

## 프로젝트와 파일 책임

- `src/Catalog.Core/Models/FrameSourceTransport.cs`: scanner/import transport
- `src/Catalog.Core/Recipes/SourceSignalKind.cs`: pixel/decode 신호 의미
- `FilmType.cs`, `DevelopmentProcess.cs`: persisted film type과 제품 process mapping
- `FilmEmulation.cs`, `FilmLookSource.cs`: 12개 profile 이름과 native route source 의미
- `DevelopRouteReader.cs`: legacy/new frame projection과 fail-closed 검증
- `DevelopRouteWriter.cs`: owned field 갱신, unknown field 보존, film marker 제거
- `DevelopRouteRules.cs`: source signal+film type의 단일 process mapping
- `DevelopRouteJsonNames.cs`: Swift/raw JSON 이름과 enum의 명시적 양방향 mapping
- `DevelopRouteSelection.cs`: UI process에서 새 recipe를 만드는 기본값 `0.5`
- `Serialization/CatalogJson.cs`: object key를 재귀적으로 ordinal 정렬하는 UTF-8 writer
- `tests/fixtures/catalog/develop-route-v1.json`: valid 5개, invalid 17개 호환 fixture
- `tests/Catalog.UnitTests/Program.cs`: projection, writer, unknown field, profile와 canonical byte 검증
- `Tests/ChromabaseTests/WindowsDevelopRouteCompatibilityTests.swift`: 같은 fixture를 현재
  `DevelopParameters` decoder/default와 대조

각 타입은 한 책임만 가지며 Shell preference, SQLite, native workspace나 pixel buffer를 소유하지 않습니다.

## 읽기 상태 머신

`DevelopRouteReader.Read`는 다음 순서로 검사합니다.

1. frame object와 필수 `sourceKind`, top-level `filmType`, `params` object를 확인합니다.
2. params `filmType`이 없으면 현재 Swift legacy default인 `colorNegative`로 해석하고 top-level과
   일치하는지 확인합니다.
3. optional `isDigitalSource`는 missing/null/true/false만 허용합니다.
4. explicit `sourceSignalKind`가 있으면 marker와 일치하는지 확인합니다.
5. explicit signal이 없으면 marker+film type으로만 legacy signal을 만듭니다.
6. source signal+film type을 여섯 `DevelopmentProcess` 중 하나로 매핑합니다.
7. profile이 없으면 `none`, intensity가 없거나 null이면 legacy `1.0`을 적용합니다.
8. 모든 값이 유효할 때만 immutable `DevelopRouteSnapshot`을 반환합니다.

오류 결과에는 route가 없습니다. 따라서 caller가 일부 field만 사용해 잘못된 preview/export를 시작할 수
없습니다.

## route 표

| source signal | film type | process | Film Look source |
|---|---|---|---|
| `filmNegativeScan` | `colorNegative` | C-41 | film scan |
| `filmNegativeScan` | `bwNegative` | D-76 | film scan |
| `filmPositiveScan` | `colorPositive` | E-6 | film scan |
| `filmPositiveScan` | `bwPositive` | B&W Reversal | film scan |
| `renderedDigital` | `colorPositive` | Digital Color | rendered digital |
| `renderedDigital` | `bwPositive` | Digital B&W | rendered digital |

다른 조합은 `SourceSignalFilmTypeMismatch`입니다. `sceneLinearDigital`과 `unknown`은 이름은 보존하지만
현재 entrance가 없으므로 `UnsupportedSourceSignal`입니다.

## 쓰기 계약

`DevelopRouteWriter.Apply`는 입력 `JsonObject`를 직접 바꾸지 않고 깊은 복사본을 만듭니다.

- `sourceKind`는 검사만 하고 바꾸지 않습니다.
- top-level `sourceSignalKind`, top-level/params `filmType`을 같은 값으로 기록합니다.
- rendered digital이면 params `isDigitalSource = true`를 기록합니다.
- film이면 `isDigitalSource` key를 제거해 nil legacy 의미를 보존합니다.
- profile과 intensity를 명시적으로 기록합니다.
- 소유하지 않는 frame/params field는 그대로 보존합니다.
- selection이 invalid이면 복사본을 반환하지 않고 원본도 바꾸지 않습니다.

`CatalogJson.SerializeCanonical`은 object의 모든 key를 ordinal 순서로 쓰고 array 순서를 보존합니다.
이는 SQLite entity payload를 deterministic하게 만들기 위한 첫 경계이며, 전체 catalog v6 encoder나
macOS JSON 숫자 표기/fingerprint byte parity를 완료했다는 뜻은 아닙니다.

## legacy와 새 기본값

| 경우 | 해석/저장 |
|---|---|
| `sourceSignalKind` 없음, marker 없음/false | film type에 맞는 film scan, legacy 표시 |
| `sourceSignalKind` 없음, marker true, positive | rendered digital, legacy 표시 |
| marker true, negative | invalid |
| intensity key 없음/null | `1.0`, legacy default 표시 |
| 새 process selection | intensity `0.5` |
| 새 film selection | marker key 제거 |
| 새 rendered-digital selection | explicit signal + marker true |

## 아직 연결하지 않은 것

- `%LOCALAPPDATA%` root, process lock, SQLite schema/transaction/readback/rollback
- 전체 `LibraryFrameRecord`와 9개 catalog entity codec
- import metadata writer와 source identity/relink
- C ABI render snapshot과 Film Look workspace cache
- WinUI process picker, preview/export/print snapshot
- complete rendered-digital graph
- macOS catalog 직접 이관과 exact recipe fingerprint parity

일반 이미지 SHA-256은 이 관리 코드 경계에서 읽거나 계산하지 않으며 기본 `끔`입니다.
