#pragma once

#include "negaflow/core/pixel.h"
#include "negaflow/gpu/gpu_pointwise.h"

#include <cstdint>
#include <vector>

struct ID3D11Buffer;
struct ID3D11ComputeShader;
struct ID3D11UnorderedAccessView;

namespace negaflow::gpu {

class GpuDevice;
class GpuWorkingImage;

// GPU 에 있는 화상에서 **점 표본 격자**를 뽑아 호스트로 내립니다.
//
// 격자 칸 (x, y) 는 원본의 (min(w-1, x*w/dw), min(h-1, y*h/dh)) 화소 하나를 그대로 담습니다 —
// `scanner_target_measure.cpp` 의 CPU 표본과 같은 자리·같은 값입니다. 화상 전체(8.7MP 면
// 138 MB)를 내리는 대신 격자(160 칸 폭)만 내리려고 둡니다.
class GpuPointSampleGrid final {
public:
    GpuPointSampleGrid() noexcept = default;
    ~GpuPointSampleGrid();

    GpuPointSampleGrid(const GpuPointSampleGrid&) = delete;
    GpuPointSampleGrid& operator=(const GpuPointSampleGrid&) = delete;

    [[nodiscard]] static GpuKernelStatus create(
        const GpuDevice& device,
        GpuPointSampleGrid& kernel) noexcept;

    // `samples` 는 `grid_width * grid_height` 칸으로 채워집니다(행 우선). 자리는 나눗수
    // `divisor_width`·`divisor_height` 로 정합니다.
    [[nodiscard]] GpuKernelStatus dispatch(
        const GpuDevice& device,
        const GpuWorkingImage& source,
        std::uint32_t divisor_width,
        std::uint32_t divisor_height,
        std::uint32_t grid_width,
        std::uint32_t grid_height,
        std::vector<core::Rgba32F>& samples) noexcept;

private:
    void reset() noexcept;
    void release_buffers() noexcept;
    [[nodiscard]] bool ensure_capacity(const GpuDevice& device, std::uint32_t count) noexcept;

    ID3D11ComputeShader* shader_{nullptr};
    ID3D11Buffer* constants_{nullptr};
    ID3D11Buffer* samples_{nullptr};
    ID3D11UnorderedAccessView* samples_view_{nullptr};
    ID3D11Buffer* readback_{nullptr};
    std::uint32_t capacity_{0U};
};

}  // namespace negaflow::gpu
