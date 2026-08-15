# macOS 기준값(golden) — Windows 포팅 대조용

macOS negaflow(이 저장소의 `negaflow-mac`)를 **기준 자료**로 두고, Windows 포팅본이 같은
결과를 내는지 확인하기 위한 실측값 모음입니다. macOS 소스는 한 줄도 고치지 않았고, 값을
뽑는 하네스만 새로 추가했습니다.

측정일: 2026-08-15 · 커밋: `fe6910d`

## 원본 파일

| 파일 | 크기(byte) | 화소 | SHA-256 |
|---|---|---|---|
| `v700/GT-X900_frame_4.tiff` | 47,316,912 | 2272 × 3471, 16bit RGB, 2400dpi | `9e3d0daf2537273a299d5a77ed17c2d3c617131e59cc6afa9d90daf867d1a198` |
| `v700/GT-X900_frame_4.tiff.ir.tiff` | 15,772,446 | 2272 × 3471, 16bit Gray, 2400dpi | `67747cd11919c5aaa84c2897d52675e65ceb32d69d7930d1480c1e316775f16e` |
| `8100/OpticFilm8100_frame_1.tiff` | 115,592,740 | 5136 × 3543, 16bit RGBA(LZW), 72dpi, `sRGB IEC61966-2.1 Linear` | `e609674131396348d445c69896c9300974fafdbc78cc96ea21e1f3507217e735` |

로컬 경로는 `/Users/songhabin/tiff_test/golden/` 아래입니다. **8100 폴더에는 IR 파일이
없습니다** — 그래서 작업 2·3(적외선)은 V700 쌍으로만 수행했습니다.

## 하네스 (새로 추가한 파일)

전부 opt-in 입니다. 환경변수를 주지 않으면 `swift test` 에서 skip 되므로 일반 테스트
실행과 CI 에 영향이 없습니다.

| 파일 | 작업 |
|---|---|
| `negaflow-mac/Tests/ChromabaseTests/MacGoldenHarnessSupport.swift` | 공용 도구 |
| `negaflow-mac/Tests/ChromabaseTests/MacGoldenDevelopExportHarnessTests.swift` | 작업 1 |
| `negaflow-mac/Tests/ChromabaseTests/MacGoldenInfraredAlignmentHarnessTests.swift` | 작업 2 |
| `negaflow-mac/Tests/ChromabaseTests/MacGoldenPrintGeometryHarnessTests.swift` | 작업 4 |
| `negaflow-mac/Tests/ChromabaseTests/MacGoldenMetadataPolicyHarnessTests.swift` | 작업 6 |
| `negaflow-mac/Tests/negaflowAppTests/MacGoldenAppHarnessSupport.swift` | 공용 도구(앱 타깃) |
| `negaflow-mac/Tests/negaflowAppTests/MacGoldenInfraredRepairHarnessTests.swift` | 작업 3 |
| `negaflow-mac/Tests/negaflowAppTests/MacGoldenExportNamingHarnessTests.swift` | 작업 5 |
| `docs/verification/macos-golden/tools/*.py` | 픽셀 통계 / 차이 분포 / TIFF 태그 덤프 |

재현 명령은 각 하네스 파일 상단 주석에 있습니다.

---

## [작업 1] 실입력 픽셀 golden

산출물: `task1-pixels/` (V700), `task1-pixels-8100/` (OpticFilm 8100)

### 고정 조건

| 항목 | 값 |
|---|---|
| 로드 경로 | `ImageLoader.loadScannerTIFF` (CLI 의 `--raw`) |
| 현상 경로 | `ChromabaseEngine.developScanner` |
| filmType | `colorNegative` (C-41) |
| look | **none** — 프리셋 미적용, 순수 `DevelopParameters()` |
| base | `auto` (입력당 1회 측정 후 8개 조건이 공유) |
| 톤 오버라이드 / defectRemoval | 없음 / 0 |
| 출력 | TIFF 16-bit, 압축 `none`, `ExportMeta = nil`, metadataPolicy `minimal` |

측정된 auto base (V700): **R 0.338134765625 / G 0.293212890625 / B 0.233398437500**, source `auto`

**재현성 확인**: 조건 a) 의 결과가 CLI 산출물과 바이트 단위로 동일했습니다.

```bash
negaflow develop GT-X900_frame_4.tiff out.tif --raw --look none --film-type colorNegative --target main
```

→ 양쪽 모두 SHA-256 `a3a17e73…4488e7`. 파이프라인이 프로세스를 넘어 결정적이라는 뜻이고,
Windows 쪽도 같은 CLI 조합으로 대조할 수 있습니다.

### V700 결과 (2272 × 3471)

| 조건 | 파일 | byte | SHA-256 |
|---|---|---|---|
| a) 기본 MAIN / sRGB | `a-default-main-srgb.tif` | 47,323,110 | `a3a17e736645d9ddb6340c7be5867f9f0580bd74d2cbec23ba1c9061654488e7` |
| b) + `noritsu__color-nega__kodak-portra-400` | `b-main-scannerprofile-portra400-srgb.tif` | 47,323,110 | `cbec99382d4d330f4042c9a1fcac986c2efad59383c60823f5d6872d48ea552e` |
| c) HS (`noritsu`) | `c-target-hs-srgb.tif` | 47,323,110 | `8170b2aadb07195bf2ec42c2cdd0f38cef95596bd0ac91981b713ba7c973746f` |
| c) SP (`sp-3000`) | `c-target-sp-srgb.tif` | 47,323,110 | `5331e970ec72ff03410cda371bbad7cb97835316d9cb51feaf03c000ffe3f23a` |
| c) F135 (`f135`) | `c-target-f135-srgb.tif` | 47,323,110 | `8296c4990a0731a8f1cf53e3482b907edfdfa75a1419cf40b9b8bf9d18a8f172` |
| c) HR (`hr`) | `c-target-hr-srgb.tif` | 47,323,110 | `ae67c78189aebd633153d1cc2ea4e13648867f8a60028cd0477b89e60e9cf877` |
| d) sRGB | = a) 와 동일 조건 | | |
| d) Display P3 | `d-main-displayp3.tif` | 47,320,502 | `230a3c85406e9f2da65476defd846f96f59b731e0f6fe6dd96366706b21414af` |
| d) Adobe RGB | `d-main-adobergb.tif` | 47,320,526 | `3915583c65a48e097302129afb3e310be2ecdcf56e328d1dd007fe1910c4c849` |

d) 의 byte 수 차이는 임베드 ICC 프로파일 크기 차이입니다(픽셀 수는 같음).

### V700 픽셀 통계 (16-bit code value 0–65535)

| 조건 | ch | min | median | max | mean |
|---|---|---|---|---|---|
| a) 기본 | R | 132 | 44908 | 60016 | 40985.701 |
| | G | 117 | 47896 | 60416 | 43601.553 |
| | B | 49 | 49865 | 61186 | 45653.284 |
| b) 스캐너 프로파일 | R | 0 | 45661 | 61659 | 40961.821 |
| | G | 0 | 49334 | 62153 | 44252.222 |
| | B | 0 | 51581 | 63001 | 46696.432 |
| c) HS | R | 0 | 46246 | 59268 | 42097.926 |
| | G | 102 | 47407 | 59166 | 43197.375 |
| | B | 45 | 48926 | 59599 | 44731.229 |
| c) SP | R | 0 | 45393 | 57892 | 41035.314 |
| | G | 117 | 47722 | 55497 | 43181.553 |
| | B | 0 | 50446 | 59494 | 45957.750 |
| c) F135 | R | 0 | 45907 | 58933 | 41455.323 |
| | G | 106 | 47850 | 58403 | 43123.989 |
| | B | 0 | 48681 | 58548 | 44257.726 |
| c) HR | R | 0 | 44156 | 58419 | 39875.636 |
| | G | 95 | 47850 | 59046 | 43086.544 |
| | B | 0 | 50490 | 60421 | 45887.129 |
| d) Display P3 | R | 161 | 45510 | 60044 | 41477.041 |
| | G | 124 | 47808 | 60396 | 43520.014 |
| | B | 109 | 49659 | 61075 | 45441.604 |
| d) Adobe RGB | R | 1399 | 45476 | 59895 | 41578.294 |
| | G | 1152 | 47526 | 60260 | 43415.267 |
| | B | 976 | 49435 | 61000 | 45388.285 |

전체 JSON: `task1-pixels/pixel-stats.json`, `task1-pixels/manifest.json`

### OpticFilm 8100 결과 (5136 × 3543)

같은 8개 조건·같은 고정 조건. 측정된 auto base: **R 0.191284179688 / G 0.093872070312 /
B 0.071105957031**, source `auto`.

| 조건 | 파일 | byte | SHA-256 |
|---|---|---|---|
| a) 기본 MAIN / sRGB | `a-default-main-srgb.tif` | 109,191,526 | `7f9179400367ba0727c7abf45e668632872192e99a01d278f394e4303b966680` |
| b) + portra-400 프로파일 | `b-main-scannerprofile-portra400-srgb.tif` | 109,191,526 | `e2f1496a7e9899503a4ade28bde6b40f227ff698e8181f38660e125a98d29f24` |
| c) HS | `c-target-hs-srgb.tif` | 109,191,526 | `8114655443a80f59f11420a9c9e77fa0e9c0f57c13581abb010f8b2e8e7a58a8` |
| c) SP | `c-target-sp-srgb.tif` | 109,191,526 | `16df704c1b33e88302fa4067eb346c29c14de3a7e67bbb0c341d32796666e898` |
| c) F135 | `c-target-f135-srgb.tif` | 109,191,526 | `9af8f911d5d69826f9dd33a60386b7f9306fbf0179f79caa252ac9eef866ebf6` |
| c) HR | `c-target-hr-srgb.tif` | 109,191,526 | `bf982accbb8a54acefd5c46cd7805c25a03f95f5f52f85827c7842431d46ff5b` |
| d) Display P3 | `d-main-displayp3.tif` | 109,188,918 | `2dc510f65b937d2308837cecfe92382bc2bb7196807d61e16bfc9d24b780583d` |
| d) Adobe RGB | `d-main-adobergb.tif` | 109,188,942 | `8464a6c082d1ba6ba0536b3a67148d0adeb0af5b3db522d0958fc8cdb7afc9dd` |

| 조건 | ch | min | median | max | mean |
|---|---|---|---|---|---|
| a) 기본 | R | 58 | 25353 | 62399 | 26936.263 |
| | G | 71 | 24632 | 62305 | 27129.359 |
| | B | 92 | 22817 | 62256 | 27563.832 |
| b) 스캐너 프로파일 | R | 0 | 20531 | 65056 | 22069.836 |
| | G | 0 | 19521 | 64982 | 22847.592 |
| | B | 0 | 16437 | 65535 | 23750.694 |
| c) HS | R | 58 | 25719 | 63776 | 28232.351 |
| | G | 0 | 24386 | 63943 | 27353.650 |
| | B | 0 | 22849 | 63178 | 27416.826 |
| c) SP | R | 58 | 27678 | 65535 | 28890.714 |
| | G | 71 | 28527 | 65535 | 30345.408 |
| | B | 91 | 25685 | 65535 | 31173.984 |
| c) F135 | R | 0 | 26198 | 65519 | 27646.626 |
| | G | 0 | 25154 | 63640 | 27483.938 |
| | B | 0 | 22643 | 65535 | 27550.543 |
| c) HR | R | 0 | 24704 | 64166 | 26080.978 |
| | G | 0 | 24463 | 63126 | 26740.365 |
| | B | 0 | 23012 | 65452 | 27836.309 |
| d) Display P3 | R | 68 | 25194 | 62382 | 27029.538 |
| | G | 74 | 24647 | 62309 | 27139.221 |
| | B | 99 | 22898 | 62262 | 27577.194 |
| d) Adobe RGB | R | 926 | 25122 | 62271 | 27335.558 |
| | G | 921 | 24672 | 62203 | 27464.208 |
| | B | 1042 | 22974 | 62154 | 27989.091 |

전체 JSON: `task1-pixels-8100/manifest.json`, `task1-pixels-8100/pixel-stats.json`

재계산:

```bash
python3 tools/pixel_stats.py task1-pixels
```

---

## [작업 2] 적외선 정렬 상관값

산출물: `task2-infrared-alignment/infrared-alignment.json`
입력: V700 RGB + IR 쌍 · 파라미터는 앱 기본값(`InfraredDefectRemoval.Parameters()`,
sensitivity 0.5 / searchRadius 32 / minArea 2 / maxCoverage 0.05)

| 항목 | macOS 실측 |
|---|---|
| alignment status | `aligned` |
| offset (x, y) | **(1, −1)** |
| peak correlation | **0.012493191491005515** |
| runner-up correlation | **0.011389978663363401** |
| peak / runner-up | 1.0969 |
| searchRadius / downsampleFactor | 32 / 1 |
| coverage | **0.10060967029705756 %** |
| median gain | **4.0** |
| candidate / confirmed | **120 / 59** |
| cluster 수 | 14 |
| 검출 소요 | 28.6 s |

### Windows 의 peak = 0.017 은 정상인가

**정상 범위입니다.** macOS 가 같은 성격의 쌍에서 0.0125 를 냈습니다. 자릿수가 같습니다.

중요한 것은 이 값이 **정규화 상관계수(NCC)가 아니라는 점**입니다. 정합기는 두 경로입니다.

1. **결함 신호 경로** — `InfraredDefectRemoval+DefectAlignment.swift:31`
   `estimateDefectAlignment`. peak 은 "IR 결함점 자리의 raw 국소 어두움"을 가중 평균한
   값이라 **단위가 밀도이고 0 근처의 작은 수가 정상**입니다. 이번 쌍은 이 경로가 답을
   냈습니다(단독 호출 결과가 통합 추정기 결과와 동일: offset (1,−1), peak 0.012493).
2. **누설 상관 경로** — `InfraredDefectRemoval+Alignment.swift:56` 이하. 결함 신호가 부족할
   때만 내려가며, 여기의 peak 은 진짜 NCC 라 0.4~0.5 대가 나옵니다.

임계값 위치:

| 게이트 | 위치 | 조건 |
|---|---|---|
| 결함 경로 채택 | `InfraredDefectRemoval+DefectAlignment.swift:121` | `best.score >= mean * 1.10` (**전체 탐색면 평균 대비** 10% — 차점 대비가 아님) |
| 결함 경로 최소 표본 | 같은 파일 `:70`, `:56` | 결함점 ≥ 16개, `spread > base * 1e-3` |
| 누설 경로 약상관 | `InfraredDefectRemoval+Alignment.swift:96` | `bestScore > 0.2` — **NCC 전용. 0.017 에 적용되지 않습니다** |

즉 0.017 을 0.2 와 비교해 "약하다"고 판정하면 오진입니다. 결함 경로에는 절대 임계값이
없고, 그 스캔 자신의 탐색면 평균 대비 상대 판정만 있습니다.

추가로 확인할 것: Windows 의 peak 이 어느 경로에서 나왔는지. `estimateDefectAlignment` 를
단독 호출해 non-nil 이면 결함 경로이고, 그때만 macOS 의 0.0125 와 직접 비교됩니다.

`medianGain = 4.0` 은 상한에 걸린 값입니다 — 게인은 `clampGain`
(`InfraredDefectRemoval+Confirmation.swift:206`)이 `[0.2, 4]` 로 자르므로, 확인된 결함의
절반 이상이 천장에 닿았다는 뜻입니다.

---

## [작업 3] GrainMend 복원 크기

산출물: `task3-grainmend/` (`grainmend-off.tif`, `grainmend-on.tif`,
`grainmend-repair.json`, `diff-stats.json`)

두 경로 모두 **같은 평탄화 base**(RGBA16 linear CGImage)에서 출발합니다 — 차이가 오직 IR
복원에서만 오도록 한 것입니다. cleaned raw 합성은 앱과 같은 `CleanedRawCanvas`, 필름
base 는 앱과 같이 현상 입력마다 재추정합니다(이번 쌍은 두 입력의 base 가 같았습니다:
R 0.338135 / G 0.293213 / B 0.233398).

| 항목 | macOS | Windows(제시값) |
|---|---|---|
| 검출 coverage | **0.10060967 %** | 0.4179 % |
| candidate / confirmed | 120 / 59 | — |
| cluster / patch | 14 / 14 | — |

차이 분포 `|off − on|` (16-bit code value):

| 관점 | p50 | p90 | p99 | p99.9 | max | >100 개수 | >100 비율 |
|---|---|---|---|---|---|---|---|
| 픽셀당 RGB 최대 (n=7,886,112) | 45 | 53 | 57 | 396 | **16000** | 7,959 | **0.1009 %** |
| 채널 표본 풀링 (n=23,658,336) | **6** | 50 | 55 | 166 | 16000 | 23,863 | **0.1009 %** |
| Windows(제시값) | 6 | — | — | 4802 | 25202 | — | 0.417 % |

읽는 법:

- Windows 가 낸 **p50 = 6 은 채널 풀링 관점과 정확히 일치**합니다. 두 구현이 같은 방식으로
  값을 세고 있다는 뜻입니다.
- **`>100` 비율(0.1009 %)이 검출 coverage(0.1006 %)와 거의 같습니다.** Windows 도
  0.417 % 대 0.4179 % 로 같은 관계였습니다. 즉 "크게 바뀐 화소 = 검출된 결함 화소"라는
  구조는 양쪽이 동일하고, **남은 차이는 오직 검출량(coverage)이 macOS 에서 약 4배 적다는
  것**입니다. 복원 로직이 아니라 검출 단계를 먼저 대조해야 합니다.
- 비영 화소가 97.9 %(픽셀당 최대 기준)나 되고 p50~p99 가 45~57 의 좁은 띠에 몰려 있습니다.
  이는 잡음이 아니라 **거의 일정한 전역 오프셋**입니다. 현상 파이프라인에 장면 적응 단계가
  있어 몇 개 화소가 바뀌면 전체 톤이 미세하게 따라 움직입니다(65535 중 45 ≈ 0.07 %).
  파이프라인 자체는 결정적입니다(작업 1의 CLI 바이트 일치로 확인).

재계산:

```bash
python3 tools/diff_stats.py task3-grainmend/grainmend-off.tif task3-grainmend/grainmend-on.tif
```

---

## [작업 4] 인화 판 기하

산출물: `task4-print-geometry/print-geometry.json`

단판은 `PrintCompositionLayout` 이 **화소**로 직접 계산합니다. 컨택트 시트는
`PrintPackageLayout` 이 **포인트**로 계산하고 `PrintPackageRenderer` 가 `dpi/72` 를 곱해
화소를 만듭니다(`round`).

이미지 사각형은 원본 종횡비에 직접 의존하므로 두 원본으로 돌렸습니다.

### A4 300dpi, 세로, 여백 10mm

캔버스는 세 경우 모두 **2480 × 3508 px**, contentRect `(118.11, 118.11, 2243.78, 3271.78)`.

| 조건 | 원본 | imageRect (x, y, w, h) | 반올림 | 천공 |
|---|---|---|---|---|
| 천공 없음 | 2272×3471 (실제 스캔) | (169.202, 118.110, 2141.597, 3271.780) | 2142 × 3272 | **0** |
| 천공 없음 | 2400×3600 (규격 2:3) | (149.407, 118.110, 2181.186, 3271.780) | 2181 × 3272 | **0** |
| 35mm 천공 | 2272×3471 | (484.667, 600.056, 1510.666, 2307.888) | 1511 × 2308 | **16** |
| 35mm 천공 | 2400×3600 | (470.704, 600.056, 1538.592, 2307.888) | 1539 × 2308 | **16** |

35mm 천공일 때 filmRect = `(118.110, 535.948, 2243.780, 2436.103)`,
천공 모서리 반지름 32.6951 px, 첫 천공 `(230.940, 598.774, 126.934, 178.861)`.

### 컨택트 시트 4열 × 3행, 사진 12장

| 항목 | 값 |
|---|---|
| 페이지 수 | 1 |
| 캔버스(포인트) | 841.8898 × 595.2756 |
| 캔버스(화소, 300dpi) | **3508 × 2480** |
| contentRect(포인트) | (28.3465, 28.3465, 785.1969, 538.5827) |
| 칸 수 | **12** |
| 칸 0 cellRect(포인트) | (28.3465, 391.1811, 192.0472, 175.7480) |
| 칸 0 destRect(포인트) | (66.8507, 391.1811, 115.0388, 175.7480) → 479.328 × 732.283 px |

시트 방향은 원본이 아니라 **격자 모양(4열 × 3행)** 으로 정해집니다(가로 격자 → A4 가로).

### Windows 제시값과의 대조

| 항목 | Windows | macOS | 판정 |
|---|---|---|---|
| A4 300dpi 캔버스 | 2480×3508 | 2480×3508 | 일치 |
| 천공 없음 이미지 | 1991×3272 | 2142×3272 / 2181×3272 | 높이 일치, 폭은 원본 종횡비 차이 |
| 천공 개수(없음) | 0 | 0 | 일치 |
| 35mm 이미지 | 1404×2308 | 1511×2308 / 1539×2308 | 높이 일치, 폭은 종횡비 차이 |
| 천공 개수(35mm) | 16 | 16 | 일치 |
| 컨택트 캔버스 | 3508×2480 | 3508×2480 | 일치 |
| 컨택트 칸 | 12 | 12 | 일치 |

높이(3272 / 2308)가 화소 단위로 정확히 일치하므로 **용지·여백·게이트 계산은 양쪽이
같습니다.** 폭만 다른 것은 Windows 가 쓴 원본의 종횡비가 다르기 때문입니다
(1991/3271.78 = 0.6085, 1404/2307.89 = 0.6083 → Windows 원본 종횡비 ≈ 0.6084;
실제 스캔은 0.6546, 규격 2:3 은 0.6667). 폭까지 맞추려면 **같은 원본**으로 다시 재야
합니다. 위 표의 `canonical-2400x3600` 행이 종횡비 의존을 제거한 비교 기준점입니다.

---

## [작업 5] 내보내기 파일명 토큰

산출물: `task5-export-naming/export-naming.json` + 실제 생성 파일 2개

패턴: `{date}-{roll}-{frame}-{name}-{preset}-{sequence}-{rollcode}-{film}-{camera}`

고정 입력: 언어 english · 롤 이름 `Roll 12` · 롤 코드 `H250729a` · 필름 `Portra 400` ·
카메라 `Nikon FM2` · 프리셋 `rich-neutral` · sequence 시작 3 · scanIndex 7 · 형식 TIFF(.tif)

| 변형 | 원본 파일 이름 | 카드 표시 이름 | 실제 생성 파일 이름 |
|---|---|---|---|
| 이름 미지정 | `…-source-7.tif` | `Frame 7` | `20260815-Roll 12-0007-Frame 7-rich-neutral-0003-H250729a-Portra 400-Nikon FM2.tif` |
| 카드 이름 변경 | `…-source-7.tif` | `Sunset At Han River` | `20260815-Roll 12-0007-Sunset At Han River-rich-neutral-0003-H250729a-Portra 400-Nikon FM2.tif` |

실제 저장 경로는 날짜 폴더 아래입니다: `20260815/default/<위 파일 이름>`.

### `{name}` 은 무엇인가

**카드 표시 이름입니다. 원본 파일 이름이 아닙니다.**

- 근거: 원본 파일 이름은 두 변형 모두 `source-7.tif` 로 같은데, 생성된 파일 이름은
  `Frame 7` ↔ `Sunset At Han River` 로 갈립니다.
- 구현: `AppModel.exportBaseName` → `frame.displayName(language:)`
  (`negaflow-mac/Sources/negaflowApp/Features/Export/AppModel+ExportNaming.swift:7`).
  비어 있을 때만 `frame<scanIndex>` 로 떨어집니다.
- 단, `displayName` 의 우선순위는 ① 사용자가 지정한 이름 → ② `sourceFrameDisplayName` →
  ③ **가져온 파일일 때(`sourceKind == .importedFile`) 원본 파일 이름(확장자 제외)** →
  ④ `Frame N`. 즉 "가져오기"로 들어온 사진은 결과적으로 파일 이름과 같아 보일 수 있지만,
  그것은 표시 이름이 파일 이름에서 왔기 때문이지 `{name}` 이 파일 이름 토큰이어서가
  아닙니다. 스캔 프레임은 ④ 가 됩니다.

각 토큰의 출처는 `export-naming.json` 의 `tokenSources` 에 적어 두었습니다.

`{date}` 주의: `makeExportBatchPlans` 는 내부에서 `Date()` 를 씁니다. 위 파일 이름의
`20260815` 는 실행일입니다. 고정 날짜(2026-08-12)로 계산한 `exportBaseName` 값도 JSON 에
함께 있습니다.

---

## [작업 6] 메타데이터 정책

산출물: `task6-metadata-policy/` (`policy-*.tif` 4개, `metadata-policy.json`,
`tiff-tags.json`)

픽셀은 정책과 무관하므로 64×64 합성 이미지를 썼습니다. 실제 스캔 TIFF 에는 IPTC/GPS 가
없어 네 정책이 같은 결과를 내므로, 정책이 무엇을 지우는지 보이지 않습니다. 그래서 원본
메타데이터를 고정 상수로 넣었습니다(TIFF Artist/Copyright/ImageDescription/Make/Model,
EXIF LensModel/ISO/FNumber, IPTC By-line/CopyrightNotice/City/SubLocation/Province/Country
×2/Headline, GPS 위경도).

`exiftool` 이 이 머신에 없어 `tools/dump_tiff_tags.py` 로 파일의 IFD 를 직접 파싱했습니다.
따라서 아래 번호는 **디스크에 실제로 기록된 태그 번호**입니다.

| 정책 | byte | TIFF IFD0 | EXIF IFD | GPS IFD | IPTC(IIM) | XMP(700) |
|---|---|---|---|---|---|---|
| `minimal` | 28,284 | 271, 272, 282, 283, 296, 305, 306, 34665 (+구조 태그) | 36867, 36868, 36880, 36881, 36882, 37510, 40962, 40963 | 없음 | 없음 | 없음 |
| `copyrightOnly` | 28,102 | 315, 33432, 33723 (+구조 태그) | **없음** | 없음 | 2:80, 2:116 | 없음 |
| `removeLocation` | 30,127 | 270, 271, 272, 282, 283, 296, 305, 306, 315, 33432, 33723, 34665, 700 | 33437, 34855, 36867, 36868, 36880, 36881, 36882, 37510, 40962, 40963, 42036 | **없음** | 2:80, 2:105, 2:116 | 있음(위치 없음) |
| `all` | 30,613 | 270, 271, 272, 282, 283, 296, 305, 306, 315, 33432, 33723, 34665, 34853, 700 | 33437, 34855, 36867, 36868, 36880, 36881, 36882, 37510, 40962, 40963, 42036 | 1, 2, 3, 4 | 2:80, 2:90, 2:92, 2:95, 2:100, 2:101, 2:105, 2:116 | 있음(위치 포함) |

모든 파일에 공통으로 들어가는 구조 태그: 256 ImageWidth, 257 ImageLength,
258 BitsPerSample `[16,16,16]`, 259 Compression `1`(무압축), 262 PhotometricInterpretation `2`,
266 FillOrder, 273 StripOffsets, 274 Orientation `1`, 277 SamplesPerPixel `3`,
278 RowsPerStrip, 279 StripByteCounts, 284 PlanarConfiguration, 296 ResolutionUnit `2`,
339 SampleFormat, 34675 ICCProfile(3144 byte, sRGB).

값 예시(`all` 기준):

```
271   Make            ASCII  Seiko Epson
272   Model           ASCII  GT-X900
282   XResolution     RATIONAL  2400/1
305   Software        ASCII  negaflow golden harness
306   DateTime        ASCII  2026:01:02 03:04:05
315   Artist          ASCII  Song Habin
33432 Copyright       ASCII  (c) 2026 Song Habin
36867 DateTimeOriginal ASCII 2026:01:02 03:04:05
42036 LensModel       ASCII  Nikkor 50mm f/1.4
GPS 2 GPSLatitude     RATIONAL  37/1 34/1 2244/100
GPS 4 GPSLongitude    RATIONAL  126/1 58/1 4584/100
IPTC 2:92  Sub-location   Jongno-gu
IPTC 2:90  City           Seoul
```

정책별 관찰 사항:

- `minimal` 은 원본 메타데이터를 통째로 버리고(`filtered(for:)` 가 nil), negaflow 가 넣는
  스캐너/해상도/날짜/소프트웨어만 남깁니다. UserComment 는 `FilmType: colorNegative`
  뿐이고 **FilmStock 은 빠집니다**.
- `copyrightOnly` 는 조기 반환이라 **Make/Model/해상도/Software/DateTime/EXIF 전체가
  없습니다.** 남는 것은 TIFF Artist·Copyright 와 IPTC By-line·CopyrightNotice 뿐입니다.
- `removeLocation` 은 IPTC 위치 5개(City 2:90, SubLocation 2:92, Province 2:95,
  CountryCode 2:100, CountryName 2:101)를 지우고, `kCGImageMetadataShouldExcludeGPS` 로
  GPS IFD 전체를 막습니다. XMP 도 위치 없이 나갑니다(확인함).
- `all` 만 GPS IFD 와 위치가 든 XMP 를 남깁니다.

재계산:

```bash
python3 tools/dump_tiff_tags.py task6-metadata-policy/policy-all.tif
```

---

## 실행하지 못한 항목

없습니다. 다만 아래는 조건부입니다.

- **8100 IR**: `8100/` 폴더에 IR TIFF 가 없어 작업 2·3 은 V700 쌍으로만 했습니다.
  파일이 생기면 같은 하네스에 `NEGAFLOW_GOLDEN_INPUT_IR` 만 바꿔 그대로 돌릴 수 있습니다.
- **작업 4 의 이미지 폭**: Windows 가 쓴 원본 크기를 모릅니다. 추정하지 않고, 실제 스캔과
  규격 2:3 두 경우를 모두 실측해 두었습니다.
- **작업 6 의 원본 메타데이터**: 실제 스캔에 IPTC/GPS 가 없어 고정 합성값을 썼습니다.
  Windows 에서는 같은 고정값을 넣어야 대조가 성립합니다(값은 위와 JSON 에 전부 있음).

## 산출물 크기

합계 **1.3 GB** — `task1-pixels` 361 MB, `task1-pixels-8100` 833 MB,
`task3-grainmend` 90 MB, 나머지(JSON·작은 TIFF·도구) 합쳐 1 MB 미만.
전부 무압축 16-bit TIFF 라 큽니다. 커밋하지 않았습니다 — 저장소에 넣을지는 판단이
필요합니다(JSON 과 이 문서만 커밋하고 TIFF 는 별도 보관하는 편이 안전합니다).
