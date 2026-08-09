# 02 — 컬러 리버설(슬라이드) 필름 조사: E-6 / K-14

조사일: 2026-08-09
제외(이미 구현됨): Kodak Ektachrome E100, Fujichrome Provia 100F, Fujichrome Velvia 50

## 0. 조사 방법과 신뢰도 표기

- **A** = 제조사 데이터시트 PDF에서 직접 읽은 수치 (본 문서 수치의 대부분)
- **B** = 데이터시트에 실린 곡선을 판독한 값
- **C** = 독립 출처 3곳 이상 일치
- **D** = 단일 출처

1차 출처는 아래 아카이브에서 원본 PDF를 내려받아 텍스트 추출로 확인했습니다.

- 125px.com Kodak/Fuji 기술문서 아카이브: `https://125px.com/techdocs/kodak/`, `https://125px.com/techdocs/fuji/`
- Kodak Alaris E-4000 (현행 E100): `https://business.kodakmoments.com/sites/default/files/files/products/e4000_ektachrome_100.pdf`
- Kodak E-164 (E100S/SW): `https://www.chrysis.net/wp-content/uploads/2020/08/Ektachrome_E100S_E100SW.pdf`
- Kodak E-27 (EPN): `https://www.cameramanuals.org/kodak_pdf/kodak_ektachrome_100.pdf`
- Agfa "Technical Data — Agfa Professional Films": `https://cacreeks.com/photos/agfaPro.pdf`

**중요한 측정 규약 차이 (시뮬레이션에서 반드시 정규화할 것)**

- Kodak / Fujifilm RMS granularity: gross diffuse visual density **1.0**, 48 µm 조리개 기준. 두 회사 수치는 같은 척도로 비교 가능.
- Agfa RMS granularity: 자체 브로슈어 기준(× 1000)이며 Kodak/Fuji 척도와 **직접 비교 불가**. Agfa RSX II 계열 RMS 10~12는 Kodak "very fine"(11~12)과 우연히 가까운 값이지만 동일 규약 확인은 못 했습니다.
- Kodak Elite Color 200/400(E-4039)은 rms 대신 별도 지표를 쓰며, 데이터시트 본문에 "It replaces rms granularity and has a different scale which cannot be compared to rms granularity"라고 명시되어 있습니다.
- **Dmax**: 본 조사에서 확인한 리버설 데이터시트 중 Dmax를 **숫자로 표기한 것은 하나도 없었습니다.** 모두 특성곡선 그래프로만 제공됩니다(판독=신뢰도 B 작업 필요). 따라서 아래 표의 Dmax 칸은 전부 "데이터 없음"입니다.

---

## 1. 요약 표

### 1.1 Kodak (E-6)

| 필름 | 코드 | ISO | 공정 | 상태 | 데이터시트 | RMS | 해상력 (1.6:1 / 1000:1) | Dmax | 신뢰도 |
|---|---|---|---|---|---|---|---|---|---|
| Ektachrome E100G | E100G | 100 | E-6 | 단종 | E-4024 (2003-07 / 2009-09) | 8 (extremely fine) | 데이터 없음 | 데이터 없음 | A |
| Ektachrome E100GX | E100GX | 100 | E-6 | 단종 | E-4024 | 8 (extremely fine) | 데이터 없음 | 데이터 없음 | A |
| Ektachrome E100VS | E100VS | 100 | E-6 | 단종 | E-163 (2005-09) | 11 (very fine) | 데이터 없음 | 데이터 없음 | A |
| Ektachrome E100S | E100S | 100 | E-6 | 단종 | E-164 | 10 (extremely fine) | 데이터 없음 | 데이터 없음 | A |
| Ektachrome E100SW | E100SW | 100 | E-6 | 단종 | E-164 | 10 (extremely fine) | 데이터 없음 | 데이터 없음 | A |
| Ektachrome E200 | E200 | 200 | E-6 | 단종 | E-28 (2005-09) | 12 (very fine) | 데이터 없음 | 데이터 없음 | A |
| Ektachrome 64 | EPR | 64 | E-6 | 단종 | E-8 (2005-09) | 11 (very fine) | 데이터 없음 | 데이터 없음 | A |
| Ektachrome 100 Plus | EPP | 100 | E-6 | 단종 | E-113 (2007-07) | 11 (very fine) | 데이터 없음 | 데이터 없음 | A |
| Ektachrome 100 | EPN | 100 | E-6 | 단종 | E-27 (2007-07) | 11 (very fine) | 데이터 없음 | 데이터 없음 | A |
| Ektachrome 200 | EPD | 200 | E-6 | 단종 | 데이터 없음 | 데이터 없음 | 데이터 없음 | 데이터 없음 | D |
| Ektachrome 400X | EPL | 400 | E-6 | 단종 | E-161 (2005-09) | 19 (fine) | 데이터 없음 | 데이터 없음 | A |
| Ektachrome P1600 | EPH | 1600 | E-6 (Push 2) | 단종 | E-147 (2007-05) | 34 @EI 1600 (coarse) | 데이터 없음 | 데이터 없음 | A |
| Ektachrome 64T | EPY | 64 | E-6 | 단종 | E-130 (2007-07) | 11 (very fine) | 데이터 없음 | 데이터 없음 | A |
| Ektachrome 160T | EPT | 160 | E-6 | 단종 | E-144 (2007-05) | 13 (very fine) | 데이터 없음 | 데이터 없음 | A |
| Ektachrome 320T | EPJ | 320 | E-6 | 단종 | E-145 (2007-05) | 19 (fine) | 데이터 없음 | 데이터 없음 | A |
| Elite Chrome 100 | EB / EB-3 | 100 | E-6 | 단종 | E-7014E (2005-04) | 8 (extremely fine) | 데이터 없음 | 데이터 없음 | A |
| Elite Chrome Extra Color 100 | EBX | 100 | E-6 | 단종 | E-126E (2005-04) | 11 | 데이터 없음 | 데이터 없음 | A |
| Elite Chrome 200 | ED | 200 | E-6 | 단종 | E-148E (2005-04) | 12 | 데이터 없음 | 데이터 없음 | A |
| Elite Chrome 400 | EL | 400 | E-6 | 단종 | E-149 (1998-01) | 19 | 데이터 없음 | 데이터 없음 | A |
| Elite Color 200 | EC200 | 200 | E-6 | 단종 | E-4039 (2006-05) | rms 미표기(별도 척도) | 데이터 없음 | 데이터 없음 | A |
| Elite Color 400 | EC400 | 400 | E-6 | 단종 | E-4039 (2006-05) | rms 미표기(별도 척도) | 데이터 없음 | 데이터 없음 | A |
| (참고) Ektachrome E100 현행 | E100 | 100 | E-6 | 현행 | E-4000 (2018-08) | 8 (extremely fine) | 데이터 없음 | 데이터 없음 | A |

### 1.2 Kodak (K-14 / Kodachrome)

| 필름 | 코드 | ISO | 공정 | 상태 | 데이터시트 | RMS | 해상력 | Dmax | 신뢰도 |
|---|---|---|---|---|---|---|---|---|---|
| Kodachrome 25 Professional | PKM | 25 | K-14 | 단종 (2009 공지, 현상 2010-12 종료) | E-55 (1996-12 / 2003-08 / 2009-06) | **9** | 데이터시트에 수치 없음(MTF 곡선만) | 데이터 없음 | A |
| Kodachrome 64 Professional | PKR | 64 | K-14 | 단종 | E-55 | **10** | 수치 없음(MTF 곡선만) | 데이터 없음 | A |
| Kodachrome 200 Professional | PKL | 200 | K-14 | 단종 | E-55 | **16** | 수치 없음(MTF 곡선만) | 데이터 없음 | A |
| Kodachrome 64 (소비자용) | KR | 64 | K-14 | 단종 | E-88 (2009-06) | 10 | 수치 없음 | 데이터 없음 | A |
| Kodachrome 200 (소비자용) | KL | 200 | K-14 | 단종 | E-88 (2009-06) | 16 | 수치 없음 | 데이터 없음 | A |
| Kodachrome 25 (소비자용) | KM | 25 | K-14 | 단종 | E-88 (1998-01 / 2002-03) | 데이터 없음(미확인) | 데이터 없음 | 데이터 없음 | — |

### 1.3 Fujifilm (E-6)

| 필름 | 코드 | ISO | 공정 | 상태 | 데이터시트 | RMS | 해상력 (1.6:1 / 1000:1) | Dmax | 신뢰도 |
|---|---|---|---|---|---|---|---|---|---|
| Velvia 100 | RVP100 | 100 | E-6 / CR-56 | 단종 | AF3-202E (2008-03) | **8** | **80 / 160 lines/mm** | 데이터 없음 | A |
| Velvia 100F | RVP100F | 100 | E-6 | 단종 | AF3-148E (2008-03) | **8** | **80 / 160 lines/mm** | 데이터 없음 | A |
| Astia 100F | RAP100F | 100 | E-6 | 단종 (2011) | AF3-149E (2008-03) | **7** | **60 / 140 lines/mm** | 데이터 없음 | A |
| Provia 400X | RXP | 400 | E-6 | 단종 (2013) | AF3-0213E (2007-10) | **11** | **55 / 135 lines/mm** | 데이터 없음 | A |
| Provia 400F | RHP III | 400 | E-6 | 단종 | AF3-066E | **13** | **55 / 135 lines/mm** | 데이터 없음 | A |
| Sensia 100 | RA | 100 | E-6 | 단종 (2010-08) | AF3-091E (2008-03) | **10** | **55 / 135 lines/mm** | 데이터 없음 | A |
| Sensia 200 | RM | 200 | E-6 | 단종 | AF3-080E (2008-03) | **13** | **60 / 140 lines/mm** | 데이터 없음 | A |
| Sensia 400 | RH | 400 | E-6 | 단종 (2010-08) | AF3-091E 계열 (2008-03) | **13** | **55 / 135 lines/mm** | 데이터 없음 | A |
| T64 | RTP | 64 (텅스텐) | E-6 | 단종 | AF3-178E (2008-03) | **7** | **55 / 115 lines/mm** | 데이터 없음 | A |
| 64T Type II | RTP II | 64 (텅스텐) | E-6 | 단종 | AF3-024E | **10** | **55 / 135 lines/mm** | 데이터 없음 | A |
| Fortia SP | — | 50 | E-6 | 단종 (2007) | 미발견 | 데이터 없음 | 데이터 없음 | 데이터 없음 | C |
| (참고) Velvia 50 현행 | RVP50 | 50 | E-6 | 구현됨 | AF3-0221E2 (2008-04) | — | — | — | — |

### 1.4 Agfa / 기타

| 필름 | ISO | 공정 | 상태 | 데이터시트 | RMS(Agfa 척도) | 해상력 (1.6:1 / 1000:1) | Dmax | 신뢰도 |
|---|---|---|---|---|---|---|---|---|
| Agfachrome RSX II 50 Professional | 50 | E-6 / AP 44 | 단종 (2005) | Technical Data Agfa Professional Films | **10.0** | **55 / 125 lines/mm** | 데이터 없음 | A |
| Agfachrome RSX II 100 Professional | 100 | E-6 / AP 44 | 단종 (2005) | 동상 | **10.0** | **50 / 125 lines/mm** | 데이터 없음 | A |
| Agfachrome RSX II 200 Professional | 200 | E-6 / AP 44 | 단종 (2005) | 동상 | **12.0** | **50 / 110 lines/mm** | 데이터 없음 | A |
| Agfa CT Precisa 100 (독일 오리지널) | 100 | E-6 | 단종 (2005) | 미발견 | 데이터 없음 | 데이터 없음 | 데이터 없음 | C |
| AgfaPhoto CT Precisa 100 (리브랜드) | 100 | E-6 | 단종 (2018) | 미발견 (Fujifilm 제조 추정) | 데이터 없음 | 데이터 없음 | 데이터 없음 | C |
| Rollei Digibase CR200 Pro (= Agfa Aviphot Chrome 200 PE1) | 200 | E-6 | 단종 (2016 Q4) | Agfa Aviphot Chrome 200 PE1 데이터시트 | 데이터 없음(미추출) | 데이터 없음 | 데이터 없음 | C |
| (참고) Agfa Scala 200x (흑백 반전, 비교용) | 200 | 전용 | 단종 | Technical Data Agfa Professional Films | 11.0 | 50 / 120 lines/mm | 데이터 없음 | A |

---

## 2. 필름별 상세

### 2.1 Kodak Ektachrome E100G / E100GX — E-4024

- **제조사/공정/상태**: Eastman Kodak / E-6 / 단종. 데이터시트 초판 2003-07, 개정 2009-09.
- **정량 (A)**
  - Diffuse rms granularity **8** (extremely fine), gross diffuse visual density 1.0 / 48 µm.
  - 노출 지수: Daylight·Electronic Flash **100**, Photolamp 3400 K + Wratten 80B **32**, Tungsten 3200 K + 80A **25**.
  - 상반칙불궤: **1/10,000 s ~ 10 s 구간 보정 불필요**. 120 s에서 **CC10R** 추가.
  - 다중 플래시: 4회까지 보정 불필요, 8회에서 CC05M.
  - 푸시: push 1(1st dev 8분) 기준 **EI 200** 노출이 권장 출발점.
  - 형광등 보정표(A): Daylight 50R +1스톱 / White 40M +2/3 / Warm White 20C+40M +1 / Warm White Deluxe 30B+30C +1 1/3 / Cool White 40M+10Y +1 / Cool White Deluxe 20C+10M +2/3 / Unknown 30M +2/3.
  - HID 보정표(A): GE Lucalox(고압나트륨) 80B+20C +2 1/3 / GE Multi-Vapor 20R+20M +2/3 / Deluxe White Mercury 30R+30M +1 1/3 / Clear Mercury 70R +1 1/3.
  - 다크 스토리지 이미지 안정성 **80년 이상** (10 °C, RH 15–20 % 조건).
  - 채널별 감마·Dmax: 데이터 없음(특성곡선 그래프만 수록, Status A / Daylight 1/100 s).
- **정성 색 시그니처 (A, 데이터시트 본문)**
  - "moderately enhanced color saturation with a **neutral color balance**" (E100G).
  - E100GX는 동일 채도에 **웜 밸런스** ("X" is for warm) — 흐린 날/저색온 조명 보정 목적.
  - **낮은 D-min**("whiter, brighter whites"), **낮은 대비의 톤스케일**로 하이라이트·섀도우 디테일 개선.
  - "Matched color records for a neutral tone scale" → 톤 전 구간 그레이스케일 일관성, 스킨톤이 자연스러움.
- **상대적 위치**: 현행 E100(E-4000)이 rms 8 + low D-min + "moderately enhanced saturation, neutral balance"로 **문구가 사실상 동일** → E100G는 E100의 직계 전신, 시뮬레이션상 거의 같은 좌표. **E100GX는 E100에 웜 오프셋만 얹은 변종**으로 구현하는 것이 가장 정직합니다.

### 2.2 Kodak Ektachrome E100VS — E-163 (2005-09)

- **정량 (A)**: rms **11** (very fine). 그 외 수치 데이터 없음.
- **정성 (A)**: "most vivid, saturated ('VS') colors available today"이며, 이 채도가 **neutral gray scale을 유지한 채** 달성되었다고 명시. E103RF 매트릭스에도 "Vividly saturated colors / Unsurpassed sharpness at 100 speed / Superb reciprocity / One-stop push".
- **상대적 위치**: E100 대비 채도를 크게 올리되 **그레이축은 틀지 않는** 방향. Velvia처럼 색상 회전을 동반하는 채도가 아니라 "중립축 보존형 채도 확장"이라는 점이 핵심 차별점.

### 2.3 Kodak Ektachrome E100S / E100SW — E-164

- **정량 (A)**: rms **10** (extremely fine). 그 외 데이터 없음.
- **정성 (A)**: E100S = "Excellent neutral color rendition and natural skin-tone" + "Enhanced color saturation (the 'S' is for saturated)". E100SW = "Produces warm, saturated colors (the 'SW' is for saturated warm)".
- **상대적 위치**: E100G/GX의 전세대. S↔SW 관계가 G↔GX 관계와 같은 축(중립 vs 웜)이며, 채도는 G세대보다 한 단계 위, 입자는 한 단계 아래(10 vs 8).

### 2.4 Kodak Ektachrome E200 — E-28 (2005-09)

- **정량 (A)**: rms **12** (very fine). 푸시 출발점 표: **EI 320 = Push 1 (1st dev 8분) / EI 640 = Push 2 (11분) / EI 800 = Push 3 (13분)**. (E103RF 매트릭스는 "Push process to EI 1000"이라고 광고 — 데이터시트 표와 문구가 불일치하므로 양쪽 기록.)
- **정성 (A)**: "moderate contrast", "excellent color", "Beautiful skin-tone", 푸시 시 **대비·컬러밸런스 변화가 최소**.
- **상대적 위치**: Provia 400X의 Kodak판 대응. E100 대비 대비를 낮추고 푸시 내성을 최우선한 감도 200 스톡.

### 2.5 Kodak Ektachrome 64 (EPR) — E-8 (2005-09)

- **정량 (A)**: rms **11** (very fine).
- **정성 (A)**: "rich, natural color and **soft highlight contrast**", "Excellent flesh-to-neutral", "Accurately records neutral ... pleasing skin tones", E103RF에서는 "Enhanced color saturation".
- **상대적 위치**: 구세대 Ektachrome의 기준점. E100 대비 **하이라이트 롤오프가 더 부드럽고** 채도는 중간, 뉴트럴 정확도가 셀링포인트.

### 2.6 Kodak Ektachrome 100 Plus (EPP) — E-113 (2007-07)

- **정량 (A)**: rms **11** (very fine).
- **정성 (A)**: "high color saturation and **dependable neutrals** combined with pleasing skin tones", "Increased color saturation → vibrant colors", "**Lower highlight contrast** → 조명으로 대비를 통제할 여지".
- **상대적 위치**: EPN(정확도)과 E100VS(채도) 사이. 채도는 올리되 하이라이트 대비는 낮춘 스튜디오/제품용 성격.

### 2.7 Kodak Ektachrome 100 (EPN) — E-27 (2007-07)

- **정량 (A)**: rms **11** (very fine).
- **정성 (A/E103RF)**: "**Accurate, natural color reproduction**", "Reduces reflectance that adversely affect color reproduction".
- **상대적 위치**: 조사 대상 전체에서 **가장 채도가 낮고 가장 측색적으로 정직한** E-6. 복제/도판/의료용 좌표. 시뮬레이션에서는 "슬라이드 룩의 원점(거의 무보정)"으로 쓸 수 있습니다.

### 2.8 Kodak Ektachrome 400X (EPL) / P1600 (EPH)

- **EPL (A)**: rms **19** (fine). "high color saturation", 포토저널리즘용. 1스톱 푸시 가능.
- **EPH (A)**: rms **34 @ EI 1600** (coarse). **2-stop push 전제로 설계**(E-6P / Push 2)되어 데이터시트의 특성곡선 자체가 Push 2 조건. "bold, saturated color" + T-GRAIN. EI 800은 1-stop push.
- **주의**: EPH는 "정상 현상 기준 곡선"이 데이터시트에 없으므로, 시뮬레이션 시 **푸시된 상태가 기본값**임을 전제해야 합니다.

### 2.9 Kodak 텅스텐 3종: EPY 64T / EPT 160T / EPJ 320T

- **EPY (A)**: rms **11** (very fine). E103RF: "Tungsten balance / **Neutral color balance with excellent color reproduction**". → 텅스텐 광원 하 측색 정확도 지향.
- **EPT (A)**: rms **13** (very fine).
- **EPJ (A)**: rms **19** (fine). "**bold, saturated colors**" + KODAK T-GRAIN. → 같은 텅스텐이라도 EPY(정확)와 EPJ(과장)는 방향이 반대.

### 2.10 Kodak Elite Chrome 계열 (소비자용)

- **Elite Chrome 100 (EB/EB-3) — E-7014E (A)**: rms **8** (extremely fine). "excellent reproduction of skin tones, colors, and neutrals", "Lower D-min → whiter, brighter whites", "Lower contrast tone scale", "Matched color records". → **E100G와 문구·rms가 사실상 동일한 소비자 버전**.
- **Elite Chrome Extra Color 100 (EBX) — E-126E (A)**: rms **11**. "**highest color saturation available in a 100-speed consumer slide film**". → Kodak판 Velvia 대응. E100VS와 rms가 같으므로 두 필름은 채도 방향(중립축 보존 vs 아님)으로만 구분해야 합니다.
- **Elite Chrome 200 (ED) — E-148E (A)**: rms **12**. "moderate contrast", "natural-looking skin tones", "Beautiful skin-tone", 동급 대비 **대비가 낮음**.
- **Elite Chrome 400 (EL) — E-149 (A)**: rms **19**.
- **Elite Color 200/400 (EC200/EC400) — E-4039 (A)**: rms 값 없음(다른 척도, 상호 비교 불가라고 데이터시트에 명시). "deep, saturated colour ... **without sacrificing skin tones**". EC400은 Push 1 시 EI 800 특성곡선이 별도 수록.

### 2.11 Fujifilm Velvia 100 [RVP100] — AF3-202E

- **정량 (A)**: RMS **8**. 해상력 **80 lines/mm @1.6:1 / 160 lines/mm @1000:1** — 본 조사 전체에서 **가장 높은 해상력 수치**(Velvia 100F와 동일).
- **푸시/풀 (A)**: **−1/2 ~ +1 stop** 범위에서 색·계조 변화 최소.
- **기술 (A)**: PSHC(Pure, Stable & High-performance dye-forming Coupler), **CEL (Color-Extension Layer)**, S-Coupler(신세대 옐로 커플러). 색상 보존성은 RVP 100F와 동등.
- **정성 (A)**: "highest level of color saturation" — Fuji 자체 표현상 Velvia 100F보다 **더 높은 채도** 계열로 포지셔닝. 풍경·자연용.
- **MTF 100 % 초과 여부**: 데이터시트에 MTF 곡선이 수록되어 있으나 본 조사에서 **수치 판독은 하지 않았습니다** → 데이터 없음(신뢰도 B 작업 필요).
- **상대적 위치**: Velvia 50 대비 감도 +1스톱, 대비는 다소 완화되고 해상력은 동급 최고. 구현된 Velvia 50에서 "톤 커브를 조금 눕히고 감도 노이즈를 소폭 올린" 좌표.

### 2.12 Fujifilm Velvia 100F [RVP100F] — AF3-148E

- **정량 (A)**: RMS **8**. 해상력 **80 / 160 lines/mm**.
- **정성 (A)**: "high level of color saturation **and color fidelity**", "high color saturation along with super-fine grain quality (RMS=8) and high sensitivity (ISO 100) that **exceed the levels of the current ISO 50 Velvia**". "negative spectral sensitivity"를 수행하는 층이 도입되어 있다고 기술.
- **푸시/풀 (A)**: 데이터시트에 항목 존재하나 본 조사에서 범위 수치 미확인 → 데이터 없음.
- **상대적 위치**: Velvia 100과 rms·해상력이 동일하지만 **"fidelity"를 함께 내세운 점**이 결정적 차이. 즉 Velvia 100 = 채도 우선, Velvia 100F = 채도 + 색재현 정확도 절충. 구현 시 두 필름을 같은 채도로 두면 안 되고, 100F 쪽 hue 왜곡을 줄여야 합니다.

### 2.13 Fujifilm Astia 100F [RAP100F] — AF3-149E

- **정량 (A)**: RMS **7** — 본 조사 **전체 리버설 중 최저 입도**(T64와 공동). 해상력 **60 / 140 lines/mm**.
- **푸시/풀 (A)**: **−1/2 ~ +2 stop**, 색밸런스·계조 변화 최소 — Kodak/Fuji 리버설 중 **가장 넓은 푸시 관용도**.
- **상반칙불궤 (A)**: **1/4000 s ~ 1분 보정 불필요**. 2분 5B +1/3 / 4분 5B +1/2 / 8분 5B +2/3.
- **다중 노출 (A)**: 전자플래시 8회 연속까지 보정 불필요.
- **광원 (A)**: 텅스텐 3200 K + 80A → ISO 32. 형광등: White 10B+5M +1/2 / Daylight 25R +1 / Cool White 15M+5B +2/3 / Warm White 80C+10M +1.
- **정성 (A)**: "**Softest tones and subdued colors among FUJICHROME films**", 하이라이트→섀도우까지 연속적인 스킨톤 계조. **MCCL (Multi-Color-Correction Layer)** + 신규 색소재로 "one of the world's highest levels of color fidelity". "clear skin tones with **minimal muddiness**".
- **상대적 위치**: Provia 100F보다 **한 단계 더 낮은 채도·낮은 대비**, 그리고 더 고운 입자(7 vs 8). Fuji 리버설 축의 최연성 끝단.

### 2.14 Fujifilm Provia 400X [RXP] — AF3-0213E (2007-10)

- **정량 (A)**: RMS **11** — "ISO-100급에 근접하는 입도"라고 데이터시트가 직접 주장. 해상력 **55 / 135 lines/mm**.
- **정성 (A)**: **고채도 옐로 커플러** 채택으로 "풍경 사진에 적합한 채도 수준"을 확보하면서 스킨톤도 유지. 푸시/풀 시 변동 적음.
- **상대적 위치**: Provia 100F의 감도 2스톱 상향판이되, **채도는 100F보다 위**로 의도적으로 올린 스톡. 단순히 "Provia 100F + 노이즈"로 구현하면 틀립니다.

### 2.15 Fujifilm Provia 400F [RHP III] — AF3-066E

- **정량 (A)**: RMS **13**. 해상력 **55 / 135 lines/mm**.
- **정성 (A)**: 전세대 대비 "higher color saturation", 푸시/풀 우수.
- **상대적 위치**: 400X의 전신. 400X 대비 입자 거칠고(13 vs 11) 채도는 낮음.

### 2.16 Fujifilm Sensia 100 / 200 / 400 (소비자용)

- **Sensia 100 [RA] — AF3-091E (A)**: RMS **10**, 해상력 **55 / 135**. "beautiful skin tones, natural" 강조.
- **Sensia 200 [RM] — AF3-080E (A)**: RMS **13**, 해상력 **60 / 140**. "higher color saturation".
- **Sensia 400 [RH] (A)**: RMS **13**, 해상력 **55 / 135**. "higher color saturation".
- **상태**: Sensia 라인은 2010년 8월 단종(신뢰도 C).
- **상대적 위치**: Sensia 100은 Provia 100F의 소비자 파생(입도 10 vs 8)으로, 채도는 Provia보다 살짝 높고 스킨톤 지향. 200/400은 감도 상승분을 채도로 보상한 전형적 소비자 튜닝.

### 2.17 Fujifilm T64 [RTP] / 64T Type II [RTP II] (텅스텐)

- **T64 — AF3-178E (A)**: RMS **7**(Fuji 리버설 최저 tier), 해상력 **55 / 115 lines/mm**. 데이터시트가 "grain with an RMS value of 7"을 전면에 내세움. 푸시/풀 우수.
- **RTP II 64T — AF3-024E (A)**: RMS **10**, 해상력 **55 / 135 lines/mm**. "excellent resolving power. It also provides high saturation".
- **주의**: **T64(RMS 7 / 1000:1 115 lines/mm)와 RTP II(RMS 10 / 135 lines/mm)는 서로 트레이드오프가 반대**입니다. T64는 입자를 얻고 해상력을 내줬고, RTP II는 반대. 두 텅스텐 필름을 동일 취급하면 안 됩니다.
- **상대적 위치**: 데이라이트 3종 대비 청감층 감도가 텅스텐(3200 K)에 맞춰져 있으므로, 시뮬레이션에서는 **화이트밸런스 기준점 자체가 다른 별도 계열**로 두어야 합니다.

### 2.18 Fujifilm Fortia SP

- **정량**: 데이터 없음. ISO 50 / 데이라이트 / E-6 / 35 mm·120 (신뢰도 C).
- **상태**: 2005–2007 일본 한정 판매 후 단종. 전신은 2004년 한정 발매 Fortia.
- **정성 (C)**: Velvia 50(RVP)보다도 강한 채도, 더 따뜻한 톤, 더 높은 대비. Fujifilm 리버설 중 **최고 채도** 에멀전으로 반복 서술됨. 실사용 권장 노출은 ISO 64(판매처 권고, 신뢰도 D). 오렌지~핑크 기미가 있다는 사용자 서술(신뢰도 D).
- **상대적 위치**: 구현된 Velvia 50의 **극단 연장선**. 별도 필름이라기보다 "Velvia 50 + 채도/웜/대비 가중" 파라미터 변형으로 구현하는 편이 정직합니다.
- **경고**: 1차 데이터시트를 확보하지 못했으므로 수치 기반 구현 불가.

### 2.19 Agfachrome RSX II 50 / 100 / 200 Professional

- **정량 (A, Agfa 자체 척도)**
  - RSX II 50: ISO 50/18°, RMS **10.0**, 해상력 **55 lines/mm @1.6:1 / 125 lines/mm @1000:1**
  - RSX II 100: ISO 100/21°, RMS **10.0**, 해상력 **50 / 125**
  - RSX II 200: ISO 200/24°, RMS **12.0**, 해상력 **50 / 110**
- **푸시/풀 (A)**: "exceptionally good push/pull stability. Up to a speed adjustment of ±1 stop, the **neutrality of colour rendition is preserved in full**".
- **상반칙불궤 (C, 검색 요약)**: RSX II 50/100은 +1/2 및 +1스톱에 05B·10B 필터, RSX II 200은 +1 및 +2스톱에 075Y·15Y·05C. → 원본 표 재확인 필요(신뢰도 C).
- **제조 허용오차 (C)**: 감도 ±0.5 DIN(±1/6스톱), 컬러밸런스 ±5 CC.
- **정성 (A, 브로슈어 본문)**: Agfa Professional 라인 공통으로 "optimum colour saturation and tonal definition, exact contrast ranges, exemplary grey balance"를 표방. 브로슈어에 "extremely high colour saturation" 계열과 "restrained saturation and flat contrast" 계열이 병기되어 있으나, 본 조사에서 **어느 문장이 RSX II 어느 감도에 붙는지 확정하지 못했습니다** → 필름별 귀속은 데이터 없음.
- **상대적 위치**: Kodak/Fuji와 **RMS 척도가 다르므로 입도 직접 비교 금지**. 색 방향은 "중립 그레이밸런스 + ±1스톱 푸시에서도 중립 유지"가 브랜드 정체성 → E100/EPN 쪽에 가까운 정직 계열로 두는 것이 안전합니다.

### 2.20 Agfa CT Precisa 100 (두 개의 서로 다른 필름)

- **오리지널(독일 Agfa, 1998 도입 → 2005 단종)**: E-6, ISO 100, 35 mm 전용(중형·대형 없음). 아마추어 지향. "fine grain, sharpness, balanced colors, moderate contrast" (신뢰도 C). **크로스 프로세싱 시 색편차가 매우 적고 깊은 블루가 나오는 것**으로 유명 (신뢰도 C).
- **리브랜드(AgfaPhoto 상표, ~2018 단종)**: 동일 이름이지만 **완전히 다른 필름**. Fujifilm 제조(초기 Ferrania 설이 병존, 출처 상충). Provia 100F 계열이라는 서술이 있으나 **1차 확인 불가**(신뢰도 D). 크로스 프로세싱 시 원판과 달리 강한 그린으로 전이.
- **정량**: 양쪽 모두 데이터 없음.
- **구현 주의**: "CT Precisa"라는 이름 하나로 구현하면 반드시 틀립니다. 최소한 두 개의 별개 프로파일로 분리하거나, 1차 데이터 확보 전까지 **구현 보류**를 권장합니다.

### 2.21 Rollei Digibase CR200 Pro (= Agfa Aviphot Chrome 200 PE1)

- **정체 (C)**: Agfa-Gevaert의 **항공사진용 Aviphot Chrome 200**을 Rollei가 일반 카메라용으로 재포장. 베이스 에멀전은 Agfa RSX II 200 계열이라는 서술이 다수. 동일 에멀전이 Lomography X-Pro 200 Slide, Wittner Chrome 200D 등으로도 유통.
- **상태**: 2016년 4분기 단종.
- **정성 (C, 제조사 표현)**: ISO 200/24°, 데이라이트, "good reciprocity characteristics for long exposures", "high color saturation with a **neutral gray balance**", "fine grain with high sharpness", **투명 폴리에스터 베이스**(스캔 유리, 다만 광파이핑 주의). 타뷸러(평판) 결정 일부 사용.
- **정량**: 데이터시트 PDF 소재는 확인(`digitaltruth.com/products/rollei_tech/agfa_aviphot_chrome_200__en.pdf`)했으나 **수치 추출은 미완료** → RMS·해상력·Dmax 모두 데이터 없음.
- **베이스 재질 출처 상충**: 아세테이트 주장(포럼)과 폴리에스터/합성 베이스 주장(제조사 문구)이 충돌. 후자가 광파이핑 경고와 일관되므로 더 신빙성 있으나 확정하지 않음.

---

## 3. Kodachrome 전용 섹션 (K-14)

### 3.1 왜 별도 취급이 필요한가 — K-14 공정 구조

Kodachrome은 **필름 안에 발색 커플러가 없습니다.** 커플러는 현상액에 들어 있고, 현상 중 산화된 발색현상주약과 반응해 그 자리에서 염료를 만듭니다. 이 구조가 만드는 결과는 다음과 같습니다(신뢰도 C — 다수 출처 일치, 단 분자구조 수준은 미확인).

1. **층 두께가 얇다.** 커플러 입자를 유제에 넣지 않아도 되므로 전체 유제 두께가 흑백 필름보다도 얇을 수 있고, 층 내 광산란이 줄어 **예리함(acutance)이 구조적으로 높습니다.** → E-6 시뮬레이션의 "커플러 산란에 의한 저주파 번짐"을 Kodachrome에는 적용하면 안 됩니다.
2. **공정 순서**: 흑백 1차 현상 → 적색 재노광 후 시안 커플러 현상 → 청색 재노광 후 옐로 커플러 현상 → 남은 은에 화학적 포깅 + 마젠타 커플러 현상 → 은 제거. 마젠타(녹감층)는 옐로 필터층 때문에 광학적 재노광이 불가능해 **화학 포깅**으로 처리됩니다.
3. **염료 고정 원리**: 생성된 염료는 현상주약·커플러보다 훨씬 난용성이라 생성된 층에 그대로 남습니다. 층간 확산이 구조적으로 억제됩니다.
4. **총 14단계, 일부 100 °F ± 0.5 °F의 정밀 온도 제어와 전용 재노광 장비가 필요** → 전용 랩만 운용 가능. 이것이 단종의 실질적 원인.
5. **염료 안정성**: 커플러 잔류물이 없어 **다크 스토리지 보존성이 리버설 중 최상**. Kodak 자신이 E-55에서 "KODACHROME Films are the **most archival** transparency films"라고 명시(신뢰도 A). 반대로 **투사광(빛) 노출에 대한 내성은 E-6보다 약하다**는 서술이 널리 있으나 본 조사에서 1차 확인 못 함 → 데이터 없음.

### 3.2 데이터시트 확정 수치 (E-55, 1996-12 / 2003-08 / 2009-06 — 신뢰도 A)

| 항목 | PKM 25 | PKR 64 | PKL 200 |
|---|---|---|---|
| Diffuse rms granularity | **9** | **10** | **16** |
| Kodak 등급 표현 | extremely fine grain, extremely high sharpness | extremely fine grain, extremely high sharpness | fine grain, extremely high sharpness |
| 노출지수 Daylight/Flash | 25 | 64 | 200 |
| Photolamp 3400 K + 80B | 8 | 20 | 64 |
| Tungsten 3200 K + 80A | 6 | 16 | 50 |
| 상반칙불궤 1/10,000–1/100 s | 보정 없음 | 보정 없음 | 보정 없음 |
| 1/10 s | +1/2 stop, 필터 없음 | +1/3 stop, CC05R | +1/2 stop, CC10Y |
| 1 s 이상 | 권장하지 않음 | 권장하지 않음 | 권장하지 않음 |
| 푸시 | **권장하지 않음** | **권장하지 않음** | EI 500 / EI 800까지 양호 |
| 특성곡선 노출조건 | Daylight 1/25 s | Daylight 1/50 s | Daylight 1/100 s + 0.20 N.D. |
| 해상력 수치 | 데이터시트에 없음(MTF 곡선만) | 없음 | 없음 |
| Dmax | 데이터 없음(곡선만) | 데이터 없음 | 데이터 없음 |

소비자용 E-88(2009-06)에서도 KR 64 = rms **10**, KL 200 = rms **16**으로 프로 버전과 동일(A). KM 25(E-88)는 본 조사에서 미확인.

**시뮬레이션에 직결되는 A급 사실 두 가지**

- **Kodachrome 25/64는 푸시 자체를 Kodak이 권장하지 않았습니다.** 즉 "푸시된 Kodachrome 룩"은 데이터시트 근거가 없습니다.
- **PKL은 푸시하면 컬러밸런스가 마젠타-레드 방향으로 이동**한다고 명시되어 있습니다(스타디움 조명의 그린 캐스트를 상쇄하는 용도). 이는 K-14 푸시 시뮬레이션의 **유일한 1차 근거 있는 색 이동 방향**입니다.

### 3.3 Kodak 자체의 색 서술 (신뢰도 A — E-55 / E103RF 본문)

- PKM 25: "Reproduces **subtle color naturally**", "Extremely sharp", "Archival".
- PKR 64: "Very high sharpness", "**Reproduces subtle colors naturally**", "**Pleasing skin tones**", "Archival dark keeping".
- PKL 200: "Very high sharpness", "Reproduces subtle colors naturally", "Push process performance", "Archival dark keeping".
- 세 필름 모두 Kodak이 **"vivid" / "saturated"라는 단어를 쓰지 않았습니다.** Kodachrome의 공식 포지션은 **채도가 아니라 "미묘한 색의 자연스러운 재현 + 예리함 + 보존성"**입니다. 널리 퍼진 "Kodachrome = 강렬한 레드" 서술은 데이터시트 근거가 아니라 사용자 담론입니다.

### 3.4 "Kodachrome look"으로 반복 서술되는 특징 (신뢰도 C~D — 1차 근거 없음, 반드시 구분)

본 조사에서 **1차 출처로 확인하지 못한** 통념입니다. 구현 시 A급 사실과 섞지 말 것.

- 강한 레드/워엄 계열 발색, 특히 붉은 계통의 채도가 두드러진다는 서술.
- 블랙 밀도가 깊고 섀도우가 "잠기는" 렌디션.
- 스킨톤이 약간 붉고 따뜻한 쪽으로 치우친다는 서술.
- 블루가 상대적으로 차분하다는 서술.
- ISO 대비 그레인이 매우 곱다는 서술 → 이것만은 A급 수치(rms 9/10)로 뒷받침됩니다.

### 3.5 시뮬레이션 시 E-6과 달라야 하는 지점 (설계 권고)

1. **샤프니스/MTF 모델을 별도로**: 유제가 얇고 커플러 산란이 없으므로, E-6에 쓰는 층내 확산(diffusion) 커널을 그대로 쓰면 Kodachrome이 과도하게 물러집니다. E-55에 MTF 곡선이 수록되어 있으므로 여기를 판독(B급 작업)해 별도 커널을 만드는 것이 정도입니다.
2. **염료 세트가 E-6과 다름**: E-55의 spectral-dye-density 곡선(K-14, 3200 K 뷰잉 기준 visual neutral 1.0 정규화)이 수록되어 있습니다. E-6 dye set을 재사용하면 안 되고, 이 곡선을 별도 판독해야 합니다. **현재 판독 미완료 → 데이터 없음.**
3. **푸시 모델**: 25/64는 푸시 경로 자체를 만들지 말 것(제조사 비권장). 200만 푸시 경로를 두고, 푸시 시 **마젠타-레드 시프트**를 넣을 것.
4. **상반칙불궤가 매우 취약**: 세 필름 모두 **1초 이상 노출은 "권장하지 않음"**. 장노출 시뮬레이션 프리셋을 제공한다면 이 한계를 반영해야 합니다.
5. **감도별로 서로 다른 필름으로 취급**: rms 9 → 10 → 16의 점프가 크고(200은 25 대비 거의 2배), Kodak 스스로 200만 "fine grain"으로 등급을 낮췄습니다. 단일 Kodachrome 프로파일 + 노이즈 스케일링은 부정확합니다.

---

## 4. 권장 우선순위 Top 12

| 순위 | 필름 | 근거 |
|---|---|---|
| 1 | **Kodachrome 64 (PKR)** | K-14 계열의 대표. rms 10·EI표·상반칙불궤·푸시 정책까지 A급 확보. 문화적 인지도가 가장 높고, E-6과 구조적으로 다른 축을 하나 세울 수 있음 |
| 2 | **Fujichrome Velvia 100 (RVP100)** | A급 수치 완비(RMS 8 / 80·160 lines/mm / 푸시 −1/2~+1). 구현된 Velvia 50과 나란히 두면 Velvia 축이 완성됨 |
| 3 | **Fujichrome Astia 100F (RAP100F)** | 데이터 완성도가 조사 대상 중 최상(RMS 7, 60/140, 푸시 −1/2~+2, 상반칙불궤 전 구간 표, 형광등 표). Provia 100F보다 아래쪽 연성 끝단을 채워 Fuji 3축이 완성됨 |
| 4 | **Kodak Ektachrome E100VS** | "중립 그레이축을 유지한 고채도"라는 명확히 구분되는 색 정책. 구현된 E100의 자연스러운 확장이라 코드 재사용률이 높음 |
| 5 | **Fujichrome Provia 400X (RXP)** | 고감도 슬라이드 대표. RMS 11 + 고채도 옐로 커플러라는 A급 근거로 "고감도인데 채도도 높다"는 비자명한 특성을 정직하게 구현 가능 |
| 6 | **Kodachrome 25 (PKM)** | rms 9. K-14 축의 저감도 끝단. 64와 rms·EI·상반칙 계수가 모두 다르므로 별도 값이 있음 |
| 7 | **Kodak Ektachrome 100 (EPN)** | 조사 대상 중 **가장 정직한 무채색 기준점**("accurate, natural color reproduction"). 다른 슬라이드 룩을 이것 대비 상대 좌표로 정의할 수 있어 엔진 설계상 가치가 큼 |
| 8 | **Kodachrome 200 (PKL)** | rms 16 + **푸시 시 마젠타-레드 시프트**라는 A급 색이동 근거. K-14 축의 고감도 끝단 |
| 9 | **Fujichrome T64 (RTP)** | RMS 7로 최저 입도이면서 1000:1 해상력은 115로 낮은, **드문 트레이드오프 조합**. 텅스텐 밸런스 축을 여는 최적 후보 |
| 10 | **Kodak Ektachrome 64 (EPR)** | "soft highlight contrast"가 데이터시트에 명시된 몇 안 되는 필름. 하이라이트 롤오프 모델을 차별화할 A급 근거 |
| 11 | **Kodak Elite Chrome Extra Color 100 (EBX)** | 소비자 고채도 축. rms 11로 E100VS와 동일해 "채도 방향만 다른 쌍"을 만들 수 있어 검증에 유용 |
| 12 | **Fujichrome Velvia 100F (RVP100F)** | Velvia 100과 수치가 같으면서 "fidelity"를 함께 표방 → 채도-정확도 절충 좌표. 단, 두 필름을 구분하려면 곡선 판독(B급) 추가 필요 |

**의도적으로 순위에서 뺀 것들**: Fortia SP·CT Precisa·Digibase CR200은 1차 정량 데이터가 없어 구현하면 추정이 섞입니다. Elite Color 200/400은 rms 척도가 달라 다른 필름과 같은 파이프라인에 넣을 수 없습니다.

---

## 5. 데이터 공백

구현 전에 반드시 메워야 하는 항목들입니다. **어느 것도 추정으로 채우지 마십시오.**

1. **Dmax — 전 필름 공백.** 확인한 리버설 데이터시트 중 Dmax를 숫자로 적은 것은 **한 건도 없습니다.** 슬라이드 룩의 핵심이 최대 밀도인데, 이 값은 전부 특성곡선 그래프 판독(신뢰도 B)으로만 얻을 수 있습니다. → **곡선 판독 작업이 별도 과제로 필요.**
2. **채널별 감마(직선부 기울기) — 전 필름 공백.** 마찬가지로 곡선 판독 필요. Status A / K-14는 E.N.D. 등 densitometry 기준이 다르므로 판독 시 기준 통일 필수.
3. **Kodak 리버설의 해상력(lines/mm) — 전 필름 공백.** Kodak은 리버설 데이터시트에 MTF 곡선만 싣고 lines/mm를 적지 않습니다. Fuji·Agfa만 수치를 제공합니다. → **Kodak vs Fuji 해상력 직접 비교 불가.**
4. **MTF 100 % 초과 구간(Velvia 계열) — 미확인.** Velvia 100 / 100F 데이터시트에 MTF 곡선이 있으나 판독하지 않았습니다.
5. **분광 염료 밀도 곡선 — 전 필름 미판독.** 모든 데이터시트에 곡선은 있으나 수치화 안 됨. K-14 dye set은 E-6과 별개로 판독해야 함(3.5절 참조).
6. **노출 관용도(±스톱) — 대부분 공백.** 푸시/풀 범위는 Fuji가 명시(Astia −1/2~+2, Velvia 100 −1/2~+1)하지만, 이는 현상 관용도이지 노출 관용도가 아닙니다. 노출 관용도 수치는 어느 데이터시트에도 없었습니다.
7. **Velvia 50 구세대(RVP) vs 현행(RVP50) 차이 — 미조사.** AF3-960E(구 RVP)와 AF3-0221E2(RVP50) 두 문서가 아카이브에 존재함을 확인했으나 대조하지 않았습니다.
8. **Agfa RMS 척도의 규약** — Kodak/Fuji와 동일 조건(density 1.0, 48 µm)인지 미확인. 확인 전까지 교차 비교 금지.
9. **Kodachrome의 광 조사(투사) 내성** — "다크 스토리지 최강 / 빛에는 약함"이라는 통념의 1차 근거 미확보.
10. **Ektachrome 200 (EPD)** — E103RF 매트릭스에 존재만 확인(120 포맷, C-41 크로스 프로세싱 가능). 전용 데이터시트 번호조차 매트릭스에 비어 있음.
11. **Kodachrome 25 소비자용(KM)의 rms** — E-88 1998/2002판 미추출.
12. **Elite Color 200/400의 입도 지표** — rms가 아닌 별도 척도의 실제 값 미확인.

---

## 6. 미조사 잔여 목록

예산 제약으로 이번 라운드에서 착수하지 못했거나 1차 자료를 확보하지 못한 대상입니다.

**Fujifilm**
- MS 100/1000 (RMS/멀티스피드 리버설) — 전혀 미조사
- Velvia 50 구세대 RVP(AF3-960E) vs 현행 RVP50(AF3-0221E2) 대조 — 문서 소재만 확인
- Fortia (2004년 초판, SP 이전 모델) — 존재만 확인
- Fortia SP 1차 데이터시트 (Fujifilm Japan 아카이브 경유 필요)

**Kodak**
- Ektachrome 200 Professional (EPD) 데이터시트
- Ektachrome 400X 이전 세대(EL/Elite 400 외) 및 Elite Chrome Extra Color의 해외판 코드 변형
- Ektachrome Professional Infrared (EIR, TI-2323 / CIS-188) — 슬라이드지만 위색(false color) 필름이라 별도 판단 필요
- Ektachrome Duplicating Film EDUPE (E-2529) — 복제용, 카메라 필름 아님
- E-55 1996판·2003판과 2009판의 수치 차이 대조

**Agfa**
- Agfachrome 50S / 100RS / 200RS (RSX II 이전 세대) — 전혀 미조사
- Agfachrome CT100 (E-6 최초 슬라이드) — 언급만 확인
- Agfa CT Precisa 100 오리지널의 1차 데이터시트
- Agfa RSX II 상반칙불궤표 원본 재확인(현재 신뢰도 C)

**기타 제조사**
- 3M / Scotch Chrome 100 / 400 — 전혀 미조사
- Rollei Crossbird — 전혀 미조사
- Rollei Digibase CR200 Pro 데이터시트 수치 추출 (PDF 소재는 확인됨)
- Wolfen / ORWO 슬라이드 (UT18, UT21 등) — 전혀 미조사
- Adox 슬라이드 제품 — 전혀 미조사
- Lomography 슬라이드 제품 (X-Pro 200 Slide, LomoChrome 계열) — Aviphot 리브랜드 관계만 언급 확인
- Ferrania Solaris/Scotch 계열 슬라이드 — 미조사
- Konica Chrome (R-100 등) — 조사 대상에 없었으나 실재하므로 추가 검토 권장
- 현행 생산 중인 유일 계열(Ektachrome E100) 외 신규 슬라이드 제품 유무 확인
