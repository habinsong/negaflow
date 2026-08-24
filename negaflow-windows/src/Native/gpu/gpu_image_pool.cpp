#include "negaflow/gpu/gpu_image_pool.h"

#include "negaflow/gpu/gpu_device.h"

#include <limits>
#include <utility>

namespace negaflow::gpu {
namespace {

void reset_images(GpuWorkingImage* const images) noexcept {
    for (int index = 0; index < GpuImagePool::size; ++index) {
        images[index] = GpuWorkingImage{};
    }
}

[[nodiscard]] bool texture_pool_bytes(
    const std::uint32_t width,
    const std::uint32_t height,
    const int image_count,
    std::uint64_t& bytes) noexcept {
    constexpr std::uint64_t bytes_per_pixel = 16ULL;
    if (width == 0U || height == 0U || image_count < 1 || image_count > GpuImagePool::size) {
        return false;
    }
    const std::uint64_t row = static_cast<std::uint64_t>(width) * bytes_per_pixel;
    if (row > std::numeric_limits<std::uint64_t>::max() / height) {
        return false;
    }
    const std::uint64_t image = row * height;
    const auto images = static_cast<std::uint64_t>(image_count);
    if (image > std::numeric_limits<std::uint64_t>::max() / images) {
        return false;
    }
    bytes = image * images;
    return true;
}

[[nodiscard]] bool can_keep_two_sizes(
    const GpuDevice& device,
    const std::uint64_t additional_bytes) noexcept {
    // WARP와 UMA는 로컬 GPU 자원이 시스템 RAM과 같은 물리 메모리를 씁니다. 치수 두 벌을
    // 보존하면 Windows RAM 캐시와 별도로 같은 RAM을 다시 잠그므로 한 벌만 유지합니다.
    if (device.capability().adapter.is_integrated) {
        return false;
    }

    GpuVideoMemoryInfo memory{};
    if (!device.query_local_video_memory_info(memory) ||
        memory.current_usage > memory.budget ||
        additional_bytes > memory.budget - memory.current_usage) {
        return false;
    }
    return true;
}

}  // namespace

bool GpuImagePool::ensure(
    const GpuDevice& device,
    const std::uint32_t width,
    const std::uint32_t height,
    const int required_image_count) noexcept {
    if (width == 0U || height == 0U ||
        required_image_count < 1 || required_image_count > size) {
        return false;
    }
    if (images_[0].is_valid() && width_ == width && height_ == height) {
        if (retained_[0].is_valid() && !can_keep_two_sizes(device, 0ULL)) {
            reset_images(retained_);
            retained_width_ = 0U;
            retained_height_ = 0U;
        }
        for (int index = 0; index < required_image_count; ++index) {
            if (!images_[index].is_valid() &&
                GpuWorkingImage::create(device, width, height, images_[index]) !=
                    GpuImageStatus::ok) {
                reset_images(images_);
                width_ = 0U;
                height_ = 0U;
                return false;
            }
        }
        return true;
    }
    if (retained_[0].is_valid() && retained_width_ == width && retained_height_ == height) {
        if (can_keep_two_sizes(device, 0ULL)) {
            for (int index = 0; index < size; ++index) {
                GpuWorkingImage swap = std::move(images_[index]);
                images_[index] = std::move(retained_[index]);
                retained_[index] = std::move(swap);
            }
            std::swap(width_, retained_width_);
            std::swap(height_, retained_height_);
            for (int index = 0; index < required_image_count; ++index) {
                if (!images_[index].is_valid() &&
                    GpuWorkingImage::create(device, width, height, images_[index]) !=
                        GpuImageStatus::ok) {
                    clear();
                    return false;
                }
            }
            return true;
        }
        reset_images(images_);
        for (int index = 0; index < size; ++index) {
            images_[index] = std::move(retained_[index]);
        }
        width_ = retained_width_;
        height_ = retained_height_;
        retained_width_ = 0U;
        retained_height_ = 0U;
        for (int index = 0; index < required_image_count; ++index) {
            if (!images_[index].is_valid() &&
                GpuWorkingImage::create(device, width, height, images_[index]) !=
                    GpuImageStatus::ok) {
                clear();
                return false;
            }
        }
        return true;
    }

    // 두 단계 전 치수는 먼저 버립니다. 그 뒤 DXGI CurrentUsage를 읽어야 이미 버린 풀까지
    // 사용량에 넣어 새 풀을 불필요하게 거부하지 않습니다.
    reset_images(retained_);
    retained_width_ = 0U;
    retained_height_ = 0U;

    std::uint64_t new_pool_bytes = 0ULL;
    const bool keep_current =
        texture_pool_bytes(width, height, required_image_count, new_pool_bytes) &&
        can_keep_two_sizes(device, new_pool_bytes);
    if (keep_current) {
        for (int index = 0; index < size; ++index) {
            retained_[index] = std::move(images_[index]);
        }
        retained_width_ = width_;
        retained_height_ = height_;
    } else {
        reset_images(images_);
    }

    for (int index = 0; index < required_image_count; ++index) {
        if (GpuWorkingImage::create(device, width, height, images_[index]) !=
            GpuImageStatus::ok) {
            // 못 잡으면 전부 놓습니다 — 반쯤 잡은 상태로 두면 다음 호출이 크기가
            // 맞는다고 믿고 씁니다.
            reset_images(images_);
            reset_images(retained_);
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

void GpuImagePool::clear() noexcept {
    reset_images(images_);
    reset_images(retained_);
    width_ = 0U;
    height_ = 0U;
    retained_width_ = 0U;
    retained_height_ = 0U;
}

}  // namespace negaflow::gpu
