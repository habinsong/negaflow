# 실제 촬영 컬러 네거티브 체크포인트

기준일: 2026-08-10

사용자가 제공한 Plustek OpticFilm 8100 스캔본(`negaflow_test/`, 15장)으로 수행한 체크포인트
검증입니다. 이번에 든 두 변경 — 행 블록 병렬 실행과 ABI v22 취소·진행률 — 을 실제 스캔
해상도에서 확인했습니다.

## 코퍼스가 실제로 덮은 것

| 프레임 | 배열 | 압축 | 채널 | ICC | 크기 |
|---|---|---|---|---|---|
| frame_1 | little-endian | none | RGB16 | 없음 | 5088×3401, 103,825,968 B |
| frame_12 | **big-endian** | **LZW** | **RGBA16** | **572 B** | 5088×3401, 128,452,302 B |

두 프레임이 디코더의 서로 다른 경로(엔디언, LZW 의미 검사, alpha, embedded ICC → ICM)를 밟습니다.

## 결과

두 프레임 모두 디코드 → 수동 Dmin 반전 → 톤(노출·대비·4밴드 커브) → Film Look → 검증된
PNG16 게시까지 통과했습니다.

| 프레임 | decode | develop | tone | film look | output | 전체 |
|---|---|---|---|---|---|---|
| frame_1 | 123 ms | 261 ms | 333 ms | 5 ms | 2,576 ms | **3,323 ms** |
| frame_12 | 2,254 ms | 257 ms | 321 ms | 6 ms | 2,652 ms | **5,512 ms** |

frame_12 의 디코드가 18배 비싼 것은 LZW inflate 와 ICM 변환 때문이며 예상된 비용입니다.

**원본 불변 확인.** 두 소스의 SHA-256 이 실행 전후로 같습니다.

- `frame_1`: `F281DEECF07FE8E6B4019EB2BE0D87985F2F1D7A861119388279796DDB5A872B`
- `frame_12`: `FBB71DD67E168FC315469CE958D7DB891E0172CABD502F70F6723E0BE60CFEC6`

## 전체 ABI 스위트를 실제 네거티브로

`negaflow_develop_export_abi_tests` 를 frame_1 을 fixture 로 전부 실행했습니다. 합성 fixture
경로뿐 아니라 v1~v17 의 실촬영 preview/export 검사와 Auto base 경로가 모두 통과했고, 총
227 초 동안 약 20회의 전체 해상도 현상이 돌았습니다. 실패 0.

## 취소가 실제로 걸리는지

가장 중요한 확인입니다. 다른 스레드가 엔진의 첫 단계 보고를 관측한 직후 래치를 세웠습니다.

```
{"note":"v22_cancelled_mid_run","stage":3,"wall_microseconds":60289}
```

`stage 3` 은 `decode` 입니다. **60.3 ms 만에 반환**했고, 같은 입력의 취소하지 않은 export 는
**3,323 ms** 입니다. 목적지 파일은 만들어지지 않았습니다. 사전 래치만으로는 경계 검사밖에
증명하지 못하므로 이 실행 중 취소가 v22 의 실질적 근거입니다.

## 이번에 드러난 기존 결함 두 가지

**1. 실제 TIFF fixture 경로가 한 세그먼트 짧았습니다.**
`CMakeLists.txt` 의 `NEGAFLOW_SOURCE_TIFF_FIXTURE` 가
`${CMAKE_CURRENT_SOURCE_DIR}/../Sources/...` 를 가리켰고, 실제 파일은
`../negaflow-mac/Sources/...` 에 있습니다. `if(EXISTS)` 가 항상 거짓이어서 실촬영 fixture 를
쓰는 테스트가 **전부 조용히 합성 전용 분기로 떨어져 있었습니다.** 통과하는 것처럼 보였을 뿐
돌지 않았습니다. 경로를 고치자 등록되는 테스트가 **46개 → 57개**로 늘었습니다.

**2. 그렇게 되살아난 테스트 3개가 낡은 기대를 갖고 있었습니다.**

- `develop_export_abi` 의 `film_look_color_applied == 1`: macOS 의 correctness fix 이후
  실제 필름 스캔의 Film Look 은 항상 identity 입니다. 스캔본에는 이미 유제를 통과한 신호가
  들어 있어 유제 응답을 두 번 먹이기 때문입니다. 기대를 현재 계약으로 바꿨습니다.
- `cli.develop_negative_tiff_film_look` 의 `statistics_full_frame_scan_count":3` → `2`,
  `cli.develop_negative_tiff_tone_film_look` 의 `4` → `3`. 이 카운터는 **픽셀을 실제로 바꾼
  단계에서만** 증가합니다. Film Look 이 identity 가 되면서 한 번 줄어든 것이며, 같은 정규식의
  `film_color_applied":false` 부분은 이미 갱신돼 있었는데 카운트만 남아 있었습니다.

셋 다 이번 변경의 회귀가 아니라, 죽어 있던 테스트가 살아나며 드러난 기존 불일치입니다.

## 이번 체크포인트에서 돌린 게이트

| 게이트 | 결과 |
|---|---|
| x64 Debug 네이티브 CTest | 57/57 |
| x64 Release 네이티브 CTest | 57/57 |
| Interop contract (Debug/Release) | 139 assertions, ABI `0.28` |
| Catalog / Shell (Debug/Release) | 583 / 316 assertions, 경고 0·오류 0 |
| ARM64 Release 네이티브 교차 빌드 | 통과, `Negaflow.Native.dll` PE machine `0xAA64` |
| ARM64 Release 관리 전체 graph | 통과, 경고 0·오류 0 |

## 검증하지 않은 것

- **ARM64 실기 실행.** 교차 빌드만 했습니다.
- 같은 입력의 macOS pixel golden. 이 코퍼스에는 macOS 쪽 대응 결과가 없습니다.
- 15장 전체 batch 처리량·장기 peak working set. 이번에는 2장만 계측했습니다.
- GrainMend·Texture 같은 공간 필터 단계를 켠 실촬영 경로.
