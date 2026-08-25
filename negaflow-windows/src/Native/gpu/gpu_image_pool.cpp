#include "negaflow/gpu/gpu_image_pool.h"

#include "negaflow/gpu/gpu_cache_budget.h"
#include "negaflow/gpu/gpu_device.h"

#include <algorithm>
#include <limits>
#include <utility>

namespace negaflow::gpu {
namespace {

void reset_images(GpuWorkingImage* const images) noexcept {
    for (int index = 0; index < GpuImagePool::size; ++index) {
        images[index] = GpuWorkingImage{};
    }
}

// 텍스처를 실제로 놓았으면 그 자리에서 회수까지 시킵니다.
//
// 스캐너 프레임은 높이가 몇 화소씩 다릅니다 - 실측 `부산` 22장이 3420·3422·3423·3461·
// 3487·3493 처럼 전부 다릅니다. 풀은 치수가 정확히 같아야 재사용하므로 **사진 한 장마다**
// 텍스처 6장을 새로 만들고 옛 6장을 놓습니다. D3D11 은 그 해제를 지연하므로, 제출하지
// 않으면 큐에 계속 쌓입니다. 그것이 "사진을 볼수록 메모리가 는다" 의 정체였습니다.
void release_images(const GpuDevice& device, GpuWorkingImage* const images) noexcept {
    bool released = false;
    for (int index = 0; index < GpuImagePool::size; ++index) {
        released = released || images[index].is_valid();
        images[index] = GpuWorkingImage{};
    }
    if (released) {
        (void)device.flush_released_resources();
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

// 이 묶음이 시스템 RAM 에서 쓰는 바이트입니다 - 스테이징 두 장이 여기 들어갑니다.
[[nodiscard]] std::uint64_t system_bytes(const GpuWorkingImage* const images) noexcept {
    std::uint64_t bytes = 0ULL;
    for (int index = 0; index < GpuImagePool::size; ++index) {
        bytes += images[index].system_memory_bytes();
    }
    return bytes;
}

// 유효한 장 수만큼의 텍스처 바이트입니다. 치수를 모르면(풀이 비었으면) 0 입니다.
[[nodiscard]] std::uint64_t live_bytes(
    const GpuWorkingImage* const images,
    const std::uint32_t width,
    const std::uint32_t height) noexcept {
    int valid = 0;
    for (int index = 0; index < GpuImagePool::size; ++index) {
        if (images[index].is_valid()) {
            ++valid;
        }
    }
    std::uint64_t bytes = 0ULL;
    if (valid == 0 || !texture_pool_bytes(width, height, valid, bytes)) {
        return 0ULL;
    }
    return bytes;
}

[[nodiscard]] bool can_keep_two_sizes(
    const GpuDevice& device,
    const std::uint64_t additional_bytes,
    const std::uint64_t own_bytes) noexcept {
    // WARP와 UMA는 로컬 GPU 자원이 시스템 RAM과 같은 물리 메모리를 씁니다. 치수 두 벌을
    // 보존하면 Windows RAM 캐시와 별도로 같은 RAM을 다시 잠그므로 한 벌만 유지합니다.
    if (device.capability().adapter.is_integrated) {
        return false;
    }

    // 설정 창이 정한 GPU 캐시 상한을 먼저 봅니다. 보존 한 벌은 **속도를 위한 여유분**이라
    // 예산이 빠듯하면 가장 먼저 놓을 것이 이것입니다.
    const std::uint64_t limit = GpuCacheBudget::effective_bytes(device);
    if (limit > 0ULL) {
        const std::uint64_t resident = gpu_pool_resident_bytes();
        const std::uint64_t others = resident > own_bytes ? resident - own_bytes : 0ULL;
        if (own_bytes > limit - std::min(limit, others) ||
            additional_bytes > limit - std::min(limit, others + own_bytes)) {
            return false;
        }
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

GpuImagePool::~GpuImagePool() {
    if (reported_bytes_ > 0ULL) {
        remove_gpu_pool_resident_bytes(reported_bytes_);
        reported_bytes_ = 0ULL;
    }
}

bool GpuImagePool::fits_budget(
    const GpuDevice& device,
    const std::uint32_t width,
    const std::uint32_t height,
    const int required_image_count) const noexcept {
    const std::uint64_t limit = GpuCacheBudget::effective_bytes(device);
    if (limit == 0ULL) {
        // 장치가 없으면 어차피 텍스처를 못 만듭니다. 여기서 막지 않습니다.
        return true;
    }
    std::uint64_t need = 0ULL;
    if (!texture_pool_bytes(width, height, required_image_count, need)) {
        return false;
    }
    // 다른 풀이 들고 있는 몫만 남의 것입니다. 내 몫은 이 호출에서 갈아 끼울 것이므로 뺍니다.
    const std::uint64_t resident = gpu_pool_resident_bytes();
    const std::uint64_t others = resident > reported_bytes_ ? resident - reported_bytes_ : 0ULL;
    if (others >= limit) {
        return false;
    }
    return need <= limit - others;
}

void GpuImagePool::sync_resident_bytes() noexcept {
    const std::uint64_t total =
        live_bytes(images_, width_, height_) +
        live_bytes(retained_, retained_width_, retained_height_);
    if (total > reported_bytes_) {
        add_gpu_pool_resident_bytes(total - reported_bytes_);
    } else if (total < reported_bytes_) {
        remove_gpu_pool_resident_bytes(reported_bytes_ - total);
    }
    reported_bytes_ = total;
    // 시스템 RAM 몫은 **스테이징 두 장**입니다(항상 CPU 접근이라 RAM 에 있습니다).
    // 내장 그래픽이면 텍스처까지 시스템 RAM 이므로 전부 셉니다.
    const std::uint64_t staging = system_bytes(images_) + system_bytes(retained_);
    set_gpu_pool_system_memory_bytes(
        system_memory_backed_ ? staging + total : staging);
}

bool GpuImagePool::ensure(
    const GpuDevice& device,
    const std::uint32_t width,
    const std::uint32_t height,
    const int required_image_count) noexcept {
    system_memory_backed_ = device.capability().adapter.is_integrated;
    const bool ready = ensure_impl(device, width, height, required_image_count);
    sync_resident_bytes();
    return ready;
}

bool GpuImagePool::ensure_impl(
    const GpuDevice& device,
    const std::uint32_t width,
    const std::uint32_t height,
    const int required_image_count) noexcept {
    if (width == 0U || height == 0U ||
        required_image_count < 1 || required_image_count > size) {
        return false;
    }
    // 설정 창이 정한 GPU 캐시 상한입니다. 이 풀이 지금 들고 있는 몫은 빼고 봅니다 —
    // 자기 자신과 경쟁하면 같은 치수를 다시 청할 때마다 거부됩니다.
    if (!fits_budget(device, width, height, required_image_count)) {
        return false;
    }
    if (images_[0].is_valid() && width_ == width && height_ == height) {
        if (retained_[0].is_valid() &&
            !can_keep_two_sizes(device, 0ULL, live_bytes(images_, width_, height_))) {
            release_images(device, retained_);
            retained_width_ = 0U;
            retained_height_ = 0U;
        }
        for (int index = 0; index < required_image_count; ++index) {
            if (!images_[index].is_valid() &&
                GpuWorkingImage::create(device, width, height, images_[index]) !=
                    GpuImageStatus::ok) {
                release_images(device, images_);
                width_ = 0U;
                height_ = 0U;
                return false;
            }
        }
        return true;
    }
    if (retained_[0].is_valid() && retained_width_ == width && retained_height_ == height) {
        if (can_keep_two_sizes(device, 0ULL, live_bytes(retained_, width, height))) {
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
        release_images(device, images_);
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
    release_images(device, retained_);
    retained_width_ = 0U;
    retained_height_ = 0U;

    std::uint64_t new_pool_bytes = 0ULL;
    const bool keep_current =
        texture_pool_bytes(width, height, required_image_count, new_pool_bytes) &&
        can_keep_two_sizes(device, new_pool_bytes, live_bytes(images_, width_, height_));
    if (keep_current) {
        for (int index = 0; index < size; ++index) {
            retained_[index] = std::move(images_[index]);
        }
        retained_width_ = width_;
        retained_height_ = height_;
    } else {
        release_images(device, images_);
    }

    for (int index = 0; index < required_image_count; ++index) {
        if (GpuWorkingImage::create(device, width, height, images_[index]) !=
            GpuImageStatus::ok) {
            // 못 잡으면 전부 놓습니다 — 반쯤 잡은 상태로 두면 다음 호출이 크기가
            // 맞는다고 믿고 씁니다.
            release_images(device, images_);
            release_images(device, retained_);
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
    // 장치를 모르는 자리입니다. 호출부(`release_transient_resources`)가 곧바로
    // `trim_idle` 로 제출·반환합니다.
    reset_images(images_);
    reset_images(retained_);
    width_ = 0U;
    height_ = 0U;
    retained_width_ = 0U;
    retained_height_ = 0U;
    sync_resident_bytes();
}

}  // namespace negaflow::gpu
