#include "negaflow/gpu/gpu_image_pool.h"

#include "negaflow/gpu/gpu_device.h"

namespace negaflow::gpu {

bool GpuImagePool::ensure(
    const GpuDevice& device,
    const std::uint32_t width,
    const std::uint32_t height) noexcept {
    if (width == 0U || height == 0U) {
        return false;
    }
    if (images_[0].is_valid() && width_ == width && height_ == height) {
        return true;
    }
    for (int index = 0; index < size; ++index) {
        if (GpuWorkingImage::create(device, width, height, images_[index]) !=
            GpuImageStatus::ok) {
            // 못 잡으면 전부 놓습니다 — 반쯤 잡은 상태로 두면 다음 호출이 크기가
            // 맞는다고 믿고 씁니다.
            for (int reset = 0; reset < size; ++reset) {
                images_[reset] = GpuWorkingImage{};
            }
            width_ = 0U;
            height_ = 0U;
            return false;
        }
    }
    width_ = width;
    height_ = height;
    return true;
}

}  // namespace negaflow::gpu
