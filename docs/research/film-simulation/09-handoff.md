# 필름 시뮬레이션 확장 — 인수인계

[Docs home](../../README.md)

> 작성: 2026-08-09. 이전 세션이 토큰 한도로 중단되어 남긴 문서입니다.
> **웹 재검색 금지.** 필요한 A등급 수치는 6절에 전부 옮겨 두었습니다.

---

## 1. 배경

이전 작업(다른 에이전트)이 필름 시뮬레이션을 11종 → 42종으로 확장하면서 흑백 경로를 새로
만들었고, 그 결과 **Digital B&W 에서 모든 프레임이 "이미지 로드 실패"로 죽었습니다.**

### 근본 원인 (해결 완료)

`DigitalBWFilmLook.applyBWGlow` 가 `CIBlendWithAlpha` 라는 **존재하지 않는 CIFilter 이름**을
불렀습니다. Core Image 는 알 수 없는 필터에 대해 원본이 아니라 **빈 이미지**(extent
`(0,0,0,0)`)를 돌려줍니다. 헐레이션은 모든 흑백 프로파일에서 항상 켜지므로 흑백 프레임이
예외 없이 소멸했고, 앱은 `developFailed` → `imageLoadFailedFormat` 만 표시했습니다.

측정으로 확정한 결과(당시 진단 출력):

```
DIAG stage triX400 -> (r: 0.0, g: 0.0, b: 0.0) extent=(0.0, 0.0, 0.0, 0.0)
DIAG CIBlendWithAlpha extent=(0.0, 0.0, 0.0, 0.0)   ← 여기서 소멸
```

교훈: **CIFilter 이름은 반드시 실재를 확인할 것.** 실패가 조용하고, 증상이 원인에서 멀다.

---

## 2. 사용자 요구사항 (반드시 지킬 것)

1. 필름 룩은 **Digital Color / Digital B&W 에서만** 작동한다.
   실제 필름 스캔 경로(C-41 / ECN-2 / E-6 / D-76 / B&W Reversal)에서는 **작동하지 않는다.**
2. Digital B&W 는 Digital Color 처럼 **진짜 같은 필름 시뮬레이션**이어야 한다
   (가상 현상·스캔·인화 기반). 단순 채널 믹스가 아니다.
3. 기존 11종(컬러 슬라이드 3 + 컬러 네거티브 8)은 **문제 없었으므로 건드리지 않는다.**
   - 슬라이드: Ektachrome E100, Provia 100F, Velvia 50
   - 네거티브: Portra 160/400/800, Ektar 100, UltraMax 400, ColorPlus 200, Fujicolor C200, Pro 400H
4. 추가된 31종은 각 필름 고유의 개성이 실제로 살아 있어야 한다.

---

## 3. 완료된 작업

### 3.1 흑백 경로 전면 재작성

| 파일 | 상태 | 내용 |
|---|---|---|
| `Chromabase/Digital/BWFilmProfile.swift` | 재작성 | 흑백 유제 자료형. 분광 가중치는 생성자에서 합=1 정규화 |
| `Chromabase/Digital/BWFilmProfile+Negative.swift` | 재작성 | 흑백 네거티브 13종, RMS 실측 반영 완료 |
| `Chromabase/Digital/BWFilmProfile+Reversal.swift` | 신설 | 흑백 반전 2종 (Scala 200X, Rollei Superpan 200) |
| `Chromabase/Digital/BWFilmResponse.swift` | 신설 | 물리량 → 곡선 계수 유도. 필름별 곡선을 손으로 넣지 않는다 |
| `Chromabase/Digital/DigitalBWFilmLook.swift` | 재작성 | 헐레이션 → 유제 응답 → acutance → 그레인 |
| `Chromabase/Engine/ChromabaseMetalKernels.swift` | 커널 추가 | `digitalBWFilm` |
| `Chromabase/Digital/DigitalHalation.swift` | 오버로드 추가 | 계수 기반 진입점(흑백 재사용) |
| `Chromabase/Digital/DigitalFilmGrain.swift` | 오버로드 추가 | 계수 기반 진입점(chromaRatio 0) |

**설계 원칙 (유지할 것)**

- 컬러 경로와 **같은 순서**: 헐레이션(밀도 형성 전) → 유제 응답 → acutance → 그레인(밀도 후).
- 분광 합성(RGB→그레이)은 **선형 광 도메인**, 특성곡선은 **sRGB 감마 도메인**.
  커널 `digitalBWFilm` 안에서 둘을 나눠 처리한다.
- 1 을 넘는 확장값은 곡선 밖으로 빼 두었다가 되돌린다(관용도 보존).
- `intensity` 는 **유제 개성에만** 걸린다. 0 이면 Rec.709 중립 그레이로 수렴한다.
  색 붕괴 자체는 항상 100% 다.
- 곡선은 `BWFilmResponse` 가 물리량(CI / toe / shoulder / latitude / Dmax)에서 **유도**한다.
  필름별로 곡선 상수를 직접 넣지 말 것 — 필름을 추가할 때마다 재튜닝하게 된다.

### 3.2 라우팅 잠금

- `DigitalFilmLook.appliesLook(emulation:monochrome:)` 신설.
  흑백 프로세스엔 흑백 유제만, 컬러 프로세스엔 컬러 유제만 걸린다.
- `DigitalFilmLook.apply(...)` 에 `monochrome:` 파라미터 추가.
- `ChromabaseEngine+PostPipeline.swift`: `else { FilmEmulationStage.apply(...) }` **제거**.
  → 필름 스캔 경로에는 필름 룩이 더 이상 걸리지 않는다(요구사항 1).
- 10번 단계 Rec.709 중립화는 **원상 복구**했다. 이미 중립인 신호에는 항등이고, 뒤 스테이지의
  색 얼룩을 청소하는 원래 역할이 남는다. (이전 작업은 이걸 조건부로 건너뛰게 바꿨었음)
- `textureParameters(from:)` 는 룩이 **실제로 걸린 경우에만** grain/halation 을 비운다.

### 3.3 UI

- `FilmEmulationSection.swift`
  - 디지털 아님 → 목록 대신 `filmLookDigitalOnly` 안내만 표시(선택값은 보존).
  - Digital B&W → 흑백 슬라이드 / 흑백 네거티브 카드.
  - Digital Color → 슬라이드 / 컬러 네거티브 / 영화용 카드.
- 새 문구 3개를 6개 언어 전부에 추가 완료:
  `filmGroupCinema`, `filmGroupBWSlide`, `filmLookDigitalOnly`.

### 3.4 테스트

`Tests/ChromabaseTests/DigitalBWFilmLookTests.swift` 신설(16개 케이스).
extent 소멸 회귀 가드, 중립성, 분광 분리(오소/적외/T-Max), 곡선(토우/반전 대비/깊은 검정),
강도 단조성, 라우팅(필름 스캔 제외·종류 불일치 무시), 테이블 비중첩, 전 필름 구별성.

**주의**: 이 테스트는 아직 한 번도 실행하지 않았다. 4절 1번 항목 참조.

---

## 4. 남은 작업 (우선순위 순)

### 1. 빌드·테스트 실행 — 최우선

```bash
cd negaflow-mac && swift build 2>&1 | grep -E "error" | head -30
```

```bash
cd negaflow-mac && swift test --filter DigitalBWFilmLookTests 2>&1 | tail -40
```

- 마지막 확인 시점에 `swift build` 는 통과(exit 0), `ChromabaseTests` 전체도 통과(exit 0)였다.
- 그 **이후** `BWFilmProfile+Negative.swift` 를 RMS 실측 반영으로 다시 썼고 아직 미검증이다.
- `DigitalBWFilmLookTests` 는 작성만 하고 실행하지 않았다. 실패하면 **테스트가 아니라 값을**
  의심할 것(테스트는 물리 방향만 검사한다).
- 앱 타깃 테스트도 확인: `swift test --filter negaflowAppTests` — 로컬라이제이션 완전성
  테스트가 새 문구 3개를 검사한다.

### 2. 컬러 31종 개성 검토 — 미착수 (핵심 남은 일)

이전 에이전트가 넣은 값을 6절 A등급 자료로 검증·보정해야 한다. **확인된 오류:**

#### (a) Vision3 헐레이션 과다 — 확실한 오류, 반드시 고칠 것

현재 `DigitalFilmPhysics.swift` 의 Vision3 4종 `halationStrength` 가 R 0.044~0.048 로
일반 C-41 스틸 네거티브(0.040~0.056)와 같은 수준이다. **틀렸다.**

- Vision3 는 remjet(2025년 이후 AHU)으로 안티할레이션이 **오히려 강하다**.
- 붉은 글로우는 **CineStill** 의 특성이다 — remjet 을 *제거*해서 안티할레이션이 사라진 결과다.
- 즉 Vision3 에 강한 붉은 헐레이션을 넣으면 Vision3 가 아니라 CineStill 을 만든 것이 된다.

→ 권장: Vision3 4종의 `halationStrength` 를 슬라이드(0.026~0.030)와 스틸 네거티브 사이,
   대략 `SIMD3(0.030~0.034, 0.011~0.013, 0.004~0.005)` 로 낮출 것.

#### (b) Vision3 대비 순위 어긋남

문서화된 순위는 **250D > 200T ≈ 50D > 500T** 인데, 현재 평균 감마 순위는
50D(0.529) > 250D(0.518) > 200T(0.513) > 500T(0.507) 로 50D 가 1위다.
→ 250D 를 최고로 올리고 50D 를 200T 수준으로 내릴 것.
   50D 의 개성은 대비가 아니라 **채도 최고 + 그레인 최소**다(현재 `interImage` 와
   `grain` 은 이미 맞게 되어 있으니 그대로 둘 것).

그레인 순위 50D < 200T < 250D < 500T 는 **이미 정확**하다(0.013 / 0.016 / 0.018 / 0.022).

#### (c) Superia Premium 400 의 "4번째 감광층" 서술 오류

이전 작업 요약과 주석이 4th color layer 를 근거로 들었으나, 일본판 데이터시트의 층 구조도는
**감광층 3개뿐이고 4번째 시안층이 없다**(A등급). 4th layer 는 Reala 100 과 Superia X-TRA 400
쪽 특성이다. 주석을 고치고, Premium 400 의 개성은 "넓힌 관용도 + 일본 시장 피부톤" 으로
다시 잡을 것.

#### (d) Reala 100 의 4th layer 의미 정정

Reala 의 4번째 층은 **시안 감광층**이고 목적은 **형광등/혼합광의 녹색 캐스트 보정**이다.
"가장 정확한 색" 이라는 일반적 채도 향상이 아니다. 주석과 파라미터 방향을 이에 맞출 것.

#### (e) 슬라이드 그레인을 RMS 실측으로 정렬

현재 값이 실측 순위와 어긋난다. 컬러 반전 RMS 는 흑백과 **같은 조건**(D=1.0, 48µm, 12×)이라
한 자에 놓을 수 있다. 기존 앵커: RMS 8 → amplitude 0.026, RMS 9 → 0.029.

| 스톡 | RMS(A등급) | 권장 amplitude | 현재 |
|---|---|---|---|
| Astia 100F | **7** | 0.023 | 0.024 |
| Velvia 100 | **8** | 0.026 | 0.027 |
| Velvia 50 | 9 (기존) | 0.029 | 0.029 (건드리지 말 것) |
| Kodachrome 64 | **10** | 0.033 | 0.025 ← 낮음 |
| E100VS | **11** | 0.036 | 0.028 ← 낮음 |

#### (f) Astia 100F 대비

데이터시트 명문: "**Softest tones and subdued colors among FUJICHROME films**".
목록의 슬라이드 중 **가장 낮은 대비 + 가장 낮은 채도**여야 한다. 현재 감마
(1.504/1.552/1.616)가 Provia 보다 낮은지 확인하고, `interImage` 도 슬라이드 중 최저인지 볼 것.

#### (g) Kodachrome 64 — 별도 변환이 필요한 스톡

비발색(non-substantive) 필름이라 E-6 유도 프로파일을 그대로 쓰면 중간톤·암부가 시안-블루로
틀어진다. 특징: 따뜻한/적색 편향, **색이 없는 깊은 그림자**(E-6 는 그림자에 틴트가 낀다),
높은 Dmax·대비, 억제된 블루. `shadowTint` 를 거의 0 에 두는 것이 이 스톡의 핵심이다.

#### (h) Lomography CN 800

제조사 데이터시트가 **존재하지 않는다**(A등급 부재 확인). 값의 `provenance` 를 정직하게
표기하고, 추측을 데이터시트인 양 주석에 적지 말 것.

### 3. 흑백 프로파일 잔여 확인

- `Rollei Superpan 200` 은 본래 네거티브인데 흑백 슬라이드 그룹(`bwReversal`)에 넣고
  `isReversal: true` 로 모델링했다. 데이터시트 현상표 기준 γ 는 0.65(네거티브 현상)이고,
  현재 `contrastIndex` 는 반전 현상 기준 0.72 로 두었다. 판단이 필요하면 사용자에게 확인.
- `Agfa Scala 200X` 노출 관용도는 데이터시트상 **±½ stop(ISO 200)** 로 극히 좁다.
  현재 `latitudeStops: 4.5` 가 이 성격을 충분히 담는지 검토.

### 4. 마무리

- `scripts/check-swift-concurrency.sh` 실행 (CI 게이트. 로컬 `swift test` 로는 재현 불가).
- **앱 릴리즈 스크립트로 빌드** — 사용자가 명시적으로 요청한 마지막 단계다.
  `scripts/` 아래에서 릴리즈 빌드 스크립트를 찾아 실행할 것.
- 커밋하지 말 것(사용자가 요청하기 전까지).

---

## 5. 검증 규칙 (프로젝트 메모리)

- **실제 이미지를 열어 눈으로 색을 판단하지 말 것.** 합성 픽스처 + 수치 측정만.
- 한 컷에 맞춰 튜닝 금지. 모든 필름·장면에서 일반적으로 동작해야 한다.
- 필름 스캔 경로는 불가침. 개선은 `isDigitalSource` 분기 안에서만.
- 파일은 작게, 단일 목적으로 유지.
- 응답은 한국어 존댓말.

---

## 6. 웹 조사 결과 (A등급 = 제조사 데이터시트 원문 / B = 신뢰 2차 / C = 추론)

**이 절의 수치로 충분하다. 다시 검색하지 말 것.**

### 6.1 흑백 — 그레인 RMS (×1000, D=1.0 / 48µm / 12배)

| 필름 | RMS | 등급 |
|---|---|---|
| T-Max 100 | **8** (D-76) | A |
| T-Max 400 | **10** (D-76) | A |
| Agfa Scala 200X | **11** (SCALA 공정) | A |
| Rollei Infrared 400 | **11.0** | A |
| Tri-X 400 | **17** (HC-110 B) | A |
| T-Max P3200 | **18** (D-76) | A |
| Ilford 전 제품(HP5+, FP4+, Delta 100/400/3200, SFX, Ortho, Kentmere) | **미공개** | A(부재 확인) |

### 6.2 흑백 — 해상력 (lines/mm, 1000:1 / 1.6:1)

T-Max 100 = **200 / 63** · T-Max 400 = **200 / 50** · T-Max P3200 = **125 / 40** ·
Scala 200X = **120 / 50** · Rollei IR 400 = **160** · **Tri-X 는 미게재**(현행·구판 모두).

### 6.3 흑백 — 분광 감도

- **Kodak T-Max 계열만** 청색 감도를 낮췄다는 명문 규정이 있다(F-4043 / F-4001 / F-32 공통 각주):
  "The blue sensitivity of KODAK PROFESSIONAL T-MAX Films is slightly less than that of other
  Kodak panchromatic black-and-white films. This enables the response of this film to be closer
  to the response of the human eye. Therefore, **blues may be recorded as slightly darker
  tones** with this film—a more natural rendition." [A]
- 파장별 상대 log 감도 **수치는 어떤 데이터시트에도 인쇄되지 않는다**(그래프뿐). [A]
- Tri-X(F-4017)에는 청색 관련 문구가 **없다** = 표준 팬크로(청색 과감)로 남는다. [A 부재]
- Ilford 전 제품: 캡션이 일괄 "Wedge spectrogram to tungsten light (2850K)", 400–650nm,
  수치·계급 표기 전혀 없음. [A]
- Ilford SFX 200: "peak red sensitivity at **720nm**, extended red sensitivity up to **740nm**". [A]
- Ilford Ortho Plus: 청+녹만, 적색 안전등 가능. ISO 80 주광 / **ISO 40 텅스텐**. [A]
- Kentmere Pan 400: 분광 감도 곡선 **자체가 없다**. [A 부재]
- Rollei Superpan 200: "superpanchromatic", 적색 연장 **750nm**, ISO 200→400 push. [A]
- Rollei Infrared 400: 데이터시트 표제 "up to **820nm**" vs 현행 제품페이지
  "hyperpanchromatic, **650–750nm**" — **제조사 내부 수치 충돌**. 순위만 쓸 것. [A]

### 6.4 흑백 — 대비 / 현상

| 필름 | 수치 | 조건 |
|---|---|---|
| Tri-X 400 | 권장 현상이 **contrast index 0.56** 목표 | D-76/HC-110(B)/XTOL/T-MAX, 20°C |
| T-Max 100 | CI 곡선 **0.3–0.9**, 4–18분 | D-76 등, 20°C |
| T-Max 400 | CI 곡선 **0.3–0.9**, 2–16분 | 20 / 24°C |
| Ilford Ortho Plus | **Gbar 0.62–0.70 이 in-camera 정상 대비** | ID-11 |
| Rollei Superpan 200 / Infrared 400 | 현상표 기준 **평균 대비 γ = 0.65** | 20°C |
| Delta 100 특성곡선 | ID-11 stock 8½분 / 20°C | A |
| Delta 400 특성곡선 | ID-11 stock 8분 / 24°C | A |
| HP5+ 특성곡선 | ILFOTEC HC 1+31 6½분 / 20°C | A |
| FP4+ 특성곡선 | ILFOTEC HC 1+31 8분 / 20°C | A |

D-76 20°C 표준시간: T-Max 100 6½분, T-Max 400 7½분, Tri-X 400 6¾분. [A]

### 6.5 흑백 — 안티할레이션 / 베이스 (헐레이션 세기의 유일한 근거)

- **Ilford 롤필름(120)** Delta 100/400, FP4+, HP5+: "clear acetate base with an
  **anti-halation backing which clears during development**". [A]
- **Ilford 35mm**: "acetate base" 만 명시(회색 염착 암시).
- **Ilford SFX 200**: "**grey acetate base which gives good halation protection**" — Ilford 중
  유일하게 회색 베이스 명시. → 확장 적감인데도 발광이 적다. [A]
- **⚠ Ilford Delta 3200**: 35mm·120 **모두** 베이스만 기술되고 **anti-halation backing 언급이
  없는 유일한 Ilford 필름**. 특유의 하이라이트 번짐과 정합. [A 부재 확인]
- **Agfa Scala 200X**: 35mm "Clear base with **AHU layer** decolorised in the developer";
  롤·시트는 AHU + dark green gelatine back. [A]
- **Rollei Superpan 200**: "crystal clear PET carrier" 0.10mm + "integrated antihalation layer". [A]
- **Rollei Infrared 400**: "crystal-clear synthetic carrier" 이고 데이터시트 표제가
  "**Special AURA effects by over exposing film**" — **발광이 제조사 공인 특성**. [A]
- **Kodak Tri-X / T-Max**: 어느 문서에도 안티할레이션 층 서술 **없음**(베이스 재질만). [A 부재]

### 6.6 흑백 — 감도 / 관용도

- Delta 3200 실제 감도 **ISO 1000/31°**, 권장 EI 3200, 양호 범위 EI 400–6400. [A]
- T-Max P3200 실제 **EI 800~1000**(현상액에 따라), EI 400–25,000. [A]
- FP4+ "overexposed by as much as **six stops**, or underexposed by **two stops**". [A]
- Tri-X: 1 stop 언더는 정상 현상 가능, 2 stop 은 증감, 400TX 는 3 stop 까지. [A]
- T-Max 400: **EI 800** 까지 정상 현상으로 고품질. [A]
- Superpan 200: **± 1 aperture**. [A]

### 6.7 흑백 반전 (Scala 200X, F-SW12-E6 08/2000 6th ed.)

- **노출 관용도: ISO 200 에서 ±½ stop, ISO 100 에서 ±1 stop.** 컬러 슬라이드급으로 좁다. [A]
- push/pull 시 대비·최대밀도·입상이 **동시에** 변한다: pull(ISO 100) → Dmax 증가·입상 −10%·
  대비 완만 / push(ISO 1600) → Dmax 감소·대비 급증·입상 조대화. [A]
- Dmax 단일 수치 미공개. push/pull 차트의 최대밀도 축 범위 약 **2.0–3.4**, 대비 축 약 0.6–2.0.
  밀도곡선 플롯은 D 0–3.0. [A(축) / C(개별 판독)]
- MTF "transfer factor" 축이 **150%까지** → 100% 초과(인접 효과) 확인. [A]
- Ilford 응용자료: "We do **not** recommend reversal processing HP5 Plus or DELTA 400 …
  unacceptably low contrast." 권장은 Pan F+, FP4+, 100 Delta. [A]
- dr5 공정 Dmax 주장치(2차, 조건 제각각이라 상호 비교 부적절): Delta 100 4.29, TXP 4.2,
  HP5+ 3.4–3.6, FP4+ 3.34, Scala 3.1. [B/C]

### 6.8 흑백 — 밀도 대비 입상감

Selwyn 법칙 S = σ(D)·√(2a) 가 개구 크기와 무관하게 일정(Zweig 1959) 까지만 확인.
**은염에서 체감 거칠기가 특정 밀도에서 극대화된다는 공표된 관계식은 찾지 못했다.**
다만 모든 제조사가 RMS 를 **D=1.0 에서만** 규정한다는 사실 자체가 밀도 의존성의 방증. [B]
→ 현재 구현은 컬러와 같은 커널(`digitalFilmGrainDensity`)을 쓰므로 이 근사를 공유한다.

### 6.9 컬러 — 그레인 척도 (절대 교차 비교 금지)

- **S1** Fuji 슬라이드 "Diffuse RMS", 48µm, 12×, gross diffuse visual D=1.0 [A]
- **S2** Kodak 슬라이드 "Diffuse rms", 동일 조건 [A] — S1 과 비교 가능
- **S3** Fuji **네거티브** "Diffuse RMS", 48µm, 12×, **Dmin+1.0** [A] — S1/S2 와 비교 **불가**
- **S4** Kodak Print Grain Index(4×6", 14in, 4.4×; 25 = 식별 문턱, 4 단위 = JND) [A]
- **S5** Vision3: rms-vs-density **곡선만** 공개, 단일 수치 없음 [A]

### 6.10 컬러 — 스톡별

| 스톡 | 그레인 | 대비 | 색 시그니처 | 관용도 | 상태 |
|---|---|---|---|---|---|
| Velvia 100 (AF3-202E) | **8**(S1) A, 해상 80/160 A | Provia 보다 높음; V50(RMS 9)보다 하이라이트 밝고 단단, 토우/숄더 급 C | "world's highest level of color saturation" A; **V50 보다 적/마젠타 편향 강함**(암석·피부가 불그스름-보랏빛), 녹·갈색이 적색보다 잘 나옴 C | push/pull −½~+1, 장면 따라 +2 A | 미국 2021 단종 A |
| E100VS (E-163) | **11**(S2) A | E100G/E100 보다 채도·대비 모두 높음 B. 현행 E100 = "low contrast tone scale" A | "most vivid, saturated colors… **neutral gray scale**" A; Velvia 대비 **따뜻한 편향**이 가장 큰 차이, 강한 적색 B | 미공개 | **2012.3 단종** B |
| Astia 100F (AF3-149E) | **7**(S1) A, 해상 60/140 A | **Fujichrome 중 최저** — "Softest tones and subdued colors among FUJICHROME films" A | 피부 "smooth and naturally continuous gradation" A; 거의 중립, 옅은 웜/옐로, 크리미 하이라이트 C | **−½ ~ +2 stop** 변화 최소 A | 2011 단종 B |
| Kodachrome 64 (E-55) | **10**(S2) A (K25=9, K200=16) | E-6 보다 대비·Dmax 높음 C (감마 미공개 A) | Ektachrome 의 차가운 블루 대비 **따뜻/적색 편향** B; **깊고 색이 없는 그림자**(E-6 는 틴트가 낌) B; 블루는 Velvia 보다 절제 C | 미공개 A; PKR 은 push 비권장 A | 2009 단종, K-14 2010.12 종료 B |
| Gold 200 (E-7022) | **PGI 44**(S4) A | 중간 | 따뜻/금빛, 황-주황-적 강조, 피부는 주황보다 장밋빛, 들린 그림자 B | **−2 / +3 stop** A | 현행 A |
| Pro Image 100 | **PGI 43**(S4) B | 중상, Gold 와 유사하게 인화 B | "high color saturation, accurate color and pleasing skin-tone" B; 설계 목적 = **인물/행사 + 고온다습 상온 보관** B | "good underexposure latitude" B | 현행 A |
| Superia X-TRA 400 (AF3-151E) | **4**(S3) A, 해상 50/125 A | 중간 C | "vibrant and dynamic reds, blues and yellows", 보라·녹 강화, 4th Color Layer A; **녹색 그림자(언더에서 악화) + 마젠타 중간톤/피부** B; 데이터시트: "slight blue cast may appear in **overexposed** areas" A | 미공개 A | **2024.4 전 시장 단종** B |
| Superia Premium 400 (JP) | **4**(S3) A, 해상 50/125 A | 동일 계열 A | ⚠ **층 구조도상 감광층 3개뿐 — 4번째 시안층 없음** A. 새 유제로 관용도를 넓혀 "과노출에서도 색이 선명", **일본인 피부톤**에 맞춤 A | 넓힌 관용도(수치 없음) A | 현행, 일본 전용 B |
| Superia 200 (AF3-008E) | **4**(S3) A, 해상 50/125 A | 저감도 형제 A | "great vividness across the entire spectrum" A. **4th layer 주장 없음** A | 미공개 A | 유제 ~2017 단종; 현 "Fujifilm 200" 은 Kodak 제조설 B |
| Reala 100 (AF3-967E) | **4**(S3) A, 해상 **63/125**(계열 중 최고) A | "Soft Gradations" A — 계열 중 가장 부드러움 B | **4번째 = 시안 감광층 + DIR 커플러**, 목적은 **형광등/혼합광 녹색 캐스트 보정**(일반 채도 향상이 아님) A/B; "Greater Underexposure Latitude" A | 미공개 A | 35mm 2012 / 120 2013 단종 B |
| Fujicolor Industrial 100 | 대용(Fujicolor 100 JP): **4**(S3), 해상 63/125 A | — | **독립 데이터시트 없음** B. 대용 스펙: New Super Uniform Fine Grain, 피부색 개선, **하이라이트→섀도 중립 그레이 밸런스** A; 통설은 차갑고 적·녹 우세, 인물보다 풍경/건축 C | 미공개 | 2020 단종 B |
| Lomography CN 800 | **미공개** A | — | **제조사 데이터시트 없음** A. Kodak 도포 C-41(Vision3 아님) B; 통제 시험에서 Portra 800 과 입자 일치 B; 탁한 웜(황-녹) 캐스트, 적색 감도 → 분홍 피부 C | "best-in-class underexposure latitude", 1600 push 가능(제조사 주장) B | 현행 A |
| Vision3 500T (H-1-5219) | 곡선만(S5) A | **계열 중 최저 대비** B | "outstanding skin tones" A; DLT = 그림자 그레인 감소, Sub-Micron = **하이라이트 관용도 2스톱 확장** A; 통설 에뮬레이션: 차가운/시안 그림자 + 따뜻한 중간톤 피부 C | 브로슈어 스톱 지도상 **≈11 스톱** A | 현행 A |
| Vision3 250D (H-1-5207) | 곡선만 A | **계열 중 최고 대비** B | 동일 DLT/Sub-Micron A; 사용자: 풍부한 대비, 깊은 검정, 마젠타/황/적 감도 C | 계열 공통 A | 현행 A |
| Vision3 50D (H-1-5203) | 곡선만 A; **Kodak 영화용 중 최미립** A | **계열 중 최고 채도** B; 그레이딩에서 유일하게 눈에 띄게 다름 B | "pristine, clean images full of color and detail", "unrivalled highlight latitude" A | 확장 A | 현행 A |
| Vision3 200T (H-1-5213) | 곡선만 A | 계열 중간; "image structure of a 100-speed film" A | 계열 통일 룩에 맞추도록 설계 A | 계열 공통 A | 현행 A |

### 6.11 컬러 — Vision3 헐레이션 (가장 중요한 발견)

- Vision3 는 전통적으로 **remjet**(베이스 뒷면 카본 백킹, 1934년 발명)으로 안티할레이션 +
  대전방지 + 스크래치 보호를 했다. 스틸 필름은 대신 **유제 아래 안티할레이션 언더코트(AHU)**
  를 쓴다. 이 앞/뒤 차이가 "Vision3 가 스틸 필름과 무엇이 다른가" 의 답이다. [A]
- **2025년 8월 Kodak 은 4개 코드(5/7219, 5/7213, 5/7207, 5/7203) 전 포맷에서 remjet 을 없애고
  AHU 로 교체**했다(어두운 갈색·광택·젤 기반·은 함유, 유제 아래 코팅). 즉 Vision3 가 스틸
  필름 구조로 옮겨 갔다. Kodak: 감광 특성 변화 없음. 2026-03 데이터시트에 명기. [A]
- **엔진에 중요:** 진짜 Vision3 는 remjet 이든 AHU 든 **붉은 글로우를 만들지 않는다.**
  그 룩은 **CineStill** 의 것이다 — remjet 을 *제거*해서 안티할레이션이 사라진 결과다.
  "Vision3 헐레이션" 을 강한 적색 블룸으로 인코딩하면 CineStill 을 재현한 것이 된다. [B]

### 6.12 컬러 — 텅스텐/데이라이트는 WB 후 시그니처가 없다

Kodak 은 T 를 3200K, D 를 5500K 로 명시하고 **최종 색 밸런싱은 포스트에서** 한다고 적는다
(500T/200T 는 무보정 ±200K 허용). [A] 따라서 WB 정규화 이후 T/D 구분 **자체는 남는 시그니처가
없다.** 실제로 남는 것은 순서대로:

1. **대비 순위**: 250D > 200T ≈ 50D > 500T
2. **채도 순위**: 50D 최고
3. **그레인 진폭**(밀도 의존 곡선): 50D << 200T < 250D < 500T
4. 계열 공통 형태: 부드러운 숄더 + 하이라이트 여유 약 2스톱, 낮은 섀도 그레인, 약 11스톱 범위

Kodak 이 200T 를 계열과 **맞추도록** 설계했다고 명시하므로, 스톡별 hue 회전은 근거가 약하다. [A/B]

### 6.13 컬러 — Kodachrome 64 의 구조적 원인

비발색(non-substantive): **필름 안에 커플러가 없고**, K-14 각 단계에서 용액이 공급하는
커플러와 산화 현상주약으로 염료가 형성된다. 유제에 커플러 입자가 없어 해상력이 높고
**잔류 컬러 마스크가 없다**. 잔류 은 하위층이 마이크로 대비와 염료 안정성의 원인으로 지목된다.
[A/B] 렌더 차이: Ektachrome 의 차가운 블루 대비 **따뜻/적색 편향**, **색이 없는 깊은 그림자**
(E-6 는 틴트가 낌), 높지만 통제된 채도, 절제된 블루. [B/C]
**실무:** Ektachrome 유도 프로파일을 그대로 쓰면 중간톤·그림자가 시안-블루로 틀어진다.
자체 변환이 필요하다. [B]

### 6.14 미공개 확인 (재검색해도 안 나옴)

- 컬러 16종 전부: **채널별 감마/평균 계조 미공개** — Fuji·Kodak 모두 D-logE 곡선만 발행.
- 관용도 스톱 수치: **Gold 200(−2/+3)** 과 **Vision3 500T(브로슈어 스톱 지도)** 만 공개.
- Vision3 단일 rms 수치: 미공개.
- Pro Image 100 1차 PDF: 취득 불가(Kodak 경로 사망).
- Ilford 전 라인 RMS·해상력·MTF: **제조사가 발행하지 않음**(부재를 A등급으로 확인).
- Tri-X 해상력, 모든 필름의 파장별 상대 log 감도 수치, Kentmere Pan 400 의 분광·입상·해상 전부.

---

## 7. 참고 문서

- `docs/research/film-simulation/01-color-negative-still.md`
- `docs/research/film-simulation/02-color-slide.md`
- `docs/research/film-simulation/03-color-motion-picture.md`
- `docs/research/film-simulation/08-digital-bw-branch-plan.md` — 분기 설계안(구현 전 작성).
  3.3절 "파이프라인 삽입 지점" 은 여전히 유효한 지도이나, 최종 구현은 10번 단계 luma 붕괴를
  **건너뛰지 않고 그대로 두는** 쪽을 택했다(이미 중립이라 항등).
