#include "grain_mend_morphology.h"

#include "negaflow/imaging/kernel_accelerator.h"

#include <algorithm>
#include <atomic>
#include <cstddef>
#include <future>
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

std::vector<float> box_mean(
    const std::vector<float>& source,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t radius) {
    const std::size_t count =
        static_cast<std::size_t>(width) * static_cast<std::size_t>(height);
    if (width == 0U || height == 0U || source.size() != count) {
        throw std::invalid_argument{"invalid GrainMend morphology plane"};
    }
    if (radius == 0U) {
        return source;
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
