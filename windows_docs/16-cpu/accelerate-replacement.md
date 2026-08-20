# Accelerate(vImage/vDSP) 대체 — 생각보다 작다

조사 2026-08-03 / 출처: `Sources/Chromabase/DefectRemoval/DefectMorphology.swift` (261줄)

## 결론 먼저

**Accelerate 의존은 저장소 전체에서 파일 1개, 함수 2개다.**

```
import Accelerate 를 쓰는 파일:  DefectMorphology.swift  (1개)
실제로 호출하는 API:            vImageMax_PlanarF, vImageMin_PlanarF  (2개)
```

그리고 **그 두 함수의 순수 Swift 대체 구현이 이미 같은 파일 안에 있다.**
`separableExtreme` — van Herk/Gil-Werman monotonic-deque sliding min/max.
주석이 "결과는 기존 naïve 구현과 **동일**"이라고 못 박고 있다.

→ **Windows 이식에서 vImage 등가물을 찾을 필요가 없다. deque 경로를 옮기면 끝이다.**
이건 이 프로젝트 이식 계획에서 드물게 "예상보다 쉬운" 항목이다.

## 옮겨야 하는 CPU 커널 3종

전부 O(N)이고 전부 스칼라 C++로 직역 가능하다.

### 1. `separableExtreme` — 형태학 erosion/dilation

```
알고리즘   van Herk / Gil-Werman, 분리형(수평 → 수직)
복잡도     창 크기(2r+1)와 무관하게 픽셀당 amortized 상수
윈도우     클램프. 각 위치에서 [max(0, i-r), min(n-1, i+r)]
자료구조   단조 deque, 라인마다 재사용 (길이 max(w,h) 정수 배열)
```

**이식 주의:**

- 경계는 **클램프**다. 반사도 아니고 0 패딩도 아니다. 틀리면 프레임 가장자리에서만 결함 검출이 달라진다 — 시각적으로 잘 안 보이고 골든 테스트로만 잡힌다
- 단조 조건이 `<=` / `>=` (등호 포함)다. `<` 로 바꾸면 동점 처리가 달라져 결과가 미세하게 갈린다
- Swift 판은 `withUnsafeBufferPointer`로 경계 검사를 제거했다. C++는 기본이 그러하므로 그대로 쓰면 된다

**SIMD 화 가능한가?** deque 경로는 데이터 의존적 분기라 벡터화가 어렵다. 대신
**라인 단위 병렬화**가 자연스럽다(수평 패스는 행끼리, 수직 패스는 열끼리 독립).
→ 스레드 병렬 먼저, SIMD는 측정 후.

### 2. `boxMean` — 적분영상 롤링 링버퍼

```
알고리즘   적분영상 기반 박스 평균
메모리     링 버퍼 (2r+2)행만 유지
누산 타입  double  ← 중요
```

**왜 링버퍼인가:** 55MP 풀해상도에서 전체 적분영상은 `(w+1)×(h+1) × 8바이트 ≈ 440MB`다.
잡으면 안 된다.

**⚠️ 누산 타입이 double인 것은 실수가 아니다.** 적분영상은 누적합이라 float32로는
큰 이미지에서 정밀도가 무너진다. Windows에서 "float면 캐시에 두 배 들어가니까"로 바꾸면
**결함 검출 임계값이 조용히 달라진다.** → [../99-plan/product-invariants.md](../99-plan/product-invariants.md)

**비트 동일성 보장:** macOS에는 `DefectBoxMeanRollingEquivalenceTests`가 링버퍼 경로와
전체 적분 경로를 대조한다. Windows에도 같은 가드를 만든다.

### 3. `dilateMask` — Bool 마스크 팽창

```
알고리즘   분리형 슬라이딩 카운트, O(N)
동치       morphMax(0/1 Float) > 0.5 와 동일한 결과
목적       Float 임시 평면(8·N 바이트) 없이 같은 결과를 냄
```

메모리 절약이 목적인 전용 경로다. C++로는 `std::vector<uint8_t>`가 자연스럽다
(`std::vector<bool>` 비트팩은 **쓰지 않는다** — 랜덤 접근이 느리고 포인터를 못 얻는다).

## 병렬화 — 현재 구조

`boxMeans(radii:parallel:)`가 **반경별로** 병렬화한다.
`DispatchQueue.concurrentPerform` + `ConcurrentResultStore`(인덱스별 결과 저장).

적분영상은 **한 번만** 만들고 반경별 출력만 병렬로 낸다. 즉 병렬 축이 "픽셀"이 아니라 "반경"이다.

Windows 등가물:

| macOS | Windows |
|---|---|
| `DispatchQueue.concurrentPerform(iterations:)` | `PPL concurrency::parallel_for` 또는 Windows Thread Pool `TrySubmitThreadpoolCallback`, 또는 `std::for_each(std::execution::par, …)` |
| `ConcurrentResultStore<T>` | 결과 슬롯을 미리 잡아 두고 인덱스로만 쓰면 동기화 불필요 (같은 패턴) |

**주의:** 반경 개수가 보통 한 자릿수라 스레드풀 오버헤드가 상대적으로 크다.
`parallel: true`가 기본이 아닌 이유가 그것으로 보인다. Windows에서도 **기본은 순차**,
측정 후 켠다.

## 실측으로 이미 밝혀진 것 — 반복하지 말 것

macOS에서 확인된 사실(다시 시도해서 시간 낭비하지 않는다):

| 시도 | 결과 |
|---|---|
| 스크래치 검출 CPU 병렬화 | **무효** |
| 캐시 전치(transpose) | **무효** |
| 근본 원인 | **메모리 대역 포화** |

→ 자동 검출 15초 중 66%가 스크래치 검출인데, **CPU 최적화로는 안 풀린다.**
Windows에서 유효한 수단은 GPU 컴퓨트뿐이거나, 현 성능을 수용하는 것이다.

**단, 이건 x86 macOS/ARM Mac 실측이다.** Windows의 다른 메모리 서브시스템에서
같은 결론일지는 재측정해야 한다. 특히:

- 대역폭이 다른 하드웨어(DDR5 듀얼채널 데스크톱 vs LPDDR5X 랩톱 vs Snapdragon X)
- 메모리 대역이 병목이면 **스레드를 늘려도 안 빨라지는 것이 정상 신호**다. 그 신호를
  먼저 확인하고, 확인되면 GPU로 넘어간다

→ [../12-performance/gpu-optimization.md](../12-performance/gpu-optimization.md)

## 이식 순서

1. `separableExtreme` — 단독으로 옮기고 골든 벡터로 대조. **의존성 0**
2. `boxMean` + 전체 적분 경로 — 두 경로 상호 대조 테스트 동반
3. `dilateMask`
4. 병렬화는 3개 다 옮기고 **측정한 뒤에**

## 골든 테스트 이전

macOS 쪽 이름(같은 것을 Windows에 만든다):

- `DefectBoxMeanRollingEquivalenceTests` — 링버퍼 ↔ 전체 적분
- `DefectScratchEquivalenceTests` — 최적화 전후 수치 동일성

**합성 픽스처만 쓴다. 실제 스캔 파일을 테스트에 넣지 않는다.**
→ [../12-performance/ci-and-testing.md](../12-performance/ci-and-testing.md)

## 관련

- [simd-and-dispatch.md](simd-and-dispatch.md) — 아키텍처별 SIMD 전략
- [../12-performance/gpu-optimization.md](../12-performance/gpu-optimization.md) — GPU로 넘길 대상
