# Chroma Engine Notes

## 목표

`samples/000036.JPG`는 Fuji SP-3000 현상소 스캔 레퍼런스다. 현재 연결된 Plustek OpticFilm 8100 스캔 TIFF를 현상했을 때 레퍼런스에 최대한 가깝게 만들어야 한다.

이번 문제의 1차 목표는 전체 룩을 무리하게 맞추는 것이 아니라, `patch1`에서 남은 아래 결함을 실제 이미지와 수치로 줄이는 것이다.

- 암부 보라/자주색 컬러 노이즈
- 암부 휘도 노이즈
- 암부 표현력 부족
- 최저부가 0으로 붙는 계조 무너짐
- RGB 히스토그램의 암부/명부 분포 차이

## 현재 입력과 레퍼런스

- 레퍼런스: `samples/000036.JPG`
  - JPEG, `4003x2728`
  - EXIF: `FUJI PHOTO FILM CO., LTD.`, `SP-3000`, `FDi V4.5 / FRONTIER355/375-1.8-0E-014`
- 실제 스캔 원본: `/var/folders/wt/88c641tj50z4rzrm6pfdld6c0000gn/T/negaflow_app_6B53642B-D5CD-405E-9191-D966E808A687.tiff`
  - TIFF, `5088x3401`
  - Plustek OpticFilm 8100에서 앱 UI의 `Scan Next`로 직접 획득

## 외부 방법론 메모

- darktable `negadoctor`는 스캔 네거티브를 처리하는 모듈이며, 네거티브 촬영/스캔 시 센서 동적 범위를 충분히 쓰고 클리핑하지 않는 노출을 강조한다. 필름 베이스와 조명 기준을 분리해서 다루는 것이 핵심이다. 참고: https://docs.darktable.org/usermanual/development/en/module-reference/processing-modules/negadoctor/
- darktable의 기존 `invert`/네거티브 처리 설명은 컬러 네거티브가 오렌지 베이스와 화이트밸런스 때문에 더 까다롭고, 미노광 필름 샘플이 필요하다고 설명한다. 참고: https://www.darktable.org/2020/08/darktable-3-2/
- RawTherapee의 `Film Negative` 도구는 raw 네거티브 반전을 별도 도구로 다루며, 필름 베이스 RGB를 찍는 워크플로가 널리 쓰인다. 참고: https://rawpedia.rawtherapee.com/Film_Negative
- Plustek 공식 페이지는 OpticFilm 8100에서 `SilverFast Multi-Exposure`가 암부 디테일을 더 드러내고 노이즈를 줄인다고 설명한다. 현재 앱 스캔이 단일 노출이면 SP-3000 대비 암부 노이즈와 계조에서 불리할 수 있다. 참고: https://plustek.com/us/products/film-photo-scanners/opticfilm-8100/
- SilverFast/VueScan 계열 방법론은 둘로 나뉜다.
  - Multi-Exposure: 센서/램프 노출 조건을 실제로 바꿔 같은 프레임을 두 번 이상 읽고, 짧은 노출은 얇은 필름/명부 클립 방지에, 긴 노출은 짙은 필름/암부 SNR 개선에 쓴다.
  - Multi-Sampling: 같은 노출로 여러 번 읽어 랜덤 노이즈를 평균으로 줄인다. 3회 평균이면 이상적인 랜덤 노이즈는 약 `sqrt(3)`만큼 줄어든다.
- 현재 설치된 Homebrew SANE 1.4.0에서 연결된 Plustek OpticFilm 8100의 `scanimage --help -d genesys:...` 실제 출력에는 `--exposure`/`--lamp-exposure`/`--scan-exposure-time`류 센서 노출 시간 옵션이 없다. 이 설치본의 공개 옵션만으로는 진짜 Multi-Exposure를 호출할 수 없다.
- 대신 `--brightness`, `--contrast`, `--gamma-table`은 노출 후 신호 매핑 옵션으로 노출 시간 제어가 아니다. 이것을 “하드웨어 HDR”이라고 부르면 안 된다.
- 다만 SANE upstream `backend/genesys/genesys.cpp`에는 `OPT_EXPOSURE_TIME`, `SANE_NAME_SCAN_EXPOS_TIME`, `settings.exposure_lperiod` 경로가 존재한다. `gl84x` 계열은 `REG_LPERIOD(0x38)`에 exposure period를 세팅한다. 다음 단계는 libusb를 새로 쓰는 것이 아니라, 해당 옵션이 포함된 `sane-backends` 빌드를 준비하고 `scanimage --scan-exposure-time`이 실제 장치에서 노출을 바꾸는지 실험하는 것이다.

## 2026-06-22 다중 패스 구현 결정

- `Sources/ScannerKit/SANEBackend.swift`에서 `multiExposureEnabled`를 소프트웨어 3패스 multi-sampling 모드로 구현한다. UI/CLI 표기는 실제 기능에 맞춰 `Multi-Sample`로 표시한다.
- 첫 시도였던 `brightness +28 / 0 / -28` 브라케팅은 폐기한다. 실제 검증 결과가 cyan/green으로 심하게 밀리고 전체 luma가 `0.65~0.78`에 몰려 계조가 무너졌다. `--brightness`는 센서 노출 시간이 아니라 후단 매핑이라 컬러 네거티브 raw의 채널 밀도 관계를 깨뜨린다.
- 현재 안전한 구현은 같은 scanimage 옵션으로 3회 스캔하고 평균하는 방식이다.
  1. 각 패스 TIFF를 Chromabase의 `loadScannerTIFF` 경로로 읽어, 단일 SANE TIFF와 같은 scanner raw linear 좌표계로 맞춘다.
  2. 패스별 median 정규화 없이 순수 산술 평균한다. 동일 노출 multi-sampling에서 밝기 정규화는 raw 밀도 스케일을 바꿔 필름 베이스 추정과 계조를 망가뜨렸다.
  3. 출력은 ICC 프로파일 없는 unsigned RGB 16-bit TIFF로 저장한다. Linear sRGB ICC를 붙이면 다음 로드에서 색관리 변환이 들어가 raw 스케일이 약 `0.24 → 0.047` 수준으로 눌리고 필름 베이스 추정이 실패했다.
- 한계: 동일 스캐너 이동을 세 번 반복하므로 패스 간 미세 misregistration이 생길 수 있다. 현재 구현은 full-frame 고정 홀더 전제이며, 필요하면 다음 루프에서 phase correlation/feature alignment를 추가한다.
- 실제 센서 노출 브라케팅은 `--scan-exposure-time`이 노출된 SANE 빌드에서 먼저 검증한다. upstream의 기본 범위는 `11000...0xFFFF`로 보이며, 장치/센서별 안전 범위는 실측해야 한다.

## 관측값

2026-06-21 기준 실측. 내부 3.5% 가장자리를 제외하고 계산했다.

| 이미지 | luma p1 | luma p5 | luma p20 | luma p50 | luma p95 | luma p99 | shadow chroma mean | shadow chroma std | shadow local luma noise |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| SP-3000 reference | 0.0656 | 0.1067 | 0.4569 | 0.7662 | 0.9566 | 0.9638 | 0.03675 | 0.03492 | 0.06123 |
| patch1 | 0.0000 | 0.0059 | 0.5763 | 0.7543 | 0.9109 | 0.9145 | 0.07159 | 0.08742 | 0.08164 |
| printgrade current | 0.0000 | 0.0039 | 0.5537 | 0.7629 | 0.9560 | 0.9602 | 0.05056 | 0.07409 | 0.07870 |
| patch5 printgrade 50 | 0.0098 | 0.0854 | 0.5468 | 0.7676 | 0.9364 | 0.9437 | 0.04432 | 0.05037 | 0.07415 |
| patch7 warm yellow | 0.0098 | 0.0793 | 0.4984 | 0.7732 | 0.9501 | 0.9554 | 0.03354 | 0.03273 | 0.06864 |

2026-06-21 추가 루프. 동일한 TIFF를 다시 현상하고, 같은 분석 스크립트 안에서 SP-3000/patch7/patch8을 비교했다.

| 이미지 | RGB mean | R/G | G/B | luma p20 | luma p50 | luma p95 | p50-p20 | shadow chroma mean | shadow chroma std | shadow local luma noise |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| SP-3000 reference | 0.7300 / 0.6853 / 0.6477 | 1.0652 | 1.0581 | 0.4570 | 0.7665 | 0.9566 | 0.3095 | 0.06047 | 0.04742 | 0.03585 |
| patch7 current baseline | 0.7268 / 0.7039 / 0.6542 | 1.0324 | 1.0760 | 0.4985 | 0.7732 | 0.9501 | 0.2748 | 0.07278 | 0.05116 | 0.01797 |
| patch8 warm yellow + mid contrast | 0.7212 / 0.7044 / 0.6456 | 1.0239 | 1.0910 | 0.4797 | 0.7817 | 0.9540 | 0.3020 | 0.07195 | 0.05237 | 0.01850 |

해석:

- `patch1`은 전체 밝기 방향은 좋아졌지만 최저부가 너무 많이 0에 붙어서 암부 계조가 무너진다.
- `patch1`의 암부 컬러 노이즈는 레퍼런스보다 약 2배 높다.
- `ScannerPrintGrade`는 명부 p95/p99를 레퍼런스 근처로 가져오지만, 최저부 0 클리핑과 암부 노이즈 문제는 해결하지 못한다. 전체 RGB 히스토그램 매핑은 유지하더라도 약하게 적용해야 한다.
- `patch5 printgrade 50`은 `patch1` 대비 암부 p5를 `0.0059 → 0.0854`로 회복했고, 암부 컬러 노이즈 평균을 `0.07159 → 0.04432`로 낮췄다. SP-3000 레퍼런스의 `0.03675`에는 아직 못 미치지만 문제 방향은 크게 줄었다.
- `patch7 warm yellow`는 patch5 대비 붉은 채널 평균을 `0.8041 → 0.7591`로 낮춰 SP-3000의 `0.7518` 근처까지 접근했다. G/B 비율은 `1.0244 → 1.0760`으로 올라가 노란 warm이 강해졌고, 암부 컬러 노이즈 평균은 `0.04432 → 0.03354`로 감소했다.
- `patch8 warm yellow + mid contrast`는 patch7 baseline 대비 B 평균을 `0.6542 → 0.6456`으로 낮추고 G/B를 `1.0760 → 1.0910`으로 올려 warm/yellow를 강화했다. 동시에 luma p20을 `0.4985 → 0.4797`로 낮추고 `p50-p20`을 `0.2748 → 0.3020`으로 늘려 SP-3000의 중간톤 대비(`0.3095`)에 더 가까워졌다. 암부 chroma 평균은 거의 유지됐지만 std는 소폭 증가해 다음 루프에서 ROI 정렬 후 재확인이 필요하다.

## 작업 가설

1. 필름 베이스 추정이 어두운 홀더/빈 공간/산발 퍼포레이션을 잡으면 밀도 반전이 틀어진다.
2. 반전의 paper black 입력점이 너무 높거나 급해서 암부가 0으로 붙고, 보라 컬러 노이즈가 더 선명해진다.
3. 후처리 노이즈 감소가 암부 색차만 충분히 억제하지 못하고, 일부 휘도 노이즈도 남긴다.
4. SP-3000처럼 보이게 하는 출력 그레이딩은 필요하지만, 전체 히스토그램을 강제로 맞추면 장면 고유 색과 암부 계조가 손상된다.

## 결정

- 우선순위는 `patch1` 기반 개선이다.
- 필름 베이스 후보는 실제 오렌지 마스크 성격과 연속성을 가져야 하며, 필름 베이스조차 없는 빈 공간은 제외한다.
- 암부는 완전한 0으로 많이 붙이면 안 된다. 레퍼런스처럼 p1/p5에 약간의 바닥을 남겨야 한다.
- 노이즈 감소는 positive 반전 이후, luma/chroma를 분리해서 암부 chroma에 더 강하게 적용한다.
- `ScannerPrintGrade`는 현재 상태 그대로 강제 적용하지 않는다. 필요하면 그림자 리프트와 약한 출력 숄더만 남기는 방향으로 축소한다.
- 전체 RGB 히스토그램을 100% 맞추면 암부 클리핑과 색 손상이 커진다. 현재는 SP-3000 목표 퍼센타일로 가는 채널별 곡선을 부분 블렌드하고, 붉은 채널을 낮추며 G/B 분리를 키워 노란 warm을 만든다.
- 중간톤 대비는 `ScannerPrintGrade` 내부의 약한 luma S-curve로 보강한다. patch5의 p20 `0.5468`은 레퍼런스 `0.4569`보다 너무 떠 있었고, patch7에서는 `0.4984`까지 낮아졌다.
- 암부는 전체 warm 그레이드와 분리한다. shadow balance는 R을 낮추고 G/B를 약하게 살려 보라/붉은 그림자 노이즈를 억제하지만, 마스크 강도는 낮춰 녹색 과잉을 피한다.
- 반전 곡선은 `blackDn` 아래를 완전 클립하지 않고 짧은 shadow toe를 둔다. 단, 미노광 필름 베이스 자체는 검정 기준으로 유지한다.
- 암부 노이즈 감소는 positive 반전 뒤에 적용한다. 깊은 암부에서는 색차를 약 45%만 보존해 보라/자주 노이즈를 낮추고, 휘도는 약하게만 평활한다.
- patch8에서는 전체 R을 더 올리는 대신 R p20/p50을 낮추고 B p20/p50/p80을 더 낮췄다. 사용자가 지적한 붉은 채널 평균 문제를 악화시키지 않으면서 노란 warm을 키우려면 blue-yellow 축을 우선 조정하는 편이 안전하다.
- 중간톤 대비는 luma curve의 0.25/0.50 지점을 낮추고 0.75 지점을 약간 올려 보강했다. 이 조정은 SP-3000 대비 낮은 미드톤이 떠 보이던 문제를 줄인다.

## 다음 실험

1. 같은 프레임을 멀티 익스포저 또는 멀티 샘플 스캔할 수 있으면 raw 단계에서 암부 노이즈 자체를 줄인다.
2. 현재 단일 스캔에서는 `patch7 warm yellow`를 기준으로, 다음 루프에서 암부가 SP-3000보다 약간 차갑게 보이는 문제와 하이라이트 하늘의 미세한 색차를 더 좁힌다.
3. 프레임마다 다른 필름 베이스/빈 공간/홀더 비율을 견디는지 샘플을 더 추가한다.
4. 가능하면 SP-3000 레퍼런스와 Plustek 스캔의 회전/크롭 정렬 후 같은 ROI별 히스토그램으로 비교한다.

## 2026-06-22 fresh scan 유효 루프

이 루프부터 이전 `/tmp` 후보와 다른 컷 비교는 폐기한다. 비교 대상은 아래 두 파일로 고정했다.

- SP-3000 레퍼런스: `samples/000036.JPG`
- 새 Plustek 스캔 원본: `scan_3600dpi.tiff`
  - 수정시각: `2026-06-22 02:05:03 +0900`
  - `scanimage --help -d genesys:...` 실제 출력에는 `--scan-exposure-time`/`--exposure` 계열 하드웨어 노출 옵션이 없었다.

웹 조사 결론은 유지한다.

- darktable `negadoctor`는 필름 동적 범위/화이트 포인트 조정 시 히스토그램을 보면서 하이라이트 클립을 피하라고 설명한다.
- RawTherapee `Film Negative`는 컬러 네거티브 반전을 별도 raw 네거티브 도구로 다룬다. 필름 베이스/마스크와 반전 좌표계를 분리하는 전제가 맞다.
- SANE genesys 백엔드는 현재 설치본에서 밝기/콘트라스트/감마 같은 소프트웨어 옵션만 노출한다. SANE 공개 옵션만으로 진짜 노출 브라케팅을 구현할 수 없었다.
- SilverFast Multi-Exposure는 같은 원고를 노출 시간이 다른 이중 스캔으로 읽어 명부/암부 정보를 합친다고 설명한다. 현재 앱의 multi-sample은 이와 다르고, 랜덤 노이즈 평균에 가깝다.

### fresh current 문제

`/tmp/negaflow_fresh_020427_current.jpg`는 같은 컷이 맞지만 SP-3000 대비 출력 DR이 무너졌다.

| 이미지 | R/G mean | G/B mean | luma p20 | luma p50 | luma p95 | high clip | shadow chroma mean/std |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| SP-3000 reference | 1.0660 | 1.0558 | 0.4570 | 0.7665 | 0.9566 | 0.00055 | 0.0605 / 0.0474 |
| fresh current | 0.9848 | 1.1644 | 0.7364 | 0.9585 | 1.0000 | 0.47546 | 0.1404 / 0.0857 |

해석:

- 명부 일부가 아니라 상위 톤의 넓은 영역이 255에 붙고 있었다.
- 암부/중간톤 컬러 노이즈도 SP-3000보다 컸지만, 먼저 하이라이트 클리핑을 막지 않으면 디테일/DR 비교가 의미 없다.
- 실패한 실험: luma percentile을 별도 `CIColorCube`/커널로 직접 맞추려 했지만 Core Image 내부 linear 좌표와 최종 JPEG 좌표가 엇갈려 오히려 클립을 키웠다. 폐기했다.

### patch20 결정

`ScannerPrintGrade`를 다음 방향으로 정리했다.

- RGB 목표 percentile을 실제 `000036.JPG`의 채널별 분위수에 맞췄다.
- 출력 커브 상단을 더 낮춰 SP-3000처럼 하이라이트 shoulder가 생기게 했다.
- 기존의 과한 shadow green/yellow 보정은 SP-3000 색비 기준으로 줄였다.
- 최종 강제 clamp는 중간톤까지 죽여 폐기했다.

최종 후보:

- `/tmp/negaflow_fresh_020427_final.jpg`
- 비교 시트: `/tmp/negaflow_fresh_020427_final_vs_000036.jpg`

| 이미지 | RGB mean | R/G mean | G/B mean | luma p20 | luma p50 | luma p95 | high clip | shadow chroma mean/std |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| SP-3000 reference | 0.7518 / 0.7053 / 0.6680 | 1.0660 | 1.0558 | 0.4570 | 0.7665 | 0.9566 | 0.00055 | 0.0605 / 0.0474 |
| fresh before | 0.8742 / 0.8876 / 0.7623 | 0.9848 | 1.1644 | 0.7364 | 0.9585 | 1.0000 | 0.47546 | 0.1404 / 0.0857 |
| fresh final | 0.7758 / 0.7155 / 0.6620 | 1.0842 | 1.0809 | 0.4177 | 0.8086 | 0.9801 | 0.00148 | 0.0736 / 0.0482 |

개선:

- high clip: `0.47546 -> 0.00148`
- RGB 평균: SP-3000 대비 매우 가까워짐. R/G는 약간 더 warm, G/B는 약간 더 yellow.
- shadow chroma std: `0.0857 -> 0.0482`로 SP-3000 `0.0474` 근처까지 감소.

남은 리스크:

- luma p1/p5가 SP-3000보다 높아 암부 바닥이 떠 보일 수 있다.
- luma p50이 SP-3000보다 약간 높고, p95/p99가 여전히 약간 높다.
- 암부 chroma mean은 SP-3000보다 높다. 단일 노출 스캔의 센서 노이즈와 컬러 노이즈는 multi-sample로만 일부 줄고, 진짜 multi-exposure 없이는 암부 SNR 한계가 남는다.
- 다음 유효 루프는 ROI 정렬 후 하늘/우하단/암부 패치별로 별도 지표를 잡아야 한다. 전체 히스토그램만 더 강하게 맞추면 다시 중간톤이나 색이 무너진다.

## 2026-06-22 riskfix2 루프

비교 대상은 계속 아래 두 파일로 고정했다. 이전 `/tmp` 후보와 다른 컷은 기준에서 제외한다.

- SP-3000 레퍼런스: `samples/000036.JPG`
- 새 Plustek 스캔 원본: `scan_3600dpi.tiff`

웹/문서 근거 재확인:

- darktable `negadoctor`는 네거티브 반전 후 출력 단계에서 black/white, exposure, paper grade를 분리해 다룬다. 즉 암부 toe, 중간톤 기울기, 하이라이트 shoulder를 한 커브로 뭉개지 않는 방향이 맞다. 참고: https://docs.darktable.org/usermanual/development/en/module-reference/processing-modules/negadoctor/
- RawTherapee `Film Negative`는 필름 베이스/마스크 기준점과 채널별 균형을 먼저 잡는 워크플로를 설명한다. 필름 여백/베이스가 아닌 빈 공간을 기준으로 쓰면 안 된다. 참고: https://rawpedia.rawtherapee.com/Film_Negative
- SANE 표준 옵션에는 `scan-exposure-time`/RGB exposure 계열 이름이 있지만, 현재 Homebrew SANE genesys 장치 help에는 노출 시간 옵션이 노출되지 않는다. `brightness/contrast/gamma-table`은 센서 노출 브라케팅이 아니므로 HDR 대체로 쓰지 않는다. 참고: https://gitlab.com/sane-project/backends/-/blob/master/include/sane/saneopts.h
- 컬러 노이즈는 luma와 chroma를 분리해서 chroma를 더 강하게 줄이는 방식이 안전하다. OpenCV의 `fastNlMeansDenoisingColored`도 컬러 이미지 노이즈에서 luminance/color component를 분리해 다루는 흐름을 쓴다. 참고: https://docs.opencv.org/4.x/d5/d69/tutorial_py_non_local_means.html

실패한 실험:

- `riskfix1`: 최종 JPEG 위에서 시험한 luma mask 커널을 Core Image linear 파이프라인에 그대로 넣었더니 실제 출력에서 `low_clip 0.25954`, `high_clip 0.37368`로 양끝 클리핑이 터졌다. 폐기했다.
- `floor16_strength72`: 최저부 p1/p5는 SP-3000에 가까워졌지만 luma p20이 `0.3573`까지 내려가 암부 중간톤이 죽었다. 폐기했다.
- `floor24_strength72`: p20 붕괴는 덜했지만 p1/p5 개선이 부족하고 shadow chroma mean이 올라갔다. 폐기했다.
- `shadow006`/`shadow010`: shadow chroma는 더 낮아졌지만 p20이 더 내려가고, 특히 `shadow006`은 chroma mean `0.0516`으로 SP-3000보다 과하게 중립화됐다. 폐기했다.

채택한 변경:

- `ScannerPrintGrade`의 채널별 SP-3000 percentile 매핑 강도를 `0.62 -> 0.72`로 올렸다. 전체 커브를 새로 얹지 않고, 기존 검증된 채널 매핑만 더 레퍼런스 쪽으로 이동한다.
- `applyDynamicRangeRecovery`의 deep shadow lift를 `0.018 -> 0.014`로 줄였다. 최저부가 너무 뜨는 문제를 약하게 낮추되 p20 붕괴를 피하기 위한 절충값이다.
- `ScannerNoiseReduction.reduceShadowChroma`에서 deep shadow chroma 보존량을 `45% -> 34%`로 낮추고 low-saturation/magenta 색차 블러를 강화했다. luma detail은 그대로 둔다.

최종 후보:

- `/tmp/negaflow_fresh_020427_riskfix2.jpg`
- 비교 시트: `/tmp/negaflow_fresh_020427_riskfix2_vs_000036.jpg`

| 이미지 | RGB mean | R/G mean | G/B mean | luma p1 | luma p5 | luma p20 | luma p50 | luma p95 | high clip | shadow chroma mean/std |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| SP-3000 reference | 0.7300 / 0.6853 / 0.6477 | 1.0652 | 1.0581 | 0.0656 | 0.1067 | 0.4570 | 0.7665 | 0.9566 | 0.00055 | 0.0605 / 0.0474 |
| previous final | 0.7709 / 0.7135 / 0.6602 | 1.0805 | 1.0806 | 0.1471 | 0.1983 | 0.4177 | 0.8086 | 0.9801 | 0.00148 | 0.0736 / 0.0482 |
| riskfix2 | 0.7570 / 0.7007 / 0.6408 | 1.0804 | 1.0935 | 0.1465 | 0.1884 | 0.4034 | 0.7789 | 0.9762 | 0.00078 | 0.0609 / 0.0442 |

해석:

- shadow chroma mean은 `0.0736 -> 0.0609`로 SP-3000 `0.0605`와 거의 같아졌다.
- shadow chroma std도 `0.0482 -> 0.0442`로 줄었다. 암부 보라/자주 컬러 노이즈 리스크는 이번 루프에서 크게 줄었다.
- luma p50은 `0.8086 -> 0.7789`로 SP-3000 `0.7665`에 가까워졌다.
- high clip은 `0.00148 -> 0.00078`로 줄었다.
- luma p95는 아직 `0.9762`로 SP-3000 `0.9566`보다 높다. 하이라이트 shoulder를 더 누를 여지는 남아 있다.
- luma p1/p5는 여전히 SP-3000보다 높다. 하지만 최저부 floor를 직접 낮추는 실험은 p20을 무너뜨렸으므로, 다음 루프에서는 전체 이미지 히스토그램이 아니라 ROI 정렬 후 실제 암부/우하단/하늘 영역별로 toe를 분리해야 한다.

## 2026-06-22 ROI shoulder/toe 루프

비교 대상은 계속 아래 두 파일만 사용했다.

- SP-3000 레퍼런스: `samples/000036.JPG`
- 새 Plustek 스캔 원본: `scan_3600dpi.tiff`

정렬:

- Plustek 후보 crop box: `(0.08250, 0.06750, 0.94750, 0.95500)`
- 후보는 crop 후 `180도 회전`해야 `000036.JPG`와 같은 방향이 된다.
- 이전 메모의 `deep_shadow: (0.08, 0.68, 0.42, 0.96)`는 실제로 밝은 하늘/명부 영역을 보고 있어 폐기했다. 암부 ROI는 오른쪽 기체/건물 그림자 영역으로 다시 잡았다.

최종 ROI:

- `sky_highlight`: `(0.03, 0.03, 0.38, 0.28)`
- `right_bottom_magenta_mid`: `(0.62, 0.60, 0.96, 0.94)`
- `deep_shadow`: `(0.68, 0.24, 0.96, 0.57)`
- `center_midtone`: `(0.34, 0.36, 0.66, 0.66)`

채택한 변경:

- `ScannerPrintGrade.applyDynamicRangeRecovery`에서 하이라이트 shoulder를 `smoothstep(0.72, 0.98, y)`로 더 일찍 시작하게 했다.
- high compression을 `0.72 + (y - 0.72) * 0.45`, cap `0.935`로 조정했다.
- deep toe는 `smoothstep(0.13, 0.31, y)`와 `0.006` 감산으로 제한했다. 최저부를 낮추되 실제 암부 p50까지 무너뜨리지 않기 위한 절충이다.
- 출력 print curve는 `p0 0.020`, `p1 0.158`, `p2 0.430`, `p3 0.520`, `p4 0.735`로 조정했다.
- 중간톤 low-sat chroma fade를 아주 약하게 추가했다. 실제 우하단 ROI의 chroma 문제를 완전히 해결하지는 못했지만, 하늘과 암부 계조를 크게 손상시키지 않는 범위로 제한했다.

최종 후보:

- `/tmp/negaflow_fresh_020427_roi_final.jpg`
- 비교 시트: `/tmp/negaflow_fresh_020427_roi_final_vs_000036.jpg`
- 지표 JSON: `/tmp/negaflow_fresh_020427_roi_final_metrics.json`

전체 지표:

| 이미지 | RGB mean | R/G | G/B | luma p01 | p05 | p20 | p50 | p95 | p99 | high clip | chroma mean/std |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| SP-3000 | 0.7395 / 0.6815 / 0.6582 | 1.0655 | 1.0547 | 0.0666 | 0.1095 | 0.4416 | 0.7640 | 0.9574 | 0.9658 | 0.00051 | 0.0666 / 0.0652 |
| ROI final | 0.7761 / 0.7106 / 0.6695 | 1.0667 | 1.0788 | 0.0888 | 0.1224 | 0.4393 | 0.8168 | 0.9566 | 0.9571 | 0.00017 | 0.0752 / 0.0860 |

ROI 지표:

| ROI | 이미지 | p01 | p05 | p20 | p50 | p95 | p99 | chroma mean/std | R/G | G/B |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| sky_highlight | SP-3000 | 0.8171 | 0.8331 | 0.8532 | 0.8776 | 0.9327 | 0.9437 | 0.0250 / 0.0079 | 1.0201 | 0.9816 |
| sky_highlight | ROI final | 0.8922 | 0.9068 | 0.9241 | 0.9387 | 0.9524 | 0.9532 | 0.0119 / 0.0085 | 0.9906 | 1.0031 |
| right_bottom_magenta_mid | SP-3000 | 0.0499 | 0.1116 | 0.5049 | 0.6269 | 0.7697 | 0.9041 | 0.1239 / 0.0445 | 1.1478 | 1.1783 |
| right_bottom_magenta_mid | ROI final | 0.0863 | 0.1194 | 0.5203 | 0.6647 | 0.8632 | 0.9448 | 0.1626 / 0.0663 | 1.1808 | 1.2430 |
| deep_shadow | SP-3000 | 0.0435 | 0.0648 | 0.0936 | 0.2378 | 0.6255 | 0.8772 | 0.0551 / 0.0447 | 1.0580 | 1.1307 |
| deep_shadow | ROI final | 0.0838 | 0.0877 | 0.1131 | 0.1767 | 0.6390 | 0.9311 | 0.0471 / 0.0430 | 1.1261 | 1.1044 |
| center_midtone | SP-3000 | 0.1991 | 0.3964 | 0.5970 | 0.7870 | 0.9554 | 0.9602 | 0.1001 / 0.0846 | 1.0991 | 1.0932 |
| center_midtone | ROI final | 0.3124 | 0.4121 | 0.6257 | 0.8386 | 0.9532 | 0.9571 | 0.1148 / 0.1054 | 1.0938 | 1.1192 |

해석:

- 전체 `p95/p99`와 high clip은 SP-3000에 훨씬 가까워졌다. 전체 히스토그램 기준으로 명부가 넓게 255에 붙는 문제는 줄었다.
- 하늘 ROI는 아직 SP-3000보다 밝다. 다만 이전 후보보다 shoulder가 생겨 p95/p99가 내려갔다.
- 실제 암부 ROI는 `p01/p05`가 여전히 SP-3000보다 높고, `p50`은 오히려 낮다. 전체 toe를 더 낮추면 암부 중간 계조가 더 막히므로 추가 toe 감산은 위험하다.
- 우하단 ROI의 chroma mean/std, R/G, G/B가 여전히 SP-3000보다 높다. 색보정 커브만으로는 이 영역의 컬러 노이즈/자주끼를 완전히 해결하지 못했다.

남은 리스크:

- 우하단 중간톤 컬러 노이즈와 warm/yellow 과다는 아직 남아 있다. 다음 루프는 luma를 더 누르는 것이 아니라, ROI 기반의 edge-preserving chroma denoise 또는 bilateral/guided chroma smoothing이 필요하다.
- 실제 암부는 최저부와 중간 암부가 동시에 맞지 않는다. 단일 스캔 SNR 한계가 있어 소프트웨어 toe만으로는 SP-3000식 암부 표현을 완전히 재현하기 어렵다.
- 하드웨어 multi-exposure는 여전히 미구현이다. 현재 genesys 공개 옵션의 `brightness/contrast/gamma-table`은 노출 브라케팅 대체가 아니다.

## 2026-06-22 midtone chroma denoise 루프

웹/문서 근거:

- RawTherapee RawPedia는 노이즈를 chrominance noise와 luminance noise로 분리하고, chrominance noise는 보통 제거 대상이지만 luminance noise는 필름 그레인처럼 남길 수 있다고 설명한다. 또한 강한 chrominance noise reduction은 색 번짐과 저주파 디테일 손실을 만들 수 있다고 경고한다. 참고: https://rawpedia.rawtherapee.com/Noise_Reduction
- darktable `denoise (profiled)`는 luma/chroma noise를 별도 처리할 수 있고, wavelet 모드에서는 luminance와 chroma noise를 독립 제어할 수 있다고 설명한다. 참고: https://docs.darktable.org/usermanual/development/en/module-reference/processing-modules/denoise-profiled/
- OpenCV의 bilateral filtering 설명은 Gaussian blur가 edge를 흐리지만 bilateral filter는 공간 거리와 intensity 차이를 같이 써서 edge를 보존한다고 설명한다. 참고: https://opencv24-python-tutorials.readthedocs.io/en/latest/py_tutorials/py_imgproc/py_filtering/py_filtering.html

채택한 방향:

- 우하단 ROI 문제는 luma를 더 누르는 문제가 아니라 중간톤 warm/purple chroma가 남는 문제로 판단했다.
- Core Image에서 별도 bilateral filter를 직접 쓰는 대신, 현재 파이프라인에 맞춰 `ScannerNoiseReduction.reduceMidtoneChroma`를 추가했다.
- 처리 방식은 원본 luma를 유지하고, blurred chroma만 중간톤/고색차/warm-purple mask로 약하게 섞는다. 따라서 luma edge는 유지하고 색차 얼룩만 줄이는 방향이다.
- warm/purple 축에서는 R/B chroma를 아주 약하게 축소해 우하단의 R/G, G/B 과다를 직접 낮췄다.

구현:

- `ScannerNoiseReduction.reduceShadowChroma` 마지막에 `reduceMidtoneChroma`를 추가했다.
- `reduceMidtoneChroma`는 Gaussian radius `4.8`, midtone mask `smoothstep(0.34, 0.52, y) * (1 - smoothstep(0.80, 0.94, y))`, warm/purple mask 기반 amount `0.34 + 0.28 * warmPurple`를 쓴다.
- 테스트 `testScannerNoiseReductionSoftensMidtoneChromaWithoutBleedingLumaEdges`를 추가해 중간톤 chroma가 줄고 luma edge가 유지되는지 잠갔다.

최종 후보:

- `/tmp/negaflow_fresh_020427_roi_final.jpg`
- 비교 시트: `/tmp/negaflow_fresh_020427_roi_final_vs_000036.jpg`
- 지표 JSON: `/tmp/negaflow_fresh_020427_roi_final_metrics.json`

ROI final 이전 대비 chroma3 결과:

| ROI | 지표 | 이전 ROI final | chroma3 final |
| --- | --- | ---: | ---: |
| 전체 | chroma mean/std | 0.0752 / 0.0860 | 0.0748 / 0.0840 |
| 전체 | high clip | 0.00017 | 0.00012 |
| right_bottom_magenta_mid | chroma mean/std | 0.1626 / 0.0663 | 0.1610 / 0.0652 |
| right_bottom_magenta_mid | R/G | 1.1808 | 1.1791 |
| right_bottom_magenta_mid | G/B | 1.2430 | 1.2401 |
| deep_shadow | chroma mean/std | 0.0471 / 0.0430 | 0.0471 / 0.0428 |
| center_midtone | chroma mean/std | 0.1148 / 0.1054 | 0.1137 / 0.1012 |

해석:

- 우하단 ROI 개선은 작지만 방향은 맞다. 색차 평균/표준편차와 R/G, G/B가 모두 내려갔다.
- 하늘 shoulder와 전체 p95/p99는 유지됐다.
- 이 방식만으로 SP-3000 우하단 chroma `0.1239 / 0.0445`까지는 못 간다. 더 강하게 걸면 RawPedia가 경고한 색 번짐/저주파 디테일 손실 위험이 커진다.

남은 리스크:

- 다음 단계는 단순 Gaussian chroma blur가 아니라 guided/bilateral 계열로 넘어가야 한다. Core Image 런타임에는 `CIGuidedFilter`가 있으므로, 다음 루프에서 chroma image를 luma guide로 필터링하는 방법을 실험한다.
- 암부 p50은 여전히 SP-3000보다 낮다. tone curve로만 올리면 하늘/중간톤이 다시 떠서, 암부 전용 luma-detail recovery가 필요하다.

## 2026-06-22 guided chroma / ROI tone 루프

비교 대상은 계속 아래 두 파일만 사용했다.

- SP-3000 레퍼런스: `samples/000036.JPG`
- 새 Plustek 스캔 원본: `scan_3600dpi.tiff`

웹/문서 근거 재확인:

- SilverFast Multi-Exposure는 서로 다른 노출로 필름을 스캔해 스캐너 동적 범위와 암부 디테일을 늘리는 방식이다. 즉 현재 SANE 공개 옵션에 노출 시간 제어가 없으면 소프트웨어 후처리만으로 같은 효과를 만들 수 없다. 참고: https://www.silverfast.com/show/ite-multiexposure/en.html
- VueScan `Number of samples`/`Number of passes`는 여러 샘플 또는 여러 패스를 평균해 노이즈를 줄이는 방식이다. `Number of passes`는 풀스캔을 반복하므로 정렬 오차가 있으면 흐려질 수 있다. 참고: https://www.hamrick.com/vuescan/html/vuesc29.htm
- RawTherapee 문서는 luminance noise와 chrominance noise를 분리해 설명한다. 이 루프에서는 luma/detail을 보존하고 chroma만 줄이는 방향을 유지한다. 참고: https://rawpedia.rawtherapee.com/Noise_Reduction
- Core Image 런타임에서 `CIGuidedFilter`가 실제로 사용 가능했고 `inputGuideImage`, `inputRadius`, `inputEpsilon` 파라미터가 확인됐다. 참고: https://developer.apple.com/library/archive/documentation/GraphicsImaging/Reference/CoreImageFilterReference/

채택한 변경:

- `ScannerNoiseReduction.reduceMidtoneChroma`를 Gaussian chroma blur에서 `CIGuidedFilter` 기반 chroma smoothing으로 바꿨다.
- 원본 luma를 guide image로 쓰고, 색차 이미지를 필터링한 뒤 재합성한다.
- 첫 guided 실험은 `guided.rgb - 0.5`를 바로 합성해 색차 안에 남은 luma 성분이 출력 luma를 들어올렸다. 실제 후보에서 high clip이 `0.05927`까지 늘어 폐기했다.
- 최종 구현은 guided chroma에서 `dot(guidedChroma, ycoef)`를 다시 빼서 luma 성분을 제거한다. 테스트도 luma 평균이 흔들리지 않는지 확인하도록 보강했다.

실패한 tone 실험:

- `applyOutputPrintCurve` 뒤에 별도 luma 커널로 shadow mid lift와 shoulder 압축을 넣었더니 p01/p05가 `0.219/0.2227`까지 떠서 폐기했다.
- output print curve의 p2/p3/p4를 낮추는 실험도 `testScannerPrintGradeMatchesSP3000ChannelBalanceAndShoulder`에서 중간톤 분리 기준을 깨서 폐기했다.
- 결론: 이번 단계에서 shoulder/toe를 후단 커널로 더 밀면 하늘/중간톤/암부 중 하나가 바로 무너진다. 현 단계의 안전한 개선은 chroma-only guided denoise로 제한한다.

최종 후보:

- `/tmp/negaflow_fresh_020427_guided_final.jpg`
- 비교 시트: `/tmp/negaflow_fresh_020427_guided_final_vs_000036.jpg`
- 지표 JSON: `/tmp/negaflow_fresh_020427_guided_final_metrics.json`

전체 지표:

| 이미지 | RGB mean | R/G | G/B | p01 | p05 | p20 | p50 | p95 | p99 | high clip | chroma mean/std |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| SP-3000 | 0.7395 / 0.6815 / 0.6582 | 1.0852 | 1.0354 | 0.0666 | 0.1095 | 0.4416 | 0.7640 | 0.9574 | 0.9658 | 0.00051 | 0.0666 / 0.0652 |
| previous ROI final | 0.7753 / 0.7105 / 0.6696 | 1.0912 | 1.0611 | 0.0888 | 0.1224 | 0.4388 | 0.8169 | 0.9566 | 0.9571 | 0.00013 | 0.0748 / 0.0840 |
| guided final | 0.7741 / 0.7105 / 0.6699 | 1.0895 | 1.0606 | 0.0888 | 0.1224 | 0.4387 | 0.8169 | 0.9566 | 0.9571 | 0.00010 | 0.0737 / 0.0821 |

ROI 지표:

| ROI | 이미지 | p01 | p05 | p20 | p50 | p95 | p99 | chroma mean/std | R/G | G/B |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| sky_highlight | SP-3000 | 0.8171 | 0.8331 | 0.8532 | 0.8776 | 0.9327 | 0.9437 | 0.0250 / 0.0079 | 1.0173 | 0.9835 |
| sky_highlight | guided final | 0.8922 | 0.9076 | 0.9244 | 0.9390 | 0.9532 | 0.9532 | 0.0119 / 0.0084 | 0.9914 | 0.9997 |
| right_bottom_magenta_mid | SP-3000 | 0.0499 | 0.1116 | 0.5049 | 0.6269 | 0.7697 | 0.9041 | 0.1239 / 0.0445 | 1.1474 | 1.1777 |
| right_bottom_magenta_mid | guided final | 0.0863 | 0.1189 | 0.5174 | 0.6635 | 0.8659 | 0.9448 | 0.1586 / 0.0643 | 1.1759 | 1.2352 |
| deep_shadow | SP-3000 | 0.0435 | 0.0648 | 0.0936 | 0.2378 | 0.6255 | 0.8772 | 0.0551 / 0.0447 | 1.0578 | 1.1300 |
| deep_shadow | guided final | 0.0838 | 0.0877 | 0.1130 | 0.1759 | 0.6348 | 0.9311 | 0.0469 / 0.0424 | 1.1250 | 1.1038 |
| center_midtone | SP-3000 | 0.1991 | 0.3964 | 0.5970 | 0.7870 | 0.9554 | 0.9602 | 0.1001 / 0.0846 | 1.0986 | 1.0903 |
| center_midtone | guided final | 0.3125 | 0.4120 | 0.6237 | 0.8388 | 0.9532 | 0.9566 | 0.1113 / 0.0980 | 1.0919 | 1.1116 |

해석:

- 전체 chroma mean/std는 `0.0748 / 0.0840 -> 0.0737 / 0.0821`로 줄었다.
- 우하단 ROI chroma mean/std는 `0.1607 / 0.0655 -> 0.1586 / 0.0643`으로 줄었고 R/G, G/B도 조금 내려갔다.
- center midtone chroma mean/std는 `0.1137 / 0.1012 -> 0.1113 / 0.0980`으로 줄었다.
- 하늘/암부 luma percentiles와 high clip은 유지됐다. 즉 이번 변경은 DR/shoulder를 다시 깨지 않고 chroma만 약하게 줄인 안전한 개선이다.

남은 리스크:

- 우하단 ROI는 SP-3000 목표 `0.1239 / 0.0445`까지 아직 멀다. 후처리 chroma-only denoise로 더 강하게 밀면 색 번짐/저주파 색 디테일 손실 위험이 커진다.
- 하늘 ROI는 여전히 SP-3000보다 밝고 chroma가 낮다. 단순 shoulder 강화는 중간톤 분리를 깨거나 암부 바닥을 띄웠다.
- 실제 암부 p50은 SP-3000보다 낮다. toe를 전역 조정하면 암부 p01/p05와 우하단 최저부가 먼저 망가진다.
- 다음 단계는 raw 단계에서 정렬된 multi-pass 평균을 안정화하거나, SANE genesys의 실제 exposure time 옵션을 노출한 빌드를 준비해 하드웨어 multi-exposure 가능성을 검증하는 것이다.

## 2026-06-22 sky shoulder / hardware exposure 재정리 루프

비교 대상은 계속 두 파일로 고정했다.

- SP-3000 레퍼런스: `samples/000036.JPG`
- 현재 스캐너 원본: `scan_3600dpi.tiff`, 정렬 multi-pass 원본: `scan_3600dpi_hdr.tiff`

웹/소스 근거:

- VueScan의 `Number of samples`/`Number of passes` 계열은 여러 샘플/패스를 평균해 랜덤 노이즈를 줄이는 방식이다. 패스 반복은 정렬 오차가 있으면 흐림을 만들 수 있다. 참고: https://www.hamrick.com/vuescan/html/vuesc29.htm
- SilverFast Multi-Exposure는 서로 다른 노출로 읽어 동적 범위와 암부 디테일을 늘리는 방식이다. 동일 노출 평균과 다르다. 참고: https://www.silverfast.com/show/ite-multiexposure/en.html
- SANE 표준 헤더에는 `scan-exposure-time`, `scan-exposure-time-r/g/b` 이름이 있다. 참고: https://gitlab.com/sane-project/backends/-/raw/master/include/sane/saneopts.h
- SANE upstream `backend/genesys/genesys.cpp`에는 `OPT_EXPOSURE_TIME`, `SANE_NAME_SCAN_EXPOS_TIME`, `settings.exposure_lperiod` 경로가 있고 range가 `11000...0xFFFF`로 잡힌다. 즉 원천적으로 genesys에 노출 시간 경로가 없는 것은 아니다.
- 하지만 현재 로컬 장치(`scanimage (sane-backends) 1.4.0`, `PLUSTEK OpticFilm 8100`)의 `scanimage --help`에는 `--scan-exposure-time`이 노출되지 않는다. 현재 공개 옵션은 `--brightness`, `--contrast`, `--custom-gamma`, `--gamma-table` 계열뿐이다.

실험 결과:

- `skyfix5`, `skyfix6`, `skyfix7`은 실제 JPG ROI 기준에서 하늘 p50/p95를 유의미하게 움직이지 못했다.
- 대표 지표:
  - SP-3000 `sky_highlight`: p50 `0.8776`, p95 `0.9327`, p99 `0.9437`
  - 단일 스캔 후보: p50 약 `0.9381`, p95 `0.9532`, p99 `0.9532`
  - 정렬 multi-pass 후보: p50 약 `0.9403`, p95 `0.9532`, p99 `0.9532`
- `ScannerPrintGrade.apply`를 극단적으로 어둡게 하는 토글은 CLI 출력 평균을 `0.121`로 바꿨다. 즉 scanner print grade 경로는 실제 CLI에 닿는다.
- 그러나 low-chroma highlight shoulder 커널은 synthetic 입력에서는 `RGB 240 -> 202`로 동작했지만, 실제 스캔 후보의 하늘 ROI에는 실효가 없었다. 실제 파이프라인 내부 값/색공간에서 조건이 하늘을 제대로 잡지 못하는 것으로 판단한다.
- output print curve의 p2/p3/p4를 낮추는 전역 shoulder 실험은 `testScannerPrintGradeMatchesSP3000ChannelBalanceAndShoulder`의 낮은 미드톤/중간톤 분리 기준을 깨서 폐기했다. 하늘 하나를 위해 전역 curve를 낮추면 중간톤 DR이 먼저 무너진다.

코드 정정:

- `SANEBackend.parseCapabilities`가 `--brightness`/`--gamma-table`만 보고 `supportsMultiExposure = true`로 표시하던 오인을 고쳤다.
- 이제 `supportsMultiExposure`는 `--scan-exposure-time`이 실제 `scanimage --help`에 노출될 때만 true다.
- 현재 연결 장치에서 `swift run negaflow capabilities sane-genesys:libusb:000:007` 결과는 `multiSample : false`다.
- `--hdr` 경고 문구도 `hardware HDR`이 아니라 `동일 노출 3-pass 평균 노이즈 저감`임을 명확히 바꿨다.

현재 결론:

- 단일 스캔 품질은 색감/전체 톤은 어느 정도 맞지만, 하늘 명부 계조는 SP-3000 대비 여전히 밝고 평탄하다.
- 정렬 multi-pass는 우하단/암부 local noise를 확실히 낮춘다. 하지만 동일 노출 평균이라 하늘의 새 계조 정보는 생기지 않는다.
- 하늘 DR 문제는 소프트웨어 후단 curve만으로 밀면 중간톤 분리나 암부 toe가 망가진다. 다음 유효한 방향은 upstream genesys `scan-exposure-time` 옵션이 이 장치에서 왜 숨는지 확인하고, 노출 시간이 실제 raw 값을 바꾸는지 검증하는 것이다.

남은 리스크 / 다음 단계:

1. Homebrew 빌드의 genesys option table에서 `scan-exposure-time`이 모델 플래그로 숨는지, 또는 현재 장치 센서 정의에서 option이 disable되는지 확인한다.
2. 별도 sane-backends 소스 빌드 또는 패치 빌드로 `scanimage --scan-exposure-time=<value>`를 실험한다.
3. 값이 실제 raw histogram을 바꾸면 3-pass를 `short / normal / long exposure`로 찍고, 정렬 후 highlight는 short, shadow는 long, midtone은 normal 중심으로 합성한다.
4. 값이 raw histogram을 바꾸지 않으면 이 장치/백엔드 조합에서는 하드웨어 multi-exposure가 불가능하므로, 하늘 계조는 별도 local tone reconstruction으로만 제한적으로 처리한다.

## 2026-06-22 upstream genesys scan-exposure-time 실제 장치 검증

목표:

- Homebrew stable SANE가 아니라 upstream `sane-backends` HEAD의 `genesys` 백엔드를 별도 prefix로 빌드한다.
- 실제 Plustek OpticFilm 8100에서 `--scan-exposure-time`이 help에만 보이는지, 아니면 raw 신호를 실제로 바꾸는지 검증한다.

빌드/실행 경로:

- upstream checkout: `/tmp/sane-backends-head`
- upstream revision: `ca8d120` (`1.4.0.106-ca8d1`)
- install prefix: `/tmp/sane-head-install`
- 실행 바이너리: `/tmp/sane-head-install/bin/scanimage`
- 기존 Homebrew stable: `/opt/homebrew/bin/scanimage`, `sane-backends 1.4.0`

빌드 메모:

- `autogen.sh`에는 GNU `grep`과 `autoconf-archive`가 필요했다.
- shallow clone 상태에서는 버전 생성기가 `.tarball-version`을 빈 파일로 만들며 `V_MAJOR=UNKNOWN` 컴파일 실패가 났다. `git fetch --unshallow` 후 `git describe`가 `1.4.0-106-gca8d1`로 정상화되자 빌드가 통과했다.
- configure는 기존 SANE를 덮지 않도록 아래 방향으로 실행했다.
  - `BACKENDS="genesys"`
  - `PRELOADABLE_BACKENDS="genesys"`
  - `--prefix=/tmp/sane-head-install`
  - `--sysconfdir=/tmp/sane-head-install/etc`

확인된 사실:

- Homebrew stable `libsane-genesys.1.so`에는 `scan-exposure-time` 문자열이 없다.
- upstream HEAD `libsane-genesys.1.so`에는 `scan-exposure-time` 문자열이 있다.
- 새 scanimage는 `/tmp/sane-head-install/lib/libsane.1.dylib`를 링크한다.
- 새 backend 로딩 로그는 `/tmp/sane-head-install/lib/sane/libsane-genesys.1.so`를 실제로 `dlopen()`한다.
- 실제 장치 help:
  - `--scan-exposure-time 11000..65535 [14000]`

장치 주소 주의:

- Plustek/genesys는 호출 사이에 `genesys:libusb:000:007`과 `genesys:libusb:000:010`처럼 주소가 바뀐다.
- stale 주소로 열면 `scanimage: open of device ... failed: Invalid argument`가 난다.
- 따라서 각 scan 직전에 `scanimage -L`로 현재 주소를 다시 파싱해야 한다.

실제 raw 테스트:

- 같은 ROI, 600dpi, 16bit PNM으로 `--scan-exposure-time`만 바꿔 스캔했다.
- 산출물:
  - `/tmp/negaflow_sane_exposure_11000.pnm`
  - `/tmp/negaflow_sane_exposure_14000.pnm`
  - `/tmp/negaflow_sane_exposure_30000.pnm`
  - `/tmp/negaflow_sane_exposure_65535.pnm`
  - `/tmp/negaflow_sane_exposure_metrics.json`

측정값:

| exposure | RGB mean | RGB p50 | RGB p99 |
| ---: | ---: | ---: | ---: |
| 11000 | 4973 / 2403 / 1665 | 4546 / 2161 / 1564 | 10535 / 5662 / 4110 |
| 14000 | 6332 / 3060 / 2127 | 5761 / 2735 / 1993 | 13428 / 7208 / 5251 |
| 30000 | 13673 / 6601 / 4591 | 12386 / 5878 / 4298 | 29254 / 15606 / 11312 |
| 65535 | 30345 / 14619 / 10143 | 27418 / 12979 / 9472 | 65535 / 35057 / 25191 |

해석:

- raw 평균과 percentile이 exposure time에 따라 단조 증가했다.
- `65535`에서는 R p99가 65535에 닿아 실제 클리핑이 발생했다.
- 결론: upstream HEAD `genesys`의 `scan-exposure-time`은 이 실제 장치에서 죽은 옵션이 아니고 센서 raw 신호를 바꾼다.

코드 반영:

- `ScanOptions.hardwareExposureTime`을 추가했다.
- `SANEBackend.makeScanimageArgs`가 `hardwareExposureTime`을 `--scan-exposure-time=<value>`로 전달한다.
- `NEGAFLOW_SCANIMAGE_PATH=/tmp/sane-head-install/bin/scanimage`로 앱/CLI가 별도 HEAD scanimage를 사용할 수 있게 했다.
- scanimage override prefix에서 `etc/sane.d`와 `lib/sane`를 우선 찾도록 했다.
- multi-sample 실행 시 `scan-exposure-time` capability가 있으면 `11000 / 14000 / 30000` 3패스를 찍고, raw linear 공간에서 exposure-normalized merge를 수행한다.
- `65535`는 실측에서 R 채널 clipping이 발생했으므로 자동 브라켓 기본값에서 제외했다.

남은 리스크:

- 이 HEAD backend는 Homebrew stable이 아니므로 앱 배포용으로는 별도 번들링/설치 전략이 필요하다.
- 현재 hardware exposure merge는 conservative한 3패스 초기값이다. 전체 35mm 프레임에서 하늘 ROI, 우하단 ROI, 암부 ROI를 SP-3000 `samples/000036.JPG`와 다시 비교해야 한다.
- `scan-exposure-time-r/g/b`는 아직 실제 help에 노출되지 않았다. 채널별 노출 보정은 현재 경로에서 하지 않는다.

## 2026-06-22 hardware exposure merge 리스크 수정

문제:

- 첫 hardware exposure 결과 `/tmp/negaflow_hwexp_600dpi_hdr_developed.jpg`는 노이즈는 줄었지만 전체 톤이 너무 어두웠다.
- SP-3000 대비 전체 luma p50이 `0.7640 -> 0.4139`, 하늘 ROI p50이 `0.8776 -> 0.4374`까지 내려갔다.
- 원인 후보는 `11k/14k/30k` 세 패스를 모두 14k 기준으로 정규화한 뒤 가중 평균하면서, 정상 14k 패스의 raw 스케일을 보존하지 못하는 병합 방식이었다.

웹/문서 근거:

- SANE 표준 옵션에는 `SANE_NAME_SCAN_EXPOS_TIME` / `scan-exposure-time`과 RGB별 exposure-time 이름이 존재한다. 참고: https://gitlab.com/sane-project/backends/-/raw/master/include/sane/saneopts.h
- VueScan 문서는 `Number of samples`와 `Number of passes`가 평균으로 노이즈를 줄이는 기능이고, `Multi exposure`는 CCD exposure time을 늘린 두 번째 패스를 어두운 영역 디테일 복구에 쓰는 기능이라고 설명한다. 참고: https://www.hamrick.com/vuescan/html/vuesc29.htm
- SilverFast Multi-Exposure 설명도 서로 다른 노출로 스캔해 스캐너 DR을 더 쓰고, 특히 shadow detail과 컬러 얼룩을 개선한다고 설명한다. 참고: https://www.silverfast.com/show/ite-multiexposure/en.html

코드 변경:

- `mergeHardwareExposureBitmap`을 baseline-preserving merge로 바꿨다.
  - 14k normal pass를 기본값으로 보존한다.
  - normal pass raw가 포화 근처일 때만 11k short pass를 섞어 highlight clip을 피한다.
  - normal pass raw가 너무 낮은 저신호 영역일 때만 30k long pass를 섞어 shadow SNR을 보강한다.
- `NEGAFLOW_KEEP_MULTIPASS=1`을 추가했다. 이 값이 있으면 세 패스 TIFF를 삭제하지 않고 `/var/folders/.../T/negaflow_multipass_sample*.tiff`에 남겨 패스별 raw 분석이 가능하다.
- 회귀 테스트를 추가했다.
  - clipped highlight는 short exposure에서 복원한다.
  - midtone은 14k normal exposure 스케일을 유지한다.

실제 장치 검증:

- 실행:
  - `NEGAFLOW_SCANIMAGE_PATH=/tmp/sane-head-install/bin/scanimage NEGAFLOW_KEEP_MULTIPASS=1 swift run negaflow scan --dpi 600 --hdr`
- 결과:
  - `/tmp/negaflow_hwexp_600dpi_hdr_baseline_merge_20260622_1815.tiff`
  - `/tmp/negaflow_hwexp_600dpi_hdr_baseline_merge_20260622_1815_developed.jpg`
  - `/tmp/negaflow_hwexp_600dpi_hdr_baseline_merge_20260622_1815_metrics.json`
  - `/tmp/negaflow_hwexp_600dpi_hdr_baseline_merge_20260622_1815_vs_000036.jpg`
- 보존된 pass TIFF:
  - sample1 = `11000`
  - sample2 = `14000`
  - sample3 = `30000`

raw TIFF 확인:

| 이미지 | RGB mean | RGB p50 | luma p50 | luma p95 | luma p99 |
| --- | --- | --- | ---: | ---: | ---: |
| pass 11000 | 0.0712 / 0.0311 / 0.0198 | 0.0627 / 0.0275 / 0.0157 | 0.0341 | 0.0920 | 0.1071 |
| pass 14000 | 0.0911 / 0.0401 / 0.0258 | 0.0784 / 0.0353 / 0.0235 | 0.0436 | 0.1178 | 0.1370 |
| pass 30000 | 0.1992 / 0.0889 / 0.0580 | 0.1765 / 0.0784 / 0.0510 | 0.0967 | 0.2578 | 0.3000 |
| merged new | 0.0912 / 0.0402 / 0.0259 | 0.0784 / 0.0353 / 0.0235 | 0.0439 | 0.1178 | 0.1370 |

해석:

- 새 merged TIFF는 14k pass와 거의 같은 raw 스케일을 유지한다.
- 첫 hardware exposure 후보의 “전체가 어둡게 눌림” 원인은 raw 병합 정책 문제였고, 이번 루프에서 병합 단계 기준으로는 해결됐다.
- 비교 시 EXIF orientation을 적용하면 ROI가 뒤집혀 잘못된 수치가 나온다. 기존 루프와 동일하게 `000036.JPG`는 raw pixel orientation 그대로 쓰고, 후보는 crop 후 180도 회전해야 한다.

현상 후 SP-3000 비교:

| 영역 | 이미지 | p20 | p50 | p95 | chroma mean/std | R/G | G/B |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 전체 | SP-3000 | 0.4416 | 0.7640 | 0.9574 | 0.0666 / 0.0652 | 1.0655 | 1.0547 |
| 전체 | hardware exposure new | 0.4331 | 0.7987 | 0.9571 | 0.0700 / 0.0797 | 1.0631 | 1.0732 |
| sky_highlight | SP-3000 | 0.8532 | 0.8776 | 0.9327 | 0.0250 / 0.0079 | 1.0201 | 0.9816 |
| sky_highlight | hardware exposure new | 0.9222 | 0.9373 | 0.9524 | 0.0107 / 0.0069 | 0.9920 | 1.0037 |
| right_bottom_magenta_mid | SP-3000 | 0.5049 | 0.6269 | 0.7697 | 0.1239 / 0.0445 | 1.1478 | 1.1783 |
| right_bottom_magenta_mid | hardware exposure new | 0.5025 | 0.6490 | 0.8286 | 0.1540 / 0.0585 | 1.1759 | 1.2269 |
| deep_shadow | SP-3000 | 0.0936 | 0.2378 | 0.6255 | 0.0551 / 0.0447 | 1.0580 | 1.1307 |
| deep_shadow | hardware exposure new | 0.1055 | 0.2149 | 0.6060 | 0.0392 / 0.0354 | 1.1056 | 1.0842 |

해석:

- 전체 톤은 더 이상 이전 hardware exposure 후보처럼 어둡게 망가지지 않는다.
- 전체 p20/p95와 RGB 평균은 SP-3000에 근접했고, p50은 여전히 약간 높다.
- 하늘 ROI는 여전히 너무 밝고 chroma가 낮다. 즉 명부 shoulder/하늘 계조 리스크는 남아 있다.
- 우하단 ROI는 luma p20은 맞지만 p50/p95와 chroma mean/std가 높다. warm/yellow 및 자주끼/컬러 노이즈가 남아 있다.
- deep shadow는 chroma noise가 SP-3000보다 낮을 정도로 정리됐지만 R/G가 높고 G/B가 낮아 색 밸런스가 다르다.

추가 미세 조정:

- `ScannerNoiseReduction.reduceMidtoneChroma`의 guided chroma mix와 warm/purple 축 감쇠를 소폭 강화했다.
- 같은 hardware exposure TIFF를 재현상한 최종 후보:
  - `/tmp/negaflow_hwexp_600dpi_hdr_final3_20260622_1828_developed.jpg`
  - `/tmp/negaflow_hwexp_600dpi_hdr_final3_20260622_1828_metrics.json`
- 우하단 ROI chroma는 `0.1540 / 0.0585 -> 0.1528 / 0.0578`로 작게 낮아졌다.
- 하늘 shoulder용 별도 low-chroma highlight 커널도 실험했지만 실제 출력에서 하늘 p50/p95가 움직이지 않았다. 효과 없는 코드는 제거했다.

남은 리스크:

1. hardware exposure scan은 이제 실제 동작하지만, 하늘 명부는 여전히 SP-3000보다 밝다. 이건 raw 병합보다 현상 단계의 low-chroma highlight shoulder 또는 스캔 노출 세트 재조정 문제다.
2. 우하단 중간톤 컬러 노이즈/자주끼는 아직 SP-3000보다 높다. guided chroma denoise를 더 강하게 하면 색 번짐 리스크가 있으므로 ROI 기반/edge-preserving 방식으로만 조정해야 한다.
3. upstream SANE HEAD 의존성이 남아 있다. Homebrew stable에는 `scan-exposure-time`이 없으므로 앱 배포에는 HEAD genesys 번들링 또는 사용자 설치 경로 고정이 필요하다.

## 2026-06-22 출력단 sky shoulder 원인 확인

문제:

- 이전 low-chroma highlight shoulder는 synthetic 테스트에서는 동작했지만 실제 후보 JPG의 `sky_highlight` ROI 수치가 거의 움직이지 않았다.
- 원인은 ROI/캐시 문제가 아니라, Core Image 파이프라인의 후단 입력 좌표가 최종 JPEG sRGB 값과 달랐기 때문이다.

관찰:

- 비교 기준은 계속 `/Users/songhabin/Negaflow/samples/000036.JPG`만 사용한다.
- 후보는 `crop (0.0825, 0.0675, 0.9475, 0.9550)` 후 180도 회전한다.
- `ScannerOutputGrade` 입력 시점에서 실제 sky 원좌표 ROI는:
  - y20/y50/y95 = `0.3605 / 0.3741 / 0.3860`
  - chroma20/chroma50/chroma95 = `0.0058 / 0.0079 / 0.0207`
  - 기존 mask20/mask50/mask95 = `0 / 0 / 0`
- 즉 최종 JPEG에서 하늘이 `0.94`처럼 보여도, 후단 Core Image linear working 값은 `0.36~0.39`였고 기존 `0.76+` shoulder 마스크가 sky를 완전히 놓쳤다.
- `ToneMapper.applyToneCurves`가 마지막에 `clamped(to:)`를 반환하던 것도 후단 필터 입력 extent를 무한대로 만들 수 있어 `cropped(to:)`로 닫았다.

코드 변경:

- `ScannerOutputGrade`를 스캐너 네거티브 경로의 색/톤 처리 뒤에 추가했다.
- low-chroma sky shoulder는 후단 입력 기준 y `0.325~0.385`, chroma `0.012~0.050` 영역에만 작동한다.
- 높은 sky 값은 `upperHighlight`로 빠르게 pull을 줄여 p95/p99가 무너지는 것을 막는다.
- warm/purple 중간톤 축 감쇠는 luma 보존 상태에서 chroma.r/chroma.b만 약하게 낮춘다.

실제 후보:

- `/tmp/negaflow_hwexp_600dpi_hdr_outputgrade_final_20260622_1907.jpg`
- `/tmp/negaflow_hwexp_600dpi_hdr_outputgrade_final_20260622_1907_metrics.json`
- 중간톤 chroma 마스크 보정 후 최종 후보:
  - `/tmp/negaflow_hwexp_600dpi_hdr_outputgrade_chroma_20260622_1910.jpg`
  - `/tmp/negaflow_hwexp_600dpi_hdr_outputgrade_chroma_20260622_1910_metrics.json`

ROI 비교:

| 영역 | 이미지 | p20 | p50 | p95 | p99 | chroma mean/std | R/G | G/B |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| sky_highlight | SP-3000 | 0.8532 | 0.8776 | 0.9327 | 0.9437 | 0.0250 / 0.0079 | 1.0201 | 0.9816 |
| sky_highlight | 이전 후보 | 0.9224 | 0.9389 | 0.9524 | 0.9532 | 0.0099 / 0.0069 | 0.9932 | 1.0038 |
| sky_highlight | outputgrade chroma | 0.8852 | 0.9132 | 0.9484 | 0.9501 | 0.0151 / 0.0068 | 0.9962 | 1.0103 |
| right_bottom_magenta_mid | SP-3000 | 0.5051 | 0.6272 | 0.7701 | 0.9050 | 0.1239 / 0.0445 | 1.1478 | 1.1783 |
| right_bottom_magenta_mid | 이전 후보 | 0.4995 | 0.6485 | 0.8333 | 0.9423 | 0.1526 / 0.0578 | 1.1746 | 1.2249 |
| right_bottom_magenta_mid | outputgrade chroma | 0.4995 | 0.6484 | 0.8328 | 0.9253 | 0.1401 / 0.0491 | 1.1662 | 1.1961 |
| deep_shadow | SP-3000 | 0.0936 | 0.2369 | 0.6252 | 0.8753 | 0.0550 / 0.0447 | 1.0577 | 1.1305 |
| deep_shadow | 이전 후보 | 0.1058 | 0.2157 | 0.6010 | 0.9234 | 0.0391 / 0.0354 | 1.1057 | 1.0841 |
| deep_shadow | outputgrade chroma | 0.1058 | 0.2157 | 0.6015 | 0.9001 | 0.0390 / 0.0349 | 1.1058 | 1.0835 |

해석:

- 하늘이 붕 뜨는 문제는 일부 개선됐다. p50은 `0.9389 -> 0.9132`, p95는 `0.9524 -> 0.9484`로 내려갔다.
- SP-3000 p50 `0.8776`까지 더 내리면 sky p95와 center midtone p95가 같이 죽는 경향이 있어 이번 루프에서는 보수적으로 멈춘다.
- 우하단은 후단 입력 기준 y20/y50/y95가 `0.0743 / 0.1350 / 0.2698`로, 기존 midtone 마스크 `0.28~0.48` 아래에 있어 axis가 전부 `0`이었다. 마스크를 `0.070~0.180`에서 시작하게 낮추자 chroma mean/std가 `0.1526 / 0.0578 -> 0.1401 / 0.0491`로 내려갔다.
- 출력단 shoulder는 DR을 새로 만드는 알고리즘이 아니라, 이미 있는 하늘 값을 덜 뜨게 보이도록 paper shoulder를 맞추는 보정이다. 진짜 하이라이트 계조 확보는 여전히 raw 단계 exposure bracket/merge 품질에 의존한다.

검증:

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'ChromabaseTests/testScannerOutputGrade'` 통과.

남은 리스크:

1. sky p50은 개선됐지만 아직 SP-3000보다 높고, sky chroma/RG/GB는 여전히 SP-3000과 다르다.
2. right_bottom_magenta_mid의 chroma/cstd는 줄었지만 아직 SP-3000보다 높다.
3. `ScannerOutputGrade`가 center midtone p95를 소폭 낮춘다. 현재는 과도하지 않지만 추가 shoulder 강화 시 중간톤 DR이 먼저 망가질 수 있다.
4. upstream SANE HEAD 의존성은 그대로 남아 있다.

## 2026-06-22 출력단 chroma/shoulder 추가 루프

목표:

- 비교 기준은 계속 `/Users/songhabin/Negaflow/samples/000036.JPG`만 사용한다.
- 후보는 hardware exposure merge TIFF `/tmp/negaflow_hwexp_600dpi_hdr_baseline_merge_20260622_1815.tiff`를 재현상한다.
- 후보 정렬은 기존과 동일하게 `crop (0.0825, 0.0675, 0.9475, 0.9550)` 후 `180도 회전`한다.
- 전체 히스토그램이 아니라 `sky_highlight`, `right_bottom_magenta_mid`, `deep_shadow`, `center_midtone` ROI별로 판단한다.

웹/장치 확인:

- SANE upstream `saneopts.h`에는 `SANE_NAME_SCAN_EXPOS_TIME`, `SANE_NAME_SCAN_EXPOS_TIME_R/G/B`가 정의되어 있고 설명은 scan exposure-time이다.
- 현재 실제 장치의 upstream HEAD `scanimage`도 `genesys:libusb:000:007`에서 `--scan-exposure-time 11000..65535 [14000]`를 노출한다.
- `scanimage (sane-backends) 1.4.0.106-ca8d1; backend version 1.4.0` 기준이다.
- 따라서 지금 경로는 Homebrew stable의 brightness/contrast/gamma-table 우회가 아니라, upstream genesys의 실제 scan exposure-time 옵션을 쓰는 경로로 본다.
- 다만 앱 배포 리스크는 남는다. Homebrew stable이나 다른 SANE 빌드에서 같은 옵션이 항상 노출된다고 가정하면 안 된다.

변경:

- `ScannerOutputGrade`의 low-chroma sky shoulder를 조금 강화했다.
  - 하늘 후단 입력 y `0.325~0.385`에서 low-chroma 영역을 더 내려, SP-3000 대비 하늘이 하얗게 뜨는 p50을 낮춘다.
  - upper highlight 쪽 pull은 그대로 약하게 유지해 p95/p99를 과하게 회색으로 만들지 않는다.
- 하늘 tint는 R/B가 G보다 같이 살아나는 방향으로 바꿨다.
  - 이전 `chroma3`는 G/B는 좋아졌지만 sky chroma가 `0.0119`까지 낮아져 하늘이 다시 회색에 가까워졌다.
  - 새 값은 SP-3000의 하늘 색비(R/G > 1, G/B < 1)에 더 가깝게 맞춘다.
- 우하단 warm/purple 중간톤 축 감쇠를 강화했다.
  - luma는 거의 건드리지 않고 chroma.r/chroma.b 축만 줄여 우하단 자주빛/컬러 노이즈를 줄인다.

실제 후보:

- `/tmp/negaflow_hwexp_600dpi_hdr_outputgrade_chroma4_20260622_1920.jpg`
- `/tmp/negaflow_hwexp_600dpi_hdr_outputgrade_chroma4_20260622_1920_metrics.json`
- 최종 후보:
  - `/tmp/negaflow_hwexp_600dpi_hdr_outputgrade_chroma5_20260622_1922.jpg`
  - `/tmp/negaflow_hwexp_600dpi_hdr_outputgrade_chroma5_20260622_1922_metrics.json`

ROI 비교:

| 영역 | 이미지 | p20 | p50 | p95 | p99 | chroma mean/std | R/G | G/B |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| sky_highlight | SP-3000 | 0.8532 | 0.8776 | 0.9327 | 0.9437 | 0.0250 / 0.0079 | 1.0173 | 0.9835 |
| sky_highlight | chroma4 | 0.8843 | 0.9137 | 0.9501 | 0.9518 | 0.0200 / 0.0110 | 1.0127 | 0.9855 |
| sky_highlight | chroma5 | 0.8754 | 0.9078 | 0.9501 | 0.9518 | 0.0189 / 0.0113 | 1.0113 | 0.9871 |
| right_bottom_magenta_mid | SP-3000 | 0.5049 | 0.6269 | 0.7697 | 0.9041 | 0.1239 / 0.0445 | 1.1474 | 1.1777 |
| right_bottom_magenta_mid | chroma4 | 0.5006 | 0.6485 | 0.8333 | 0.9253 | 0.1387 / 0.0484 | 1.1660 | 1.1913 |
| right_bottom_magenta_mid | chroma5 | 0.5009 | 0.6485 | 0.8336 | 0.9214 | 0.1312 / 0.0444 | 1.1603 | 1.1753 |
| deep_shadow | SP-3000 | 0.0936 | 0.2378 | 0.6255 | 0.8772 | 0.0551 / 0.0447 | 1.0578 | 1.1300 |
| deep_shadow | chroma4 | 0.1059 | 0.2166 | 0.6061 | 0.9016 | 0.0391 / 0.0349 | 1.1067 | 1.0821 |
| deep_shadow | chroma5 | 0.1059 | 0.2168 | 0.6071 | 0.8960 | 0.0389 / 0.0345 | 1.1065 | 1.0815 |
| center_midtone | SP-3000 | 0.5970 | 0.7870 | 0.9554 | 0.9602 | 0.1001 / 0.0846 | 1.0986 | 1.0903 |
| center_midtone | chroma4 | 0.6129 | 0.8213 | 0.9518 | 0.9540 | 0.1030 / 0.0681 | 1.0992 | 1.0766 |
| center_midtone | chroma5 | 0.6129 | 0.8219 | 0.9518 | 0.9540 | 0.0958 / 0.0606 | 1.0947 | 1.0675 |

해석:

- `chroma5`가 이번 루프 기준 최선이다.
- 하늘 p50은 `0.9137 -> 0.9078`로 더 내려갔고, p20도 `0.8843 -> 0.8754`로 SP-3000 방향에 가까워졌다.
- 하늘 p95/p99는 거의 그대로라, 더 강하게 누르면 실제 DR 확보가 아니라 하늘 전체를 회색으로 압축하는 쪽이 된다.
- 우하단 chroma mean/std는 `0.1387 / 0.0484 -> 0.1312 / 0.0444`로 SP-3000 `0.1239 / 0.0445`에 가까워졌다. 특히 chroma std는 거의 맞았다.
- 우하단 G/B는 `1.1753`으로 SP-3000 `1.1777`에 근접했다. R/G는 아직 높아 붉은/자주 축이 조금 남아 있다.
- deep shadow는 chroma noise가 SP-3000보다 낮지만 R/G가 높고 G/B가 낮다. 후단 chroma 감쇠를 더 강하게 밀면 암부 색비가 더 멀어질 수 있다.

검증:

- `swift run negaflow develop /tmp/negaflow_hwexp_600dpi_hdr_baseline_merge_20260622_1815.tiff /tmp/negaflow_hwexp_600dpi_hdr_outputgrade_chroma5_20260622_1922.jpg --raw` 성공.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'ChromabaseTests/testScannerOutputGrade'` 통과.

남은 리스크:

1. 하늘 p50/p95는 아직 SP-3000보다 높다. 후처리로 더 누르면 하늘 계조를 얻는 게 아니라 이미 있는 값을 종이 shoulder처럼 압축하는 것이라, 진짜 해결은 exposure set 또는 merge 가중치 재검증이다.
2. 우하단 chroma std는 맞았지만 chroma mean/RG가 아직 높다. 더 줄이면 center midtone chroma와 색 분리가 같이 죽는 리스크가 있다.
3. deep shadow 색비는 아직 다르다. 현재는 노이즈 억제를 우선해 색차가 낮아져 있고, SP-3000 같은 암부 컬러 깊이를 만들려면 raw 단계 SNR이 더 필요하다.
4. upstream SANE HEAD 의존성은 여전히 배포 리스크다.

## 2026-06-22 6-pass hardware exposure + repeated sampling 검증

웹/방법론 정리:

- `scan-exposure-time`은 SANE upstream 옵션 이름으로 존재하며, 현재 실제 장치 `genesys:libusb:000:010`에서도 `--scan-exposure-time 11000..65535 [14000]`로 노출된다.
- 스캐너 품질 개선 방법은 두 축이다.
  - 서로 다른 노출을 합치는 multi-exposure는 highlight/shadow DR 보강용이다.
  - 같은 조건을 여러 번 찍어 평균하는 multi-sampling은 random/color noise 감소용이다.
- 따라서 “명부/중간/암부 3단계”만으로는 노이즈 리스크가 완전히 줄지 않는다. 같은 노출 반복 샘플을 평균해야 한다.

구현/실험:

- `NEGAFLOW_HWEXP_SAMPLES=2`일 때 hardware exposure plan을 `[11000, 11000, 14000, 14000, 30000, 30000]`로 확장했다.
- 같은 exposure 값이 여러 장이면 merge 단계에서 해당 exposure끼리 먼저 평균되도록 했다.
- long exposure가 암부를 전부 지배하면 long pass의 컬러 바이어스를 따라가므로, low-signal long-pass 보강량을 `0.72 -> 0.48`로 낮췄다.
- 기본값은 다시 1 sample per exposure, 즉 기존 3패스로 유지했다. 6패스는 실제 검증 결과 기본으로 쓰기에는 색비 리스크가 남았다.

실제 스캔:

- 명령:
  - `NEGAFLOW_SCANIMAGE_PATH=/tmp/sane-head-install/bin/scanimage NEGAFLOW_KEEP_MULTIPASS=1 NEGAFLOW_HWEXP_SAMPLES=2 swift run negaflow scan --dpi 600 --hdr`
  - `NEGAFLOW_SCANIMAGE_PATH=/tmp/sane-head-install/bin/scanimage NEGAFLOW_HWEXP_SAMPLES=2 swift run negaflow scan --dpi 600 --hdr`
- 두 번 모두 실제 6패스 진행 확인:
  - `Exposure bracket 1/6 @ 11000`
  - `Exposure bracket 2/6 @ 11000`
  - `Exposure bracket 3/6 @ 14000`
  - `Exposure bracket 4/6 @ 14000`
  - `Exposure bracket 5/6 @ 30000`
  - `Exposure bracket 6/6 @ 30000`
- 스캔 시간은 약 `140s`로 기존 3패스 대비 거의 2배다.

후보:

- 첫 6패스 후보:
  - `/tmp/negaflow_hwexp_600dpi_6pass_1939_developed.jpg`
  - `/tmp/negaflow_hwexp_600dpi_6pass_1939_aligned_metrics.json`
- long-pass 보강 제한 후 6패스 후보:
  - `/tmp/negaflow_hwexp_600dpi_6pass_limitedlong_1945_developed.jpg`
  - `/tmp/negaflow_hwexp_600dpi_6pass_limitedlong_1945_metrics.json`
- 새 실제 스캔은 기존 고정 crop보다 `x` 시작이 더 왼쪽이라 정렬 crop을 `(0.0675, 0.0625, 0.9475, 0.9650)`로 다시 잡았다.

ROI 비교:

| 영역 | 이미지 | p20 | p50 | p95 | p99 | chroma mean/std | R/G | G/B |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| sky_highlight | SP-3000 | 0.8532 | 0.8776 | 0.9327 | 0.9437 | 0.0250 / 0.0079 | 1.0173 | 0.9835 |
| sky_highlight | old chroma5 | 0.8754 | 0.9078 | 0.9501 | 0.9518 | 0.0189 / 0.0113 | 1.0113 | 0.9871 |
| sky_highlight | 6pass limited | 0.8765 | 0.9154 | 0.9518 | 0.9540 | 0.0188 / 0.0116 | 1.0146 | 0.9893 |
| right_bottom_magenta_mid | SP-3000 | 0.5049 | 0.6269 | 0.7697 | 0.9041 | 0.1239 / 0.0445 | 1.1474 | 1.1777 |
| right_bottom_magenta_mid | old chroma5 | 0.5009 | 0.6485 | 0.8336 | 0.9214 | 0.1312 / 0.0444 | 1.1603 | 1.1753 |
| right_bottom_magenta_mid | 6pass limited | 0.4852 | 0.6549 | 0.8415 | 0.9198 | 0.1356 / 0.0422 | 1.1653 | 1.1816 |
| deep_shadow | SP-3000 | 0.0936 | 0.2378 | 0.6255 | 0.8772 | 0.0551 / 0.0447 | 1.0578 | 1.1300 |
| deep_shadow | old chroma5 | 0.1059 | 0.2168 | 0.6071 | 0.8960 | 0.0389 / 0.0345 | 1.1065 | 1.0815 |
| deep_shadow | 6pass limited | 0.1073 | 0.2154 | 0.5868 | 0.8809 | 0.0457 / 0.0376 | 1.1670 | 1.0693 |
| center_midtone | SP-3000 | 0.5970 | 0.7870 | 0.9554 | 0.9602 | 0.1001 / 0.0846 | 1.0986 | 1.0903 |
| center_midtone | old chroma5 | 0.6129 | 0.8219 | 0.9518 | 0.9540 | 0.0958 / 0.0606 | 1.0947 | 1.0675 |
| center_midtone | 6pass limited | 0.6107 | 0.8216 | 0.9526 | 0.9540 | 0.0996 / 0.0614 | 1.0977 | 1.0733 |

결론:

- 6패스는 실제로 동작했고, 같은 노출 반복 평균까지 구현됐다.
- 하지만 이 필름/장치/현재 exposure set에서는 6패스 결과가 SP-3000 색비에 더 가까워지지 않았다.
- 특히 deep shadow R/G가 `1.1065 -> 1.1670`으로 나빠졌다. long-pass 보강을 줄여도 암부 색비 리스크가 남는다.
- 따라서 6패스는 현실적인 실험 옵션으로 남기되 기본값으로 고정하지 않는다.
- 현재 기본 후보는 여전히 `/tmp/negaflow_hwexp_600dpi_hdr_outputgrade_chroma5_20260622_1922.jpg`가 더 낫다.

남은 현실 리스크:

1. 같은 노출 반복 평균은 랜덤 노이즈에는 맞는 방법이지만, 이 장치에서는 long exposure 컬러 바이어스가 암부 색비를 망칠 수 있다.
2. 6패스는 스캔 시간이 약 140초라 사용성 비용이 크다.
3. 하늘 p95/p99는 6패스로도 개선되지 않았다. 이건 exposure set 자체나 scanner raw clipping/headroom 문제로 봐야 한다.

## 2026-06-22 exposure-time grid 실측

목표:

- analog gain/register reverse engineering 전에, 공개 `scan-exposure-time`만으로 실제 최적 노출 조합을 찾는다.
- 같은 필름, 같은 600dpi, 같은 16bit TIFF 조건에서 exposure-time 단일 패스를 직접 찍고, `/Users/songhabin/Negaflow/samples/000036.JPG`와 ROI 비교한다.

실제 스캔:

- 장치: `genesys:libusb:000:007` / `genesys:libusb:000:010`로 재열거됨. 각 패스 직전 `scanimage -L`로 현재 주소를 다시 잡았다.
- 옵션: `--mode Color --source "Transparency Adapter" --resolution 600 --depth 16 -x 36.33 -y 24.94 --format=tiff`
- exposure grid:
  - `/tmp/negaflow_exposure_grid/exposure_11000.tiff`
  - `/tmp/negaflow_exposure_grid/exposure_14000.tiff`
  - `/tmp/negaflow_exposure_grid/exposure_18000.tiff`
  - `/tmp/negaflow_exposure_grid/exposure_22000.tiff`
  - `/tmp/negaflow_exposure_grid/exposure_30000.tiff`
  - `/tmp/negaflow_exposure_grid/exposure_45000.tiff`
- 각 TIFF를 `swift run negaflow develop ... --raw`로 현상했다.
- 지표:
  - `/tmp/negaflow_exposure_grid/grid_metrics.json`

단일 exposure score:

| exposure | score | 해석 |
| ---: | ---: | --- |
| 14000 | 0.3632 | 종합 최선. 하늘 p50이 가장 낮은 편이고 deep shadow 색비도 상대적으로 덜 망가짐. |
| 45000 | 0.3903 | 점수 2위지만 하늘 p50이 더 뜨고 long exposure 색비 리스크가 남음. |
| 30000 | 0.4101 | 45000보다 크게 낫지 않음. |
| 22000 | 0.4217 | 중간값이지만 종합 이득 없음. |
| 18000 | 0.4476 | 14000보다 모든 핵심 리스크에서 애매함. |
| 11000 | 0.4555 | short pass 단독으로는 노이즈/중간톤 손실 리스크가 큼. |

단일 exposure 핵심 ROI:

| exposure | sky p50/p95 | 우하단 chroma/std | 우하단 R/G / G/B | deep p50/p95 | deep R/G / G/B |
| ---: | ---: | ---: | ---: | ---: | ---: |
| SP-3000 | 0.8776 / 0.9327 | 0.1239 / 0.0445 | 1.1474 / 1.1777 | 0.2378 / 0.6255 | 1.0578 / 1.1300 |
| 11000 | 0.9112 / 0.9512 | 0.1351 / 0.0429 | 1.1654 / 1.1794 | 0.2355 / 0.5882 | 1.1458 / 1.0838 |
| 14000 | 0.8997 / 0.9501 | 0.1344 / 0.0435 | 1.1523 / 1.1934 | 0.2406 / 0.5954 | 1.1132 / 1.0949 |
| 18000 | 0.9137 / 0.9501 | 0.1370 / 0.0425 | 1.1572 / 1.1932 | 0.2426 / 0.5892 | 1.1595 / 1.0855 |
| 22000 | 0.9104 / 0.9501 | 0.1346 / 0.0424 | 1.1550 / 1.1892 | 0.2406 / 0.5877 | 1.1491 / 1.0877 |
| 30000 | 0.9104 / 0.9501 | 0.1351 / 0.0412 | 1.1615 / 1.1843 | 0.2456 / 0.6006 | 1.1504 / 1.0907 |
| 45000 | 0.9146 / 0.9501 | 0.1348 / 0.0417 | 1.1619 / 1.1832 | 0.2448 / 0.5990 | 1.1399 / 1.0931 |

3-exposure 조합 시뮬레이션:

- 조합 현상 후보:
  - `/tmp/negaflow_exposure_grid/combo_11000_14000_18000_developed.jpg`
  - `/tmp/negaflow_exposure_grid/combo_11000_14000_22000_developed.jpg`
  - `/tmp/negaflow_exposure_grid/combo_11000_14000_30000_developed.jpg`
  - `/tmp/negaflow_exposure_grid/combo_11000_14000_45000_developed.jpg`
  - `/tmp/negaflow_exposure_grid/combo_11000_18000_30000_developed.jpg`
  - `/tmp/negaflow_exposure_grid/combo_14000_22000_45000_developed.jpg`
- 지표:
  - `/tmp/negaflow_exposure_grid/combo_metrics.json`

조합 score:

| 조합 | score | 해석 |
| --- | ---: | --- |
| 14000/22000/45000 | 0.4789 | 조합 중 최선이지만 단일 14000보다 나쁨. |
| 11000/14000/45000 | 0.4934 | 하늘 색비는 일부 좋지만 우하단/암부가 나빠짐. |
| 11000/18000/30000 | 0.5029 | 전체적으로 애매함. |
| 11000/14000/30000 | 0.5178 | 기존 조합 계열. 단일 14000보다 나쁨. |
| 11000/14000/18000 | 0.5391 | long이 약해도 별 이득 없음. |
| 11000/14000/22000 | 0.5598 | 최악. 우하단 chroma/G/B가 망가짐. |

결론:

- 현재 공개 `scan-exposure-time` 범위에서 단일 14000이 가장 균형이 좋다.
- 18000/22000/30000/45000 long 계열은 하늘 p95를 낮추지 못하고, 암부/우하단 색비를 더 틀어지게 만들 수 있다.
- 11000 short 계열은 clipping 보호용으로만 의미가 있다. 단독 품질은 좋지 않다.
- 따라서 exposure-time grid 최적화의 현실적 결론은:
  - 기본 raw 기준 exposure는 `14000`.
  - multi-exposure merge는 `[11000, 14000, 30000]` 같은 넓은 브라케팅보다, `14000` baseline을 거의 그대로 유지하고 극단 clipping/저신호에만 alternate pass를 제한적으로 쓰는 방향이 맞다.
  - 후보 조합을 바꾼다고 SP-3000 하늘 p95/p99가 살아나지는 않는다.
- 현재까지 수치상 최종 후보는 여전히 `/tmp/negaflow_hwexp_600dpi_hdr_outputgrade_chroma5_20260622_1922.jpg`가 낫다.

## 2026-06-22 실제 3600dpi 스캔 ROI 기반 Basic Tone/Look 검증

입력 고정:

- 기준 SP-3000: `/Users/songhabin/negaflow/samples/000036.JPG`
- 실제 스캐너 raw: `/Users/songhabin/negaflow/scan_3600dpi.tiff`
- stale/cache 방지용 복사본: `/tmp/negaflow_real_roi_20260622_205029/scan_3600dpi_real_raw.tiff`
- 기준 overlay: `/tmp/negaflow_real_roi_20260622_205029/sp3000_000036_ref_roi_overlay_oriented.jpg`
- 실제 scan overlay: `/tmp/negaflow_real_roi_20260622_205029/baseline_neutral_final_roi_overlay.jpg`

중요 정정:

- `000036.JPG`에는 EXIF Orientation 3이 있다. ROI 분석 시 `ImageOps.exif_transpose` 또는 동등한 방향 보정을 적용해야 한다.
- 방향 보정 없이 PIL/raw pixel 좌표로 읽으면 deep_shadow ROI가 엉뚱한 하늘/명부를 잡는다.

ROI 화면 기준:

| ROI | normalized rect | 목적 |
| --- | --- | --- |
| sky | `(0.70, 0.10, 0.95, 0.72)` | 하늘 명부/shoulder/컬러 노이즈 |
| right_bottom | `(0.48, 0.62, 0.78, 0.93)` | 우하단 중간톤 보라끼/컬러 노이즈 |
| shadow | `(0.05, 0.58, 0.34, 0.92)` | 암부 toe/노이즈/계조 |
| fuselage | `(0.36, 0.43, 0.57, 0.58)` | 기체 명부 디테일 |
| runway | `(0.35, 0.15, 0.58, 0.40)` | 중간톤 대비/색감 |

최종 조치:

- `ScannerOutputGrade`를 사용자 Basic Tone 이전으로 이동했다. 이유: 최종 output grade가 Exposure/Contrast/Highlights/Shadows/Whites/Blacks/Density 결과를 뒤에서 다시 압축해 슬라이더가 안 먹는 것처럼 보였다.
- `ToneMapper.applyToneCurves`의 Basic Tone을 전역 `CIColorControls`/전역 gamma 대신 luma 마스크 기반 `CIColorKernel`로 변경했다.
- 실제 스캔 선형 working 값에서 하늘/명부가 화면상 밝아도 내부 luma는 대략 0.3~0.5 범위에 있으므로 `Highlights/Whites` 마스크를 이 범위로 내렸다.
- `Shadows/Blacks/Contrast`는 1차 수정에서 암부 p05를 과도하게 올려 최종 강도를 낮췄다.
- `Whites`는 최종적으로 실제 스캔 픽셀의 약 51%에 영향을 주며, `Highlights`는 약 49%에 영향을 준다.

실제 스캔 최종 ROI 변화량 (`baseline_neutral_final2.jpg` 대비):

| control | value | sky l50 | sky lstd | right-bottom l50 | right-bottom chroma | shadow p05 | shadow l50 | fuselage p95 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| exposure | -1 | -0.2627 | -0.0037 | -0.2571 | -0.0134 | -0.0445 | -0.1154 | -0.2622 |
| exposure | +1 | +0.0538 | -0.0164 | +0.0827 | -0.0181 | +0.0871 | +0.1545 | +0.0611 |
| contrast | -1 | +0.0078 | -0.0031 | +0.0137 | -0.0080 | +0.5202 | +0.3782 | +0.0106 |
| contrast | +1 | -0.0092 | +0.0032 | -0.0140 | +0.0126 | -0.0916 | -0.2449 | -0.0090 |
| highlights | -1 | +0.0252 | +0.0052 | +0.0143 | -0.0013 | +0.0000 | +0.0000 | +0.0235 |
| highlights | +1 | -0.0289 | -0.0065 | -0.0143 | +0.0006 | +0.0000 | +0.0000 | -0.0241 |
| shadows | -1 | +0.0000 | +0.0000 | +0.0000 | +0.0078 | -0.0916 | -0.2429 | +0.0000 |
| shadows | +1 | +0.0000 | -0.0000 | +0.0000 | -0.0040 | +0.2888 | +0.1966 | +0.0000 |
| whites | -1 | -0.0367 | -0.0074 | -0.0232 | +0.0010 | +0.0000 | +0.0000 | -0.0339 |
| whites | +1 | +0.0314 | +0.0049 | +0.0221 | -0.0016 | +0.0000 | +0.0000 | +0.0316 |
| blacks | -1 | +0.0000 | +0.0000 | +0.0000 | +0.0073 | -0.0916 | -0.2432 | +0.0000 |
| blacks | +1 | +0.0000 | +0.0000 | +0.0000 | -0.0038 | +0.3162 | +0.2137 | +0.0000 |
| density | -1 | +0.0538 | -0.0163 | +0.0827 | -0.0211 | +0.0000 | +0.0000 | +0.0611 |
| density | +1 | -0.1465 | +0.0042 | -0.1549 | +0.0092 | +0.0000 | -0.0000 | -0.1482 |

Look 검증:

- 실제 scan 원본에서 `none`, `neutral`, `rich-neutral`, `soft-print`, `warm-lab`, `clear-chrome`을 각각 현상했다.
- `none`과 `neutral`은 의도상 동일하다.
- `rich-neutral`, `soft-print`, `warm-lab`, `clear-chrome`은 neutral 대비 mean absolute pixel difference가 약 28.6~38.8로 충분히 보인다.
- 산출물/지표: `/tmp/negaflow_real_roi_20260622_205029/look_final_roi_metrics.json`

남은 판단:

- Basic Tone/Look은 이제 실제 스캔 기준으로 동작한다.
- 다만 `Contrast -1`, `Shadows +1`, `Blacks +1`은 암부 ROI에서 큰 변화가 나므로 UI상 최대값 사용 시 암부가 뜰 수 있다. 이건 작동 불량이 아니라 강도 설계 문제이며, 필요하면 UI range를 더 좁히거나 내부 강도를 더 낮추는 후속 튜닝 대상이다.

## 2026-06-23 실제 앱 스캔 ROI 기반 Color 탭 검증

입력 고정:

- 실제 앱 스캔 raw: `/tmp/negaflow_app_direct_scan_color_20260623_001055.tiff`
  - 앱 UI에서 `Scan Next`로 직접 획득한 Plustek OpticFilm 8100 스캔이다.
  - 원 scanimage 옵션은 `--mode Color --source "Transparency Adapter" --resolution 3600 --depth 16 -x 36.00 -y 24.00 --format=tiff`였다.
  - 파일 크기: `103825968 bytes`
  - 수정시각: `2026-06-23 00:11:49 +0900`
- ROI 측정 출력: `/tmp/negaflow_color_outputs_20260623_001055`
- Film base 추정값: `0.1979 / 0.0837 / 0.0613`

ROI:

| ROI | normalized rect | 목적 |
| --- | --- | --- |
| sky | `(0.70, 0.10, 0.25, 0.62)` | 하늘 명부/채도/색축 |
| right_bottom | `(0.48, 0.62, 0.30, 0.31)` | 우하단 중간톤 보라끼/컬러 노이즈 |
| shadow | `(0.05, 0.58, 0.29, 0.34)` | 암부 색축/채도 변화 |
| fuselage | `(0.36, 0.43, 0.21, 0.15)` | 기체 명부/중간톤 |
| runway | `(0.35, 0.15, 0.23, 0.25)` | 중간톤 색감/채도 |

문제 확인:

- `Warmth`/`Tint`는 기존 코드에서도 방향은 맞았지만, `-1...+1` 전체 범위 대비 변화량이 약해 실제 UI에서 조절이 약하게 보였다.
- 새 단위 테스트의 red phase에서 `Warmth`와 `Tint` 변화량 기준이 실패했다.
  - `Warmth -1`: red/blue ratio `1.0778`, 기준 하한 `1.0232`보다 낮아지지 못함.
  - `Warmth +1`: red/blue ratio `1.3432`, 기준 상한 `1.3832`보다 높아지지 못함.
  - `Tint -1`: green/magenta ratio `0.9490`, 기준 하한 `0.8576`보다 낮아지지 못함.
  - `Tint +1`: green/magenta ratio `1.0880`, 기준 상한 `1.1776`보다 높아지지 못함.

채택한 변경:

- `ColorModel.apply`에서 `Warmth` 계수를 키웠다.
  - R/B 축: `0.12 -> 0.18`
  - G 보조축: `0.02 -> 0.03`
- `Tint` 계수를 키웠다.
  - G 축: `0.10 -> 0.24`
  - R/B 반대축: `0.05 -> 0.12`
- `Vibrance`, `Saturation`, `Color Depth`는 실제 스캔 ROI와 단위 테스트에서 이미 동작 확인되어 이번 루프에서는 계수를 바꾸지 않았다.

실제 스캔 ROI 변화량 (`baseline` 대비):

| control | value | 대표 ROI | 핵심 변화 |
| --- | ---: | --- | --- |
| Warmth | -1 | sky | `delta_rb -0.3142`, R `-0.0710`, B `+0.0691` |
| Warmth | +1 | sky | `delta_rb +0.4523`, R `+0.0710`, B `-0.0691` |
| Warmth | -1/+1 | right_bottom | `delta_rb -0.3326 / +0.4789` |
| Tint | -1 | sky | `delta_rg +0.5095`, `delta_gb -0.3083`, G `-0.0882` |
| Tint | +1 | sky | `delta_rg -0.3121`, `delta_gb +0.3925`, G `+0.0882` |
| Tint | -1/+1 | right_bottom | `delta_rg +0.5113 / -0.3133`, `delta_gb -0.3251 / +0.4139` |
| Vibrance | -1/+1 | right_bottom | `delta_chroma -0.0094 / +0.0261` |
| Vibrance | -1/+1 | runway | `delta_chroma -0.0100 / +0.0235` |
| Saturation | -1/+1 | runway | `delta_chroma -0.0367 / +0.0367` |
| Saturation | -1/+1 | fuselage | `delta_chroma -0.0311 / +0.0311` |
| Color Depth | -1/+1 | runway | `delta_chroma -0.0214 / +0.0214` |
| Color Depth | -1/+1 | fuselage | `delta_chroma -0.0181 / +0.0181` |

검증:

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ColorModelControlsTests`
  - red phase: 변경 전 `Warmth`/`Tint` 테스트 실패.
  - green phase: 변경 후 3개 테스트 모두 통과.
- `/tmp/negaflow-color-qa` 측정 스크립트로 실제 앱 스캔 TIFF를 다시 현상하고 ROI를 측정했다.
- 산출 JPG는 `/tmp/negaflow_color_outputs_20260623_001055`에 저장했다.

남은 리스크:

- `Vibrance`와 `Color Depth`는 `Saturation`보다 의도적으로 약하다. 수치상 동작은 확인됐지만, UI에서 더 강한 체감을 원하면 별도 강도 설계가 필요하다.
- Color 컨트롤은 색축/채도 조절이다. 하늘 명부 shoulder, 암부 계조, raw SNR 문제는 Color 탭 조절로 해결할 수 없고 Tone/ScannerPrintGrade/raw multi-pass 쪽 문제로 계속 분리해야 한다.
