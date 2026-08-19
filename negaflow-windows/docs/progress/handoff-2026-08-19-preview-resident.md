# 핸드오프 — 2026-08-19 프리뷰 GPU 상주

## 한 일

`07` H.12 의 invert→tone 호스트 왕복을 줄였습니다. macOS `CIImage` 지연 평가에 맞춰
`GpuResidentScope` 가 프리뷰 반전·톤을 GPU 텍스처에 묶습니다. 새 커널 없음.
해상도 접기 없음.

Release `negaflow-cli --develop-timing OpticFilm8100_frame_1.tiff x2 nocurve`
`NEGA_TIMING=1`, RTX 4060 Ti, 상자 3600:

| 단계 | H.12 | 지금 두 번째 |
|---|---:|---:|
| develop | 113 | 55.5 |
| tone_adjust | 75 | 19.3 |
| output | 81 | 64.2 |
| 합 | 298 | 153.7 |
| 벽시계 | 298 | 182 |

지문 `f6f4ab3dbcd1f25` Debug/Release 네 번 같음.

시험 `invert_then_tone_is_one_host_round_trip` 두 번: 올리기 1 · 내리기 1 ·
오차 1.43e-06. `native.gpu_working_image` 하드웨어 실패(COM 주소 재사용)도
create 순서를 바꿔 통과.

## 확인 못 한 것

- 앱 슬라이더 벽시계
- 렌더당 ~1GB 작업 집합 누수
- A4 `run-app` x64 Release abort 재현

## 다음 한 걸음

**② 는 닫힘.** [`handoff-2026-08-19-preview-bgra8.md`](handoff-2026-08-19-preview-bgra8.md).
다음은 커브 중간 왕복 (H.12 ③).
