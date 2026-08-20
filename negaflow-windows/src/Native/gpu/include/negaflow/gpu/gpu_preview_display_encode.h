#pragma once

// macOS `renderDisplayCGImage` 의 `createCGImage(..., format: .RGBA8)` 대응.
// CPU 판은 `write_preview` 1:1 화소 경로. 마지막 회수는 BGRA8 입니다.

#include "negaflow/gpu/gpu_pointwise.h"

#include <cstdint>

struct ID3D11Texture2D;
struct ID3D11UnorderedAccessView;

namespace negaflow::gpu {

class GpuDevice;
class GpuWorkingImage;

class GpuPreviewDisplayEncode final {
public:
    GpuPreviewDisplayEncode() noexcept = default;
    ~GpuPreviewDisplayEncode();

    GpuPreviewDisplayEncode(const GpuPreviewDisplayEncode&) = delete;
    GpuPreviewDisplayEncode& operator=(const GpuPreviewDisplayEncode&) = delete;

    [[nodiscard]] static GpuKernelStatus create(
        const GpuDevice& device,
        GpuPreviewDisplayEncode& kernel) noexcept;

    // `destination` 은 width*height*4 BGRA8. 상자 평균 없이 1:1 일 때만 부릅니다.
    [[nodiscard]] GpuKernelStatus encode(
        const GpuDevice& device,
        const GpuWorkingImage& source,
        std::uint8_t* destination,
        std::uint32_t destination_stride_bytes,
        const float proof_scale[3],
        const float proof_bias[3]) const noexcept;

    [[nodiscard]] bool is_valid() const noexcept { return shader_ != nullptr; }

private:
    void reset() noexcept;
    [[nodiscard]] bool ensure_target(
        const GpuDevice& device,
        std::uint32_t width,
        std::uint32_t height) const noexcept;

    ID3D11ComputeShader* shader_{nullptr};
    ID3D11Buffer* constants_{nullptr};
    mutable ID3D11Texture2D* target_{nullptr};
    mutable ID3D11UnorderedAccessView* target_uav_{nullptr};
    mutable ID3D11Texture2D* staging_{nullptr};
    mutable std::uint32_t width_{0};
    mutable std::uint32_t height_{0};
};

}  // namespace negaflow::gpu
