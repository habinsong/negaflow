#include "negaflow/imaging/mipmap_downsampler.h"

#include "negaflow/imaging/kernel_accelerator.h"

#include <algorithm>
#include <cmath>
#include <utility>

namespace negaflow::imaging {
namespace {

struct Level final {
    std::uint32_t width{0U};
    std::uint32_t height{0U};
    std::vector<negaflow::core::Rgba32F> pixels;
};

[[nodiscard]] Level halve(
    const negaflow::core::Rgba32F* parent,
    const std::uint32_t parent_width,
    const std::uint32_t parent_height,
    const std::size_t parent_stride) {
    Level level{};
    level.width = std::max(1U, parent_width / 2U);
    level.height = std::max(1U, parent_height / 2U);
    level.pixels.resize(static_cast<std::size_t>(level.width) * level.height);
    for (std::uint32_t y = 0U; y < level.height; ++y) {
        for (std::uint32_t x = 0U; x < level.width; ++x) {
            const std::uint32_t sx = std::min(x * 2U, parent_width - 1U);
            const std::uint32_t sy = std::min(y * 2U, parent_height - 1U);
            const std::uint32_t sx1 = std::min(sx + 1U, parent_width - 1U);
            const std::uint32_t sy1 = std::min(sy + 1U, parent_height - 1U);
            const negaflow::core::Rgba32F a =
                parent[(static_cast<std::size_t>(sy) * parent_stride) + sx];
            const negaflow::core::Rgba32F b =
                parent[(static_cast<std::size_t>(sy) * parent_stride) + sx1];
            const negaflow::core::Rgba32F c =
                parent[(static_cast<std::size_t>(sy1) * parent_stride) + sx];
            const negaflow::core::Rgba32F d =
                parent[(static_cast<std::size_t>(sy1) * parent_stride) + sx1];
            level.pixels[(static_cast<std::size_t>(y) * level.width) + x] = {
                (a.red + b.red + c.red + d.red) * 0.25F,
                (a.green + b.green + c.green + d.green) * 0.25F,
                (a.blue + b.blue + c.blue + d.blue) * 0.25F,
                1.0F,
            };
        }
    }
    return level;
}

[[nodiscard]] negaflow::core::Rgba32F bilinear_at(
    const negaflow::core::Rgba32F* pixels,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::size_t stride,
    const double source_x,
    const double source_y) noexcept {
    const double fx = std::clamp(
        source_x, 0.0, static_cast<double>(width - 1U));
    const double fy = std::clamp(
        source_y, 0.0, static_cast<double>(height - 1U));
    const auto x0 = static_cast<std::uint32_t>(fx);
    const auto y0 = static_cast<std::uint32_t>(fy);
    const std::uint32_t x1 = std::min(x0 + 1U, width - 1U);
    const std::uint32_t y1 = std::min(y0 + 1U, height - 1U);
    const double tx = fx - static_cast<double>(x0);
    const double ty = fy - static_cast<double>(y0);
    const negaflow::core::Rgba32F a = pixels[(static_cast<std::size_t>(y0) * stride) + x0];
    const negaflow::core::Rgba32F b = pixels[(static_cast<std::size_t>(y0) * stride) + x1];
    const negaflow::core::Rgba32F c = pixels[(static_cast<std::size_t>(y1) * stride) + x0];
    const negaflow::core::Rgba32F d = pixels[(static_cast<std::size_t>(y1) * stride) + x1];
    const auto mix = [tx, ty](
                         const float aa, const float bb, const float cc, const float dd) {
        const double top = aa + ((bb - aa) * tx);
        const double bottom = cc + ((dd - cc) * tx);
        return static_cast<float>(top + ((bottom - top) * ty));
    };
    return {
        mix(a.red, b.red, c.red, d.red),
        mix(a.green, b.green, c.green, d.green),
        mix(a.blue, b.blue, c.blue, d.blue),
        1.0F,
    };
}

}  // namespace

DownsampledProxy downsample_for_statistics(
    const negaflow::core::ConstImageView source,
    const std::uint32_t target_width,
    const std::uint32_t target_height) {
    DownsampledProxy proxy{};
    if (source.pixels == nullptr || source.width == 0U || source.height == 0U ||
        target_width == 0U || target_height == 0U) {
        return proxy;
    }
    proxy.width = target_width;
    proxy.height = target_height;
    proxy.pixels.resize(static_cast<std::size_t>(target_width) * target_height);

    // 고를 밉맵 단계. 축소가 아니면 0 단계(원본)에서 바로 뽑는다.
    const double ratio =
        static_cast<double>(source.width) / static_cast<double>(target_width);
    const int wanted = ratio > 1.0 ? static_cast<int>(std::floor(std::log2(ratio))) : 0;

    std::vector<Level> levels;
    const negaflow::core::Rgba32F* current = source.pixels;
    std::uint32_t current_width = source.width;
    std::uint32_t current_height = source.height;
    std::size_t current_stride = source.stride_pixels;
    int applied_levels = 0;

    // 큰 축소만 GPU. 마지막 이중선형은 CPU `double` 그대로.
    // GenerateMips 는 필터가 규정되지 않아 쓰지 않습니다.
    bool used_gpu = false;
    if (wanted > 0 && approximate_acceleration_allowed()) {
        if (const KernelAccelerator* const table = kernel_accelerator();
            table != nullptr && table->mip_halve_levels != nullptr) {
            std::uint32_t last_width = source.width;
            std::uint32_t last_height = source.height;
            int steps = 0;
            for (int step = 0; step < wanted; ++step) {
                if (last_width < 2U || last_height < 2U) {
                    break;
                }
                last_width = std::max(1U, last_width / 2U);
                last_height = std::max(1U, last_height / 2U);
                ++steps;
            }
            if (steps > 0) {
                Level gpu_level{};
                gpu_level.width = last_width;
                gpu_level.height = last_height;
                gpu_level.pixels.resize(
                    static_cast<std::size_t>(last_width) * last_height);
                std::uint32_t out_width = 0U;
                std::uint32_t out_height = 0U;
                if (table->mip_halve_levels(
                        reinterpret_cast<const float*>(source.pixels),
                        source.width,
                        source.height,
                        static_cast<std::uint32_t>(source.stride_pixels),
                        steps,
                        reinterpret_cast<float*>(gpu_level.pixels.data()),
                        last_width * last_height,
                        &out_width,
                        &out_height) &&
                    out_width == last_width && out_height == last_height) {
                    levels.push_back(std::move(gpu_level));
                    current = levels.back().pixels.data();
                    current_width = levels.back().width;
                    current_height = levels.back().height;
                    current_stride = levels.back().width;
                    applied_levels = steps;
                    used_gpu = true;
                }
            }
        }
    }

    if (!used_gpu) {
        for (int step = 0; step < wanted; ++step) {
            if (current_width < 2U || current_height < 2U) {
                break;
            }
            levels.push_back(halve(current, current_width, current_height, current_stride));
            current = levels.back().pixels.data();
            current_width = levels.back().width;
            current_height = levels.back().height;
            current_stride = levels.back().width;
            ++applied_levels;
        }
    }

    // macOS 는 폭으로 구한 배율 하나를 양 축에 적용하고, 소수 높이를 버린 정수 bounds에
    // 렌더합니다. Core Image 좌표는 y-up이므로 그 소수 나머지는 y-down 버퍼의 위쪽에서
    // 잘립니다. 종전 코드는 target_height로 v를 다시 정규화해 전체 높이를 늘였고, 그 한 칸
    // 미만의 위상 오차가 얇은 필름 베이스 성분을 살려 Dmin과 장면 대비를 바꿨습니다.
    const double uniform_scale =
        static_cast<double>(target_width) / static_cast<double>(source.width);
    const double level_factor = std::ldexp(1.0, applied_levels);
    const double effective_scale = uniform_scale * level_factor;
    const double source_height_remainder =
        static_cast<double>(source.height) -
        (static_cast<double>(target_height) / uniform_scale);
    const double current_top_crop = source_height_remainder / level_factor;

    for (std::uint32_t y = 0U; y < target_height; ++y) {
        const double source_y =
            ((static_cast<double>(y) + 0.5) / effective_scale) - 0.5 +
            current_top_crop;
        for (std::uint32_t x = 0U; x < target_width; ++x) {
            const double source_x =
                ((static_cast<double>(x) + 0.5) / effective_scale) - 0.5;
            proxy.pixels[(static_cast<std::size_t>(y) * target_width) + x] =
                bilinear_at(
                    current,
                    current_width,
                    current_height,
                    current_stride,
                    source_x,
                    source_y);
        }
    }
    return proxy;
}

}  // namespace negaflow::imaging
