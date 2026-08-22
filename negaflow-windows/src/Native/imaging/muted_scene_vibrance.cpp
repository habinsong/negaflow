#include "negaflow/imaging/muted_scene_vibrance.h"
#include "negaflow/imaging/mipmap_downsampler.h"
#include "negaflow/imaging/kernel_accelerator.h"

#include "bilinear_rgb_sampler.h"
#include "vibrance_math.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>

namespace negaflow::imaging {
namespace {

// macOS 의 [vib] 줄과 같은 이름·같은 자릿수로 씁니다(NEGA_DEBUG opt-in).
[[nodiscard]] bool debug_enabled() noexcept {
    std::size_t length = 0U;
    return getenv_s(&length, nullptr, 0U, "NEGA_DEBUG") == 0 && length > 0U;
}

constexpr std::uint32_t minimum_proxy_width = 32U;
constexpr std::uint32_t maximum_proxy_width = 160U;
constexpr double saturation_target = 0.24;
constexpr double maximum_vibrance = 0.5;
constexpr double vibrance_scale = 3.0;
constexpr double activation_threshold = 0.01;

[[nodiscard]] double scene_mean_saturation(
    const negaflow::core::ImageView image) noexcept {
    if (image.width <= 4U || image.height <= 4U) {
        return 0.5;
    }

    const std::uint32_t target_width = std::max(
        minimum_proxy_width,
        std::min(maximum_proxy_width, image.width));
    const double scale =
        static_cast<double>(target_width) / static_cast<double>(image.width);
    const std::uint64_t target_height = std::max<std::uint64_t>(
        1U,
        static_cast<std::uint64_t>(static_cast<double>(image.height) * scale));
    const negaflow::core::ConstImageView source{
        image.pixels,
        image.pixel_capacity,
        image.width,
        image.height,
        image.stride_pixels,
    };

    // 장면 채도도 축소본에서 잽니다. 통계·base 격자와 **같은 축소기**를 써야 합니다 —
    // 점 표본은 입자를 그대로 남겨 채도를 실제보다 높게 재고, 그러면 vibrance 가 덜 걸립니다.
    const DownsampledProxy proxy = downsample_for_statistics(
        source, target_width, static_cast<std::uint32_t>(target_height));
    if (proxy.pixels.empty()) {
        return 0.5;
    }

    double sum = 0.0;
    for (const negaflow::core::Rgba32F pixel : proxy.pixels) {
        const double maximum =
            std::max(pixel.red, std::max(pixel.green, pixel.blue));
        const double minimum =
            std::min(pixel.red, std::min(pixel.green, pixel.blue));
        sum += maximum > 1.0e-6 ? (maximum - minimum) / maximum : 0.0;
    }
    const double sample_count =
        static_cast<double>(target_width) * static_cast<double>(target_height);
    return sum / std::max(sample_count, 1.0);
}

} // namespace

VibrancePlaneSelection select_vibrance_planes(const float amount) noexcept {
    // −0.05보다 낮은 쪽은 측정상 같은 음수 slope 를 쓰고, 나머지 표 밖은 양끝 slope 를
    // 씁니다. amount 자체는 그대로 곱하므로 0 은 정확한 항등입니다.
    VibrancePlaneSelection selection{};
    while (selection.low + 2U < detail::vibrance_table_plane_count &&
           amount > detail::vibrance_table_amounts[selection.low + 1U]) {
        ++selection.low;
    }
    const float span = detail::vibrance_table_amounts[selection.low + 1U] -
                       detail::vibrance_table_amounts[selection.low];
    selection.blend = span > 0.0F
        ? std::clamp(
              (amount - detail::vibrance_table_amounts[selection.low]) / span, 0.0F, 1.0F)
        : 0.0F;
    return selection;
}

MutedSceneVibranceResult apply_muted_scene_vibrance(
    const negaflow::core::ImageView image,
    const bool monochrome) noexcept {
    MutedSceneVibranceResult result{};
    if (monochrome) {
        result.status = negaflow::core::KernelStatus::ok;
        return result;
    }

    const negaflow::core::ConstImageView input{
        image.pixels,
        image.pixel_capacity,
        image.width,
        image.height,
        image.stride_pixels,
    };
    bool gpu_finite = false;
    if (approximate_acceleration_allowed()) {
        if (const KernelAccelerator* const table = kernel_accelerator();
            table != nullptr && table->resident_finite_check != nullptr) {
            bool all_finite = false;
            if (table->resident_finite_check(
                    reinterpret_cast<const float*>(image.pixels),
                    image.width,
                    image.height,
                    static_cast<std::uint32_t>(image.stride_pixels),
                    &all_finite)) {
                if (!all_finite) {
                    result.status = negaflow::core::KernelStatus::non_finite_output;
                    return result;
                }
                gpu_finite = true;
            }
        }
    }
    if (!gpu_finite) {
        result.status = negaflow::core::validate_finite_pixels(input);
        if (result.status != negaflow::core::KernelStatus::ok) {
            return result;
        }
    } else {
        result.status = negaflow::core::KernelStatus::ok;
    }

    result.info.mean_saturation = scene_mean_saturation(image);
    result.info.amount = std::clamp(
        (saturation_target - result.info.mean_saturation) * vibrance_scale,
        0.0,
        maximum_vibrance);
    if (debug_enabled()) {
        std::fprintf(
            stderr,
            "[vib] meanSat=%.4f amount=%.3f\n",
            result.info.mean_saturation,
            result.info.amount);
    }
    if (result.info.amount <= activation_threshold) {
        result.status = negaflow::core::KernelStatus::ok;
        return result;
    }

    const float amount = static_cast<float>(result.info.amount);
    // **근사입니다**(33³ 표의 삼선형 + 곱셈). `ApproximateAcceleratorScope` 안에서만
    // 돕니다 — 내보내기·골든은 CPU 그대로입니다. 세기는 위에서 이미 정해졌습니다.
    if (approximate_acceleration_allowed() && image.stride_pixels <= 0xFFFFFFFFULL) {
        if (const KernelAccelerator* const table = kernel_accelerator();
            table != nullptr && table->muted_scene_vibrance != nullptr) {
            if (table->muted_scene_vibrance(
                    reinterpret_cast<float*>(image.pixels),
                    image.width,
                    image.height,
                    static_cast<std::uint32_t>(image.stride_pixels),
                    amount)) {
                bool all_finite = false;
                if (table->resident_finite_check != nullptr &&
                    table->resident_finite_check(
                        reinterpret_cast<const float*>(image.pixels),
                        image.width,
                        image.height,
                        static_cast<std::uint32_t>(image.stride_pixels),
                        &all_finite)) {
                    if (!all_finite) {
                        result.status = negaflow::core::KernelStatus::non_finite_output;
                        return result;
                    }
                } else {
                    result.status = negaflow::core::validate_finite_pixels(input);
                    if (result.status != negaflow::core::KernelStatus::ok) {
                        result.status = negaflow::core::KernelStatus::non_finite_output;
                        return result;
                    }
                }
                result.info.applied = true;
                result.status = negaflow::core::KernelStatus::ok;
                return result;
            }
        }
    }
    for (std::uint32_t row = 0U; row < image.height; ++row) {
        auto* const row_pixels =
            image.pixels + (static_cast<std::size_t>(row) * image.stride_pixels);
        for (std::uint32_t column = 0U; column < image.width; ++column) {
            auto& pixel = row_pixels[column];
            detail::apply_measured_vibrance_to_channels(
                pixel.red,
                pixel.green,
                pixel.blue,
                amount);
            if (!std::isfinite(pixel.red) || !std::isfinite(pixel.green) ||
                !std::isfinite(pixel.blue)) {
                result.status = negaflow::core::KernelStatus::non_finite_output;
                return result;
            }
        }
    }
    result.info.applied = true;
    result.status = negaflow::core::KernelStatus::ok;
    return result;
}

} // namespace negaflow::imaging
