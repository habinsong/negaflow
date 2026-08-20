# GPU 벤더 범용성

기준일: 2026-08-04  
결정: Intel·AMD·NVIDIA·Qualcomm·WARP에서 기능과 결과는 같고 속도만 달라야 한다.

세부 API 선택은 [backend-selection.md](backend-selection.md)를 따른다. 이전 문서의
`D3D12 + FL 12_0 + SM 6.0 필수` 결론은 폐기되었고 v1 기준선은
`D3D11 FL 11_0 + SM 5.0 + Direct2D/DirectCompute`다.

## 1. 제품 원칙

```text
1순위  모든 필수 벤더에서 같은 기능·같은 품질
2순위  가장 느린 필수 장치에서도 충분한 사용자 경험
3순위  CPU와 WARP로 완전한 복구 경로
4순위  벤더 전용 선택 가속
```

다음은 제품 실패다.

- NVIDIA에서만 Defect Removal이 보임
- Intel에서 자동 톤 결과가 달라짐
- AMD에서 highlight가 더 일찍 clamp됨
- ARM64에서 export가 저품질 codec으로 조용히 바뀜
- WARP에서 일부 조정이 비활성화됨
- GPU 오류 후 원본 이미지로 조용히 export함

## 2. 필수 어댑터군

| 군 | 최소 대표 범위 | 집중 위험 |
|---|---|---|
| Intel x64 iGPU | UHD/Iris Xe | 공유 메모리, 낮은 bandwidth, 오래된 OEM driver |
| Intel x64 dGPU | Arc | discrete budget, driver update, hybrid display |
| AMD x64 iGPU | Ryzen APU | UMA, 전력 상태, shared budget |
| AMD x64 dGPU | Radeon | wave 차이, multi-monitor, device reset |
| NVIDIA x64 dGPU | GTX/RTX 세대 범위 | Optimus, Studio/Game driver, discrete copy |
| Qualcomm ARM64 | Adreno Windows 장치 | native ARM64, UMA, driver/format coverage |
| Microsoft WARP | 지원 OS 내장 | 기능 conformance, 낮은 처리량 |

특정 모델 목록은 출시 직전 hardware lab inventory에서 작성한다. 최소 한 최신 장치만 통과시키지
않고 지원하려는 feature level의 오래된 하한, 일반 장치, 최신 장치를 나눈다.

## 3. 기능 query가 vendor 문자열보다 우선한다

앱은 `VendorId == NVIDIA` 같은 분기로 core algorithm을 고르지 않는다.

startup에 확인:

- feature level 11_0 이상
- required texture formats의 sample/render/UAV support
- Direct2D buffer precision
- maximum texture dimension
- compute shader와 resource limits
- DXGI memory budget API
- composition swap-chain support

알려진 driver workaround가 필요할 때만 `vendor + device + driver range`를 좁게 사용하고 다음을
함께 기록한다.

- upstream/내부 issue ID
- 실제 재현 조건
- 우회로가 바꾸는 것은 실행 방식뿐이며 결과가 같다는 테스트
- 제거할 driver version과 만료일

영구적인 “AMD면 이 코드”, “Intel이면 품질 낮춤” 분기는 금지한다.

## 4. HLSL portable subset

v1 셰이더는 SM5 범용 subset을 사용한다.

- wave size를 32/64로 가정하지 않는다.
- vendor intrinsic, inline assembly, NVIDIA/AMD extension을 core shader에 쓰지 않는다.
- subgroup/wave intrinsic에 의존하지 않는다.
- thread-group 크기와 shared-memory 사용을 상한까지 채우지 않는다.
- out-of-bounds read/write를 driver가 막아줄 것으로 가정하지 않는다.
- resource와 sampler slot을 manifest에서 고정한다.
- uninitialized groupshared/register 값을 읽지 않는다.
- atomics의 실행 순서를 수치 결과의 순서로 사용하지 않는다.
- denormal, NaN, Inf, signed zero를 stage별로 명시한다.
- compiler optimization에 따라 undefined result가 바뀌는 HLSL을 허용하지 않는다.

하나의 shader blob을 모든 벤더가 소비하는 것이 기본이다. 벤더별 blob은 verified compiler/driver
bug workaround 또는 선택적 CUDA module에만 허용한다.

## 5. 부동소수 결과 계약

GPU 부동소수는 bit-identical을 항상 보장하지 않는다. 그렇다고 최종 이미지가 눈에 띄게 달라도
된다는 뜻은 아니다.

### stage별 계약

| 단계 | 비교 |
|---|---|
| pointwise color/tone | absolute/relative error, neutral·highlight·saturated probes |
| LUT/interpolation | grid corner, cell boundary, monotonicity |
| resize/spatial | impulse, edge, gradient, halo, border behavior |
| histogram | exact integer bins가 기본 |
| floating reduction | deterministic partial layout 또는 CPU final reduction |
| auto parameters | 동일 값 또는 매우 좁은 명시 오차 |
| final export | decoded pixels + ICC + metadata semantics |

단일 PSNR 숫자로 모든 문제를 가리지 않는다. 예를 들어 전체 평균 오차가 작아도 neutral gray의
channel imbalance나 highlight clamp는 제품에 치명적일 수 있다.

### 연산 순서

- 자동 톤·film-base measurement처럼 결과가 다음 파라미터를 바꾸는 계산은 순서를 고정한다.
- histogram bin은 integer atomic 또는 결정적 CPU 경로를 사용한다.
- percentile 계산은 같은 tie/boundary 정책을 사용한다.
- FMA 사용 여부가 임계값을 넘나들면 CPU/GPU 양쪽의 contract를 재설계한다.
- fast-math는 전역 compile flag로 켜지 않는다.

## 6. 정밀도와 포맷

- intermediate UNORM 금지
- extended-linear 음수·1 초과 값 보존
- FP16은 stage별 골든 통과 후 선택 최적화
- display surface format과 working texture를 구분
- sRGB flag와 ICC transform을 혼동하지 않음
- alpha premultiplication을 input/output마다 명시
- mask와 color texture의 precision을 별도로 정함

지원하지 않는 float format을 만났을 때 8-bit로 내리지 않는다. CPU 또는 다른 float 경로로
전환하고 adapter diagnostic에 기록한다.

## 7. groupshared와 thread-group portability

하드웨어마다 occupancy, register file, cache, wave scheduling이 다르다.

초기 후보:

- pointwise 2D: 8×8, 16×8, 16×16
- spatial tile: halo 포함 shared-memory byte 수를 먼저 계산
- reduction: 128, 256
- 512/1024 threads는 실제 순이득이 있을 때만

튜닝 기준:

- kernel time뿐 아니라 full graph와 memory traffic
- 각 필수 벤더 p50/p95
- register spill과 occupancy
- UMA와 dGPU의 upload/readback 차이
- 작은 ROI와 큰 tile
- thermal/battery sustained run

한 벤더의 최고값보다 전체 matrix에서 최악의 회귀를 최소화한다. 벤더별 최적 thread-group
permutation을 둘 수는 있지만 같은 HLSL source와 결과 contract를 사용하고 capability/timing으로
선택한다.

## 8. Intel

집중 항목:

- shared system memory budget을 VRAM 크기로 오인하지 않기
- OEM driver와 Intel generic driver 차이
- 낮은 bandwidth에서 full-frame intermediate 수
- iGPU와 Arc가 함께 있는 환경
- older FL11_0 장치의 format support
- integrated display adapter와 external GPU 선택

성능 최적화 우선순위는 Intel iGPU와 Qualcomm UMA가 기준이다. 이 장치에서 pass fusion, ROI,
tile cache와 CPU/GPU transfer를 줄이면 다른 벤더도 대부분 이득을 본다.

## 9. AMD

집중 항목:

- wave size에 대한 암묵적 가정 제거
- LDS 사용과 thread-group별 occupancy
- APU UMA와 Radeon dGPU의 다른 budget 성격
- multi-monitor/Advanced Color
- driver update와 device removal
- atomics-heavy histogram의 분포 편향

GPUOpen 자료는 최적화 아이디어의 출발점일 뿐 AMD 전용 결과를 기준으로 만들지 않는다.

## 10. NVIDIA

집중 항목:

- Optimus에서 render adapter와 display/compositor 관계
- Studio와 Game Ready driver 모두의 smoke
- PCIe upload/readback과 discrete VRAM budget
- laptop power preference
- CUDA optional module이 없을 때 완전한 D3D11 기능
- CUDA module load/version failure의 안전 폴백

NVIDIA가 빠르다는 이유로 kernel 작업 크기와 sync 전략을 NVIDIA 기준으로 고정하지 않는다.

## 11. Qualcomm·Windows ARM64

집중 항목:

- 앱, native DLL, 의존성, plugin host의 순수 ARM64
- Adreno D3D11/Direct2D 필수 format 실측
- UMA memory pressure
- x64 에뮬레이션과 native artifact 혼입 방지
- long-running export의 전력·thermal behavior
- WARP 폴백 성능
- 스캐너 kernel driver는 별도의 ARM64 지원 문제

ARM64 CI가 compile만 통과해서는 안 된다. 실제 ARM64 장치에서 WARP와 hardware GPU의 픽셀
golden, 설치, 캔버스, export를 실행한다.

## 12. 하이브리드 GPU와 다중 모니터

노트북은 다음 상태가 동적으로 변한다.

- Windows graphics preference
- 전원/배터리 상태
- 외장 모니터 연결
- 창이 있는 모니터
- driver update
- eGPU 연결·해제

원칙:

- startup에 고른 adapter를 영원히 유효하다고 가정하지 않는다.
- 사용자가 Windows Settings에서 정한 preference를 우선한다.
- 창 이동마다 무조건 engine을 재생성하지 않고 color profile과 presentation 경계를 분리한다.
- adapter LUID와 display/output/profile identity를 따로 추적한다.
- cross-adapter copy가 생기는지 PIX/PresentMon으로 측정한다.
- 변경으로 device가 제거되면 사용자 상태를 유지하고 generation 전체를 재생성한다.

## 13. 드라이버 정책

### 최소 버전

실제 blocker가 없는 한 임의의 최신 driver를 강제하지 않는다. blocker가 확인되면:

- 벤더·device family·최소 fixed version
- 재현 fixture와 오류
- 앱의 safe fallback
- 사용자에게 제공할 공식 driver 링크
- telemetry 없이도 진단 가능한 adapter report

를 문서화한다.

### blacklist

원격으로 조용히 기능을 끄는 blacklist를 v1 기본으로 만들지 않는다. 필요하면 signed compatibility
manifest, expiry, 사용자 표시, offline fallback, 회귀 테스트가 있어야 한다.

### 오류 보고

로그에는 driver version과 HRESULT를 포함할 수 있지만 원본 파일명·경로·이미지 내용은 기본으로
수집하지 않는다.

## 14. WARP conformance

WARP는 실제 vendor matrix를 대체하지 않는다. 역할은 다음이다.

- CI에서 shader/effect registration과 basic graph를 항상 실행
- hardware가 없는 build agent에서 수치 회귀 감지
- hardware device creation 실패 시 기능 유지
- device-lost 복구 테스트

WARP 테스트만 통과했다고 Intel/AMD/NVIDIA/Qualcomm 지원을 선언하지 않는다. 반대로 hardware
결과와 WARP가 허용 오차를 넘으면 vendor 특성으로 무시하지 않는다.

## 15. CUDA의 위치

CUDA는 NVIDIA 전용 선택 tier다.

- 기능 flag가 아니라 operation backend
- 설치되지 않아도 오류 없이 D3D11 사용
- D3D11/CPU 구현과 골든이 먼저 존재
- end-to-end 20% 이상 또는 명확한 절대 시간 이득
- driver, runtime, interop, package size, EULA, 유지 테스트 비용 포함
- CUDA 전용 품질 option·preset 금지

초기 후보를 억지로 정하지 않는다. 실제 프로파일에서 NVIDIA의 D3D11 병목이 확인된 operation만
평가한다. `nvJPEG` 같은 codec도 disk/CPU pipeline 전체와 비교한다.

## 16. 실기 QA matrix 기록 형식

각 결과는 다음 필드를 가진다.

```text
test-run-id
product-build-id / engine-build-id / shader-manifest-hash
Windows build
CPU architecture and model
adapter LUID / vendor-device ID / driver version
feature level / WARP flag / required-format report
RAM / video-memory budget
display mode / ICC / SDR-HDR
dataset IDs and licenses
operation timings and memory peaks
numeric-conformance report
device-lost / warning / fallback events
```

“제 컴퓨터에서 됨” 대신 재현 가능한 artifact를 남긴다.

## 17. 출시 게이트

- 필수 벤더군별 최소 1대가 아니라 하한·일반·최신 범위를 승인한다.
- x64 Intel/AMD CPU와 ARM64에서 native binary를 확인한다.
- WARP full functional suite를 통과한다.
- 동일 fixture의 backend 수치 report를 비교한다.
- 8GB UMA에서 OOM 대신 bounded degradation을 확인한다.
- device removal 강제 시험 후 작업 상태가 보존된다.
- hybrid GPU와 서로 다른 ICC의 다중 모니터를 시험한다.
- unsupported adapter는 품질 저하가 아니라 명시적 CPU/WARP 전환을 한다.

## 공식 근거

- [Direct3D hardware feature levels](https://learn.microsoft.com/en-us/windows/win32/direct3d12/hardware-feature-levels)
- [Direct3D 11 compute shader overview](https://learn.microsoft.com/en-us/windows/win32/direct3d11/direct3d-11-advanced-stages-compute-shader)
- [Direct2D and Direct3D interoperability](https://learn.microsoft.com/en-us/windows/win32/direct2d/direct2d-and-direct3d-interoperation-overview)
- [DXGI video-memory budget](https://learn.microsoft.com/en-us/windows/win32/direct3ddxgi/dxgi-1-4-improvements)
- [Create a WARP device](https://learn.microsoft.com/en-us/windows/win32/direct3d11/overviews-direct3d-11-devices-create-warp)
- [Handle device removed scenarios](https://learn.microsoft.com/en-us/windows/uwp/gaming/handling-device-lost-scenarios)
- [Add Arm support to Windows apps](https://learn.microsoft.com/en-us/windows/arm/add-arm-support)

