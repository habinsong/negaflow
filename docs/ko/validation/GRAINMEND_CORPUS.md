# GrainMend 실제 스캔 비교

[문서 홈](../README.md)

GrainMend RGB의 회귀 검사에는 FILM-R v2를 씁니다.

| 항목 | 값 |
|---|---|
| 손상본·수동 복원본 | 각 44장 |
| 라이선스 | CC BY 4.0 |
| 전체 크기 | 437,570,872바이트 |
| 저장 위치 | `build/defect-corpus/` |
| 용도 | GrainMend RGB 회귀 비교 |

## 자료

- 이름: *Authentically damaged & manually restored film scans*
- 저자: Daniela Ivanova
- DOI: <https://doi.org/10.6084/m9.figshare.21803304.v2>
- 논문: <https://doi.org/10.1111/cgf.14749>
- 설명: <https://daniela997.github.io/FilmDamageSimulator/>
- 라이선스: CC BY 4.0
- 구성: 손상된 35mm 필름 스캔 44장과 전문가 수동 복원본 44장
- 전체 크기: 437,570,872바이트

이미지는 저장소에 넣지 않습니다.
`Config/defect-corpus-film-r-v2.json`에 DOI 버전, 라이선스, 쌍 수, 전체 크기를 고정했습니다.
가져오기 스크립트는 Figshare가 제공한 파일별 MD5와 크기를 검사합니다.
받은 파일과 결과는 `build/defect-corpus/`에 두며 Git에서 제외합니다.

## 받기

기본 명령은 빠른 확인용 한 쌍만 받습니다.

<details>
<summary>자료 받기 명령</summary>

```bash
python3 scripts/defect-corpus/fetch-film-r.py
```

44쌍 전체:

```bash
python3 scripts/defect-corpus/fetch-film-r.py --all
```

Figshare 파일 CDN이 자동 요청을 차단하면 데이터셋 페이지에서 `Download all`로 받은 ZIP을 그대로
검증해 풀 수 있습니다.
ZIP의 파일명, 크기와 Figshare MD5가 고정 계약과 모두 맞아야 추출이 완료됩니다.

```bash
python3 scripts/defect-corpus/fetch-film-r.py \
  --archive ~/Downloads/21803304.zip \
  --all
```

한 사례만 받기:

```bash
python3 scripts/defect-corpus/fetch-film-r.py --case portra400_135_1
```

</details>

## 비교 실행

손상본과 이름 끝에 `_restored`가 붙은 복원본을 같은 폴더에 둡니다.

<details open>
<summary>44쌍 비교 명령</summary>

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift run -c release negaflow defect-bench build/defect-corpus/film-r-v2 \
  --reference-dir build/defect-corpus/film-r-v2 \
  --out build/defect-corpus/film-r-v2-report \
  --metrics-only
```

</details>

`--metrics-only`는 큰 PNG를 만들지 않습니다.
옵션을 빼면 수동 확인용 `before`, `after`, `diff`, `mask`, 100% 크롭도 만듭니다.

보고서에 들어가는 값:

- 기존 검출 수, 신뢰도, 바뀐 픽셀 수, 처리 시간
- 손상본과 전문가 복원본 사이의 PSNR과 평균 절대 오차
- GrainMend 결과와 전문가 복원본 사이의 PSNR과 평균 절대 오차
- PSNR 변화
- 정답 오차가 줄거나 늘어난 픽셀 비율

FILM-R 논문은 PSNR, SSIM, LPIPS를 함께 씁니다.
이 저장소는 ML 의존성을 새로 넣지 않기 때문에 표준 라이브러리로 계산할 수 있는 PSNR과 절대
오차만 자동으로 냅니다.

이 숫자만으로 출시를 승인하지는 않습니다. 수동 복원본에도 편집 판단과 JPEG 차이가 들어갑니다.
다만 같은 자료와 설정으로 다시 실행하는 자동 품질 하한은
`Config/defect-removal-film-r-v2-baseline.json`에 고정합니다.
최종 판정에는 `before`, `after`, `diff`, `mask`와 100% 크롭을 함께 봐야 합니다.

> [!CAUTION]
> PSNR이나 평균 오차 하나로 GrainMend의 화질을 승인하지 않습니다. 원본 질감 손상과 오검출은
> 전후 이미지, 차이 이미지, 마스크, 100% 크롭을 함께 보고 판단합니다.

이 자료로 확인할 수 있는 것은 렌더된 이미지의 GrainMend RGB 경로뿐입니다.
RAW 디코딩, 필름 반전 정확도, IR 정렬, 실제 스캐너 동작을 증명하는 데 쓰면 안 됩니다.

## 2026-07-25 결과

44쌍 전체를 Release 빌드에서 `--metrics-only --crops 0`으로 실행했습니다.
직전 회귀 기준인 민감도 3.0과 출시 자동 경로인 0.7을 비교했습니다.

| 지표 | 직전 기준 3.0 | 안전 자동 0.7 |
|---|---:|---:|
| 평가 이미지 | 44 | 44 |
| PSNR 개선 / 악화 / 동일 | 11 / 33 / 0 | 34 / 6 / 4 |
| 평균 PSNR 변화 | -1.688 dB | +0.466 dB |
| 중앙 PSNR 변화 | -0.237 dB | +0.118 dB |
| 최저 PSNR 변화 | -18.952 dB | -1.338 dB |
| 가중 개선 픽셀 | 0.128% | 0.029% |
| 가중 악화 픽셀 | 0.792% | 0.017% |
| 가중 변경 픽셀 | 0.794% | 0.043% |
| 자동 안전 중지 | 없음 | 3장 |

기존 앱 기본값은 6.0이었고, 직전 3.0 기준보다도 공격적이었습니다.
출시 자동 경로는 0.7로 낮추고 미세 이물 검출은 기본에서 껐습니다.
후보가 한 타일의 2%를 넘으면 그 타일에 닿은 성분을 제외하고, 5%를 넘는 타일이 있거나 필터 후
전체 후보가 0.06%를 넘으면 그 사진의 자동 복원을 적용하지 않습니다.
이때 사용자는 가이드로 영역을 좁혀 처리할 수 있습니다.

이 안전선은 자동에만 적용됩니다.
가이드, 브러시, 복제 도장, IR의 검출 범위와 복원 동작을 자동 기준으로 제한하지 않습니다.

`Config/defect-removal-film-r-v2-baseline.json`은 관측값 회귀 기준과 함께 다음 절대 하한도
검사합니다.

- 개선 30장 이상, 악화 10장 이하
- 평균·중앙 PSNR 변화 0 dB 이상
- 최저 PSNR 변화 -1.5 dB 이상
- 가중 악화 픽셀 0.03% 이하
- 전체 변경 픽셀 0.06% 이하

이번 결과는 직전 기준보다 개선 이미지가 23장 늘고, 악화 이미지가 27장 줄었으며, 최악 사례는
17.614 dB 나아졌습니다.
그래도 6장은 전문가 복원본보다 PSNR이 낮습니다.
FILM-R은 실제 손상본과 수동 복원본을 제공하지만 복원 판단의 모호함도 포함합니다.
자료와 논문은 [FILM-R 프로젝트](https://daniela997.github.io/FilmDamageSimulator/)와
[FILM-R 논문](https://arxiv.org/abs/2302.10004)에서 확인할 수 있습니다.

고밀도 후보를 자동에서 제외한 이유는 질감이 많은 영역의 오검출을 줄이는 기존 영상 복원 연구와도
맞습니다.
다만 이 결과로 다음을 주장할 수는 없습니다.

- 모든 사진에서 자동 결과가 수동 복원보다 낫다.
- GrainMend RGB가 하드웨어 IR 청소와 같다.
- 실제 스캐너의 RGB·IR 정렬과 광학 품질이 검증됐다.

전체 재현은 수동 `GrainMend corpus` workflow에서 실행합니다.
자동 품질 게이트와 별도로 100% 크롭 수동 확인을 거쳐야 합니다.
