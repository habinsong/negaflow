# 컬러 네거티브 스틸 필름 조사 (C-41 및 파생) — 1차

[Docs home](../../README.md)

- 작성일: 2026-08-09
- 목적: negaflow 필름 시뮬레이션 엔진용 필름별 고유 특성 수집
- **조사 상태: 부분 완료(예산 제약으로 중단).** 아래 "미조사 잔여 목록" 참조.
- 이미 구현되어 조사 대상에서 제외한 필름: Kodak Portra 160/400/800, Ektar 100, UltraMax 400, ColorPlus 200, Fujicolor C200, Fujifilm Pro 400H
  - 단, **비교 기준값**으로 필요한 경우에 한해 이 8종의 데이터시트 수치를 인용했습니다.

## 0. 방법론 및 주의사항

- 본 문서의 수치는 대부분 **제조사 1차 데이터시트 PDF 원문**에서 직접 추출했습니다(로컬 다운로드 후 텍스트 추출).
- **Kodak과 Fujifilm의 그레인 척도는 서로 비교 불가**입니다.
  - Kodak(1990년대 후반 이후): **Print Grain Index (PGI)**. Kodak 자신이 데이터시트에 "It replaces rms granularity and has a different scale which cannot be compared to rms granularity"라고 명기.
    - PGI 25 = 그레인 지각 임계값, 4단위 차이 = 90% 관찰자의 JND(just noticeable difference), 관찰 거리 14 inch 고정.
    - 별도 표기가 없으면 **135 (24×36mm) → 4×6 inch 프린트, 배율 4.4X** 기준입니다.
  - Fujifilm: **Diffuse RMS Granularity**. 측정 조건 = 마이크로덴시토미터 개구 48 µm, 배율 12×, 샘플 농도 = D-min +1.0.
  - 따라서 시뮬레이션 엔진에서 그레인 강도를 통합 파라미터로 쓰려면 **제조사별 척도를 별도 정규화**해야 합니다. 두 값을 같은 축에 놓으면 안 됩니다.
- 채널별 감마(특성곡선 직선부 기울기)의 **수치**는 Kodak/Fuji 어느 데이터시트에도 인쇄되어 있지 않습니다. 곡선 그래프만 제공됩니다. 따라서 본 문서에서는 전부 "데이터 없음(곡선 판독 필요)"으로 표기했습니다.
- 정성적 색 서술은 **데이터시트 원문의 제조사 주장**과 **독립 출처 서술**을 분리해 표기했습니다. 이번 조사에서는 독립 출처 교차검증(3곳 이상)까지 도달한 항목이 거의 없으므로, 대부분 "제조사 주장" 등급입니다.

### 신뢰도 등급 정의

- **A** = 제조사 데이터시트에 인쇄된 수치를 원문에서 직접 확인
- **B** = 데이터시트 곡선/그래프 판독 필요(수치 미인쇄)
- **C** = 독립 출처 3곳 이상 정성 일치
- **D** = 단일·약한 출처

---

## 1. 요약 표

### 1-1. Kodak (그레인 척도 = Print Grain Index, 4×6 / 4.4X 기준)

| 필름 | ISO | 상태 | 데이터시트 | PGI (4×6) | PGI (8×10) | PGI (16×20) | 신뢰도 |
|---|---|---|---|---|---|---|---|
| Kodak Gold 200 | 200 | 현행 | E-7022 (2016-02) | **44** | 데이터 없음 | 데이터 없음 | A |
| Kodak Gold 100 | 100 | 단종 | E-7022 (구판, Gold 100/200 합본) | **42** | 데이터 없음 | 데이터 없음 | A |
| Kodak Pro Image 100 | 100 | 현행 | E-5051 (원문 미확보) | **43** | 데이터 없음 | 데이터 없음 | C |
| Kodak Ultra Max 800 | 800 | 단종 | E-7024 (2007-12) | **48** | 데이터 없음 | 데이터 없음 | A |
| Kodak High Definition 200 | 200 | 단종 | E-7017 (2003-07) | **32** | 데이터 없음 | 데이터 없음 | A |
| Kodak High Definition 400 | 400 | 단종 | E-7013 (2003-01) | **39** | 데이터 없음 | 데이터 없음 | A |
| Kodak Royal Gold 25 | 25 | 단종 | E-40 (1996-12) | **<25** | 데이터 없음 | 데이터 없음 | A |
| Kodak Royal Gold 100 | 100 | 단종 | E-41 (1998-02) | **28** | 데이터 없음 | 데이터 없음 | A |
| Kodak Royal Gold 200 (구판) | 200 | 단종 | E-42 (1998-02) | **41** | 데이터 없음 | 데이터 없음 | A |
| Kodak Royal Gold 200 / RB (신판) | 200 | 단종 | E-7006 (2002-03) | **32** | 데이터 없음 | 데이터 없음 | A |
| Kodak Royal Gold 400 (구판) | 400 | 단종 | E-43 (1998-02) | **41** | 데이터 없음 | 데이터 없음 | A |
| Kodak Royal Gold 400 (신판) | 400 | 단종 | E-2509 (2000-01) | **39** | 데이터 없음 | 데이터 없음 | A |
| Kodak Royal Gold 1000 | 1000 | 단종 | E-44 (1998-02) | **57** | 데이터 없음 | 데이터 없음 | A |
| Kodak Bright Sun / GA 100 | 100 | 단종 | E-2328 (2003-07) | **45** | 데이터 없음 | 데이터 없음 | A |
| Kodak Portra 160NC | 160 | 단종 | E-190 (2006-10) | **36** | 58 | 87 | A |
| Kodak Portra 160VC | 160 | 단종 | E-190 (2006-10) | **40** | 62 | 91 | A |
| Kodak Portra 400NC | 400 | 단종 | E-190 (2006-10) | **44** | 66 | 96 | A |
| Kodak Portra 400VC | 400 | 단종 | E-190 (2006-10) | **48** | 70 | 99 | A |
| Kodak Portra 800 (구판) | 800 | (신형 구현됨) | E-190 (2006-10) | **48** | 70 | 99 | A |
| Kodak Ultra Color 100UC | 100 | 단종 | E-4035 (2007-05) | **31** | 53 | 83 | A |
| Kodak Ultra Color 400UC | 400 | 단종 | E-4035 (2007-05) | **40** | 62 | 92 | A |
| Kodak Supra 100 | 100 | 단종 | E-2519 (2003-05) | **27** | 49 | 78 | A |
| Kodak Supra 400 | 400 | 단종 | E-2519 (2003-05) | **36** | 58 | 87 | A |
| Kodak Supra 800 | 800 | 단종 | E-2519 (2003-05) | **50** | 72 | 101 | A |
| Kodak Vericolor III (VPS) | 160 | 단종 | E-26 (1997-04) | **39** | 61 | 91 | A |
| Kodak Profoto 100 (PRN 계열) | 100 | 단종 | E-2E (1997-07) | **43** | 65 | 94 | A |
| *(참고) Kodak UltraMax 400* | 400 | 현행 | E-7019 / E-7023 | *46* | — | — | A |

> Vericolor III 추가 포맷: 120/220(6×6cm) = 27 / 39 / 61, 4×5 시트 = <25 / <25 / 38 (배율 각각 2.6X·4.4X·8.8X, 1.2X·2.1X·4.2X).

### 1-2. Fujifilm (그레인 척도 = Diffuse RMS Granularity, 48 µm / 12× / D-min+1.0)

| 필름 | ISO | 상태 | 데이터시트 | RMS | 해상력 1.6:1 | 해상력 1000:1 | 신뢰도 |
|---|---|---|---|---|---|---|---|
| Fujicolor Superia 100 [CN] | 100 | 단종 | AF3-007E | **4** | 63 lines/mm | 125 lines/mm | A |
| Fujicolor Superia 200 [CA] | 200 | 단종 | AF3-008E | **4** | 50 lines/mm | 125 lines/mm | A |
| Fujicolor Superia X-TRA 400 [CH] | 400 | 현행 | AF3-151E (구), AF3-0217E (신) | **4** | 50 lines/mm | 125 lines/mm | A |
| Fujicolor Superia X-TRA 800 [CZ] | 800 | 단종 | AF3-068E | **5** | 50 lines/mm | 125 lines/mm | A |
| Fujicolor Superia 1600 [CU] | 1600 | 단종 | AF3-145E | **7** | 50 lines/mm | 125 lines/mm | A |
| Fujicolor Superia Reala [CS] | 100 | 단종 | AF3-967E | **4** | 63 lines/mm | 125 lines/mm | A |
| Fujicolor True Definition 400 [CH] | 400 | 단종 | AF3-196E | **5** | 50 lines/mm | 125 lines/mm | A |
| Fujicolor PRO 160S | 160 | 단종 | AF3-203U | **3** | 63 lines/mm | 125 lines/mm | A |
| Fujicolor PRO 160C | 160 | 단종 | AF3-204U | **3** | 63 lines/mm | 125 lines/mm | A |
| Fujicolor PRO 800Z | 800 | 단종 | (125px 미러 pro_800z_datasheet) | **5** | 50 lines/mm | 115 lines/mm | A |
| Fujicolor Portrait NPZ 800 | 800 | 단종 | (125px 미러 NPZ.pdf) | **5** | 50 lines/mm | 115 lines/mm | A |
| *(참고) Fujifilm PRO 400H* | 400 | 단종 | (125px 미러 pro_400h_datasheet) | *4* | *50 lines/mm* | *125 lines/mm* | A |

---

## 2. 필름별 상세

### 2-1. Kodak Gold 200

1. **제조사/제품명/ISO/공정/상태**: Kodak Alaris / KODAK GOLD 200 Film / ISO 200/24° / Process C-41 (Kodak Flexicolor) / **현행 생산**
2. **1차 출처**: KODAK Publication **E-7022**, February 2016 (Revised 2/16)
   - https://kodakprofessional.com/sites/default/files/wysiwyg/pro/resources/E7022%20Gold%20tech%20sheet.pdf (2023-06 개정판)
   - https://business.kodakmoments.com/sites/default/files/files/resources/E7022_Gold_200.pdf (2016-02판, 본 문서에서 원문 확인)
   - 구판 합본(Gold 100 + Gold 200): https://125px.com/docs/film/kodak/E7022-Gold_100_200.pdf
3. **정량 데이터**
   - 채널별 감마/contrast: **데이터 없음** (특성곡선 그래프만 제공. 곡선 조건: Exposure Daylight, Densitometry Status M, **Log H Ref −1.14**, 축 범위 log H −3.0…+1.0 / Density 0.0…4.0)
   - 그레인: **Print Grain Index 44** (135, 4×6 inch, 배율 4.4X). RMS 값은 미공개.
   - Dmin/Dmax 경향: 수치 **데이터 없음**. Spectral-Dye-Density 곡선에 Minimum Density / Midscale Neutral 두 곡선 제공(400–700 nm, 0.0–2.5 축). **오렌지 마스크 있음**(D-min 곡선이 청·녹역에서 높고 적색역에서 낮은 전형적 마스크 형태).
   - 노출 관용도: **−2 스톱 ~ +3 스톱** (데이터시트 명기: "from two stops underexposure to three stops overexposure")
   - 상반칙불궤: **1/10,000초 ~ 1초 범위에서 노출·필터 보정 불필요.** 그보다 긴 노출은 "make tests under your conditions"(수치 미제공).
   - 해상력(lines/mm), MTF: **데이터 없음** (E-7022에는 해상력·MTF 곡선 미수록)
   - 안티할레이션층: 데이터시트 명시 없음(일반 C-41 스틸 필름이므로 안티할레이션층 존재. remjet 아님)
   - 색온도 밸런스: **Daylight**. 3400 K 포토램프 → 80B, EI 64. 3200 K 텅스텐 → 80A, EI 50.
   - 정상 노출 판정 기준(Status M red / Wratten 92): 그레이카드 0.85–1.05, 그레이스케일 최명부 스텝 1.25–1.45, 밝은 피부 이마 1.15–1.45, 어두운 피부 이마 0.90–1.30
   - 형광등 보정: Daylight 40R +2/3, White 20C+30M +1, Warm White 40B +1, Warm White Deluxe 30B+30C +1⅓, Cool White 30M +2/3, Cool White Deluxe 20C+10M +2/3
4. **정성적 색 시그니처**
   - 제조사 주장(데이터시트 원문): "outstanding combination of color saturation, fine grain, and high sharpness", "Saturated colors → Bright, colorful prints"
   - 스킨톤 / 초록 / 파랑 / 빨강 / 노랑 / 섀도우·하이라이트 캐스트 / 크로스오버: **독립 출처 교차검증 미완료 — 데이터 없음**(이번 조사 범위에서 3출처 일치 확인 못함)
5. **상대적 위치**: PGI 기준으로 Gold 200(44)은 Pro Image 100(43)과 사실상 동급, Portra 400(37)보다 거칠고, UltraMax 400(46)보다 약간 곱다. 즉 **"Portra 계열보다 한 단계 거친 소비자용 그레인"** 위치. 색 방향(ColorPlus 200 대비)은 정량 근거 미확보.
6. **신뢰도**: 정량 **A**, 정성 **데이터 없음**

---

### 2-2. Kodak Pro Image 100

1. Kodak Alaris / KODAK PRO IMAGE 100 / ISO 100 / C-41 / **현행 생산**
2. **1차 출처**: KODAK Publication **E-5051** — **PDF 원문 미확보**(이번 조사에서 직접 열람 실패). 상업 사이트·리뷰 다수가 E-5051을 인용.
3. **정량 데이터**
   - PGI: **43** (4×6). 데이터시트에 3개 프린트 사이즈 값이 있다고 보고되나 나머지 2개 값은 **데이터 없음**.
   - 감마/RMS/Dmin/Dmax/해상력/MTF/상반칙불궤: **전부 데이터 없음**
   - 노출 관용도: 데이터시트 문구 미확인. **데이터 없음**
   - 색온도: Daylight (C-41 일반)
   - 특기 사항(제조사 주장으로 전해짐): **상온 보관 내성**(고온다습 지역 유통을 전제로 설계), 언더노출 관용도 양호
4. **정성**: 교차검증 미완료 — **데이터 없음**
5. **상대적 위치**: PGI 43 → **Gold 200(44)과 거의 동일한 그레인**, Portra 160(28)·Ektar 100(<25)보다 뚜렷하게 거칢. ISO 100 필름 중에서는 상당히 거친 축.
6. **신뢰도**: PGI 값 **C**, 나머지 **데이터 없음**

---

### 2-3. Kodak Royal Gold 계열 (전량 단종)

| 제품 | ISO | Pub | 날짜 | PGI | 비고(데이터시트 원문) |
|---|---|---|---|---|---|
| Royal Gold 25 | 25 | E-40 | 1996-12 | <25 | Royal Gold 계열 최소 그레인 |
| Royal Gold 100 | 100 | E-41 | 1998-02 | 28 | Sharpness: Extremely High / Degree of Enlargement: Extremely High. "KODAK ADVANTIX 기술을 35mm에 도입" |
| Royal Gold 200 | 200 | E-42 | 1998-02 | 41 | Sharpness: Extremely High |
| Royal Gold 200 / RB | 200 | E-7006 | 2002-03 | 32 | 개량판. "excellent sharpness, contrast, and color" |
| Royal Gold 400 | 400 | E-43 | 1998-02 | 41 | Wide exposure latitude |
| Royal Gold 400 | 400 | E-2509 | 2000-01 | 39 | 데이터시트 원문: "the world's finest grain 400-speed color print film" |
| Royal Gold 1000 | 1000 | E-44 | 1998-02 | 57 | Wide exposure latitude |

- 감마·RMS·Dmin/Dmax·해상력·상반칙불궤 수치: **전부 데이터 없음**(Kodak 소비자 계열 데이터시트에는 미수록)
- 주목할 점: **동일 제품명 Royal Gold 200/400이 개정판에서 PGI가 크게 개선**(200: 41→32, 400: 41→39). 시뮬레이션에서 "Royal Gold 200"을 하나로 뭉뚱그리면 안 되고 **세대 구분이 필요**합니다.
- 신뢰도: PGI **A**, 나머지 **데이터 없음**

---

### 2-4. Kodak High Definition 200 / 400 (단종)

- HD 200: Pub **E-7017** (2003-07), 정식명 "KODAK High Definition 200 Film / 3992 / HD2", **PGI 32**
- HD 400: Pub **E-7013** (2003-01), **PGI 39**, 데이터시트 원문 "the world's finest grain 400-speed color print film" (= E-2509 Royal Gold 400과 동일 문구, 사실상 후속 리브랜딩으로 보임. PGI도 39로 동일)
- 감마/RMS/해상력/상반칙불궤: **데이터 없음**
- 상대적 위치: HD 200(32)은 Gold 200(44)보다 **PGI 12단위(≈3 JND) 곱다**. 소비자 라인 중 가장 미립자.
- 신뢰도: **A**(PGI), 나머지 없음

---

### 2-5. Kodak Bright Sun / GA 100 (단종)

- Pub **E-2328** (2003-07). 정식명 "KODAK Bright Sun Film / GA"
- 데이터시트 원문: "the best combination of color saturation, color accuracy, and sharpness at ISO 100"
- **PGI 45** (4×6). ISO 100치고 매우 거친 편.
- 노출 관용도: **−2 스톱 ~ +3 스톱** (Gold 200과 동일 문구)
- 나머지 정량: **데이터 없음**
- 신뢰도: **A**

---

### 2-6. Kodak Portra 160NC / 160VC / 400NC / 400VC (구세대, 단종)

1. Eastman Kodak → Kodak Alaris / KODAK PROFESSIONAL PORTRA 160NC·160VC·400NC·400VC·800 / C-41 / **단종**(현행 Portra 160·400·800으로 통합 대체)
2. **1차 출처**: KODAK Publication **E-190**, October 2006 — https://125px.com/docs/film/kodak/e190-Portra-2006.pdf
3. **정량 데이터**
   - PGI (135, 4×6 / 8×10 / 16×20, 배율 4.4X / 8.8X / 17.8X):
     - 160NC: **36 / 58 / 87**
     - 160VC: **40 / 62 / 91**
     - 400NC: **44 / 66 / 96**
     - 400VC: **48 / 70 / 99**
     - 800: **48 / 70 / 99**
   - 감마/RMS/해상력/MTF/Dmin/Dmax/상반칙불궤: **데이터 없음**(E-190 본문에서 미확인)
4. **정성**: 제품명 자체가 NC = Natural Color, VC = Vivid Color. 같은 감도에서 **VC가 NC보다 PGI 4단위(정확히 1 JND) 높음** — 즉 채도를 올린 대가로 지각 그레인이 딱 1 JND만큼 증가하도록 설계되었다는 정량적 정황. 이는 시뮬레이션에서 NC↔VC를 "채도 + 미세 그레인" 축으로 모델링할 근거가 됩니다.
5. **상대적 위치**: 현행 Portra 400(PGI 37)은 구 400NC(44)·400VC(48)보다 확연히 곱습니다. **구세대 Portra를 현행 Portra 파라미터로 재활용하면 안 됩니다.**
6. **신뢰도**: PGI **A**, 색 방향 정성 **C 미만**(제품명·설계 정황 근거, 리뷰 교차검증 미실시)

---

### 2-7. Kodak Ultra Color 100UC / 400UC (구세대, 단종)

- Pub **E-4035** (2007-05) — https://125px.com/docs/film/kodak/e4035-100UC_400UC.pdf
- 데이터시트 원문: "This family of color negative films delivers an extra punch of color."
- PGI (4×6 / 8×10 / 16×20): 100UC = **31 / 53 / 83**, 400UC = **40 / 62 / 92**
- 나머지 정량: **데이터 없음**
- 상대적 위치: 100UC(31)는 Ektar 100(<25)보다 거칠고 Portra 160(28)보다 약간 거칢. 400UC(40)는 현행 Portra 400(37)과 근접.
- 신뢰도: **A**

---

### 2-8. Kodak Supra 100 / 400 / 800 (단종)

- Pub **E-2519** (2003-05, 단종 공지 포함) — https://125px.com/docs/film/kodak/e2519-2003_05.pdf
- PGI (4×6 / 8×10 / 16×20): Supra 100 = **27 / 49 / 78**, Supra 400 = **36 / 58 / 87**, Supra 800 = **50 / 72 / 101**
- 데이터시트 원문 서술:
  - 공통: "superior image structure, bold/dynamic color, and natural skin tones... an excellent choice when negatives will be electronically scanned"
  - Supra 100: "extremely fine grain and excellent sharpness"
  - Supra 400: "the finest grain of any color negative film in its speed class, plus vibrant colors without oversaturated skin tones", 유제 오버코트로 스크래치 저항 개선, **1스톱 증감 가능**
  - Supra 800: "the sharpest high-speed color negative film available today", **EI 3200까지 증감 가능**(그레인·대비·색·섀도우 디테일 영향 최소)
- 단종 시 Kodak 권장 대체: Supra 400 → Portra 400UC
- 나머지 정량: **데이터 없음**
- 신뢰도: **A**(PGI 및 인용 문구)

---

### 2-9. Kodak Vericolor III Professional (VPS) — 단종

- Pub **E-26** (1997-04) — https://125px.com/docs/film/kodak/e26-Vericolor_III.pdf
- PGI:
  - 135 (24×36mm), 4×6/8×10/16×20 = **39 / 61 / 91** (배율 4.4X/8.8X/17.8X)
  - 120·220 (6×6cm) = **27 / 39 / 61** (배율 2.6X/4.4X/8.8X)
  - 4×5 시트 = **<25 / <25 / 38** (배율 1.2X/2.1X/4.2X)
- 인화지 최적화: EKTACOLOR PORTRA III / SUPRA II / ULTRA II, DURAFLEX RA
- 감마·RMS·해상력·상반칙불궤: **데이터 없음**
- 신뢰도: **A**
- 참고: Kodak Pro Films 마이그레이션 표(E-182, 1997-02)에 따르면 **VERICOLOR III(VPS) → PORTRA 160NC**가 공식 후속입니다. 같은 표: Pro 100(PRN)→160VC, Pro 400 MC(PMC)→400NC, Pro 400(PPF)→400VC, Pro 1000(PMZ)→Portra 800, Pro 100T(PRT)→Portra 100T.

---

### 2-10. Kodak Profoto 100 (PRN 계열) — 단종

- Pub **E-2E** (1997-07) — https://125px.com/docs/film/kodak/e2e-Profoto_100.pdf
- PGI: **43 / 65 / 94** (4×6 / 8×10 / 16×20, 배율 4.4X/8.8X/17.8X)
- 나머지 정량: **데이터 없음**
- 신뢰도: **A**

---

### 2-11. Fujicolor Superia X-TRA 400 [CH]

1. Fujifilm / FUJICOLOR SUPERIA X-TRA 400 [CH] / ISO 400/27° / Process CN-16, CN-16Q, CN-16FA, CN-16L, CN-16S 또는 **C-41** / **현행 생산**
2. **1차 출처**:
   - Ref. No. **AF3-151E** (Fuji Photo Film Co., Ltd.) — https://125px.com/docs/film/fuji/superia_xtra400_datasheet.pdf (본 문서에서 원문 확인)
   - 최신 개정: **AF3-0217E** — https://asset.fujifilm.com/master/emea/files/2020-10/9a958fdcc6bd1442a06f71e134b811f6/films_superia-xtra400_datasheet_01.pdf
3. **정량 데이터**
   - 채널별 감마: **데이터 없음**(특성곡선 그래프만. 조건: Daylight 1/125 sec, Process CN-16, Status M, 축 log H −4.0…0.0 / Density 0.0…4.0)
   - **Diffuse RMS Granularity = 4** (개구 48 µm, 배율 12×, 샘플 농도 D-min+1.0)
   - **해상력: 1.6:1 = 50 lines/mm, 1000:1 = 125 lines/mm**
   - **MTF 곡선 제공**: 응답 축 2–150%, 공간주파수 1–200 cycles/mm. **저주파(1–5 c/mm)에서 100%를 넘는 오버슈트**가 보이며(≈120% 부근 평탄), 100 c/mm 부근에서 급락. → **에지 강조(adjacency effect)가 뚜렷한 필름**. 시뮬레이션에서 언샵 성분을 넣을 근거.
   - 상반칙불궤: **1/4000초 ~ 2초 보정 불필요.** 4초 = +1/3, 16초 = +2/3, 64초 = +1 스톱. (색보정 필터 지시는 없음 → 장노출 컬러 시프트가 상대적으로 작게 설계됨)
   - Dmin/Dmax: 수치 **데이터 없음**. Spectral Dye Density 곡선(400–700 nm, 0.0–2.0+)에 Mid-scale / Minimum Density 제공. **오렌지 마스크 있음**.
   - 안티할레이션층: **있음**(Film Structure 도해에 "Antihalation Layer" 명시, 필름 베이스 바로 위)
   - 색온도 밸런스: **Daylight**. 3200 K 텅스텐 → LBB-12(=Wratten 80A), EI 100, +2스톱.
   - 정상 노출 판정: 18% 그레이카드 Status M **RED 필터 0.75–0.95**
   - 형광등 보정: Daylight 10M+10Y +1/3, Cool White 무보정, White 10C +1/3, Warm White 30C+30M +1, Deluxe White Mercury 10C +1/3, Clear Mercury 40M+40Y +1⅓
4. **정성적 색 시그니처** (제조사 데이터시트 원문 주장)
   - **4th Color Layer(제4감색층)** 탑재 → "Accurate color reproduction even under fluorescent lights", "Minimal loss of color balance under mixed light". **형광등 하 녹색 캐스트 억제가 이 필름의 구조적 개성**입니다.
   - 빨강/파랑/노랑: "Vibrant and dynamic reds, blues, and yellows"
   - 보라·초록: "Violets and a variety of greens with enhanced fidelity"
   - 스킨톤: "Smooth, beautiful and naturally depicted skin tones"
   - 그레이 밸런스: "Precisely maintained gray balance throughout, from the brightest highlights to the deepest shadows" → **크로스오버가 작게 설계**되었다는 제조사 주장
   - 선예도: "Extremely sharp depiction... from overall form to textural details" (MTF 오버슈트와 정합)
   - **마스크 색 변화(중요)**: 데이터시트 9-4 항목 — 신형 X-TRA 400은 구형 대비 **"slight reddish tint"** 의 포스트프로세싱 마스킹 색. 12항 — 일부 프린터에서 **오버노출 영역에 약한 블루 캐스트**가 나타날 수 있음. → **하이라이트 블루 캐스트 + 약간 붉은 마스크**는 데이터시트가 직접 인정한 특성입니다. 시뮬레이션에서 반영 가치 높음.
   - 유제 기술: Super Fine-Σ (Sigma) Grain — 기존 육각 결정 대비 **두께 약 1/2**의 얇은 균일 결정, Super Efficient Coupler.
5. **상대적 위치**: 이미 구현된 Fujicolor C200과 같은 Superia 계열 색 설계(4th Color Layer 계보)이나, **한 단계 높은 감도 + 동일 RMS 4**로 "C200의 그레인을 유지한 채 2배 감도"에 해당. Pro 400H(RMS 4, 동일 해상력)와 수치상 그레인·해상력이 같으므로, **두 필름의 차이는 그레인이 아니라 계조·색 설계(프로용 저채도 vs 소비자용 고채도)에 있습니다.**
6. **신뢰도**: 정량 **A**, 정성 **A(제조사 문구 인용)** — 단, 독립 출처 교차검증은 미실시

---

### 2-12. Fujicolor Superia 100 [CN] / Superia 200 [CA] (단종)

- Ref. **AF3-007E** (100) / **AF3-008E** (200)
- Superia 100: ISO 100/21°, 텅스텐 3200K → ISO 25/15° + LBB-12. **RMS 4**, 해상력 **63 / 125 lines/mm**
- Superia 200: ISO 200/24°, 텅스텐 3200K → ISO 50/18° + LBB-12. **RMS 4**, 해상력 **50 / 125 lines/mm**
- 상반칙불궤(양쪽 동일): 1/4000–2초 보정 불필요, 4초 +1/3, 16초 +2/3, 64초 +1
- 제조사 정성 주장(양쪽 거의 동일 문구):
  - "Great vividness across the entire spectrum, including vibrant reds, blues and yellows"
  - "Enhanced realism in the reproduction of difficult-to-create colors, including **violet and various greens**"
  - "Beautiful, natural skin tone rendition"
  - "Accurate color reproduction even under fluorescent lights"
- 감마·Dmin/Dmax: **데이터 없음**
- 신뢰도: **A**
- 주: Superia 100/200은 현행 "Fujicolor 100 / Fujifilm 200"의 직계 선조로 널리 알려져 있으나, **현행 제품의 데이터시트는 이번에 확인하지 못했습니다**(미조사 목록 참조). 두 세대를 동일 시뮬레이션으로 취급하는 것은 근거가 부족합니다.

---

### 2-13. Fujicolor Superia Reala [CS] (단종)

- Ref. **AF3-967E** — https://125px.com/docs/film/fuji/superia_reala_datasheet.pdf
- ISO 100, Daylight, C-41/CN-16 계열
- **RMS 4**, 해상력 **63 / 125 lines/mm**
- **상반칙불궤가 Superia 계열과 다름(중요)**: 1/4000–**1초**까지 보정 불필요, **4초 +1/3, 16초 +1, 64초는 "Not recommended"**. → Superia 100/200/400(64초 +1)보다 **장노출 특성이 확연히 나쁩니다.** 야경 시뮬레이션 시 구별 포인트.
- 제조사 정성 주장(원문 그대로):
  - **"Fourth Sensitized Layer"** → "Superb color reproduction under tungsten, fluorescent, and other light sources", "Minimal loss of color balance even under mixed light sources that include fluorescent light"
  - **"Soft Gradations"** → "Rich highlight-to-shadow tone reproduction"
  - **"Greater Underexposure Latitude"** → "Wider choice of exposure"
  - "Optimum Spectral Sensitivity Balance", "Faithful, natural color reproduction"
  - "Superb Granularity and Sharpness"
- 시뮬레이션 함의: Reala는 Superia와 **동일 RMS·동일 해상력**이면서 데이터시트가 **"soft gradation + faithful(=저채도 방향) color"** 를 명시합니다. 즉 **Superia = 고채도/일반 계조, Reala = 저채도/연조**가 제조사 스스로의 포지셔닝입니다.
- 감마 수치·Dmin/Dmax: **데이터 없음**
- 신뢰도: **A**

---

### 2-14. Fujicolor Superia X-TRA 800 [CZ] (단종)

- Ref. **AF3-068E**
- ISO 800, **RMS 5**, 해상력 **50 / 125 lines/mm**
- 상반칙불궤: 1/4000–2초 보정 불필요, **4초 +2/3, 16초 +1½, 64초 +2** (X-TRA 400보다 장노출 손실이 큼)
- 제조사 정성 주장: "Wide exposure latitude that allows vibrant colors, good image depth and high fidelity to be obtained **even from underexposed negatives**", "brilliant reds, bright blues and clear yellows", "violet and various greens", "Excellent Gray Balance ... from the brightest highlights to the deepest shadows"
- 신뢰도: **A**

---

### 2-15. Fujicolor Superia 1600 [CU] (단종)

- Ref. **AF3-145E**
- ISO 1600, **RMS 7**, 해상력 **50 / 125 lines/mm**
- 유제 기술: **Nano-structured Σ (Sigma) Grain Technology** + **4th Color Layer**
- 상반칙불궤: 1/4000–2초 보정 불필요, **4초 +2/3, 16초 +1½, 64초 +2**
- 제조사 정성 주장: "Highly uniform fine grain, regardless of the film's ultrahigh speed", "good image depth and high fidelity even if underexposed", "Vibrant and dynamic reds, blues, and yellows", "Violets and a variety of greens with enhanced fidelity", "Excellent Gray Balance"
- 용도로 명시: 실내 가정, 결혼식, 파티, 무대, 일몰·야경, 스포츠, **천체 사진**, 보도
- 신뢰도: **A**
- 참고: Natura 1600(일본 내수)과의 관계는 이번 조사에서 **확인하지 못했습니다**.

---

### 2-16. Fujicolor True Definition 400 [CH] (단종)

- Ref. **AF3-196E** — https://125px.com/docs/film/fuji/True_Definition_DataSheet.pdf
- ISO 400, 135/24-exp., 베이스 = Cellulose Triacetate 122 µm
- **RMS 5**, 해상력 **50 / 125 lines/mm** → **X-TRA 400(RMS 4)보다 오히려 그레인이 거칠다.**
- 상반칙불궤: 1/4000–2초 보정 불필요, 4초 +1/3, 16초 +2/3, 64초 +1 (X-TRA 400과 동일)
- 유제 기술: **New Fine Color Film Technology(신 계조 설계)** + 4th Color Layer + Super Fine-Σ Grain
- 제조사 정성 주장(핵심 차별점):
  - **"Natural Skin Tones"** — "natural skin tone with continuously smooth gradation from the highlights to shadows **without washed-out flash pictures**" → **플래시 하이라이트 날림 억제**가 설계 목표
  - **"Soft Gradation"** — "Rich highlight-to-shadow tone reproduction that allows for fine details to be reproduced"
- 시뮬레이션 함의: 같은 Superia 계보 안에서 **X-TRA 400 = 표준/고채도, True Definition 400 = 연조·하이라이트 보호형**. 그레인을 희생해 계조를 얻은 설계.
- 신뢰도: **A**

---

### 2-17. Fujicolor PRO 160S / PRO 160C (단종)

- Ref. **AF3-203U** (160S) / **AF3-204U** (160C) — Product Information Bulletin
  - https://125px.com/docs/film/fuji/AF3-203U_Pro160S_Product_Information_Bulletin.pdf
  - https://125px.com/docs/film/fuji/AF3-204U_Pro160C_Product_Information_Bulletin.pdf
- 양쪽 모두 ISO 160/23°, Daylight, C-41/CN-16
- **양쪽 모두 RMS 3** (Fuji 컬러 네거티브 중 최소값), 해상력 **63 / 125 lines/mm**
  - 데이터시트 각주: "Based on Fujifilm measurements. Due to difference in measurement conditions, comparison with color reversal film is not possible."
- 감마·Dmin/Dmax·상반칙불궤 수치: 본 조사에서 **미확인 — 데이터 없음**
- **160S vs 160C의 차이는 RMS·해상력 수치로는 전혀 구분되지 않습니다**(완전 동일). 차이는 색 설계(S = Soft/저채도 포트레이트, C = Color/고채도)에 있으나 이번 조사에서 데이터시트 문구를 확인하지 못했습니다 → **정성 데이터 없음**.
- 신뢰도: 정량 **A**, 정성 **데이터 없음**
- 후속 제품 Pro 160NS(일본 내수)는 **미조사**.

---

### 2-18. Fujicolor PRO 800Z / Portrait NPZ 800 (단종)

- PRO 800Z: **RMS 5**, 해상력 **50 / 115 lines/mm**
- NPZ 800 (FUJICOLOR PORTRAIT FILM NPZ 800 PROFESSIONAL): **RMS 5**, 해상력 **50 / 115 lines/mm** (측정 조건 표기: 개구 48 µm, 배율 12×, 샘플 농도 NETA 1.0)
- → **두 필름의 image-structure 수치가 완전히 동일**. NPZ 800이 PRO 800Z로 리브랜딩된 계보임을 시사(단, 이 인과관계 자체는 데이터시트에 명시되어 있지 않음).
- Superia X-TRA 800(RMS 5, 1000:1 = 125 lines/mm)과 비교하면 **RMS는 같고 고대비 해상력만 115로 낮음** → 프로용 800이 소비자용 800보다 약간 연조/저선예 방향.
- 감마·상반칙불궤·정성: **데이터 없음**
- 신뢰도: **A**(수치), 나머지 없음

---

## 3. 권장 우선순위 (현재까지 수집된 근거만으로)

> 기준: (a) 현재 유통량, (b) 사용자 인지도, (c) 색 개성의 뚜렷함, (d) **1차 데이터시트 수치 확보 여부**.
> 데이터가 없는 필름을 상위에 두면 추정 구현이 되므로, 데이터 확보 여부에 큰 가중치를 두었습니다.

| 순위 | 필름 | 근거 |
|---|---|---|
| 1 | **Kodak Gold 200** | 현행·최대 유통량·최고 인지도. E-7022 원문으로 PGI 44·관용도 −2/+3·상반칙불궤·스펙트럼 커브 전부 확보. 즉시 구현 가능. |
| 2 | **Fujicolor Superia X-TRA 400** | 현행·Fuji 소비자 라인 대표. RMS 4·해상력·MTF·상반칙불궤·형광등 보정·**하이라이트 블루 캐스트/붉은 마스크**까지 데이터시트가 직접 명시. 개성이 가장 문서화된 필름. |
| 3 | **Kodak Pro Image 100** | 현행·최근 인지도 급상승. PGI 43 확보(다만 원문 미확보). Gold 200과 그레인 동급이면서 색 방향이 다르다는 사용자 인식이 강함. |
| 4 | **Fujicolor Superia Reala** | 4th layer + soft gradation + **장노출 특성이 확연히 다름(64초 not recommended)** → 다른 Fuji와 구별되는 물리적 근거가 명확. |
| 5 | **Kodak Portra 400NC / 400VC** | 구세대 Portra는 현행 Portra와 PGI가 크게 달라(44·48 vs 37) 별도 프로파일 가치가 큼. NC/VC 쌍이 정확히 1 JND 차이라는 정량 근거 확보. |
| 6 | **Kodak Portra 160NC / 160VC** | 위와 동일 논리. 36 / 40. |
| 7 | **Fujicolor Superia 200** | 현행 "Fujifilm 200"의 직계. RMS 4·해상력 확보. |
| 8 | **Fujicolor Superia 100** | 현행 "Fujicolor 100"의 직계. 해상력 63 lines/mm로 200보다 높음(구별 근거). |
| 9 | **Fujicolor Superia X-TRA 800** | 고감도 Fuji 대표. RMS 5 + 장노출 손실 큼(64초 +2). |
| 10 | **Kodak Ultra Color 100UC / 400UC** | "extra punch of color" — Ektar 이전의 Kodak 고채도 라인. PGI 3사이즈 전부 확보. |
| 11 | **Kodak High Definition 200** | PGI 32로 Gold 200 대비 3 JND 곱다 — 소비자 라인 내에서 뚜렷한 차별점. |
| 12 | **Fujicolor PRO 160S / 160C** | RMS 3(Fuji 최저). 프로 라인 저그레인 기준점. 단 S/C 색 차이 데이터 필요. |
| 13 | **Kodak Supra 400 / 800** | "in-class 최소 그레인", "EI 3200 증감" 등 증감 시뮬레이션 근거 보유. |
| 14 | **Fujicolor Superia 1600** | 초고감도 개성(RMS 7). 야간·무대 시나리오 커버. |
| 15 | **Kodak Vericolor III (VPS)** | 포맷별 PGI 3세트 확보 — 중형/대형 시뮬레이션 검증용 레퍼런스로 유용. |

**우선순위에서 의도적으로 제외한 것**: Aerocolor IV 2460 파생(Santacolor 800, Flic Film Elektra 100 등), Harman Phoenix, ORWO NC400/NC500, Lomography 라인, Agfa Vista/Optima — **유통량·화제성은 높지만 이번 조사에서 1차 데이터를 전혀 확보하지 못했습니다.** 데이터 없이 순위를 매기면 추정 구현이 되므로 제외했습니다. 2차 조사 후 재평가가 필요합니다.

---

## 4. 데이터 공백

### 4-1. 모든 필름에 공통으로 없는 항목

| 항목 | 상태 |
|---|---|
| **채널별 감마 수치(R/G/B 직선부 기울기)** | **어느 데이터시트에도 인쇄되어 있지 않음.** 전 제품이 곡선 그래프만 제공 → 구현하려면 곡선 이미지 판독(등급 B) 또는 실측 필요 |
| **Dmin / Dmax 수치** | 미인쇄. Spectral Dye Density 곡선에서 판독해야 함 |
| **오렌지 마스크 수치화(채널별 베이스 밀도)** | 미인쇄. Kodak "Minimum Density" 곡선 / Fuji "Minimum Density" 곡선에서 판독 |
| **크로스오버(밝기대별 색 갈림) 정량치** | 어느 제조사도 수치 미제공. 특성곡선 3채널 간격 변화로 추정해야 함 |
| **Kodak 필름의 RMS granularity** | 1990년대 후반 이후 Kodak은 컬러 네거티브에 RMS를 아예 발표하지 않음(PGI로 대체). **Kodak↔Fuji 그레인 직접 비교는 원리적으로 불가** |
| **Kodak 소비자 필름의 해상력(lines/mm)·MTF** | E-7022, E-7013, E-7017, E-7024 등에 미수록 |

### 4-2. 데이터시트 자체를 확보하지 못한 필름

- **Kodak Pro Image 100** — E-5051 원문 미확보(PGI 43만 2차 출처)
- **Kodak Max / Farbwelt 400**
- **Kodacolor VR / 구세대 Gold**
- **Kodak Ektar 25 / 125 (구세대)**
- **Kodak Portra 400UC** (E-4035에 100UC/400UC만 확인, 400UC = Supra 400 대체품이라는 문구만 확보)
- **Aerocolor IV 2460 및 파생품 전부**(Santacolor 800, Flic Film Elektra 100, Amber 등) — 원본 항공필름 데이터시트조차 미확인. **remjet/안티할레이션 처리 여부가 이 계열의 핵심 개성**인데 근거 없음
- **Agfa 전 제품**(Vista 100/200/400, Vista Plus, Optima 100/200/400, Ultra 50/100, Portrait 160) — 125px 아카이브에 Agfa 컬러 네거티브 데이터시트가 사실상 없음(APX 흑백·Scala만 존재)
- **Fujifilm 현행 리브랜딩 제품**(Fujicolor 100 / Fujifilm 200 / Fujifilm 400 / Superia Premium 400)
- **Fujifilm 일본 내수**(Natura 1600, Industrial 100, Venus 800, Pro 160NS)
- **Fujicolor NPH 400 / NPS 160 / NPC 160** — Professional Data Guide에 항목명은 존재하나 image-structure 수치 미추출
- **Lomography** 전 제품(Color Negative 100/400/800, LomoChrome Metropolis/Purple/Turquoise) — 데이터시트 부재가 구조적(제조원 비공개)
- **Harman Phoenix 200 / Phoenix II** — 마스크 없는 컬러 네거티브라는 점이 핵심 개성이나 미확인
- **ORWO Wolfen NC400 / NC500**, **Adox Color Mission 200**, **Ilford Ilfocolor 400**, **Kono/Revolog**, **Flic Film 라인**

---

## 5. 미조사 잔여 목록 (2차 조사 대상)

원 지시 대상 중 이번에 **전혀 손대지 못한** 필름:

**Kodak**
- Max / Farbwelt 400
- Kodacolor VR / 구세대 Gold
- Ektar 25 / Ektar 125 (구세대)
- Aerocolor IV 2460 파생: Santacolor 800, Flic Film Elektra 100, Amber 등

**Fujifilm**
- Superia 400(일본 내수), Superia Premium 400
- Fujicolor 100 / Fujifilm 200 / Fujifilm 400 (현행 리브랜딩)
- Natura 1600, Industrial 100, Venus 800
- Pro 160NS, NPH 400, NPS 160, NPC 160
- Reala 100 Professional(아마추어용 Superia Reala와 별개 제품인지 확인 필요)

**Agfa**
- Vista 100 / 200 / 400, Vista Plus
- Optima 100 / 200 / 400
- Ultra 50 / 100
- Portrait 160
- APX 컬러 라인(존재 여부 자체 검증 필요)

**기타 제조사**
- Lomography Color Negative 100 / 400 / 800
- LomoChrome Metropolis / Purple / Turquoise
- Harman Phoenix 200, Phoenix II
- ORWO Wolfen NC400 / NC500
- Adox Color Mission 200
- Ilford Ilfocolor 400
- Kono / Revolog 특수 필름
- Flic Film 라인 전반
- (조사 중 발견) **Konica** 컬러 네거티브 라인 — 125px 아카이브에 VX100/200/400, VX-S 시리즈, Centuria Super 100/200/400/800/1600, Centuria Pro 400, Professional 160, Impresa 50, Infrared 750 데이터시트가 전부 보존되어 있음(https://125px.com/docs/film/konica/). 전량 단종이나 **1차 데이터 확보가 쉬운 미개척 영역**.

**2차 조사 시 권장 진입점**
- Kodak 아카이브: https://125px.com/docs/film/kodak/ (E-시리즈 다수, 구판 포함)
- Fuji 아카이브: https://125px.com/docs/film/fuji/ (AF3-시리즈)
- Konica 아카이브: https://125px.com/docs/film/konica/
- Agfa 아카이브: https://125px.com/docs/film/agfa/ (컬러 네거티브는 빈약)
- Kodak Print Grain Index 방법론 문서: **E-58** — https://filmcolors.org/wp-content/uploads/2025/12/Kodak_Print-Grain-Index_E-58.pdf
- Kodak Pro Films 마이그레이션 표: **E-182** — https://125px.com/docs/film/kodak/e182-Pro_Films.pdf
- Fujifilm Professional Data Guide(다품종 합본): https://125px.com/docs/film/fuji/ProfessionalFilmDataGuide.pdf
