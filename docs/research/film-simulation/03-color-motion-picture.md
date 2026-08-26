# 03. 컬러 영화용 필름 (Color Motion Picture Film)

[Docs home](../../README.md)

> 조사 상태: **부분 완료 (예산 제약으로 중단)**
> 최종 갱신: 2026-08-09
> 1차 출처 확보 방식: Kodak 공식 기술자료 PDF(H-1-xxxx / TI-xxxx) 직접 다운로드 후 텍스트 추출.
> Fujifilm·기타 제조사는 웹 검색 요약 수준까지만 확보했습니다.

## 0. 신뢰도 등급 정의

| 등급 | 의미 |
|---|---|
| A | 제조사 데이터시트에 **숫자로 명기**된 값 |
| B | 데이터시트의 **곡선(그래프) 판독** 필요 — 본 문서에서는 숫자 미기재 |
| C | 독립 출처 3곳 이상 교차 확인 |
| D | 단일 출처 |
| — | 미확인 / 데이터 없음 |

**중요**: 본 문서의 모든 "데이터 없음"은 실제로 확인하지 못했다는 뜻이며, 추정치를 채워 넣지 않았습니다.

---

## 1. 요약 표

### 1-1. Kodak 카메라 네거티브 (ECN-2)

| 필름 | 코드(35/16mm) | EI (텅스텐 3200K) | EI (데이라이트 5500K) | 밸런스 | 공정 | 상태 | RMS granularity | 신뢰도 |
|---|---|---|---|---|---|---|---|---|
| VISION3 50D | 5203 / 7203 | 12 (80A) | **50** | Daylight | ECN-2 | 생산 중 | 데이터 없음(곡선만) | A(EI) |
| VISION3 250D | 5207 / 7207 | 데이터 없음 | **250** | Daylight | ECN-2 | 생산 중 | 데이터 없음(곡선만) | A(EI) |
| VISION3 200T | 5213 / 7213 | **200** | 데이터 없음 | Tungsten | ECN-2 | 생산 중 | 데이터 없음(곡선만) | A(EI) |
| VISION3 500T | 5219 / 7219 / SO-219 | **500** | **320** (85) | Tungsten | ECN-2 | 생산 중 | 데이터 없음(곡선만) | A(EI) |
| VISION2 50D | 5201 / 7201 | 12 (80A) | **50** | Daylight | ECN-2 | 단종 | 데이터 없음(곡선만) | A(EI) |
| VISION2 100T | 5212 / 7212 | **100** | 64 (85) | Tungsten | ECN-2 | 단종 | 데이터 없음(곡선만) | A(EI) |
| VISION2 200T | 5217 / 7217 | **200** | 125 (85) | Tungsten | ECN-2 | 단종 | 데이터 없음(곡선만) | A(EI) |
| VISION2 250D | 5205 / 7205 | 64 (80A) | **250** | Daylight | ECN-2 | 단종 | 데이터 없음(곡선만) | A(EI) |
| VISION2 500T | 5218 / 7218 / SO-218 | **500** | **320** | Tungsten | ECN-2 | 단종 | 데이터 없음(곡선만) | A(EI) |
| VISION2 Expression 500T | 5229 / 7229 | **500** | 320 (85) | Tungsten | ECN-2 | 단종 | 데이터 없음(곡선만) | A(EI) |
| VISION2 500T (Vision-look) | 5260 | **500** | **320** | Tungsten | ECN-2 | 단종 | 데이터 없음(곡선만) | A(EI) |
| VISION 250D | 5246 / 7246 | 64 (80A) | **250** | Daylight | ECN-2 | 단종 | 데이터 없음(곡선만) | A(EI) |
| VISION 200T | 5274 / 7274 | **200** | 125 (85) | Tungsten | ECN-2 | 단종 | 데이터 없음(곡선만) | A(EI) |
| VISION 320T | 5277 / 7277 | **320** | 200 (85) | Tungsten | ECN-2 | 단종 | 데이터 없음(곡선만) | A(EI) |
| VISION 500T | 5279 / 7279 | **500** | 320 (85) | Tungsten | ECN-2 | 단종 | 데이터 없음(곡선만) | A(EI) |
| VISION 500T (저대비) | 5263 / 7263 | **500** | 320 (85) | Tungsten | ECN-2 | 단종 | 데이터 없음(곡선만) | A(EI) |
| EXR 50D | 5245 / 7245 | 데이터 없음 | Daylight balanced | Daylight | ECN-2 | 단종 | **Less than 5** | **A** |
| EXR 100T | 5248 / 7248 | 데이터 없음 | 데이터 없음 | Tungsten | ECN-2 | 단종 | **Less than 5** | **A** |
| EXR 200T | 5293 / 7293 | 데이터 없음 | 데이터 없음 | Tungsten | ECN-2 | 단종 | **Less than 5** | **A** |
| EXR 500T | 5298 | 데이터 없음 | 데이터 없음 | Tungsten | ECN-2 | 단종 | 곡선 참조 | A(RP만) |

> EXR 계열의 "Less than 5"는 **net diffuse visual density 1.0**, **48 µm aperture** 조건의 Diffuse RMS Granularity 값입니다(데이터시트 각주 명기).

### 1-2. Kodak 리버설 / 인터미디에이트 / 프린트

| 필름 | 코드 | 종류 | 공정 | 자료 번호 | 신뢰도 |
|---|---|---|---|---|---|
| EKTACHROME 100D | 5285 | 컬러 리버설 카메라 | 데이터 없음 | H-1-5285 (2000-01) | A(EI) |
| EASTMAN EKTACHROME (Daylight) | 7239 | 컬러 리버설 | 데이터 없음 | H-1-5239 (1999-02) | D |
| EASTMAN EKTACHROME High-Speed Daylight | 7251 / 2253 | 컬러 리버설 | 데이터 없음 | H-1-7251t (2004-04) | D |
| EXR Color Intermediate | 2244 / 5244 / 7244 | 인터미디에이트 | 데이터 없음 | H-1-5244 (1999-03) | A(정성) |
| VISION3 Color Digital Intermediate | 5254 / 2254 | DI 인터미디에이트 | 데이터 없음 | H-1-5254t (2012-08, 2015-07) | A(정성) |
| Color Internegative | 2273 / 3273 | 인터네거티브 | 데이터 없음 | H-1-2273t (2015-07) | A(정성) |
| VISION3 Digital Separation | 2237 | B&W 세퍼레이션 | 데이터 없음 | H-1-2237t (2015-07) | A(정성) |
| Panchromatic Separation | 2238 | B&W 세퍼레이션 | 데이터 없음 | TI2404 (2015-07) | A(정성) |
| EXR Color Print | 5386 / 7386 / 2386 / 3386 | 프린트 | ECP-2 계열 | H-1-5386 (1999-02) | A(정성) |
| **VISION Color Print** | **2383 / 3383** | 프린트 | **ECP-2D** | H-1-2383t (2005-03, 2015-07) | **A** |
| **VISION Premier Color Print** | **2393** | 프린트 | **ECP-2B** | H-1-2393t (1998-09) | **A** |
| Fine Grain Release Positive | 5302 / 7302 | B&W 프린트 | 데이터 없음 | H-1-5302 (1999-02) | A(정성) |

### 1-3. Fujifilm 카메라 네거티브 (ECN-2, 전 제품 단종)

| 필름 | 35mm / 16mm | EI | 밸런스 | 도입 | 사이드프린트 | 신뢰도 |
|---|---|---|---|---|---|---|
| ETERNA Vivid 160 | 8543 / 8643 | 160 | Tungsten | 2007 | FN43 | C |
| ETERNA 250T | 8553 / 8653 | 250 | Tungsten | 2006 | FN53 | D |
| ETERNA 250D | 8563 / 8663 | 250 | Daylight | 2006 | FN63 | C |
| ETERNA Vivid 250D | 8546 / 8646 | 250 | Daylight | 2010 | 데이터 없음 | D |
| ETERNA 400T | 8583 / 8683 | 400 (데이라이트 250, 85 필터) | Tungsten | 2005-03 (2011-07 단종) | FN83 | C |
| ETERNA 500T | 8573 / 8673 | 500 (데이라이트 320, 85 필터) | Tungsten | 2004 | FN73 | C |
| ETERNA Vivid 500 | 8547 / 8647 | 500 | Tungsten | 2009 | 데이터 없음 | D |

> Fujifilm은 2013년에 영화용 필름 생산을 완전히 중단했습니다(신뢰도 C).
> 1차 출처는 **FUJIFILM MOTION PICTURE FILM MANUAL** PDF이며, 스톡별 페이지가 배정되어 있습니다:
> ETERNA Vivid 160 p.10, ETERNA 250 p.14, ETERNA 400 p.18, ETERNA 500 p.22, F-64D p.26, ETERNA 250D p.30.
> 각 섹션에 분광 감도 / 특성곡선 / MTF / 분광 염료 농도 그래프가 수록되어 있으나, **본 조사에서는 PDF 본문 수치를 아직 추출하지 못했습니다.**

---

## 2. 카메라 네거티브 상세

### 2-1. Kodak VISION3 계열 (현행 제품)

VISION3 4종은 데이터시트 문구가 거의 동일하며, 공통 아키텍처를 공유합니다.

#### 공통 사양 (A등급, H-1-5203t / H-1-5207t / H-1-5213t / H-1-5219)
- **베이스**: acetate safety base with **rem-jet backing** (전 기종 동일)
- **공정**: Process ECN-2 (Kodak Publication H-24.07 Module 7)
- **암실**: 세이프라이트 사용 불가, 완전 암흑에서 취급
- **보관**: 미노광 13°C(55°F) 이하 / 장기 −18~−23°C(0~−10°F), RH 50% 미만
- **상호법칙불궤(reciprocity)**: **1/1000초 ~ 1초 구간에서 필터·노출 보정 불필요** (5203, 5219 명기)
- **식별**: 현상 후 제품 코드 + emulsion/roll/strip 번호 + KEYKODE + 제조사 코드(5219는 `EJ`)가 필름 길이 방향에 노출

#### VISION3의 두 가지 핵심 기술 (데이터시트 원문, A등급)
1. **Dye Layering Technology (DLT)**
   원문: *"The proprietary, advanced Dye Layering Technology (DLT) provides noticeably reduced grain in shadows, allowing you to pull out an amazing amount of shadow detail."*
   → **암부 그레인 저감**이 목적. 시뮬레이션 관점에서는 "저밀도(암부) 영역의 σD 감소"로 해석해야 합니다.
2. **Sub-Micron Technology**
   원문: *"The proprietary Sub-Micron Technology enables **2 stops of extended highlight latitude**, so you can follow the action into bright light—in a single shot—without worrying about blown-out details."*
   → **명부 관용도 +2 stop**. 이것이 VISION3를 VISION2와 구분 짓는 결정적 차이입니다.

- DI 관련 원문: *"The improved grain provides better signal to noise capabilities allowing the colorist to provide greater detail in shadows, while the extended highlight latitude enables improved digital 'dodging and burning'."*
- **스캐닝 경고 (중요)**: *"If traditional 10-bit scanner data encoding schemes are used to digitize films having this extended density range, highlight information captured on these films could be lost."*
  → Kodak은 별도 문서 *Scanning Recommendations for Extended Dynamic Range Camera Films* 를 제공합니다. VISION3의 확장 밀도역은 기존 Cineon 10-bit 인코딩 범위를 넘어섭니다.
- **노출 스케일 확장**: VISION3의 특성곡선 x축(camera stops) 스케일이 이전 VISION/VISION2의 0–4에서 **0–5로 확장**되었습니다(명부 관용도 측정 영역 확보 목적). 신뢰도 C.

#### 개별 사양

**VISION3 50D — 5203 / 7203 (H-1-5203t, 2015-07)**
- EI: Daylight (5500K) **50**, Tungsten (3200K) **12** (80A 필터)
- 조명 불명 시 CC 필터 사용 시 EI **25** 옵션 명기
- Kodak 마케팅 문구: *"the world's finest grain film"*, *"the world's finest grain to ensure a pristine, clean image"*
- 데이터시트 설명: *"unrivaled highlight latitude, flexibility in postproduction, and proven archival stability"*, *"expanded dynamic range ... especially high contrast daylight exteriors"*, *"ideal for recorder output"*
- **관용도(A등급, 데이터시트 특성곡선 주석)**:
  - x축 `0` = 18% 그레이카드 정상 노출
  - **화이트 카드 = +2⅓ stop**, 그 위로 **최소 +3½ stop**의 스페큘러 하이라이트 디테일 여유
  - **3% 블랙 카드 = −2⅔ stop**, 그 아래로 **최소 −2½ stop**의 섀도우 디테일 여유
  - → 대략 **약 11 stop 이상**의 기록 범위를 의미하나, Kodak이 "총 latitude = N stop"으로 직접 명기하지는 않았습니다.
- RMS granularity: 곡선만 제공(48 µm aperture microdensitometer). 수치 **데이터 없음**
- 해상력(lines/mm): **데이터 없음** — 현행 VISION3 데이터시트는 resolving power 표를 싣지 않습니다.

**VISION3 250D — 5207 / 7207 (H-1-5207t, 2015-07)**
- EI: Daylight (5500K) **250**
- DLT + Sub-Micron Technology 2 stop 명기(5219와 동일 문구)
- 데이터시트 설명: *"outstanding skin tones and color reproduction"*
- RMS / 해상력: **데이터 없음(곡선만)**

**VISION3 200T — 5213 / 7213 (H-1-5213t, 2015-07)**
- EI: Tungsten (3200K) **200**
- 핵심 문구: *"provides the image structure of a 100 speed film with the versatility of a 200 speed product—offering you the benefits of two films in one."*
  → **200T이지만 이미지 구조(그레인/샤프니스)는 100T급**이라는 것이 이 스톡의 정체성입니다.
- *"performs superbly in both controlled interiors and in challenging high-contrast exteriors"*
- RMS / 해상력: **데이터 없음(곡선만)**

**VISION3 500T — 5219 / 7219 / SO-219 (H-1-5219, 2022-03 개정)**
- EI: Tungsten (3000K/3200K) **500**, Daylight (5500K) **320** (WRATTEN 2 / 85 필터)
- **광원별 EI 표 (A등급 원문)**:

  | 광원 | 카메라 필터 | EI |
  |---|---|---|
  | Tungsten 3000 K | 없음 | 500 |
  | Tungsten 3200 K | 없음 | 500 |
  | KINO FLO 29 / 32 | 없음 | 500 |
  | Daylight 5500 K | WRATTEN 2 / 85 | 320 |
  | Metal Halide | WRATTEN 2 / 85 | 320 |
  | H.M.I. | WRATTEN 2 / 85 | 320 |
  | KINO FLO 55 | WRATTEN 2 / 85 | 320 |
  | Fluorescent, Warm White | CC30R + CC05M | 320 |
  | Fluorescent, Cool White | CC40R | 160 |
  | 광원 불명 | CC30R + CC20Y | 250 |

- **컬러 밸런스 허용 폭**: 3200K ±200K 범위는 보정 필터 없이 촬영 가능(포스트에서 최종 밸런싱). → 시뮬레이션에서 텅스텐 스톡의 화이트 밸런스는 "정확히 3200K"가 아니라 **3000–3400K 밴드**로 두는 것이 데이터시트에 부합합니다.
- 노출 표(24 fps, 180° 셔터): f/1.4 = 5 fc, f/2 = 10, f/2.8 = 20, f/4 = 40, f/5.6 = 80, f/8 = 160, f/11 = 320, f/16 = 640 footcandles
- 워밍업 시간: 35mm 3~5시간(8~39°C 상승 기준)
- RMS / 해상력: **데이터 없음(곡선만)**

### 2-2. Kodak VISION2 계열 (전 기종 단종)

공통 데이터시트 문구(A등급):
> *"All VISION2 Films offer excellent tone scale and flesh-to-neutral reproduction while maintaining neutrality through the full range of exposures."*
> *"The VISION2 Film family is the first line of products created specifically for both film and digital postproduction."*

→ VISION2의 설계 목표는 **노출 전 범위에 걸친 중립성(neutrality) 유지**입니다. VISION3의 "명부 +2 stop"과 달리 VISION2의 차별점은 **크로스오버 억제**입니다. 시뮬레이션에서 VISION2와 VISION3의 차이를 만들 때 이 지점이 핵심 축이 됩니다.

| 필름 | 자료 번호 | 데이터시트 핵심 문구 |
|---|---|---|
| 5201 50D | H-1-5201t (2005-08) | *"expansive dynamic range that delivers more detail in shadow areas—even in high contrast situations"*, *"ideal for recorder output"* |
| 5205 250D | H-1-5205t (2004-08) | *"beautiful fleshtones, accurate color reproduction, and—thanks to its wider latitude—increased detail in shadow and highlight areas"*, 혼합 광원 대응 강조 |
| 5212 100T | (브로슈어) | *"is **the sharpest color negative motion picture film**"*, *"extremely fine grain"*, VFX/디지털 합성 최적화 |
| 5217 200T | (브로슈어) | *"highly versatile and reliable. Offering excellent image structure under a wide variety of lighting conditions"*, VFX 엣지 품질 강조 |
| 5218 500T | H-1-5218t (2006-03) | *"the finest grain available in a 500T product"*, *"toe speed has been optimized to give enhanced shadow detail and improved shadow neutrality"*, **"The curve shape of this film is very linear"** |
| 5229 Expression 500T | (브로슈어) | *"a subdued range of contrast and color saturation for smooth skin tones"*, *"greatly reduced grain and superior shadow detail"* |
| 5260 500T | H-1-5260t (2008-06) | *"rich and vivid color reproduction similar to the look of our VISION platform ... but with ... VISION2 technology: tighter grain and consistent color reproduction through a range of exposures"* |

**시뮬레이션에 직결되는 포인트**
- **5218**은 *very linear* 곡선 + 토 스피드 최적화 → 직선부 감마가 가장 일정하고 암부 중립성이 좋은 500T. "표준 500T" 레퍼런스로 적합합니다.
- **5229 Expression**은 같은 500 감도에서 **대비·채도를 의도적으로 낮춘** 변형입니다. 5218 대비 "저대비/저채도" 델타로 구현하는 것이 구조적으로 맞습니다.
- **5260**은 VISION2 그레인 + VISION(1세대) 색감이라는 하이브리드 포지션입니다. 즉 Kodak 스스로 "VISION 1세대 색 = 더 rich/vivid", "VISION2 색 = 더 consistent/neutral"로 구분하고 있습니다(A등급, 데이터시트 원문 근거).

### 2-3. Kodak VISION (1세대) 계열

| 필름 | 자료 번호 | EI | 핵심 문구 |
|---|---|---|---|
| 5246 / 7246 VISION 250D | H-1-5246t (2003-03) | D250 / T64(80A) | *"grain structure and sharpness you associate with slower speed stocks"*, *"Rich black shadows"* |
| 5274 / 7274 VISION 200T | TI2325 (rev 2001-06) | T200 / D125(85) | *"a **modified T-grain technology**"*, *"wide exposure range, providing excellent highlight and shadow detail, with a rich reproduction of blacks"*, *"hue accuracy and color saturation ... accurate and balanced color reproduction across the exposure scale"*. 데이터시트: *"In VISION 200T Film, the measured granularity is very low."* |
| 5277 / 7277 VISION 320T | H-1-5277t | T320 / D200(85) | ***"A LOOK THAT'S SOFTER. DIFFERENT."*, *"Softer. More pastel."*** *"very wide latitude that lets you see deep, deep into the shadows without losing the highlights"*. 데이터시트: *"In VISION 320T Film, the measured granularity is very low."* |
| 5279 / 7279 VISION 500T | H-1-5279 (1996-03) | T500 / D320(85) | *"Rich black shadows. Clean white highlights. Lively colors. And excellent flesh-to-neutral reproduction."* |
| 5263 / 7263 VISION 500T | H-1-5263tx (2002-01) | T500 / D320(85) | ***"our lowest contrast 500T film stock"*, *"a subdued color palette"*** *"true blacks, pure whites, and an excellent flesh-to-neutral balance"* |

**5263 vs 5279 (A등급, 데이터시트 직접 비교 문구)**
- MTF: *"[MTF of] 5263/7263 500T Color Negative Film is **less than** that of KODAK VISION 500T Color Negative Film / 5279, 7279. This can be expected with a **softer color, low contrast film**."*
- 그레인: *"In KODAK VISION 5263/7263 ... the measured granularity is very low and is **similar to** KODAK VISION 500T Color Negative Film / 5279, 7279."*
→ 즉 **5263 = 5279와 같은 그레인, 더 낮은 대비, 더 낮은 샤프니스**. 시뮬레이션에서 두 스톡을 구분하는 파라미터가 명확히 정의됩니다.

**1세대 VISION 라인의 룩 축 정리**
- 5277 320T = "softer / more pastel" (저채도·저대비 방향)
- 5263 500T = "lowest contrast / subdued palette" (더 극단적인 저대비)
- 5279 500T = "lively colors / rich blacks" (표준 대비)
- 5274 200T = "hue accuracy + saturation, rich blacks" (정확도 지향)

### 2-4. Kodak EXR 계열 — **유일하게 정량 수치가 공개된 세대**

EXR 데이터시트는 현행 VISION3와 달리 **RMS granularity와 resolving power를 숫자로 명기**합니다. 시뮬레이션의 그레인/해상력 스케일 기준점으로 매우 중요합니다.

| 필름 | 자료 번호 | Diffuse RMS Granularity¹ | Resolving Power² TOC 1.6:1 | TOC 1000:1 | 신뢰도 |
|---|---|---|---|---|---|
| EXR 50D 5245 / 7245 | H-1-5245 (1999) | **Less than 5** | **50 lines/mm** | **100 lines/mm** | A |
| EXR 100T 5248 / 7248 | H-1-7248 | **Less than 5** | **80 lines/mm** | **160 lines/mm** | A |
| EXR 200T 5293 / 7293 | H-1-5293 (1999) | **Less than 5** | **50 lines/mm** | **100 lines/mm** | A |
| EXR 500T 5298 | TI2082 (rev 1993-10) | 곡선 참조 | **ISO RPL 50 lines/mm** | **ISO RP 100 lines/mm** | A |

¹ *Read at a net diffuse visual density of 1.0, using a 48-micrometre aperture.*
² *Determined according to a method similar to the one described in ISO 6328-1982.*

> **주의**: 5245(ISO 50)와 5293(ISO 200)의 해상력이 50/100으로 동일하고, 5248(ISO 100)만 80/160으로 두 배입니다. 이는 오탈자가 아니라 각 데이터시트에 그대로 기재된 값입니다. 감도-해상력 단조 관계를 가정하면 안 됩니다.

**EXR 계열 정성 특성 (데이터시트 원문)**
- 5245 EXR 50D: *"micro-fine grain, very high sharpness, and high resolving power. It features wide exposure latitude and accurate tone reproduction. The emulsion contains a **colored-coupler mask** for good color reproduction in release prints."*
- 5248 EXR 100T: *"micro-fine grain, very high sharpness, and high resolving power. The wide exposure latitude ... especially suitable for both indoor and outdoor photography."*
- 5293 EXR 200T: *"micro-fine grain, very high sharpness, and high resolving power ... wide exposure latitude and accurate tone reproduction."*
- 5298 EXR 500T: *"wide under and over exposure latitude, with **whiter whites**, and accurate color and **flesh-to-neutral** reproduction. **Enhanced shadow detail provides crisper, richer blacks.** ... reproduces a wide range of colors for increased performance in special-effects applications."*

**MTF 측정 조건(5298, TI2082 원문 — 시뮬레이션 시 반드시 유의)**
> *"The film was exposed with the specified illuminant to spatially varying sinusoidal test patterns having an aerial image modulation of a nominal 60 percent at the image plane... **In most cases, the photographic modulation-transfer values are influenced by development-adjacency effects and are not equivalent to the true optical modulation-transfer curve** of the emulsion layer."*
→ 필름 MTF가 100%를 넘는 구간(인접효과/에지 강조)은 실제로 존재하며, 이는 광학 MTF가 아니라 **현상 인접효과(DIR 커플러 유래)** 때문입니다. 필름 샤프닝 시뮬레이션의 물리적 근거입니다.

### 2-5. Kodak 리버설 (영화용)

- **EKTACHROME 100D 5285 (H-1-5285, 2000-01)**: EI Daylight (5500K) **100** / Tungsten (3200K) **25** (80A).
  데이터시트 원문: *"strikingly saturated color performance while maintaining a neutral gray scale and accurate flesh reproduction"*, *"exceptional sharpness that is unsurpassed by any other 100-speed reversal technology"*, *"very strong reciprocity uniformity and keeping stability"*. 공정: **데이터 없음**(미확인).
- **EASTMAN EKTACHROME 7239 (Daylight)** (H-1-5239, 1999-02): 고감도 리버설, **5400K 프로젝션 밸런스** — 즉 현상 원본을 그대로 영사·방송에 쓰는 용도. 뉴스/스포츠/고속촬영용.
- **EASTMAN EKTACHROME High-Speed Daylight 7251 / 2253** (H-1-7251t, 2004-04): 초고감도 리버설, *"medium degree of sharpness"*. 2253은 ESTAR 베이스.

---

## 3. 프린트 / 인터미디에이트 필름 — 룩의 최종 렌더링

### 3-1. 왜 프린트 필름이 "필름 룩"의 본체인가

카메라 네거티브 데이터시트와 프린트 필름 데이터시트를 나란히 놓으면 구조가 드러납니다(A등급, 각 데이터시트 축 범위 직접 확인).

| | 카메라 네거티브 (예: 5245/5293) | 프린트 필름 2383 |
|---|---|---|
| 특성곡선 밀도축 플롯 범위 | 0.0 – 3.0 (일부 4.0) | **0.0 – 6.0** |
| 로그 노출축 플롯 범위 | 약 −1.0 – +1.0 (lux·s) / camera stops −6 – +6 | **−3.0 – +3.0** |
| 덴시토메트리 | **Status M** | **Status A** |
| 공정 | ECN-2 | **ECP-2D** (2383) / **ECP-2B** (2393) |

→ 네거티브는 **저감마 마스터**이고, 극장에서 보는 대비·블랙·채도는 거의 전부 **프린트 필름 단계에서 만들어집니다.** DI 파이프라인에서 "2383 emulation LUT"가 필름 룩의 대명사가 된 이유가 바로 이것입니다. 시뮬레이션 엔진에서도 **네거티브 응답 → 프린트 응답**을 두 단계로 분리해야 물리적으로 맞습니다.

### 3-2. KODAK VISION Color Print Film 2383 / 3383 (H-1-2383t)

- 공정: **ECP-2D**
- 데이터시트 문구: *"The colors you love, the **rich blacks**, and the 'look' you're used to."*, *"the great look you associate with Kodak films, with **rich blacks and neutral highlights**"*, *"durable and resistant to scratches and dirt"*, *"With the excellent tonal scale, cinematographers can be more creative with lighting and exposure"*
- **Laboratory Aim Density (LAD) — A등급 핵심 수치**
  - 프린트 필름의 LAD 패치는 처리된 프린트 상에서 **중성 회색 시각 밀도 1.0 (1.00 Equivalent Neutral Density)** 이 되도록 프린트합니다.
  - Status A 밀도: **R 1.09 / G 1.06 / B 1.03**
  - → **시뮬레이션의 중간 회색 앵커**로 그대로 쓸 수 있는 값입니다. 또한 R>G>B 순의 미세한 오프셋(0.06 스프레드)이 존재한다는 점이 중요합니다. "완벽한 중성 = RGB 동일 밀도"가 아닙니다.
- 특성곡선 측정 조건: *Exposure: 1/500 sec Tungsten + KODAK Heat Absorbing Glass No. 2043 (+ Series 1700 Filter); Process: ECP-2D; Status A Densitometry*
- MTF 측정 조건: *Tungsten 3200 K, ECP-2D, Status A, **35% Modulation Target***
- RMS granularity: 곡선만(Status A, ECP-2D). 축 눈금 표기 `.100 / .050 / .040 / .030` 확인 — 수치 판독은 곡선 필요(B등급 대상)
- 재생 프린터 조건: 1/10초 ~ 약 1/3000초 노광에서 톤 스케일 변화 거의 없음(상호법칙불궤 안정)

### 3-3. KODAK VISION Premier Color Print Film 2393 (H-1-2393t, 1998-09)

프리미어는 2383과 **같은 LAD(R 1.09 / G 1.06 / B 1.03)** 를 쓰지만 **톤 스케일 상단이 다릅니다.** 이것이 두 스톡의 룩 차이의 전부라고 해도 과언이 아닙니다.

- **핵심 원문 (A등급)**:
  > *"The **upper tone scale** of VISION Premier Film is **significantly higher in density** than EASTMAN EXR Color Print Film, so **shadows are deeper, colors are more vivid**, and the image snaps and sizzles on the screen. The **toe areas of the sensitometric curves are matched more closely**, producing **more neutral highlights** on projection."*
- 정리하면 2393 = **(a) 상단 톤스케일 밀도 상승 → 더 깊은 섀도우 + 더 높은 채도**, **(b) 토 영역 3채널 정합 → 하이라이트 중성화**.
  → 시뮬레이션 파라미터로 직역하면 "숄더 게인 상승 + 토 채널 정합"입니다. 임의의 saturation 슬라이더가 아니라 **곡선 상단의 밀도 차이**가 원인입니다.
- 공정: **ECP-2B**
- **필름 구조 (A등급, 층 구성 원문 — 시뮬레이션 층 모델의 근거)**
  베이스로부터: ESTAR Base(120 µm / 0.0047 in) → 서브층 → **Anti-Halation Dye Layer (solid particle dyes)** → **Blue-sensitive (yellow dye)** → interlayer → **Red-sensitive (cyan dye)** → interlayer → **Green-sensitive (magenta dye, 최상단 이미지층)** → SOC(보호층)
  - 뒷면: 도전성 대전방지층 + 폴리머 스크래치 방지 백코팅 + 공정 생존 윤활층
  - **rem-jet 없음** — 프린트 필름은 카메라 네거티브와 달리 remjet을 쓰지 않고 **고체 입자 염료 안티할레이션층**을 유제 아래에 둡니다.
  - 유제층 내부에 **intragrain absorbing dyes**(흡수 염료)가 있어 필름 속도 정밀 제어 + 입자 내 광 산란 감소 → **샤프니스 증가 + 할레이션 추가 억제**. 이 염료가 미현상 유제의 보라-청색을 만들며 현상 중 씻겨 나갑니다.
- 할레이션 관련 원문: *"These dyes offer superior protection against exposure by light reflected back from the support surfaces, **minimizing color fringing** in critical scenes like **white titles and night scenes with automobile headlights**."*
  → 프린트 필름의 헐레이션 억제는 **컬러 프린징** 형태로 나타난다는 점이 명시되어 있습니다.
- 사운드트랙: 같은 사운드 네거티브에서 2393의 프린트 밀도가 2383보다 **약 0.1 높음**(A등급). → 2393의 전반적 밀도 게인이 2383보다 높다는 독립적 근거입니다.
- 아카이브: 실온 50% RH 보관 시 수십 년 후에도 **이미지 염료 손실 10% 미만**
- 베이스: ESTAR(폴리에스터) 전용, 시멘트 스플라이스 불가(테이프/초음파 용접만). 아세테이트 프린트보다 20 µm 얇음.

### 3-4. 인터미디에이트 / 세퍼레이션

- **EASTMAN EXR Color Intermediate Film 2244 / 5244 / 7244 (H-1-5244, 1999-03)**
  - 용도: 컬러 네거티브 → 마스터 포지티브, 마스터 포지티브 → 듀프 네거티브. B&W 실버 세퍼레이션 포지티브로부터 듀프 네거티브 제작도 가능.
  - **원문**: *"It contains an **integral mask similar to the mask in Eastman color negative films but is more red in color**."*
    → 인터미디에이트 마스크는 카메라 네거티브 마스크보다 **더 붉습니다**. 오렌지 마스크 시뮬레이션 시 네거티브/인터미디에이트를 같은 마스크로 처리하면 안 됩니다.
- **KODAK VISION3 Color Digital Intermediate Film 5254 / 2254 (H-1-5254t, 2012-08 / 2015-07)**
  - 원문: *"designed as part of an integrated end-to-end solution, providing a **bridge between** the outstanding performance of KODAK VISION3 Color Negative Films **and** the show quality of KODAK VISION Color Print Films."*
  - ESTAR / acetate 두 베이스 제공.
  - → DI 파이프라인의 정식 경로는 **VISION3 네거티브 → 2254 DI 필름 → 2383 프린트**입니다.
- **KODAK Color Internegative 2273 / 3273 (H-1-2273t, 2015-07)**: 리버설 원본 또는 프린트로부터 인터네거티브 제작용, 색보정 마스킹 보유, ESTAR 베이스, **rem-jet 없음**.
- **VISION3 Digital Separation Film 2237 (H-1-2237t)**: 디지털 레코더 노광용 B&W 아카이브 세퍼레이션. *"fine detail, tight grain, optimal resolution and excellent flare characteristics"*.
- **KODAK Panchromatic Separation Film 2238 (TI2404, 2015-07)**: EASTMAN 5235/SO-202 대체품. *"Improved spectral sensitization gives better color reproduction, **similar to that of EASTMAN EXR Color Intermediate**"*.
- **EASTMAN EXR Color Print Film 5386 / 7386 / 2386 / 3386 (H-1-5386, 1999-02)**: *"extended range tone reproduction, excellent sharpness, fine-grain, superior color reproduction, and excellent dye stability"*. 2393/2383의 직전 세대 기준점입니다.
- **EASTMAN Fine Grain Release Positive 5302 / 7302 (H-1-5302)**: 청감성 B&W 저감도 고해상 프린트 필름, 5.6 mil 클리어 아세테이트.

---

## 4. 특수 현상 룩 (Bleach bypass / ENR / ACE / 크로스 프로세싱)

**본 조사에서 1차 출처를 확보하지 못했습니다.** 다만 Kodak 데이터시트에서 **간접적으로 확인된 사실 1건**이 있습니다.

- **H-1-5219 (VISION3 500T) LAD 섹션 원문 (A등급)**:
  > *"Some specialized films and/or specialized negative processing techniques (**push-processing, pull-processing, 'skip-bleach' processing**, etc.) may require **more extreme adjustment from the LAD printing condition** to attain desired results."*
  → Kodak이 **skip-bleach를 '네거티브 현상 기법'으로 분류**하고 있음이 확인됩니다. 즉 최소한 스킵 블리치는 네거티브 단계에도 적용되는 공정이며, 그 결과 **표준 LAD 프린팅 조건에서 크게 벗어난 보정이 필요**할 만큼 밀도 구조가 달라집니다.

아래 항목은 **모두 미확인 — 데이터 없음**이며, 추정치를 기록하지 않았습니다.
- Bleach bypass의 밀도·채도·그레인 정량 효과: **데이터 없음**
- ENR (Technicolor Italia) 적용 단계 및 은 보유량 제어 방식: **데이터 없음**
- ACE (Deluxe) 사양: **데이터 없음**
- Skip bleach를 네거티브에 적용할 때와 프린트에 적용할 때의 차이: **데이터 없음** (Kodak 문서상 네거티브 적용 사례만 확인)
- ECN-2 필름의 C-41 크로스 프로세싱 결과 특성: **데이터 없음**
- Remjet 제거로 인한 헐레이션의 정량적 특성: **데이터 없음** (단, 프린트 필름 2393의 안티할레이션 설명에서 "할레이션 = 지지체 표면 반사광에 의한 노광, 결과는 **컬러 프린징**"이라는 물리 기술은 확인됨 — A등급)

---

## 5. 파생 스틸 제품 (CineStill 등)

**본 조사에서 확인하지 못했습니다. 전 항목 데이터 없음.**

- CineStill 50D / 400D / 800T: **데이터 없음**
- Flic Film Cine Color / Amber: **데이터 없음**
- Reflx Lab: **데이터 없음**

다만 아래는 **Kodak 데이터시트로 확인된 배경 사실**로, 파생 제품 설계의 전제가 됩니다(A등급).
- Kodak VISION / VISION2 / VISION3 카메라 네거티브는 **전 기종 acetate + rem-jet backing**입니다. 즉 remjet은 예외 없이 존재합니다.
- 반면 Kodak **프린트 필름(2383, 2393)과 인터네거티브(2273)는 remjet이 없고**, 대신 유제 아래의 **고체 입자 염료 안티할레이션층**과 도전성 대전방지층을 사용합니다.
  → "remjet을 제거하면 안티할레이션이 사라진다"는 통설은 **카메라 네거티브에 한해** 성립합니다. Kodak은 프린트 필름에서 remjet 없이도 *"superior halation protection"* 을 달성했다고 명기합니다(2393). remjet 제거 = 무조건 헐레이션이 아니라, **remjet을 대체 층 없이 제거했을 때** 헐레이션이 발생하는 것입니다.
- 또한 remjet 제거의 부수 효과로 Kodak이 명기한 것: 정전기에 의한 먼지 흡착, 프린터 청결도, 프리배스 화학약품·용수 사용량. → 현상 공정 자체에 영향을 줍니다.
- CineStill류가 remjet을 제거한 뒤 **C-41**로 현상되는데, ECN-2 카메라 네거티브에서 rem-jet은 반드시 **prebath 단계**에서 제거되어야 하며(2393 데이터시트가 remjet 없는 프린트 필름의 이점으로 "prebath 화학약품 제거 가능"을 언급), 이를 생략하면 현상기가 오염됩니다. 웹 검색에서도 *"carries a remjet layer, so it can't be dropped off at a standard lab without damaging their processing machine"* 로 재확인됩니다(신뢰도 C).

---

## 6. ECN-2 vs C-41 — 구조적 차이 정리

시뮬레이션 설계의 핵심 섹션입니다. **확인된 것과 미확인을 엄격히 구분**했습니다.

### 6-1. 확인된 구조적 차이 (A등급, Kodak 데이터시트 근거)

| 항목 | ECN-2 영화용 카메라 네거티브 | 비고 |
|---|---|---|
| **안티할레이션** | **rem-jet backing** (카본 블랙 + prebath 가용성 바인더). VISION/VISION2/VISION3 전 기종 확인 | C-41 스틸 필름의 층 구조는 본 문서에서 미확인 — **데이터 없음** |
| **덴시토메트리 표준** | **Status M** (카메라 네거티브 특성곡선의 명시 조건) | 프린트 필름은 Status A. 두 도메인을 섞으면 안 됩니다 |
| **후속 단계 전제** | **프린트 필름(감마 매우 높음)에 인화되는 것을 전제한 저감마 마스터**. LAD로 중간 회색을 프린트 상 **시각 밀도 1.0**에 앵커 | C-41 스틸은 광학 인화 또는 스캔이 종착점. 본 문서에서 C-41 측 근거 미확보 |
| **컬러 마스킹** | colored-coupler mask 보유(EXR 계열 명기). 인터미디에이트 마스크는 **더 붉음** | 마스크 자체는 C-41과 공통 개념 |
| **명부 관용도** | VISION3는 **+2 stop 확장**이 데이터시트에 명기. 10-bit 인코딩 범위를 넘어설 수 있다는 경고까지 포함 | C-41 대비 비교 수치는 **데이터 없음** |
| **노출 기준점** | 데이터시트 x축 `0` = **18% 그레이카드 정상 노출**. 화이트카드 +2⅓ stop, 3% 블랙카드 −2⅔ stop | 시뮬레이션 노출 앵커를 이 정의에 맞춰야 합니다 |
| **컬러 밸런스 허용 폭** | 텅스텐 스톡은 **3200K ±200K 무보정 허용**(포스트 보정 전제) | "필름은 색온도에 엄격하다"는 통념과 다릅니다 |
| **상호법칙불궤** | 1/1000초 ~ 1초 무보정(VISION3 50D, 500T) | |
| **암실** | 세이프라이트 **완전 불가**(전 카메라 네거티브 공통) | |

### 6-2. 시뮬레이션 관점의 결론

1. **2단계 모델이 필수입니다.** ECN-2 네거티브는 그 자체로 "룩"이 완성된 물건이 아닙니다. 밀도축 0–3 범위의 저감마 마스터입니다. 극장 룩은 밀도축 0–6 범위의 프린트 필름(2383/2393)이 만듭니다. 네거티브 응답만 시뮬레이션하고 프린트 응답을 생략하면 "밋밋하다"는 결과가 나오는 것이 물리적으로 당연합니다.
2. **중간 회색 앵커는 LAD 1.0 END (Status A R 1.09 / G 1.06 / B 1.03)** 로 잡을 수 있습니다. 3채널이 정확히 같지 않다는 점이 중요합니다.
3. **채널별 감마 / 직선부 기울기는 전부 데이터 없음**입니다. 현행 Kodak 데이터시트는 감마를 숫자로 공개하지 않고 곡선만 제공합니다. 필요하면 곡선 판독(B등급) 작업이 별도로 필요합니다.
4. **RMS granularity는 EXR 세대만 숫자가 있습니다(<5 @ D=1.0, 48 µm).** VISION/VISION2/VISION3는 전부 곡선 판독이 필요합니다. VISION3의 σD 축 눈금은 2383 데이터시트 기준 `.030 ~ .100` 대역에 표기되어 있음이 확인되었으므로, 판독 시 이 범위를 기대할 수 있습니다.
5. **MTF > 100% 구간은 정상입니다.** Kodak이 명시적으로 *"influenced by development-adjacency effects and are not equivalent to the true optical modulation-transfer curve"* 라고 밝히고 있습니다. 필름 시뮬레이션의 인접효과(에지 강조)는 아티팩트가 아니라 재현 대상입니다.

---

## 7. 권장 우선순위 Top 12

| 순위 | 필름 | 근거 |
|---|---|---|
| 1 | **VISION3 500T 5219** | 현행 최다 사용 스톡. 데이터시트가 2022년 개정본으로 가장 최신이며 DLT/Sub-Micron 기술 설명이 가장 상세. 광원별 EI 표 완비 |
| 2 | **VISION Color Print 2383** | "필름 룩"의 사실상 표준. LAD Status A 수치 확보. 프린트 단계 없이는 어떤 네거티브 시뮬레이션도 완성되지 않음 |
| 3 | **VISION3 250D 5207** | 데이라이트 측 현행 주력. 500T와 동일 기술 세트로 페어 구성 가능 |
| 4 | **VISION3 50D 5203** | 관용도 정의(18% 그레이 기준 +2⅓/−2⅔ stop, 여유 +3½/−2½)가 데이터시트에 유일하게 명문화됨. **노출 앵커 캘리브레이션 기준으로 최적** |
| 5 | **VISION Premier 2393** | 2383과의 차이가 "상단 톤스케일 밀도 상승 + 토 정합"으로 정량 기술됨. 두 프린트 룩의 델타 모델을 만들 수 있는 유일한 쌍 |
| 6 | **VISION3 200T 5213** | "200 감도에 100 감도 이미지 구조"라는 명확한 정체성. 그레인/감도 분리 모델 검증에 유용 |
| 7 | **VISION2 500T 5218** | *"curve shape ... very linear"* + 토 스피드 최적화. **선형 기준선(reference straight-line)** 으로 삼기 가장 적합 |
| 8 | **VISION 500T 5263** | *"lowest contrast 500T"*. 5279와 그레인은 같고 대비·MTF만 낮다는 직접 비교 문구 확보 → **대비 축 단독 검증용** |
| 9 | **VISION 320T 5277** | *"softer / more pastel"* 라는 명시적 저채도 룩. 채도 축 단독 검증용 |
| 10 | **EXR 100T 5248** | RMS <5 + RP 80/160 lines/mm. **정량 그레인·해상력 수치를 가진 유일한 세대 중 최고 해상력** → 스케일 캘리브레이션 기준 |
| 11 | **VISION2 Expression 500T 5229** | 5218 대비 "대비·채도 하향" 변형. 같은 세대 내 룩 델타 모델 검증 |
| 12 | **VISION3 Color DI Film 2254** | 네거티브→프린트 사이의 공식 브리지. 3단계 파이프라인 모델을 정확히 하려면 필요 |

**의도적으로 순위에서 제외한 것**: Fujifilm ETERNA 계열은 룩 가치가 높지만 **본 조사에서 정량 데이터를 전혀 확보하지 못했으므로**(정성 서술도 신뢰도 D 단일 출처) 현 시점 구현 대상으로 올리지 않았습니다. Fujifilm Motion Picture Film Manual PDF 본문 추출이 선행되어야 합니다.

---

## 8. 데이터 공백

### 8-1. Kodak — 확인했으나 수치가 존재하지 않는 항목
- **채널별 감마 / 직선부 기울기**: 전 기종 **데이터 없음**. Kodak은 특성곡선만 제공하며 감마 숫자를 명기하지 않습니다.
- **Dmin / Dmax**: 전 기종 **데이터 없음**. 곡선 플롯 축 범위만 확인 가능(네거티브 0–3/0–4, 프린트 2383 0–6).
- **RMS granularity 수치 (VISION / VISION2 / VISION3)**: **데이터 없음**. 곡선 판독 필요. 판독 절차는 데이터시트에 명기: *"find the density on the left vertical scale → 특성곡선 → 수직 이동 → granularity 곡선 → 우측 Granularity Sigma D 축 → 읽은 값 × 1000"*.
- **Resolving power (VISION / VISION2 / VISION3)**: **데이터 없음**. 현행 데이터시트는 resolving power 표를 삭제하고 MTF 곡선만 남겼습니다.
- **Print Grain Index (PGI)**: 영화용 필름에는 **적용되지 않습니다**. PGI는 스틸 필름용 설문 기반 지표이며, 영화용은 물리적 RMS를 씁니다(신뢰도 C). **영화용 필름의 PGI를 찾으려 하지 마세요.**
- **EXR 500T 5298의 RMS 수치**: 곡선 참조만. **데이터 없음**.
- **EXR 50D 5245 / 100T 5248 / 200T 5293의 EI**: 해당 데이터시트 발췌 구간에서 미확인. **데이터 없음**.

### 8-2. 조사 자체를 못 한 항목 → 9절 참조

---

## 9. 미조사 잔여 목록

예산 제약으로 중단되었습니다. 아래 항목은 **전혀 조사하지 못했거나 1차 출처를 확보하지 못했습니다.**

### 9-1. Kodak
- [ ] Vision 1세대 **5245 / 5248**(Vision 명칭판), **5293 / 5298**(Vision 명칭판) 구분 정리
- [ ] **EXR 5296** — 데이터시트 미확보
- [ ] **Eastman 5254** (구세대), **5247** (ECN-1 → ECN-2 전환) — 미조사
- [ ] **Ektachrome 100D 5294 / 7294** (Vision 시대 영화용 리버설) — 미조사. 본 문서에 수록된 것은 **5285**로 다른 제품입니다
- [ ] **Vision Color Intermediate 2242 / 5242** — 미조사 (본 문서에는 2244/5244와 2254/5254만 수록)
- [ ] **Kodak Aerocolor IV 2460** — 미조사
- [ ] Kodak Publication **H-24.07** (ECN-2 현상 사양), **H-61** (LAD 상세), **H-1** / **H-845** (Essential Reference Guide — image structure 원 데이터 수록 가능성 높음) 미열람
- [ ] *Scanning Recommendations for Extended Dynamic Range Camera Films* 미열람 — VISION3 확장 밀도역의 실제 수치가 담겨 있을 가능성이 큽니다
- [ ] 각 데이터시트 특성곡선 / RMS 곡선 **그래프 판독 작업(B등급 데이터 생성)** 미수행

### 9-2. Fujifilm
- [ ] **FUJIFILM MOTION PICTURE FILM MANUAL** PDF 본문 추출 미수행 — 스톡별 분광 감도 / 특성곡선 / MTF / 분광 염료 농도 수록 확인됨. **최우선 후속 작업**
- [ ] Fujifilm 데이터시트 번호(AF3-xxx 형식) 확인 실패
- [ ] **ETERNA-CP 3513DI**, **F-CP 3510** (프린트 필름) — 미조사
- [ ] **Reala 500D 8592** — 미조사
- [ ] **Super F-64D / F-125 / F-250D / F-500** — 미조사 (F-64D가 매뉴얼 p.26에 있다는 사실만 확인)
- [ ] ETERNA 계열 RMS / 해상력 / 감마 정량치 — 전부 **데이터 없음**

### 9-3. 기타 제조사
- [ ] **ORWO NC500 / NC400** — 미조사
- [ ] **Agfa XT320 / XTS400** — 미조사

### 9-4. 특수 현상
- [ ] Bleach bypass / skip bleach 정량 효과 — 미조사 (Kodak이 skip-bleach를 **네거티브 현상 기법**으로 분류한다는 사실만 확인)
- [ ] **ENR** (Technicolor) / **ACE** (Deluxe) — 미조사
- [ ] ECN-2 → C-41 크로스 프로세싱 특성 — 미조사

### 9-5. 파생 스틸 제품
- [ ] **CineStill 50D / 400D / 800T** — 미조사. 원본 VISION3 대비 차이(remjet 제거 헐레이션, C-41 현상 차이) 전부 **데이터 없음**
- [ ] **Flic Film Cine Color / Amber**, **Reflx Lab** — 미조사

### 9-6. C-41 스틸 필름 측 대조 데이터
- [ ] ECN-2 vs C-41 비교를 완성하려면 C-41 스틸 필름 데이터시트(Portra 등) 측의 층 구조·감마·관용도 수치가 필요합니다. 본 문서는 **ECN-2 측 근거만** 확보한 상태입니다

---

## 10. 확보한 1차 출처 목록

### Kodak 공식 PDF (직접 다운로드 후 텍스트 추출 완료)
- `H-1-5219` VISION3 500T 5219/7219 (2022-03) — kodak.com/content/products-brochures/Film/VISION3_5219_7219_Technical-data.pdf
- `H-1-5203t` (TI2657) VISION3 50D 5203/7203 (2015-07)
- `H-1-5207t` (TI2650) VISION3 250D 5207/7207 (2015-07)
- `H-1-5213t` (TI2653) VISION3 200T 5213/7213 (2015-07)
- `H-1-5201t` VISION2 50D (2005-08) / `H-1-5205t` VISION2 250D (2004-08)
- VISION2 100T 5212 · VISION2 200T 5217 · VISION2 Expression 500T 5229 (제품 브로슈어)
- `H-1-5218t` VISION2 500T (2006-03) / `H-1-5260t` VISION2 500T 5260 (2008-06)
- `H-1-5246t` VISION 250D (2003-03) / `TI2325` VISION 200T 5274 (2001-06) / `H-1-5277t` VISION 320T / `H-1-5279` VISION 500T (1996-03) / `H-1-5263tx` VISION 500T 5263 (2002-01)
- `H-1-5245` EXR 50D (1999) / `H-1-7248` EXR 100T / `H-1-5293` EXR 200T (1999) / `TI2082` EXR 500T 5298 (1993-10)
- `H-1-5285` EKTACHROME 100D 5285 (2000-01) / `H-1-5239` 7239 (1999-02) / `H-1-7251t` 7251·2253 (2004-04)
- `H-1-2383t` VISION Color Print 2383/3383 (2005-03, 2015-07 · TI2397)
- `H-1-2393t` VISION Premier 2393 (1998-09)
- `H-1-5386` EXR Color Print (1999-02) / `H-1-5302` Fine Grain Release Positive (1999-02)
- `H-1-5244` EXR Color Intermediate 2244/5244/7244 (1999-03)
- `H-1-5254t` VISION3 Color DI Film 5254/2254 (2012-08 · 2015-07 TI2651)
- `H-1-2273t` Color Internegative 2273/3273 (2015-07 · TI2655)
- `H-1-2237t` VISION3 Digital Separation 2237 (TI2659) / `TI2404` Panchromatic Separation 2238

미러 아카이브: `125px.com/docs/motionpicture/kodak/`, `.../kodak_2018/`, `.../kodak/lab/`, `.../kodak_guides/`

### Fujifilm / 기타 (검색 요약 수준, 본문 미추출)
- FUJIFILM MOTION PICTURE FILM MANUAL (PDF, theodoropoulos.info · bioskoplab.wordpress.com 미러)
- Evertz `FilmID.pdf` — Film Emulsion Codes Rev 1.14 (2012-05-01), 에멀전 코드/도입일 대조표
