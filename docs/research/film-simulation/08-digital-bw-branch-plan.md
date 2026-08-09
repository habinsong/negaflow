# Digital B&W 분기 설계

[Docs home](../../README.md)

> 상태: 설계안(코드 미변경). 웹 조사 문서 01~07과 짝을 이루는 구현 준비 문서입니다.
> 근거는 전부 현재 저장소 코드를 직접 읽고 확인한 사실입니다.

## 1. 지금 무슨 일이 일어나고 있는가

`DevelopmentProcess`(`negaflow-mac/Sources/negaflowApp/Features/Develop/Model/DevelopmentProcess.swift`)는
디지털 소스 2종을 필름 포지티브 경로에 그대로 얹습니다.

| 프로세스 | `filmType` | `isDigitalSource` |
|---|---|---|
| Digital Color | `.colorPositive` | `true` |
| Digital B&W | `.bwPositive` | `true` |

즉 **Digital B&W는 Digital Color와 같은 파이프라인을 타고**, 마지막에 흑백으로 붕괴됩니다.

필름 룩 선택 UI(`FilmEmulationSection.swift`)는 프로세스를 보지 않습니다.
`FilmEmulation.films(of: .slide)` 와 `.negative` 두 카드를 **항상** 그립니다.
그래서 Digital B&W에서도 Portra 400 · Velvia 50 같은 컬러 스톡만 나열됩니다(첨부 스크린샷과 동일).

### 그 컬러 프리셋은 실제로 무엇을 하는가

`ChromabaseEngine+PostPipeline.swift`의 순서가 답입니다.

```
8.4.y  DigitalFilmLook.apply(...)        ← 헐레이션 → 필름 LUT → 색 프리셋 → 그레인
 ...
10.    if filmType == .bwNegative || .bwPositive {
           CIColorMatrix(Rec.709 luma)   ← 무조건 중립 그레이스케일로 붕괴
           applyMonochromeTint(...)
           BWToningStage.apply(...)
       }
```

`DigitalFilmLook`이 만든 스톡 고유의 색 매트릭스·밝기대별 크로스오버·inter-image 채도는
10번 단계의 luma 행렬에서 **전부 폐기**됩니다. Rec.709 가중치(0.2126/0.7152/0.0722)를 통과해
살아남는 것은 채널 톤커브가 휘도에 남긴 잔재뿐입니다.

정리하면 현재 Digital B&W의 필름 선택은 **거의 무의미한 UI**입니다.
Velvia 50을 고르든 Portra 160을 고르든 결과 차이는 톤커브 부산물 수준이고,
그마저도 "그 필름의 흑백 렌디션"과는 아무 관계가 없습니다.

## 2. 흑백 필름 시뮬레이션의 핵심은 색 매트릭스가 아니다

흑백 필름을 가르는 1차 변수는 **분광 감도(spectral sensitivity)** 입니다.
같은 장면이라도 유제가 어느 파장을 얼마나 받는지에 따라 그레이 값이 달라집니다.

- 오소크로매틱(Ilford Ortho Plus 등): 적색 감도 거의 없음 → 붉은 것이 검게, 입술·벽돌이 어둡게
- 팬크로매틱(대다수): 가시광 전역, 다만 청색 과감도 경향
- 확장 적감(Ilford SFX 200, Rollei Retro 80S 등): 근적외까지 → 하늘이 극단적으로 어둡고 잎사귀가 하얗게
- 적외(Kodak HIE 등): Wood 효과

이것을 엔진 언어로 옮기면 **RGB → 그레이 가중치가 필름마다 달라야 한다**는 뜻입니다.
현재는 모든 흑백 프레임이 Rec.709 고정 가중치 하나를 씁니다.

2차 변수는 특성곡선 형태(long-toe Tri-X 계열 vs straight-line T-Max/Delta 계열),
RMS granularity와 결정 구조(전통 큐빅 vs T-GRAIN vs Core-Shell),
MTF/acutance, 안티할레이션층 유무(투명 폴리에스터 베이스의 발광)입니다.

컬러에서 쓰던 축 중 **색 매트릭스·HSL 밴드·색 크로스오버·chroma 그레인은 흑백에서 전부 무의미**합니다.
반대로 흑백에만 필요한 축(분광 가중치, 필터 시뮬레이션)이 새로 생깁니다.
→ 그래서 자료형을 컬러와 공유하면 안 됩니다.

## 3. 분기 설계안

### 3.1 선택지 비교

| 안 | 내용 | 장점 | 단점 |
|---|---|---|---|
| A | `FilmEmulation` enum에 흑백 케이스를 추가하고 `Kind`만 늘림 | 배선 최소, 영속성 그대로 | 컬러 전용 테이블 3개(`FilmEmulationProfile`/`DigitalFilmPhysics`/`DigitalFilmColorPreset`)가 흑백 케이스를 억지로 떠안음. switch 4곳이 전부 비대해짐 |
| B | `BWFilmEmulation` enum + `DevelopParameters.bwFilmEmulation` 필드를 새로 만듦 | 자료형이 정직하게 갈림 | 영속성·XMP·배치 동기화·프리셋 4곳에 필드 추가. 프레임이 컬러↔흑백을 오갈 때 선택 2개가 공존 |
| **C (권장)** | `FilmEmulation` enum은 그대로 **하나의 "선택된 필름"** 으로 두되(`Kind`에 `.bwNegative`/`.bwReversal` 추가), 흑백 케이스는 **별도 파라미터 테이블 `BWFilmProfile`** 과 **별도 스테이지**로 라우팅 | 영속성·UI·배치 동기화 변경 없음(rawValue 문자열 그대로). 자료형은 흑백/컬러가 분리됨 | `FilmEmulationProfile.of` 등 컬러 테이블의 switch에 흑백 케이스 방어 코드 필요 |

C안을 권장합니다. UI가 이미 "필름 하나만 선택"이고, 영속화된 문자열 rawValue를 건드리지 않는 것이
가장 안전합니다. 컬러 테이블 3개는 흑백 케이스에서 `nil`/identity를 반환하도록 하고,
흑백은 `BWFilmProfile.of(...)`가 유일한 진입점이 됩니다.

### 3.2 새 자료형 초안

```swift
/// 흑백 유제 한 종. 컬러와 축이 다르므로 자료형을 공유하지 않는다.
public struct BWFilmProfile: Sendable {
    /// 분광 감도에서 유도한 RGB→그레이 가중치. 합=1로 정규화.
    /// 오소 유제는 x≈0, 확장 적감 유제는 x가 크게 잡힌다.
    public var spectralWeights: SIMD3<Double>
    /// 특성곡선: contrast index(표준 현상 기준), toe/shoulder 형태, Dmax
    public var contrastIndex: Double
    public var toeSoftness: Double        // long-toe(Tri-X) ↔ straight-line(T-Max)
    public var shoulderSoftness: Double
    public var latitudeStops: Double
    /// 그레인: 흑백은 은염이라 chroma 성분이 없다(컬러의 chromaRatio 없음).
    public var grainAmplitude: Double
    public var grainSize: Double
    public var grainProvenance: DigitalFilmDataProvenance
    /// MTF acutance
    public var acutance: (radius: Double, intensity: Double)
    /// 안티할레이션이 약한 투명 베이스 유제의 발광(휘도 번짐만, 색 없음)
    public var halationStrength: Double
    public var halationRadiusRatio: Double
    /// 반전(흑백 슬라이드)이면 true — Dmax가 훨씬 높고 관용도가 좁다.
    public var isReversal: Bool
}
```

`DigitalFilmPhysics`의 컬러 전용 축(`layerSpeed`, `layerDmax`, `interImage`, 채널별 `gamma`,
채널별 `scatterStrength`)은 흑백에 존재하지 않으므로 옮기지 않습니다.

### 3.3 파이프라인 삽입 지점 — 여기가 함정입니다

현재 흑백 중립화는 **세 곳**에서 일어납니다. 순서대로:

1. `PositiveDevelop.applyBaseGrade` — `filmType == .bwPositive`면 채도 0
   (`ChromabaseEngine+PositivePipeline.swift:32`에서 **스캐너 에뮬레이션 타겟일 때만** 호출)
2. `ScannerTargetGrade.apply` 내부 — `monochrome`이면 시작하자마자 Rec.709 luma 붕괴
   (`ScannerTargetGrade+Apply.swift:193`, 역시 스캐너 타겟 한정)
3. `applyPostPipeline` 10번 — 흑백 타입이면 **항상** Rec.709 luma 붕괴

`developTarget` 기본값은 `.main`이므로 일반적인 Digital B&W 경로에서는 1·2번이 실행되지 않고,
색 정보가 PostPipeline까지 살아서 도착합니다. 따라서 **현재 필름 룩 자리(8.4.y)에서
분광 가중치를 적용할 수 있습니다.**

다만 사용자가 NORITSU/SP 같은 스캐너 타겟을 고르면 2번이 먼저 색을 없애 버려
분광 가중치가 무력화됩니다. 구현 시 둘 중 하나가 필요합니다.

- (권장) 흑백 필름 룩이 선택된 경우 2번의 luma 붕괴를 건너뛰고, 붕괴 책임을 흑백 필름 스테이지로 넘긴다
- 또는 흑백 필름 스테이지를 스캐너 타겟보다 앞으로 옮긴다 (파이프라인 순서 변경이라 위험도가 높음)

10번 단계의 luma 행렬은 **그대로 두어도 안전합니다** — 이미 중립인 이미지에 Rec.709를 곱하면
항등이고, 그레인·텍스처가 만든 색 얼룩을 청소하는 원래 역할도 유지됩니다.

### 3.4 새 흐름

```
DigitalFilmLook.apply(...)
  - emulation.kind == .slide / .negative      → 기존 컬러 경로 (변경 없음)
  - emulation.kind == .bwNegative / .bwReversal
       - BWHalation   (휘도 번짐만, 색 없음. 투명 베이스 유제만 유효)
       - BWSpectralGray  RGB → 그레이 (필름별 가중치)   ★ 여기서 컬러가 사라짐
       - BWFilmLUT       1D 톤커브 (contrast index / toe / shoulder / Dmax)
       - BWAcutance      MTF 근사
       - BWGrain         은염 그레인 (chroma 성분 없음)
```

`FilmEmulationStage`(필름 스캔 경로)도 같은 분기가 필요합니다.
흑백 **필름 스캔**에 흑백 스톡 룩을 얹는 것은 이미 그 유제를 통과한 신호에 유제 응답을
두 번 먹이는 것이므로, 스캔 경로에서는 **분광 가중치와 그레인을 빼고 톤커브만** 적용하는 것이
맞습니다(메모리 규칙 "필름 경로는 불가침"과도 일치 — 개선은 `isDigitalSource` 분기 안에서만).

### 3.5 UI 분기

`FilmEmulationSection.swift`가 현재 프로세스를 보고 카드를 고르게 합니다.

| 프로세스 | 보여줄 카드 |
|---|---|
| Digital Color / E-6 / C-41 | 슬라이드 · 컬러 네거티브 (+ 신설: 컬러 영화용) |
| Digital B&W / D-76 / B&W Reversal | 흑백 네거티브 · 흑백 슬라이드 (+ 신설: 흑백 영화용) |

`FilmEmulation.Kind`에 `.bwNegative` / `.bwReversal` / `.motionPicture` 를 추가하고,
섹션이 `frame.params.filmType`(또는 `DevelopmentProcess`)으로 필터링하면 됩니다.

**주의**: 프레임의 프로세스를 컬러↔흑백으로 바꾸면 기존 선택이 목록에 없는 필름이 됩니다.
이때 선택을 자동으로 `.none`으로 되돌릴지, 값은 보존하되 표시만 숨길지 결정이 필요합니다.
값 보존(숨김)을 권장합니다 — 사용자가 프로세스를 되돌리면 선택이 살아 돌아오는 편이 덜 놀랍습니다.

### 3.6 흑백 슬라이드(반전)를 별도 그룹으로 두는 이유

`bwPositive` 타입은 이미 있지만 대응 프리셋이 하나도 없습니다.
흑백 반전은 흑백 네거티브를 흑백 변환한 것과 다릅니다 — Dmax가 훨씬 높고(2.9~3.3대),
관용도가 좁으며, 토우/숄더가 급격합니다. 컬러에서 슬라이드/네거티브를 나눈 것과 같은 근거로
흑백에서도 나눠야 합니다. 구체 수치는 조사 문서 `06-bw-reversal-and-motion-picture.md` 참조.

## 4. 영향 범위 (변경이 필요한 파일)

| 파일 | 변경 |
|---|---|
| `Chromabase/Adjustments/FilmEmulation.swift` | 흑백·영화용 케이스, `Kind` 확장, `displayName` |
| `Chromabase/Adjustments/FilmEmulationProfile.swift` | 흑백 케이스에서 identity 반환(방어) |
| `Chromabase/Digital/DigitalFilmPhysics.swift` | 흑백 케이스에서 `nil` 반환 |
| `Chromabase/Digital/DigitalFilmColorPreset.swift` | 흑백 케이스에서 `nil` 반환 |
| `Chromabase/Digital/BWFilmProfile.swift` | **신설** — 흑백 유제 파라미터 테이블 |
| `Chromabase/Digital/DigitalBWFilmLook.swift` | **신설** — 흑백 전용 스테이지 |
| `Chromabase/Digital/DigitalFilmLook.swift` | kind 분기 라우팅 |
| `Chromabase/Engine/ChromabaseEngine+PostPipeline.swift` | 흑백 필름 선택 시 중복 중립화 정리 |
| `Chromabase/Profiles/ScannerTargetGrade/ScannerTargetGrade+Apply.swift` | 흑백 필름 룩 활성 시 조기 luma 붕괴 건너뛰기 |
| `negaflowApp/Features/Develop/Inspector/FilmEmulationSection.swift` | 프로세스별 카드 필터링 |
| `negaflowApp/Localization/**` | 새 섹션 헤더 문구 7개 언어 |
| `Tests/ChromabaseTests/DigitalFilmLookTests.swift` | 흑백 경로 테스트 추가 |

파일 크기 규칙(메모리: 작은 단일 목적 파일)을 지키려면 `BWFilmProfile`은
`BWFilmProfile.swift`(자료형) / `BWFilmProfile+Negative.swift` / `BWFilmProfile+Reversal.swift` /
`BWFilmProfile+MotionPicture.swift` 로 나누는 것이 기존 `FilmEmulationProfile+Negative/Slide` 관례와 맞습니다.

## 5. 검증 계획

메모리 규칙상 실제 이미지로 판단하지 않고 **합성 픽스처 + 수치 측정**으로 검증합니다.

1. **분광 가중치 검증**: 순수 R/G/B 패치와 컬러체커 합성 이미지를 넣고, 오소 프로파일에서
   빨강 패치가 팬크로 대비 유의하게 어두워지는지 수치로 확인
2. **중립성 검증**: 모든 흑백 프로파일 출력에서 R=G=B (허용오차 1e-4) — 그레인 이후에도 유지
3. **곡선 검증**: long-toe 프로파일이 straight-line 프로파일보다 섀도우 구간(입력 0.05~0.2)에서
   출력이 높은지(토우가 들려 있는지) 측정
4. **반전 vs 네거티브**: 반전 프로파일의 출력 밀도 범위가 네거티브보다 넓고 관용도가 좁은지
5. **필름 스캔 경로 불변**: `isDigitalSource != true`인 기존 흑백 스캔 결과가 픽셀 단위로 불변인지
   골든 테스트 (메모리: "필름 경로는 불가침")
6. **strict concurrency 게이트**: 푸시 전 `scripts/check-swift-concurrency.sh`

## 6. 미결정 사항 (구현 착수 전 확인 필요)

1. **컬러 필터 시뮬레이션**: 황색 K2 / 적색 25 / 녹색 X1 필터를 별도 UI 축으로 둘지,
   아니면 필름 프리셋에 녹여 둘지. 물리적으로는 분리가 맞습니다(필름 가중치 × 필터 투과율).
   조사 문서 `07`의 결론을 보고 결정합니다.
2. **현상액 축**: 같은 필름도 D-76 / Rodinal / HC-110에서 곡선과 그레인이 달라집니다.
   축을 열면 조합이 폭발하므로, 1차 구현은 **제조사 표준 현상 조건 하나로 고정**을 권장합니다.
3. **영화용 필름 그룹의 위치**: 컬러 영화용(Vision3 등)을 "컬러 네거티브" 카드에 합칠지
   별도 카드로 뺄지. ECN-2는 C-41과 톤 구조가 다르므로 별도 카드를 권장합니다.
4. **프로세스 전환 시 선택 보존** 정책 (3.5절).
