#include "negaflow/gpu/gpu_image_pool.h"

#include "negaflow/gpu/gpu_device.h"

#include <utility>

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
    if (retained_[0].is_valid() && retained_width_ == width && retained_height_ == height) {
        for (int index = 0; index < size; ++index) {
            GpuWorkingImage swap = std::move(images_[index]);
            images_[index] = std::move(retained_[index]);
            retained_[index] = std::move(swap);
        }
        std::swap(width_, retained_width_);
        std::swap(height_, retained_height_);
        return true;
    }
    for (int index = 0; index < size; ++index) {
        retained_[index] = std::move(images_[index]);
    }
    retained_width_ = width_;
    retained_height_ = height_;
    for (int index = 0; index < size; ++index) {
        if (GpuWorkingImage::create(device, width, height, images_[index]) !=
            GpuImageStatus::ok) {
            // 못 잡으면 전부 놓습니다 — 반쯤 잡은 상태로 두면 다음 호출이 크기가
            // 맞는다고 믿고 씁니다.
            for (int reset = 0; reset < size; ++reset) {
                images_[reset] = GpuWorkingImage{};
                retained_[reset] = GpuWorkingImage{};
            }
            width_ = 0U;
            height_ = 0U;
            retained_width_ = 0U;
            retained_height_ = 0U;
            return false;
        }
    }
    width_ = width;
    height_ = height;
    return true;
}

}  // namespace negaflow::gpu
