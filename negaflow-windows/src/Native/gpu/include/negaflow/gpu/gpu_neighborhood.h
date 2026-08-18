#pragma once

// 이웃을 보는 원시연산입니다. macOS 는 이 자리를 Apple 내장 필터가 채웁니다 —
// `CIGaussianBlur` · `CIBoxBlur` · `CIMedianFilter` · `CIAreaAverage`.
// **Windows 에는 그 내장 필터가 없어 우리가 만들어야 합니다. 여기가 실제 작업량입니다.**
//
// | | macOS | Windows CPU | 셰이더 |
// |---|---|---|---|
// | 박스 블러 | `CIBoxBlur` (`FilmScanDenoise.swift:154`) | `imaging/film_scan_denoise_filters.cpp` `box_blur` | `shaders/box_blur.hlsl` |
//
// 가이드 필터 4커널(`gfProduct`·`gfCoeffA`·`gfCoeffB`·`gfApply`)과 `filmScanShrink` 가
// 박스 평균에 물려 있습니다. 그래서 그 커널들보다 이것이 먼저입니다.

#include <cstdint>

#include "negaflow/gpu/gpu_pointwise.h"

struct ID3D11ComputeShader;
struct ID3D11Buffer;

namespace negaflow::gpu {

class GpuDevice;
class GpuWorkingImage;

// 분리형(수평 → 수직) 박스 블러입니다.
//
// ☠️ CPU 판은 러닝 섬이라 부동소수 누적 **순서**가 결과에 남습니다. 이 구현은 행/열마다
//    스레드 하나를 두어 같은 순서로 누적합니다. 순진한 "반경만큼 다시 더하기" 로 바꾸면
//    화소당 O(r) 로 느려질 뿐 아니라 값도 갈립니다.
class GpuBoxBlur final {
public:
    GpuBoxBlur() noexcept = default;
    ~GpuBoxBlur();

    GpuBoxBlur(const GpuBoxBlur&) = delete;
    GpuBoxBlur& operator=(const GpuBoxBlur&) = delete;
    GpuBoxBlur(GpuBoxBlur&& other) noexcept;
    GpuBoxBlur& operator=(GpuBoxBlur&& other) noexcept;

    [[nodiscard]] static GpuKernelStatus create(const GpuDevice& device, GpuBoxBlur& kernel) noexcept;

    // `source` → `scratch`(수평) → `destination`(수직). 세 장이 모두 같은 크기여야 하고
    // 서로 달라야 합니다 — D3D11 은 한 자원을 SRV 와 UAV 로 동시에 묶을 수 없습니다.
    //
    // `radius` 가 0 이면 CPU 판과 같이 원본을 그대로 내보냅니다(창 크기 1).
    [[nodiscard]] GpuKernelStatus dispatch(
        const GpuDevice& device,
        const GpuWorkingImage& source,
        GpuWorkingImage& scratch,
        GpuWorkingImage& destination,
        std::int32_t radius) const noexcept;

    [[nodiscard]] bool is_valid() const noexcept { return horizontal_ != nullptr; }

private:
    void reset() noexcept;

    ID3D11ComputeShader* horizontal_{nullptr};
    ID3D11ComputeShader* vertical_{nullptr};
    ID3D11Buffer* constants_{nullptr};
};

}  // namespace negaflow::gpu
