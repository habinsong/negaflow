#pragma once

// macOS `CIAreaAverage` 대응 GPU 리덕션입니다.
//
// CPU 판 : `imaging/area_average.cpp`
// 셰이더 : `src/Native/gpu/shaders/area_average.hlsl`
//
// cs_5_0 `groupshared` 트리만 씁니다. Wave 내장은 벤더마다 크기가 달라 쓰지 않습니다.
//
// ☠️ **근사입니다.** CPU 는 행 우선 double, GPU 는 float 트리. 평균 1e-5.

#include "negaflow/gpu/gpu_pointwise.h"

#include <cstdint>

struct ID3D11ComputeShader;
struct ID3D11Buffer;
struct ID3D11UnorderedAccessView;
struct ID3D11ShaderResourceView;

namespace negaflow::gpu {

class GpuDevice;
class GpuWorkingImage;

class GpuAreaAverage final {
public:
    GpuAreaAverage() noexcept = default;
    ~GpuAreaAverage();

    GpuAreaAverage(const GpuAreaAverage&) = delete;
    GpuAreaAverage& operator=(const GpuAreaAverage&) = delete;
    GpuAreaAverage(GpuAreaAverage&& other) noexcept;
    GpuAreaAverage& operator=(GpuAreaAverage&& other) noexcept;

    [[nodiscard]] static GpuKernelStatus create(
        const GpuDevice& device,
        GpuAreaAverage& kernel) noexcept;

    // `mean` 은 rgba, `count` 는 영역에 들어간 화소 수입니다.
    [[nodiscard]] GpuKernelStatus dispatch(
        const GpuDevice& device,
        const GpuWorkingImage& source,
        std::uint32_t origin_x,
        std::uint32_t origin_y,
        std::uint32_t extent_width,
        std::uint32_t extent_height,
        float mean[4],
        std::uint64_t& count) const noexcept;

    [[nodiscard]] bool is_valid() const noexcept { return image_ != nullptr; }

private:
    void reset() noexcept;

    ID3D11ComputeShader* image_{nullptr};
    ID3D11ComputeShader* partials_{nullptr};
    ID3D11Buffer* constants_{nullptr};
    ID3D11Buffer* buffer_a_{nullptr};
    ID3D11Buffer* buffer_b_{nullptr};
    ID3D11UnorderedAccessView* uav_a_{nullptr};
    ID3D11UnorderedAccessView* uav_b_{nullptr};
    ID3D11ShaderResourceView* srv_a_{nullptr};
    ID3D11ShaderResourceView* srv_b_{nullptr};
    ID3D11Buffer* readback_{nullptr};
    std::uint32_t capacity_{0};
};

}  // namespace negaflow::gpu
