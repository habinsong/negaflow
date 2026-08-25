#include "grain_mend_morphology.h"

#include "negaflow/core/parallel_rows.h"
#include "negaflow/imaging/kernel_accelerator.h"

#include <algorithm>
#include <atomic>
#include <cstddef>
#include <future>
#include <limits>
#include <stdexcept>
#include <system_error>
#include <thread>
#include <vector>

namespace negaflow::imaging::grain_mend_detail {
namespace {

std::atomic_flag background_morphology_worker = ATOMIC_FLAG_INIT;

class BackgroundMorphologyLease final {
public:
    BackgroundMorphologyLease() noexcept
        : acquired_(
              std::thread::hardware_concurrency() != 1U &&
              !background_morphology_worker.test_and_set(
                  std::memory_order_acquire)) {}

    ~BackgroundMorphologyLease() {
        if (acquired_) {
            background_morphology_worker.clear(std::memory_order_release);
        }
    }

    BackgroundMorphologyLease(const BackgroundMorphologyLease&) = delete;
    BackgroundMorphologyLease& operator=(const BackgroundMorphologyLease&) = delete;

    [[nodiscard]] bool acquired() const noexcept { return acquired_; }

private:
    bool acquired_{false};
};

template <bool Minimum>
void filter_horizontal(
    const std::vector<float>& source,
    std::vector<float>& destination,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t radius) {
    std::vector<int> queue(static_cast<std::size_t>(width) + radius * 2U);
    const int length = static_cast<int>(width);
    const int window_radius = static_cast<int>(radius);
    for (std::uint32_t y = 0U; y < height; ++y) {
        const std::size_t row = static_cast<std::size_t>(y) * width;
        std::size_t head = 0U;
        std::size_t tail = 0U;
        const auto sample = [&](const int logical_x) noexcept {
            const int x = std::clamp(logical_x, 0, length - 1);
            return source[row + static_cast<std::size_t>(x)];
        };
        for (int logical_x = -window_radius;
             logical_x < length + window_radius;
             ++logical_x) {
            const float value = sample(logical_x);
            while (tail != head) {
                const float back = sample(queue[tail - 1U]);
                if constexpr (Minimum) {
                    if (back < value) {
                        break;
                    }
                } else if (back > value) {
                    break;
                }
                --tail;
            }
            queue[tail++] = logical_x;
            const int expired = logical_x - window_radius * 2;
            while (tail != head && queue[head] < expired) {
                ++head;
            }
            if (logical_x >= window_radius) {
                const std::size_t x = static_cast<std::size_t>(
                    logical_x - window_radius);
                destination[row + x] = sample(queue[head]);
            }
        }
    }
}

template <bool Minimum>
void filter_vertical(
    const std::vector<float>& source,
    std::vector<float>& destination,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t radius) {
    std::vector<int> queue(static_cast<std::size_t>(height) + radius * 2U);
    const int length = static_cast<int>(height);
    const int window_radius = static_cast<int>(radius);
    for (std::uint32_t x = 0U; x < width; ++x) {
        std::size_t head = 0U;
        std::size_t tail = 0U;
        const auto sample = [&](const int logical_y) noexcept {
            const int y = std::clamp(logical_y, 0, length - 1);
            return source[static_cast<std::size_t>(y) * width + x];
        };
        for (int logical_y = -window_radius;
             logical_y < length + window_radius;
             ++logical_y) {
            const float value = sample(logical_y);
            while (tail != head) {
                const float back = sample(queue[tail - 1U]);
                if constexpr (Minimum) {
                    if (back < value) {
                        break;
                    }
                } else if (back > value) {
                    break;
                }
                --tail;
            }
            queue[tail++] = logical_y;
            const int expired = logical_y - window_radius * 2;
            while (tail != head && queue[head] < expired) {
                ++head;
            }
            if (logical_y >= window_radius) {
                const std::size_t y = static_cast<std::size_t>(
                    logical_y - window_radius);
                destination[y * width + x] = sample(queue[head]);
            }
        }
    }
}

template <bool Minimum>
void box_filter(
    const std::vector<float>& source,
    std::vector<float>& horizontal,
    std::vector<float>& destination,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t radius) {
    filter_horizontal<Minimum>(source, horizontal, width, height, radius);
    filter_vertical<Minimum>(horizontal, destination, width, height, radius);
}

}  // namespace

std::vector<float> opening(
    const std::vector<float>& source,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t radius) {
    if (source.empty() || width == 0U || height == 0U || radius == 0U) {
        return source;
    }
    // 형태학은 창 안에서 **하나를 고르는** 일이라 부동소수 산술이 없습니다. 창과 가장자리
    // 처리가 같으면 고른 값도 같으므로 GPU 결과가 CPU 와 **비트 단위로 같습니다** —
    // 그래서 내보내기·골든 경로에서도 켭니다(`kernel_accelerator.h` 의 "정확한 것").
    if (const KernelAccelerator* const accelerator = kernel_accelerator();
        accelerator != nullptr && accelerator->opening != nullptr) {
        std::vector<float> accelerated(source.size());
        if (accelerator->opening(source.data(), accelerated.data(), width, height, radius)) {
            return accelerated;
        }
        // 실패하면 조용히 CPU 로 갑니다. GPU 가 없거나 메모리가 모자란 경우입니다.
    }
    std::vector<float> first(source.size());
    std::vector<float> result(source.size());
    box_filter<true>(source, first, result, width, height, radius);
    box_filter<false>(result, first, result, width, height, radius);
    return result;
}

std::vector<float> closing(
    const std::vector<float>& source,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t radius) {
    if (source.empty() || width == 0U || height == 0U || radius == 0U) {
        return source;
    }
    if (const KernelAccelerator* const accelerator = kernel_accelerator();
        accelerator != nullptr && accelerator->closing != nullptr) {
        std::vector<float> accelerated(source.size());
        if (accelerator->closing(source.data(), accelerated.data(), width, height, radius)) {
            return accelerated;
        }
    }
    std::vector<float> first(source.size());
    std::vector<float> result(source.size());
    box_filter<false>(source, first, result, width, height, radius);
    box_filter<true>(result, first, result, width, height, radius);
    return result;
}

std::vector<float> bipolar_top_hat(
    const std::vector<float>& source,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t radius) {
    if (source.empty() || width == 0U || height == 0U || radius == 0U) {
        return std::vector<float>(source.size(), 0.0F);
    }
    if (const KernelAccelerator* const accelerator = kernel_accelerator();
        accelerator != nullptr && accelerator->bipolar_top_hat != nullptr) {
        std::vector<float> accelerated(source.size());
        if (accelerator->bipolar_top_hat(
                source.data(), accelerated.data(), width, height, radius)) {
            return accelerated;
        }
    }
    const BackgroundMorphologyLease lease{};
    std::future<std::vector<float>> opened_future{};
    if (lease.acquired()) {
        try {
            opened_future = std::async(
                std::launch::async,
                [&source, width, height, radius] {
                    return opening(source, width, height, radius);
                });
        } catch (const std::system_error&) {
            opened_future = {};
        }
    }

    std::vector<float> opened{};
    std::vector<float> closed{};
    if (opened_future.valid()) {
        closed = closing(source, width, height, radius);
        opened = opened_future.get();
    } else {
        opened = opening(source, width, height, radius);
        closed = closing(source, width, height, radius);
    }
    std::vector<float> magnitude(source.size());
    for (std::size_t index = 0U; index < source.size(); ++index) {
        magnitude[index] = std::max(0.0F, source[index] - opened[index]);
    }

    for (std::size_t index = 0U; index < source.size(); ++index) {
        magnitude[index] = std::max(
            magnitude[index],
            std::max(0.0F, closed[index] - source[index]));
    }
    return magnitude;
}

RgbPlanes run_rgb(
    std::span<const float> red,
    std::span<const float> green,
    std::span<const float> blue,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t radius,
    const std::uint32_t halo_radius_multiplier,
    negaflow::imaging::MorphologyRgbFunction function) {
    RgbPlanes planes{};
    if (function == nullptr || red.size() != green.size() || green.size() != blue.size()) {
        return planes;
    }
    const bool duplicate_blue = green.data() == blue.data();
    planes.red.resize(red.size());
    planes.green.resize(green.size());
    if (!duplicate_blue) {
        planes.blue.resize(blue.size());
    }
    constexpr std::size_t kMaximumUntiledPixels = 16U * 1024U * 1024U;
    constexpr std::uint32_t kTileCore = 1536U;
    if (red.size() > kMaximumUntiledPixels && radius > 0U &&
        halo_radius_multiplier > 0U &&
        radius <= (std::numeric_limits<std::uint32_t>::max() / halo_radius_multiplier)) {
        const std::uint32_t halo = radius * halo_radius_multiplier;
        if (halo <= (std::numeric_limits<std::uint32_t>::max() - kTileCore) / 2U) {
            const std::uint32_t tile_width = kTileCore + 2U * halo;
            const std::uint32_t tile_height = kTileCore + 2U * halo;
            const std::uint32_t process_width = std::min(tile_width, width);
            const std::uint32_t process_height = std::min(tile_height, height);
            const std::size_t tile_count =
                static_cast<std::size_t>(process_width) * process_height;
            std::vector<float> tile_red(tile_count, 0.0F);
            std::vector<float> tile_green(tile_count, 0.0F);
            std::vector<float> tile_blue(
                duplicate_blue ? 0U : tile_count,
                0.0F);
            std::vector<float> tile_out_red(tile_count, 0.0F);
            std::vector<float> tile_out_green(tile_count, 0.0F);
            std::vector<float> tile_out_blue(
                duplicate_blue ? 0U : tile_count,
                0.0F);
            for (std::uint32_t core_y = 0U; core_y < height; core_y += kTileCore) {
                const std::uint32_t core_height = std::min(kTileCore, height - core_y);
                const std::uint32_t source_y0 = core_y > halo ? core_y - halo : 0U;
                const std::uint32_t source_y1 = std::min(height, core_y + core_height + halo);
                const std::uint32_t active_height = source_y1 - source_y0;
                const std::uint32_t place_y = source_y0 == 0U
                    ? 0U
                    : (source_y1 == height ? process_height - active_height : 0U);
                const std::uint32_t local_core_y = place_y + core_y - source_y0;
                for (std::uint32_t core_x = 0U; core_x < width; core_x += kTileCore) {
                    const std::uint32_t core_width = std::min(kTileCore, width - core_x);
                    const std::uint32_t source_x0 = core_x > halo ? core_x - halo : 0U;
                    const std::uint32_t source_x1 = std::min(width, core_x + core_width + halo);
                    const std::uint32_t active_width = source_x1 - source_x0;
                    const std::uint32_t place_x = source_x0 == 0U
                        ? 0U
                        : (source_x1 == width ? process_width - active_width : 0U);
                    const std::uint32_t local_core_x = place_x + core_x - source_x0;
                    const std::size_t active_count =
                        static_cast<std::size_t>(active_width) * active_height;
                    negaflow::core::for_each_row_block(
                        active_height,
                        static_cast<std::uint64_t>(active_count) *
                            (duplicate_blue ? 4U : 6U),
                        [&](const std::uint32_t first_row,
                            const std::uint32_t row_count) noexcept {
                            for (std::uint32_t tile_y = first_row;
                                 tile_y < first_row + row_count;
                                 ++tile_y) {
                                const std::uint32_t source_y = source_y0 + tile_y;
                                for (std::uint32_t tile_x = 0U; tile_x < active_width; ++tile_x) {
                                    const std::uint32_t source_x = source_x0 + tile_x;
                                    const std::size_t source_index =
                                        static_cast<std::size_t>(source_y) * width + source_x;
                                    const std::size_t tile_index =
                                        static_cast<std::size_t>(place_y + tile_y) * process_width +
                                        place_x + tile_x;
                                    tile_red[tile_index] = red[source_index];
                                    tile_green[tile_index] = green[source_index];
                                    if (!duplicate_blue) {
                                        tile_blue[tile_index] = blue[source_index];
                                    }
                                }
                            }
                        });
                    if (!function(
                            tile_red.data(),
                            tile_green.data(),
                            duplicate_blue ? tile_green.data() : tile_blue.data(),
                            tile_out_red.data(),
                            tile_out_green.data(),
                            duplicate_blue ? tile_out_green.data() : tile_out_blue.data(),
                            process_width,
                            process_height,
                            radius)) {
                        return {};
                    }
                    negaflow::core::for_each_row_block(
                        core_height,
                        static_cast<std::uint64_t>(core_width) * core_height *
                            (duplicate_blue ? 4U : 6U),
                        [&](const std::uint32_t first_row,
                            const std::uint32_t row_count) noexcept {
                            for (std::uint32_t local_y = first_row;
                                 local_y < first_row + row_count;
                                 ++local_y) {
                                const std::size_t source_base =
                                    static_cast<std::size_t>(local_y + local_core_y) * process_width +
                                    local_core_x;
                                const std::size_t destination_base =
                                    static_cast<std::size_t>(core_y + local_y) * width + core_x;
                                std::copy_n(
                                    tile_out_red.begin() + static_cast<std::ptrdiff_t>(source_base),
                                    core_width,
                                    planes.red.begin() + static_cast<std::ptrdiff_t>(destination_base));
                                std::copy_n(
                                    tile_out_green.begin() + static_cast<std::ptrdiff_t>(source_base),
                                    core_width,
                                    planes.green.begin() + static_cast<std::ptrdiff_t>(destination_base));
                                if (!duplicate_blue) {
                                    std::copy_n(
                                        tile_out_blue.begin() +
                                            static_cast<std::ptrdiff_t>(source_base),
                                        core_width,
                                        planes.blue.begin() +
                                            static_cast<std::ptrdiff_t>(destination_base));
                                }
                            }
                        });
                }
            }
            return planes;
        }
    }
    if (function(
            red.data(),
            green.data(),
            blue.data(),
            planes.red.data(),
            planes.green.data(),
            duplicate_blue ? planes.green.data() : planes.blue.data(),
            width,
            height,
            radius)) {
        return planes;
    }
    return {};
}

RgbPlanes opening_rgb(
    std::span<const float> red,
    std::span<const float> green,
    std::span<const float> blue,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t radius) {
    const KernelAccelerator* const accelerator = kernel_accelerator();
    return run_rgb(
        red,
        green,
        blue,
        width,
        height,
        radius,
        2U,
        accelerator != nullptr ? accelerator->opening_rgb : nullptr);
}

RgbPlanes closing_rgb(
    std::span<const float> red,
    std::span<const float> green,
    std::span<const float> blue,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t radius) {
    const KernelAccelerator* const accelerator = kernel_accelerator();
    return run_rgb(
        red,
        green,
        blue,
        width,
        height,
        radius,
        2U,
        accelerator != nullptr ? accelerator->closing_rgb : nullptr);
}

RgbPlanes close_open_rgb(
    std::span<const float> red,
    std::span<const float> green,
    std::span<const float> blue,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t radius) {
    const KernelAccelerator* const accelerator = kernel_accelerator();
    return run_rgb(
        red,
        green,
        blue,
        width,
        height,
        radius,
        4U,
        accelerator != nullptr ? accelerator->close_open_rgb : nullptr);
}

RgbPlanes bipolar_top_hat_rgb(
    std::span<const float> red,
    std::span<const float> green,
    std::span<const float> blue,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t radius) {
    const KernelAccelerator* const accelerator = kernel_accelerator();
    return run_rgb(
        red,
        green,
        blue,
        width,
        height,
        radius,
        2U,
        accelerator != nullptr ? accelerator->bipolar_top_hat_rgb : nullptr);
}

std::vector<float> box_mean(
    const std::span<const float> source,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t radius) {
    const std::size_t count =
        static_cast<std::size_t>(width) * static_cast<std::size_t>(height);
    if (width == 0U || height == 0U || source.size() != count) {
        throw std::invalid_argument{"invalid GrainMend morphology plane"};
    }
    if (radius == 0U) {
        return std::vector<float>(source.begin(), source.end());
    }

    // Only the integral rows needed by the current vertical window are kept.
    // This preserves O(N) box means without a full double-precision integral
    // image at the 1800-pixel detection ceiling.
    const std::size_t integral_width = static_cast<std::size_t>(width) + 1U;
    const std::size_t ring_rows = static_cast<std::size_t>(radius) * 2U + 2U;
    std::vector<double> ring(ring_rows * integral_width, 0.0);
    std::vector<float> result(count, 0.0F);
    std::uint32_t built_integral_row = 1U;

    const auto build_row = [&](const std::uint32_t integral_row) {
        const std::uint32_t source_y = integral_row - 1U;
        const std::size_t source_base =
            static_cast<std::size_t>(source_y) * width;
        const std::size_t current_base =
            (static_cast<std::size_t>(integral_row) % ring_rows) *
            integral_width;
        const std::size_t previous_base =
            (static_cast<std::size_t>(integral_row - 1U) % ring_rows) *
            integral_width;
        double row_sum = 0.0;
        ring[current_base] = 0.0;
        for (std::uint32_t x = 0U; x < width; ++x) {
            row_sum += static_cast<double>(source[source_base + x]);
            ring[current_base + static_cast<std::size_t>(x) + 1U] =
                ring[previous_base + static_cast<std::size_t>(x) + 1U] +
                row_sum;
        }
    };

    for (std::uint32_t y = 0U; y < height; ++y) {
        const std::uint32_t y0 = y > radius ? y - radius : 0U;
        const std::uint32_t y1 = std::min(height - 1U, y + radius);
        while (built_integral_row <= y1 + 1U) {
            build_row(built_integral_row);
            ++built_integral_row;
        }
        const std::size_t top_base =
            (static_cast<std::size_t>(y0) % ring_rows) * integral_width;
        const std::size_t bottom_base =
            (static_cast<std::size_t>(y1 + 1U) % ring_rows) * integral_width;
        for (std::uint32_t x = 0U; x < width; ++x) {
            const std::uint32_t x0 = x > radius ? x - radius : 0U;
            const std::uint32_t x1 = std::min(width - 1U, x + radius);
            const double sum =
                ring[bottom_base + static_cast<std::size_t>(x1) + 1U] -
                ring[top_base + static_cast<std::size_t>(x1) + 1U] -
                ring[bottom_base + x0] + ring[top_base + x0];
            const std::uint64_t samples =
                static_cast<std::uint64_t>(y1 - y0 + 1U) *
                static_cast<std::uint64_t>(x1 - x0 + 1U);
            result[static_cast<std::size_t>(y) * width + x] =
                static_cast<float>(sum / static_cast<double>(samples));
        }
    }
    return result;
}

}  // namespace negaflow::imaging::grain_mend_detail
